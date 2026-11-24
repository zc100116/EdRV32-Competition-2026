/* File: soc_test.c
 * Spec: disp 2.4/2.7; gpu-soc 8.2; aud 2/4; sys-subsys 2.5.
 * Description: Check media composition, frame handoff, audio and PLIC semantics.
 * Clock domain: deterministic host test.
 */
#include "pc_soc.h"
#include "mmio.h"
#include "plic.h"
#include "aud.h"
#include "regs/disp_gpu_regs.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#define D(name) EDRV32_DISP_GPU_##name
#define DW(name, value) mmio_write32(EDRV32_DISP_BASE + D(name##_OFFSET), value)
#define DR(name) mmio_read32(EDRV32_DISP_BASE + D(name##_OFFSET))
#define AW(name, value) mmio_write32(EDRV32_AUD_BASE + EDRV32_AUD_##name##_OFFSET, value)
#define AR(name) mmio_read32(EDRV32_AUD_BASE + EDRV32_AUD_##name##_OFFSET)
static unsigned delivered, audio_count;
static int16_t audio_samples[4096];
void pc_frontend_audio(const int16_t *samples, uint32_t frames)
{
    assert(audio_count + frames * 2 <= sizeof(audio_samples) / sizeof(audio_samples[0]));
    memcpy(audio_samples + audio_count, samples, frames * 4);
    audio_count += frames * 2;
}
static void interrupt(void) { ++delivered; }
static unsigned div255(unsigned x) { unsigned t = x + 128; return (t + (t >> 8)) >> 8; }
static uint32_t rgb565(uint16_t color)
{
    unsigned r = color >> 11, g = (color >> 5) & 63, b = color & 31;
    return ((r * 8 + r / 4) << 16) | ((g * 4 + g / 16) << 8) | (b * 8 + b / 4);
}
static void composition_pixels(void)
{
    uint16_t *background = pc_soc_alloc(1296 * 722 * 2,4096);
    uint32_t *foreground = pc_soc_alloc(40 * 24 * 4,4096);
    for (unsigned i = 0; i < 1296 * 722; ++i) background[i] = (uint16_t)(i * 317);
    for (unsigned i = 0; i < 40 * 24; ++i) foreground[i] = i * 0x9e3779b9u;
    /* All layer combinations, both scales, clipped L1 and opacity endpoints. */
    for (unsigned mode = 0; mode < 8; ++mode) {
        unsigned scale = mode & 4 ? 2 : 1;
        for (unsigned variant = 0; variant < 3; ++variant) {
            unsigned opacity = variant == 0 ? 0 : variant == 1 ? 128 : 255;
            unsigned lx = variant == 2 ? 1272 : 8;
            unsigned ly = variant == 2 ? 719 : 5;
            DW(CTRL, D(CTRL_SOFT_RST_MASK));
            DW(NEXT_BASE,ddr_physical(background));
            DW(STRIDE,2592);
            DW(L0_SCROLL,16u | (2u << D(L0_SCROLL_SCROLL_Y_POS)));
            DW(L1_NEXT_BASE,ddr_physical(foreground));
            DW(L1_STRIDE,160);
            DW(L1_SIZE,40u | (24u << D(L1_SIZE_H_POS)));
            DW(L1_POS,lx | (ly << D(L1_POS_Y_POS)));
            DW(L1_OPA,opacity);
            DW(LAYER_CTRL,mode);
            DW(CTRL,D(CTRL_ENABLE_MASK));
            pc_soc_vsync(0);
            for (unsigned y = 0; y < 720; ++y) for (unsigned x = 0; x < 1280; ++x) {
                uint32_t base = mode & 1 ? rgb565(background[(y / scale + 2) * 1296 +
                                                            x / scale + 16]) : 0;
                uint32_t fg = 0;
                if ((mode & 2) && x >= lx && x-lx < 40 && y >= ly && y-ly < 24)
                    fg = foreground[(y-ly)*40+x-lx];
                unsigned alpha = div255((fg >> 24)*opacity);
                uint32_t expected = 0;
                for (unsigned shift = 0; shift < 24; shift += 8)
                    expected |= div255(((fg >> shift) & 255)*alpha +
                                       ((base >> shift) & 255)*(255-alpha)) << shift;
                if (pc_soc_pixels()[y*1280+x] != expected) {
                    fprintf(stderr,"DISP mode=%u variant=%u x=%u y=%u got=%06x expected=%06x\n",
                            mode,variant,x,y,pc_soc_pixels()[y*1280+x],expected);
                    assert(pc_soc_pixels()[y*1280+x] == expected);
                }
            }
        }
    }
}
int main(void)
{
    pc_soc_init();
    pc_soc_interrupt(interrupt);
    uint16_t *l0 = pc_soc_alloc(2560 * 722, 4096);
    assert((uintptr_t)l0 % 4096 == 0 && ddr_physical(l0) % 4096 == 0);
    uint16_t *other = pc_soc_alloc(2560 * 722, 4096);
    uint32_t *l1 = pc_soc_alloc(512, 4096);
    for (unsigned i = 0; i < 1280 * 722; ++i) l0[i] = (i / 1280) & 1 ? 0x07e0 : 0xf800;
    for (unsigned i = 0; i < 128; ++i) l1[i] = 0x80ffffff;
    DW(NEXT_BASE, ddr_physical(l0));
    DW(CTRL, D(CTRL_ENABLE_MASK));
    pc_soc_vsync(0);
    assert(DR(FRAME_CNT) == 1 && DR(CUR_BASE) == ddr_physical(l0));
    assert(!(DR(IRQ_STAT) & D(IRQ_STAT_SWITCH_MASK)));
    assert(pc_soc_pixels()[0] == 0xff0000 && pc_soc_pixels()[1280] == 0x00ff00);
    DW(L0_SCROLL, 1u << D(L0_SCROLL_SCROLL_Y_POS));
    DW(LAYER_CTRL, D(LAYER_CTRL_L0_EN_MASK) | D(LAYER_CTRL_L0_X2_MASK));
    pc_soc_vsync(0);
    assert(pc_soc_pixels()[0] == 0x00ff00 && pc_soc_pixels()[1280] == 0x00ff00);
    assert(pc_soc_pixels()[2560] == 0xff0000);
    DW(L1_NEXT_BASE, ddr_physical(l1));
    DW(L1_SIZE, 8u | (1u << D(L1_SIZE_H_POS)));
    DW(L1_STRIDE, 32);
    DW(L1_OPA, 128);
    DW(LAYER_CTRL, D(LAYER_CTRL_L0_EN_MASK) | D(LAYER_CTRL_L1_EN_MASK));
    pc_soc_vsync(0);
    unsigned alpha = div255(128 * 128);
    unsigned blend = div255(alpha * 255);
    assert(pc_soc_pixels()[0] == ((blend << 16) | (255 << 8) | blend));
    assert(pc_soc_pixels()[8] == 0x00ff00);
    DW(NEXT_BASE, ddr_physical(other));
    assert(DR(CUR_BASE) == ddr_physical(l0));
    pc_soc_vsync(0);
    assert(DR(CUR_BASE) == ddr_physical(other));
    assert(DR(REL_BASE) == ddr_physical(l0));
    assert(DR(IRQ_STAT) & D(IRQ_STAT_SWITCH_MASK));
    DW(IRQ_STAT, UINT32_MAX);
    DW(LAYER_CTRL, 0);
    pc_soc_vsync(0);
    assert(DR(REL_BASE) == ddr_physical(other));
    assert(DR(L1_REL_BASE) == ddr_physical(l1));
    assert((DR(IRQ_STAT) & (D(IRQ_STAT_SWITCH_MASK) | D(IRQ_STAT_SWITCH1_MASK))) ==
           (D(IRQ_STAT_SWITCH_MASK) | D(IRQ_STAT_SWITCH1_MASK)));
    DW(DESC_BASE, 1234);
    assert(DR(DESC_BASE) == 0);
    DW(CTRL, D(CTRL_SOFT_RST_MASK));
    assert(DR(FRAME_CNT) == 0 && DR(STATUS) == D(STATUS_IDLE_MASK));
    DW(NEXT_BASE, 64u * 1024u * 1024u);
    DW(CTRL, D(CTRL_ENABLE_MASK));
    pc_soc_vsync(0);
    assert(DR(ERR_CODE) == 2 && (DR(STATUS) & D(STATUS_ERROR_MASK)));
    DW(IRQ_STAT, UINT32_MAX);
    assert(!(DR(STATUS) & D(STATUS_ERROR_MASK)) && DR(ERR_CODE) == 2);
    DW(CTRL, D(CTRL_SOFT_RST_MASK));
    uint32_t *samples = pc_soc_alloc(4096, 512);
    assert((uintptr_t)samples % 512 == 0 && ddr_physical(samples) % 512 == 0);
    for (unsigned i = 0; i < 1024; ++i) samples[i] = 0x1234fedc;
    AW(RING_BASE, ddr_physical(samples));
    AW(RING_SIZE, 4096);
    AW(WR_PTR, 2048);
    AW(LOW_LEVEL, 1024);
    AW(IRQ_EN, EDRV32_AUD_IRQ_EN_RX_NOTIFY0_MASK);
    plic_set_enable((1u << EDRV32_PLIC_SOURCE_AUD) | (1u << EDRV32_PLIC_SOURCE_DISP));
    plic_set_priority(EDRV32_PLIC_SOURCE_AUD, 2);
    plic_set_priority(EDRV32_PLIC_SOURCE_DISP, 2);
    AW(CTRL, EDRV32_AUD_CTRL_ENABLE_MASK);
    assert(AR(RD_PTR) == 2048 && (AR(IRQ_STAT) & EDRV32_AUD_IRQ_STAT_RX_NOTIFY0_MASK));
    DW(IRQ_EN, D(IRQ_EN_FRAME_MASK));
    DW(CTRL, D(CTRL_ENABLE_MASK));
    pc_soc_vsync(1);
    assert(delivered && audio_samples[0] == (int16_t)0xfedc && audio_samples[1] == 0x1234);
    assert(plic_claim() == EDRV32_PLIC_SOURCE_AUD);
    assert(plic_claim() == EDRV32_PLIC_SOURCE_DISP);
    assert(plic_claim() == 0);
    plic_complete(EDRV32_PLIC_SOURCE_AUD);
    assert(plic_claim() == EDRV32_PLIC_SOURCE_AUD); /* Still-high level re-pends. */
    AW(IRQ_STAT, UINT32_MAX);
    plic_complete(EDRV32_PLIC_SOURCE_AUD);
    assert(plic_claim() == 0);
    DW(IRQ_STAT, UINT32_MAX);
    plic_complete(EDRV32_PLIC_SOURCE_DISP);
    plic_set_threshold(2);
    AW(WR_PTR, 3072);
    pc_soc_vsync(520);
    assert(AR(UNDERRUN_CNT) == 0);
    AW(CTRL, 0);
    assert(AR(RD_PTR) == 0);
    AW(WR_PTR, 32);
    AW(CTRL, 1);
    audio_count = 0;
    pc_soc_vsync(16);
    assert(AR(UNDERRUN_CNT) == 8);
    assert(audio_samples[16] == 0 && audio_samples[17] == 0);
    assert(plic_claim() == 0); /* Priority equal to threshold cannot claim. */
    AW(CTRL, 0);
    unsigned underruns = AR(UNDERRUN_CNT);
    pc_soc_vsync(16);
    assert(AR(UNDERRUN_CNT) == underruns);
    AW(RING_BASE, 64u * 1024u * 1024u);
    AW(WR_PTR, 32);
    AW(CTRL, 1);
    assert(AR(ERR_CODE) == 1 && (AR(STATUS) & EDRV32_AUD_STATUS_ERROR_MASK));
    AW(IRQ_STAT, UINT32_MAX);
    assert(!(AR(STATUS) & EDRV32_AUD_STATUS_ERROR_MASK) && AR(ERR_CODE) == 1);
    composition_pixels();
    pc_soc_destroy();
    puts("PASS DISP all-pixel layer/opacity/clip/X2/scroll/switch, "
         "AUD FIFO/LOW/underrun, PLIC gateway");
    return 0;
}
