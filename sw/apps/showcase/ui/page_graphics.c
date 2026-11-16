/* page_graphics.c — showcase 4.6.3; measured benchmark and paired renderer cases.
 * Results are backend measurements; the desktop backend marks scripted data.
 */
#include "widgets.h"
#include "renderer.h"
static lv_obj_t *progress;
static lv_obj_t *benchmark_back;
void ui_benchmark_controls(bool show)
{
    if(show) {
        benchmark_back=ui_action_button(lv_layer_sys(),"‹ 返回",1004);
        lv_obj_align(benchmark_back,LV_ALIGN_TOP_LEFT,UI_SPACE_XS,UI_SPACE_XS);
        lv_obj_set_height(benchmark_back,36);
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
static void tabs_changed(lv_event_t *event)
{
    ui_graphics_action(lv_buttonmatrix_get_selected_button(lv_event_get_target_obj(event)));
}
static void result(lv_obj_t *p,unsigned test)
{
    const ui_render_result_t *r=&ui_data_render_results()[test];
    ui_text_label(p,r->name,&sim_font_28,TEXT);
    if(test==TEST_LAYERS) {
        ui_text_label(p,"L0 卷轴 · L1 移动 / 透明度",&sim_font_20,TEAL); return;
    }
    lv_obj_t *row=ui_stack(p,LV_FLEX_FLOW_ROW,UI_SPACE_LG);
    for(unsigned side=0;side<2;++side) {
        lv_obj_t *card=ui_panel(row,LV_PCT(48));
        ui_text_label(card,side ? "LVGL 软件渲染" : "RND 硬件渲染",&sim_font_20,ACCENT);
        if(r->complete) {
            lv_obj_t *image=lv_image_create(card);
            lv_image_set_src(image,ui_data_render_image(side));
            lv_obj_set_size(image,384,192);
            char text[80];
            lv_snprintf(text,sizeof text,"%u us",side ? r->software_us : r->hardware_us);
            ui_text_label(card,text,&sim_font_20,TEXT);
        }
    }
    char text[192];
    if(r->complete) {
        unsigned ratio=r->hardware_us ? r->software_us*100/r->hardware_us : 0;
        unsigned percent=r->equal*10000/r->total;
        lv_snprintf(text,sizeof text,"加速比 %u.%02u 倍 · 一致 %u / %u (%u.%02u%%)",
            ratio/100,ratio%100,r->equal,r->total,percent/100,percent%100);
    } else lv_snprintf(text,sizeof text,"正在绘制与比较");
    ui_text_label(p,text,&sim_font_20,TEAL);
    ui_text_label(p,"圆角抗锯齿与混合舍入差异按实测显示",&sim_font_14,MUTED);
}
void ui_page_graphics(lv_obj_t *p)
{
    lv_obj_t *header=ui_page_layout(p,"图形引擎",false);
    static const char *const tabs[]={"LVGL benchmark","渲染器功能测试",""};
    lv_obj_t *selector=ui_segment(header,tabs,ui_tab);
    lv_obj_set_width(selector,480);
    lv_obj_add_event_cb(selector,tabs_changed,LV_EVENT_VALUE_CHANGED,NULL);
    progress=NULL;
    if(ui_tab==1) {
        if(ui_mode) { result(p,ui_mode-1); return; }
        ui_action_button(header,"全部运行",3);
        lv_obj_t *list=ui_stack(p,LV_FLEX_FLOW_ROW_WRAP,UI_SPACE_SM);
        lv_obj_set_flex_grow(list,1); lv_obj_set_scrollable(list,true);
        const ui_render_result_t *r=ui_data_render_results();
        for(unsigned i=0;i<RENDER_TEST_COUNT;++i) {
            lv_obj_t *button=ui_action_button(list,ui_render_names[i],10+i);
            lv_obj_set_size(button,LV_PCT(48),64);
            if(r[i].complete) {
                char text[80];
                lv_snprintf(text,sizeof text,"%u/%u · %u / %u us",r[i].equal,r[i].total,
                    r[i].hardware_us,r[i].software_us);
                ui_text_label(button,text,&sim_font_14,TEAL);
            }
        }
        return;
    }
    ui_action_button(header,"开始测试",2);
    lv_obj_t *row=ui_stack(p,LV_FLEX_FLOW_ROW,UI_SPACE_LG);
    const ui_benchmark_t *rows=ui_data_benchmark();
    for(unsigned col=0;col<2;++col) {
        lv_obj_t *table=ui_data_table(row,3,9); lv_obj_set_width(table,LV_PCT(48));
        lv_table_set_column_width(table,0,310);
        lv_table_set_column_width(table,1,130); lv_table_set_column_width(table,2,130);
        lv_table_set_cell_value(table,0,0,"场景");
        lv_table_set_cell_value(table,0,1,"每帧 ms"); lv_table_set_cell_value(table,0,2,"fps");
        for(unsigned i=0;i<8;++i) {
            unsigned n=col*8+i; char text[40];
            lv_table_set_cell_value(table,i+1,0,rows[n].name);
            lv_snprintf(text,sizeof text,"%u.%u",rows[n].ms_tenths/10,rows[n].ms_tenths%10);
            lv_table_set_cell_value(table,i+1,1,text);
            lv_snprintf(text,sizeof text,"%u.%u",rows[n].fps_tenths/10,rows[n].fps_tenths%10);
            lv_table_set_cell_value(table,i+1,2,text);
        }
    }
    progress=ui_text_label(p,"",&sim_font_16,MUTED);
}
void ui_graphics_update(void)
{
    if(!progress) return;
    char s[96]; unsigned n=ui_data_benchmark_progress();
    lv_snprintf(s,sizeof(s),"%s · %u / 16 个场景",ui_data_benchmark_running() ?
        "测试中，返回立即停止" : n==16 ? "测试完成" : n ? "已停止" : "按确认开始",n);
    ui_text(progress,s);
}
