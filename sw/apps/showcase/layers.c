/* File: layers.c
 * Spec: DISP 2.4–2.7/4/5.3; DS-20; RN-30; SoC 7.3 R3/R4.
 * Description: Immutable DISP Surfaces exercise alpha, geometry, opacity and scroll;
 * LVGL renders a half-opacity widget container through its offscreen layer.
 * Clock domain: clk_sys CPU; DISP/RND execution in clk_mem.
 */
#include "apps.h"
#include "runtime.h"
#include "platform.h"
#include "cache.h"
#include "lvgl/showcase_lvgl.h"
#include "lvgl/draw_rnd.h"


static uint16_t background[848][1536]
    __attribute__((aligned(4096), section(".noinit")));
static uint32_t overlay[720][1280] __attribute__((aligned(4096), section(".noinit")));

void showcase_layers_frame(unsigned int scene, uint32_t milliseconds, uint32_t frame,
                     uint32_t l0, uint32_t l1, void (*write)(uint32_t, uint32_t, void *),
                     void *context)
{
    uint32_t x = 512;
    uint32_t y = 296;
    uint32_t width = 256;
    uint32_t height = 128;
    uint32_t opacity = 255;
    uint32_t scroll = 0;
    if (scene == 1) {
        x = 0;
        y = 0;
        width = 1280;
        height = 720;
    } else if (scene == 2) {
        /* Each two-second leg holds its edge for 1 s, then moves for 1 s.
         * X interpolation is in units of eight pixels (DISP 4.2).
         */
        static const uint16_t points[5][2] = {
            {0, 296}, {1024, 296}, {512, 0}, {512, 592}, {0, 296}
        };
        unsigned int leg = milliseconds / 2000u % 4u;
        uint32_t t = milliseconds % 2000u;
        t = t < 1000u ? 0u : t - 1000u;
        int32_t ax = points[leg][0] / 8;
        int32_t ay = points[leg][1];
        x = (uint32_t)(ax + ((int32_t)points[leg + 1][0] / 8 - ax) *
                       (int32_t)t / 1000) * 8u;
        y = (uint32_t)(ay + ((int32_t)points[leg + 1][1] - ay) * (int32_t)t / 1000);
    } else if (scene == 3) {
        uint32_t t = milliseconds % 4000u;
        opacity = (t <= 2000u ? t : 4000u - t) * 255u / 2000u;
    } else if (scene == 4) {
        scroll = (frame * 3u % 257u) | ((frame % 129u) << 16);
        x = 960;
        y = 48;
    }
    write(EDRV32_DISP_STRIDE_OFFSET, 1536 * 2u, context);
    write(EDRV32_DISP_NEXT_BASE_OFFSET, l0, context);
    write(EDRV32_DISP_L0_SCROLL_OFFSET, scroll, context);
    write(EDRV32_DISP_L1_STRIDE_OFFSET, scene == 1 ? 5120u : 1024u, context);
    write(EDRV32_DISP_L1_NEXT_BASE_OFFSET, l1, context);
    write(EDRV32_DISP_L1_POS_OFFSET, x | (y << 16), context);
    write(EDRV32_DISP_L1_SIZE_OFFSET, width | (height << 16), context);
    write(EDRV32_DISP_L1_OPA_OFFSET, opacity, context);
    write(EDRV32_DISP_LAYER_CTRL_OFFSET, 3, context);
}

static void register_write(uint32_t offset, uint32_t value, void *context)
{
    (void)context;
    mmio_write32(EDRV32_DISP_BASE + offset, value);
}

static void prepare(unsigned int scene, unsigned first, unsigned last)
{
    static const uint16_t bars[] = {0xf800, 0xffe0, 0x07e0, 0x07ff, 0x001f, 0xf81f};
    uint16_t *l0 = &background[0][0];
    uint32_t *l1 = &overlay[0][0];
    /* The previous owner is IDLE: these Surfaces are never written during scan. */
    for (unsigned int y = first; y < last && y < 848; ++y) {
        for (unsigned int x = 0; x < 1536; ++x) {
            uint16_t color = bars[x / 256u];
            if (scene == 4 && ((x / 32u + y / 32u) & 1u)) color >>= 1;
            l0[y * 1536 + x] = color;
        }
    }
    unsigned int width = scene == 1 ? 1280u : 256u;
    unsigned int height = scene == 1 ? 720u : 128u;
    static const uint8_t alpha[] = {0, 64, 128, 192, 255};
    for (unsigned int y = first; y < last && y < height; ++y) {
        for (unsigned int x = 0; x < width; ++x) {
            uint32_t a = scene == 1 ? (y < 360 ? x * 255u / 1279u : alpha[x / 256u])
                                    : 255u;
            uint32_t color = scene == 1 ? 0xffffffu :
                (((x / 16u + y / 16u) & 1u) ? 0xff8020u : 0x2080ffu);
            l1[y * width + x] = (a << 24) | color;
        }
    }
}

static void text(lv_obj_t *parent, const char *value, int x, int y)
{
    lv_obj_t *label = lv_label_create(parent);
    lv_label_set_text(label, value);
    lv_obj_set_pos(label, x, y);
}

static void lvgl_scene(void)
{
    lv_obj_t *screen = lv_screen_active();
    lv_obj_clean(screen);
    for (unsigned int i = 0; i < 8; ++i) {
        lv_obj_t *stripe = lv_obj_create(screen);
        lv_obj_set_pos(stripe, (int)i * 160, 0);
        lv_obj_set_size(stripe, 160, 720);
        lv_obj_set_style_bg_color(stripe, lv_color_hex(i & 1u ? 0x124f70 : 0xe8bd60), 0);
        lv_obj_set_style_border_width(stripe, 0, 0);
        lv_obj_set_style_radius(stripe, 0, 0);
    }
    lv_obj_t *panel = lv_obj_create(screen);
    lv_obj_set_pos(panel, 240, 160);
    lv_obj_set_size(panel, 800, 400);
    lv_obj_set_style_bg_color(panel, lv_color_hex(0xf0f4ff), 0);
    /* LVGL 9.6 opa_layered applies 50% to the composed container and children. */
    lv_obj_set_style_opa_layered(panel, LV_OPA_50, 0);
    text(panel, "05  LVGL LAYER / 50% OPACITY", 30, 20);
    text(panel, "Background stripes remain visible through every control", 30, 65);
    lv_obj_t *button = lv_button_create(panel);
    lv_obj_set_pos(button, 30, 120);
    lv_obj_set_size(button, 220, 60);
    text(button, "HALF OPACITY", 10, 8);
    lv_obj_t *slider = lv_slider_create(panel);
    lv_obj_set_pos(slider, 320, 140);
    lv_obj_set_width(slider, 340);
    lv_slider_set_value(slider, 65, LV_ANIM_OFF);
    lv_obj_t *check = lv_checkbox_create(panel);
    lv_obj_set_pos(check, 30, 235);
    lv_checkbox_set_text(check, "Offscreen container + RND BLIT");
    lv_obj_add_state(check, LV_STATE_CHECKED);
    text(screen, "LAYERS  KEY1/a previous   KEY2/d next   KEY4/p return", 240, 630);
}

static void expectation(unsigned int scene)
{
    static const char *messages[] = {
        "LAYERS 1: Color bars under white L1; upper alpha rises left 0 -> right 255.\r\n"
        "Lower five blocks: alpha 0/64/128/192/255; smooth monotonic blending.\r\n",
        "LAYERS 2: 256x128 checker moves to LEFT, RIGHT, TOP, BOTTOM; holds ~1 s.\r\n"
        "Each edge is flush; no L1 pixels remain outside the moving rectangle.\r\n",
        "LAYERS 3: Fixed checker fades 0 -> 255 -> 0 in ~4 s, without jumps.\r\n",
        "LAYERS 4: Color grid scrolls X +3 / Y +1 each frame; fixed L1 at top right.\r\n"
        "Grid stays aligned and tear-free, including non-16-aligned scroll.\r\n",
        "LAYERS 5: 50% opacity container, button, slider and checkbox over stripes.\r\n"
        "Uniform transparency, aligned control edges; RND claims LAYER blend.\r\n"
    };
    platform_puts(messages[scene - 1]);
}

static unsigned scene;
static unsigned next_scene;
static unsigned prepare_row;
static unsigned phase;
static uint32_t start;
static uint32_t frame;
static uint32_t previous_keys;
void layers_enter(void)
{
    scene = 1;
    next_scene = 1;
    phase = 0;
    prepare_row = 0;
    previous_keys = platform_keys();
    app_wake_at(platform_ticks());
}
void layers_exit(void)
{
    engine_control(ENGINE_DISP, 0);
}
void layers_step(void)
{
    uint32_t keys = platform_keys();
    uint32_t pressed = keys & ~previous_keys;
    previous_keys = keys;
    if (pressed & PLATFORM_BACK) { app_return(); return; }
    if (pressed & (PLATFORM_LEFT | PLATFORM_RIGHT)) {
        next_scene = (scene + ((pressed & PLATFORM_LEFT) ? 3u : 0u)) % 5u + 1u;
        engine_control(ENGINE_DISP, 0);
        app_gui_pause(1);
        phase = 0;
        prepare_row = 0;
    }
    if (phase == 0) {
        if (!platform_display_idle()) {
            app_wake_at(platform_ticks() + platform_clock_hz() / 1000u);
            return;
        }
        scene = next_scene;
        if (scene == 5) {
            lvgl_scene();
            app_gui_pause(0);
            phase = 3;
            expectation(scene);
            return;
        }
        /* Prepare one 16-row stripe per step; never monopolize the scheduler. */
        prepare(scene, prepare_row, prepare_row + 16u);
        prepare_row += 16;
        if (prepare_row < 848) {
            app_wake_at(platform_ticks());
            return;
        }
        cache_clean_all();
        showcase_layers_frame(scene, 0, 0, rnd_physical(background), rnd_physical(overlay),
                              register_write, NULL);
        engine_control(ENGINE_DISP, EDRV32_DISP_CTRL_ENABLE_MASK);
        start = platform_milliseconds();
        frame = 0;
        phase = 2;
        expectation(scene);
    } else if (phase == 2 && (app_events() & PLATFORM_FRAME)) {
        showcase_layers_frame(scene, platform_milliseconds() - start, ++frame,
                              rnd_physical(background), rnd_physical(overlay),
                              register_write, NULL);
    }
}
