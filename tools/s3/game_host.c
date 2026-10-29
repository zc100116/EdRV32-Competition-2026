/* File: game_host.c
 * Spec: Task B3-3b host acceptance; rnd 2.5/5.4; SoC 7.3 R3.
 * Description: Fixed input tests of production logic and real encoder batch capture.
 * Clock domain: host.
 */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "game_logic.h"
#include "game_render.h"
#include "s3_platform.h"

extern const char __executable_start;
static unsigned int batch_index;
static uint64_t ticks;
static const void *scanning;
static uint32_t overlay_base;
static uint32_t background_base;

uint32_t __wrap_rnd_physical(const void *address)
{
    return (uint32_t)((uintptr_t)address - (uintptr_t)&__executable_start);
}

uint64_t s3_ticks(void)
{
    return ++ticks;
}

void s3_rnd_run(const struct rnd_batch *batch)
{
    for (size_t i = 0; i < batch->target_count; ++i) {
        assert(batch->targets[i].address != scanning);
    }
    char path[128];
    snprintf(path, sizeof(path), "build/s3/game/batch%u.cmd", batch_index);
    FILE *file = fopen(path, "wb");
    assert(file);
    assert(fwrite(batch->commands, 64, batch->count, file) == batch->count);
    assert(fclose(file) == 0);
    if (batch_index == 0) {
        file = fopen("build/s3/game/memory.bin", "wb+");
        assert(file);
        for (size_t i = 0; i < batch->source_count; ++i) {
            const struct rnd_range *range = &batch->sources[i];
            assert(fseek(file, __wrap_rnd_physical(range->address), SEEK_SET) == 0);
            assert(fwrite(range->address, 1, range->bytes, file) == range->bytes);
        }
        assert(fclose(file) == 0);
    }
    printf("batch=%u commands=%u\n", batch_index, batch->count);
    ++batch_index;
}

static void step_frames(struct game_state *g, unsigned int frames, uint32_t keys)
{
    for (unsigned int i = 0; i < frames; ++i) {
        game_step(g, keys);
    }
}

static void test_logic(void)
{
    struct game_state g;
    game_reset(&g);
    step_frames(&g, 120, S3_KEY_RIGHT);
    assert(g.mode == GAME_DEAD && g.deaths == 1 && g.score >= 200);
    int death_x = g.x;
    game_step(&g, S3_KEY_JUMP);
    assert(g.mode == GAME_PLAY && g.x == 80 && g.score == 0 && g.deaths == 1);
    game_step(&g, 0);
    game_step(&g, S3_KEY_PAUSE);
    assert(g.mode == GAME_PAUSE);
    int paused_x = g.x;
    unsigned int paused_frame = g.frame;
    step_frames(&g, 30, S3_KEY_RIGHT);
    assert(g.x == paused_x && g.frame == paused_frame);
    game_step(&g, 0);
    game_step(&g, S3_KEY_PAUSE);
    assert(g.mode == GAME_PLAY);
    game_reset(&g);
    /* Exact frame/key sequence; no position writes, teleportation or adaptive input. */
    static const unsigned int jumps[] = {92, 208, 324, 436, 539, 642, 724};
    for (unsigned int frame = 1; frame <= 840; ++frame) {
        uint32_t keys = S3_KEY_RIGHT;
        for (unsigned int j = 0; j < sizeof(jumps) / sizeof(jumps[0]); ++j) {
            if (frame == jumps[j]) {
                keys |= S3_KEY_JUMP;
            }
        }
        game_step(&g, keys);
        if (g.mode == GAME_DEAD) {
            fprintf(stderr, "FAIL route frame=%u x=%d y=%d score=%u\n",
                    frame, g.x, g.y, g.score);
            exit(1);
        }
    }
    assert(g.mode == GAME_WON && g.score >= 1500 && g.camera == 3840);
    printf("PASS logic: death_x=%d restart/deaths=1 pause/freeze win_x=%d score=%u\n",
           death_x, g.x, g.score);
    game_step(&g, S3_KEY_PAUSE);
    assert(g.mode == GAME_EXIT);
    game_reset(&g);
    game_step(&g, S3_KEY_PAUSE);
    game_step(&g, S3_KEY_RIGHT);
    game_step(&g, S3_KEY_JUMP);
    assert(g.mode == GAME_EXIT);
    puts("PASS menus: victory return and pause return");
    game_reset(&g);
    step_frames(&g, 50, S3_KEY_LEFT);
    assert(g.x == 0 && g.y == 576 && g.grounded);
    game_reset(&g);
    for (unsigned int frame = 1; frame <= 370; ++frame) {
        uint32_t keys = S3_KEY_RIGHT;
        if (frame == 92 || frame == 208) {
            keys |= S3_KEY_JUMP;
        }
        game_step(&g, keys);
    }
    assert(g.mode == GAME_PLAY && g.x == 2080 && g.grounded);
    game_step(&g, S3_KEY_RIGHT | S3_KEY_JUMP);
    step_frames(&g, 40, S3_KEY_RIGHT);
    assert(g.x > 2208 && g.grounded);
    puts("PASS terrain: left boundary, wall stop, jump onto and beyond raised platform");
    game_reset(&g);
    for (unsigned int frame = 1; frame <= 260; ++frame) {
        game_step(&g, S3_KEY_RIGHT | (frame == 92 ? S3_KEY_JUMP : 0));
    }
    assert(g.mode == GAME_DEAD && g.y > GAME_HEIGHT && g.x > 1400 && g.x < 1504);
    puts("PASS pit: fixed input falls into gap and dies");
    game_reset(&g);
    for (unsigned int frame = 1; frame <= 500; ++frame) {
        uint32_t keys = S3_KEY_RIGHT;
        if (frame == 92 || frame == 208 || frame == 324) {
            keys |= S3_KEY_JUMP;
        }
        game_step(&g, keys);
    }
    assert(g.mode == GAME_DEAD && g.x > 2650 && g.x < 2930 && g.y == 576);
    puts("PASS patrol: fixed input reaches enemy side collision and dies");
}

static void capture_frame(void)
{
    struct game_state g;
    game_reset(&g);
    game_render_init();
    game_render_frame(&g, 0);
    scanning = game_overlay(0);
    step_frames(&g, 58, S3_KEY_RIGHT);
    game_render_frame(&g, 1);
    scanning = game_overlay(1); /* Simulated SWITCH releases buffer 0. */
    step_frames(&g, 1, S3_KEY_LEFT);
    game_render_frame(&g, 0);
    overlay_base = __wrap_rnd_physical(game_overlay(0));
    background_base = __wrap_rnd_physical(game_background());
    FILE *file = fopen("build/s3/game/view.txt", "w");
    assert(file);
    fprintf(file, "%u %u %d\n", background_base, overlay_base, g.camera);
    assert(fclose(file) == 0);
    puts("PASS render capture: static TILEMAP and actual L1 batches, SWITCH ownership");
}

int main(void)
{
    test_logic();
    capture_frame();
    return 0;
}
