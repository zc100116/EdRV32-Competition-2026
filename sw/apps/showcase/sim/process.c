/* process.c — PIX 2.1–2.5 / GEO 2.1–2.2; simulator-only L0 software model.
 * Recomputed only after parameter changes, independent of LVGL's L1 draw buffer.
 */
#include "sim_data.h"
#include "theme.h"
#include "geo_matrix.h"
#include <string.h>
#include <stdlib.h>
extern const lv_image_dsc_t sim_indoor;
extern const lv_image_dsc_t sim_street;
static uint32_t rgb[2][1280 * 720];
static uint16_t output[UI_BLOCK_MAX+1][1280 * 720];
static lv_image_dsc_t images[UI_BLOCK_MAX+1];
static uint16_t thumbnail[UI_BLOCK_MAX+1][160 * 90];
static lv_image_dsc_t thumbnails[UI_BLOCK_MAX+1];
static ui_chain_t previous;
static bool valid;
static int clamp(int x) { return x < 0 ? 0 : x > 255 ? 255 : x; }
static uint32_t expand(uint16_t p)
{
    unsigned r = p >> 11, g = (p >> 5) & 63, b = p & 31;
    return (((r << 3) | (r >> 2)) << 16) | (((g << 2) | (g >> 4)) << 8) |
           ((b << 3) | (b >> 2));
}
static uint16_t pack(uint32_t p)
{
    return (uint16_t)(((p >> 8) & 0xf800) | ((p >> 5) & 0x07e0) | ((p >> 3) & 31));
}
static int gray(uint32_t p)
{
    return (77 * (p >> 16) + 150 * ((p >> 8) & 255) + 29 * (p & 255) + 128) >> 8;
}
static void stage(uint32_t *dst, const uint32_t *src, int op)
{
    for (int y = 0; y < 720; ++y) for (int x = 0; x < 1280; ++x) {
        uint32_t p[9];
        for (int dy = -1; dy <= 1; ++dy) for (int dx = -1; dx <= 1; ++dx)
            p[(dy+1)*3+dx+1] = x+dx < 0 || x+dx >= 1280 || y+dy < 0 || y+dy >= 720 ?
                               0 : src[(y+dy)*1280+x+dx];
        uint32_t result = 0;
        for (int shift = 0; shift <= 16; shift += 8) {
            int c[9];
            for (unsigned k = 0; k < 9; ++k)
                c[k] = op >= 4 ? gray(p[k]) : (int)((p[k] >> shift) & 255);
            int value = c[4];
            if (op == 1) {
                int sum = 0;
                for (unsigned k = 0; k < 9; ++k) sum += c[k];
                value = (sum + 4) / 9;
            } else if (op == 2)
                value = (c[0]+2*c[1]+c[2]+2*c[3]+4*c[4]+2*c[5]+c[6]+2*c[7]+c[8]+8)>>4;
            else if (op == 3) value = clamp(5*c[4]-c[1]-c[3]-c[5]-c[7]);
            else if (op == 4) value = clamp(abs(-c[0]+c[2]-2*c[3]+2*c[5]-c[6]+c[8]) +
                                           abs(-c[0]-2*c[1]-c[2]+c[6]+2*c[7]+c[8]));
            else if (op >= 5) for (unsigned k = 0; k < 9; ++k)
                if ((op == 5 && c[k] < value) || (op == 6 && c[k] > value)) value = c[k];
            result |= (uint32_t)value << shift;
        }
        dst[y*1280+x] = result;
    }
}
static void geometric(uint32_t *dst,const uint32_t *src,const ui_block_t *b)
{
    int32_t m[6];
    geo_matrix(m,b->p[0],b->p[1],b->p[2],b->p[3],b->flags&1,b->flags&2,1280,720);
    for(int y=0;y<720;++y) for(int x=0;x<1280;++x) {
        int sx=(int)(((int64_t)m[0]*x+(int64_t)m[1]*y+m[2])>>16);
        int sy=(int)(((int64_t)m[3]*x+(int64_t)m[4]*y+m[5])>>16);
        dst[y*1280+x]=sx<0 || sx>=1280 || sy<0 || sy>=720 ? 0 : src[sy*1280+sx];
    }
}
static void rectangle(uint32_t *pixels,int x,int y,int w,int h)
{
    for(int py=y;py<y+h;++py) for(int px=x;px<x+w;++px)
        if(px<x+3 || px>=x+w-3 || py<y+3 || py>=y+h-3)
            pixels[py*1280+px]=0x28ddbb;
}
static void update_images(void)
{
    ui_chain_t c=ui_data_chain();
    ui_chain_t content=c; content.view=0; content.preset=0;
    if(valid && !memcmp(&previous,&content,sizeof content)) return;
    previous=content; valid=true;
    const lv_image_dsc_t *source=c.source==UI_SOURCE_PC_IMAGE ? &sim_indoor : &sim_street;
    const uint16_t *pixels=(const uint16_t *)source->data;
    for(unsigned y=0;y<720;++y) for(unsigned x=0;x<1280;++x)
        rgb[0][y*1280+x]=expand(pixels[y*source->header.h/720*source->header.w+
            x*source->header.w/1280]);
    unsigned bank=0;
    for(unsigned i=0;i<=c.count;++i) {
        if(i) {
            const ui_block_t *b=&c.block[i-1];
            if(b->type==UI_BLOCK_FILTER) {
                stage(rgb[bank^1],rgb[bank],b->p[0]); bank^=1;
            } else if(b->type==UI_BLOCK_GEO) {
                geometric(rgb[bank^1],rgb[bank],b); bank^=1;
            } else if(b->type==UI_BLOCK_OVERLAY) {
                if(b->flags&1) {
                    static const int boxes[][4]={{160,236,155,400},{451,236,147,300},
                        {613,287,207,123},{851,293,413,191}};
                    for(unsigned j=0;j<4;++j)
                        rectangle(rgb[bank],boxes[j][0],boxes[j][1],boxes[j][2],boxes[j][3]);
                }
                if(b->flags&2) {
                    for(unsigned y=0;y<54;++y) for(unsigned x=0;x<1280;++x)
                        rgb[bank][y*1280+x]=0xeaf2ff;
                    rectangle(rgb[bank],24,12,180,30);
                }
            } else if(b->type!=UI_BLOCK_DETECT) {
                uint8_t gamma[256];
                if(b->type==UI_BLOCK_GAMMA) pix_gamma_table(gamma,(unsigned)b->p[0]);
                for(unsigned j=0;j<1280*720;++j) {
                    uint32_t p=rgb[bank][j];
                    if(b->type==UI_BLOCK_GRAY) p=(uint32_t)gray(p)*0x010101;
                    if(b->type==UI_BLOCK_BINARY) p=gray(p)>=b->p[0] ? 0xffffff : 0;
                    if(b->type==UI_BLOCK_INVERT) p^=0xffffff;
                    if(b->type==UI_BLOCK_LEVEL || b->type==UI_BLOCK_GAMMA) {
                        uint32_t result=0;
                        for(unsigned shift=0;shift<=16;shift+=8) {
                            int n=(p>>shift)&255;
                            n=b->type==UI_BLOCK_LEVEL ?
                                clamp(((n-128)*b->p[1]>>8)+128+b->p[0]) : gamma[n];
                            result|=(uint32_t)n<<shift;
                        }
                        p=result;
                    }
                    rgb[bank][j]=p;
                }
            }
        }
        for(unsigned j=0;j<1280*720;++j) output[i][j]=pack(rgb[bank][j]);
        images[i]=(lv_image_dsc_t){.header={.magic=LV_IMAGE_HEADER_MAGIC,
            .cf=LV_COLOR_FORMAT_RGB565,.w=1280,.h=720,.stride=2560},
            .data_size=sizeof output[i],.data=(const uint8_t *)output[i]};
        for(unsigned y=0;y<90;++y) for(unsigned x=0;x<160;++x)
            thumbnail[i][y*160+x]=output[i][y*8*1280+x*8];
        thumbnails[i]=(lv_image_dsc_t){.header={.magic=LV_IMAGE_HEADER_MAGIC,
            .cf=LV_COLOR_FORMAT_RGB565,.w=160,.h=90,.stride=320},
            .data_size=sizeof thumbnail[i],.data=(const uint8_t *)thumbnail[i]};
    }
}
/* A fused PIX pass exposes its final DDR output, not its internal register stages. */
static unsigned output_index(unsigned block)
{
    ui_pipe_stats_t stats=ui_data_pipe_stats();
    for(unsigned i=0;i<stats.hop_count;++i) {
        ui_hop_t h=stats.hop[i];
        if((h.engine==UI_HOP_CAM_PIX || h.engine==UI_HOP_MEM_PIX) &&
            block>=h.first && block<=h.last) return h.last+1u;
    }
    return block+1;
}
const lv_image_dsc_t *sim_pipeline_image(void)
{
    update_images();
    ui_chain_t c=ui_data_chain();
    return &images[c.view==UI_VIEW_SOURCE ? 0 :
        c.view==UI_VIEW_FINAL ? c.count : output_index(c.view)];
}
const lv_image_dsc_t *ui_data_thumb(unsigned block)
{
    update_images();
    return &thumbnails[block==UI_VIEW_FINAL ? 0 : output_index(block)];
}
const lv_image_dsc_t *sim_l0_image(void)
{
    return ui_page==1 ? sim_pipeline_image() : NULL;
}
uint32_t sim_composite(const lv_image_dsc_t *l0, uint32_t foreground, unsigned x, unsigned y)
{
    uint32_t back = 0;
    if (l0) {
        const uint16_t *pixels = (const uint16_t *)l0->data;
        back = expand(pixels[(y*l0->header.h/720)*l0->header.w+x*l0->header.w/1280]);
    }
    unsigned alpha = foreground >> 24;
    uint32_t result = 0xff000000;
    for (unsigned shift = 0; shift <= 16; shift += 8) {
        unsigned value = alpha*((foreground >> shift)&255) +
                         (255-alpha)*((back >> shift)&255) + 128;
        result |= ((value + (value >> 8)) >> 8) << shift;
    }
    return result;
}
