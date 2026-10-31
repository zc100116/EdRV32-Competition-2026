/* File: layers_check.c
 * Spec: DISP 4; DS-20; RN-30; SoC 7.3 R3/R4.
 * Description: Record production frame writes, check Surface bounds and native LVGL layers.
 * Clock domain: deterministic host frames.
 */
#include <assert.h>
#include <stdio.h>
#include "../layers.c"

static uint32_t registers[EDRV32_DISP_L1_OPA_OFFSET / 4 + 1];
static unsigned int writes;

static void record(uint32_t offset, uint32_t value, void *context)
{
    assert(context == registers);
    registers[offset / 4] = value;
    ++writes;
}

/* The host never enables physical scan; frame configuration uses record(). */
void engine_control(enum engine_id engine, uint32_t value)
{
    (void)engine;
    (void)value;
    assert(0 && "unexpected hardware control in host layer check");
}

void s3_layers_register_check(void)
{
    unsigned int edges = 0;
    unsigned int scroll_phases = 0;
    unsigned int transparent = 0;
    unsigned int opaque = 0;
    for (unsigned int scene = 1; scene <= 4; ++scene) {
        for (uint32_t frame = 0; frame < 6000; ++frame) {
            writes = 0;
            s3_layers_frame(scene, frame * 1000u / 60u, frame,
                            0x10000000, 0x10400000, record, registers);
            assert(writes == 9);
            uint32_t stride = registers[EDRV32_DISP_STRIDE_OFFSET / 4];
            uint32_t stride1 = registers[EDRV32_DISP_L1_STRIDE_OFFSET / 4];
            uint32_t scroll = registers[EDRV32_DISP_L0_SCROLL_OFFSET / 4];
            uint32_t sx = scroll & 0x7fffu;
            uint32_t sy = scroll >> 16;
            uint32_t pos = registers[EDRV32_DISP_L1_POS_OFFSET / 4];
            uint32_t size = registers[EDRV32_DISP_L1_SIZE_OFFSET / 4];
            uint32_t x = pos & 0xffffu;
            uint32_t y = pos >> 16;
            uint32_t w = size & 0xffffu;
            uint32_t h = size >> 16;
            uint32_t opa = registers[EDRV32_DISP_L1_OPA_OFFSET / 4];
            assert(registers[EDRV32_DISP_NEXT_BASE_OFFSET / 4] == 0x10000000);
            assert(registers[EDRV32_DISP_L1_NEXT_BASE_OFFSET / 4] == 0x10400000);
            assert(!(registers[EDRV32_DISP_NEXT_BASE_OFFSET / 4] & 4095));
            assert(!(registers[EDRV32_DISP_L1_NEXT_BASE_OFFSET / 4] & 4095));
            assert(stride == S3_LAYERS_WIDTH * 2u && !(stride & 31) && stride <= 65504);
            assert(!(stride1 & 31) && stride1 >= 4 * w && stride1 <= 65504);
            assert(((sx + 1280 + 15) / 16) * 16 <= S3_LAYERS_WIDTH);
            assert(sy + 720 <= S3_LAYERS_HEIGHT && sy <= 4095);
            assert(!(x & 7) && !(w & 7) && w >= 8 && x + w <= 1280);
            assert(h >= 1 && y + h <= 720);
            assert((h - 1) * stride1 + w * 4 <= sizeof(overlay));
            assert(registers[EDRV32_DISP_LAYER_CTRL_OFFSET / 4] == 3 && opa <= 255);
            if (scene == 2) {
                uint32_t t = frame * 1000u / 60u % 8000u;
                if (t >= 2000 && t < 3000) { assert(x + w == 1280); edges |= 2; }
                if (t >= 4000 && t < 5000) { assert(y == 0); edges |= 4; }
                if (t >= 6000 && t < 7000) { assert(y + h == 720); edges |= 8; }
                if (t < 1000) { assert(x == 0); edges |= 1; }
            }
            if (scene == 3) { transparent |= opa == 0; opaque |= opa == 255; }
            if (scene == 4) {
                assert(sx == frame * 3u % 257u && sy == frame % 129u);
                assert(x == 960 && y == 48);
                scroll_phases |= 1u << (sx & 15);
            }
        }
    }
    assert(edges == 15 && scroll_phases == 65535 && transparent && opaque);
    prepare(1);
    assert(overlay[0][0] >> 24 == 0 && overlay[0][1279] >> 24 == 255);
    for (unsigned int x = 1; x < 1280; ++x)
        assert((overlay[0][x] >> 24) >= (overlay[0][x - 1] >> 24));
    static const uint8_t alpha[] = {0, 64, 128, 192, 255};
    for (unsigned int i = 0; i < 5; ++i) assert(overlay[719][i * 256] >> 24 == alpha[i]);
    puts("PASS 24000 frame submissions: Surface bounds, four edge holds, opacity, scroll phases");
}

void s3_layers_lvgl_check(void)
{
    lvgl_scene();
    const struct s3_draw_rnd_stats *stats = s3_draw_rnd_stats();
    uint32_t claimed = stats->claimed[LV_DRAW_TASK_TYPE_LAYER];
    uint32_t unclaimed = stats->unclaimed[LV_DRAW_TASK_TYPE_LAYER];
    lv_refr_now(s3_lvgl_display());
    assert(stats->claimed[LV_DRAW_TASK_TYPE_LAYER] > claimed);
    assert(stats->unclaimed[LV_DRAW_TASK_TYPE_LAYER] == unclaimed);
    printf("PASS LVGL 50%% layer claimed=%u unclaimed=%u\n",
           stats->claimed[LV_DRAW_TASK_TYPE_LAYER] - claimed,
           stats->unclaimed[LV_DRAW_TASK_TYPE_LAYER] - unclaimed);
}
