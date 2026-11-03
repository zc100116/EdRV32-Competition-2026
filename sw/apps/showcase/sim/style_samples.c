/* style_samples.c — 一次性样板，风格选定后删除（设计记录 P1a）
 * Design 2026-11-03-showcase-ui §3–5: shared desktop style selection.
 * Simulated data only; LVGL timer clock, no hardware accesses.
 */
#include "style_samples.h"
#include <stdio.h>

LV_FONT_DECLARE(sim_font_14);
LV_FONT_DECLARE(sim_font_16);
LV_FONT_DECLARE(sim_font_20);
LV_FONT_DECLARE(sim_font_28);
LV_FONT_DECLARE(sim_font_40);
LV_FONT_DECLARE(sim_digits_40);
LV_FONT_DECLARE(sim_digits_48);

typedef struct {
    uint32_t background, gradient, panel, selected, line, text, muted, accent;
    const char *name;
} palette_t;
static const palette_t palettes[] = {
    {0x08141f, 0x08141f, 0x102431, 0x153e49, 0x254452, 0xeaf6fa, 0x91aab9,
     0x43e0ba, "深色科技"},
    {0xeff3f8, 0xeff3f8, 0xffffff, 0xeaf2ff, 0xd6e0ec, 0x152b45, 0x61748b,
     0x2468df, "浅色简洁"},
    {0x191329, 0x302042, 0x2a203b, 0x493046, 0x55405f, 0xfff4e8, 0xc2afc9,
     0xffbd69, "深紫仪表"}
};
static const char *names[] = {"视觉识别", "图片识别", "图像处理", "图形引擎",
    "游戏", "系统监控", "芯片信息", "调试助手"};
static const char *descriptions[] = {"发现镜头中的每一个目标", "上传图片，即刻了解结果",
    "当前硬件无此模块", "探索实时图形的表现力", "在经典像素世界中畅玩",
    "洞察每一份计算与带宽", "认识这颗自主设计的芯片", "连接设备，掌握通信状态"};
static const char *icons[] = {LV_SYMBOL_VIDEO, LV_SYMBOL_IMAGE, LV_SYMBOL_TINT,
    LV_SYMBOL_EDIT, LV_SYMBOL_PLAY, LV_SYMBOL_BARS, LV_SYMBOL_SETTINGS, LV_SYMBOL_USB};
static unsigned current_style;
static unsigned current_focus;
static unsigned step;
static bool monitoring;
static const palette_t *p;
static lv_obj_t *cards[8];
static lv_obj_t *chart;
static lv_chart_series_t *series[3];
static lv_obj_t *bandwidth[6][2];
static lv_obj_t *bandwidth_text[6];
static lv_obj_t *busy[2];
static lv_obj_t *large[2];
static lv_obj_t *status;

static lv_obj_t *box(lv_obj_t *parent, int x, int y, int w, int h, uint32_t color,
                     uint32_t border, int radius)
{
    lv_obj_t *obj = lv_obj_create(parent);
    lv_obj_remove_style_all(obj);
    lv_obj_set_pos(obj, x, y);
    lv_obj_set_size(obj, w, h);
    lv_obj_set_style_bg_color(obj, lv_color_hex(color), 0);
    lv_obj_set_style_bg_opa(obj, LV_OPA_COVER, 0);
    lv_obj_set_style_border_color(obj, lv_color_hex(border), 0);
    lv_obj_set_style_border_width(obj, border == color ? 0 : 1, 0);
    lv_obj_set_style_radius(obj, radius, 0);
    lv_obj_set_scrollable(obj, false);
    return obj;
}

static lv_obj_t *label(lv_obj_t *parent, const char *text, int x, int y,
                       const lv_font_t *font, uint32_t color)
{
    lv_obj_t *obj = lv_label_create(parent);
    lv_obj_remove_style_all(obj);
    lv_obj_set_style_text_font(obj, font, 0);
    lv_obj_set_style_text_color(obj, lv_color_hex(color), 0);
    lv_label_set_text(obj, text);
    lv_obj_set_pos(obj, x, y);
    return obj;
}

static void focus_update(void)
{
    for(unsigned i = 0; i < 8; ++i) {
        lv_obj_set_style_border_color(cards[i],
            lv_color_hex(i == current_focus ? p->accent : p->line), 0);
        lv_obj_set_style_border_width(cards[i], i == current_focus ? 2 : 1, 0);
        lv_obj_set_style_bg_color(cards[i],
            lv_color_hex(i == current_focus ? p->selected : p->panel), 0);
    }
}

static void card_click(lv_event_t *event)
{
    current_focus = (unsigned)(uintptr_t)lv_event_get_user_data(event);
    focus_update();
    samples_key(LV_KEY_ENTER);
}

static void home_page(lv_obj_t *screen)
{
    label(screen, "探索芯片的无限可能", 40, 76, &sim_font_40, p->text);
    label(screen, "边缘视觉 · 自主计算 · 实时交互", 42, 132, &sim_font_16, p->muted);
    label(screen, "应用中心  /  08", 1090, 136, &sim_font_16, p->accent);
    for(unsigned i = 0; i < 8; ++i) {
        int x = 40 + (int)(i % 4) * 306;
        int y = 181 + (int)(i / 4) * 238;
        cards[i] = box(screen, x, y, 282, 216, p->panel, p->line, 14);
        lv_obj_set_clickable(cards[i], true);
        lv_obj_add_event_cb(cards[i], card_click, LV_EVENT_CLICKED, (void *)(uintptr_t)i);
        uint32_t ink = i == 2 ? p->muted : p->accent;
        label(cards[i], icons[i], 24, 22, &sim_font_40, ink);
        label(cards[i], names[i], 24, 89, &sim_font_28, i == 2 ? p->muted : p->text);
        label(cards[i], descriptions[i], 24, 137, &sim_font_16, p->muted);
        label(cards[i], i == 2 ? "暂不可用" : "进入应用  >", 24, 177, &sim_font_14, ink);
    }
    focus_update();
}

static void monitor_page(lv_obj_t *screen)
{
    label(screen, "系统监控", 40, 70, &sim_font_40, p->text);
    label(screen, "实时计算与数据流，一目了然", 42, 124, &sim_font_16, p->muted);
    lv_obj_t *cpu = box(screen, 40, 171, 788, 235, p->panel, p->line, 14);
    label(cpu, "CPU 任务占用", 22, 17, &sim_font_20, p->text);
    const char *legend[] = {"通信服务", "当前应用", "图形界面"};
    uint32_t colors[] = {p->accent, 0x779ef2, 0xdb85b6};
    for(unsigned i = 0; i < 3; ++i)
        label(cpu, legend[i], 370 + (int)i * 130, 21, &sim_font_14, colors[i]);
    chart = lv_chart_create(cpu);
    lv_obj_remove_style_all(chart);
    lv_obj_set_pos(chart, 24, 66);
    lv_obj_set_size(chart, 740, 141);
    lv_obj_set_style_line_color(chart, lv_color_hex(p->line), LV_PART_MAIN);
    lv_obj_set_style_line_width(chart, 1, LV_PART_MAIN);
    lv_obj_set_style_line_width(chart, 2, LV_PART_ITEMS);
    lv_obj_set_style_size(chart, 0, 0, LV_PART_INDICATOR);
    lv_chart_set_type(chart, LV_CHART_TYPE_LINE);
    lv_chart_set_range(chart, LV_CHART_AXIS_PRIMARY_Y, 0, 100);
    lv_chart_set_div_line_count(chart, 4, 9);
    lv_chart_set_point_count(chart, 30);
    for(unsigned i = 0; i < 3; ++i) {
        series[i] = lv_chart_add_series(chart, lv_color_hex(colors[i]), LV_CHART_AXIS_PRIMARY_Y);
        for(unsigned j = 0; j < 30; ++j)
            lv_chart_set_next_value(chart, series[i], 12 + (int)i * 16 + (int)((j * 7 + i) % 19));
    }
    lv_obj_t *ddr = box(screen, 40, 426, 788, 230, p->panel, p->line, 14);
    label(ddr, "DDR 端口带宽", 22, 16, &sim_font_20, p->text);
    label(ddr, "读 / 写    MB/s", 592, 20, &sim_font_14, p->muted);
    const char *ports[] = {"CPU", "显示", "摄像头", "NPU", "渲染", "网口"};
    for(unsigned i = 0; i < 6; ++i) {
        int y = 54 + (int)i * 27;
        label(ddr, ports[i], 24, y, &sim_font_16, p->muted);
        box(ddr, 110, y + 4, 450, 7, p->line, p->line, 3);
        box(ddr, 110, y + 14, 450, 4, p->line, p->line, 2);
        bandwidth[i][0] = box(ddr, 110, y + 4, 200, 7, p->accent, p->accent, 3);
        bandwidth[i][1] = box(ddr, 110, y + 14, 100, 4, 0x779ef2, 0x779ef2, 2);
        bandwidth_text[i] = label(ddr, "", 590, y, &sim_font_16, p->text);
    }
    lv_obj_t *metrics = box(screen, 850, 171, 390, 485, p->panel, p->line, 14);
    label(metrics, "核心运行状态", 24, 18, &sim_font_20, p->text);
    label(metrics, "GUI 帧率", 24, 75, &sim_font_16, p->muted);
    const lv_font_t *digits = current_style == 2 ? &sim_digits_48 : &sim_digits_40;
    large[0] = label(metrics, "", 24, 100, digits, p->accent);
    label(metrics, "CPU 空闲率", 24, 174, &sim_font_16, p->muted);
    large[1] = label(metrics, "", 24, 199, digits, p->accent);
    label(metrics, "NPU 忙碌率", 24, 286, &sim_font_16, p->muted);
    busy[0] = label(metrics, "", 240, 280, &sim_font_28, p->text);
    label(metrics, "RND 忙碌率", 24, 350, &sim_font_16, p->muted);
    busy[1] = label(metrics, "", 240, 344, &sim_font_28, p->text);
    label(metrics, LV_SYMBOL_OK "  网口已连接 · 1000 Mbps", 24, 432, &sim_font_16, p->accent);
}

static void update(lv_timer_t *timer)
{
    (void)timer;
    ++step;
    unsigned seconds = lv_tick_get() / 1000;
    lv_label_set_text_fmt(status, "运行 00:%02u:%02u     CPU %u%%     网口 已连接     GUI %u FPS",
                          seconds / 60, seconds % 60, 28 + step % 9, 58 + step % 3);
    if(!monitoring) return;
    for(unsigned i = 0; i < 3; ++i)
        lv_chart_set_next_value(chart, series[i], 12 + (int)i * 16 + (int)((step * 7 + i) % 19));
    for(unsigned i = 0; i < 6; ++i) {
        unsigned read = 65 + (i * 61 + step * 13) % 350;
        unsigned write = 20 + (i * 47 + step * 7) % 210;
        lv_obj_set_width(bandwidth[i][0], (int)read);
        lv_obj_set_width(bandwidth[i][1], (int)write);
        lv_label_set_text_fmt(bandwidth_text[i], "%3u / %3u", read, write);
    }
    lv_label_set_text_fmt(large[0], "%u FPS", 58 + step % 3);
    lv_label_set_text_fmt(large[1], "%u %%", 63 + step % 9);
    lv_label_set_text_fmt(busy[0], "%u%%", 65 + step % 13);
    lv_label_set_text_fmt(busy[1], "%u%%", 21 + step % 11);
}

void samples_state(unsigned style, bool monitor, unsigned focus)
{
    current_style = style;
    monitoring = monitor;
    current_focus = focus;
    p = &palettes[style];
    lv_obj_t *screen = lv_screen_active();
    lv_obj_clean(screen);
    lv_obj_remove_style_all(screen);
    lv_obj_set_style_bg_color(screen, lv_color_hex(p->background), 0);
    lv_obj_set_style_bg_grad_color(screen, lv_color_hex(p->gradient), 0);
    lv_obj_set_style_bg_grad_dir(screen, LV_GRAD_DIR_VER, 0);
    lv_obj_set_style_bg_opa(screen, LV_OPA_COVER, 0);
    lv_obj_set_scrollable(screen, false);
    lv_obj_t *top = box(screen, 0, 0, 1280, 48, p->panel, p->panel, 0);
    label(top, "EdRV32", 40, 9, &sim_font_20, p->accent);
    label(top, "演示系统", 150, 12, &sim_font_16, p->text);
    status = label(top, "", 539, 14, &sim_font_14, p->muted);
    if(monitor) monitor_page(screen);
    else home_page(screen);
    lv_obj_t *bottom = box(screen, 0, 680, 1280, 40, p->panel, p->panel, 0);
    label(bottom, "← → 选择    Enter 确认    Esc 返回    1 / 2 / 3 切换风格",
          40, 10, &sim_font_14, p->muted);
    char caption[96];
    snprintf(caption, sizeof(caption), "样板 %c：%s", 'A' + (int)style, p->name);
    label(bottom, caption, 1040, 10, &sim_font_14, p->accent);
    update(NULL);
}

void samples_key(uint32_t key)
{
    if(key >= '1' && key <= '3') samples_state(key - '1', monitoring, current_focus);
    else if(key == LV_KEY_ESC) samples_state(current_style, false, current_focus);
    else if(!monitoring && key == LV_KEY_ENTER && current_focus == 5)
        samples_state(current_style, true, current_focus);
    else if(!monitoring && (key == LV_KEY_LEFT || key == LV_KEY_RIGHT)) {
        current_focus = (current_focus + (key == LV_KEY_RIGHT ? 1 : 7)) % 8;
        focus_update();
    }
}

void samples_start(void)
{
    samples_state(0, false, 0);
    lv_timer_create(update, 500, NULL);
}
