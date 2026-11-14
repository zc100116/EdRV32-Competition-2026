/* pipeline_exec.c — PIPE-SPEC 3.3, 7.1–7.4; DDR latest-frame execution.
 * Foreground prepares matrices/LUTs; IRQs own queues, slots and hardware starts.
 * Clock domain: clk_sys; completion IRQs originate in clk_mem.
 */
#include "pipeline_exec.h"
#include "../ddr_map.h"
#include "memory.h"
#include "../vision_hooks.h"
#include "../../platform.h"
#include "../../lvgl/showcase_lvgl.h"
#include "../../runtime.h"
#include "geo_matrix.h"
#include "port.h"
#include "vin.h"
#include "pix.h"
#include "geo.h"
#include "disp.h"
#include <string.h>
#include <stdio.h>
#include <math.h>
extern const unsigned char _binary_build_showcase_pipe_test_bin_start[];
enum { TOKEN_COUNT = 39, NO_TOKEN = -1, STOPPED, PREPARE, RUNNING, DRAIN, PAUSED };
static ui_chain_t requested = {.view = UI_VIEW_FINAL, .preset = 1, .count = 2,
    .block = {{UI_BLOCK_DETECT, 0, {0}}, {UI_BLOCK_OVERLAY, 1, {0}}}};
static uint32_t revision = 1;
static uint32_t pending_upload;
static struct {
    ui_chain_t chain;
    struct pipe_plan plan;
    uint32_t revision;
    unsigned state, stopping, error, capture_channel;
    unsigned ref[TOKEN_COUNT];
    struct { uint32_t frame; uint64_t tick; } token[TOKEN_COUNT];
    int latest[UI_HOP_MAX], pending[UI_HOP_MAX];
    int source, display, submitted, selected;
    int block_output[UI_BLOCK_MAX];
    struct { int hop, input, output; uint64_t start; } active[3];
    unsigned memory_done, memory_need, memory_published, input_used;
    int writing_input, waiting_input, npu_input;
    uint32_t input_frame[3]; uint64_t input_tick[3], input_start[3];
    unsigned input_hop[3], input_cancelled[3];
    unsigned has_detection, image_done, image_done_frame, pc_cancelled;
    uint32_t source_frame;
    unsigned test_ready;
    unsigned test_copied;
    uint64_t source_due;
    struct pix_config pix[UI_HOP_MAX];
    uint8_t gamma[UI_HOP_MAX][256];
    int32_t matrix[UI_HOP_MAX][6];
    int32_t forward[UI_BLOCK_MAX + 1][6];
    unsigned gamma_bank;
    uint64_t sums[UI_HOP_MAX], npu_sum, e2e_sum, box_tick, since, thumb_due;
    unsigned samples[UI_HOP_MAX], npu_samples, frames;
    uint64_t bytes;
    ui_pipe_stats_t stats;
    lv_image_dsc_t thumbs[9];
    int thumb_token[9];
    unsigned thumb_pending, thumb_active, thumb_index, thumb_valid, l1_owned;
    struct rnd_batch batch;
    char report[320];
} p;
static void *uncached(uint32_t address)
{ return (void *)(uintptr_t)(EDRV32_DDR_UNCACHED_BASE + address); }
static uint32_t address(int token)
{ return SHOWCASE_PIPE_BASE + (unsigned)token * SHOWCASE_PIPE_SLOT_BYTES; }
static void retain(int token) { if (token >= 0) ++p.ref[token]; }
static void release(int token) { if (token >= 0) --p.ref[token]; }
static void replace(int *target, int token)
{ retain(token); release(*target); *target = token; }
static unsigned us(uint64_t ticks)
{ return (unsigned)(ticks * 1000000u / platform_clock_hz()); }
static int free_token(unsigned group)
{
    for (unsigned i = group * 3; i < group * 3 + 3; ++i)
        if (!p.ref[i]) return (int)i;
    return NO_TOKEN;
}
static int camera_hop(void)
{
    return p.chain.source == UI_SOURCE_CAMERA ? 0 : -1;
}
static void kick(void);
static void enqueue(unsigned hop, int token);
static void publish(unsigned hop, int token)
{
    replace(&p.latest[hop], token);
    if (p.plan.hop[hop].first != PIPE_NO_BLOCK) {
        for (unsigned b = p.plan.hop[hop].first; b <= p.plan.hop[hop].last; ++b)
            if (p.plan.sample[hop] != b || p.plan.hop[hop].engine == UI_HOP_MEM_NPU)
                replace(&p.block_output[b], token);
    }
    unsigned selected = p.chain.view == UI_VIEW_FINAL ? p.plan.count - 1 :
        p.chain.view == UI_VIEW_SOURCE ? UI_HOP_MAX : p.plan.block_hop[p.chain.view];
    if (hop == selected && (p.chain.view == UI_VIEW_FINAL ||
        p.plan.sample[hop] != p.chain.view || p.plan.hop[hop].engine == UI_HOP_MEM_NPU))
        replace(&p.selected, token);
    if (hop + 1 < p.plan.count) enqueue(hop + 1, token);
    else if (p.chain.source == UI_SOURCE_PC_IMAGE && !p.has_detection && !p.pc_cancelled) {
        p.image_done = 1; p.image_done_frame = p.token[token].frame;
    }
}
static void enqueue(unsigned hop, int token)
{
    replace(&p.pending[hop], token);
    /* Detection taps never wait for CH2 or NPU before advancing the main chain. */
    if (p.plan.hop[hop].engine == UI_HOP_MEM_NPU) publish(hop, token);
}
static void source(int token)
{
    replace(&p.source, token);
    if (p.chain.view == UI_VIEW_SOURCE) replace(&p.selected, token);
    if (p.plan.count) enqueue(0, token);
    else {
        replace(&p.selected, token);
        if (p.chain.source == UI_SOURCE_PC_IMAGE && !p.pc_cancelled) {
            p.image_done = 1; p.image_done_frame = p.token[token].frame;
        }
    }
}
static void camera_busy(void)
{
    int h = camera_hop();
    if (h < 0 || p.state != RUNNING) return;
    uint32_t busy = 0;
    for (unsigned i = 0; i < 3; ++i) if (p.ref[3 + i]) busy |= 1u << i;
    vin_slots_busy(p.capture_channel, busy);
    if (p.capture_channel == 0) {
        busy = 0;
        for (unsigned i = 0; i < 3; ++i) if (p.ref[i]) busy |= 1u << i;
        vin_slots_busy(1, busy);
    }
}
static void camera_configure(void)
{
    if (p.chain.source != UI_SOURCE_CAMERA || p.state != RUNNING) return;
    struct vin_channel c = {VIN_CAM0, 3, VISION_STRIDE, {0}, 0};
    for (unsigned i = 0; i < 3; ++i) {
        c.base[i] = address(3 + (int)i);
        if (p.ref[3+i]) c.busy_slots |= 1u << i;
    }
    if (p.capture_channel == 0) {
        if (p.pix[0].flags & EDRV32_PIX_CFG_GAMMA_EN_MASK) {
            p.gamma_bank ^= 1;
            pix_gamma_load(p.gamma_bank, p.gamma[0]);
            p.pix[0].gamma_bank = p.gamma_bank;
        }
        p.pix[0].gamma_bank = p.gamma_bank;
        pix_configure(&p.pix[0]);
    }
    vin_channel_configure(p.capture_channel, &c);
    if (p.capture_channel == 0) {
        for (unsigned i = 0; i < 3; ++i) c.base[i] = address((int)i);
        c.busy_slots = 0;
        for (unsigned i = 0; i < 3; ++i) if (p.ref[i]) c.busy_slots |= 1u << i;
        vin_channel_configure(1, &c);
    }
}
static void input_start(void)
{
    if (p.waiting_input < 0) return;
    unsigned i = (unsigned)p.waiting_input;
    if (p.input_cancelled[i]) {
        p.input_used &= ~(1u << i); p.waiting_input = -1; return;
    }
    if (vision_pipe_start(i, p.input_frame[i], p.input_tick[i])) {
        p.npu_input = (int)i; p.waiting_input = -1;
    }
}
static int allocate_input(void)
{
    /* The pending input is replaceable; the NPU and writer retain theirs. */
    if (p.waiting_input >= 0) {
        p.input_used &= ~(1u << p.waiting_input); p.waiting_input = -1;
    }
    for (unsigned i = 0; i < 3; ++i)
        if (!(p.input_used & (1u << i))) { p.input_used |= 1u << i; return (int)i; }
    return -1;
}
static void npu_channel(int input)
{
    uint32_t base = VISION_INPUT_BASE + (unsigned)input * VISION_INPUT_SPACING;
    struct vin_channel c = {VIN_MEMORY, 2, VISION_STRIDE, {base, base}, 0};
    vin_channel_configure(2, &c);
}
static int engine_kind(unsigned h)
{
    unsigned e = p.plan.hop[h].engine;
    return e == UI_HOP_MEM_PIX || e == UI_HOP_MEM_NPU ? 0 : e == UI_HOP_GEO ? 1 : 2;
}
static void mapped(ui_detection_t *d, const int32_t m[6])
{
    int x[2] = {d->x, d->x + d->width}, y[2] = {d->y, d->y + d->height};
    int lo_x = 2147483647, lo_y = 2147483647, hi_x = -2147483647, hi_y = -2147483647;
    for (unsigned i = 0; i < 2; ++i) for (unsigned j = 0; j < 2; ++j) {
        int64_t xx = (int64_t)m[0]*x[i] + (int64_t)m[1]*y[j] + m[2];
        int64_t yy = (int64_t)m[3]*x[i] + (int64_t)m[4]*y[j] + m[5];
        int a = (int)(xx >> 16), b = (int)(yy >> 16);
        int ceil_x = (int)((xx + 65535) >> 16), ceil_y = (int)((yy + 65535) >> 16);
        if (a < lo_x) lo_x = a;
        if (b < lo_y) lo_y = b;
        if (ceil_x > hi_x) hi_x = ceil_x;
        if (ceil_y > hi_y) hi_y = ceil_y;
    }
    if (lo_x < 0) lo_x = 0;
    if (lo_y < 0) lo_y = 0;
    if (hi_x > 1280) hi_x = 1280;
    if (hi_y > 720) hi_y = 720;
    d->x = lo_x; d->y = lo_y; d->width = hi_x - lo_x; d->height = hi_y - lo_y;
}
void pipe_map_detections(ui_detection_t *boxes, unsigned count)
{ for (unsigned i = 0; i < count; ++i) mapped(&boxes[i], p.forward[p.chain.count]); }
static void rnd_start(unsigned h, int input, int output)
{
    struct rnd_command *commands = uncached(SHOWCASE_PIPE_RND_DESC);
    struct rnd_common c = {.dst_base = address(output), .dst_stride = VISION_STRIDE,
        .dst_fmt = RND_RGB565, .src_fmt = RND_RGB565,
        .clip = {0,0,1279,719}, .rect = {0,0,1279,719}, .opa = 255};
    struct rnd_source src = {address(input), VISION_STRIDE, 0, 0};
    rnd_copy(commands, &c, &src);
    unsigned count = 1;
    const ui_block_t *b = &p.chain.block[p.plan.hop[h].first];
    if (b->flags & 1) {
        ui_detection_t boxes[5]; unsigned n = vision_pipe_boxes(boxes);
        for (unsigned i = 0; i < n; ++i) {
            mapped(&boxes[i], p.forward[p.plan.hop[h].first]);
            if (boxes[i].width <= 0 || boxes[i].height <= 0) continue;
            c.rect = (struct rnd_rect){boxes[i].x, boxes[i].y,
                boxes[i].x + boxes[i].width - 1, boxes[i].y + boxes[i].height - 1};
            c.color = 0x00ff40;
            rnd_border(&commands[count++], &c, 0, 3, 15);
        }
    }
    if (b->flags & 2) {
        c.rect = c.clip; c.src_fmt = RND_ARGB8888;
        struct rnd_blit blit = {.source = {rnd_physical(showcase_gui_l1_front()),
            5120, 0, 0}, .scale_x = 65536, .scale_y = 65536};
        rnd_blit(&commands[count++], &c, &blit);
    }
    p.batch = (struct rnd_batch){.commands = commands, .count = count};
    board_pipe_rnd_submit(&p.batch);
}
static void start_hop(unsigned h, int kind, int output)
{
    int input = p.pending[h]; p.pending[h] = -1;
    p.active[kind].hop = (int)h; p.active[kind].input = input;
    p.active[kind].output = output; p.active[kind].start = platform_ticks();
    retain(output);
    if (output >= 0) p.token[output] = p.token[input];
    unsigned engine = p.plan.hop[h].engine;
    if (p.plan.sample[h] != PIPE_NO_BLOCK) {
        replace(&p.block_output[p.plan.sample[h]], input);
        if (p.chain.view == p.plan.sample[h]) replace(&p.selected, input);
    }
    if (kind == 0) {
        unsigned sample = p.plan.sample[h] != PIPE_NO_BLOCK;
        p.memory_done = p.memory_published = 0; p.memory_need = (engine == UI_HOP_MEM_PIX ? 1 : 0) |
            (sample ? 2 : 0);
        if (sample) {
            p.writing_input = allocate_input(); npu_channel(p.writing_input);
            p.input_frame[p.writing_input] = p.token[input].frame;
            p.input_tick[p.writing_input] = p.token[input].tick;
            p.input_start[p.writing_input] = platform_ticks();
            p.input_hop[p.writing_input] = h;
            p.input_cancelled[p.writing_input] = 0;
        }
        if (p.capture_channel == 0 && p.chain.source == UI_SOURCE_CAMERA)
            vin_channel_enable(0, 0);
        if (engine == UI_HOP_MEM_PIX) {
            if (p.pix[h].flags & EDRV32_PIX_CFG_GAMMA_EN_MASK) {
                p.gamma_bank ^= 1; pix_gamma_load(p.gamma_bank, p.gamma[h]);
            }
            p.pix[h].gamma_bank = p.gamma_bank; pix_configure(&p.pix[h]);
            struct vin_channel c = {VIN_MEMORY, 2, VISION_STRIDE,
                {address(output), address(output)}, 0};
            vin_channel_configure(0, &c);
        }
        vin_memory_start(address(input), VISION_STRIDE, VISION_WIDTH, VISION_HEIGHT);
    } else if (kind == 1) {
        struct geo_config c = {.src_base = address(input), .src_stride = VISION_STRIDE,
            .src_width = 1280, .src_height = 720, .dst_base = address(output),
            .dst_stride = VISION_STRIDE, .rect_width = 1280, .rect_height = 720};
        memcpy(c.matrix, p.matrix[h], sizeof c.matrix);
        geo_descriptor_pack(uncached(SHOWCASE_PIPE_GEO_DESC), &c);
        geo_submit(SHOWCASE_PIPE_GEO_DESC, 1);
    } else rnd_start(h, input, output);
}
static void kick(void)
{
    if (p.state != RUNNING) return;
    input_start();
    for (int kind = 0; kind < 3; ++kind) {
        if (p.active[kind].hop != -1 || (kind == 2 && p.thumb_active)) continue;
        int chosen = -1, output = -1;
        for (unsigned h = 0; h < p.plan.count; ++h) {
            if (p.pending[h] < 0 || p.plan.hop[h].engine < UI_HOP_MEM_PIX ||
                engine_kind(h) != kind) continue;
            int slot = p.plan.hop[h].engine == UI_HOP_MEM_NPU ? -1 : free_token(h + 1);
            if (slot < 0 && p.plan.hop[h].engine != UI_HOP_MEM_NPU) continue;
            if (chosen < 0 || p.token[p.pending[h]].frame <
                p.token[p.pending[chosen]].frame) { chosen = (int)h; output = slot; }
        }
        if (chosen < 0) continue;
        if (kind == 0 && p.chain.source == UI_SOURCE_CAMERA && p.capture_channel == 0) {
            /* VIN 5.2: disable prevents a new CAM frame but lets its writer drain.
             * The completing CAM IRQ retries this queue before switching CH0's source. */
            vin_channel_enable(0, 0);
            if (vin_write_status(0) & EDRV32_VIN_CH_WR_STAT_ACTIVE_MASK) continue;
        }
        if (kind == 2 && (p.chain.block[p.plan.hop[chosen].first].flags & 2)) {
            if (!showcase_gui_l1_acquire()) continue;
            p.l1_owned = 1;
        }
        start_hop((unsigned)chosen, kind, output);
    }
    camera_busy();
}
static void complete(int kind)
{
    unsigned h = (unsigned)p.active[kind].hop;
    int output = p.active[kind].output;
    if (p.plan.hop[h].engine != UI_HOP_MEM_NPU && !(kind == 0 && p.memory_published)) {
        p.sums[h] += platform_ticks() - p.active[kind].start; ++p.samples[h];
    }
    if (p.state == RUNNING && output >= 0 && !(kind == 0 && p.memory_published))
        publish(h, output);
    release(p.active[kind].input); release(output);
    p.active[kind].hop = -1;
    if (kind == 0) {
        vin_channel_enable(0, 0); vin_channel_enable(2, 0);
        if (p.capture_channel == 0) camera_configure();
    }
    if (kind == 2 && p.l1_owned) { p.l1_owned = 0; showcase_gui_l1_release(); }
    kick();
}
void pipe_irq(const struct engine_event *e, unsigned engine)
{
    if (p.state != RUNNING && p.state != DRAIN) return;
    if (e->error || (e->irq & EDRV32_VIN_IRQ_STAT_ERROR_MASK)) {
        p.error = e->error ? e->error : 1; return;
    }
    if (engine == ENGINE_VIN) {
        const uint32_t bits[3] = {EDRV32_VIN_IRQ_STAT_FRAME_MASK,
            EDRV32_VIN_IRQ_STAT_CH1_FRAME_MASK, EDRV32_VIN_IRQ_STAT_CH2_FRAME_MASK};
        for (unsigned ch = 0; ch < 3; ++ch) if (e->irq & bits[ch]) {
            struct vin_frame f = vin_frame_done(ch);
            if (f.info & (EDRV32_VIN_CH_DONE_INFO_INCOMPLETE_MASK |
                          EDRV32_VIN_CH_DONE_INFO_BUS_ERR_MASK)) { p.error = 1; continue; }
            if (p.active[0].hop >= 0 && ((ch == 0 && (p.memory_need & 1)) || ch == 2)) {
                p.memory_done |= ch == 0 ? 1 : 2;
                if (ch == 0 && p.memory_need == 3) {
                    unsigned h = (unsigned)p.active[0].hop;
                    p.sums[h] += platform_ticks() - p.active[0].start; ++p.samples[h];
                    p.memory_published = 1;
                    if (p.state == RUNNING) publish(h, p.active[0].output);
                    kick();
                }
                if (ch == 2) {
                    if (p.waiting_input >= 0) p.input_used &= ~(1u << p.waiting_input);
                    p.waiting_input = p.writing_input; p.writing_input = -1; input_start();
                }
                if (p.memory_done == p.memory_need) complete(0);
            } else if (p.chain.source == UI_SOURCE_CAMERA && p.capture_channel == 0 &&
                       ch == 1 && p.state == RUNNING) {
                int token = (int)vin_frame_slot(f.info);
                p.token[token].frame = f.frame_id; p.token[token].tick = platform_ticks();
                replace(&p.source, token);
                if (p.chain.view == UI_VIEW_SOURCE) replace(&p.selected, token);
                camera_busy();
            } else if (p.chain.source == UI_SOURCE_CAMERA && ch == p.capture_channel &&
                       p.state == RUNNING) {
                int token = 3 + (int)vin_frame_slot(f.info);
                p.token[token].frame = f.frame_id;
                p.token[token].tick = platform_ticks();
                if (p.capture_channel == 1) {
                    replace(&p.source, token);
                    if (p.chain.view == UI_VIEW_SOURCE) replace(&p.selected, token);
                }
                publish(0, token); kick();
            }
        }
    } else if (engine == ENGINE_GEO && (e->irq & EDRV32_GEO_IRQ_STAT_DONE_MASK)) {
        if (p.active[1].hop == -2) {
            int token = p.active[1].output; p.active[1].hop = -1;
            if (p.state == RUNNING) {
                p.test_ready = 1; p.test_copied |= 1u << token; source(token);
            }
            release(token); kick();
        } else if (p.active[1].hop >= 0) complete(1);
    }
}
void pipe_rnd_done(void)
{
    if (p.thumb_active) {
        release(p.thumb_token[p.thumb_index]); p.thumb_token[p.thumb_index] = -1;
        p.thumb_valid |= 1u << p.thumb_index;
        p.thumb_active = 0;
    } else if (p.active[2].hop >= 0) complete(2);
    kick();
}
void pipe_npu_done(void)
{
    if (p.npu_input >= 0) {
        unsigned h = p.input_hop[p.npu_input];
        if (p.plan.hop[h].engine == UI_HOP_MEM_NPU) {
            p.sums[h] += platform_ticks() - p.input_start[p.npu_input]; ++p.samples[h];
        }
    }
    if (p.npu_input >= 0 && p.chain.source != UI_SOURCE_PC_IMAGE) {
        p.input_used &= ~(1u << p.npu_input); p.npu_input = -1;
    }
    kick();
}
void pipe_detection_available(void) { kick(); }
void pipe_detection_release(void)
{
    if (p.npu_input >= 0) { p.input_used &= ~(1u << p.npu_input); p.npu_input = -1; }
    kick();
}
void pipe_detection_published(uint64_t tick) { p.box_tick = tick; }
void pipe_upload(uint32_t base) { pending_upload = base; p.pc_cancelled = 0; }
void pipe_cancel_upload(void)
{
    pending_upload = 0; p.image_done = 0; p.pc_cancelled = 1;
    if (p.writing_input >= 0) p.input_cancelled[p.writing_input] = 1;
    if (p.waiting_input >= 0) {
        p.input_used &= ~(1u << p.waiting_input); p.waiting_input = -1;
    }
}
void pipe_memory_sample(const struct mem_xbar_stats *sample)
{
    for (unsigned i = 0; i < 7; ++i)
        p.bytes += ((uint64_t)sample->port[i].rd_beat + sample->port[i].wr_beat) * 32;
}
static void prepare(void)
{
    vision_pipe_clear();
    p.chain = requested; p.revision = revision;
    p.test_ready = p.test_copied = 0;
    pipe_compile(&p.chain, &p.plan);
    p.has_detection = 0;
    for (unsigned i = 0; i < p.chain.count; ++i)
        if (p.chain.block[i].type == UI_BLOCK_DETECT) p.has_detection = 1;
    p.capture_channel = p.plan.count && p.plan.hop[0].engine == UI_HOP_CAM_PIX ? 0 : 1;
    int32_t forward[6] = {65536,0,0,0,65536,0};
    for (unsigned b = 0; b <= p.chain.count; ++b) {
        memcpy(p.forward[b], forward, sizeof forward);
        if (b == p.chain.count) break;
        if (p.chain.block[b].type == UI_BLOCK_DETECT) {
            const int32_t identity[6] = {65536,0,0,0,65536,0};
            memcpy(forward, identity, sizeof forward);
        } else if (p.chain.block[b].type == UI_BLOCK_GEO) {
            const ui_block_t *block = &p.chain.block[b];
            int32_t inverse[6];
            geo_matrix(inverse, block->p[0], block->p[1], block->p[2], block->p[3],
                block->flags & 1, block->flags & 2, 1280, 720);
            double a = inverse[0]/65536.0, c = inverse[3]/65536.0;
            double d = inverse[4]/65536.0, bb = inverse[1]/65536.0;
            double det = a*d - bb*c;
            double m[6] = {d/det, -bb/det, 0, -c/det, a/det, 0};
            m[2] = -(m[0]*inverse[2] + m[1]*inverse[5])/65536.0;
            m[5] = -(m[3]*inverse[2] + m[4]*inverse[5])/65536.0;
            int32_t result[6];
            for (unsigned r = 0; r < 2; ++r) for (unsigned col = 0; col < 3; ++col) {
                double value = m[r*3]*forward[col] + m[r*3+1]*forward[3+col];
                if (col == 2) value += m[r*3+2]*65536;
                result[r*3+col] = (int32_t)lround(value);
            }
            memcpy(forward, result, sizeof forward);
        }
    }
    for (unsigned h = 0; h < p.plan.count; ++h) {
        const ui_hop_t *hop = &p.plan.hop[h];
        if (hop->engine == UI_HOP_GEO) {
            const ui_block_t *b = &p.chain.block[hop->first];
            geo_matrix(p.matrix[h], b->p[0], b->p[1], b->p[2], b->p[3],
                b->flags & 1, b->flags & 2, 1280, 720);
        }
        struct pix_config *c = &p.pix[h];
        *c = (struct pix_config){.contrast = 256, .threshold = 128};
        if (hop->engine != UI_HOP_CAM_PIX && hop->engine != UI_HOP_MEM_PIX) continue;
        for (unsigned i = p.plan.pix_first[h]; i <= hop->last; ++i) {
            const ui_block_t *b = &p.chain.block[i];
            switch (b->type) {
            case UI_BLOCK_LEVEL: c->flags |= EDRV32_PIX_CFG_BC_EN_MASK;
                c->brightness = b->p[0]; c->contrast = b->p[1]; break;
            case UI_BLOCK_GAMMA: c->flags |= EDRV32_PIX_CFG_GAMMA_EN_MASK;
                pix_gamma_table(p.gamma[h], (unsigned)b->p[0]); break;
            case UI_BLOCK_FILTER:
                if (c->stage1 == PIX_BYPASS) c->stage1 = (enum pix_operation)b->p[0];
                else c->stage2 = (enum pix_operation)b->p[0];
                break;
            case UI_BLOCK_GRAY: c->flags |= EDRV32_PIX_CFG_GRAY_EN_MASK; break;
            case UI_BLOCK_BINARY: c->flags |= EDRV32_PIX_CFG_BIN_EN_MASK;
                c->threshold = b->p[0]; break;
            case UI_BLOCK_INVERT: c->flags |= EDRV32_PIX_CFG_INV_EN_MASK; break;
            default: break;
            }
        }
    }
    p.stats = (ui_pipe_stats_t){.hop_count = p.plan.count, .ddr_limit_mbps = 1950};
    memcpy(p.stats.hop, p.plan.hop, sizeof p.stats.hop);
    for (unsigned i = 0; i < 9; ++i) p.thumbs[i] = (lv_image_dsc_t){
        .header = {.magic = LV_IMAGE_HEADER_MAGIC, .cf = LV_COLOR_FORMAT_RGB565,
            .flags = LV_IMAGE_FLAGS_MODIFIABLE, .w = 160, .h = 90, .stride = 320},
        .data_size = 28800, .data = uncached(SHOWCASE_PIPE_THUMB_BASE + i*0x8000)};
    p.since = platform_ticks(); p.source_due = p.since;
    p.thumb_due = p.since + platform_clock_hz()/5;
    p.state = RUNNING;
    showcase_gui_pipeline_overlay(p.plan.hide_l1 && p.chain.view == UI_VIEW_FINAL);
    engine_control(ENGINE_VIN, EDRV32_VIN_CTRL_ENABLE_MASK);
    engine_control(ENGINE_PIX, EDRV32_PIX_CTRL_ENABLE_MASK);
    engine_control(ENGINE_GEO, EDRV32_GEO_CTRL_ENABLE_MASK);
    vin_camera_size(0, 1280, 720); camera_configure();
}
void pipe_enter(void)
{
    memset(&p, 0, sizeof p);
    p.source = p.display = p.submitted = p.selected = -1;
    p.writing_input = p.waiting_input = p.npu_input = -1;
    for (unsigned i = 0; i < UI_HOP_MAX; ++i) p.latest[i] = p.pending[i] = -1;
    for (unsigned i = 0; i < 3; ++i) p.active[i].hop = -1;
    for (unsigned i = 0; i < 9; ++i) p.thumb_token[i] = -1;
    for (unsigned i = 0; i < UI_BLOCK_MAX; ++i) p.block_output[i] = -1;
    p.state = PREPARE;
}
void pipe_stop(bool pause)
{
    uint32_t lock = sched_port_lock();
    p.state = DRAIN; p.stopping = pause ? 1 : 0;
    vin_channel_enable(p.capture_channel, 0);
    if (p.capture_channel == 0) vin_channel_enable(1, 0);
    for (unsigned i = 0; i < UI_HOP_MAX; ++i) {
        replace(&p.pending[i], -1); replace(&p.latest[i], -1);
    }
    replace(&p.source, -1); replace(&p.selected, -1);
    for (unsigned i = 0; i < UI_BLOCK_MAX; ++i) replace(&p.block_output[i], -1);
    for (unsigned i = 0; i < 9; ++i)
        if (!p.thumb_active || p.thumb_index != i) replace(&p.thumb_token[i], -1);
    p.thumb_pending = 0;
    if (p.waiting_input >= 0) { p.input_used &= ~(1u << p.waiting_input); p.waiting_input = -1; }
    sched_port_unlock(lock);
    app_wake_at(platform_ticks());
}
void pipe_resume(void) { p.state = PREPARE; app_wake_at(platform_ticks()); }
bool pipe_ready(ui_state_t target)
{
    return target == UI_STATE_IDLE ? p.state == STOPPED :
        target == UI_STATE_PAUSED ? p.state == PAUSED : p.state == RUNNING;
}
void pipe_display_irq(uint32_t irq)
{
    if (p.state == STOPPED || p.state == PREPARE || p.state == PAUSED) return;
    if (irq & EDRV32_DISP_IRQ_STAT_SWITCH_MASK) {
        uint32_t rel = disp_released(DISP_L0);
        if (p.display >= 0 && rel == address(p.display)) replace(&p.display, -1);
    }
    if (irq & EDRV32_DISP_IRQ_STAT_FRAME_MASK) {
        if (p.submitted >= 0 && disp_current(DISP_L0) == address(p.submitted)) {
            p.display = p.submitted; p.submitted = -1;
            p.e2e_sum += platform_ticks() - p.token[p.display].tick; ++p.frames;
        }
        if (p.state == DRAIN && p.stopping != 1) disp_layer_enable(DISP_L0, 0);
        else if (p.selected >= 0 && p.submitted < 0 && p.selected != p.display) {
            p.submitted = p.selected; retain(p.submitted);
            disp_submit(DISP_L0, address(p.submitted), VISION_STRIDE);
            disp_layer_enable(DISP_L0, 1);
        }
    }
    kick();
}
static void thumbnails(void)
{
    uint64_t now = platform_ticks();
    if (now >= p.thumb_due && !p.thumb_pending && !p.thumb_active) {
        replace(&p.thumb_token[8], p.source);
        for (unsigned b = 0; b < p.chain.count; ++b)
            replace(&p.thumb_token[b], p.block_output[b]);
        for (unsigned b = 0; b < 9; ++b)
            if (p.thumb_token[b] >= 0) p.thumb_pending |= 1u << b;
        p.thumb_due = now + platform_clock_hz()/5;
    }
    if (!p.thumb_pending || p.thumb_active || p.active[2].hop >= 0) return;
    unsigned index = 0;
    while (!(p.thumb_pending & (1u << index))) ++index;
    p.thumb_pending &= ~(1u << index); p.thumb_index = index; p.thumb_active = 1;
    struct rnd_common c = {.dst_base = SHOWCASE_PIPE_THUMB_BASE + index*0x8000,
        .dst_stride = 320, .dst_fmt = RND_RGB565, .src_fmt = RND_RGB565,
        .clip = {0,0,159,89}, .rect = {0,0,159,89}, .opa = 255};
    struct rnd_blit b = {.source = {address(p.thumb_token[index]), VISION_STRIDE, 0, 0},
        .scale_x = 8*65536, .scale_y = 8*65536};
    struct rnd_command *cmd = uncached(SHOWCASE_PIPE_RND_DESC);
    rnd_blit(cmd, &c, &b);
    p.batch = (struct rnd_batch){.commands = cmd, .count = 1};
    board_pipe_rnd_submit(&p.batch);
}
static void image_source(void)
{
    if (p.chain.source == UI_SOURCE_CAMERA) return;
    if (p.chain.source == UI_SOURCE_TEST_IMAGE && p.test_ready) {
        if (platform_ticks() >= p.source_due) {
            /* Upscale once, then resubmit the immutable source at the demo cadence. */
            int token = free_token(0);
            if (token < 0) return;
            if (!(p.test_copied & (1u << token))) {
                memcpy(uncached(address(token)), uncached(address(p.source)), VISION_IMAGE_BYTES);
                p.test_copied |= 1u << token;
            }
            uint32_t lock = sched_port_lock();
            p.token[token].frame = p.source_frame++;
            p.token[token].tick = platform_ticks();
            source(token); kick();
            p.source_due = platform_ticks() + platform_clock_hz()/30;
            sched_port_unlock(lock);
        }
        return;
    }
    if (p.active[1].hop != -1) return;
    if (p.chain.source == UI_SOURCE_PC_IMAGE && !pending_upload) return;
    if (p.chain.source == UI_SOURCE_TEST_IMAGE && platform_ticks() < p.source_due) return;
    int output = free_token(0);
    if (output < 0) return;
    if (p.chain.source == UI_SOURCE_PC_IMAGE) {
        /* The upload buffer is copied once; later uploads can reuse its window. */
        memcpy(uncached(address(output)), uncached(pending_upload), VISION_IMAGE_BYTES);
        pending_upload = 0;
        uint32_t lock = sched_port_lock();
        p.token[output].frame = p.source_frame++;
        p.token[output].tick = platform_ticks(); source(output); kick();
        sched_port_unlock(lock);
    } else {
        struct geo_config c = {.src_base = rnd_physical(
            _binary_build_showcase_pipe_test_bin_start), .src_stride = 1280,
            .src_width = 640, .src_height = 360, .dst_base = address(output),
            .dst_stride = VISION_STRIDE, .rect_width = 1280, .rect_height = 720,
            .matrix = {32768,0,0,0,32768,0}};
        geo_descriptor_pack(uncached(SHOWCASE_PIPE_GEO_DESC), &c);
        p.active[1].hop = -2; p.active[1].output = output; retain(output);
        p.token[output].frame = p.source_frame++; p.token[output].tick = platform_ticks();
        p.source_due = platform_ticks() + platform_clock_hz()/30;
        geo_submit(SHOWCASE_PIPE_GEO_DESC, 1);
    }
}
static void statistics(void)
{
    uint64_t now = platform_ticks(), elapsed = now - p.since;
    if (elapsed < platform_clock_hz()) return;
    p.stats.fps = (unsigned)((uint64_t)p.frames * platform_clock_hz()/elapsed);
    p.stats.e2e_us = p.frames ? us(p.e2e_sum/p.frames) : 0;
    p.stats.box_lag_us = p.box_tick ? us(now - p.box_tick) : 0;
    p.stats.npu_us = p.npu_samples ? us(p.npu_sum/p.npu_samples) : 0;
    p.npu_sum = p.npu_samples = 0;
    p.stats.ddr_mbps = (unsigned)(p.bytes * platform_clock_hz()/elapsed/1000000);
    unsigned offset = (unsigned)snprintf(p.report, sizeof p.report, "pipe fps=%u e2e=%u hops=",
        p.stats.fps, p.stats.e2e_us);
    for (unsigned h = 0; h < p.plan.count; ++h) {
        p.stats.hop[h].us = p.samples[h] ? us(p.sums[h]/p.samples[h]) : 0;
        const char *const names[] = {"CAM-CH0/PIX", "CAM-CH1", "MEMSRC-CH0/PIX",
            "MEMSRC-CH2/NPU", "GEO", "RND"};
        offset += (unsigned)snprintf(p.report + offset, sizeof p.report - offset,
            "%s%s:%u", h ? "," : "", names[p.plan.hop[h].engine],
            (unsigned)p.stats.hop[h].us);
        p.sums[h] = 0; p.samples[h] = 0;
    }
    snprintf(p.report + offset, sizeof p.report - offset, " ddr=%u\r\n", p.stats.ddr_mbps);
    p.bytes = p.e2e_sum = p.frames = 0; p.since = now;
}
const char *pipe_report(void)
{
    static char taken[sizeof p.report];
    memcpy(taken, p.report, sizeof taken); p.report[0] = 0;
    return taken;
}
void pipe_npu_time(uint64_t ticks)
{ p.npu_sum += ticks; ++p.npu_samples; }
int pipe_service(void)
{
    if (p.error) {
        platform_puts("showcase pipeline hardware error "); platform_put_hex(p.error);
        platform_puts("\r\n"); platform_stop();
    }
    if (p.state == STOPPED || p.state == PAUSED) return 0;
    if (p.state == PREPARE) prepare();
    if (p.state == RUNNING && p.revision != revision) {
        pipe_stop(false); p.stopping = 2;
    }
    uint32_t lock = sched_port_lock();
    if (p.state == DRAIN) {
        bool idle = p.active[0].hop == -1 && p.active[1].hop == -1 &&
            p.active[2].hop == -1 && !p.thumb_active && p.npu_input < 0 &&
            vision_pipe_idle() &&
            (engine_poll(ENGINE_VIN).status & EDRV32_VIN_STATUS_IDLE_MASK);
        if (!p.stopping || p.stopping == 2) {
            if (engine_poll(ENGINE_DISP).status & EDRV32_DISP_STATUS_IDLE_MASK) {
                replace(&p.display, -1); replace(&p.submitted, -1);
            }
            idle = idle && p.display < 0 && p.submitted < 0;
        }
        if (idle) {
            engine_control(ENGINE_VIN, 0);
            engine_control(ENGINE_PIX, 0); engine_control(ENGINE_GEO, 0);
            engine_control(ENGINE_NPU, 0);
            showcase_gui_pipeline_overlay(false);
            unsigned next = p.stopping;
            if (next == 2) { pipe_enter(); }
            else p.state = next == 1 ? PAUSED : STOPPED;
        }
        sched_port_unlock(lock); return 1;
    }
    kick(); thumbnails();
    sched_port_unlock(lock);
    image_source();
    if (p.image_done) {
        p.image_done = 0; vision_pipe_image_done(p.image_done_frame);
    }
    lock = sched_port_lock(); statistics(); sched_port_unlock(lock);
    app_wake_at(platform_ticks() + platform_clock_hz()/1000);
    return 0;
}
ui_chain_t ui_data_chain(void)
{
    uint32_t lock = sched_port_lock(); ui_chain_t result = requested;
    sched_port_unlock(lock); return result;
}
unsigned ui_data_chain_set(const ui_chain_t *chain)
{
    unsigned error = pipe_chain_validate(chain);
    if (error) return error;
    uint32_t lock = sched_port_lock(); requested = *chain; requested.preset = 0; ++revision;
    sched_port_unlock(lock); app_wake_at(platform_ticks()); return 0;
}
void ui_data_chain_preset(unsigned preset)
{
    ui_chain_t chain; pipe_chain_preset(&chain, preset);
    uint32_t lock = sched_port_lock(); requested = chain; ++revision;
    sched_port_unlock(lock); app_wake_at(platform_ticks());
}
uint32_t pipe_revision(void) { return revision; }
bool pipe_pc_image(void) { return p.chain.source == UI_SOURCE_PC_IMAGE; }
ui_pipe_stats_t ui_data_pipe_stats(void)
{
    uint32_t lock = sched_port_lock(); ui_pipe_stats_t result = p.stats;
    sched_port_unlock(lock); return result;
}
const lv_image_dsc_t *ui_data_thumb(unsigned block)
{
    unsigned index = block == UI_VIEW_FINAL ? 8 : block;
    return p.thumb_valid & (1u << index) ? &p.thumbs[index] : NULL;
}
void pipe_hardware_error(uint32_t error) { p.error = error; }
