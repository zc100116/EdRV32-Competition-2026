/* File: host_test.c
 * Spec: Task B2-4b acceptance; design 2026-10-29-b2-software 3.3–3.5a.
 * Description: Independent wire/layout vectors, menu bounds and integer frame division.
 * Clock domain: none (host-only pure logic).
 */
#include "demo.h"
#include "overlay.h"
#include "cache.h"
#include "font8x16.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

void demo_test_switching(void);

static uint32_t word(const uint8_t *p)
{
    return (uint32_t)p[0] + 256u * p[1] + 65536u * p[2] + 16777216u * p[3];
}

static void test_monitor(void)
{
    struct eth_monitor r = {0};
    uint8_t out[320];
    r.sequence = 0x12345678;
    r.scene = 1;
    r.time = UINT64_C(0x1122334455667788);
    r.memory.window_cycles = 1250000;
    r.memory.downstream_busy = 1000000;
    r.memory.direction_switches = 27;
    for (unsigned int p = 0; p < 7; ++p) {
        r.memory.port[p] = (struct mem_xbar_port_stats){
            100u * p + 1u, 100u * p + 2u, 100u * p + 3u, 100u * p + 4u,
            100u * p + 5u, 100u * p + 6u, 100u * p + 7u};
    }
    for (unsigned int i = 0; i < 4; ++i) {
        r.vin[i] = 701u + i;
        r.npu[i] = 801u + i;
    }
    r.disp[0] = 901;
    r.disp[1] = 902;
    r.eth[0] = 1001;
    r.eth[1] = 1002;
    r.idle_cycles = 12345;
    r.system_hz = 100000000;
    r.video_skips = 0xfedcba98;
    memset(out, 0xff, sizeof out);
    eth_monitor_pack(out, &r);
    const uint8_t header[] = {'E','D','T','M', 1,0,1,0, 0x78,0x56,0x34,0x12,
        1,0,0,0, 0x88,0x77,0x66,0x55,0x44,0x33,0x22,0x11};
    assert(memcmp(out, header, sizeof header) == 0);
    assert(word(out + 24) == 1250000);
    assert(word(out + 28) == 1000000);
    assert(word(out + 32) == 27);
    for (unsigned int p = 0; p < 7; ++p) {
        for (unsigned int field = 0; field < 7; ++field) {
            assert(word(out + 36 + p * 28 + field * 4) == p * 100 + field + 1);
        }
    }
    for (unsigned int i = 0; i < 4; ++i) {
        assert(word(out + 232 + i * 4) == 701 + i);
        assert(word(out + 256 + i * 4) == 801 + i);
    }
    assert(word(out + 248) == 901);
    assert(word(out + 252) == 902);
    assert(word(out + 272) == 1001);
    assert(word(out + 276) == 1002);
    assert(word(out + 280) == 12345);
    assert(word(out + 284) == 100000000);
    assert(word(out + 288) == 180000000);
    assert(word(out + 292) == 0xfedcba98);
    for (unsigned int i = 296; i < 320; ++i) {
        assert(out[i] == 0);
    }
}

static void test_video(void)
{
    uint8_t out[32];
    const uint8_t expected[32] = {
        'E','D','V','F', 1,0,1,0, 0,5,0xd0,2, 0,10,0,0,
        0x78,0x56,0x34,0x12, 8,7,6,5,4,3,2,1, 2,0,0,0
    };
    demo_video_pack(out, 0x12345678, UINT64_C(0x0102030405060708), 2);
    assert(memcmp(out, expected, sizeof out) == 0);
}

static void test_detections(void)
{
    uint8_t out[1216];
    yolo_detection boxes[100] = {{-1, -2, 1280, 720, 79, 1000}};
    const uint8_t expected[28] = {
        'E','D','D','T', 1,0,1,0, 0xef,0xcd,0xab,0x89, 0,0,0,0,
        0xff,0xff,0xfe,0xff,0,5,0xd0,2,79,0,0xe8,3
    };
    assert(demo_detection_pack(out, boxes, 1, 0x89abcdef) == 28);
    assert(memcmp(out, expected, sizeof expected) == 0);
    assert(demo_detection_pack(out, boxes, 0, UINT32_MAX) == 16);
    assert(out[6] == 0 && out[7] == 0);
    assert(word(out + 8) == UINT32_MAX);
    boxes[99] = (yolo_detection){10, 20, 30, 40, 0, 250};
    assert(demo_detection_pack(out, boxes, 100, 1) == 1216);
    assert(out[6] == 100 && out[7] == 0);
    const uint8_t last[] = {10,0,20,0,30,0,40,0,0,0,250,0};
    assert(memcmp(out + 1204, last, 12) == 0);
}

static void test_commands(void)
{
    const struct {
        const char *line;
        enum demo_command_kind kind;
        unsigned int value;
    } commands[] = {
        {"help", DEMO_HELP, 0}, {"status", DEMO_STATUS, 0},
        {"s1", DEMO_SCENE, 1}, {"s2", DEMO_SCENE, 2},
        {"pix bypass", DEMO_PIX, 0}, {"pix brightness", DEMO_PIX, 1},
        {"pix gamma", DEMO_PIX, 2}, {"pix gaussian", DEMO_PIX, 3},
        {"pix sobel", DEMO_PIX, 4}, {"geo off", DEMO_GEO, 0},
        {"geo rotate", DEMO_GEO, 1}, {"geo scale", DEMO_GEO, 2},
        {"output hdmi", DEMO_OUTPUT, 0}, {"output eth", DEMO_OUTPUT, 1},
        {"output both", DEMO_OUTPUT, 2}, {"fps 1", DEMO_FPS, 1},
        {"fps 60", DEMO_FPS, 60}, {"sample 10", DEMO_SAMPLE, 10},
        {"sample 100", DEMO_SAMPLE, 100}, {"sample 1000", DEMO_SAMPLE, 1000}
    };
    for (unsigned int i = 0; i < sizeof commands / sizeof commands[0]; ++i) {
        struct demo_command result;
        assert(demo_parse(commands[i].line, &result) == 0);
        assert(result.kind == commands[i].kind);
        assert(result.value == commands[i].value);
    }
    const char *bad[] = {"", "s3", "S1", "s1 ", "pix", "geo", "output",
        "fps", "fps ", "fps 0", "fps 61", "fps -1", "fps 1x", "fps 1 2",
        "fps 99999999999999999999999999999999999999999999999",
        "sample 9", "sample 1001", "sample +100", "probe on"};
    for (unsigned int i = 0; i < sizeof bad / sizeof bad[0]; ++i) {
        struct demo_command result;
        assert(demo_parse(bad[i], &result) == -1);
    }
}

static void test_frame_division(void)
{
    for (unsigned int source = 30; source <= 60; source += 30) {
        for (unsigned int target = 1; target <= 60; ++target) {
            unsigned int divisor = demo_frame_divisor(source, target);
            assert(divisor >= 1 && divisor <= source);
            assert(source <= target * divisor);
            if (divisor > 1) {
                assert(source > target * (divisor - 1));
            }
            unsigned int count = 0;
            for (unsigned int frame = 1; frame <= source * 60u; ++frame) {
                count += (unsigned int)demo_frame_due(frame, divisor);
            }
            assert(count == source * 60u / divisor);
        }
    }
    assert(demo_frame_divisor(30, 7) == 5);
    assert(demo_frame_divisor(30, 60) == 1);
    assert(demo_frame_divisor(60, 60) == 1);
    assert(demo_frame_due(0, 1));
    assert(demo_frame_due(UINT32_MAX, 3));
}

static void test_layout(void)
{
    assert(DEMO_DESC_BASE == 0x00080000 && DEMO_DESC_SIZE == 65536);
    assert(DEMO_MODEL_BASE == 0x00100000 && DEMO_MODEL_SIZE == 4 * 1024 * 1024);
    assert(DEMO_WORK_BASE == 0x01000000 && DEMO_WORK_SIZE == 8 * 1024 * 1024);
    assert(DEMO_INPUT_BASE == 0x04000000 && DEMO_INPUT_COUNT == 3);
    assert(DEMO_INPUT_SPACING == 1024 * 1024 && DEMO_INPUT_BYTES == 983040);
    assert(DEMO_OUTPUT_BASE == 0x05000000 && DEMO_OUTPUT_COUNT == 2);
    assert(DEMO_OUTPUT_SPACING == 1024 * 1024 && DEMO_OUTPUT_BYTES == 725760);
    assert(DEMO_IMAGE_BASE == 0x06000000 && DEMO_IMAGE_COUNT == 4);
    assert(DEMO_IMAGE_SPACING == 2 * 1024 * 1024 && DEMO_IMAGE_BYTES == 1843200);
    assert(DEMO_GEO_BASE == 0x07000000 && DEMO_GEO_COUNT == 2);
    assert(DEMO_OVERLAY_BASE == 0x07400000 && DEMO_OVERLAY_SPACING == 0x00400000);
    assert(DEMO_OVERLAY_RESOURCE_BASE == 0x07c00000);
    assert(DEMO_OVERLAY_STRIDE == 5120 && DEMO_OVERLAY_BYTES == 3686400);
    assert(DEMO_GEO_BASE + 2u * DEMO_IMAGE_SPACING <= DEMO_OVERLAY_BASE);
    assert(DEMO_OVERLAY_BASE + 2u * DEMO_OVERLAY_SPACING <= DEMO_OVERLAY_RESOURCE_BASE);
    assert(DEMO_OVERLAY_ZERO + DEMO_OVERLAY_BYTES <= DEMO_OVERLAY_COMMANDS);
    assert(DEMO_OVERLAY_COMMANDS + DEMO_OVERLAY_COMMAND_COUNT * 64u <= DEMO_OVERLAY_FONT);
    assert(DEMO_OVERLAY_FONT + 95u * 16u <= DEMO_WINDOW_BASE);
    assert(DEMO_WINDOW_BASE == 0x08000000 && DEMO_WINDOW_SIZE == 2 * 1024 * 1024);
    assert(DEMO_MODEL_WINDOW == 0x09000000 && DEMO_MODEL_WINDOW_SIZE == 16 * 1024 * 1024);
    assert(DEMO_COMMAND_WINDOW == 0x0a000000 && DEMO_COMMAND_WINDOW_SIZE == 65536);
    assert(DEMO_SEND_BASE == 0x0a100000 && DEMO_SEND_SIZE == 4 * 1024 * 1024);
    assert(DEMO_STRIDE == 2560 && DEMO_WIDTH == 1280 && DEMO_HEIGHT == 720);
    assert(DEMO_IMAGE_BYTES == DEMO_STRIDE * DEMO_HEIGHT);
    assert(DEMO_WORKSPACE == 0x01800000 && DEMO_WORKSPACE_BYTES == 120960);
    assert(DEMO_WORKSPACE >= DEMO_WORK_BASE + DEMO_WORK_SIZE);
    assert(DEMO_WORKSPACE + DEMO_WORKSPACE_BYTES <= DEMO_INPUT_BASE);
    assert(DEMO_TX_DESCRIPTORS + 3u * 32u <= DEMO_TX_VIDEO);
    assert(DEMO_TX_VIDEO + 32u <= DEMO_TX_DETECTIONS);
    assert(DEMO_TX_DETECTIONS + 1216u <= DEMO_GEO_DESCRIPTOR);
    assert(DEMO_GEO_DESCRIPTOR + 64u <= DEMO_TX_MONITOR);
    assert(DEMO_TX_MONITOR + 16u * 320u <= DEMO_MONITOR_RING);
    assert(DEMO_MONITOR_RING + DEMO_MONITOR_CAPACITY * 320u <=
           DEMO_SEND_BASE + DEMO_SEND_SIZE);
}

static void test_model(void)
{
    uint8_t header[32] = {'E','D','N','M', 1,0,0,0, 68,0,0,0, 0,17,0,0,
        0,123,49,0, 0,0,0,1, 0,0,0,4, 0,0,0,5};
    uint32_t bytes = 32u + 4352u + 3242752u;
    assert(demo_model_header(header, bytes) == NULL);
    assert(strcmp(demo_model_header(header, bytes - 1), "Model bytes") == 0);
    header[0] = 'X';
    assert(strcmp(demo_model_header(header, bytes), "EDNM magic/version") == 0);
    header[0] = 'E';
    header[4] = 2;
    assert(strcmp(demo_model_header(header, bytes), "EDNM magic/version") == 0);
    header[4] = 1;
    header[20] = 32;
    assert(strcmp(demo_model_header(header, bytes), "EDNM base layout") == 0);
    header[20] = 0;
    header[12] = 1;
    assert(strcmp(demo_model_header(header, bytes), "EDNM descriptor/model length") == 0);
}

static uint32_t overlay_pixels[2][DEMO_WIDTH * DEMO_HEIGHT];
static uint32_t overlay_visible[2][DEMO_WIDTH * DEMO_HEIGHT];
static unsigned int overlay_clean_slot;
static unsigned int overlay_cleans;

/* Emulate the BSP clean boundary: DISP sees only bytes already written back. */
void cache_clean(uintptr_t address, uint32_t size)
{
    uintptr_t base = (uintptr_t)overlay_pixels[overlay_clean_slot];
    assert(address >= base && address + size <= base + DEMO_OVERLAY_BYTES);
    assert((address - base) % DEMO_OVERLAY_STRIDE + size <= DEMO_OVERLAY_STRIDE);
    memcpy((uint8_t *)overlay_visible[overlay_clean_slot] + address - base,
           (const void *)address, size);
    ++overlay_cleans;
}

static void check_overlay(unsigned int slot, const yolo_detection *boxes,
                          const char *const *labels, unsigned int count)
{
    /* Independent per-pixel evaluation of overlay.c's RND command parameters:
     * BORDER radius=0/width=1/sides=15; FILL green OPA=255; A1 white MSB-first.
     * The label rectangle, like RND's CLIP, intersects the 1280x720 Surface.
     */
    for (unsigned int y = 0; y < DEMO_HEIGHT; ++y) {
        for (unsigned int x = 0; x < DEMO_WIDTH; ++x) {
            uint32_t expected = x == 800u && y == 300u ? 0x12345678u : 0;
            for (unsigned int i = 0; i < count; ++i) {
                const yolo_detection *b = &boxes[i];
                if (x >= (unsigned int)b->x0 && x < (unsigned int)b->x1 &&
                    y >= (unsigned int)b->y0 && y < (unsigned int)b->y1 &&
                    (x == (unsigned int)b->x0 || x + 1u == (unsigned int)b->x1 ||
                     y == (unsigned int)b->y0 || y + 1u == (unsigned int)b->y1)) {
                    expected = 0xff00ff00u;
                }
                unsigned int top = b->y0 >= 16 ? (unsigned int)b->y0 - 16u :
                                                (unsigned int)b->y0;
                unsigned int width = (unsigned int)strlen(labels[i]) * 8u;
                if (x >= (unsigned int)b->x0 && x < (unsigned int)b->x0 + width &&
                    y >= top && y < top + 16u) {
                    expected = 0xff00ff00u;
                    unsigned int local = x - (unsigned int)b->x0;
                    unsigned int ch = (uint8_t)labels[i][local / 8u] - 32u;
                    if (font8x16[ch][y - top] & (0x80u >> (local % 8u))) {
                        expected = 0xffffffffu;
                    }
                }
            }
            unsigned int at = y * DEMO_WIDTH + x;
            assert(overlay_pixels[slot][at] == expected);
            assert(overlay_visible[slot][at] == expected);
        }
    }
}

static void test_overlay(void)
{
    struct demo_dirty dirty[2] = {0};
    const yolo_detection first[] = {
        {40, 60, 180, 130, 0, 875},
        {1264, 4, 1280, 30, 2, 1000},
        {400, 700, 450, 720, 79, 250}
    };
    const char *const first_labels[] = {"person 0.875", "car 1.000", "toothbrush 0.250"};
    const yolo_detection second[] = {
        {100, 100, 220, 180, 15, 900}, {108, 110, 109, 111, 2, 500}
    };
    const char *const second_labels[] = {"cat 0.900", "car 0.500"};
    for (unsigned int slot = 0; slot < 2; ++slot) {
        overlay_pixels[slot][300u * DEMO_WIDTH + 800u] = 0x12345678u;
        overlay_visible[slot][300u * DEMO_WIDTH + 800u] = 0x12345678u;
    }
    overlay_clean_slot = 0;
    demo_overlay_cpu_draw(overlay_pixels[0], &dirty[0], first, 3);
    assert(dirty[0].count == 15 && overlay_cleans == 286);
    assert(dirty[0].rect[0].x1 == 179 && dirty[0].rect[0].y1 == 60);
    assert(dirty[0].rect[4].x1 == 135 && dirty[0].rect[4].y0 == 44);
    check_overlay(0, first, first_labels, 3);
    check_overlay(1, NULL, NULL, 0);
    overlay_clean_slot = 1;
    demo_overlay_cpu_draw(overlay_pixels[1], &dirty[1], second, 2);
    check_overlay(1, second, second_labels, 2);
    check_overlay(0, first, first_labels, 3);
    overlay_clean_slot = 0;
    demo_overlay_cpu_draw(overlay_pixels[0], &dirty[0], second, 2);
    check_overlay(0, second, second_labels, 2);
    check_overlay(1, second, second_labels, 2);
    /* YOLO's display clipping can collapse a box at an image boundary. */
    const yolo_detection edges[] = {
        {1280, 0, 1280, 20, 0, 0}, {50, 0, 70, 0, 0, 0}, {300, 720, 320, 720, 2, 500}
    };
    const char *const edge_labels[] = {"person 0.000", "person 0.000", "car 0.500"};
    demo_overlay_cpu_draw(overlay_pixels[0], &dirty[0], edges, 3);
    check_overlay(0, edges, edge_labels, 3);
    for (unsigned int slot = 0; slot < 2; ++slot) {
        overlay_clean_slot = slot;
        demo_overlay_cpu_draw(overlay_pixels[slot], &dirty[slot], NULL, 0);
        assert(dirty[slot].count == 0);
        check_overlay(slot, NULL, NULL, 0);
    }
}

static unsigned int dirty_pixels(const struct demo_dirty *dirty)
{
    unsigned int pixels = 0;
    for (unsigned int i = 0; i < dirty->count; ++i) {
        const struct demo_rect *r = &dirty->rect[i];
        pixels += (unsigned int)(r->x1 - r->x0 + 1) * (unsigned int)(r->y1 - r->y0 + 1);
    }
    return pixels;
}

static void test_overlay_moving(void)
{
    struct demo_dirty dirty[2] = {0};
    yolo_detection boxes[] = {
        {40, 60, 640, 460, 0, 875}, {200, 160, 800, 560, 0, 875},
        {600, 300, 1200, 700, 0, 875}
    };
    const char label[] = "person 0.875";
    unsigned int glyph_writes = 0;
    for (unsigned int j = 0; j < strlen(label); ++j) {
        for (unsigned int row = 0; row < 16; ++row) {
            for (unsigned int bit = 0; bit < 8; ++bit) {
                glyph_writes += !!(font8x16[(uint8_t)label[j] - 32u][row] & (0x80u >> bit));
            }
        }
    }
    /* Count pixel stores, including repeated corners, overlaps and white glyph writes. */
    unsigned int draw_writes = 3u * (2u * (600u + 400u) +
                                    (unsigned int)(sizeof label - 1u) * 8u * 16u + glyph_writes);
    memset(overlay_pixels, 0, sizeof overlay_pixels);
    memset(overlay_visible, 0, sizeof overlay_visible);
    overlay_clean_slot = 0;
    demo_overlay_cpu_draw(overlay_pixels[0], &dirty[0], boxes, 3);
    unsigned int clear_writes = dirty_pixels(&dirty[0]);
    assert(clear_writes == 10608);
    for (unsigned int i = 0; i < 3; ++i) {
        boxes[i].x0 += 20;
        boxes[i].x1 += 20;
        boxes[i].y0 += 10;
        boxes[i].y1 += 10;
    }
    overlay_cleans = 0;
    demo_overlay_cpu_draw(overlay_pixels[0], &dirty[0], boxes, 3);
    unsigned int moving_cleans = overlay_cleans;
    assert(moving_cleans == 4908);
    overlay_clean_slot = 1;
    demo_overlay_cpu_draw(overlay_pixels[1], &dirty[1], boxes, 3);
    /* A moved frame must equal the same frame drawn into a never-used transparent slot. */
    assert(memcmp(overlay_pixels[0], overlay_pixels[1], sizeof overlay_pixels[0]) == 0);
    assert(memcmp(overlay_visible[0], overlay_visible[1], sizeof overlay_visible[0]) == 0);
    for (unsigned int slot = 0; slot < 2; ++slot) {
        overlay_clean_slot = slot;
        demo_overlay_cpu_draw(overlay_pixels[slot], &dirty[slot], NULL, 0);
        for (unsigned int i = 0; i < DEMO_WIDTH * DEMO_HEIGHT; ++i) {
            assert(overlay_pixels[slot][i] == 0 && overlay_visible[slot][i] == 0);
        }
    }
    printf("CPU L1 3x600x400 steady frame before: writes=%u (clear=%u draw=%u), cleans=12\n",
           3u * (600u * 400u + (unsigned int)(sizeof label - 1u) * 8u * 16u) + draw_writes,
           3u * (600u * 400u + (unsigned int)(sizeof label - 1u) * 8u * 16u), draw_writes);
    printf("CPU L1 3x600x400 steady frame after: writes=%u (clear=%u draw=%u), cleans=%u\n",
           clear_writes + draw_writes, clear_writes, draw_writes, moving_cleans);
}

int main(void)
{
    test_monitor();
    test_video();
    test_detections();
    test_commands();
    test_frame_division();
    test_layout();
    test_model();
    test_overlay();
    test_overlay_moving();
    demo_test_switching();
    puts("PASS demo: EDTM, EDVF, EDDT, menu, frame division, DDR layout, EDNM, "
         "CPU L1 pixels/dirty/cache, PIX/GEO/scene/output event sequences");
    return 0;
}
