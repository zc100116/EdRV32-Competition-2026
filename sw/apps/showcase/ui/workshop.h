/* workshop.h — block workshop task §§2–6; integer-only world and input contracts.
 * Application task owns simulation; GUI receives value snapshots at 60 Hz.
 */
#ifndef SHOWCASE_WORKSHOP_H
#define SHOWCASE_WORKSHOP_H
#include <stdbool.h>
#include <stdint.h>
enum { WS_COLS=20, WS_ROWS=11, WS_CELL=48, WS_X=160, WS_Y=152,
       WS_BOTTOM=680, WS_BLOCKS=220, WS_ANIMALS=4, WS_PARTICLES=512, WS_HZ=60 };
typedef enum {
    WS_HAND, WS_PICK, WS_GRASS, WS_DIRT, WS_STONE, WS_GRAVEL, WS_SAND,
    WS_PLANK, WS_LOG, WS_STONEBRICK, WS_BRICK, WS_METAL, WS_ICE, WS_GLASS,
    WS_LEAVES, WS_LAMP, WS_WINDOW, WS_DOOR, WS_BEAM, WS_PILLAR,
    WS_WOOD_SLOPE, WS_BRICK_SLOPE, WS_ITEMS
} ws_item;
typedef enum { WS_DAY, WS_DUSK, WS_NIGHT } ws_sky;
typedef enum { WS_IDLE, WS_WALK, WS_RUN, WS_LIFT, WS_STUN, WS_FALL, WS_JUMP } ws_action;
typedef struct { int x,y,cls; bool closed; unsigned lost; } ws_input;
/* x/y identify the leftmost bottom cell; orientation 0/1 is horizontal/vertical.
 * Slope orientation follows bl, br, tr, tl. Positions/velocities use half pixels.
 */
typedef struct {
    bool used;
    uint8_t item, orientation;
    int16_t x,y, group;
} ws_block;
typedef struct { int offset, velocity; } ws_fall;
typedef struct {
    int x,y,velocity, direction, timer, phase, frame, jump_x,jump_y;
    uint8_t species, action;
} ws_animal;
typedef struct { int x,y,vx,vy,life; uint32_t color; uint8_t kind; } ws_particle;
typedef struct {
    ws_block blocks[WS_BLOCKS];
    ws_fall falls[WS_BLOCKS];
    int16_t grid[WS_ROWS][WS_COLS];
    ws_animal animals[WS_ANIMALS];
    ws_particle particles[WS_PARTICLES];
    ws_input hand;
    uint32_t random, ticks;
    unsigned animal_count, scene, sky, selected, orientation, places, breaks, moves;
    unsigned ok_ticks, mine_ticks, return_ticks, menu_hold;
    int held, lifted, mining, last_cell, inventory_hover, menu_hover;
    int origin_x,origin_y, return_x,return_y;
    bool selection_grab;
    bool menu, inventory, ok_latched, scissors, was_closed, preview;
    int preview_x,preview_y;
} workshop_state;
typedef struct { int x,y,w,h; } ws_rect;
typedef struct {
    ws_block blocks[WS_BLOCKS];
    int16_t offset[WS_BLOCKS];
    ws_animal animals[WS_ANIMALS];
    ws_particle particles[WS_PARTICLES];
    ws_input hand;
    unsigned ticks, animal_count, scene, sky, selected, orientation;
    unsigned places,breaks,moves, hold, crack;
    int held,lifted,mining, held_x,held_y, preview_x,preview_y, hover;
    bool menu,inventory,preview,returning;
} workshop_snapshot;
extern const char *const ws_names[WS_ITEMS];
extern const char *const ws_scene_names[3];
extern const uint32_t ws_colors[WS_ITEMS];
void workshop_init(workshop_state *s);
void workshop_scene(workshop_state *s, unsigned scene);
void workshop_reconnect(workshop_state *s);
void workshop_step(workshop_state *s, ws_input input);
void workshop_key(workshop_state *s, unsigned key); /* 1 next, 2 prev, 3 OK, 4 back */
int workshop_add(workshop_state *s, unsigned item, unsigned orientation, int x,int y);
void workshop_remove(workshop_state *s, int id);
bool workshop_fits(const workshop_state *s, unsigned item,unsigned orientation,int x,int y);
void workshop_shape(unsigned item,unsigned orientation,int *w,int *h);
unsigned workshop_hardness(unsigned item);
unsigned workshop_rotate(unsigned item,unsigned orientation);
void workshop_snapshot_copy(const workshop_state *s, workshop_snapshot *out);
ws_rect workshop_block_rect(const workshop_snapshot *s,int id);
/* Same dirty rectangles drive LVGL and host measurements. */
void workshop_dirty(const workshop_snapshot *a,const workshop_snapshot *b,
                    void (*emit)(ws_rect,void *),void *context);
#endif
