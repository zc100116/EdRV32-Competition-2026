/* page_monitor.c — showcase 4.6.5; persistent 320x240 performance overlay.
 * The same objects render on the main sys layer or the NES software display.
 */
#include "widgets.h"
static lv_obj_t *window, *parent, *move_button, *close_button;
static lv_obj_t *fps, *busy, *tasks[3], *ports[7], *bars[7][2], *chart;
static lv_chart_series_t *series;
static lv_obj_t *usage[3], *link_led;
static bool visible, compact, suppressed;
static unsigned corner, last_second=UINT32_MAX;
static int32_t history[60];
static unsigned history_next;
static void update_timer(lv_timer_t *timer) { (void)timer; ui_monitor_update(); }
void ui_monitor_init(void) { lv_timer_create(update_timer,500,NULL); }
bool ui_monitor_visible(void) { return visible && !suppressed; }
void ui_monitor_suppress(bool hide)
{
    suppressed=hide;
    if(window) lv_obj_set_hidden(window,!ui_monitor_visible());
}
void ui_monitor_position(int *x,int *y)
{
    *x=(corner&1) ? 960 : 0;
    *y=(corner&2) ? 480 : 0;
}
static void position(void)
{
    const lv_align_t corners[]={LV_ALIGN_TOP_LEFT,LV_ALIGN_TOP_RIGHT,
                                LV_ALIGN_BOTTOM_LEFT,LV_ALIGN_BOTTOM_RIGHT};
    lv_obj_align(window,compact ? LV_ALIGN_TOP_LEFT : corners[corner],0,0);
}
void ui_monitor_corner(void) { corner=(corner+1)%4; if(window) position(); }
void ui_monitor_controls(void)
{
    if(!window) return;
    lv_group_add_obj(lv_group_get_default(),move_button);
    lv_group_add_obj(lv_group_get_default(),close_button);
}
static void build(void)
{
    window=ui_panel(parent,320); lv_obj_set_height(window,240);
    lv_obj_set_style_pad_all(window,4,0); lv_obj_set_style_pad_gap(window,0,0);
    lv_obj_t *heading=ui_stack(window,LV_FLEX_FLOW_ROW,6);
    ui_text_label(heading,"性能",&sim_font_14,ACCENT);
    link_led=lv_led_create(heading); lv_obj_set_size(link_led,12,12);
    move_button=ui_action_button(heading,"换角",1003);
    close_button=ui_action_button(heading,"关闭",1001);
    lv_obj_set_height(move_button,22); lv_obj_set_height(close_button,22);
    fps=ui_text_label(window,"",&sim_font_14,TEXT);
    busy=ui_text_label(window,"",&sim_font_14,TEXT);
    lv_obj_t *gauges=ui_stack(window,LV_FLEX_FLOW_ROW,6);
    for(unsigned i=0;i<3;++i) {
        usage[i]=lv_bar_create(gauges); ui_widget_style(usage[i]);
        lv_obj_set_size(usage[i],96,5); lv_bar_set_range(usage[i],0,100);
    }
    for(unsigned i=0;i<3;++i) tasks[i]=ui_text_label(window,"",&sim_font_14,TEXT);
    lv_obj_t *bandwidth=ui_stack(window,LV_FLEX_FLOW_ROW_WRAP,0);
    for(unsigned i=0;i<7;++i) {
        lv_obj_t *cell=ui_stack(bandwidth,LV_FLEX_FLOW_COLUMN,0);
        lv_obj_set_width(cell,150);
        ports[i]=ui_text_label(cell,"",&sim_font_14,MUTED);
        for(unsigned j=0;j<2;++j) {
            bars[i][j]=lv_bar_create(cell); ui_widget_style(bars[i][j]);
            lv_obj_set_size(bars[i][j],144,2); lv_bar_set_range(bars[i][j],0,4000);
        }
    }
    chart=lv_chart_create(window); lv_obj_remove_style_all(chart);
    lv_obj_set_size(chart,LV_PCT(100),24);
    lv_obj_set_style_bg_color(chart,lv_color_hex(SELECTED),0);
    lv_obj_set_style_bg_opa(chart,LV_OPA_COVER,0);
    lv_obj_set_style_line_width(chart,1,LV_PART_ITEMS);
    lv_obj_set_style_size(chart,0,0,LV_PART_INDICATOR);
    lv_chart_set_point_count(chart,60);
    lv_chart_set_range(chart,LV_CHART_AXIS_PRIMARY_Y,0,4000);
    series=lv_chart_add_series(chart,lv_color_hex(ACCENT),LV_CHART_AXIS_PRIMARY_Y);
    for(unsigned i=0;i<60;++i)
        lv_chart_set_next_value(chart,series,history[(history_next+i)%60]);
    position();
    lv_obj_set_hidden(window,!ui_monitor_visible());
}
void ui_monitor_parent(lv_obj_t *p,bool small)
{
    if(window) lv_obj_delete(window);
    parent=p; compact=small; build(); ui_monitor_update();
}
void ui_monitor_toggle(void)
{
    visible=!visible;
    if(!window) { parent=lv_layer_sys(); build(); }
    lv_obj_set_hidden(window,!ui_monitor_visible());
    if(visible) ui_monitor_update();
}
void ui_monitor_update(void)
{
    ui_system_t d=ui_data_system();
    unsigned total=0;
    for(unsigned i=0;i<7;++i) total+=d.ddr_read[i]+d.ddr_write[i];
    if(d.seconds!=last_second) {
        last_second=d.seconds; history[history_next]=total;
        history_next=(history_next+1)%60;
        if(window && visible) lv_chart_set_next_value(chart,series,(int32_t)total);
    }
    if(!window || !ui_monitor_visible()) return;
    char s[128];
    lv_snprintf(s,sizeof(s),"渲染 %u fps    显示 %u fps",d.fps,d.display_fps);
    ui_text(fps,s);
    lv_snprintf(s,sizeof(s),"CPU %u%%  NPU %u%%  RND %u%%",d.cpu,d.npu_busy,d.rnd_busy);
    ui_text(busy,s);
    unsigned percent[]={d.cpu,d.npu_busy,d.rnd_busy};
    for(unsigned i=0;i<3;++i) lv_bar_set_value(usage[i],percent[i],LV_ANIM_OFF);
    lv_led_set_color(link_led,lv_color_hex(d.link ? TEAL : 0xdc2626));
    const char *names[]={"通信","应用","界面"};
    for(unsigned i=0;i<3;++i) {
        lv_snprintf(s,sizeof(s),"%s %u%%   最长 %u us",names[i],d.task_cpu[i],d.task_max_us[i]);
        ui_text(tasks[i],s);
    }
    /* SoC 6.4.1 port order P0..P6; user-facing names only (no port numbers). */
    const char *ports_name[]={"显示","摄像头","CPU","NPU","渲染","几何","网口"};
    for(unsigned i=0;i<7;++i) {
        lv_snprintf(s,sizeof(s),"%s %u/%u MB/s",ports_name[i],d.ddr_read[i],d.ddr_write[i]);
        ui_text(ports[i],s);
        unsigned values[]={d.ddr_read[i],d.ddr_write[i]};
        for(unsigned j=0;j<2;++j) {
            lv_bar_set_value(bars[i][j],(int)values[j],LV_ANIM_OFF);
        }
    }
}
