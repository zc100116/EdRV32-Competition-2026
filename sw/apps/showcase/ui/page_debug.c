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
static void format_changed(lv_event_t *e)
{ (void)e; ui_data_debug_format(); ui_debug_update(); }
static void baud_changed(lv_event_t *e)
{
    const unsigned rates[]={115200,921600,2000000};
    unsigned target=lv_dropdown_get_selected(lv_event_get_target_obj(e));
    while(ui_data_debug().baud!=rates[target]) ui_data_debug_baud();
    ui_debug_update();
}
void ui_page_debug(lv_obj_t *p)
{
    ui_title(p, "调试助手");
    ui_button(p, "串口", 40, 118, 190, 0);
    ui_button(p, "网口", 250, 118, 190, 1);
    lv_obj_add_state(lv_obj_get_child(p,ui_tab==0 ? 1 : 2),LV_STATE_CHECKED);
    lv_obj_t *panel = ui_box(p, 40, 178, 816, 422, PANEL);
    ui_label(panel, ui_tab ? "收到的 UDP 数据" : "收发数据", 24, 20, &sim_font_20, TEXT);
    data_text = ui_label(panel, "", 24, 70, &sim_font_16, TEXT);
    lv_obj_set_width(data_text, 768);
    lv_obj_t *side = ui_box(p, 880, 178, 360, 422, PANEL);
    ui_label(side, "通信状态", 24, 20, &sim_font_20, TEXT);
    counters = ui_label(side, "", 24, 70, &sim_font_16, TEXT);
    if(ui_tab == 0) {
        ui_label(panel,"十六进制",24,356,&sim_font_16,TEXT);
        format=ui_switch(panel,130,355);
        lv_obj_add_event_cb(format,format_changed,LV_EVENT_VALUE_CHANGED,NULL);
        baud=ui_dropdown(panel,240,348,240,"115200\n921600\n2000000");
        lv_obj_add_event_cb(baud,baud_changed,LV_EVENT_VALUE_CHANGED,NULL);
        ui_button(side, "发送预置测试串", 24, 292, 312, 4);
        ui_button(side, "清空", 24, 348, 312, 5);
        ui_label(side, "测试串：Hello EdRV32!", 24, 236, &sim_font_16, MUTED);
    } else {
        network = ui_label(side, "", 24, 198, &sim_font_16, TEXT);
        echo = ui_label(panel, "", 24, 238, &sim_font_16, MUTED);
        ui_button(side, "清零回环统计", 24, 348, 312, 6);
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
        lv_obj_set_state(format,LV_STATE_CHECKED,d.hex);
        if(!lv_dropdown_is_open(baud))
            lv_dropdown_set_selected(baud,d.baud==115200 ? 0 : d.baud==921600 ? 1 : 2);
    } else {
        lv_snprintf(s, sizeof(s), "接收    %u 包 / %u B\n\n发送    %u 包 / %u B",
            d.rx_packets, d.rx_bytes, d.tx_packets, d.tx_bytes); ui_text(counters, s);
        lv_snprintf(s, sizeof(s), "%s · 1000 Mbps\n\nPEER\n%s",
            d.link ? "已连接" : "未连接", d.peer); ui_text(network, s);
        lv_snprintf(s, sizeof(s), "回环测试\n\n收到 ECHO %u    已回复 %u",
            d.echo_count, d.echo_replies);
        ui_text(echo, s);
    }
}
