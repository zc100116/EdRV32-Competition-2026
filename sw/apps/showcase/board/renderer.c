/* renderer.c — RND 2.1–2.6/5.4; paired hardware and LVGL software measurements.
 * One small offscreen case per application step, using the GUI RND IRQ owner.
 */
#include "board.h"
#include "../ui/renderer.h"
#include "../ui/theme.h"
#include "../platform.h"
#include "../lvgl/showcase_lvgl.h"
#include "cache.h"
#include <string.h>
#include "src/misc/cache/instance/lv_image_cache.h"
_Alignas(64) static uint8_t pixels[2][RENDER_W*RENDER_H*4];
_Alignas(64) static uint8_t packed[RENDER_SW*RENDER_SH];
_Alignas(64) static struct rnd_command command;
static lv_image_dsc_t images[2];
static ui_render_result_t results[RENDER_TEST_COUNT];
static unsigned next_test,all;
static bool running;
const ui_render_result_t *ui_data_render_results(void)
{
    for(unsigned i=0;i<RENDER_TEST_COUNT;++i) results[i].name=ui_render_names[i];
    return results;
}
bool ui_data_render_running(void) { return running; }
const lv_image_dsc_t *ui_data_render_image(unsigned side) { return &images[side]; }
void ui_data_render_start(unsigned test)
{
    if(test==TEST_LAYERS) {
        extern const struct app board_layers_app;
        board_request(&board_layers_app); return;
    }
    all=test==RENDER_TEST_COUNT; next_test=all ? 0 : test; running=true;
    if(!all) results[test].complete=false;
    app_wake_at(platform_ticks());
}
void board_render_step(void)
{
    if(!running) return;
    unsigned test=next_test;
    unsigned bytes=ui_render_bytes(test);
    unsigned bpp=lv_color_format_get_size(ui_render_format(test));
    unsigned kind=ui_render_kind(test);
    ui_render_source(test);
    ui_render_clear(test,pixels[0]); ui_render_clear(test,pixels[1]);
    uint64_t start=platform_ticks();
    ui_render_software(test,pixels[1]);
    uint64_t sw_ticks=platform_ticks()-start;
    const lv_image_dsc_t *src=ui_render_source_image();
    const uint8_t *source=src->data;
    struct rnd_common c={.dst_base=rnd_physical(pixels[0]),.dst_stride=RENDER_W*bpp,
        .dst_fmt=bpp==4 ? RND_ARGB8888 : RND_RGB565,.src_fmt=RND_RGB565,
        .clip={0,0,RENDER_W-1,RENDER_H-1},.rect={16,16,175,79},
        .color=0x3488e0,.opa=255};
    if(kind<=TEST_ROUND) {
        int32_t step[4]={0};
        if(kind==TEST_ALPHA) c.opa=128;
        if(kind==TEST_GRAD_H || kind==TEST_GRAD_V) {
            unsigned length=kind==TEST_GRAD_H ? 159 : 63;
            c.flags=RND_GRAD | (kind==TEST_GRAD_V ? RND_GRAD_V : 0);
            step[1]=(int32_t)(192u*65536/length);
            step[2]=(int32_t)(64u*65536/length);
            step[3]=-(int32_t)(96u*65536/length);
        }
        rnd_fill(&command,&c,kind==TEST_ROUND ? 20 : 0,0xff204080,step);
    } else if(kind==TEST_BORDER) rnd_border(&command,&c,20,5,15);
    else {
        c.rect=(struct rnd_rect){32,32,95,63};
        struct rnd_source s={rnd_physical(source),(uint16_t)src->header.stride,0,0};
        if(kind>=TEST_A8 && kind<=TEST_A1) {
            unsigned bits=8u>>(kind-TEST_A8);
            memset(packed,0,sizeof(packed));
            for(unsigned y=0;y<RENDER_SH;++y) for(unsigned x=0;x<RENDER_SW;++x) {
                unsigned a=source[y*RENDER_SW+x]>> (8-bits);
                packed[y*RENDER_SW*bits/8+x*bits/8]|=(uint8_t)(a<<(8-bits-x*bits%8));
            }
            c.src_fmt=(enum rnd_format)(RND_A8+kind-TEST_A8);
            s.base=rnd_physical(packed); s.stride=RENDER_SW*bits/8;
            rnd_glyph(&command,&c,&s);
        } else if(kind==TEST_COPY || kind==TEST_COPY_ARGB) {
            c.src_fmt=c.dst_fmt; rnd_copy(&command,&c,&s);
        } else {
            struct rnd_blit blit={.source=s,.scale_x=65536,.scale_y=65536};
            if(kind==TEST_ARGB8888) c.src_fmt=RND_ARGB8888;
            if(kind==TEST_I8) {
                c.src_fmt=RND_I8; blit.source.base+=1024;
                blit.palette=rnd_physical(ui_render_palette());
            }
            if(kind==TEST_SCALE) {
                c.rect.x1=159; c.rect.y1=95;
                blit.scale_x=blit.scale_y=32768;
            }
            if(kind==TEST_FLIP) c.flags=RND_HFLIP|RND_VFLIP;
            if(kind==TEST_RECOLOR) {
                c.flags=RND_RECOLOR; blit.rc_color=0xff6030; blit.rc_opa=128;
            }
            if(kind==TEST_KEY) { c.flags=RND_COLORKEY; blit.key=0xf81f; }
            rnd_blit(&command,&c,&blit);
        }
    }
    struct rnd_range sources[3]={{pixels[0],bytes}};
    unsigned source_count=1;
    if(kind>=TEST_A8 && kind<=TEST_A1)
        sources[source_count++]=(struct rnd_range){packed,sizeof(packed)};
    else if(kind>=TEST_RGB565)
        sources[source_count++]=(struct rnd_range){src->data,src->data_size};
    if(kind==TEST_I8)
        sources[source_count++]=(struct rnd_range){ui_render_palette(),1024};
    struct rnd_range target={pixels[0],bytes};
    struct rnd_batch batch={&command,1,sources,source_count,&target,1};
    start=platform_ticks(); showcase_rnd_run(&batch);
    uint64_t hw_ticks=platform_ticks()-start;
    unsigned equal=0;
    for(unsigned i=0;i<RENDER_W*RENDER_H;++i)
        if(!memcmp(pixels[0]+i*bpp,pixels[1]+i*bpp,bpp)) ++equal;
    results[test]=(ui_render_result_t){ui_render_names[test],
        (unsigned)(hw_ticks*1000000/platform_clock_hz()),
        (unsigned)(sw_ticks*1000000/platform_clock_hz()),equal,RENDER_W*RENDER_H,true};
    for(unsigned i=0;i<2;++i) {
        lv_image_cache_drop(&images[i]);
        images[i]=(lv_image_dsc_t){.header={.magic=LV_IMAGE_HEADER_MAGIC,
            .cf=ui_render_format(test),.w=RENDER_W,.h=RENDER_H,.stride=RENDER_W*bpp},
            .data_size=bytes,.data=pixels[i]};
    }
    if(all && ++next_test<TEST_LAYERS) app_wake_at(platform_ticks());
    else { running=false; ui_open(4); }
}
