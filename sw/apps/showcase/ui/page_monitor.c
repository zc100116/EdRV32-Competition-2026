/* page_monitor.c — showcase design §4.3; three task curves and DDR meters.
 * Curve updates follow seconds; other changed objects update at 2 Hz.
 */
#include "theme.h"
static lv_obj_t *chart;
static lv_chart_series_t *series[3];
static lv_obj_t *band[6][2];
static lv_obj_t *band_text[6];
static lv_obj_t *metrics[4];
static lv_obj_t *network;
static unsigned last_second;
void ui_page_monitor(lv_obj_t *p)
{
    ui_title(p, "系统监控", "实时计算与数据流，一目了然");
    lv_obj_t *cpu = ui_box(p, 40, 123, 788, 235, PANEL);
    ui_label(cpu, "CPU 任务占用", 22, 17, &sim_font_20, TEXT);
    const char *legend[] = {"通信服务", "当前应用", "图形界面"};
    uint32_t colors[] = {ACCENT, TEAL, 0x748ca6};
    for(unsigned i = 0; i < 3; ++i)
        ui_label(cpu, legend[i], 370 + (int)i * 130, 21, &sim_font_14, colors[i]);
    chart = lv_chart_create(cpu);
    lv_obj_remove_style_all(chart);
    lv_obj_set_pos(chart, 24, 66);
    lv_obj_set_size(chart, 740, 141);
    lv_obj_set_style_line_color(chart, lv_color_hex(LINE), LV_PART_MAIN);
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
    last_second = (unsigned)-1;
    lv_obj_t *ddr = ui_box(p, 40, 378, 788, 230, PANEL);
    ui_label(ddr, "DDR 端口带宽", 22, 16, &sim_font_20, TEXT);
    ui_label(ddr, "读 / 写    MB/s", 590, 20, &sim_font_14, MUTED);
    const char *ports[] = {"CPU", "显示", "摄像头", "NPU", "渲染", "网口"};
    for(unsigned i = 0; i < 6; ++i) {
        int y = 54 + (int)i * 27;
        ui_label(ddr, ports[i], 24, y, &sim_font_16, MUTED);
        ui_bar(ddr, 110, y + 4, 450, 1, ACCENT);
        band[i][0] = lv_obj_get_child(ddr, -1);
        ui_bar(ddr, 110, y + 14, 450, 1, TEAL);
        band[i][1] = lv_obj_get_child(ddr, -1);
        lv_obj_set_height(band[i][1], 4);
        band_text[i] = ui_label(ddr, "", 590, y, &sim_font_16, TEXT);
    }
    lv_obj_t *card = ui_box(p, 850, 123, 390, 485, PANEL);
    ui_label(card, "核心运行状态", 24, 18, &sim_font_20, TEXT);
    const char *titles[] = {"GUI 帧率", "CPU 空闲率", "NPU 忙碌率", "RND 忙碌率"};
    for(unsigned i = 0; i < 4; ++i) {
        int y = 75 + (int)i * 86;
        ui_label(card, titles[i], 24, y, &sim_font_16, MUTED);
        metrics[i] = ui_label(card, "", 24, y + 24, &sim_digits_40, ACCENT);
    }
    network = ui_label(card, "", 24, 442, &sim_font_16, ACCENT);
    ui_hint("Esc 返回首页    曲线每秒更新    读 / 写带宽以 MB/s 显示");
}
void ui_monitor_update(void)
{
    ui_system_t d = ui_data_system();
    if(d.seconds != last_second) {
        last_second = d.seconds;
        for(unsigned i = 0; i < 3; ++i)
            lv_chart_set_next_value(chart, series[i], (int)d.task_cpu[i]);
    }
    char s[96];
    for(unsigned i = 0; i < 6; ++i) {
        unsigned values[] = {d.ddr_read[i], d.ddr_write[i]};
        for(unsigned j = 0; j < 2; ++j)
            if(lv_obj_get_width(band[i][j]) != (int)values[j])
                lv_obj_set_width(band[i][j], (int)values[j]);
        lv_snprintf(s, sizeof(s), "%3u / %3u", values[0], values[1]);
        ui_text(band_text[i], s);
    }
    unsigned values[] = {d.fps, d.idle, d.npu_busy, d.rnd_busy};
    for(unsigned i = 0; i < 4; ++i) {
        lv_snprintf(s, sizeof(s), "%u %s", values[i], i == 0 ? "FPS" : "%");
        ui_text(metrics[i], s);
    }
    ui_text(network, d.link ? LV_SYMBOL_OK "  网口已连接 · 1000 Mbps" : "网口未连接");
}
