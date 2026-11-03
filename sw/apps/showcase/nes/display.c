/* display.c: showcase design 4.4; IRQ-driven RND/DISP ownership.
 * Snapshots survive simulation frames; SWITCH alone releases an old surface.
 * Clock domain: CPU clk_sys; media engines clk_mem.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "cache.h"
#include "disp.h"
#include "display.h"
#include "../board/overlay.h"

_Alignas(4096) static uint8_t surfaces[2][NES_SCREEN_BYTES] __attribute__((section(".noinit")));
_Alignas(64) static uint8_t dma_pixels[256 * 240];
_Alignas(64) static uint32_t dma_palette[256];
_Alignas(64) static struct rnd_command command_storage;
static struct rnd_command *command;
static struct rnd_range sources[2];
static unsigned back;
static volatile enum { DISPLAY_STARTING, DISPLAY_FREE, DISPLAY_RENDERING,
                       DISPLAY_SWITCH, DISPLAY_STOPPED } phase;
static volatile uint32_t rnd_error;
static volatile uint32_t disp_error;

void nes_display_rnd_irq(const struct rnd_result *result, void *context)
{
    (void)context;
    rnd_error = result->error;
    if (result->irq & EDRV32_RND_IRQ_STAT_ERROR_MASK)
        rnd_error = result->error ? result->error : UINT32_MAX;
    if (!rnd_error && phase == DISPLAY_RENDERING) {
        /* DISP 5.3: stride/geometry are fixed for this owner. Updating the
         * single NEXT_BASE word needs no extra FRAME rendezvous. */
        phase = DISPLAY_SWITCH;
        mmio_write32(EDRV32_DISP_BASE + EDRV32_DISP_NEXT_BASE_OFFSET,
                     rnd_physical(surfaces[back]));
    }
}

void nes_display_disp_irq(const struct engine_event *event, void *context)
{
    (void)context;
    board_overlay_irq(event->irq);
    /* DISP 5.3: first enabled FRAME establishes CUR_BASE without SWITCH. */
    if (phase == DISPLAY_STARTING && (event->irq & EDRV32_DISP_IRQ_STAT_FRAME_MASK))
        phase = DISPLAY_FREE;
    if (event->irq & EDRV32_DISP_IRQ_STAT_ERROR_MASK)
        disp_error = event->error ? event->error : UINT32_MAX;
    if (phase == DISPLAY_SWITCH && (event->irq & EDRV32_DISP_IRQ_STAT_SWITCH_MASK)) {
        back = surface_ring_slot(disp_released(DISP_L0), rnd_physical(surfaces),
                                 NES_SCREEN_BYTES);
        ++nes_shown;
        phase = DISPLAY_FREE;
    }
}

void nes_display_check(void)
{
    if (rnd_error || disp_error) {
        fprintf(stderr, "NES media error RND=%lu DISP=%lu\n",
                (unsigned long)rnd_error, (unsigned long)disp_error);
        exit(1);
    }
}

void nes_display_init(void)
{
    /* Application STARTING state already observed stopped DISP IDLE. */
    disp_layer_enable(DISP_L1, 0);
    memset(surfaces, 0, sizeof(surfaces));
    cache_clean_invalidate((uintptr_t)surfaces, sizeof(surfaces));
    engine_irq_clear(ENGINE_DISP, engine_poll(ENGINE_DISP).irq);
    disp_l0_scroll(0, 0);
    disp_submit(DISP_L0, rnd_physical(surfaces[0]), NES_SCREEN_STRIDE);
    disp_layer_enable(DISP_L0, 1);
    back = 1;
    rnd_error = 0;
    disp_error = 0;
    phase = DISPLAY_STARTING;
    cache_clean_invalidate((uintptr_t)&command_storage, sizeof(command_storage));
    command = (struct rnd_command *)((uintptr_t)&command_storage - EDRV32_DDR_BASE +
                                     EDRV32_DDR_UNCACHED_BASE);
    sources[0] = (struct rnd_range){dma_pixels, sizeof(dma_pixels)};
    sources[1] = (struct rnd_range){dma_palette, sizeof(dma_palette)};
}

void nes_display_frame(const uint8_t *pixels, const struct nes_rgb *palette)
{
    if (phase != DISPLAY_FREE)
        return;
    memcpy(dma_pixels, pixels, sizeof(dma_pixels));
    int changed = nes_palette_update(dma_palette, palette);
    nes_blit_encode(command, rnd_physical(surfaces[back]), rnd_physical(dma_pixels),
                    rnd_physical(dma_palette));
    struct rnd_batch batch = {command, 1, sources, changed ? 2u : 1u, NULL, 0};
    phase = DISPLAY_RENDERING;
    rnd_submit(&batch);
}

void nes_display_stop(void)
{
    phase = DISPLAY_STOPPED;
    mmio_write32(EDRV32_RND_BASE + EDRV32_RND_IRQ_EN_OFFSET, 0);
    mmio_write32(EDRV32_RND_BASE + EDRV32_RND_CTRL_OFFSET, EDRV32_RND_CTRL_ABORT_MASK);
    engine_control(ENGINE_DISP, 0);
}

int nes_display_idle(void)
{
    return (engine_poll(ENGINE_DISP).status & EDRV32_DISP_STATUS_IDLE_MASK) &&
           !(mmio_read32(EDRV32_RND_BASE + EDRV32_RND_STATUS_OFFSET) &
             EDRV32_RND_STATUS_BUSY_MASK);
}
