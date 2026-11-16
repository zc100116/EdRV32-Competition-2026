/* page_tower.c — showcase R4 §6.1/6.5; camera-backed tower view and atlas loading.
 * GUI owns LVGL and reads snapshots; application callbacks only touch rules/input.
 */
#include "widgets.h"
#include "tower.h"
#include "sprite_rot.h"
#include "game_loop.h"
#include "grab.h"
#include "../platform.h"
#include "../board/ddr_map.h"
#include <port.h>
#include "src/draw/lv_draw_private.h"
#include "src/misc/lv_area_private.h"
#include <stdio.h>
#include <string.h>
#ifdef __riscv
#include <cache.h>
#include <soc_map.h>
#else
#include <stdlib.h>
#endif
LV_IMAGE_DECLARE(tower_block_wood_square);
LV_IMAGE_DECLARE(tower_block_wood_plank);
LV_IMAGE_DECLARE(tower_block_wood_brick);
LV_IMAGE_DECLARE(tower_block_wood_triangle);
LV_IMAGE_DECLARE(tower_block_wood_arch);
LV_IMAGE_DECLARE(tower_block_wood_circle);
LV_IMAGE_DECLARE(tower_block_stone_square);
LV_IMAGE_DECLARE(tower_block_stone_plank);
LV_IMAGE_DECLARE(tower_block_stone_brick);
LV_IMAGE_DECLARE(tower_block_stone_triangle);
LV_IMAGE_DECLARE(tower_block_stone_arch);
LV_IMAGE_DECLARE(tower_block_stone_circle);
LV_IMAGE_DECLARE(tower_block_ice_square);
LV_IMAGE_DECLARE(tower_block_ice_plank);
LV_IMAGE_DECLARE(tower_block_ice_brick);
LV_IMAGE_DECLARE(tower_block_ice_triangle);
LV_IMAGE_DECLARE(tower_block_ice_arch);
LV_IMAGE_DECLARE(tower_block_ice_circle);
LV_IMAGE_DECLARE(tower_block_metal_square);
LV_IMAGE_DECLARE(tower_block_metal_plank);
LV_IMAGE_DECLARE(tower_block_metal_brick);
LV_IMAGE_DECLARE(tower_block_metal_triangle);
LV_IMAGE_DECLARE(tower_block_metal_arch);
LV_IMAGE_DECLARE(tower_block_metal_circle);
LV_IMAGE_DECLARE(tower_block_rubber_square);
LV_IMAGE_DECLARE(tower_block_rubber_plank);
LV_IMAGE_DECLARE(tower_block_rubber_brick);
LV_IMAGE_DECLARE(tower_block_rubber_triangle);
LV_IMAGE_DECLARE(tower_block_rubber_arch);
LV_IMAGE_DECLARE(tower_block_rubber_circle);
LV_IMAGE_DECLARE(tower_block_glass_square);
LV_IMAGE_DECLARE(tower_block_glass_plank);
LV_IMAGE_DECLARE(tower_block_glass_brick);
LV_IMAGE_DECLARE(tower_block_glass_triangle);
LV_IMAGE_DECLARE(tower_block_glass_arch);
LV_IMAGE_DECLARE(tower_block_glass_circle);
LV_IMAGE_DECLARE(tower_platform);
LV_IMAGE_DECLARE(tower_shelf);
LV_IMAGE_DECLARE(tower_ruler);
LV_IMAGE_DECLARE(tower_hand_open);
LV_IMAGE_DECLARE(tower_hand_fist);
LV_IMAGE_DECLARE(tower_rotate_hint);
LV_IMAGE_DECLARE(tower_badge_record);
LV_IMAGE_DECLARE(tower_dust_1);
LV_IMAGE_DECLARE(tower_dust_2);
LV_IMAGE_DECLARE(tower_dust_3);
LV_IMAGE_DECLARE(tower_shard_1);
LV_IMAGE_DECLARE(tower_shard_2);
LV_IMAGE_DECLARE(tower_shard_3);
static const lv_image_dsc_t *const originals[TOWER_KINDS] = {
    &tower_block_wood_square,&tower_block_wood_plank,&tower_block_wood_brick,
    &tower_block_wood_triangle,&tower_block_wood_arch,&tower_block_wood_circle,
    &tower_block_stone_square,&tower_block_stone_plank,&tower_block_stone_brick,
    &tower_block_stone_triangle,&tower_block_stone_arch,&tower_block_stone_circle,
    &tower_block_ice_square,&tower_block_ice_plank,&tower_block_ice_brick,
    &tower_block_ice_triangle,&tower_block_ice_arch,&tower_block_ice_circle,
    &tower_block_metal_square,&tower_block_metal_plank,&tower_block_metal_brick,
    &tower_block_metal_triangle,&tower_block_metal_arch,&tower_block_metal_circle,
    &tower_block_rubber_square,&tower_block_rubber_plank,&tower_block_rubber_brick,
    &tower_block_rubber_triangle,&tower_block_rubber_arch,&tower_block_rubber_circle,
    &tower_block_glass_square,&tower_block_glass_plank,&tower_block_glass_brick,
    &tower_block_glass_triangle,&tower_block_glass_arch,&tower_block_glass_circle,
};
static tower_state state;
static tower_snapshot snapshots[3], shown, next;
static sprite_rot atlas;
static lv_image_dsc_t images[TOWER_KINDS][64];
static uint32_t *storage;
static lv_obj_t *frame, *menu, *choices, *load_panel, *load_bar, *hud, *height_label;
static lv_obj_t *level_label, *prompt, *countdown, *hold_arc, *result, *result_text;
static lv_obj_t *record_label;
static lv_timer_t *timer;
static unsigned command, record_height;
static tower_mode selected;
static bool loading, ended, painted;
static unsigned menu_hold, menu_started;
static bool choosing_challenge;
static lv_obj_t *clear_button;
static int menu_hover = -1;
static void event_snapshot(const char *event, const tower_snapshot *snap)
{
    char line[224];
    snprintf(line,sizeof line,
        "game name=tower event=%s mode=%s height=%d blocks=%u dur_ms=%u stars=%u\r\n",
        event,tower_name(snap->mode),snap->height/10,snap->bodies,
        snap->ticks*1000/TOWER_HZ,snap->stars);
    platform_puts(line);
}
static void event_line(const char *event)
{
    tower_snapshot snap;
    tower_snapshot_copy(&state,&snap);
    event_snapshot(event,&snap);
}
static void simulate(void *context)
{
    (void)context;
    uint32_t lock = sched_port_lock();
    unsigned action = command;
    command = 0;
    sched_port_unlock(lock);
    if (action == 1) {
        tower_init(&state,selected,(uint32_t)platform_ticks(),record_height);
        ended = false;
        if (selected != TOWER_MENU) event_line("start");
    }
    if (action == 2) tower_clear(&state);
    tower_input hand = {(int)ui_grab.x,(int)ui_grab.y,ui_grab.cls,
                        ui_grab.closed,ui_grab.lost};
    tower_step(&state,hand);
    if (state.phase == TOWER_RESULT && !ended) { event_line("end"); ended = true; }
    if (state.record > record_height) record_height = state.record;
}
static void snapshot(void *context, void *destination)
{
    (void)context;
    tower_snapshot_copy(&state,destination);
}
static void report(void *context, unsigned draws, unsigned steps,
                   unsigned late, unsigned mean_us)
{
    (void)context;
    tower_snapshot snap;
    tower_snapshot_copy(&state,&snap);
    char line[256];
    snprintf(line,sizeof line,
        "game name=tower draw_fps=%u phys_ms=%u.%03u steps=%u late=%u "
        "awake=%u bodies=%u cursor=%d,%d lost=%u cls=%d\r\n",
        draws,mean_us/1000,mean_us%1000,steps,late,
        snap.awake+state.world.bodies[state.platform].awake,snap.bodies+1,
        snap.hand.x,snap.hand.y,snap.hand.lost,snap.hand.cls);
    platform_puts(line);
}
static void run_loop(void)
{
    game_loop_config config = {simulate,snapshot,report,NULL,
        {&snapshots[0],&snapshots[1],&snapshots[2]},sizeof(tower_snapshot)};
    command = 1;
    game_loop_start(&config);
}
static void picture(lv_layer_t *layer, const lv_image_dsc_t *image, int x, int y,
                    unsigned width, unsigned height, lv_opa_t opacity)
{
    lv_draw_image_dsc_t d;
    lv_draw_image_dsc_init(&d);
    d.src = image;
    d.opa = opacity;
    d.scale_x = width*256/image->header.w;
    d.scale_y = height*256/image->header.h;
    d.pivot = (lv_point_t){0,0};
    lv_area_t area = {x,y,x+(int)image->header.w-1,y+(int)image->header.h-1};
    lv_draw_image(layer,&d,&area);
}
static void line(lv_layer_t *layer, int x, int y, int width, uint32_t color)
{
    lv_draw_rect_dsc_t d;
    lv_draw_rect_dsc_init(&d);
    d.bg_color = lv_color_hex(color);
    lv_area_t area = {x,y,x+width-1,y+1};
    lv_draw_rect(layer,&d,&area);
}
static void draw(lv_event_t *event)
{
    painted = true;
    lv_layer_t *layer = lv_event_get_layer(event);
    if (loading) return;
    picture(layer,&tower_platform,shown.platform_x,TOWER_PLATFORM_Y,
            TOWER_PLATFORM_W,TOWER_PLATFORM_H,255);
    picture(layer,&tower_shelf,40,150,160,420,255);
    picture(layer,&tower_shelf,1080,150,160,420,255);
    picture(layer,&tower_ruler,1010,140,42,480,255);
    for (int y = 220; y <= 620; y += 100) line(layer,1000,y,14,0xf3d985);
    if (shown.mode == TOWER_HIGH) line(layer,280,620-TOWER_TARGET,770,0x42eac3);
    if (shown.peak) line(layer,950,620-shown.peak,104,0xffc45c);
    if (shown.height) line(layer,978,620-shown.height,76,0xffffff);
    for (unsigned i = 0; i < TOWER_SLOTS; ++i) {
        int x, y;
        tower_shelf_position(i,&x,&y);
        const lv_image_dsc_t *image = originals[shown.shelf[i]];
        unsigned scale = 120*256/image->header.w;
        if (scale > 72*256/image->header.h) scale = 72*256/image->header.h;
        unsigned w = image->header.w*scale/256;
        unsigned h = image->header.h*scale/256;
        picture(layer,image,x-(int)w/2,y-(int)h/2,w,h,255);
    }
    if (shown.held >= 0) {
        const tower_render_block *b = &shown.blocks[shown.held];
        lv_draw_rect_dsc_t d;
        lv_draw_rect_dsc_init(&d);
        d.bg_color = lv_color_hex(0x60ddce);
        d.bg_opa = 35;
        lv_area_t area = {b->bounds.min.x/PHYS_ONE,b->bounds.max.y/PHYS_ONE,
                         b->bounds.max.x/PHYS_ONE,TOWER_PLATFORM_Y};
        if (area.y1 <= area.y2) lv_draw_rect(layer,&d,&area);
    }
    for (int i = 0; i < PHYS_MAX_BODIES; ++i) {
        const tower_render_block *b = &shown.blocks[i];
        if (!b->used) continue;
        const sprite_frame *f = &atlas.frames[b->kind][b->frame];
        picture(layer,&images[b->kind][b->frame],b->x+f->left,b->y+f->top,
                f->width,f->height,255);
    }
    static const lv_image_dsc_t *const particle_images[] = {
        &tower_dust_1,&tower_shard_1,&tower_shard_2,&tower_shard_3};
    for (unsigned i = 0; i < TOWER_PARTICLES; ++i) {
        const tower_particle *p = &shown.particles[i];
        if (p->life) picture(layer,particle_images[p->kind],p->x-12,p->y-12,24,24,
                            (lv_opa_t)(p->life*255/(p->kind ? 60 : 24)));
    }
    picture(layer,shown.hand.closed ? &tower_hand_fist : &tower_hand_open,
            shown.hand.x-24,shown.hand.y-24,48,48,255);
    if (shown.held >= 0)
        picture(layer,&tower_rotate_hint,shown.hand.x+28,shown.hand.y-42,48,48,255);
    if (shown.badge) picture(layer,&tower_badge_record,540,120,200,80,255);
}
static lv_area_t body_bounds(const tower_render_block *b)
{
    const sprite_frame *f = &atlas.frames[b->kind][b->frame];
    return (lv_area_t){b->x+f->left-2,b->y+f->top-2,
        b->x+f->left+(int)f->width+2,b->y+f->top+(int)f->height+2};
}
static void dirty(lv_area_t a, lv_area_t b)
{
    lv_area_join(&a,&a,&b);
    lv_obj_invalidate_area(frame,&a);
}
static lv_area_t cursor_bounds(const tower_snapshot *s)
{
    return (lv_area_t){s->hand.x-36,s->hand.y-48,s->hand.x+80,s->hand.y+36};
}
static void invalidate(const tower_snapshot *a, const tower_snapshot *b)
{
    for (int i = 0; i < PHYS_MAX_BODIES; ++i) {
        const tower_render_block *old = &a->blocks[i], *now = &b->blocks[i];
        if (!old->used && !now->used) continue;
        if (old->used && now->used && old->x == now->x && old->y == now->y &&
            old->frame == now->frame) continue;
        lv_area_t first = body_bounds(old->used ? old : now);
        lv_area_t last = body_bounds(now->used ? now : old);
        dirty(first,last);
    }
    if (a->hand.x != b->hand.x || a->hand.y != b->hand.y ||
        a->hand.closed != b->hand.closed || a->held != b->held)
        dirty(cursor_bounds(a),cursor_bounds(b));
    for (unsigned i = 0; i < TOWER_PARTICLES; ++i) {
        const tower_particle *p = &a->particles[i], *q = &b->particles[i];
        if (p->life || q->life) dirty((lv_area_t){p->x-14,p->y-14,p->x+14,p->y+14},
                                    (lv_area_t){q->x-14,q->y-14,q->x+14,q->y+14});
    }
    for (unsigned i = 0; i < TOWER_SLOTS; ++i)
        if (a->shelf[i] != b->shelf[i]) {
            int x, y;
            tower_shelf_position(i,&x,&y);
            lv_area_t area = {x-64,y-40,x+64,y+40};
            lv_obj_invalidate_area(frame,&area);
        }
    if (a->platform_x != b->platform_x)
        dirty((lv_area_t){a->platform_x,620,a->platform_x+720,684},
              (lv_area_t){b->platform_x,620,b->platform_x+720,684});
    if (a->peak != b->peak || a->height != b->height) {
        lv_area_t ruler = {945,100,1060,622};
        lv_obj_invalidate_area(frame,&ruler);
    }
    if (a->badge || b->badge) {
        if (!a->badge || !b->badge) {
            lv_area_t area = {538,118,742,202};
            lv_obj_invalidate_area(frame,&area);
        }
    }
    bool projection_moved = a->held != b->held;
    if (a->held >= 0 && a->held == b->held)
        projection_moved = memcmp(&a->blocks[a->held].bounds,&b->blocks[b->held].bounds,
                                   sizeof(phys_aabb)) != 0;
    if (projection_moved) {
        const tower_snapshot *states[] = {a,b};
        for (unsigned i = 0; i < 2; ++i) if (states[i]->held >= 0) {
            phys_aabb bb = states[i]->blocks[states[i]->held].bounds;
            lv_area_t area = {bb.min.x/PHYS_ONE-2,bb.min.y/PHYS_ONE-2,
                             bb.max.x/PHYS_ONE+2,622};
            lv_obj_invalidate_area(frame,&area);
        }
    }
}
static void choose(tower_mode mode)
{
    game_loop_stop();
    selected = mode;
    lv_obj_set_hidden(clear_button,true);
    lv_obj_set_hidden(hold_arc,true);
    loading = true;
    lv_obj_invalidate(frame);
    lv_obj_set_hidden(menu,true);
    lv_obj_set_hidden(choices,true);
    lv_obj_set_hidden(result,true);
    lv_obj_set_hidden(load_panel,false);
    lv_obj_set_hidden(hud,true);
    sprite_source sources[TOWER_KINDS];
    for (unsigned i = 0; i < TOWER_KINDS; ++i)
        sources[i] = (sprite_source){(const uint32_t *)originals[i]->data,
                                    originals[i]->header.w,originals[i]->header.h};
    sprite_rot_begin(&atlas,sources,tower_kinds(mode),storage);
    lv_bar_set_value(load_bar,0,LV_ANIM_OFF);
}
void ui_tower_action(unsigned action)
{
    if (action == 1) choose(TOWER_TUTORIAL);
    if (action == 2) {
        choosing_challenge = true;
        menu_hover = -1;
        menu_hold = 0;
        lv_obj_set_hidden(menu,true);
        lv_obj_set_hidden(choices,false);
    }
    if (action == 3) choose(TOWER_FREE);
    if (action == 5) choose(TOWER_HIGH);
    if (action == 6) choose(TOWER_QUAKE);
    if (action == 7) choose(selected);
    if (action == 8 && selected == TOWER_FREE) {
        uint32_t lock = sched_port_lock();
        command = 2;
        sched_port_unlock(lock);
    }
}
bool ui_tower_loading(void) { return loading; }
unsigned ui_tower_atlas_bytes(void) { return atlas.bytes; }
void ui_tower_update(void)
{
    if (painted) { game_loop_drawn(); painted = false; }
    if (loading) {
        unsigned kind = atlas.kind, frame_number = atlas.frame;
        while (!(atlas.kinds & (UINT64_C(1)<<kind))) ++kind;
        bool done = sprite_rot_generate(&atlas);
        const sprite_frame *f = &atlas.frames[kind][frame_number];
#ifdef __riscv
        cache_clean((uintptr_t)f->pixels,f->width*f->height*4);
#endif
        images[kind][frame_number] = (lv_image_dsc_t){
            .header={.magic=LV_IMAGE_HEADER_MAGIC,.cf=LV_COLOR_FORMAT_ARGB8888,
                .w=f->width,.h=f->height,.stride=f->width*4},
            .data_size=f->width*f->height*4,.data=(const uint8_t *)f->pixels};
        lv_bar_set_value(load_bar,(int)(atlas.completed*100/atlas.total),LV_ANIM_OFF);
        if (done) {
            loading = false;
            memset(&shown,0,sizeof shown);
            shown.held = -1;
            shown.platform_x = TOWER_PLATFORM_X;
            lv_obj_set_hidden(load_panel,true);
            lv_obj_set_hidden(hud,false);
            ui_text(level_label,tower_name(selected));
            run_loop();
            lv_obj_invalidate(frame);
        }
        return;
    }
    if (!game_loop_read(&next)) return;
    invalidate(&shown,&next);
    shown = next;
    ui_text(level_label,tower_name(shown.mode));
    lv_obj_set_hidden(clear_button,shown.mode != TOWER_FREE || shown.phase == TOWER_RESULT);
    char text[160];
    snprintf(text,sizeof text,"%d",shown.height/10);
    ui_text(height_label,text);
    lv_obj_set_hidden(record_label,!shown.badge);
    lv_arc_set_value(hold_arc,(int)(shown.mode == TOWER_MENU ? menu_hold : shown.hold));
    lv_obj_set_pos(hold_arc,shown.hand.x-32,shown.hand.y-32);
    lv_obj_set_hidden(hold_arc,shown.mode == TOWER_MENU ? !menu_hold : !shown.hold);
    unsigned seconds = shown.ticks/TOWER_HZ;
    unsigned duration = shown.mode == TOWER_HIGH ? 90 : 60;
    lv_obj_set_hidden(countdown,shown.mode != TOWER_HIGH && shown.mode != TOWER_QUAKE);
    lv_bar_set_value(countdown,(int)(seconds < duration ? (duration-seconds)*100/duration : 0),
                     LV_ANIM_OFF);
    if (shown.mode == TOWER_MENU) {
        int hover = -1;
        int x = shown.hand.x, y = shown.hand.y;
        if (choosing_challenge) {
            if (y >= 368 && y <= 408 && x >= 330 && x < 940)
                hover = x < 640 ? 0 : 1;
        } else if (y >= 378 && y <= 418 && x >= 280 && x < 1000)
            hover = (x-280)/240;
        if (hover != menu_hover || !shown.hand.closed) menu_started = shown.ticks;
        menu_hover = hover;
        menu_hold = hover >= 0 && shown.hand.closed ? shown.ticks-menu_started : 0;
        if (menu_hold >= TOWER_HOLD) {
            unsigned action = choosing_challenge ? (unsigned)hover+5 : (unsigned)hover+1;
            ui_tower_action(action);
            menu_hold = 0;
            menu_started = shown.ticks;
        }
    }
    if (shown.mode == TOWER_TUTORIAL) ui_text(prompt,shown.tutorial == 0 ?
        "握拳抓起积木 → 移到平台上方 → 张手放下" : "抓着时比剪刀手旋转 → 张手放下");
    else if (shown.phase == TOWER_SHAKE) ui_text(prompt,"地震测试 · 平台晃动中");
    else if (shown.phase == TOWER_SETTLE) ui_text(prompt,"等待积木稳定");
    else {
        snprintf(text,sizeof text,"%s · 纪录 %d cm · %u 块 · %u s",
            shown.mode == TOWER_HIGH ? "目标 24 cm，稳定 3 秒" : "握拳抓起 · 剪刀手旋转 · 张手放下",
            shown.peak/10,shown.bodies,seconds);
        ui_text(prompt,text);
    }
    if (shown.phase == TOWER_RESULT) {
        snprintf(text,sizeof text,"高度 %d cm   用时 %u s\n星级 %u / 3%s",
            shown.height/10,seconds,shown.stars,shown.new_record ? "   新纪录" : "");
        ui_text(result_text,text);
        lv_obj_set_hidden(result,false);
    }
}
static void tick(lv_timer_t *t) { (void)t; ui_tower_update(); }
static void deleted(lv_event_t *event)
{
    (void)event;
    game_loop_stop();
    game_loop_read(&shown);
    if (shown.mode != TOWER_MENU && shown.phase != TOWER_RESULT && !loading)
        event_snapshot("end",&shown);
    lv_timer_delete(timer);
#ifndef __riscv
    free(storage);
#endif
}
void ui_page_tower(lv_obj_t *p)
{
    grab_init(&ui_grab);
    ui_grab.mode = 2;
    ui_grab.mirror = true;
    ui_grab.smooth = true;
    ui_data_grab_mirror(true);
    selected = TOWER_MENU;
    loading = false;
    menu_hold = menu_started = 0;
    choosing_challenge = false;
    menu_hover = -1;
    memset(&shown,0,sizeof shown);
    shown.held = -1;
    shown.platform_x = TOWER_PLATFORM_X;
#ifdef __riscv
    storage = (uint32_t *)(EDRV32_DDR_BASE+SHOWCASE_TOWER_ROT_BASE);
#else
    storage = malloc(SHOWCASE_TOWER_ROT_BYTES);
#endif
    ui_video_surface(p);
    frame = ui_box(lv_screen_active(),0,0,1280,720,0x000000);
    lv_obj_set_style_bg_opa(frame,89,0);
    lv_obj_set_style_border_width(frame,0,0);
    lv_obj_set_style_radius(frame,0,0);
    lv_obj_move_to_index(frame,0);
    lv_obj_add_event_cb(frame,draw,LV_EVENT_DRAW_MAIN,NULL);
    lv_obj_add_event_cb(frame,deleted,LV_EVENT_DELETE,NULL);
    hud = ui_box(p,240,8,800,78,0x142b40);
    lv_obj_set_style_bg_opa(hud,235,0);
    level_label = ui_badge(hud,"积木塔");
    lv_obj_set_pos(level_label,20,8);
    lv_obj_set_style_text_font(level_label,&showcase_bold_32,0);
    prompt = ui_label(hud,"握拳停留 1 秒选择，或点按",20,48,&sim_font_16,0xd6e8f7);
    countdown = lv_bar_create(hud);
    lv_obj_set_pos(countdown,220,16);
    lv_obj_set_size(countdown,540,12);
    lv_obj_set_hidden(countdown,true);
    height_label = ui_label(p,"0",870,470,&showcase_digits_64,0xffffff);
    ui_label(p,"cm",970,510,&sim_font_20,0xffd880);
    for (unsigned cm = 0; cm <= 40; cm += 10) {
        char value[8];
        snprintf(value,sizeof value,"%u",cm);
        ui_label(p,value,1052,562-(int)cm*10,&sim_font_14,0xffd880);
    }
    record_label = ui_label(p,"新纪录",586,102,&sim_font_28,0x753b14);
    lv_obj_set_hidden(record_label,true);
    hold_arc = ui_hold_arc(lv_screen_active(),TOWER_HOLD);
    lv_obj_set_hidden(hold_arc,true);
    menu = ui_box(p,250,190,780,280,0x142b40);
    lv_obj_set_style_bg_opa(menu,245,0);
    ui_label(menu,"积木塔",40,24,&sim_font_40,0xffffff);
    ui_label(menu,"把创意一块块搭起来",40,80,&sim_font_20,0xb9d8e9);
    ui_button(menu,"教学",30,140,220,1);
    ui_button(menu,"挑战",270,140,220,2);
    ui_button(menu,"自由搭建",510,140,220,3);
    ui_label(menu,"握拳抓起   剪刀手旋转   张手放下",40,210,&sim_font_16,0xffd880);
    choices = ui_box(p,300,220,680,220,0x142b40);
    ui_label(choices,"选择挑战",30,20,&sim_font_28,0xffffff);
    ui_button(choices,"盖高楼 · 90 秒",30,100,290,5);
    ui_button(choices,"地震测试 · 60 秒",350,100,290,6);
    lv_obj_set_hidden(choices,true);
    load_panel = ui_box(p,360,250,560,160,0x142b40);
    ui_label(load_panel,"正在生成积木旋转帧",30,24,&sim_font_28,0xffffff);
    load_bar = lv_bar_create(load_panel);
    lv_obj_set_pos(load_bar,30,90);
    lv_obj_set_size(load_bar,500,20);
    lv_obj_set_hidden(load_panel,true);
    result = ui_box(p,340,190,600,280,0x142b40);
    ui_label(result,"搭建完成",30,20,&sim_font_40,0xffffff);
    result_text = ui_label(result,"",30,90,&sim_font_28,0xffd880);
    ui_button(result,"再来一局",30,210,240,7);
    ui_button(result,"返回",320,210,240,1000);
    lv_obj_set_hidden(result,true);
    ui_button(p,"清空",40,550,160,8);
    clear_button = lv_obj_get_child(p,-1);
    lv_obj_set_hidden(clear_button,true);
    timer = lv_timer_create(tick,16,NULL);
    ui_hint("积木塔 · 握拳停留抓起 · 比剪刀手转 90° · 张手松开");
    run_loop();
}
