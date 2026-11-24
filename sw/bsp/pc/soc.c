/* File: soc.c
 * Spec: PC design 4.1/4.3; disp 2.4/2.7; aud 2-6; sys-subsys 2.5.
 * Description: Functional media register dispatch, frame composition, audio FIFO
 * and level-triggered interrupt gateway over a contiguous 64 MiB DDR image.
 * Clock domain: host main loop; sample and frame clocks advanced by frontend.
 */
#include "pc_soc.h"
#include "mmio.h"
#include "gpu_emu.h"
#include "plic.h"
#include "regs/disp_gpu_regs.h"
#include "regs/aud_regs.h"
#include "regs/gpu_regs.h"
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define D(name) EDRV32_DISP_GPU_##name
#define A(name) EDRV32_AUD_##name
#define DR(name) disp[D(name##_OFFSET) / 4u]
#define AR(name) aud[A(name##_OFFSET) / 4u]
enum { DDR_BYTES = 64 * 1024 * 1024, REG_WORDS = EDRV32_APB_SLOT_SIZE / 4 };
static uint8_t *ddr;
static void *ddr_allocation;
static size_t allocated;
static struct gpu_emu *gpu;
struct gpu_emu_usage pc_soc_gpu_usage(void) { return gpu_emu_usage(gpu); }
static uint16_t game_keys;
static struct plat_pointer_state game_pointer;
void pc_soc_game_input(uint16_t keys, struct plat_pointer_state pointer)
{
    game_keys = keys;
    game_pointer = pointer;
}
uint32_t pc_soc_game_keys(void) { return game_keys; }
struct plat_pointer_state pc_soc_pointer(void) { return game_pointer; }
static uint32_t disp[REG_WORDS];
static uint32_t aud[REG_WORDS];
static uint32_t pixels[1280 * 720];
static uint32_t layers;
static uint32_t fifo[512];
static unsigned fifo_head, fifo_count;
static uint32_t priority[16], enables, threshold, pending, claimed;
static void (*interrupt_handler)(void);
static FILE *trace;
static int trace_pending;
static void trace_snapshot(void);
static const char *trace_directory;
struct reg_info { uint32_t offset, reset, mask; unsigned writable; };
static const struct reg_info disp_gpu_registers[] = {
    {D(ID_OFFSET), D(ID_RESET),
        D(ID_TYPE_MASK) | D(ID_VERSION_MASK), 0 },
    {D(CTRL_OFFSET), D(CTRL_RESET),
        D(CTRL_ENABLE_MASK) | D(CTRL_START_MASK) | D(CTRL_ABORT_MASK) | D(CTRL_SOFT_RST_MASK), 1 },
    {D(STATUS_OFFSET), D(STATUS_RESET),
        D(STATUS_BUSY_MASK) | D(STATUS_IDLE_MASK) | D(STATUS_ERROR_MASK), 0 },
    {D(IRQ_EN_OFFSET), D(IRQ_EN_RESET),
        D(IRQ_EN_DONE_MASK) |
        D(IRQ_EN_ERROR_MASK) |
        D(IRQ_EN_FRAME_MASK) |
        D(IRQ_EN_SWITCH_MASK) |
        D(IRQ_EN_SWITCH1_MASK), 1 },
    {D(IRQ_STAT_OFFSET), D(IRQ_STAT_RESET),
        D(IRQ_STAT_DONE_MASK) |
        D(IRQ_STAT_ERROR_MASK) |
        D(IRQ_STAT_FRAME_MASK) |
        D(IRQ_STAT_SWITCH_MASK) |
        D(IRQ_STAT_SWITCH1_MASK), 0 },
    {D(ERR_CODE_OFFSET), D(ERR_CODE_RESET),
        UINT32_MAX, 0 },
    {D(DESC_BASE_OFFSET), D(DESC_BASE_RESET),
        UINT32_MAX, 1 },
    {D(DESC_COUNT_OFFSET), D(DESC_COUNT_RESET),
        UINT32_MAX, 1 },
    {D(DOORBELL_OFFSET), D(DOORBELL_RESET),
        UINT32_MAX, 0 },
    {D(DONE_COUNT_OFFSET), D(DONE_COUNT_RESET),
        UINT32_MAX, 0 },
    {D(NEXT_BASE_OFFSET), D(NEXT_BASE_RESET),
        D(NEXT_BASE_VALUE_MASK), 1 },
    {D(STRIDE_OFFSET), D(STRIDE_RESET),
        D(STRIDE_VALUE_MASK), 1 },
    {D(CUR_BASE_OFFSET), D(CUR_BASE_RESET),
        UINT32_MAX, 0 },
    {D(REL_BASE_OFFSET), D(REL_BASE_RESET),
        UINT32_MAX, 0 },
    {D(FRAME_CNT_OFFSET), D(FRAME_CNT_RESET),
        D(FRAME_CNT_VALUE_MASK), 0 },
    {D(L0_SCROLL_OFFSET), D(L0_SCROLL_RESET),
        D(L0_SCROLL_SCROLL_X_MASK) | D(L0_SCROLL_SCROLL_Y_MASK), 1 },
    {D(LAYER_CTRL_OFFSET), D(LAYER_CTRL_RESET),
        D(LAYER_CTRL_L0_EN_MASK) | D(LAYER_CTRL_L1_EN_MASK) | D(LAYER_CTRL_L0_X2_MASK), 1 },
    {D(L1_NEXT_BASE_OFFSET), D(L1_NEXT_BASE_RESET),
        D(L1_NEXT_BASE_VALUE_MASK), 1 },
    {D(L1_STRIDE_OFFSET), D(L1_STRIDE_RESET),
        D(L1_STRIDE_VALUE_MASK), 1 },
    {D(L1_POS_OFFSET), D(L1_POS_RESET),
        D(L1_POS_X_MASK) | D(L1_POS_Y_MASK), 1 },
    {D(L1_SIZE_OFFSET), D(L1_SIZE_RESET),
        D(L1_SIZE_W_MASK) | D(L1_SIZE_H_MASK), 1 },
    {D(L1_OPA_OFFSET), D(L1_OPA_RESET),
        D(L1_OPA_OPA_MASK), 1 },
    {D(L1_CUR_BASE_OFFSET), D(L1_CUR_BASE_RESET),
        UINT32_MAX, 0 },
    {D(L1_REL_BASE_OFFSET), D(L1_REL_BASE_RESET),
        UINT32_MAX, 0 },
};
static const struct reg_info aud_registers[] = {
    {A(ID_OFFSET), A(ID_RESET),
        A(ID_TYPE_MASK) | A(ID_VERSION_MASK), 0 },
    {A(CTRL_OFFSET), A(CTRL_RESET),
        A(CTRL_ENABLE_MASK) | A(CTRL_START_MASK) | A(CTRL_ABORT_MASK) | A(CTRL_SOFT_RST_MASK), 1 },
    {A(STATUS_OFFSET), A(STATUS_RESET),
        A(STATUS_BUSY_MASK) | A(STATUS_IDLE_MASK) | A(STATUS_ERROR_MASK), 0 },
    {A(IRQ_EN_OFFSET), A(IRQ_EN_RESET),
        A(IRQ_EN_DONE_MASK) |
        A(IRQ_EN_ERROR_MASK) |
        A(IRQ_EN_FRAME_MASK) |
        A(IRQ_EN_RX_NOTIFY0_MASK) |
        A(IRQ_EN_RX_NOTIFY1_MASK) |
        A(IRQ_EN_RX_NOTIFY2_MASK) |
        A(IRQ_EN_RX_NOTIFY3_MASK), 1 },
    {A(IRQ_STAT_OFFSET), A(IRQ_STAT_RESET),
        A(IRQ_STAT_DONE_MASK) |
        A(IRQ_STAT_ERROR_MASK) |
        A(IRQ_STAT_FRAME_MASK) |
        A(IRQ_STAT_RX_NOTIFY0_MASK) |
        A(IRQ_STAT_RX_NOTIFY1_MASK) |
        A(IRQ_STAT_RX_NOTIFY2_MASK) |
        A(IRQ_STAT_RX_NOTIFY3_MASK), 0 },
    {A(ERR_CODE_OFFSET), A(ERR_CODE_RESET),
        UINT32_MAX, 0 },
    {A(DESC_BASE_OFFSET), A(DESC_BASE_RESET),
        A(DESC_BASE_VALUE_MASK), 1 },
    {A(DESC_COUNT_OFFSET), A(DESC_COUNT_RESET),
        A(DESC_COUNT_VALUE_MASK), 1 },
    {A(DOORBELL_OFFSET), A(DOORBELL_RESET),
        UINT32_MAX, 0 },
    {A(DONE_COUNT_OFFSET), A(DONE_COUNT_RESET),
        UINT32_MAX, 0 },
    {A(RING_BASE_OFFSET), A(RING_BASE_RESET),
        A(RING_BASE_ADDR_MASK), 1 },
    {A(RING_SIZE_OFFSET), A(RING_SIZE_RESET),
        A(RING_SIZE_VALUE_MASK), 1 },
    {A(WR_PTR_OFFSET), A(WR_PTR_RESET),
        A(WR_PTR_VALUE_MASK), 1 },
    {A(RD_PTR_OFFSET), A(RD_PTR_RESET),
        A(RD_PTR_VALUE_MASK), 0 },
    {A(LOW_LEVEL_OFFSET), A(LOW_LEVEL_RESET),
        A(LOW_LEVEL_VALUE_MASK), 1 },
    {A(UNDERRUN_CNT_OFFSET), A(UNDERRUN_CNT_RESET),
        A(UNDERRUN_CNT_VALUE_MASK), 0 },
};
static void reset_regs(uint32_t *regs, const struct reg_info *info, size_t count)
{
    memset(regs, 0, REG_WORDS * sizeof(*regs));
    for (size_t i = 0; i < count; ++i) regs[info[i].offset / 4] = info[i].reset;
}
#define RESET(block, table) reset_regs(block, table, sizeof(table) / sizeof(table[0]))
static void write_shadow(uint32_t *regs, const struct reg_info *info, size_t count,
                         uint32_t offset, uint32_t value)
{
    /* Both media blocks leave the common command-list registers unused. */
    if (offset == A(DESC_BASE_OFFSET) || offset == A(DESC_COUNT_OFFSET) ||
        offset == A(DOORBELL_OFFSET)) return;
    for (size_t i = 0; i < count; ++i) {
        if (info[i].offset == offset && info[i].writable) {
            regs[offset / 4] = value & info[i].mask;
            return;
        }
    }
}
#define SHADOW(block, table, offset, value) \
    write_shadow(block, table, sizeof(table) / sizeof(table[0]), offset, value)
static _Noreturn void bad_address(uintptr_t address)
{
    fprintf(stderr, "PC SoC unmapped address 0x%" PRIxPTR "\n", address);
    abort();
}
uint32_t ddr_physical(const void *address)
{
    uintptr_t value = (uintptr_t)address;
    if (value < (uintptr_t)ddr || value >= (uintptr_t)ddr + DDR_BYTES) {
        fprintf(stderr, "PC pointer outside DDR: %p\n", address);
        abort();
    }
    return (uint32_t)(value - (uintptr_t)ddr);
}
void *pc_soc_alloc(size_t bytes, size_t alignment)
{
    allocated = (allocated + alignment - 1) & ~(alignment - 1);
    if (bytes > DDR_BYTES - allocated) {
        fprintf(stderr, "PC DDR allocation exhausted: %zu bytes\n", bytes);
        abort();
    }
    void *result = ddr + allocated;
    allocated += bytes;
    return result;
}
void pc_soc_init(void)
{
    /* Page alignment also aligns host pointers for the Surface/DMA contracts. */
    ddr_allocation = calloc(1, DDR_BYTES + 4095);
    if (!ddr_allocation) { perror("allocate PC DDR"); abort(); }
    ddr = (uint8_t *)(((uintptr_t)ddr_allocation + 4095) & ~(uintptr_t)4095);
    gpu = gpu_emu_create(ddr, DDR_BYTES);
    RESET(disp, disp_gpu_registers);
    RESET(aud, aud_registers);
}
void pc_soc_destroy(void)
{
    gpu_emu_destroy(gpu);
    free(ddr_allocation);
}
void pc_soc_interrupt(void (*handler)(void)) { interrupt_handler = handler; }
static void gateway(void)
{
    uint32_t levels = 0;
    if (DR(IRQ_STAT) & DR(IRQ_EN)) levels |= 1u << EDRV32_PLIC_SOURCE_DISP;
    if (AR(IRQ_STAT) & AR(IRQ_EN)) levels |= 1u << EDRV32_PLIC_SOURCE_AUD;
    if (gpu_emu_irq(gpu)) levels |= 1u << EDRV32_PLIC_SOURCE_GPU;
    pending |= levels & ~claimed;
}
static unsigned best_source(void)
{
    gateway();
    unsigned best = 0;
    for (unsigned i = 1; i <= PLIC_SOURCE_COUNT; ++i) {
        if ((pending & enables & (1u << i)) && priority[i] > threshold &&
            (best == 0 || priority[i] > priority[best])) best = i;
    }
    return best;
}
static uint32_t plic_read(uint32_t offset)
{
    if (offset < 4 * (PLIC_SOURCE_COUNT + 1)) return priority[offset / 4];
    if (offset == PLIC_ENABLE) return enables;
    if (offset == PLIC_THRESHOLD) return threshold;
    if (offset == PLIC_PENDING) { gateway(); return pending; }
    if (offset == PLIC_CLAIM) {
        unsigned source = best_source();
        if (source) { pending &= ~(1u << source); claimed |= 1u << source; }
        return source;
    }
    return 0;
}
static void plic_write(uint32_t offset, uint32_t value)
{
    if (offset && offset < 4 * (PLIC_SOURCE_COUNT + 1))
        priority[offset / 4] = value & PLIC_PRIORITY_MASK;
    else if (offset == PLIC_ENABLE) enables = value & PLIC_SOURCE_MASK;
    else if (offset == PLIC_THRESHOLD) threshold = value & PLIC_THRESHOLD_MASK;
    else if (offset == PLIC_CLAIM && value > 0 && value <= PLIC_SOURCE_COUNT)
        claimed &= ~(1u << value);
}
static uint32_t available(void)
{
    return AR(RING_SIZE) ? (AR(WR_PTR) + AR(RING_SIZE) - AR(RD_PTR)) % AR(RING_SIZE) : 0;
}
static void aud_prefetch(void)
{
    if (!(AR(CTRL) & A(CTRL_ENABLE_MASK)) || AR(ERR_CODE)) return;
    uint32_t avail = available();
    while (avail && fifo_count <= 504) {
        uint32_t bytes = 4 * (512 - fifo_count);
        if (bytes > 512) bytes = 512;
        if (bytes > avail) bytes = avail;
        if (bytes > AR(RING_SIZE) - AR(RD_PTR)) bytes = AR(RING_SIZE) - AR(RD_PTR);
        uint32_t address = AR(RING_BASE) + AR(RD_PTR);
        if (bytes > 4096 - (address & 4095)) bytes = 4096 - (address & 4095);
        bytes &= ~31u;
        if (!bytes) break;
        if ((uint64_t)address + bytes > DDR_BYTES) {
            AR(ERR_CODE) = 1;
            AR(IRQ_STAT) |= A(IRQ_STAT_ERROR_MASK);
            break;
        }
        for (unsigned i = 0; i < bytes / 4; ++i) {
            memcpy(&fifo[(fifo_head + fifo_count) % 512], ddr + address + i * 4, 4);
            ++fifo_count;
        }
        AR(RD_PTR) = (AR(RD_PTR) + bytes) % AR(RING_SIZE);
        uint32_t next = available();
        if (avail >= AR(LOW_LEVEL) && next < AR(LOW_LEVEL))
            AR(IRQ_STAT) |= A(IRQ_STAT_RX_NOTIFY0_MASK);
        avail = next;
    }
}
static void audio_advance(uint32_t frames)
{
    int16_t samples[256 * 2];
    while (frames) {
        unsigned count = frames > 256 ? 256 : frames;
        for (unsigned i = 0; i < count; ++i) {
            uint32_t sample = 0;
            if (AR(CTRL) & A(CTRL_ENABLE_MASK)) {
                aud_prefetch();
                if (fifo_count) {
                    sample = fifo[fifo_head];
                    fifo_head = (fifo_head + 1) % 512;
                    --fifo_count;
                } else if (AR(UNDERRUN_CNT) != UINT32_MAX) ++AR(UNDERRUN_CNT);
            }
            samples[2 * i] = (int16_t)sample;
            samples[2 * i + 1] = (int16_t)(sample >> 16);
            gateway();
            if (best_source()) interrupt_handler();
        }
        pc_frontend_audio(samples, count);
        frames -= count;
    }
}
static void aud_write_reg(uint32_t offset, uint32_t value)
{
    if (offset == A(IRQ_EN_OFFSET))
        AR(IRQ_EN) = value & (A(IRQ_EN_ERROR_MASK) | A(IRQ_EN_RX_NOTIFY0_MASK));
    else if (offset == A(IRQ_STAT_OFFSET)) AR(IRQ_STAT) &= ~value;
    else if (offset == A(CTRL_OFFSET)) {
        uint32_t previous = AR(CTRL);
        AR(CTRL) = value & A(CTRL_ENABLE_MASK);
        if (value & A(CTRL_ABORT_MASK)) AR(CTRL) = 0;
        if ((previous & A(CTRL_ENABLE_MASK)) && !AR(CTRL)) {
            fifo_head = fifo_count = 0;
            AR(RD_PTR) = 0;
        }
        if (value & A(CTRL_SOFT_RST_MASK)) {
            RESET(aud, aud_registers);
            fifo_head = fifo_count = 0;
        }
    } else if ((offset != A(RING_BASE_OFFSET) && offset != A(RING_SIZE_OFFSET)) ||
               !(AR(CTRL) & A(CTRL_ENABLE_MASK))) {
        SHADOW(aud, aud_registers, offset, value);
    }
    aud_prefetch();
}
static unsigned div255(unsigned value)
{
    unsigned t = value + 128;
    return (t + (t >> 8)) >> 8;
}
static uint32_t expand565(uint16_t value)
{
    unsigned r = value >> 11, g = (value >> 5) & 63, b = value & 31;
    return ((r << 3 | r >> 2) << 16) | ((g << 2 | g >> 4) << 8) | (b << 3 | b >> 2);
}
static void display_frame(void)
{
    if (!(DR(CTRL) & D(CTRL_ENABLE_MASK))) {
        memset(pixels, 0, sizeof(pixels));
        return;
    }
    unsigned next = DR(LAYER_CTRL);
    const uint32_t enabled[] = {D(LAYER_CTRL_L0_EN_MASK), D(LAYER_CTRL_L1_EN_MASK)};
    const uint32_t bases[] = {D(NEXT_BASE_OFFSET), D(L1_NEXT_BASE_OFFSET)};
    const uint32_t current[] = {D(CUR_BASE_OFFSET), D(L1_CUR_BASE_OFFSET)};
    const uint32_t released[] = {D(REL_BASE_OFFSET), D(L1_REL_BASE_OFFSET)};
    const uint32_t switched[] = {D(IRQ_STAT_SWITCH_MASK), D(IRQ_STAT_SWITCH1_MASK)};
    for (unsigned i = 0; i < 2; ++i) {
        if ((layers & enabled[i]) && (!(next & enabled[i]) ||
            disp[bases[i] / 4] != disp[current[i] / 4])) {
            disp[released[i] / 4] = disp[current[i] / 4];
            DR(IRQ_STAT) |= switched[i];
        }
        if (next & enabled[i]) disp[current[i] / 4] = disp[bases[i] / 4];
    }
    layers = next;
    ++DR(FRAME_CNT);
    ++disp[D(PERF_OFFSET(0)) / 4];
    DR(DONE_COUNT) = DR(FRAME_CNT);
    DR(IRQ_STAT) |= D(IRQ_STAT_FRAME_MASK);
    unsigned scale = (layers & D(LAYER_CTRL_L0_X2_MASK)) ? 2 : 1;
    unsigned sx = DR(L0_SCROLL) & D(L0_SCROLL_SCROLL_X_MASK);
    unsigned sy = (DR(L0_SCROLL) & D(L0_SCROLL_SCROLL_Y_MASK)) >> D(L0_SCROLL_SCROLL_Y_POS);
    unsigned lx = DR(L1_POS) & D(L1_POS_X_MASK);
    unsigned ly = (DR(L1_POS) & D(L1_POS_Y_MASK)) >> D(L1_POS_Y_POS);
    unsigned lw = DR(L1_SIZE) & D(L1_SIZE_W_MASK);
    unsigned lh = (DR(L1_SIZE) & D(L1_SIZE_H_MASK)) >> D(L1_SIZE_H_POS);
    /* L0 is opaque. Expand each source pixel once and replicate X2 rows. */
    if (layers & D(LAYER_CTRL_L0_EN_MASK)) {
        for (unsigned y = 0; y < 720; y += scale) {
            uint64_t row = (uint64_t)DR(CUR_BASE) + (sy + y / scale) * DR(STRIDE) + 2 * sx;
            uint32_t *out = pixels + y * 1280;
            unsigned width = 1280 / scale;
            unsigned valid = row >= DDR_BYTES ? 0 :
                (DDR_BYTES - row) / 2 < width ? (unsigned)((DDR_BYTES - row) / 2) : width;
            const uint8_t *source = ddr + (valid ? row : 0);
            if (scale == 2) {
                for (unsigned x = 0; x < valid; ++x) {
                    uint16_t value;
                    memcpy(&value, source + 2 * x, 2);
                    uint32_t color = expand565(value);
                    out[2 * x] = color;
                    out[2 * x + 1] = color;
                }
            } else {
                for (unsigned x = 0; x < valid; ++x) {
                    uint16_t value;
                    memcpy(&value, source + 2 * x, 2);
                    out[x] = expand565(value);
                }
            }
            if (valid < width) {
                DR(ERR_CODE) = 2;
                DR(IRQ_STAT) |= D(IRQ_STAT_ERROR_MASK);
                memset(out + valid * scale, 0, (width - valid) * scale * sizeof(*out));
            }
            if (scale == 2) memcpy(out + 1280, out, 1280 * sizeof(*out));
        }
    } else memset(pixels, 0, sizeof(pixels));
    if (!(layers & D(LAYER_CTRL_L1_EN_MASK))) return;
    unsigned right = lx + lw < 1280 ? lx + lw : 1280;
    unsigned bottom = ly + lh < 720 ? ly + lh : 720;
    for (unsigned y = ly; y < bottom; ++y) {
        uint64_t row = (uint64_t)DR(L1_CUR_BASE) + (y - ly) * DR(L1_STRIDE);
        for (unsigned x = lx; x < right; ++x) {
            uint64_t address = row + 4 * (x - lx);
            uint32_t foreground = 0;
            if (address + 4 > DDR_BYTES) {
                DR(ERR_CODE) = 2;
                DR(IRQ_STAT) |= D(IRQ_STAT_ERROR_MASK);
            } else memcpy(&foreground, ddr + address, 4);
            unsigned alpha = div255((foreground >> 24) * DR(L1_OPA));
            if (!alpha) continue;
            uint32_t *out = pixels + y * 1280 + x;
            if (alpha == 255) { *out = foreground & 0xffffff; continue; }
            uint32_t output = 0;
            for (unsigned shift = 0; shift < 24; shift += 8) {
                unsigned f = (foreground >> shift) & 255;
                unsigned b = (*out >> shift) & 255;
                output |= div255(alpha * f + (255 - alpha) * b) << shift;
            }
            *out = output;
        }
    }
}
void pc_soc_vsync(uint32_t audio_frames)
{
    audio_advance(audio_frames);
    display_frame();
    if (best_source()) interrupt_handler();
}
const uint32_t *pc_soc_pixels(void) { return pixels; }
uint32_t mmio_read32(uintptr_t address)
{
    if (address >= EDRV32_GPU_BASE && address < EDRV32_GPU_BASE + EDRV32_APB_SLOT_SIZE)
        return gpu_emu_read(gpu, (uint32_t)(address - EDRV32_GPU_BASE));
    if (address >= EDRV32_DISP_BASE && address < EDRV32_DISP_BASE + EDRV32_APB_SLOT_SIZE) {
        uint32_t offset = (uint32_t)(address - EDRV32_DISP_BASE);
        if (offset == D(STATUS_OFFSET)) return (DR(CTRL) ? D(STATUS_BUSY_MASK) :
            D(STATUS_IDLE_MASK)) |
            ((DR(IRQ_STAT) & D(IRQ_STAT_ERROR_MASK)) ? D(STATUS_ERROR_MASK) : 0);
        return disp[offset / 4];
    }
    if (address >= EDRV32_AUD_BASE && address < EDRV32_AUD_BASE + EDRV32_APB_SLOT_SIZE) {
        uint32_t offset = (uint32_t)(address - EDRV32_AUD_BASE);
        if (offset == A(STATUS_OFFSET)) return (AR(CTRL) ? A(STATUS_BUSY_MASK) :
            A(STATUS_IDLE_MASK)) |
            ((AR(IRQ_STAT) & A(IRQ_STAT_ERROR_MASK)) ? A(STATUS_ERROR_MASK) : 0);
        return aud[offset / 4];
    }
    if (address >= EDRV32_PLIC_BASE && address < EDRV32_PLIC_BASE + EDRV32_PLIC_SIZE)
        return plic_read((uint32_t)(address - EDRV32_PLIC_BASE));
    bad_address(address);
}
void mmio_write32(uintptr_t address, uint32_t value)
{
    if (address >= EDRV32_GPU_BASE && address < EDRV32_GPU_BASE + EDRV32_APB_SLOT_SIZE) {
        uint32_t offset = (uint32_t)(address - EDRV32_GPU_BASE);
        if (trace_pending) trace_snapshot();
        if (trace) fprintf(trace, "%u %u\n", offset, value);
        gpu_emu_write(gpu, offset, value);
    } else if (address >= EDRV32_DISP_BASE &&
               address < EDRV32_DISP_BASE + EDRV32_APB_SLOT_SIZE) {
        uint32_t offset = (uint32_t)(address - EDRV32_DISP_BASE);
        if (offset == D(IRQ_EN_OFFSET))
            DR(IRQ_EN) = value & (D(IRQ_EN_ERROR_MASK) | D(IRQ_EN_FRAME_MASK) |
                D(IRQ_EN_SWITCH_MASK) | D(IRQ_EN_SWITCH1_MASK));
        else if (offset == D(IRQ_STAT_OFFSET)) DR(IRQ_STAT) &= ~value;
        else if (offset == D(CTRL_OFFSET)) {
            DR(CTRL) = value & D(CTRL_ENABLE_MASK);
            if (value & D(CTRL_ABORT_MASK)) DR(CTRL) = 0;
            if (value & D(CTRL_SOFT_RST_MASK)) { RESET(disp, disp_gpu_registers); layers = 0; }
        } else SHADOW(disp, disp_gpu_registers, offset, value);
    } else if (address >= EDRV32_AUD_BASE && address < EDRV32_AUD_BASE + EDRV32_APB_SLOT_SIZE)
        aud_write_reg((uint32_t)(address - EDRV32_AUD_BASE), value);
    else if (address >= EDRV32_PLIC_BASE && address < EDRV32_PLIC_BASE + EDRV32_PLIC_SIZE)
        plic_write((uint32_t)(address - EDRV32_PLIC_BASE), value);
    else bad_address(address);
    gateway();
}
static FILE *trace_file(const char *name, const char *mode)
{
    char path[1024];
    snprintf(path, sizeof(path), "%s/%s", trace_directory, name);
    FILE *file = fopen(path, mode);
    if (!file) { perror(path); abort(); }
    return file;
}
void pc_soc_trace_begin(const char *directory)
{
    trace_directory = directory;
    trace_pending = 1;
}
static void trace_snapshot(void)
{
    trace_pending = 0;
    FILE *file = trace_file("frame150-input.bin", "wb");
    if (fwrite(ddr, 1, DDR_BYTES, file) != DDR_BYTES) { perror("trace DDR input"); abort(); }
    fclose(file);
    trace = trace_file("frame150-writes.txt", "w");
}
void pc_soc_trace_end(void)
{
    fclose(trace);
    trace = NULL;
    FILE *file = trace_file("frame150-output.bin", "wb");
    if (fwrite(ddr, 1, DDR_BYTES, file) != DDR_BYTES) { perror("trace DDR output"); abort(); }
    fclose(file);
    file = trace_file("frame150-perf.txt", "w");
    for (unsigned i = 0; i < EDRV32_GPU_PERF_N_COUNT; ++i)
        fprintf(file, "%u\n", gpu_emu_read(gpu, EDRV32_GPU_PERF_OFFSET(i)));
    fclose(file);
}
