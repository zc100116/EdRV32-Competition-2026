/* renderer.c — RND 2.6 / showcase 4.6.3; LVGL software reference drawings.
 * Calls the LVGL software draw functions directly, independent of the RND unit.
 */
#include "renderer.h"
#include "src/draw/sw/lv_draw_sw_private.h"
#include <string.h>
#include "src/misc/cache/instance/lv_image_cache.h"
const char *const ui_render_names[RENDER_TEST_COUNT]={
    "纯色填充", "透明填充", "水平渐变", "垂直渐变", "圆角填充", "圆角边框",
    "A8 字形着色", "A4 字形着色", "A2 字形着色", "A1 字形着色",
    "RGB565 贴图", "ARGB8888 透明贴图", "缩放贴图", "水平/垂直翻转",
    "重新着色", "RGB565 色键", "I8 调色板", "RGB565 拷贝", "ARGB8888 拷贝",
    "DISP 双层合成"
};
_Alignas(64) static uint8_t source[RENDER_SW*RENDER_SH*4+1024];
_Alignas(64) static uint32_t palette[256];
static lv_image_dsc_t image;
static uint16_t rgb565(unsigned r,unsigned g,unsigned b)
{ return (uint16_t)((r>>3)<<11 | (g>>2)<<5 | (b>>3)); }
lv_color_format_t ui_render_format(unsigned test)
{ return test==TEST_COPY_ARGB ? LV_COLOR_FORMAT_ARGB8888 : LV_COLOR_FORMAT_RGB565; }
unsigned ui_render_bytes(unsigned test)
{ return RENDER_W*RENDER_H*(test==TEST_COPY_ARGB ? 4u : 2u); }
const lv_image_dsc_t *ui_render_source_image(void) { return &image; }
const uint32_t *ui_render_palette(void) { return palette; }
void ui_render_source(unsigned test)
{
    lv_image_cache_drop(&image);
    unsigned bits=16;
    lv_color_format_t cf=LV_COLOR_FORMAT_RGB565;
    if(test>=TEST_A8 && test<=TEST_A1) {
        bits=8u>>(test-TEST_A8);
        /* LVGL's decoder accepts A8; expand A4/A2/A1 masks for its reference. */
        cf=LV_COLOR_FORMAT_A8;
    } else if(test==TEST_ARGB8888 || test==TEST_COPY_ARGB) {
        bits=32; cf=LV_COLOR_FORMAT_ARGB8888;
    } else if(test==TEST_I8) { bits=8; cf=LV_COLOR_FORMAT_I8; }
    memset(source,0,sizeof(source));
    for(unsigned i=0;i<256;++i) palette[i]=0xff000000u|((i*37u&255)<<16)|
        ((i*13u&255)<<8)|(i*7u&255);
    if(test==TEST_I8) memcpy(source,palette,sizeof(palette));
    for(unsigned y=0;y<RENDER_SH;++y) for(unsigned x=0;x<RENDER_SW;++x) {
        unsigned n=y*RENDER_SW+x;
        unsigned r=x*4,g=y*8,b=((x/8+y/8)&1) ? 224 : 48;
        if(test>=TEST_A8 && test<=TEST_A1) {
            unsigned levels=(1u<<bits)-1, a=x*levels/(RENDER_SW-1);
            source[n]=(uint8_t)(a*255/levels);
        } else if(cf==LV_COLOR_FORMAT_I8) source[1024+n]=(uint8_t)(x+y*3);
        else if(bits==32) ((uint32_t *)source)[n]=
            ((test==TEST_COPY_ARGB ? 255 : x*255/63)<<24)|(r<<16)|(g<<8)|b;
        else ((uint16_t *)source)[n]=(test==TEST_KEY && ((x/8+y/8)&1)) ?
            0xf81f : rgb565(r,g,b);
    }
    image=(lv_image_dsc_t){.header={.magic=LV_IMAGE_HEADER_MAGIC,.cf=cf,
        .w=RENDER_SW,.h=RENDER_SH,.stride=RENDER_SW*(cf==LV_COLOR_FORMAT_ARGB8888 ? 4 :
            cf==LV_COLOR_FORMAT_RGB565 ? 2 : 1)},
        .data_size=cf==LV_COLOR_FORMAT_I8 ? 1024+RENDER_SW*RENDER_SH :
            RENDER_SH*RENDER_SW*(cf==LV_COLOR_FORMAT_ARGB8888 ? 4 :
                cf==LV_COLOR_FORMAT_RGB565 ? 2 : 1),.data=source};
}
void ui_render_clear(unsigned test,void *pixels)
{
    unsigned bpp=test==TEST_COPY_ARGB ? 4 : 2;
    if(bpp==4) for(unsigned i=0;i<RENDER_W*RENDER_H;++i) ((uint32_t *)pixels)[i]=0xff203048;
    else for(unsigned i=0;i<RENDER_W*RENDER_H;++i) ((uint16_t *)pixels)[i]=rgb565(32,48,72);
}
void ui_render_software(unsigned test,void *pixels)
{
    unsigned bpp=test==TEST_COPY_ARGB ? 4 : 2;
    lv_draw_buf_t buffer;
    lv_draw_buf_init(&buffer,RENDER_W,RENDER_H,ui_render_format(test),RENDER_W*bpp,
        pixels,ui_render_bytes(test));
    lv_layer_t layer; lv_layer_init(&layer);
    layer.display=lv_display_get_default();
    layer.draw_buf=&buffer; layer.color_format=ui_render_format(test);
    layer.buf_area=(lv_area_t){0,0,RENDER_W-1,RENDER_H-1};
    layer._clip_area=layer.buf_area; layer.phy_clip_area=layer.buf_area;
    lv_draw_task_t task={.target_layer=&layer,.clip_area=layer.buf_area};
    lv_area_t rect={16,16,175,79};
    if(test<=TEST_ROUND) {
        lv_draw_fill_dsc_t d; lv_draw_fill_dsc_init(&d);
        d.color=lv_color_hex(0x3488e0); d.opa=test==TEST_ALPHA ? 128 : 255;
        d.radius=test==TEST_ROUND ? 20 : 0;
        if(test==TEST_GRAD_H || test==TEST_GRAD_V) {
            d.grad.dir=test==TEST_GRAD_H ? LV_GRAD_DIR_HOR : LV_GRAD_DIR_VER;
            d.grad.stops_count=2;
            d.grad.stops[0]=(lv_grad_stop_t){.color=lv_color_hex(0x204080),.opa=255,.frac=0};
            d.grad.stops[1]=(lv_grad_stop_t){.color=lv_color_hex(0xe08020),.opa=255,.frac=255};
        }
        lv_draw_sw_fill(&task,&d,&rect);
    } else if(test==TEST_BORDER) {
        lv_draw_border_dsc_t d; lv_draw_border_dsc_init(&d);
        d.color=lv_color_hex(0x3488e0); d.opa=255; d.radius=20; d.width=5;
        d.side=LV_BORDER_SIDE_FULL; lv_draw_sw_border(&task,&d,&rect);
    } else {
        lv_draw_image_dsc_t d; lv_draw_image_dsc_init(&d);
        d.src=&image; d.opa=255; d.antialias=0;
        d.recolor=lv_color_hex(0x3488e0);
        if(test>=TEST_A8 && test<=TEST_A1) d.recolor_opa=255;
        if(test==TEST_RECOLOR) { d.recolor=lv_color_hex(0xff6030); d.recolor_opa=128; }
        if(test==TEST_SCALE) d.scale_x=d.scale_y=512;
        if(test==TEST_FLIP) { d.rotation=1800; d.pivot=(lv_point_t){32,16}; }
        lv_image_colorkey_t key={.low=lv_color_hex(0xff00ff),.high=lv_color_hex(0xff00ff)};
        if(test==TEST_KEY) d.colorkey=&key;
        lv_area_t area={32,32,95,63};
        d.image_area=area;
        lv_draw_sw_image(&task,&d,&area);
    }
}
