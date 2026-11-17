/* tower_scenes.h — T-PHYS-BLOCKS §4 host reproduction and capture fixtures.
 * Real full-size geometry, seed 42; ±0.03 rad tilt and 1–5 px placement gaps.
 * Host only, shared by rules regression and native LVGL captures.
 */
#ifndef SHOWCASE_TOWER_SCENES_H
#define SHOWCASE_TOWER_SCENES_H
#include "tower.h"
static void tower_scene(tower_state *s, unsigned scene)
{
    tower_init(s,42);
    if (scene == 0)
        for (int i = 0; i < 5; ++i) tower_spawn(s,0,640,580-80*i);
    if (scene == 1) {
        for (int i = 0; i < 3; ++i) tower_spawn(s,1,640,600-40*i);
        tower_spawn(s,3,580,473);
        tower_spawn(s,3,700,473);
    }
    if (scene == 2) {
        tower_spawn(s,0,480,580);
        tower_spawn(s,0,800,580);
        for (int i = 0; i < 3; ++i) tower_spawn(s,5,560+80*i,572);
    }
    for (int i = 1; i <= 5; ++i) {
        phys_body *b = &s->world.bodies[i];
        phys_body_def d = {.type=PHYS_DYNAMIC,.position=b->position,
            .angle=(i%2 ? 1 : -1)*1966,.material=b->material,.part_count=b->part_count};
        d.position.y -= i*PHYS_ONE;
        for (int k = 0; k < b->part_count; ++k) d.parts[k] = b->parts[k].shape;
        phys_body_remove(&s->world,i);
        phys_body_add(&s->world,&d);
    }
}
#endif
