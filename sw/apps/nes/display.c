/* File: display.c
 * Spec: rnd-spec 5.4; disp-spec 5.3; SoC 7.3 R3; Task B3-4b step 2.
 * Description: Snapshot a free frame for RND, then release L0 buffers only on SWITCH.
 * Clock domain: clk_sys CPU; polling RND/DISP status in clk_mem.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "cache.h"
#include "disp.h"
#include "display.h"

_Alignas(4096) static uint8_t surfaces[2][NES_SCREEN_BYTES];
_Alignas(64) static uint8_t dma_pixels[256 * 240];
_Alignas(64) static uint32_t dma_palette[256];
_Alignas(64) static struct rnd_command command;
static struct rnd_range sources[2];
static unsigned back = 1;
static enum { DISPLAY_FREE, DISPLAY_RENDERING, DISPLAY_READY, DISPLAY_SWITCH } phase;

static void display_poll(void)
{
    struct engine_event event = engine_poll(ENGINE_DISP);
    if (event.irq & EDRV32_DISP_IRQ_STAT_ERROR_MASK) {
        fprintf(stderr, "NES DISP ERR_CODE=%lu\n", (unsigned long)event.error);
        exit(1);
    }
    if (phase == DISPLAY_SWITCH && disp_switched(DISP_L0)) {
        /* disp 5.3: only REL_BASE captured with SWITCH can be reused by RND. */
        back = surface_ring_slot(disp_released(DISP_L0), rnd_physical(surfaces),
                                 NES_SCREEN_BYTES);
        engine_irq_clear(ENGINE_DISP, EDRV32_DISP_IRQ_STAT_SWITCH_MASK);
        ++nes_shown;
        phase = DISPLAY_FREE;
    }
    if (phase == DISPLAY_RENDERING) {
        uint32_t irq = mmio_read32(EDRV32_RND_BASE + EDRV32_RND_IRQ_STAT_OFFSET);
        uint32_t status = mmio_read32(EDRV32_RND_BASE + EDRV32_RND_STATUS_OFFSET);
        if (irq & EDRV32_RND_IRQ_STAT_ERROR_MASK) {
            fprintf(stderr, "NES RND ERR_CODE=%lu CUR_DESC=%lu\n",
                    (unsigned long)mmio_read32(EDRV32_RND_BASE + EDRV32_RND_ERR_CODE_OFFSET),
                    (unsigned long)mmio_read32(EDRV32_RND_BASE + EDRV32_RND_CUR_DESC_OFFSET));
            exit(1);
        }
        if (!(irq & EDRV32_RND_IRQ_STAT_DONE_MASK) || (status & EDRV32_RND_STATUS_BUSY_MASK))
            return;
        /* DONE and drained bus observed: rnd_wait only collects/acknowledges this batch. */
        (void)rnd_wait();
        phase = DISPLAY_READY;
        engine_irq_clear(ENGINE_DISP, EDRV32_DISP_IRQ_STAT_FRAME_MASK);
        return;
    }
    if (phase == DISPLAY_READY && (event.irq & EDRV32_DISP_IRQ_STAT_FRAME_MASK)) {
        engine_irq_clear(ENGINE_DISP, EDRV32_DISP_IRQ_STAT_FRAME_MASK);
        disp_submit(DISP_L0, rnd_physical(surfaces[back]), NES_SCREEN_STRIDE);
        phase = DISPLAY_SWITCH;
    }
}

void nes_display_init(void)
{
    /* R3: stop any BIOS display and wait for its reads before touching the surfaces. */
    engine_control(ENGINE_DISP, 0);
    while (!(engine_poll(ENGINE_DISP).status & EDRV32_DISP_STATUS_IDLE_MASK)) {
    }
    disp_layer_enable(DISP_L1, 0);
    memset(surfaces, 0, sizeof(surfaces));
    cache_clean_invalidate((uintptr_t)surfaces, sizeof(surfaces));
    engine_irq_clear(ENGINE_DISP, engine_poll(ENGINE_DISP).irq);
    disp_l0_scroll(0, 0);
    disp_submit(DISP_L0, rnd_physical(surfaces[0]), NES_SCREEN_STRIDE);
    disp_layer_enable(DISP_L0, 1);
    engine_control(ENGINE_DISP, EDRV32_DISP_CTRL_ENABLE_MASK);
    sources[0] = (struct rnd_range){dma_pixels, sizeof(dma_pixels)};
    sources[1] = (struct rnd_range){dma_palette, sizeof(dma_palette)};
}

void nes_display_frame(const uint8_t *pixels, const struct nes_rgb *palette)
{
    display_poll();
    if (phase != DISPLAY_FREE)
        return;
    /* RND owns these snapshots until DONE; the next emulated frame may change its inputs. */
    memcpy(dma_pixels, pixels, sizeof(dma_pixels));
    int changed = nes_palette_update(dma_palette, palette);
    nes_blit_encode(&command, rnd_physical(surfaces[back]), rnd_physical(dma_pixels),
                    rnd_physical(dma_palette));
    /* No CPU access to RND targets: ownership goes straight to DISP after DONE.
     * Initial CPU zeros were cleaned/invalidated above; targets stay outside CPU cache.
     */
    struct rnd_batch batch = {&command, 1, sources, changed ? 2u : 1u, NULL, 0};
    rnd_submit(&batch);
    phase = DISPLAY_RENDERING;
}
