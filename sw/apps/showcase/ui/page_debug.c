/* page_debug.c — showcase design §4.3; UART and network inspection.
 * Buttons call data actions; changed labels update on the 2 Hz UI timer.
 */
#include "widgets.h"
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
static void tab_changed(lv_event_t *event)
{
    ui_tab=lv_tabview_get_tab_active(lv_event_get_target_obj(event)); ui_open(8);
}
void ui_page_debug(lv_obj_t *p)
{
    ui_page_layout(p,"调试助手",false);
    lv_obj_t *tabs=lv_tabview_create(p); ui_widget_style(tabs);
    lv_obj_set_size(tabs,LV_PCT(100),LV_PCT(84));
    lv_tabview_set_tab_bar_size(tabs,44);
    lv_obj_t *serial=lv_tabview_add_tab(tabs,"串口");
    lv_obj_t *net=lv_tabview_add_tab(tabs,"网口");
    lv_tabview_set_active(tabs,ui_tab,LV_ANIM_OFF);
    lv_obj_add_event_cb(tabs,tab_changed,LV_EVENT_VALUE_CHANGED,NULL);
    ui_control(lv_tabview_get_tab_bar(tabs));
    lv_obj_t *active=ui_tab ? net : serial;
    lv_obj_set_flex_flow(active,LV_FLEX_FLOW_ROW);
    lv_obj_set_style_pad_gap(active,UI_SPACE_LG,0);
    lv_obj_t *panel=ui_panel(active,LV_PCT(65));
    ui_text_label(panel,ui_tab ? "收到的 UDP 数据" : "收发数据",&sim_font_20,TEXT);
    data_text=ui_text_label(panel,"",&sim_font_16,TEXT);
    lv_obj_set_width(data_text,LV_PCT(100));
    lv_obj_t *side=ui_panel(active,LV_PCT(32));
    ui_text_label(side,"通信状态",&sim_font_20,TEXT);
    counters=ui_text_label(side,"",&sim_font_16,TEXT);
    if(ui_tab==0) {
        format=ui_flex_switch(panel,"十六进制",false);
        lv_obj_add_event_cb(format,format_changed,LV_EVENT_VALUE_CHANGED,NULL);
        baud=ui_select(panel,"115200\n921600\n2000000");
        lv_obj_add_event_cb(baud,baud_changed,LV_EVENT_VALUE_CHANGED,NULL);
        ui_text_label(side,"测试串：Hello EdRV32!",&sim_font_16,MUTED);
        ui_action_button(side,"发送预置测试串",4); ui_action_button(side,"清空",5);
    } else {
        network=ui_text_label(side,"",&sim_font_16,TEXT);
        echo=ui_text_label(panel,"",&sim_font_16,MUTED);
        ui_action_button(side,"清零回环统计",6);
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
