/* page_workshop.c — T-WS-GAME §§3,5–7; camera backed creative workshop.
 * GUI caches fixed cells and draws small dynamic objects from 60 Hz snapshots.
 */
#include "widgets.h"
#include "workshop.h"
#include "game_loop.h"
#include "grab.h"
#include "../platform.h"
#include <port.h>
#include "src/draw/lv_draw_private.h"
#include <stdio.h>
#include <string.h>
LV_IMAGE_DECLARE(ws_block_grass);
LV_IMAGE_DECLARE(ws_block_dirt);
LV_IMAGE_DECLARE(ws_block_stone);
LV_IMAGE_DECLARE(ws_block_gravel);
LV_IMAGE_DECLARE(ws_block_sand);
LV_IMAGE_DECLARE(ws_block_plank);
LV_IMAGE_DECLARE(ws_block_log);
LV_IMAGE_DECLARE(ws_block_stonebrick);
LV_IMAGE_DECLARE(ws_block_brick);
LV_IMAGE_DECLARE(ws_block_metal);
LV_IMAGE_DECLARE(ws_block_ice);
LV_IMAGE_DECLARE(ws_block_glass);
LV_IMAGE_DECLARE(ws_block_leaves);
LV_IMAGE_DECLARE(ws_block_lamp);
LV_IMAGE_DECLARE(ws_block_lamp_on);
LV_IMAGE_DECLARE(ws_block_window);
LV_IMAGE_DECLARE(ws_block_window_on);
LV_IMAGE_DECLARE(ws_door);
LV_IMAGE_DECLARE(ws_beam_h);
LV_IMAGE_DECLARE(ws_beam_v);
LV_IMAGE_DECLARE(ws_pillar_h);
LV_IMAGE_DECLARE(ws_pillar_v);
LV_IMAGE_DECLARE(ws_slope_wood_bl);
LV_IMAGE_DECLARE(ws_slope_wood_br);
LV_IMAGE_DECLARE(ws_slope_wood_tr);
LV_IMAGE_DECLARE(ws_slope_wood_tl);
LV_IMAGE_DECLARE(ws_slope_brick_bl);
LV_IMAGE_DECLARE(ws_slope_brick_br);
LV_IMAGE_DECLARE(ws_slope_brick_tr);
LV_IMAGE_DECLARE(ws_slope_brick_tl);
LV_IMAGE_DECLARE(ws_crack_1);
LV_IMAGE_DECLARE(ws_crack_2);
LV_IMAGE_DECLARE(ws_crack_3);
LV_IMAGE_DECLARE(ws_crack_4);
LV_IMAGE_DECLARE(ws_crack_5);
LV_IMAGE_DECLARE(ws_crack_6);
LV_IMAGE_DECLARE(ws_crack_7);
LV_IMAGE_DECLARE(ws_crack_8);
LV_IMAGE_DECLARE(ws_bunny_walk_1_r);
LV_IMAGE_DECLARE(ws_bunny_walk_1_l);
LV_IMAGE_DECLARE(ws_bunny_walk_2_r);
LV_IMAGE_DECLARE(ws_bunny_walk_2_l);
LV_IMAGE_DECLARE(ws_bunny_walk_3_r);
LV_IMAGE_DECLARE(ws_bunny_walk_3_l);
LV_IMAGE_DECLARE(ws_bunny_walk_4_r);
LV_IMAGE_DECLARE(ws_bunny_walk_4_l);
LV_IMAGE_DECLARE(ws_bunny_walk_5_r);
LV_IMAGE_DECLARE(ws_bunny_walk_5_l);
LV_IMAGE_DECLARE(ws_bunny_walk_6_r);
LV_IMAGE_DECLARE(ws_bunny_walk_6_l);
LV_IMAGE_DECLARE(ws_bunny_walk_7_r);
LV_IMAGE_DECLARE(ws_bunny_walk_7_l);
LV_IMAGE_DECLARE(ws_bunny_walk_8_r);
LV_IMAGE_DECLARE(ws_bunny_walk_8_l);
LV_IMAGE_DECLARE(ws_bunny_idle_1_r);
LV_IMAGE_DECLARE(ws_bunny_idle_1_l);
LV_IMAGE_DECLARE(ws_bunny_idle_2_r);
LV_IMAGE_DECLARE(ws_bunny_idle_2_l);
LV_IMAGE_DECLARE(ws_bunny_lift_1_r);
LV_IMAGE_DECLARE(ws_bunny_lift_1_l);
LV_IMAGE_DECLARE(ws_bunny_lift_2_r);
LV_IMAGE_DECLARE(ws_bunny_lift_2_l);
LV_IMAGE_DECLARE(ws_bunny_stun_1_r);
LV_IMAGE_DECLARE(ws_bunny_stun_1_l);
LV_IMAGE_DECLARE(ws_bunny_stun_2_r);
LV_IMAGE_DECLARE(ws_bunny_stun_2_l);
LV_IMAGE_DECLARE(ws_duck_walk_1_r);
LV_IMAGE_DECLARE(ws_duck_walk_1_l);
LV_IMAGE_DECLARE(ws_duck_walk_2_r);
LV_IMAGE_DECLARE(ws_duck_walk_2_l);
LV_IMAGE_DECLARE(ws_duck_walk_3_r);
LV_IMAGE_DECLARE(ws_duck_walk_3_l);
LV_IMAGE_DECLARE(ws_duck_walk_4_r);
LV_IMAGE_DECLARE(ws_duck_walk_4_l);
LV_IMAGE_DECLARE(ws_duck_walk_5_r);
LV_IMAGE_DECLARE(ws_duck_walk_5_l);
LV_IMAGE_DECLARE(ws_duck_walk_6_r);
LV_IMAGE_DECLARE(ws_duck_walk_6_l);
LV_IMAGE_DECLARE(ws_duck_walk_7_r);
LV_IMAGE_DECLARE(ws_duck_walk_7_l);
LV_IMAGE_DECLARE(ws_duck_walk_8_r);
LV_IMAGE_DECLARE(ws_duck_walk_8_l);
LV_IMAGE_DECLARE(ws_duck_idle_1_r);
LV_IMAGE_DECLARE(ws_duck_idle_1_l);
LV_IMAGE_DECLARE(ws_duck_idle_2_r);
LV_IMAGE_DECLARE(ws_duck_idle_2_l);
LV_IMAGE_DECLARE(ws_duck_lift_1_r);
LV_IMAGE_DECLARE(ws_duck_lift_1_l);
LV_IMAGE_DECLARE(ws_duck_lift_2_r);
LV_IMAGE_DECLARE(ws_duck_lift_2_l);
LV_IMAGE_DECLARE(ws_duck_stun_1_r);
LV_IMAGE_DECLARE(ws_duck_stun_1_l);
LV_IMAGE_DECLARE(ws_duck_stun_2_r);
LV_IMAGE_DECLARE(ws_duck_stun_2_l);
LV_IMAGE_DECLARE(ws_cursor_hand_open);
LV_IMAGE_DECLARE(ws_cursor_hand_grab);
LV_IMAGE_DECLARE(ws_cursor_pick);
LV_IMAGE_DECLARE(ws_cursor_pick_swing);
LV_IMAGE_DECLARE(ws_tool_hand);
LV_IMAGE_DECLARE(ws_tool_pick);
LV_IMAGE_DECLARE(ws_sky_day);
LV_IMAGE_DECLARE(ws_sky_dusk);
LV_IMAGE_DECLARE(ws_sky_night);
LV_IMAGE_DECLARE(ws_glow);
LV_IMAGE_DECLARE(ws_dust_1);
LV_IMAGE_DECLARE(ws_dust_2);
LV_IMAGE_DECLARE(ws_dust_3);
LV_IMAGE_DECLARE(ws_shard_1);
LV_IMAGE_DECLARE(ws_shard_2);
LV_IMAGE_DECLARE(ws_shard_3);
static const lv_image_dsc_t *const blocks[WS_ITEMS]={
    &ws_tool_hand,&ws_tool_pick,&ws_block_grass,&ws_block_dirt,&ws_block_stone,
    &ws_block_gravel,&ws_block_sand,&ws_block_plank,&ws_block_log,&ws_block_stonebrick,
    &ws_block_brick,&ws_block_metal,&ws_block_ice,&ws_block_glass,&ws_block_leaves,
    &ws_block_lamp,&ws_block_window,&ws_door,&ws_beam_h,&ws_pillar_h,
    &ws_slope_wood_bl,&ws_slope_brick_bl};
static const lv_image_dsc_t *const slopes[2][4]={
    {&ws_slope_wood_bl,&ws_slope_wood_br,&ws_slope_wood_tr,&ws_slope_wood_tl},
    {&ws_slope_brick_bl,&ws_slope_brick_br,&ws_slope_brick_tr,&ws_slope_brick_tl}};
static const lv_image_dsc_t *const cracks[]={
    &ws_crack_1,&ws_crack_2,&ws_crack_3,&ws_crack_4,
    &ws_crack_5,&ws_crack_6,&ws_crack_7,&ws_crack_8};
static const lv_image_dsc_t *const skies[]={&ws_sky_day,&ws_sky_dusk,&ws_sky_night};
static const lv_image_dsc_t *const animal_frames[2][4][2][8]={
    {
        {
            {&ws_bunny_idle_1_r,&ws_bunny_idle_2_r},
            {&ws_bunny_idle_1_l,&ws_bunny_idle_2_l},
        },
        {
            {&ws_bunny_walk_1_r,&ws_bunny_walk_2_r,&ws_bunny_walk_3_r,&ws_bunny_walk_4_r,
             &ws_bunny_walk_5_r,&ws_bunny_walk_6_r,&ws_bunny_walk_7_r,&ws_bunny_walk_8_r},
            {&ws_bunny_walk_1_l,&ws_bunny_walk_2_l,&ws_bunny_walk_3_l,&ws_bunny_walk_4_l,
             &ws_bunny_walk_5_l,&ws_bunny_walk_6_l,&ws_bunny_walk_7_l,&ws_bunny_walk_8_l},
        },
        {
            {&ws_bunny_lift_1_r,&ws_bunny_lift_2_r},
            {&ws_bunny_lift_1_l,&ws_bunny_lift_2_l},
        },
        {
            {&ws_bunny_stun_1_r,&ws_bunny_stun_2_r},
            {&ws_bunny_stun_1_l,&ws_bunny_stun_2_l},
        },
    },
    {
        {
            {&ws_duck_idle_1_r,&ws_duck_idle_2_r},
            {&ws_duck_idle_1_l,&ws_duck_idle_2_l},
        },
        {
            {&ws_duck_walk_1_r,&ws_duck_walk_2_r,&ws_duck_walk_3_r,&ws_duck_walk_4_r,
             &ws_duck_walk_5_r,&ws_duck_walk_6_r,&ws_duck_walk_7_r,&ws_duck_walk_8_r},
            {&ws_duck_walk_1_l,&ws_duck_walk_2_l,&ws_duck_walk_3_l,&ws_duck_walk_4_l,
             &ws_duck_walk_5_l,&ws_duck_walk_6_l,&ws_duck_walk_7_l,&ws_duck_walk_8_l},
        },
        {
            {&ws_duck_lift_1_r,&ws_duck_lift_2_r},
            {&ws_duck_lift_1_l,&ws_duck_lift_2_l},
        },
        {
            {&ws_duck_stun_1_r,&ws_duck_stun_2_r},
            {&ws_duck_stun_1_l,&ws_duck_stun_2_l},
        },
    },
};
static workshop_state state;
static workshop_snapshot snapshots[3],shown,next;
static lv_obj_t *frame,*overlay,*cursor_layer,*menu,*inventory;
static lv_obj_t *hud,*item_label,*item_icon,*hold_arc;
static lv_obj_t *cells[25],*cards[3];
static lv_timer_t *timer;
static unsigned command, max_us;
static bool painted;
static uint32_t tiles[WS_ROWS+2][WS_COLS+2][48*48];
static lv_image_dsc_t tile_images[WS_ROWS+2][WS_COLS+2];
static bool tile_used[WS_ROWS+2][WS_COLS+2];
static uint32_t minimaps[3][160*88];
static lv_image_dsc_t thumbnails[3];
static uint32_t swing_pixels[64*64];
static lv_image_dsc_t swing_image;
static const lv_image_dsc_t *block_image(unsigned item,unsigned orientation,unsigned sky)
{
    if (item==WS_BEAM) return orientation ? &ws_beam_v : &ws_beam_h;
    if (item==WS_PILLAR) return orientation ? &ws_pillar_v : &ws_pillar_h;
    if (item==WS_WOOD_SLOPE || item==WS_BRICK_SLOPE)
        return slopes[item==WS_BRICK_SLOPE][orientation];
    if (sky && item==WS_LAMP) return &ws_block_lamp_on;
    if (sky && item==WS_WINDOW) return &ws_block_window_on;
    return blocks[item];
}
static void picture(lv_layer_t *layer,const lv_image_dsc_t *image,int x,int y,
                    unsigned width,unsigned height,lv_opa_t opacity)
{
    lv_draw_image_dsc_t d;
    lv_draw_image_dsc_init(&d);
    d.src=image;
    d.opa=opacity;
    d.scale_x=width*256/image->header.w;
    d.scale_y=height*256/image->header.h;
    d.pivot=(lv_point_t){0,0};
    lv_area_t area={x,y,x+(int)image->header.w-1,y+(int)image->header.h-1};
    lv_draw_image(layer,&d,&area);
}
static void rect(lv_layer_t *layer,ws_rect r,uint32_t color,lv_opa_t opacity)
{
    lv_draw_rect_dsc_t d;
    lv_draw_rect_dsc_init(&d);
    d.bg_color=lv_color_hex(color);
    d.bg_opa=opacity;
    lv_area_t a={r.x,r.y,r.x+r.w-1,r.y+r.h-1};
    lv_draw_rect(layer,&d,&a);
}
/* Reciprocal alpha normalizes straight-alpha edges with MULHU, never DIVU.
 * Opaque wall/halo blending uses two packed RGB multiplications per source.
 */
static const uint32_t alpha_reciprocal[256]={
    0,16843009,8421504,5614336,4210752,3368601,2807168,2406144,
    2105376,1871445,1684300,1531182,1403584,1295616,1203072,1122867,
    1052688,990765,935722,886474,842150,802048,765591,732304,
    701792,673720,647808,623815,601536,580793,561433,543322,
    526344,510394,495382,481228,467861,455216,443237,431872,
    421075,410805,401024,391697,382795,374289,366152,358361,
    350896,343734,336860,330255,323904,317792,311907,306236,
    300768,295491,290396,285474,280716,276114,271661,267349,
    263172,259123,255197,251388,247691,244101,240614,237225,
    233930,230726,227608,224573,221618,218740,215936,213202,
    210537,207938,205402,202927,200512,198153,195848,193597,
    191397,189247,187144,185088,183076,181107,179180,177294,
    175448,173639,171867,170131,168430,166762,165127,163524,
    161952,160409,158896,157411,155953,154523,153118,151738,
    150384,149053,147745,146460,145198,143957,142737,141537,
    140358,139198,138057,136935,135830,134744,133674,132622,
    131586,130565,129561,128572,127598,126639,125694,124763,
    123845,122941,122050,121172,120307,119453,118612,117783,
    116965,116158,115363,114578,113804,113040,112286,111543,
    110809,110085,109370,108664,107968,107280,106601,105930,
    105268,104614,103969,103331,102701,102078,101463,100856,
    100256,99662,99076,98497,97924,97358,96798,96245,
    95698,95158,94623,94095,93572,93055,92544,92038,
    91538,91043,90553,90069,89590,89116,88647,88183,
    87724,87269,86819,86374,85933,85497,85065,84638,
    84215,83796,83381,82970,82563,82161,81762,81367,
    80976,80588,80204,79824,79448,79075,78705,78339,
    77976,77617,77261,76908,76559,76212,75869,75529,
    75192,74857,74526,74198,73872,73550,73230,72913,
    72599,72287,71978,71672,71368,71067,70768,70472,
    70179,69888,69599,69312,69028,68746,68467,68190,
    67915,67642,67372,67103,66837,66573,66311,66051,
};
static const uint16_t falloff[256]={
    65025,64009,63001,62500,61504,61009,60025,59049,
    58564,57600,57121,56169,55696,54756,53824,53361,
    52441,51984,51076,50625,49729,48841,48400,47524,
    47089,46225,45796,44944,44100,43681,42849,42436,
    41616,41209,40401,39601,39204,38416,38025,37249,
    36864,36100,35344,34969,34225,33856,33124,32761,
    32041,31329,30976,30276,29929,29241,28900,28224,
    27556,27225,26569,26244,25600,24964,24649,24025,
    23716,23104,22801,22201,21609,21316,20736,20449,
    19881,19600,19044,18496,18225,17689,17424,16900,
    16641,16129,15625,15376,14884,14641,14161,13924,
    13456,12996,12769,12321,12100,11664,11449,11025,
    10609,10404,10000,9801,9409,9216,8836,8464,
    8281,7921,7744,7396,7225,6889,6561,6400,
    6084,5929,5625,5329,5184,4900,4761,4489,
    4356,4096,3844,3721,3481,3364,3136,3025,
    2809,2601,2500,2304,2209,2025,1936,1764,
    1600,1521,1369,1296,1156,1089,961,841,
    784,676,625,529,484,400,324,289,
    225,196,144,121,81,49,36,16,
    9,1,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,
};
static unsigned divide255(unsigned value)
{
    return (value+1+(value>>8))>>8;
}
static uint32_t blend(uint32_t dest,uint32_t src)
{
    unsigned alpha=src>>24,back=dest>>24;
    if (!alpha) return dest;
    if (alpha==255 || !back) return src;
    if (back==255) {
        unsigned amount=alpha+(alpha>>7),inverse=256-amount;
        uint32_t rb=(((src&0xff00ff)*amount+(dest&0xff00ff)*inverse)>>8)&0xff00ff;
        uint32_t g=(((src&0x00ff00)*amount+(dest&0x00ff00)*inverse)>>8)&0x00ff00;
        return 0xff000000|rb|g;
    }
    unsigned background=back*(255-alpha);
    unsigned out=alpha+divide255(background);
    uint32_t value=out<<24;
    for (unsigned shift=0;shift<24;shift+=8) {
        unsigned numerator=((src>>shift)&255)*alpha*255+
                           ((dest>>shift)&255)*background;
        unsigned c=(unsigned)(((uint64_t)numerator*alpha_reciprocal[out])>>32);
        value|=c<<shift;
    }
    return value;
}
enum { LIGHT_RADIUS=144, LIGHT_RADIUS2=144*144, CACHE_BUDGET=6, MAP_COLS=133, MAP_ROWS=79, FRAME_CYCLES=380000 };
static struct { int x,y; } lights[WS_BLOCKS];
static unsigned light_count;
/* 2 = local edit due this frame; 1 = queued lighting/sky refresh. */
static uint8_t changed_tiles[WS_ROWS+2][WS_COLS+2];
static uint32_t weighted_falloff[256];
static uint8_t coarse_light[MAP_ROWS][MAP_COLS];
static unsigned map_row=MAP_ROWS;
static uint8_t lighting[48*48];
static bool lighting_ready;
static bool light_item(unsigned item) { return item==WS_LAMP || item==WS_WINDOW; }
static unsigned ambient(unsigned sky)
{
    static const unsigned values[]={255,179,102};
    return values[sky];
}
static void light_row(unsigned row)
{
    unsigned base=ambient(next.sky);
    int y=WS_Y-48+(int)row*8;
    for (unsigned col=0;col<MAP_COLS;++col) {
        int x=WS_X-48+(int)col*8;
        unsigned value=base;
        for (unsigned i=0;i<light_count;++i) {
            int dx=x-lights[i].x,dy=y-lights[i].y;
            unsigned distance=(unsigned)(dx*dx+dy*dy);
            if (distance>=LIGHT_RADIUS2) continue;
            unsigned index=distance>>7;
            unsigned weighted=weighted_falloff[index]-
                (((weighted_falloff[index]-weighted_falloff[index+1])*
                  (distance&127)+64)>>7);
            unsigned restored=base+(unsigned)(((uint64_t)weighted*
                                               alpha_reciprocal[255])>>32);
            if (restored>value) value=restored;
        }
        coarse_light[row][col]=(uint8_t)value;
    }
}
static void light_tile(int col,int row)
{
    int mx=col*6,my=row*6;
    for (int y=0;y<48;++y) {
        unsigned fraction=(unsigned)y&7;
        const uint8_t *top=&coarse_light[my+y/8][mx];
        const uint8_t *bottom=top+MAP_COLS;
        for (int x=0;x<48;x+=8) {
            int a=top[x/8]*(int)(8-fraction)+bottom[x/8]*(int)fraction;
            int b=top[x/8+1]*(int)(8-fraction)+bottom[x/8+1]*(int)fraction;
            int value=a*8,step=b-a;
            for (int j=0;j<8;++j) {
                lighting[y*48+x+j]=(uint8_t)((value+32)>>6);
                value+=step;
            }
        }
    }
}
static uint32_t shade(uint32_t pixel,unsigned amount)
{
    unsigned gain=amount+(amount>>7);
    uint32_t rb=(((pixel&0xff00ff)*gain)>>8)&0xff00ff;
    uint32_t g=(((pixel&0x00ff00)*gain)>>8)&0x00ff00;
    return (pixel&0xff000000)|rb|g;
}
static void tile_blit(int col,int row,const lv_image_dsc_t *image,int x,int y,
                      bool illuminate,bool source)
{
    int tx=WS_X+(col-1)*48,ty=WS_Y+(row-1)*48;
    int left=x>tx ? x : tx,top=y>ty ? y : ty;
    int right=x+(int)image->header.w,bottom=y+(int)image->header.h;
    if (right>tx+48) right=tx+48;
    if (bottom>ty+48) bottom=ty+48;
    if (left>=right || top>=bottom) return;
    if (illuminate && !source && !lighting_ready) {
        light_tile(col,row);
        lighting_ready=true;
    }
    const uint32_t *src=(const uint32_t *)image->data;
    for (int yy=top;yy<bottom;++yy)
        for (int xx=left;xx<right;++xx) {
            uint32_t pixel=src[(yy-y)*image->header.w+xx-x];
            if (!(pixel>>24)) continue;
            if (illuminate && !source) pixel=shade(pixel,lighting[(yy-ty)*48+xx-tx]);
            uint32_t *p=&tiles[row][col][(yy-ty)*48+xx-tx];
            *p=blend(*p,pixel);
            tile_used[row][col]=true;
        }
}
static bool fixed(const workshop_snapshot *s,int i)
{
    return s->blocks[i].used && !s->blocks[i].group && i!=s->held;
}
static void cache_region(ws_rect r,unsigned priority)
{
    const int origin_x=WS_X-48,origin_y=WS_Y-48;
    int left=r.x>origin_x ? r.x : origin_x;
    int top=r.y>origin_y ? r.y : origin_y;
    int right=r.x+r.w,bottom=r.y+r.h;
    if (right>WS_X+(WS_COLS+1)*48) right=WS_X+(WS_COLS+1)*48;
    if (bottom>WS_Y+(WS_ROWS+1)*48) bottom=WS_Y+(WS_ROWS+1)*48;
    if (left>=right || top>=bottom) return;
    for (int y=(top-origin_y)/48;y<=(bottom-1-origin_y)/48;++y)
        for (int x=(left-origin_x)/48;x<=(right-1-origin_x)/48;++x)
            if (changed_tiles[y][x]<priority) changed_tiles[y][x]=(uint8_t)priority;
}
static void cache_update(void)
{
    bool full=shown.menu!=next.menu || shown.scene!=next.scene || shown.sky!=next.sky;
    unsigned gain=255-ambient(next.sky);
    for (unsigned i=0;i<256;++i) weighted_falloff[i]=gain*falloff[i];
    unsigned previous_count=light_count;
    bool light_changed=shown.sky!=next.sky;
    light_count=0;
    if (next.sky) for (int i=0;i<WS_BLOCKS;++i)
        if (next.blocks[i].used && light_item(next.blocks[i].item)) {
            ws_rect r=workshop_block_rect(&next,i);
            if (lights[light_count].x!=r.x+24 || lights[light_count].y!=r.y+24)
                light_changed=true;
            lights[light_count].x=r.x+24;
            lights[light_count++].y=r.y+24;
        }
    if (light_changed || previous_count!=light_count) map_row=0;
    if (full) {
        for (int y=0;y<WS_ROWS+2;++y) for (int x=0;x<WS_COLS+2;++x)
            if (tile_used[y][x]) changed_tiles[y][x]=1;
        for (int i=0;i<WS_BLOCKS;++i)
            if (fixed(&next,i)) cache_region(workshop_block_rect(&next,i),1);
        for (unsigned i=0;i<light_count;++i)
            cache_region((ws_rect){lights[i].x-72,lights[i].y-72,144,144},1);
    } else for (int i=0;i<WS_BLOCKS;++i) {
        bool old=fixed(&shown,i),now=fixed(&next,i);
        ws_rect a=workshop_block_rect(&shown,i),b=workshop_block_rect(&next,i);
        if (old==now && !memcmp(&shown.blocks[i],&next.blocks[i],sizeof(ws_block)) &&
            !memcmp(&a,&b,sizeof a)) continue;
        if (old) cache_region(a,2);
        if (now) cache_region(b,2);
        if (!next.sky) continue;
        if (shown.blocks[i].used && light_item(shown.blocks[i].item))
            cache_region((ws_rect){a.x-144,a.y-144,a.w+288,a.h+288},1);
        if (next.blocks[i].used && light_item(next.blocks[i].item))
            cache_region((ws_rect){b.x-144,b.y-144,b.w+288,b.h+288},1);
    }
}
unsigned ui_workshop_pending(void)
{
    unsigned count=MAP_ROWS-map_row;
    for (int y=0;y<WS_ROWS+2;++y) for (int x=0;x<WS_COLS+2;++x)
        if (changed_tiles[y][x]) ++count;
    return count;
}
static void cache_process(void)
{
    unsigned count=0,cycles=0;
    unsigned row_cycles=MAP_COLS*(12+30*light_count);
    while (map_row<MAP_ROWS && cycles+row_cycles<=FRAME_CYCLES) {
        light_row(map_row++);
        cycles+=row_cycles;
    }
    for (unsigned priority=2;priority>0;--priority)
    for (int row=0;row<WS_ROWS+2;++row) for (int col=0;col<WS_COLS+2;++col) {
        if (changed_tiles[row][col]!=priority) continue;
        if (priority==1 && map_row<MAP_ROWS) continue;
        int tx=WS_X+(col-1)*48,ty=WS_Y+(row-1)*48;
        unsigned estimated=51000;
        for (unsigned i=0;i<light_count;++i) {
            int left=tx>lights[i].x-72 ? tx : lights[i].x-72;
            int top=ty>lights[i].y-72 ? ty : lights[i].y-72;
            int right=tx+48<lights[i].x+72 ? tx+48 : lights[i].x+72;
            int bottom=ty+48<lights[i].y+72 ? ty+48 : lights[i].y+72;
            if (left<right && top<bottom) estimated+=(right-left)*(bottom-top)*20;
        }
        if (priority==1 && cycles+estimated>FRAME_CYCLES) continue;
        cycles+=estimated;
        changed_tiles[row][col]=map_row<MAP_ROWS ? 1 : 0;
        memset(tiles[row][col],0,sizeof tiles[row][col]);
        tile_used[row][col]=false;
        lighting_ready=false;
        for (int i=0;i<WS_BLOCKS;++i) {
            if (!fixed(&next,i)) continue;
            ws_rect r=workshop_block_rect(&next,i);
            unsigned item=next.blocks[i].item;
            tile_blit(col,row,block_image(item,next.blocks[i].orientation,next.sky),
                      r.x,r.y,next.sky!=WS_DAY,light_item(item));
        }
        for (unsigned i=0;i<light_count;++i)
            tile_blit(col,row,&ws_glow,lights[i].x-72,lights[i].y-72,false,false);
        lv_area_t area={WS_X+(col-1)*48,WS_Y+(row-1)*48,
                        WS_X+col*48-1,WS_Y+row*48-1};
        lv_obj_invalidate_area(frame,&area);
        lv_obj_invalidate_area(overlay,&area);
        if (++count==CACHE_BUDGET) return;
    }
}
static void shaded_picture(lv_layer_t *layer,const lv_image_dsc_t *image,ws_rect r,
                           bool source,lv_opa_t opacity)
{
    lv_draw_image_dsc_t d;
    lv_draw_image_dsc_init(&d);
    d.src=image;
    d.opa=opacity;
    d.scale_x=r.w*256/image->header.w;
    d.scale_y=r.h*256/image->header.h;
    d.pivot=(lv_point_t){0,0};
    d.recolor=lv_color_black();
    d.recolor_opa=(lv_opa_t)(source ? 0 : 255-ambient(shown.sky));
    lv_area_t area={r.x,r.y,r.x+(int)image->header.w-1,r.y+(int)image->header.h-1};
    lv_draw_image(layer,&d,&area);
}
static void draw_world(lv_event_t *e)
{
    painted=true;
    if (shown.menu) return;
    lv_layer_t *layer=lv_event_get_layer(e);
    for (int y=0;y<WS_ROWS+2;++y) for (int x=0;x<WS_COLS+2;++x)
        if (tile_used[y][x])
            picture(layer,&tile_images[y][x],WS_X+(x-1)*48,WS_Y+(y-1)*48,48,48,255);
}
static void draw_dynamic(lv_event_t *e)
{
    lv_layer_t *layer=lv_event_get_layer(e);
    if (!shown.menu) {
        for (int i=0;i<WS_BLOCKS;++i) {
            const ws_block *b=&shown.blocks[i];
            if (!b->used || (!b->group && i!=shown.held) ||
                (i==shown.held && !shown.returning)) continue;
            ws_rect r=workshop_block_rect(&shown,i);
            shaded_picture(layer,block_image(b->item,b->orientation,shown.sky),r,
                           light_item(b->item),255);
        }
        for (unsigned i=0;i<shown.animal_count;++i) {
            const ws_animal *a=&shown.animals[i];
            unsigned action=a->action==WS_LIFT ? 2 : a->action==WS_STUN ? 3 :
                (a->action==WS_WALK || a->action==WS_RUN || a->action==WS_JUMP) ? 1 : 0;
            const lv_image_dsc_t *art=animal_frames[a->species][action][a->direction<0]
                                                  [a->frame%(action==1 ? 8 : 2)];
            shaded_picture(layer,art,(ws_rect){a->x/2-(int)art->header.w/2,a->y/2-52,
                           (int)art->header.w,(int)art->header.h},false,255);
        }
        for (unsigned i=0;i<WS_PARTICLES;++i) {
            const ws_particle *p=&shown.particles[i];
            if (!p->life) continue;
            if (!p->kind) {
                const lv_image_dsc_t *dust[]={&ws_dust_1,&ws_dust_2,&ws_dust_3};
                picture(layer,dust[(18-p->life)/6],p->x/2-16,p->y/2-16,32,32,
                        (lv_opa_t)(p->life*255/18));
            } else if (p->kind==2) {
                const lv_image_dsc_t *shards[]={&ws_shard_1,&ws_shard_2,&ws_shard_3};
                picture(layer,shards[i%3],p->x/2-6,p->y/2-6,12,12,255);
            } else rect(layer,(ws_rect){p->x/2-3,p->y/2-3,6,6},p->color,255);
        }
        if (shown.mining>=0 && shown.crack) {
            ws_rect r=workshop_block_rect(&shown,shown.mining);
            for (int y=r.y;y<r.y+r.h;y+=48) for (int x=r.x;x<r.x+r.w;x+=48)
                picture(layer,cracks[shown.crack-1],x,y,48,48,255);
        }
        if (!shown.inventory && !shown.returning && shown.lifted<0 &&
            (shown.selected>=WS_GRASS || shown.held>=0)) {
            unsigned item=shown.held>=0 ? shown.blocks[shown.held].item : shown.selected;
            unsigned ori=shown.held>=0 ? shown.blocks[shown.held].orientation : shown.orientation;
            int w,h;
            workshop_shape(item,ori,&w,&h);
            ws_rect r={WS_X+shown.preview_x*48,WS_Y+(shown.preview_y-h+1)*48,w*48,h*48};
            if (shown.preview_x>=0 && shown.preview_y>=0 && shown.preview_x<20 &&
                shown.preview_y<11) {
                shaded_picture(layer,block_image(item,ori,shown.sky),r,light_item(item),153);
                uint32_t color=shown.preview ? 0x62e29a : 0xff6161;
                rect(layer,(ws_rect){r.x,r.y,r.w,2},color,255);
                rect(layer,(ws_rect){r.x,r.y+r.h-2,r.w,2},color,255);
                rect(layer,(ws_rect){r.x,r.y,2,r.h},color,255);
                rect(layer,(ws_rect){r.x+r.w-2,r.y,2,r.h},color,255);
            }
        }
    }
}
static void outline(lv_layer_t *layer,ws_rect r,uint32_t color)
{
    rect(layer,(ws_rect){r.x,r.y,r.w,2},color,255);
    rect(layer,(ws_rect){r.x,r.y+r.h-2,r.w,2},color,255);
    rect(layer,(ws_rect){r.x,r.y,2,r.h},color,255);
    rect(layer,(ws_rect){r.x+r.w-2,r.y,2,r.h},color,255);
}
static void draw_cursor(lv_event_t *e)
{
    lv_layer_t *layer=lv_event_get_layer(e);
    bool swinging=shown.selected==WS_PICK && shown.hand.closed && shown.ticks/10%2;
    const lv_image_dsc_t *cursor=shown.selected==WS_PICK ?
        (swinging ? &swing_image : &ws_cursor_pick) :
        (shown.hand.closed ? &ws_cursor_hand_grab : &ws_cursor_hand_open);
    /* Tip coordinates from compose_workshop_art.py, scaled to a 48 px cursor.
     * The swing frame is mirrored so the handle remains below/right of its tip.
     */
    int tip_x=shown.selected==WS_PICK ? (swinging ? 15 : 16) :
              shown.hand.closed ? 14 : 23;
    int tip_y=shown.selected==WS_PICK ? (swinging ? 12 : 13) :
              shown.hand.closed ? 16 : 7;
    if (!shown.menu && !shown.inventory && shown.selected<WS_GRASS && shown.held<0) {
        int x=(shown.hand.x-WS_X)/48,y=(shown.hand.y-WS_Y)/48;
        if (shown.hand.x>=WS_X && shown.hand.y>=WS_Y && x<WS_COLS && y<WS_ROWS)
            outline(layer,(ws_rect){WS_X+x*48,WS_Y+y*48,48,48},0xe5f2ef);
    }
    picture(layer,cursor,shown.hand.x-tip_x,shown.hand.y-tip_y,48,48,255);
    if (!shown.menu && !shown.inventory && (shown.selected>=WS_GRASS || shown.held>=0)) {
        unsigned item=shown.held>=0 ? shown.blocks[shown.held].item : shown.selected;
        unsigned orientation=shown.held>=0 ? shown.blocks[shown.held].orientation :
                                          shown.orientation;
        const lv_image_dsc_t *icon=block_image(item,orientation,shown.sky);
        int maximum=icon->header.w>icon->header.h ? icon->header.w : icon->header.h;
        ws_rect r={shown.hand.x+36,shown.hand.y+24,
                   (int)icon->header.w*24/maximum,(int)icon->header.h*24/maximum};
        shaded_picture(layer,icon,r,light_item(item),255);
    }
}
static void simulate(void *unused)
{
    (void)unused;
    uint64_t start=platform_ticks();
    uint32_t lock=sched_port_lock();
    unsigned action=command;
    command=0;
    ws_input input={(int)ui_grab.x,(int)ui_grab.y,ui_grab.cls,ui_grab.closed,
        ui_grab.lost ? (uint32_t)(start*1000/platform_clock_hz())-ui_grab.seen_at : 0};
    sched_port_unlock(lock);
    unsigned old_scene=state.scene;
    bool old_menu=state.menu;
    if (action>=1 && action<=3) workshop_scene(&state,action-1);
    if (action==4) workshop_init(&state);
    if (action==5) { state.inventory=!state.inventory; state.mining=-1; }
    if (action>=10 && action<=13) workshop_key(&state,action-9);
    if (action>=100 && action<125) {
        state.inventory_hover=(int)(action-100);
        workshop_key(&state,3);
    }
    workshop_step(&state,input);
    if (!state.menu && (old_menu || old_scene!=state.scene)) {
        char line[96];
        snprintf(line,sizeof line,"game name=workshop event=scene name=%s\r\n",
                 ws_scene_names[state.scene]);
        platform_puts(line);
    }
    unsigned us=(unsigned)((platform_ticks()-start)*1000000/platform_clock_hz());
    if (us>max_us) max_us=us;
}
static void snapshot(void *unused,void *destination)
{
    (void)unused;
    workshop_snapshot_copy(&state,destination);
}
static void report(void *unused,unsigned draws,unsigned steps,unsigned late,unsigned mean_us)
{
    (void)unused; (void)steps;
    unsigned count=0,fall=0;
    for (int i=0;i<WS_BLOCKS;++i) if (state.blocks[i].used) {
        ++count;
        if (state.blocks[i].group) ++fall;
    }
    char line[256];
    snprintf(line,sizeof line,
        "game name=workshop draw_fps=%u logic_us=%u logic_max_us=%u late=%u "
        "blocks=%u falling=%u animals=%u places=%u breaks=%u moves=%u\r\n",
        draws,mean_us,max_us,late,count,fall,state.animal_count,
        state.places,state.breaks,state.moves);
    max_us=0;
    platform_puts(line);
}
void ui_workshop_action(unsigned action)
{
    uint32_t lock=sched_port_lock();
    command=action;
    sched_port_unlock(lock);
}
bool ui_workshop_key(uint32_t key)
{
    unsigned action=0;
    if (key==LV_KEY_NEXT || key==LV_KEY_RIGHT) action=10;
    if (key==LV_KEY_PREV || key==LV_KEY_LEFT) action=11;
    if (key==LV_KEY_ENTER) action=12;
    if (key==LV_KEY_ESC && shown.inventory) action=13;
    if (!action) return false;
    ui_workshop_action(action);
    return true;
}
static void damage(ws_rect r,void *unused)
{
    (void)unused;
    lv_area_t area={r.x,r.y,r.x+r.w-1,r.y+r.h-1};
    lv_obj_invalidate_area(frame,&area);
    lv_obj_invalidate_area(overlay,&area);
    lv_obj_invalidate_area(cursor_layer,&area);
}
void ui_workshop_update(void)
{
    if (painted) { game_loop_drawn(); painted=false; }
    if (!game_loop_read(&next)) { cache_process(); return; }
    cache_update();
    workshop_dirty(&shown,&next,damage,NULL);
    bool menu_changed=shown.menu!=next.menu,inventory_changed=shown.inventory!=next.inventory;
    unsigned old_item=shown.selected,old_orientation=shown.orientation,old_sky=shown.sky;
    int hover=shown.hover;
    shown=next;
    if (menu_changed) lv_obj_set_hidden(menu,!shown.menu);
    if (inventory_changed) lv_obj_set_hidden(inventory,!shown.inventory);
    if (menu_changed || old_sky!=shown.sky) {
        const uint32_t colors[]={0x000000,0x59351e,0x081a3b};
        const lv_opa_t opacity[]={89,156,208};
        lv_obj_set_style_bg_color(frame,lv_color_hex(colors[shown.sky]),0);
        lv_obj_set_style_bg_opa(frame,opacity[shown.sky],0);
    }
    if (old_item!=shown.selected || old_orientation!=shown.orientation || menu_changed) {
        ui_text(item_label,ws_names[shown.selected]);
        lv_image_set_src(item_icon,block_image(shown.selected,shown.orientation,shown.sky));
    }
    if (hover!=shown.hover || menu_changed || inventory_changed) {
        unsigned count=shown.menu ? 3 : 25;
        for (unsigned i=0;i<count;++i) {
            lv_obj_t *o=shown.menu ? cards[i] : cells[i];
            lv_obj_set_style_border_width(o,(int)i==shown.hover ? 3 : 1,0);
            lv_obj_set_style_border_color(o,lv_color_hex((int)i==shown.hover ?
                0x4aceb4 : 0x44556b),0);
        }
    }
    lv_obj_set_hidden(hold_arc,!shown.hold);
    if (shown.hold) {
        lv_arc_set_range(hold_arc,0,shown.menu ? 60 : WS_INVENTORY_HOLD);
        lv_arc_set_value(hold_arc,(int)shown.hold);
        lv_obj_set_pos(hold_arc,shown.hand.x+(shown.menu ? -32 : 24),shown.hand.y-32);
    }
    cache_process();
}
static void tick(lv_timer_t *t) { (void)t; ui_workshop_update(); }
static void deleted(lv_event_t *e)
{
    (void)e;
    game_loop_stop();
    lv_timer_delete(timer);
    platform_puts("game name=workshop event=exit\r\n");
}
static lv_obj_t *surface(lv_obj_t *parent)
{
    lv_obj_t *o=lv_obj_create(parent);
    lv_obj_remove_style_all(o);
    lv_obj_set_size(o,1280,720);
    lv_obj_set_pos(o,0,0);
    lv_obj_set_clickable(o,false);
    lv_obj_set_scrollable(o,false);
    return o;
}
static void maps(void)
{
    static workshop_state world;
    for (unsigned scene=0;scene<3;++scene) {
        workshop_scene(&world,scene);
        for (int row=0;row<11;++row) for (int col=0;col<20;++col) {
            int id=world.grid[row][col];
            uint32_t c=id<0 ? 0xff203247 : 0xff000000|ws_colors[world.blocks[id].item];
            for (int y=0;y<8;++y) for (int x=0;x<8;++x)
                minimaps[scene][(row*8+y)*160+col*8+x]=c;
        }
        thumbnails[scene]=(lv_image_dsc_t){
            .header={.magic=LV_IMAGE_HEADER_MAGIC,.cf=LV_COLOR_FORMAT_ARGB8888,
                .w=160,.h=88,.stride=640},.data_size=sizeof minimaps[scene],
            .data=(const uint8_t *)minimaps[scene]};
    }
}
void ui_page_workshop(lv_obj_t *p)
{
    grab_init(&ui_grab);
    ui_grab.mode=2;
    workshop_init(&state);
    workshop_snapshot_copy(&state,&shown);
    command=max_us=0;
    painted=false;
    memset(tiles,0,sizeof tiles);
    memset(tile_used,0,sizeof tile_used);
    memset(changed_tiles,0,sizeof changed_tiles);
    next=shown;
    light_count=0;
    map_row=MAP_ROWS;
    memset(coarse_light,255,sizeof coarse_light);
    maps();
    const uint32_t *source=(const uint32_t *)ws_cursor_pick_swing.data;
    for (int y=0;y<64;++y) for (int x=0;x<64;++x)
        swing_pixels[y*64+x]=source[y*64+63-x];
    swing_image=ws_cursor_pick_swing;
    swing_image.data=(const uint8_t *)swing_pixels;
    for (int y=0;y<WS_ROWS+2;++y) for (int x=0;x<WS_COLS+2;++x)
        tile_images[y][x]=(lv_image_dsc_t){
            .header={.magic=LV_IMAGE_HEADER_MAGIC,.cf=LV_COLOR_FORMAT_ARGB8888,
                .w=48,.h=48,.stride=192},.data_size=sizeof tiles[y][x],
            .data=(const uint8_t *)tiles[y][x]};
    hud=ui_camera_layout(p,"方块工坊");
    frame=surface(lv_screen_active());
    lv_obj_move_to_index(frame,0);
    lv_obj_set_style_bg_color(frame,lv_color_hex(0),0);
    lv_obj_set_style_bg_opa(frame,89,0);
    lv_obj_add_event_cb(frame,draw_world,LV_EVENT_DRAW_MAIN,NULL);
    lv_obj_add_event_cb(frame,deleted,LV_EVENT_DELETE,NULL);
    item_icon=lv_image_create(hud);
    lv_obj_set_size(item_icon,36,36);
    lv_image_set_inner_align(item_icon,LV_IMAGE_ALIGN_CONTAIN);
    lv_image_set_src(item_icon,&ws_tool_hand);
    item_label=ui_text_label(hud,"空手",&sim_font_16,TEAL);
    lv_obj_t *hint=ui_text_label(hud,"点赞保持 0.8 s：物品栏 · 剪刀手：旋转",&sim_font_14,MUTED);
    lv_obj_set_flex_grow(hint,1);
    ui_action_button(hud,"物品栏",5);
    ui_action_button(hud,"换场景",4);
    menu=ui_box(lv_screen_active(),0,48,1280,632,0x142638);
    lv_obj_set_style_bg_opa(menu,180,0);
    lv_obj_set_style_border_width(menu,0,0);
    lv_obj_set_style_radius(menu,0,0);
    ui_label(menu,"从一片空地，到你的想象",190,76,&sim_font_28,0xffefd0);
    ui_label(menu,"握拳停留选择场景 · 也可使用方向键与确认键",190,122,
             &sim_font_16,0xc4d2df);
    static const char *const descriptions[]={"草地与泥土，自由开始", "一间木屋，一棵树", "石砖塔楼，等你改造"};
    for (unsigned i=0;i<3;++i) {
        cards[i]=ui_game_button(menu,"",190+(int)i*310,198,280,i+1);
        lv_obj_set_height(cards[i],230);
        lv_obj_set_style_bg_color(cards[i],lv_color_hex(0x243d50),0);
        lv_obj_set_style_border_width(cards[i],1,0);
        lv_obj_clean(cards[i]);
        lv_obj_set_layout(cards[i],LV_LAYOUT_NONE);
        lv_obj_set_style_pad_all(cards[i],0,0);
        ui_picture(cards[i],&thumbnails[i],20,18,240,132);
        ui_label(cards[i],ws_scene_names[i],20,162,&sim_font_20,0xffefd0);
        ui_label(cards[i],descriptions[i],20,195,&sim_font_14,0xc4d2df);
    }
    inventory=ui_box(lv_screen_active(),280,130,720,478,0x14283b);
    lv_obj_set_style_border_color(inventory,lv_color_hex(0x61778b),0);
    lv_obj_set_style_border_width(inventory,2,0);
    for (unsigned i=0;i<25;++i) {
        const lv_image_dsc_t *art;
        const char *name;
        unsigned item=i<2 ? i : i-3;
        if (i>=2 && i<=4) {
            static const char *const names[]={"白天","黄昏","夜晚"};
            art=skies[i-2]; name=names[i-2];
        } else { art=block_image(item,item==WS_PILLAR,WS_DAY); name=ws_names[item]; }
        cells[i]=ui_game_button(inventory,"",20+(int)(i%5)*136,20+(int)(i/5)*90,128,100+i);
        lv_obj_set_height(cells[i],84);
        lv_obj_set_style_bg_color(cells[i],lv_color_hex(0x294359),0);
        lv_obj_clean(cells[i]);
        lv_obj_set_layout(cells[i],LV_LAYOUT_NONE);
        lv_obj_set_style_pad_all(cells[i],0,0);
        ui_picture(cells[i],art,38,5,52,52);
        lv_obj_t *label=ui_label(cells[i],name,0,62,&sim_font_14,0xe7edf2);
        lv_obj_set_width(label,128);
        lv_obj_set_style_text_align(label,LV_TEXT_ALIGN_CENTER,0);
    }
    lv_obj_set_hidden(inventory,true);
    overlay=surface(lv_screen_active());
    lv_obj_add_event_cb(overlay,draw_dynamic,LV_EVENT_DRAW_MAIN,NULL);
    lv_obj_move_to_index(overlay,lv_obj_get_index(p));
    cursor_layer=surface(lv_screen_active());
    lv_obj_add_event_cb(cursor_layer,draw_cursor,LV_EVENT_DRAW_MAIN,NULL);
    hold_arc=ui_hold_arc(lv_screen_active(),60);
    lv_obj_set_hidden(hold_arc,true);
    timer=lv_timer_create(tick,16,NULL);
    ui_hint("空手移动 · 稿子挖掘 · 握拳放置 · 张手松开");
    game_loop_config config={simulate,snapshot,report,NULL,
        {&snapshots[0],&snapshots[1],&snapshots[2]},sizeof(workshop_snapshot)};
    game_loop_start(&config);
}
