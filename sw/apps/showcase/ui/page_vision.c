/* page_vision.c — showcase design 4.6.1; full-screen L0 with L1 detection objects.
 * Only result and statistic changes invalidate L1; video frames bypass LVGL.
 */
#include "widgets.h"
#include "detection.h"
#include "src/misc/lv_area_private.h"
static lv_obj_t *frame;
static lv_area_t boxes[5];
static bool box_visible[5];
static uint32_t metrics_tick;
static bool metrics_ready;
static lv_obj_t *tags[5];
static lv_obj_t *metrics;
static lv_obj_t *counts[5];
static lv_obj_t *results, *status_led, *spinner;
static lv_obj_t *categories[5];
static lv_obj_t *image_status, *image_detail;
static lv_obj_t *pause_label;

static lv_obj_t *filter_label;
static lv_obj_t *previous_button, *next_button, *box_switch;
static void draw_boxes(lv_event_t *e)
{
    lv_draw_rect_dsc_t d;
    lv_draw_rect_dsc_init(&d);
    d.bg_opa=LV_OPA_TRANSP;
    d.border_color=lv_color_hex(TEAL);
    d.border_width=2;
    for(unsigned i=0;i<5;++i)
        if(box_visible[i]) lv_draw_rect(lv_event_get_layer(e),&d,&boxes[i]);
}
static void edges(const lv_area_t *a,lv_area_t out[4])
{
    out[0]=(lv_area_t){a->x1,a->y1,a->x2,a->y1+1};
    out[1]=(lv_area_t){a->x1,a->y2-1,a->x2,a->y2};
    out[2]=(lv_area_t){a->x1,a->y1,a->x1+1,a->y2};
    out[3]=(lv_area_t){a->x2-1,a->y1,a->x2,a->y2};
}
static void update_box(unsigned i,bool show,const lv_area_t *next)
{
    bool was=box_visible[i];
    lv_area_t *old=&boxes[i];
    if(was==show && (!show || (old->x1==next->x1 && old->y1==next->y1 &&
       old->x2==next->x2 && old->y2==next->y2))) return;
    lv_area_t before[4],after[4];
    edges(old,before); edges(next,after);
    for(unsigned edge=0;edge<4;++edge) {
        /* Merge nearby strips to reduce traversal as well as pixel work. */
        lv_area_t joined;
        lv_area_join(&joined,&before[edge],&after[edge]);
        if(was && show && lv_area_get_size(&joined)<=
           2*(lv_area_get_size(&before[edge])+lv_area_get_size(&after[edge]))) {
            lv_obj_invalidate_area(frame,&joined);
        } else {
            if(was) lv_obj_invalidate_area(frame,&before[edge]);
            if(show) lv_obj_invalidate_area(frame,&after[edge]);
        }
    }
    *old=*next; box_visible[i]=show;
}
static void boxes_changed(lv_event_t *e)
{ (void)e; ui_data_boxes(); ui_refresh(); }
void ui_vision_build(lv_obj_t *p, bool batch)
{
    lv_obj_t *header=ui_camera_layout(p,batch ? "图片识别" : "目标检测计数");
    metrics=ui_camera_metrics(header);
    previous_button=ui_action_button(header,batch ? "上一张" : "暂停画面",0);
    pause_label=lv_obj_get_child(previous_button,0);
    if(batch) next_button=ui_action_button(header,"下一张",1);
    lv_obj_t *drawer=ui_camera_drawer(p,header,"检测设置");
    filter_label=ui_text_label(drawer,"",&sim_font_14,MUTED);
    if(!batch) {
        box_switch=ui_flex_switch(drawer,"检测框",true);
        lv_obj_set_width(lv_obj_get_parent(box_switch),210);
        lv_obj_add_event_cb(box_switch,boxes_changed,LV_EVENT_VALUE_CHANGED,NULL);
    }
    ui_detection_controls(drawer);
    metrics_ready=false;
    frame=ui_box(lv_screen_active(),0,0,1280,720,BG);
    lv_obj_set_style_bg_opa(frame,LV_OPA_TRANSP,0);
    lv_obj_set_style_border_width(frame,0,0);
    lv_obj_move_to_index(frame,0);
    lv_obj_add_event_cb(frame,draw_boxes,LV_EVENT_DRAW_MAIN,NULL);
    for(unsigned i=0;i<5;++i) {
        box_visible[i]=false;
        tags[i]=ui_text_label(frame,"",&sim_font_14,PANEL);
        lv_obj_set_style_bg_color(tags[i],lv_color_hex(TEAL),0);
        lv_obj_set_style_bg_opa(tags[i],LV_OPA_COVER,0);
    }
    lv_obj_t *side=ui_camera_card(p);
    lv_obj_set_style_pad_all(side,UI_SPACE_SM,0);
    lv_obj_set_style_pad_gap(side,4,0);
    if(batch) {
        results=ui_data_table(side,2,6);
        lv_obj_set_style_pad_ver(results,3,LV_PART_ITEMS);
        lv_table_set_column_width(results,0,120); lv_table_set_column_width(results,1,80);
        lv_table_set_cell_value(results,0,0,"目标");
        lv_table_set_cell_value(results,0,1,"置信度");
        lv_obj_t *state=ui_stack(drawer,LV_FLEX_FLOW_ROW,12);
        status_led=lv_led_create(state); lv_obj_set_size(status_led,18,18);
        spinner=lv_spinner_create(state); lv_obj_set_size(spinner,24,24);
        image_detail=ui_text_label(drawer,"",&sim_font_16,MUTED);
        image_status=ui_text_label(side,"",&sim_font_14,MUTED);
        lv_obj_set_width(image_status,LV_PCT(100));
    } else {
        for(unsigned i=0;i<5;++i) {
            lv_obj_t *row=ui_stack(side,LV_FLEX_FLOW_ROW,12);
            lv_obj_set_flex_align(row,LV_FLEX_ALIGN_START,LV_FLEX_ALIGN_CENTER,
                                  LV_FLEX_ALIGN_CENTER);
            categories[i]=ui_text_label(row,"",&sim_font_16,TEAL);
            lv_obj_set_width(categories[i],150);
            counts[i]=ui_text_label(row,"0",&sim_font_20,ACCENT);
        }
    }
}
void ui_vision_frame(bool batch)
{
    ui_vision_t d=ui_data_vision();
    char s[200];
    for(unsigned i = 0; i < 5; ++i) {
        bool show = i < d.count && d.boxes && (!batch || d.image_status==UI_IMAGE_DONE);
        ui_detection_t t = d.targets[i];
        lv_area_t next={t.x,t.y,t.x+t.width-1,t.y+t.height-1};
        update_box(i,show,&next);
        lv_obj_set_hidden(tags[i], !show);
        if(show) {
            lv_snprintf(s, sizeof(s), "%s %u%%", t.category, t.confidence);
            ui_text(tags[i], s);
            lv_obj_set_pos(tags[i], t.x, t.y < 22 ? 0 : t.y - 22);
        }
    }
}
void ui_vision_update(bool batch)
{
    ui_vision_t d = ui_data_vision();
    char s[200];
    ui_detection_config_t config=ui_data_detection_config();
    unsigned selected=0;
    for(unsigned i=0;i<80;++i) selected+=(config.classes[i/32]>>(i%32))&1u;
    lv_snprintf(s,sizeof(s),"≥%u.%02u · %u 类",config.threshold/100,
        config.threshold%100,selected); ui_text(filter_label,s);
    ui_vision_frame(batch);
    ui_camera_metrics_update(metrics);
    if(batch) {
        bool busy=d.image_status==UI_IMAGE_RECEIVING || d.image_status==UI_IMAGE_DETECTING;
        lv_obj_set_state(previous_button,LV_STATE_DISABLED,busy);
        lv_obj_set_state(next_button,LV_STATE_DISABLED,busy);
        lv_group_t *g=lv_group_get_default();
        lv_obj_t *focus=lv_group_get_focused(g);
        if(busy && (focus==previous_button || focus==next_button)) lv_group_focus_next(g);
        for(unsigned i = 0; i < 5; ++i) {
            bool available = i < d.count && (!batch || d.image_status==UI_IMAGE_DONE);
            lv_table_set_cell_value(results,i+1,0,available ? d.targets[i].category : "—");
            if(available) lv_snprintf(s, sizeof(s), "%u%%", d.targets[i].confidence);
            else lv_snprintf(s, sizeof(s), "—");
            lv_table_set_cell_value(results,i+1,1,s);
        }
        const char *states[]={"等待","接收中","识别中","完成","失败"};
        lv_snprintf(s,sizeof s,"%s\n\n%u / %u 张 · %s\n\n往返时间  %u ms",
            d.image_name,d.image_index,d.image_total,states[d.image_status],d.roundtrip_ms);
        ui_text(image_detail,s);
        ui_text(image_status,states[d.image_status]);
        lv_led_set_color(status_led,lv_color_hex(
            d.image_status==UI_IMAGE_FAILED ? 0xdc2626 : TEAL));
        lv_led_set_brightness(status_led,busy ? 120 : 255);
        lv_obj_set_hidden(spinner,!busy);
    } else {
        ui_text(pause_label, ui_data_session().state==UI_STATE_PAUSED ? "继续画面" : "暂停画面");
        lv_obj_set_state(box_switch,LV_STATE_CHECKED,d.boxes);
        if(metrics_ready && lv_tick_elaps(metrics_tick)<1000) return;
        metrics_ready=true; metrics_tick=lv_tick_get();
        ui_camera_metrics_update(metrics);
        for(unsigned i = 0; i < 5; ++i) {
            bool used=i<d.category_used;
            lv_obj_set_hidden(lv_obj_get_parent(categories[i]),!used);
            ui_text(categories[i],used ? ui_coco_names[d.category_id[i]] : "—");
            if(used) lv_snprintf(s, sizeof(s), "%u", d.category_count[i]);
            else s[0]=0;
            ui_text(counts[i], s);

        }
    }
}
void ui_page_vision(lv_obj_t *p) { ui_vision_build(p, false); }
