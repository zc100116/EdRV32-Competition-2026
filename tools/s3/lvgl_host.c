/* File: lvgl_host.c
 * Spec: rnd-testplan RN-17(a); Task B3-3b.
 * Description: Linux platform services; real descriptor execution is supplied by rnd_ref.py.
 * Clock domain: deterministic host milliseconds controlled by the RN-17 runner.
 */
#include "s3_lvgl.h"
#include "s3_platform.h"
#include "draw_rnd.h"
#include "mem_xbar.h"
#include <stdio.h>
#include <stdlib.h>

static uint32_t milliseconds;
static uint32_t frame_count;
static const void *scan_surface;
static uint32_t scan_bytes;
static void (*execute_batch)(const struct rnd_batch *);
static struct s3_rnd_timing timing;
static const void *uncached_commands;
static const void *uncached_copy;

/* Host storage has one address; retain its board alias ownership for timing. */
void *s3_uncached(void *storage)
{
    uncached_commands = storage;
    uncached_copy = (struct rnd_command *)storage + S3_RND_BATCH_COMMANDS;
    return storage;
}

void s3_host_install(void (*execute)(const struct rnd_batch *)) { execute_batch = execute; }
void s3_host_time(uint32_t value) { milliseconds = value; }
uint32_t rnd_physical(const void *pointer) { return (uint32_t)(uintptr_t)pointer; }
void s3_platform_init(void) { }
uint64_t s3_ticks(void) { return milliseconds * UINT64_C(100000); }
uint32_t s3_clock_hz(void) { return 100000000; }
uint32_t s3_milliseconds(void) { return milliseconds; }
uint32_t s3_input(void) { return 0; }
uint32_t s3_frame_count(void) { return frame_count; }
void s3_wait_frame(void) { frame_count++; }
void s3_rnd_run(const struct rnd_batch *batch)
{
    /* RN-17 checks the ownership protocol in the host platform boundary. */
    for (size_t i = 0; i < batch->target_count; ++i) {
        uintptr_t begin = (uintptr_t)batch->targets[i].address;
        uintptr_t scan = (uintptr_t)scan_surface;
        if (scan_surface && begin < scan + scan_bytes &&
            scan < begin + batch->targets[i].bytes) {
            fputs("FAIL RND target is the scanning Surface\n", stderr);
            abort();
        }
    }
    timing = (struct s3_rnd_timing) {
        .cache_ops = (batch->commands != uncached_commands &&
                      batch->commands != uncached_copy) +
                     batch->source_count + batch->target_count
    };
    /* rnd_ref consumes batch sources as its address space. Cached A8 bytes
     * are already clean and immutable on board; expose them only to the model,
     * without counting them as another per-doorbell clean.
     */
    struct rnd_range sources[batch->source_count + 1u];
    for (size_t i = 0; i < batch->source_count; ++i) sources[i] = batch->sources[i];
    sources[batch->source_count] = s3_draw_rnd_glyph_cache();
    struct rnd_batch model = *batch;
    model.sources = sources;
    model.source_count++;
    execute_batch(&model);
}
uint64_t s3_rnd_elapsed_ticks(void) { return 0; }
struct s3_rnd_timing s3_rnd_last_timing(void) { return timing; }
void s3_cpu_begin(void) { }
void s3_cpu_end(struct s3_cpu_counters *c) { *c = (struct s3_cpu_counters) {0}; }
_Noreturn void s3_stop(void) { abort(); }
/* No hardware counters or advancing tick inside a synchronous host dispatch. */
void __wrap_rnd_read_perf(uint32_t perf[6])
{
    for (unsigned i = 0; i < 6; ++i) perf[i] = 0;
}
void __wrap_mem_xbar_snapshot(struct mem_xbar_stats *stats)
{
    *stats = (struct mem_xbar_stats) {0};
}
void s3_display_begin(const void *l0, uint32_t stride, const void *l1, uint32_t stride1)
{
    (void)stride; (void)l1; (void)stride1;
    scan_surface = l0;
    scan_bytes = stride * 720;
    frame_count++;
}
void s3_display_stop(void) { scan_surface = NULL; }
void s3_display_present(const void *l0, uint32_t stride, const void *l1, uint32_t stride1)
{
    s3_display_begin(l0, stride, l1, stride1);
}
void s3_puts(const char *text) { fputs(text, stdout); fflush(stdout); }
void s3_put_u32(uint32_t value) { printf("%u", value); }
void s3_put_hex(uint32_t value) { printf("%08x", value); }
void cache_clean(uintptr_t address, uint32_t bytes) { (void)address; (void)bytes; }
void cache_invalidate(uintptr_t address, uint32_t bytes) { (void)address; (void)bytes; }
void cache_clean_invalidate(uintptr_t address, uint32_t bytes) { (void)address; (void)bytes; }
void cache_clean_all(void) { }
void plic_set_priority(uint32_t source, uint32_t priority) { (void)source; (void)priority; }
void plic_set_enable(uint32_t mask) { (void)mask; }

/* The integration test's small menu is created by the caller, never by the
 * LVGL service. C's complete S3 menu can use the same host platform services.
 */
void s3_host_menu(void)
{
    lv_obj_t *screen = lv_screen_active();
    lv_obj_set_style_bg_opa(screen, LV_OPA_COVER, 0);
    lv_obj_set_style_bg_color(screen, lv_color_hex(0x102133), 0);
    lv_obj_t *label = lv_label_create(screen);
    lv_label_set_text(label, "S3 host lifecycle check");
    lv_obj_center(label);
}

/* RN-17's ARGB mask check uses the locked native renderer before composition. */
#include "src/draw/lv_draw_private.h"
#include "src/draw/sw/lv_draw_sw.h"
void s3_host_mask_reference(uint32_t *pixels, int32_t width, int32_t height,
                             int32_t x0, int32_t y0, int32_t x1, int32_t y1,
                             int32_t radius, bool keep_outside)
{
    lv_draw_buf_t buffer;
    lv_draw_buf_init(&buffer, (uint32_t)width, (uint32_t)height, LV_COLOR_FORMAT_ARGB8888,
                     (uint32_t)width * 4u, pixels, (uint32_t)(width * height) * 4u);
    lv_layer_t layer = { .draw_buf = &buffer, .color_format = LV_COLOR_FORMAT_ARGB8888,
                         .buf_area = { 0, 0, width - 1, height - 1 } };
    lv_draw_task_t task = { .target_layer = &layer, .clip_area = layer.buf_area };
    lv_draw_mask_rect_dsc_t dsc = { .area = { x0, y0, x1, y1 }, .radius = radius,
                                  .keep_outside = keep_outside };
    lv_draw_sw_mask_rect(&task, &dsc);
}
