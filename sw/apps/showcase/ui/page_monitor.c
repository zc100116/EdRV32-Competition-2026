/* page_monitor.c — showcase 4.6.5; persistent 320x240 performance overlay.
 * The same objects render on the main sys layer or the NES software display.
 */
#include "theme.h"
static lv_obj_t *window, *parent;
static lv_obj_t *fps, *busy, *tasks[3], *ports[7], *bars[7][2], *chart;
static lv_chart_series_t *series;
static bool visible, compact;
static unsigned corner, last_second=UINT32_MAX;
static int32_t history[60];
static unsigned history_next;
static void update_timer(lv_timer_t *timer) { (void)timer; ui_monitor_update(); }
void ui_monitor_init(void) { lv_timer_create(update_timer,500,NULL); }
bool ui_monitor_visible(void) { return visible; }
void ui_monitor_position(int *x,int *y)
{
    *x=(corner&1) ? 960 : 0;
    *y=(corner&2) ? 480 : 0;
}
static void position(void)
{
    int x,y; ui_monitor_position(&x,&y);
    lv_obj_set_pos(window,compact ? 0 : x,compact ? 0 : y);
}
void ui_monitor_corner(void) { corner=(corner+1)%4; if(window) position(); }
static void move_clicked(lv_event_t *e) { (void)e; ui_monitor_corner(); }
static void close_clicked(lv_event_t *e) { (void)e; ui_monitor_toggle(); }
static void build(void)
{
    window=ui_box(parent,0,0,320,240,PANEL);
    lv_obj_set_style_radius(window,6,0);
    ui_label(window,"性能",8,4,&sim_font_14,ACCENT);
    lv_obj_t *move=ui_label(window,"换角",224,4,&sim_font_14,ACCENT);
    lv_obj_set_clickable(move,true);
    lv_obj_add_event_cb(move,move_clicked,LV_EVENT_CLICKED,NULL);
    lv_obj_t *close=ui_label(window,"关闭",276,4,&sim_font_14,MUTED);
    lv_obj_set_clickable(close,true);
    lv_obj_add_event_cb(close,close_clicked,LV_EVENT_CLICKED,NULL);
    fps=ui_label(window,"",8,24,&sim_font_14,TEXT);
    busy=ui_label(window,"",8,42,&sim_font_14,TEXT);
    for(unsigned i=0;i<3;++i) tasks[i]=ui_label(window,"",8,60+(int)i*17,&sim_font_14,TEXT);
    for(unsigned i=0;i<7;++i) {
        int x=8+(int)(i%2)*156, y=113+(int)(i/2)*21;
        ports[i]=ui_label(window,"",x,y,&sim_font_14,MUTED);
        for(unsigned j=0;j<2;++j) {
            bars[i][j]=ui_box(window,x,y+16+(int)j*2,1,2,j ? TEAL : ACCENT);
            lv_obj_set_style_border_width(bars[i][j],0,0);
        }
    }
    ui_label(window,"DDR 总带宽 / 60 秒",164,178,&sim_font_14,MUTED);
    chart=lv_chart_create(window);
    lv_obj_remove_style_all(chart);
    lv_obj_set_pos(chart,8,201); lv_obj_set_size(chart,304,31);
    lv_obj_set_style_line_width(chart,1,LV_PART_ITEMS);
    lv_obj_set_style_size(chart,0,0,LV_PART_INDICATOR);
    lv_chart_set_point_count(chart,60);
    lv_chart_set_range(chart,LV_CHART_AXIS_PRIMARY_Y,0,4000);
    series=lv_chart_add_series(chart,lv_color_hex(ACCENT),LV_CHART_AXIS_PRIMARY_Y);
    for(unsigned i=0;i<60;++i)
        lv_chart_set_next_value(chart,series,history[(history_next+i)%60]);
    position();
    lv_obj_set_hidden(window,!visible);
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
    lv_obj_set_hidden(window,!visible);
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
    if(!window || !visible) return;
    char s[128];
    lv_snprintf(s,sizeof(s),"渲染 %u fps    显示 %u fps",d.fps,d.display_fps);
    ui_text(fps,s);
    lv_snprintf(s,sizeof(s),"NPU %u%%   RND %u%%",d.npu_busy,d.rnd_busy); ui_text(busy,s);
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
            unsigned width=values[j]*144/4000;
            if(width>144) width=144;
            if(lv_obj_get_width(bars[i][j])!=(int)width) lv_obj_set_width(bars[i][j],(int)width);
        }
    }
}
