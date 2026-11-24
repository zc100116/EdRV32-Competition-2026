/* File: preview.c
 * Spec: ember_isles E1/E2 acceptance; GPU 2.8-2.10.
 * Description: Real-driver/PC-GPU presentation capture, full-pool CPU preparation,
 * simulation immutability and paused hardware-particle verification.
 * Clock domain: virtual 60 Hz host frontend.
 */
#include "gfx2d/gfx.h"
#include "ui/ui.h"
#include "plat.h"
#include "pc_soc.h"
#include "png.h"
#include "mmio.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static struct ember_sim sim;
static unsigned frame;
static struct ember_sim before;
uint32_t pc_frontend_wait(void) { return 800; }
uint32_t pc_frontend_keys(void) { return 0; }
uint32_t pc_frontend_millis(void) { return frame * 1000 / 60; }
void pc_frontend_audio(const int16_t *p, uint32_t n) { (void)p; (void)n; }
static void prepare(const struct ember_ui_state *ui)
{
    before = sim;
    ember_gfx_prepare(&sim, 60, ui);
    if (memcmp(&sim, &before, sizeof(sim))) {
        fputs("FAIL: prepare modified simulation\n", stderr);
        exit(1);
    }
}
static void full_pools(void)
{
    sim.phase = EMBER_PLAY;
    sim.player.x = 1280 * EMBER_Q;
    sim.player.y = 720 * EMBER_Q;
    sim.world_width = 2560 * EMBER_Q;
    sim.world_height = 1440 * EMBER_Q;
    sim.safe_right = sim.world_width;
    sim.safe_bottom = sim.world_height;
    sim.player.hp = sim.player.max_hp = 180;
    sim.player.next_xp = 100;
    sim.player.xp = 1000000;
    for (unsigned i = 0; i < EMBER_ENEMIES; ++i) {
        sim.enemies[i] = (struct ember_enemy){.alive=1,.burn=1,.kind=i%3,
            .x=1280*EMBER_Q,.y=720*EMBER_Q};
        sim.pickups[i] = (struct ember_pickup){.alive=1,
            .x=1280*EMBER_Q,.y=720*EMBER_Q};
    }
    for (unsigned i = 0; i < EMBER_SHOTS; ++i)
        sim.shots[i] = (struct ember_shot){.alive=1,.kind=i%7,.radius=20,
            .x=1280*EMBER_Q,.y=720*EMBER_Q};
    sim.obstacle_count = EMBER_OBSTACLES;
    for (unsigned i = 0; i < EMBER_OBSTACLES; ++i)
        sim.obstacles[i] = (struct ember_obstacle){1280*EMBER_Q,720*EMBER_Q,24};
    sim.events.count = EMBER_EVENTS;
    for (unsigned i = 0; i < EMBER_EVENTS; ++i)
        sim.events.item[i] = (struct ember_event){2,0,1280*EMBER_Q,720*EMBER_Q};
    const struct ember_ui_state ui = {.show_perf=1};
    for (sim.frame = 1; sim.frame < 5; ++sim.frame) prepare(&ui);
    memset(&sim, 0, sizeof(sim));
}
int main(void)
{
    plat_init();
    ember_gfx_init();
    full_pools();
    sim.world_width = 2560 * EMBER_Q;
    sim.world_height = 1440 * EMBER_Q;
    sim.safe_right = sim.world_width;
    sim.safe_bottom = sim.world_height;
    sim.player.x = 1280 * EMBER_Q;
    sim.player.y = 720 * EMBER_Q;
    sim.player.hp = 142;
    sim.player.max_hp = 180;
    sim.player.next_xp = 100;
    sim.player.xp = 64;
    sim.player.level = 3;
    sim.player.charge = 78;
    sim.wave = 2;
    sim.alive_count = 3;
    sim.shot_count = 4;
    sim.choices[0] = (struct ember_choice){0, 1, 0};
    sim.choices[1] = (struct ember_choice){1, 2, 0};
    sim.choices[2] = (struct ember_choice){2, 0, 0};
    sim.selected = 1;
    for (unsigned i = 0; i < 3; ++i) {
        sim.enemies[i] = (struct ember_enemy){.alive=1,.kind=i,.flash=i==2,
            .x=(1200+(int)i*80)*EMBER_Q,.y=(650+(int)i*30)*EMBER_Q};
        sim.shots[i] = (struct ember_shot){.alive=1,.kind=i,.radius=30,
            .x=(1100+(int)i*130)*EMBER_Q,.y=780*EMBER_Q};
        sim.pickups[i] = (struct ember_pickup){.alive=1,
            .x=(1230+(int)i*70)*EMBER_Q,.y=830*EMBER_Q};
    }
    sim.shots[3] = (struct ember_shot){.alive=1,.kind=3,.radius=12,
        .x=1450*EMBER_Q,.y=750*EMBER_Q};
    sim.obstacle_count = 1;
    sim.obstacles[0] = (struct ember_obstacle){1120*EMBER_Q,680*EMBER_Q,24};
    const char *names[] = {"menu","play","upgrade","won","lost","paused","coast"};
    unsigned previous_alive = 0;
    for (frame = 0; frame < 7; ++frame) {
        sim.frame = frame;
        sim.phase = frame <= 4 ? (enum ember_phase)frame : EMBER_PLAY;
        sim.paused = frame == 5;
        if (frame == 6) { sim.player.x = 100*EMBER_Q; sim.player.y = 100*EMBER_Q; }
        sim.events.count = frame == 1 ? 2 : 0;
        sim.events.item[0] = (struct ember_event){1,127,1280*EMBER_Q,680*EMBER_Q};
        sim.events.item[1] = (struct ember_event){2,0,1340*EMBER_Q,750*EMBER_Q};
        struct ember_ui_state ui = {.show_perf=frame==1};
        prepare(&ui);
        ember_gfx_submit(frame);
        unsigned alive = mmio_read32(EDRV32_GPU_BASE + EDRV32_GPU_OBJ_ALIVE_COUNT_OFFSET);
        if ((frame == 1 && !alive) || (frame == 5 && alive != previous_alive)) {
            fputs("FAIL: GPU particle emission/pause\n", stderr);
            return 1;
        }
        previous_alive = alive;
        plat_wait_vsync();
        char path[200];
        snprintf(path,sizeof(path),"build/ember_isles/gfx-%s.png",names[frame]);
        pc_png_write(path,pc_soc_pixels());
        puts(path);
    }
    pc_soc_destroy();
    puts("PASS: full pools, immutable sim, GPU particles, pause and seven captures");
}
