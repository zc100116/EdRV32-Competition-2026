/* page_graphics.c — showcase 4.6.3; measured benchmark and paired renderer cases.
 * Results are backend measurements; the desktop backend marks scripted data.
 */
#include "theme.h"
#include "renderer.h"
static lv_obj_t *progress;
static lv_obj_t *benchmark_back;
static void stop_clicked(lv_event_t *e) { (void)e; ui_data_benchmark_stop(); }
void ui_benchmark_controls(bool show)
{
    if(show) {
        benchmark_back=ui_box(lv_layer_sys(),8,8,124,36,PANEL);
        ui_label(benchmark_back,"‹ 返回",14,8,&sim_font_16,ACCENT);
        lv_obj_set_clickable(benchmark_back,true);
        lv_obj_add_event_cb(benchmark_back,stop_clicked,LV_EVENT_CLICKED,NULL);
    } else {
        lv_obj_delete(benchmark_back); benchmark_back=NULL;
    }
}
void ui_graphics_action(unsigned action)
{
    if(action<2) { ui_tab=action; ui_mode=0; ui_open(4); }
    else if(action==2) { ui_data_benchmark_start(); ui_refresh(); }
    else if(action==3) { ui_mode=0; ui_data_render_start(RENDER_TEST_COUNT); }
    else {
        unsigned test=action-10;
        ui_mode=test+1;
        ui_data_render_start(test);
        ui_open(4);
    }
}
static void result(lv_obj_t *p,unsigned test)
{
    const ui_render_result_t *r=&ui_data_render_results()[test];
    ui_label(p,r->name,42,162,&sim_font_28,TEXT);
    if(test==TEST_LAYERS) {
        ui_label(p,"L0 卷轴 · L1 移动 / 透明度",42,214,&sim_font_20,TEAL);
        return;
    }
    for(unsigned side=0;side<2;++side) {
        lv_obj_t *card=ui_box(p,40+(int)side*612,212,588,298,PANEL);
        ui_label(card,side ? "LVGL 软件渲染" : "RND 硬件渲染",20,14,&sim_font_20,ACCENT);
        if(r->complete) {
            ui_picture(card,ui_data_render_image(side),20,60,384,192);
            char s[64];
            lv_snprintf(s,sizeof(s),"%u us",side ? r->software_us : r->hardware_us);
            ui_label(card,s,20,267,&sim_font_16,TEXT);
        }
    }
    char s[192];
    if(r->complete) {
        unsigned ratio=r->hardware_us ? r->software_us*100/r->hardware_us : 0;
        unsigned percent=r->equal*10000/r->total;
        lv_snprintf(s,sizeof(s),"加速比 %u.%02u 倍    逐像素一致 %u / %u (%u.%02u%%)",
            ratio/100,ratio%100,r->equal,r->total,percent/100,percent%100);
    } else lv_snprintf(s,sizeof(s),"正在绘制与比较");
    ui_label(p,s,42,530,&sim_font_20,TEAL);
    ui_label(p,"圆角抗锯齿与混合舍入差异按实测显示",42,570,&sim_font_14,MUTED);
}
void ui_page_graphics(lv_obj_t *p)
{
    ui_title(p,"图形引擎");
    const char *tabs[]={"LVGL benchmark","渲染器功能测试"};
    for(unsigned i=0;i<2;++i) ui_button(p,tabs[i],40+(int)i*280,104,260,i);
    progress=NULL;
    if(ui_tab==1) {
        if(ui_mode) { result(p,ui_mode-1); return; }
        ui_button(p,"全部运行",1020,104,220,3);
        lv_obj_t *list=ui_box(p,40,163,1200,432,BG);
        lv_obj_set_scrollable(list,true); lv_obj_set_scroll_dir(list,LV_DIR_VER);
        const ui_render_result_t *r=ui_data_render_results();
        for(unsigned i=0;i<RENDER_TEST_COUNT;++i) {
            int x=(int)(i%2)*596,y=(int)(i/2)*52;
            ui_button(list,ui_render_names[i],x,y,572,10+i);
            if(r[i].complete) {
                char s[80];
                lv_snprintf(s,sizeof(s),"%u/%u  %u us / %u us",r[i].equal,r[i].total,
                    r[i].hardware_us,r[i].software_us);
                ui_label(lv_obj_get_child(list,-1),s,240,12,&sim_font_14,TEAL);
            }
        }
        return;
    }
    const ui_benchmark_t *rows=ui_data_benchmark();
    for(unsigned col=0;col<2;++col) {
        lv_obj_t *card=ui_box(p,40+(int)col*612,164,588,350,PANEL);
        ui_label(card,"场景",16,12,&sim_font_16,MUTED);
        ui_label(card,"每帧 ms",370,12,&sim_font_16,MUTED);
        ui_label(card,"fps",500,12,&sim_font_16,MUTED);
        for(unsigned r=0;r<8;++r) {
            unsigned n=col*8+r;
            int y=50+(int)r*36;
            ui_label(card,rows[n].name,16,y,&sim_font_16,TEXT);
            char s[40];
            lv_snprintf(s,sizeof(s),"%u.%u",rows[n].ms_tenths/10,rows[n].ms_tenths%10);
            ui_label(card,s,380,y,&sim_font_16,ACCENT);
            lv_snprintf(s,sizeof(s),"%u.%u",rows[n].fps_tenths/10,rows[n].fps_tenths%10);
            ui_label(card,s,500,y,&sim_font_16,TEXT);
        }
    }
    ui_button(p,"开始测试",40,544,180,2);
    progress=ui_label(p,"",244,555,&sim_font_16,MUTED);
}
void ui_graphics_update(void)
{
    if(!progress) return;
    char s[96]; unsigned n=ui_data_benchmark_progress();
    lv_snprintf(s,sizeof(s),"%s · %u / 16 个场景",ui_data_benchmark_running() ?
        "测试中，返回立即停止" : n==16 ? "测试完成" : n ? "已停止" : "按确认开始",n);
    ui_text(progress,s);
}
