/* page_farm.c — R5-11; whole-area inventory, intrusion and daily dashboard.
 * GUI tick clock; full postprocessed COCO boxes use the existing camera pipeline.
 */
#include "widgets.h"
#include "detection.h"
#include "farm.h"
#include "grab.h"
#include <stdio.h>
#include <string.h>
enum { FARM_BOXES=100, RED=0xdc2626 };
static farm_t farm;
static lv_obj_t *surface, *metrics, *rows[FARM_CLASSES], *dashboard_rows[FARM_CLASSES];
static lv_obj_t *banner, *chart, *chart_scale, *timeline, *daily, *tags[FARM_BOXES];
static lv_chart_series_t *series[FARM_CLASSES];
static lv_area_t rectangles[FARM_BOXES];
static uint32_t rectangle_colors[FARM_BOXES];
static unsigned shown_count, timeline_revision, chart_revision;
static uint32_t report_tick, metrics_tick;
static const uint32_t colors[FARM_CLASSES]={TEAL,ACCENT,0xd97706,0x9333ea};
static void event_output(const farm_event_t *e)
{
    char line[120];
    snprintf(line,sizeof line,"farm event=%s class=%u amount=%u\r\n",
             farm_event_name(e->type),e->class_id,e->amount);
    ui_data_grab_output(line);
}

static void draw_boxes(lv_event_t *event)
{
    lv_draw_rect_dsc_t d;
    lv_draw_rect_dsc_init(&d);
    d.bg_opa=LV_OPA_TRANSP;
    d.border_color=lv_color_hex(TEAL);
    d.border_width=2;
    for(unsigned i=0;i<shown_count;++i) {
        d.border_color=lv_color_hex(rectangle_colors[i]);
        lv_draw_rect(lv_event_get_layer(event),&d,&rectangles[i]);
    }
}
static void invalidate_edges(const lv_area_t *a)
{
    lv_area_t strips[4]={{a->x1,a->y1,a->x2,a->y1+1},
        {a->x1,a->y2-1,a->x2,a->y2},{a->x1,a->y1,a->x1+1,a->y2},
        {a->x2-1,a->y1,a->x2,a->y2}};
    for(unsigned i=0;i<4;++i) lv_obj_invalidate_area(surface,&strips[i]);
}
static void update_chart(void)
{
    if(chart_revision==farm.sample_revision) return;
    chart_revision=farm.sample_revision;
    unsigned maximum=4;
    for(unsigned a=0;a<FARM_CLASSES;++a) {
        lv_chart_set_all_values(chart,series[a],LV_CHART_POINT_NONE);
        for(unsigned i=0;i<farm.sample_count;++i) {
            unsigned index=(farm.sample_head+FARM_SAMPLES-farm.sample_count+i)%FARM_SAMPLES;
            unsigned n=farm.samples[index].total[a];
            if(n>maximum) maximum=n;
            lv_chart_set_series_value_by_id(chart,series[a],i,(int32_t)n);
        }
    }
    lv_chart_set_axis_range(chart,LV_CHART_AXIS_PRIMARY_Y,0,(int32_t)maximum);
    char text[100];
    snprintf(text,sizeof text,"数量 0–%u · 每 10 秒采样",maximum);
    ui_text(chart_scale,text);
}
static void update_timeline(void)
{
    if(timeline_revision==farm.event_revision) return;
    timeline_revision=farm.event_revision;
    char text[3000];
    size_t used=0;
    for(unsigned i=0;i<farm.event_count;++i) {
        unsigned index=(farm.event_head+FARM_EVENTS-1-i)%FARM_EVENTS;
        const farm_event_t *e=&farm.events[index];
        char message[100];
        farm_event_text(e,message,sizeof message);
        unsigned sec=e->time_ms/1000;
        used+=(size_t)snprintf(text+used,sizeof text-used,"%02u:%02u:%02u  %s\n",
                              sec/3600,sec/60%60,sec%60,message);
    }
    ui_text(timeline,text);
}
void ui_farm_update(void)
{
    /* This reserves/acknowledges the camera snapshot exactly as the vision page does. */
    (void)ui_data_vision();
    unsigned count;
    const ui_detection_t *raw=ui_data_detections(&count);
    farm_box_t boxes[FARM_BOXES];
    unsigned confidence[FARM_BOXES];
    unsigned kept=0;
    for(unsigned i=0;i<count;++i) {
        const ui_detection_t *b=&raw[i];
        if(farm_animal(b->class_id)<0 && b->class_id!=0) continue;
        confidence[kept]=b->confidence;
        boxes[kept++]=(farm_box_t){b->class_id,b->x,b->y,b->width,b->height};
    }
    uint32_t now=lv_tick_get();
    farm_frame(&farm,boxes,kept,now);
    for(unsigned i=0;i<shown_count || i<kept;++i) {
        bool before=i<shown_count;
        bool after=i<kept;
        lv_area_t next={0};
        if(after) next=(lv_area_t){boxes[i].x,boxes[i].y,
            boxes[i].x+boxes[i].width-1,boxes[i].y+boxes[i].height-1};
        uint32_t color=after && boxes[i].class_id==0 ?
            (farm.intrude.active ? RED : ACCENT) : TEAL;
        if(before!=after || (after && (memcmp(&next,&rectangles[i],sizeof next) ||
                                      rectangle_colors[i]!=color))) {
            if(before) invalidate_edges(&rectangles[i]);
            if(after) invalidate_edges(&next);
            rectangles[i]=next;
            rectangle_colors[i]=color;
        }
        lv_obj_set_hidden(tags[i],!after);
        if(after) {
            char text[64];
            snprintf(text,sizeof text,"%s %u%%",ui_coco_names[boxes[i].class_id],confidence[i]);
            ui_text(tags[i],text);
            lv_obj_set_style_bg_color(tags[i],lv_color_hex(color),0);
            lv_obj_set_pos(tags[i],boxes[i].x,boxes[i].y<22 ? 0 : boxes[i].y-22);
        }
    }
    shown_count=kept;
    for(unsigned a=0;a<FARM_CLASSES;++a) {
        char text[100];
        bool missing=farm.counts[a]<farm.expected[a];
        snprintf(text,sizeof text,"%s %s%u%s / %u",ui_coco_names[farm_class_ids[a]],
                 missing ? "#dc2626 " : "",farm.counts[a],missing ? "#" : "",
                 farm.expected[a]);
        ui_text(rows[a],text);
        ui_text(dashboard_rows[a],text);
    }
    char text[120];
    snprintf(text,sizeof text,"今日走失 %u 次 · 闯入 %u 次",farm.missing_today,farm.intrude_today);
    ui_text(daily,text);
    bool alert=farm.intrude.active;
    if(alert) ui_text(banner,"有人闯入");
    else for(unsigned a=0;a<FARM_CLASSES;++a) {
        if(!farm.missing[a].active) continue;
        farm_event_t event={now,farm_class_ids[a],farm.expected[a]-farm.counts[a],FARM_MISSING};
        farm_event_text(&event,text,sizeof text);
        ui_text(banner,text);
        alert=true;
        break;
    }
    lv_obj_set_hidden(banner,!alert);
    update_chart();
    update_timeline();
    if(now-metrics_tick>=1000) {
        metrics_tick=now;
        ui_camera_metrics_update(metrics);
    }
    if(now-report_tick>=1000) {
        report_tick=now;
        char line[120];
        snprintf(line,sizeof line,"farm counts=%u,%u,%u,%u person=%u alerts=%u\r\n",
            farm.counts[0],farm.counts[1],farm.counts[2],farm.counts[3],
            farm.person,farm_alerts(&farm));
        ui_data_grab_output(line);
    }
}
void ui_farm_action(unsigned action)
{
    if(action==0) {
        farm_inventory(&farm,lv_tick_get());
        ui_farm_update();
    }
}
void ui_page_farm(lv_obj_t *parent)
{
    uint32_t now=lv_tick_get();
    farm_init(&farm,now,event_output);
    report_tick=metrics_tick=now;
    timeline_revision=chart_revision=0;
    shown_count=0;
    lv_obj_t *header=ui_camera_layout(parent,"智慧农场");
    metrics=ui_camera_metrics(header);
    ui_action_button(header,"盘点",0);
    surface=ui_box(parent,0,48,1280,672,BG);
    lv_obj_set_ignore_layout(surface,true);
    lv_obj_set_style_bg_opa(surface,LV_OPA_TRANSP,0);
    lv_obj_set_style_border_width(surface,0,0);
    /* Full-screen box coordinates match the real-time vision overlay. */
    lv_obj_set_pos(surface,0,0); lv_obj_set_height(surface,720);
    lv_obj_move_to_index(surface,0);
    lv_obj_add_event_cb(surface,draw_boxes,LV_EVENT_DRAW_MAIN,NULL);
    for(unsigned i=0;i<FARM_BOXES;++i) {
        tags[i]=ui_label(surface,"",0,0,&sim_font_14,PANEL);
        lv_obj_set_style_bg_color(tags[i],lv_color_hex(TEAL),0);
        lv_obj_set_style_bg_opa(tags[i],LV_OPA_COVER,0);
        lv_obj_set_hidden(tags[i],true);
    }
    lv_obj_t *card=ui_camera_card(parent);
    ui_text_label(card,"当前 / 基准",&sim_font_14,MUTED);
    for(unsigned a=0;a<FARM_CLASSES;++a) {
        rows[a]=ui_text_label(card,"",&sim_font_16,TEXT);
        lv_label_set_recolor(rows[a],true);
        lv_obj_set_width(rows[a],208);
    }
    banner=ui_label(parent,"",0,54,&sim_font_20,PANEL);
    lv_obj_set_ignore_layout(banner,true);
    lv_obj_set_style_bg_color(banner,lv_color_hex(RED),0);
    lv_obj_set_style_bg_opa(banner,LV_OPA_COVER,0);
    lv_obj_set_style_pad_all(banner,8,0);
    lv_obj_align(banner,LV_ALIGN_TOP_MID,0,54);
    lv_obj_set_hidden(banner,true);
    lv_obj_t *drawer=ui_camera_drawer(parent,header,"看板");
    lv_obj_set_style_pad_gap(drawer,8,0);
    ui_text_label(drawer,"动物盘点 · 当前 / 基准",&sim_font_20,TEXT);
    for(unsigned a=0;a<FARM_CLASSES;++a) {
        dashboard_rows[a]=ui_text_label(drawer,"",&sim_font_16,TEXT);
        lv_label_set_recolor(dashboard_rows[a],true);
        lv_obj_set_width(dashboard_rows[a],288);
    }
    daily=ui_text_label(drawer,"今日走失 0 次 · 闯入 0 次",&sim_font_16,TEXT);
    ui_text_label(drawer,"今日统计",&sim_font_20,TEXT);
    lv_obj_t *legend=ui_stack(drawer,LV_FLEX_FLOW_ROW,12);
    for(unsigned a=0;a<FARM_CLASSES;++a)
        ui_text_label(legend,ui_coco_names[farm_class_ids[a]],&sim_font_16,colors[a]);
    chart_scale=ui_text_label(drawer,"数量 0–4 · 每 10 秒采样",&sim_font_14,MUTED);
    chart=lv_chart_create(drawer);
    lv_obj_set_size(chart,288,140);
    lv_chart_set_type(chart,LV_CHART_TYPE_LINE);
    lv_chart_set_point_count(chart,FARM_SAMPLES);
    lv_chart_set_axis_range(chart,LV_CHART_AXIS_PRIMARY_Y,0,4);
    lv_obj_set_style_line_width(chart,2,LV_PART_ITEMS);
    lv_obj_set_style_size(chart,0,0,LV_PART_INDICATOR);
    for(unsigned a=0;a<FARM_CLASSES;++a) {
        series[a]=lv_chart_add_series(chart,lv_color_hex(colors[a]),LV_CHART_AXIS_PRIMARY_Y);
        lv_chart_set_all_values(chart,series[a],LV_CHART_POINT_NONE);
    }
    ui_text_label(drawer,"最近事件",&sim_font_20,TEXT);
    timeline=ui_text_label(drawer,"暂无告警",&sim_font_14,MUTED);
    lv_obj_set_width(timeline,288);
}
