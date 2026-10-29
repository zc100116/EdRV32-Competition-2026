/* File: game.c
 * Spec: design rnd-disp 3.5/5.2; DISP 5.3; SoC 7.3 R3.
 * Description: UI-callable game with FRAME pacing, SWITCH ownership and timing telemetry.
 * Clock domain: clk_sys CPU; shared platform handles media interrupts.
 */
#include "game.h"
#include "game_logic.h"
#include "game_render.h"
#include "../s3_platform.h"

/* Shared platform extension confirmed by coordinator; implemented by platform owner. */
extern void s3_display_scroll(uint16_t x, uint16_t y);

static void print_average_ms(uint64_t ticks, unsigned int frames)
{
    uint32_t us = (uint32_t)(ticks * 1000000u / s3_clock_hz() / frames);
    s3_put_u32(us / 1000u);
    s3_puts(".");
    s3_put_u32(us / 100u % 10u);
    s3_put_u32(us / 10u % 10u);
    s3_put_u32(us % 10u);
}

void s3_game_run(void)
{
    static struct game_state game;
    game_reset(&game);
    s3_display_stop();
    game_render_init();
    game_render_frame(&game, 0);
    s3_display_begin(game_background(), GAME_WIDTH * 2,
                     game_overlay(0), GAME_SCREEN * 4);
    unsigned int front = 0;
    unsigned int frames = 0;
    uint64_t cpu_ticks = 0;
    uint64_t rnd_ticks = 0;
    uint64_t report_start = s3_ticks();
    while (game.mode != GAME_EXIT) {
        uint64_t start = s3_ticks();
        game_step(&game, s3_input());
        if (game.mode == GAME_EXIT) {
            break;
        }
        unsigned int back = front ^ 1u;
        game_render_frame(&game, back);
        uint64_t after_rnd = s3_ticks();
        rnd_ticks += game_render_ticks();
        cpu_ticks += after_rnd - start - game_render_ticks();
        s3_display_scroll((uint16_t)game.camera, 0);
        /* present returns at the next FRAME after SWITCH; old front is now free.
         * An additional wait_frame would halve the update rate to 30 Hz.
         */
        s3_display_present(NULL, 0, game_overlay(back), GAME_SCREEN * 4);
        front = back;
        ++frames;
        uint64_t now = s3_ticks();
        if (now - report_start >= s3_clock_hz()) {
            s3_puts("GAME fps=");
            s3_put_u32((uint32_t)((uint64_t)frames * s3_clock_hz() / (now - report_start)));
            s3_puts(" rnd_ms=");
            print_average_ms(rnd_ticks, frames);
            s3_puts(" cpu_ms=");
            print_average_ms(cpu_ticks, frames);
            s3_puts("\n");
            frames = 0;
            cpu_ticks = 0;
            rnd_ticks = 0;
            report_start = now;
        }
    }
    s3_display_stop();
}
