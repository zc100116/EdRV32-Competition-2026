/* File: rnd.c
 * Spec: rnd-spec v0.2 2.5–2.6, 4–6; SoC 7.4.
 * Description: Exact 64-byte encoding and explicit cache ownership transfers.
 * Clock domain: clk_sys CPU; engine registers in clk_mem.
 */
#include "rnd.h"
#include "cache.h"
#include "plic.h"
#include "clint.h"

_Static_assert(sizeof(struct rnd_command) == 64, "RND descriptor size");
static struct rnd_batch active;
static rnd_callback completion;
static void *completion_context;
static struct rnd_timing timing;

/* Keep the driver usable without linking the CLINT interrupt/timer service. */
static uint64_t ticks(void)
{
    uint32_t high;
    uint32_t low;
    uint32_t again;
    do {
        high = mmio_read32(EDRV32_CLINT_BASE + CLINT_MTIME_HI);
        low = mmio_read32(EDRV32_CLINT_BASE + CLINT_MTIME_LO);
        again = mmio_read32(EDRV32_CLINT_BASE + CLINT_MTIME_HI);
    } while (high != again);
    return ((uint64_t)high << 32) | low;
}

const struct rnd_timing *rnd_last_timing(void) { return &timing; }

static uint32_t xy(uint16_t x, uint16_t y)
{
    return x | ((uint32_t)y << 16);
}

static void common(struct rnd_command *out, const struct rnd_common *c, uint32_t op)
{
    for (unsigned int i = 0; i < 16; ++i) {
        out->word[i] = 0;
    }
    out->word[0] = op | ((uint32_t)c->dst_fmt << 8) | ((uint32_t)c->src_fmt << 12) |
                   ((uint32_t)c->flags << 16);
    out->word[1] = c->dst_base;
    out->word[2] = c->dst_stride;
    out->word[3] = xy(c->clip.x0, c->clip.y0);
    out->word[4] = xy(c->clip.x1, c->clip.y1);
    out->word[5] = xy(c->rect.x0, c->rect.y0);
    out->word[6] = xy(c->rect.x1, c->rect.y1);
    out->word[7] = c->color | ((uint32_t)c->opa << 24);
}

static void source_words(struct rnd_command *out, const struct rnd_source *source)
{
    out->word[8] = source->base;
    out->word[9] = source->stride;
    out->word[10] = xy(source->x, source->y);
}

void rnd_fill(struct rnd_command *out, const struct rnd_common *c, uint16_t radius,
              uint32_t grad_start, const int32_t steps[4])
{
    common(out, c, 1);
    out->word[8] = radius;
    out->word[9] = grad_start;
    for (unsigned int i = 0; i < 4; ++i) {
        out->word[10 + i] = (uint32_t)steps[i];
    }
}

void rnd_border(struct rnd_command *out, const struct rnd_common *c,
                uint16_t radius, uint16_t width, uint8_t sides)
{
    common(out, c, 2);
    out->word[8] = radius;
    out->word[9] = width | ((uint32_t)sides << 16);
}

void rnd_glyph(struct rnd_command *out, const struct rnd_common *c,
               const struct rnd_source *source)
{
    common(out, c, 3);
    source_words(out, source);
}

void rnd_blit(struct rnd_command *out, const struct rnd_common *c,
              const struct rnd_blit *blit)
{
    common(out, c, 4);
    source_words(out, &blit->source);
    out->word[11] = blit->scale_x;
    out->word[12] = blit->scale_y;
    out->word[13] = blit->palette;
    out->word[14] = blit->key;
    out->word[15] = blit->rc_color | ((uint32_t)blit->rc_opa << 24);
}

void rnd_copy(struct rnd_command *out, const struct rnd_common *c,
              const struct rnd_source *source)
{
    common(out, c, 5);
    source_words(out, source);
}

void rnd_box_shadow(struct rnd_command *out, const struct rnd_common *c,
                    uint16_t radius, uint8_t blur, uint32_t temp_base)
{
    common(out, c, 6);
    out->word[8] = radius;
    out->word[9] = blur;
    out->word[10] = temp_base;
}

void rnd_blur(struct rnd_command *out, const struct rnd_common *c,
              uint8_t radius, uint32_t temp_base)
{
    common(out, c, 7);
    out->word[8] = radius;
    out->word[9] = temp_base;
}

void rnd_tilemap(struct rnd_command *out, const struct rnd_common *c,
                 const struct rnd_tilemap *tilemap)
{
    common(out, c, 8);
    out->word[8] = tilemap->tile_base;
    out->word[9] = tilemap->map_base;
    out->word[10] = tilemap->map_stride;
    out->word[11] = xy(tilemap->map_x, tilemap->map_y);
    out->word[13] = tilemap->palette;
    out->word[14] = tilemap->key;
}

uint32_t rnd_physical(const void *cpu_address)
{
    uintptr_t address = (uintptr_t)cpu_address;
    return (uint32_t)(address - (address >= EDRV32_DDR_UNCACHED_BASE ?
                               EDRV32_DDR_UNCACHED_BASE : EDRV32_DDR_BASE));
}

void rnd_submit(const struct rnd_batch *batch)
{
    active = *batch;
    uint64_t start = ticks();
    timing.cache_ops = 0;
    /* SoC 7.4 and rnd.h: both DDR aliases are valid CPU addresses. Noncached
     * stores complete before DOORBELL (cpu-spec 4.7); no clean is needed.
     */
    if ((uintptr_t)batch->commands < EDRV32_DDR_UNCACHED_BASE) {
        cache_clean((uintptr_t)batch->commands, (uint32_t)batch->count * 64u);
        timing.cache_ops++;
    }
    for (size_t i = 0; i < batch->source_count; ++i) {
        if ((uintptr_t)batch->sources[i].address < EDRV32_DDR_UNCACHED_BASE) {
            cache_clean((uintptr_t)batch->sources[i].address, batch->sources[i].bytes);
            timing.cache_ops++;
        }
    }
    timing.clean_ticks = ticks() - start;
    mmio_write32(EDRV32_RND_BASE + EDRV32_RND_DESC_BASE_OFFSET,
                 rnd_physical(batch->commands));
    mmio_write32(EDRV32_RND_BASE + EDRV32_RND_DESC_COUNT_OFFSET, batch->count);
    timing.doorbell_tick = ticks();
    mmio_write32(EDRV32_RND_BASE + EDRV32_RND_DOORBELL_OFFSET, 1);
}

static struct rnd_result finish(void)
{
    uint64_t start = ticks();
    /* rnd 6: ERROR may precede completion of already-issued AXI transactions. */
    while (mmio_read32(EDRV32_RND_BASE + EDRV32_RND_STATUS_OFFSET) &
           EDRV32_RND_STATUS_BUSY_MASK) {
    }
    struct rnd_result result = {
        mmio_read32(EDRV32_RND_BASE + EDRV32_RND_IRQ_STAT_OFFSET),
        mmio_read32(EDRV32_RND_BASE + EDRV32_RND_ERR_CODE_OFFSET),
        mmio_read32(EDRV32_RND_BASE + EDRV32_RND_CUR_DESC_OFFSET)
    };
    for (size_t i = 0; i < active.target_count; ++i) {
        if ((uintptr_t)active.targets[i].address < EDRV32_DDR_UNCACHED_BASE) {
            cache_invalidate((uintptr_t)active.targets[i].address, active.targets[i].bytes);
            timing.cache_ops++;
        }
    }
    mmio_write32(EDRV32_RND_BASE + EDRV32_RND_IRQ_STAT_OFFSET, result.irq);
    timing.finish_ticks = ticks() - start;
    return result;
}

struct rnd_result rnd_wait(void)
{
    uint32_t irq;
    do {
        irq = mmio_read32(EDRV32_RND_BASE + EDRV32_RND_IRQ_STAT_OFFSET);
    } while (!(irq & (EDRV32_RND_IRQ_STAT_DONE_MASK | EDRV32_RND_IRQ_STAT_ERROR_MASK)));
    return finish();
}

void rnd_irq_register(unsigned int priority, rnd_callback callback, void *context)
{
    completion = callback;
    completion_context = context;
    mmio_write32(EDRV32_RND_BASE + EDRV32_RND_IRQ_EN_OFFSET,
                 EDRV32_RND_IRQ_EN_DONE_MASK | EDRV32_RND_IRQ_EN_ERROR_MASK);
    plic_set_priority(EDRV32_PLIC_SOURCE_RND, priority);
    plic_set_enable(mmio_read32(EDRV32_PLIC_BASE + PLIC_ENABLE) |
                    (1u << EDRV32_PLIC_SOURCE_RND));
}

void rnd_irq_handle(void)
{
    struct rnd_result result = finish();
    completion(&result, completion_context);
}

struct rnd_result rnd_abort(void)
{
    mmio_write32(EDRV32_RND_BASE + EDRV32_RND_CTRL_OFFSET, EDRV32_RND_CTRL_ABORT_MASK);
    return finish();
}

void rnd_read_perf(uint32_t perf[6])
{
    /* rnd 4.3: read after completion, before the next DOORBELL clears PERF. */
    for (unsigned int i = 0; i < 6; ++i) {
        perf[i] = mmio_read32(EDRV32_RND_BASE + EDRV32_RND_PERF_OFFSET(i));
    }
}
