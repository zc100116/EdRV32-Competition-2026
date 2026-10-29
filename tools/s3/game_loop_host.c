/* File: game_loop_host.c
 * Spec: Task B3-3b host acceptance; DISP 5.3; SoC 7.3 R3.
 * Description: Run the production entry with FRAME/SWITCH and timing stubs.
 * Clock domain: host, 60 Hz simulated FRAME.
 */
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include "game.h"
#include "game_render.h"
#include "s3_platform.h"

static const void *front;
static unsigned int input_frame;
static unsigned int presents;
static unsigned int stops;
static unsigned int peak_commands;
static uint64_t ticks;
static uint32_t pending_scroll;

uint64_t s3_ticks(void)
{
    return ticks;
}

uint32_t s3_clock_hz(void)
{
    return 60000000u;
}

uint32_t s3_input(void)
{
    ++input_frame;
    switch (input_frame) {
    case 66: return S3_KEY_PAUSE;
    case 68: return S3_KEY_RIGHT;
    case 70: return S3_KEY_JUMP;
    default: return 0;
    }
}

void s3_display_scroll(uint16_t x, uint16_t y)
{
    assert(x <= 3840 && y == 0);
    pending_scroll = x;
}

void s3_display_stop(void)
{
    front = NULL;
    ++stops;
}

void s3_display_begin(const void *l0, uint32_t l0_stride,
                      const void *l1, uint32_t l1_stride)
{
    assert(l0 == game_background() && l0_stride == 10240 && l1_stride == 5120);
    assert(l1 == game_overlay(0));
    assert(front == NULL);
    front = l1;
}

void s3_display_present(const void *l0, uint32_t l0_stride,
                        const void *l1, uint32_t l1_stride)
{
    assert(l0 == NULL && l0_stride == 0 && l1_stride == 5120);
    assert(l1 != front);
    assert(l1 == game_overlay((presents + 1) & 1u));
    assert(pending_scroll == 0);
    front = l1; /* SWITCH grants the old Surface to the next render batch. */
    ++presents;
    ticks = (uint64_t)presents * 1000000u;
}

void s3_rnd_run(const struct rnd_batch *batch)
{
    if (batch->count > peak_commands) {
        peak_commands = batch->count;
    }
    for (size_t i = 0; i < batch->target_count; ++i) {
        const unsigned char *base = batch->targets[i].address;
        const unsigned char *end = base + batch->targets[i].bytes;
        assert((uintptr_t)front < (uintptr_t)base || (uintptr_t)front >= (uintptr_t)end);
    }
    ticks += 12000u; /* 0.200 ms; verifies decimal telemetry arithmetic. */
}

void s3_puts(const char *text)
{
    fputs(text, stdout);
}

void s3_put_u32(uint32_t value)
{
    printf("%u", value);
}

int main(void)
{
    s3_game_run();
    assert(stops == 2 && front == NULL && presents == 69);
    printf("PASS game entry: presents=%u stops=%u peak_commands=%u paused return to UI\n",
           presents, stops, peak_commands);
    return 0;
}
