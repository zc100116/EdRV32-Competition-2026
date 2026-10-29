/* File: display_host.c
 * Spec: Task B3-4b step 2; SoC 7.3 R3; rnd-spec 5.4; disp-spec 5.3.
 * Description: Exercise real drivers with delayed DONE/FRAME/SWITCH and DMA snapshots.
 * Clock domain: host test events.
 */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "display.h"
#include "disp.h"

unsigned nes_shown;
static uint32_t rnd_regs[256];
static uint32_t disp_regs[256];
static unsigned submissions;
static unsigned palette_cleans;
static const uint8_t *dma_snapshot;
static const uint32_t *palette_snapshot;
static const struct rnd_command *last_command;
static uint8_t pixels[256 * 240];
static struct nes_rgb palette[256];

uint32_t mmio_read32(uintptr_t address)
{
    if (address >= EDRV32_RND_BASE && address < EDRV32_RND_BASE + sizeof(rnd_regs))
        return rnd_regs[(address - EDRV32_RND_BASE) / 4];
    assert(address >= EDRV32_DISP_BASE && address < EDRV32_DISP_BASE + sizeof(disp_regs));
    return disp_regs[(address - EDRV32_DISP_BASE) / 4];
}

void mmio_write32(uintptr_t address, uint32_t value)
{
    if (address >= EDRV32_RND_BASE && address < EDRV32_RND_BASE + sizeof(rnd_regs)) {
        unsigned offset = (unsigned)(address - EDRV32_RND_BASE);
        if (offset == EDRV32_RND_IRQ_STAT_OFFSET)
            rnd_regs[offset / 4] &= ~value;
        else
            rnd_regs[offset / 4] = value;
        if (offset == EDRV32_RND_DOORBELL_OFFSET) {
            ++submissions;
            rnd_regs[EDRV32_RND_STATUS_OFFSET / 4] = EDRV32_RND_STATUS_BUSY_MASK;
            assert(last_command->word[1] != disp_current(DISP_L0));
        }
        return;
    }
    assert(address >= EDRV32_DISP_BASE && address < EDRV32_DISP_BASE + sizeof(disp_regs));
    unsigned offset = (unsigned)(address - EDRV32_DISP_BASE);
    if (offset == EDRV32_DISP_IRQ_STAT_OFFSET)
        disp_regs[offset / 4] &= ~value;
    else
        disp_regs[offset / 4] = value;
}

void cache_clean(uintptr_t address, uint32_t bytes)
{
    assert(address % 64 == 0);
    if (bytes == sizeof(struct rnd_command))
        last_command = (const struct rnd_command *)address;
    else if (bytes == sizeof(pixels))
        dma_snapshot = (const uint8_t *)address;
    else {
        assert(bytes == 256 * sizeof(uint32_t));
        palette_snapshot = (const uint32_t *)address;
        ++palette_cleans;
    }
}

void cache_clean_invalidate(uintptr_t address, uint32_t bytes)
{
    assert(address % 4096 == 0 && bytes == 2 * NES_SCREEN_BYTES);
    const uint8_t *surfaces = (const uint8_t *)address;
    for (unsigned i = 0; i < bytes; ++i)
        assert(surfaces[i] == 0);
}

void cache_invalidate(uintptr_t address, uint32_t bytes)
{
    (void)address;
    (void)bytes;
    assert(0 && "RND targets are never CPU-accessed after startup");
}

static void render_complete(void)
{
    rnd_regs[EDRV32_RND_STATUS_OFFSET / 4] = 0;
    rnd_regs[EDRV32_RND_IRQ_STAT_OFFSET / 4] = EDRV32_RND_IRQ_STAT_DONE_MASK;
    nes_display_frame(pixels, palette);
}

static void submit_at_frame(void)
{
    disp_regs[EDRV32_DISP_IRQ_STAT_OFFSET / 4] = EDRV32_DISP_IRQ_STAT_FRAME_MASK;
    nes_display_frame(pixels, palette);
}

static uint32_t switch_frame(void)
{
    uint32_t released = disp_current(DISP_L0);
    disp_regs[EDRV32_DISP_REL_BASE_OFFSET / 4] = released;
    disp_regs[EDRV32_DISP_CUR_BASE_OFFSET / 4] =
        disp_regs[EDRV32_DISP_NEXT_BASE_OFFSET / 4];
    disp_regs[EDRV32_DISP_IRQ_STAT_OFFSET / 4] =
        EDRV32_DISP_IRQ_STAT_FRAME_MASK | EDRV32_DISP_IRQ_STAT_SWITCH_MASK;
    nes_display_frame(pixels, palette);
    return released;
}

int main(void)
{
    disp_regs[EDRV32_DISP_STATUS_OFFSET / 4] = EDRV32_DISP_STATUS_IDLE_MASK;
    disp_regs[EDRV32_DISP_LAYER_CTRL_OFFSET / 4] = 3;
    nes_display_init();
    assert(disp_regs[EDRV32_DISP_LAYER_CTRL_OFFSET / 4] == 1);
    disp_regs[EDRV32_DISP_CUR_BASE_OFFSET / 4] =
        disp_regs[EDRV32_DISP_NEXT_BASE_OFFSET / 4];
    memset(pixels, 7, sizeof(pixels));
    palette[7] = (struct nes_rgb){12, 34, 56};
    nes_display_frame(pixels, palette);
    assert(submissions == 1 && palette_cleans == 1);
    assert(palette_snapshot[7] == 0xff0c2238);
    memset(pixels, 9, sizeof(pixels));
    nes_display_frame(pixels, palette);
    assert(submissions == 1 && dma_snapshot[0] == 7);
    assert(dma_snapshot[sizeof(pixels) - 1] == 7);
    /* DONE may be visible before bus drain: never enter the driver's blocking wait yet. */
    rnd_regs[EDRV32_RND_IRQ_STAT_OFFSET / 4] = EDRV32_RND_IRQ_STAT_DONE_MASK;
    nes_display_frame(pixels, palette);
    assert(submissions == 1 && nes_shown == 0);
    render_complete();
    nes_display_frame(pixels, palette);
    assert(submissions == 1);
    submit_at_frame();
    nes_display_frame(pixels, palette);
    assert(submissions == 1 && nes_shown == 0);
    uint32_t released = switch_frame();
    assert(submissions == 2 && nes_shown == 1);
    assert(last_command->word[1] == released && palette_cleans == 1);
    assert(dma_snapshot[0] == 9);
    palette[7].g = 99;
    nes_display_frame(pixels, palette);
    assert(palette_snapshot[7] == 0xff0c2238 && palette_cleans == 1);
    render_complete();
    submit_at_frame();
    released = switch_frame();
    assert(submissions == 3 && nes_shown == 2 && palette_cleans == 2);
    assert(last_command->word[1] == released && palette_snapshot[7] == 0xff0c6338);
    puts("PASS NES ownership: busy skips, snapshots, palette changes, DONE/FRAME/SWITCH");
    return 0;
}
