/* page_debug.c — showcase design §4.3; UART and network inspection.
 * Buttons call data actions; changed labels update on the 2 Hz UI timer.
 */
#include "theme.h"
static lv_obj_t *data_text;
static lv_obj_t *counters;
static lv_obj_t *format;
static lv_obj_t *baud;
static lv_obj_t *network;
static lv_obj_t *echo;
void ui_page_debug(lv_obj_t *p)
{
    ui_title(p, "调试助手", "连接、观察与验证，让通信状态清晰可见");
    ui_button(p, "串口", 40, 118, 190, 0);
    ui_button(p, "网口", 250, 118, 190, 1);
    lv_obj_t *panel = ui_box(p, 40, 178, 816, 422, PANEL);
    ui_label(panel, ui_tab ? "收到的 UDP 数据" : "收发数据", 24, 20, &sim_font_20, TEXT);
    data_text = ui_label(panel, "", 24, 70, &sim_font_16, TEXT);
    lv_obj_set_width(data_text, 768);
    lv_obj_t *side = ui_box(p, 880, 178, 360, 422, PANEL);
    ui_label(side, "通信状态", 24, 20, &sim_font_20, TEXT);
    counters = ui_label(side, "", 24, 70, &sim_font_16, TEXT);
    if(ui_tab == 0) {
        ui_button(panel, "文本 / 十六进制", 24, 348, 200, 2);
        format = lv_obj_get_child(lv_obj_get_child(panel, -1), 0);
        ui_button(panel, "波特率", 240, 348, 240, 3);
        baud = lv_obj_get_child(lv_obj_get_child(panel, -1), 0);
        ui_button(side, "发送预置测试串", 24, 292, 312, 4);
        ui_button(side, "清空", 24, 348, 312, 5);
        ui_label(side, "测试串：Hello EdRV32!", 24, 236, &sim_font_16, MUTED);
    } else {
        network = ui_label(side, "", 24, 198, &sim_font_16, TEXT);
        echo = ui_label(panel, "", 24, 238, &sim_font_16, MUTED);
        ui_button(side, "回环测试", 24, 348, 312, 6);
    }
}
void ui_debug_update(void)
{
    ui_debug_t d = ui_data_debug();
    char s[300];
    ui_text(data_text, ui_tab ? d.udp_text : d.hex ? d.uart_hex : d.uart_text);
    if(ui_tab == 0) {
        lv_snprintf(s, sizeof(s), "接收    %u 字节\n\n发送    %u 字节", d.uart_rx, d.uart_tx);
        ui_text(counters, s);
        ui_text(format, d.hex ? "显示：十六进制" : "显示：文本");
        lv_snprintf(s, sizeof(s), "波特率：%u", d.baud); ui_text(baud, s);
    } else {
        lv_snprintf(s, sizeof(s), "接收    %u 包 / %u B\n\n发送    %u 包 / %u B",
            d.rx_packets, d.rx_bytes, d.tx_packets, d.tx_bytes); ui_text(counters, s);
        lv_snprintf(s, sizeof(s), "%s · 1000 Mbps\n\nPEER\n%s",
            d.link ? "已连接" : "未连接", d.peer); ui_text(network, s);
        lv_snprintf(s, sizeof(s), "回环测试\n\n次数 %u    平均往返 %u.%u ms    丢失 %u",
            d.echo_count, d.echo_tenths / 10, d.echo_tenths % 10, d.echo_lost);
        ui_text(echo, s);
    }
}
