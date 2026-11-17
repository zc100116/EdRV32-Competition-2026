/* page_tower.c — block workshop design §6; physical blocks view and boot-lifetime atlas.
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
LV_IMAGE_DECLARE(tower_block_wood_circle);
LV_IMAGE_DECLARE(tower_block_stone_square);
LV_IMAGE_DECLARE(tower_block_stone_circle);
LV_IMAGE_DECLARE(tower_block_ice_square);
LV_IMAGE_DECLARE(tower_block_ice_circle);
LV_IMAGE_DECLARE(tower_block_metal_square);
LV_IMAGE_DECLARE(tower_block_metal_circle);
LV_IMAGE_DECLARE(tower_block_rubber_square);
LV_IMAGE_DECLARE(tower_block_rubber_circle);
LV_IMAGE_DECLARE(tower_block_glass_square);
LV_IMAGE_DECLARE(tower_block_glass_circle);
LV_IMAGE_DECLARE(tower_platform);
LV_IMAGE_DECLARE(tower_hand_open);
LV_IMAGE_DECLARE(tower_hand_fist);
LV_IMAGE_DECLARE(tower_rotate_hint);
LV_IMAGE_DECLARE(tower_dust_1);
LV_IMAGE_DECLARE(tower_shard_1);
LV_IMAGE_DECLARE(tower_shard_2);
LV_IMAGE_DECLARE(tower_shard_3);
static const lv_image_dsc_t *const originals[TOWER_KINDS] = {
    &tower_block_wood_square,&tower_block_wood_circle,
    &tower_block_stone_square,&tower_block_stone_circle,
    &tower_block_ice_square,&tower_block_ice_circle,
    &tower_block_metal_square,&tower_block_metal_circle,
    &tower_block_rubber_square,&tower_block_rubber_circle,
    &tower_block_glass_square,&tower_block_glass_circle,
};
static tower_state state;
static tower_snapshot snapshots[3], shown, next;
static sprite_rot atlas;
static lv_image_dsc_t images[TOWER_KINDS][16];
static uint32_t *storage;
static void *geo_scratch;
static uint64_t atlas_started;
static lv_obj_t *frame, *load_panel, *load_bar, *mode_text;
static lv_timer_t *timer;
static unsigned command, phys_max_us, selected_mode;
static bool closed;
static bool loading, atlas_ready, painted, key_down;
static void simulate(void *context)
{
    (void)context;
    uint64_t started = platform_ticks();
    uint32_t lock = sched_port_lock();
    unsigned action = command;
    command = 0;
    sched_port_unlock(lock);
    if (action) tower_summon(&state,(int)ui_grab.x);
    grab_state_t rule = ui_grab;
    rule.mode = selected_mode;
    int hand_x = (int)ui_grab.x, hand_y = (int)ui_grab.y;
    const ui_hand_t *pose = ui_data_hand();
    state.opening = false;
    if (pose->count) {
        unsigned largest = 0;
        for (unsigned i = 1; i < pose->count; ++i)
            if (pose->people[i].width*pose->people[i].height >
                pose->people[largest].width*pose->people[largest].height) largest = i;
        grab_object_t targets[PHYS_MAX_BODIES];
        unsigned count = 0;
        for (int i = 0; i < PHYS_MAX_BODIES; ++i) {
            const phys_body *b = &state.world.bodies[i];
            if (b->used && i != state.platform)
                targets[count++] = (grab_object_t){b->position.x/(float)PHYS_ONE,
                    b->position.y/(float)PHYS_ONE,0,false};
        }
        const ui_pose_point_t *points = pose->points[largest];
        static const unsigned required[4][10] = {
            {0,5,9,13,17,4,8},{0,5,9,13,17,4,8,12,16,20},{0,5,9,13,17},{4,8}};
        static const unsigned counts[] = {7,10,5,2};
        bool valid = true;
        for (unsigned i = 0; i < counts[rule.mode]; ++i)
            if (points[required[rule.mode][i]].visibility < .5f) valid = false;
        if (valid) {
            bool close, release;
            grab_rule(&rule,points,ui_grab.cls,targets,count,40,false,&close,&release);
            /* Finger separation moves the fingertip cursor before release hysteresis.
             * Keep the last closed-pose position throughout that opening transition. */
            if (closed && !close) {
                state.opening = true;
                hand_x = state.hand.x;
                hand_y = state.hand.y;
            }
            if (closed ? release : close) closed = !closed;
        }
    } else {
        closed = false;
        hand_x = state.hand.x;
        hand_y = state.hand.y;
    }
    /* Scissors rotates the held body in every mode, even when the fingers separate. */
    if (pose->count && state.world.grab.body >= 0 && ui_grab.cls == 2) {
        closed = true;
        state.opening = false;
        hand_x = (int)ui_grab.x;
        hand_y = (int)ui_grab.y;
    }
    tower_input hand = {hand_x,hand_y,ui_grab.cls,
                        closed,ui_grab.lost};
    tower_step(&state,hand);
    unsigned us = (unsigned)((platform_ticks()-started)*1000000/platform_clock_hz());
    if (us > phys_max_us) phys_max_us = us;
}
static void snapshot(void *context, void *destination)
{
    (void)context;
    tower_snapshot_copy(&state,destination);
}
static void report(void *context, unsigned draws, unsigned steps,
                   unsigned late, unsigned mean_us)
{
    (void)context; (void)steps;
    tower_snapshot snap;
    tower_snapshot_copy(&state,&snap);
    char line[192];
    snprintf(line,sizeof line,
        "game name=grablab draw_fps=%u phys_us=%u phys_max_us=%u late=%u bodies=%u awake=%u\r\n",
        draws,mean_us,phys_max_us,late,snap.bodies,snap.awake);
    phys_max_us = 0;
    platform_puts(line);
}
static void run_loop(void)
{
    game_loop_config config = {simulate,snapshot,report,NULL,
        {&snapshots[0],&snapshots[1],&snapshots[2]},sizeof(tower_snapshot)};
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
static void draw(lv_event_t *event)
{
    painted = true;
    lv_layer_t *layer = lv_event_get_layer(event);
    if (loading) return;
    picture(layer,&tower_platform,shown.platform_x,TOWER_PLATFORM_Y,
            TOWER_PLATFORM_W,TOWER_PLATFORM_H,255);
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
                f->width,f->height,(lv_opa_t)b->opacity);
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
            old->frame == now->frame && old->opacity == now->opacity) continue;
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
bool ui_tower_key(uint32_t key)
{
    if (key != LV_KEY_ENTER || loading) return false;
    uint32_t lock = sched_port_lock();
    command = 1;
    sched_port_unlock(lock);
    return true;
}
bool ui_tower_keypad(lv_indev_t *input, uint32_t key)
{
    if (key != LV_KEY_ENTER) return false;
    bool pressed = lv_indev_get_state(input) == LV_INDEV_STATE_PRESSED;
    if (pressed && !key_down) ui_tower_key(key);
    key_down = pressed;
    return true;
}
bool ui_tower_loading(void) { return loading; }
unsigned ui_tower_atlas_bytes(void) { return atlas.bytes; }
void ui_tower_update(void)
{
    if (painted) { game_loop_drawn(); painted = false; }
    if (loading) {
        unsigned kind = atlas.kind;
        while (!(atlas.kinds & (UINT64_C(1)<<kind))) ++kind;
        void *scratch = geo_scratch;
        struct geo_descriptor *descriptors = scratch;
        unsigned first_byte = atlas.bytes;
        sprite_rot_prepare(&atlas,scratch);
        unsigned count = tower_frame_count(kind%2)*2;
        for (unsigned i = 0; i < count; ++i)
            geo_descriptor_pack(&descriptors[i],&atlas.configs[i]);
        engine_dma_clean((uintptr_t)scratch,atlas.source_end);
        uint32_t error = geo_execute(descriptors,SHOWCASE_TOWER_GEO_BASE,count);
        if (error) {
            platform_puts("tower GEO ERR_CODE=");
            platform_put_hex(error);
            platform_puts("\r\n");
            platform_stop();
        }
        engine_dma_invalidate((uintptr_t)scratch+atlas.source_end,
                              atlas.scratch_bytes-atlas.source_end);
        bool done = sprite_rot_finish(&atlas,scratch);
        engine_dma_clean((uintptr_t)storage+first_byte,atlas.bytes-first_byte);
        for (unsigned frame_number = 0; frame_number < tower_frame_count(kind%2);
             ++frame_number) {
            const sprite_frame *f = &atlas.frames[kind][frame_number];
            images[kind][frame_number] = (lv_image_dsc_t){
                .header={.magic=LV_IMAGE_HEADER_MAGIC,.cf=LV_COLOR_FORMAT_ARGB8888,
                    .w=f->width,.h=f->height,.stride=f->width*4},
                .data_size=f->width*f->height*4,.data=(const uint8_t *)f->pixels};
        }
        lv_bar_set_value(load_bar,(int)(atlas.completed*100/atlas.total),LV_ANIM_OFF);
        if (done) {
            char line[128];
            snprintf(line,sizeof line,"game name=grablab event=atlas total_ms=%u\r\n",
                (unsigned)((platform_ticks()-atlas_started)*1000/platform_clock_hz()));
            platform_puts(line);
            atlas_ready = true;
            loading = false;
            memset(&shown,0,sizeof shown);
            shown.held = -1;
            shown.platform_x = TOWER_PLATFORM_X;
            lv_obj_set_hidden(load_panel,true);
            run_loop();
            lv_obj_invalidate(frame);
        }
        return;
    }
    if (!game_loop_read(&next)) return;
    invalidate(&shown,&next);
    shown = next;
}
static void tick(lv_timer_t *t) { (void)t; ui_tower_update(); }
static void deleted(lv_event_t *event)
{
    (void)event;
    game_loop_stop();
    lv_timer_delete(timer);
    /* The atlas and its storage live for the boot, including page re-entry. */
}
static void mode_changed(lv_event_t *event)
{
    static const char *const names[] = {"A 捏合","B 五指聚拢","C 手势分类","D 双指夹取"};
    unsigned mode = lv_buttonmatrix_get_selected_button(lv_event_get_target_obj(event));
    uint32_t lock = sched_port_lock();
    selected_mode = ui_grab.mode = mode;
    closed = false;
    sched_port_unlock(lock);
    lv_label_set_text(mode_text,names[mode]);
}
void ui_page_tower(lv_obj_t *p)
{
    grab_init(&ui_grab);
    ui_settings_apply_grab();
    selected_mode = ui_grab.mode = 0;
    closed = false;
    tower_init(&state,42);
    tower_snapshot_copy(&state,&shown);
    command = phys_max_us = 0;
    painted = key_down = false;
    lv_obj_t *header = ui_camera_layout(p,"抓取实验");
    static const char *const modes[] = {"A","B","C","D",""};
    lv_obj_t *selector = ui_segment(header,modes,selected_mode);
    lv_obj_set_size(selector,220,40);
    lv_obj_add_event_cb(selector,mode_changed,LV_EVENT_VALUE_CHANGED,NULL);
    mode_text = ui_text_label(header,"A 捏合",&sim_font_14,MUTED);
    ui_text_label(header,"点赞：掉落 · 剪刀手：旋转",&sim_font_14,MUTED);
    frame = ui_box(lv_screen_active(),0,0,1280,720,0);
    lv_obj_set_clickable(frame,false);
    lv_obj_set_scrollable(frame,false);
    lv_obj_set_style_bg_opa(frame,89,0);
    lv_obj_set_style_border_width(frame,0,0);
    lv_obj_set_style_radius(frame,0,0);
    lv_obj_move_to_index(frame,0);
    lv_obj_add_event_cb(frame,draw,LV_EVENT_DRAW_MAIN,NULL);
    lv_obj_add_event_cb(frame,deleted,LV_EVENT_DELETE,NULL);
    load_panel = ui_box(lv_screen_active(),360,250,560,160,0x142b40);
    ui_label(load_panel,"正在生成积木旋转帧",30,24,&sim_font_28,0xffffff);
    load_bar = lv_bar_create(load_panel);
    lv_obj_set_pos(load_bar,30,90);
    lv_obj_set_size(load_bar,500,20);
    loading = !atlas_ready;
    lv_obj_set_hidden(load_panel,!loading);
    if (loading) {
        if (!storage) {
#ifdef __riscv
            storage = (uint32_t *)(EDRV32_DDR_BASE+SHOWCASE_TOWER_ROT_BASE);
            geo_scratch = (void *)(EDRV32_DDR_BASE+SHOWCASE_TOWER_GEO_BASE);
#else
            storage = malloc(SHOWCASE_TOWER_ROT_BYTES);
            geo_scratch = malloc(SHOWCASE_TOWER_GEO_BYTES);
#endif
            sprite_source sources[TOWER_KINDS];
            for (unsigned i = 0; i < TOWER_KINDS; ++i)
                sources[i] = (sprite_source){(const uint32_t *)originals[i]->data,
                                            originals[i]->header.w,originals[i]->header.h};
            for (unsigned i = 1; i < TOWER_KINDS; i += 2) images[i][0] = *originals[i];
            atlas_started = platform_ticks();
            sprite_rot_begin(&atlas,sources,(UINT64_C(1)<<TOWER_KINDS)-1,storage);
        }
        lv_bar_set_value(load_bar,(int)(atlas.completed*100/atlas.total),LV_ANIM_OFF);
    } else run_loop();
    timer = lv_timer_create(tick,16,NULL);
}
