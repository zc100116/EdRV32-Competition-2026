/* clear.c — RND 2.6 COPY / P5b 9.2; inspect real clear callback descriptors; host clock. */
#include "draw_rnd.h"
#include "src/draw/lv_draw_buf_private.h"
#include <assert.h>
#include <stdio.h>
static unsigned runs, cpu;
static struct rnd_command command;
void *platform_uncached(void *p) { return p; }
void showcase_rnd_run(const struct rnd_batch *batch)
{
    assert(batch->count == 1 && batch->source_count == 1 && batch->target_count == 1);
    command = batch->commands[0];
    assert(batch->sources[0].address == batch->targets[0].address);
    ++runs;
}
uint64_t showcase_rnd_elapsed_ticks(void) { return 100; }
struct showcase_rnd_timing showcase_rnd_last_timing(void)
{ return (struct showcase_rnd_timing){0}; }
void __wrap_rnd_read_perf(uint32_t perf[6]) { for (unsigned i = 0; i < 6; ++i) perf[i] = 0; }
void lv_draw_buf_clear_ex(lv_draw_buf_t *buf, const lv_area_t *area, lv_layer_t *layer)
{ (void)buf; (void)area; assert(!layer); ++cpu; }
static uint32_t xy(unsigned x, unsigned y) { return x | (y << 16); }
int main(void)
{
    uint32_t source = 0;
    for (unsigned fmt = 0; fmt < 2; ++fmt) {
        lv_draw_buf_t buf = {.header = {.cf = fmt ? LV_COLOR_FORMAT_ARGB8888 :
            LV_COLOR_FORMAT_RGB565, .w = 1280, .h = 720, .stride = fmt ? 5120 : 2560},
            .data = (uint8_t *)(uintptr_t)(fmt ? 0x90000000 : 0xd0000000)};
        lv_area_t area = {11, 7, 70, 29};
        showcase_draw_rnd_clear(&buf, &area, (lv_layer_t *)1);
        assert(command.word[0] == (5u | (fmt << 8) | (fmt << 12)));
        assert(command.word[1] == 0x10000000 && command.word[2] == buf.header.stride);
        assert(command.word[3] == xy(11, 7) && command.word[4] == xy(70, 29));
        assert(command.word[5] == xy(11, 7) && command.word[6] == xy(70, 29));
        if (fmt) assert(command.word[8] == source);
        source = command.word[8];
        assert(command.word[9] == (fmt ? 5120u : 2560u) && command.word[10] == 0);
        showcase_draw_rnd_clear(&buf, NULL, (lv_layer_t *)1);
        assert(command.word[5] == 0 && command.word[6] == xy(1279, 719));
        area = (lv_area_t){-3, -2, 3, 2};
        showcase_draw_rnd_clear(&buf, &area, (lv_layer_t *)1);
        assert(command.word[5] == 0 && command.word[6] == xy(3, 2));
    }
    /* Layer buffers can have padded rows: whole-buffer clear includes padding. */
    lv_draw_buf_t padded = {.header = {.cf = LV_COLOR_FORMAT_ARGB8888,
        .w = 19, .h = 9, .stride = 128}, .data = (uint8_t *)(uintptr_t)0x90000100};
    showcase_draw_rnd_clear(&padded, NULL, (lv_layer_t *)1);
    assert(command.word[1] == 0x10000100 && command.word[2] == 128);
    assert(command.word[5] == 0 && command.word[6] == xy(31, 8));
    lv_area_t clipped = {15, 6, 30, 20};
    showcase_draw_rnd_clear(&padded, &clipped, (lv_layer_t *)1);
    assert(command.word[5] == xy(15, 6) && command.word[6] == xy(18, 8));
    lv_draw_buf_t other = {.header = {.cf = LV_COLOR_FORMAT_A8, .w = 8, .h = 4,
        .stride = 8}, .data = (uint8_t *)(uintptr_t)0x90000000};
    showcase_draw_rnd_clear(&other, NULL, (lv_layer_t *)1);
    other.header.cf = LV_COLOR_FORMAT_RGB565;
    other.data = (uint8_t *)(uintptr_t)0x10000;
    showcase_draw_rnd_clear(&other, NULL, (lv_layer_t *)1);
    assert(runs == 8 && cpu == 2);
    assert(showcase_draw_rnd_stats()->clear_rnd == 8);
    assert(showcase_draw_rnd_stats()->clear_cpu_bytes == 64);
    puts("PASS clear COPY formats, DDR aliases, source, strides, rectangles and CPU dispatch");
}
