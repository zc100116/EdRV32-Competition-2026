/* page_demo.c — T-DEMO-PAGES; face stickers and helmet validation.
 * RND-supported circles/rounded rectangles and horizontal strips; GUI domain.
 */
#include "widgets.h"
#include <string.h>
#include "sticker.h"
static lv_obj_t *surface, *tags[100], *metrics, *warning, *pause_label;
static ui_demo_t shown;
#define points_enabled ui_debug_overlay
static sticker_state_t stickers;
static int selected[STICKER_PARTS];
static unsigned preset, revision, frame_tick;
static lv_obj_t *sticker_name, *part_select[STICKER_PARTS], *preset_buttons[4];
static const char *part_maps[STICKER_PARTS][STICKER_SETS+2];
static int choices[STICKER_PARTS][STICKER_SETS+1];
static unsigned choice_count[STICKER_PARTS];
static lv_obj_t *helmet_count, *head_count;
#define ART(name) \
    extern const lv_image_dsc_t sticker_##name##_m24, sticker_##name##_m12, \
        sticker_##name##_z0, sticker_##name##_p12, sticker_##name##_p24
ART(cat_ears); ART(bunny_ears); ART(sunglasses); ART(crown); ART(party_hat); ART(heart_headband);
ART(heart_glasses); ART(star_eyes); ART(cartoon_eyes); ART(cat_nose); ART(clown_nose);
ART(cat_whiskers_left);
ART(dog_nose); ART(moustache); ART(red_lips); ART(tongue); ART(blush); ART(cat_whiskers);
#define FRAMES(name) {&sticker_##name##_m24, &sticker_##name##_m12, &sticker_##name##_z0, \
    &sticker_##name##_p12, &sticker_##name##_p24}
static const lv_image_dsc_t *const artwork[STICKER_SETS][5] = {
    FRAMES(cat_ears), FRAMES(bunny_ears), FRAMES(sunglasses), FRAMES(crown),
    FRAMES(party_hat), FRAMES(heart_headband), FRAMES(heart_glasses), FRAMES(star_eyes),
    FRAMES(cartoon_eyes), FRAMES(cat_nose), FRAMES(clown_nose), FRAMES(dog_nose),
    FRAMES(moustache), FRAMES(red_lips), FRAMES(tongue), FRAMES(blush), FRAMES(cat_whiskers)
};
static const lv_image_dsc_t *const left_whiskers[5] = FRAMES(cat_whiskers_left);
static lv_area_t sticker_area(const sticker_track_t *t, unsigned style, unsigned side,
                              lv_draw_image_dsc_t *image)
{
    sticker_placement_t p;
    sticker_place_part(t, style, side, &p);
    const lv_image_dsc_t *art = style == 16 && side == 0 ?
        left_whiskers[t->angle] : artwork[style][t->angle];
    int pixels = (int)sticker_styles[style].pixels;
    int size = p.width*(int)art->header.w/pixels;
    lv_area_t area = {p.x-size/2, p.y-size/2, p.x+(size+1)/2-1, p.y+(size+1)/2-1};
    if (image) {
        lv_draw_image_dsc_init(image);
        image->src = art;
        image->opa = sticker_opacity(t);
        image->scale_x = image->scale_y = p.width*256/pixels;
        image->pivot = (lv_point_t){0,0};
        image->antialias = 0;
    }
    return area;
}
static uint32_t color(unsigned cls)
{
    static const uint32_t colors[] = {0x2563eb,0xdc2626,0x059669,0x9333ea,0xea580c};
    return colors[cls % 5];
}
static void shape(lv_layer_t *layer, int x, int y, int w, int h,
                  uint32_t ink, bool outline, bool round)
{
    lv_draw_rect_dsc_t d;
    lv_draw_rect_dsc_init(&d);
    d.radius = round ? LV_RADIUS_CIRCLE : 0;
    d.bg_color = d.border_color = lv_color_hex(ink);
    if (outline) { d.bg_opa = LV_OPA_TRANSP; d.border_width = 3; }
    lv_area_t a = {x, y, x + w - 1, y + h - 1};
    lv_draw_rect(layer, &d, &a);
}
static void draw(lv_event_t *event)
{
    lv_layer_t *layer = lv_event_get_layer(event);
    if (ui_page == 11) {
        for (unsigned i = 0; i < STICKER_FACES; ++i) {
            const sticker_track_t *t = &stickers.tracks[i];
            if (!sticker_opacity(t)) continue;
            for (unsigned part = 0; part < STICKER_PARTS; ++part) {
                if (selected[part] < 0) continue;
                unsigned style = (unsigned)selected[part];
                unsigned sides = part == STICKER_CHEEKS ? 2 : 1;
                for (unsigned side = 0; side < sides; ++side) {
                    lv_draw_image_dsc_t image;
                    lv_area_t a = sticker_area(t, style, side, &image);
                    const lv_image_dsc_t *art = image.src;
                    a.x2 = a.x1 + (int)art->header.w-1;
                    a.y2 = a.y1 + (int)art->header.h-1;
                    lv_draw_image(layer, &image, &a);
                    if (points_enabled) {
                        sticker_placement_t p;
                        sticker_place_part(t, style, side, &p);
                        shape(layer,p.anchor_x-3,p.anchor_y-3,7,7,0x00ff88,false,true);
                        shape(layer,p.x-3,p.y-3,7,7,0xff00ff,false,true);
                    }
                }
            }
        }
        if (!points_enabled) return;
    }
    for (unsigned i = 0; i < shown.count; ++i) {
        const ui_detection_t *box = &shown.objects[i];
        uint32_t ink = ui_page == 13 ? (box->class_id ? 0xdc2626 : 0x059669) :
                       color(box->class_id);
        shape(layer, box->x, box->y, box->width, box->height, ink, true, false);
        if (ui_page != 11) continue;
        const ui_pose_point_t *p = shown.points[i];
        if (points_enabled) for (unsigned k = 0; k < 5; ++k)
            shape(layer, (int)p[k].x-3, (int)p[k].y-3, 7, 7, 0xea580c, false, true);
    }
}
static void invalidate(void)
{
    if (ui_page == 11) {
        for (unsigned i = 0; i < STICKER_FACES; ++i) {
            if (!sticker_opacity(&stickers.tracks[i])) continue;
            for (unsigned part = 0; part < STICKER_PARTS; ++part) {
                if (selected[part] < 0) continue;
                for (unsigned side = 0; side < (part == STICKER_CHEEKS ? 2u : 1u); ++side) {
                    lv_area_t a = sticker_area(&stickers.tracks[i], selected[part], side, NULL);
                    lv_obj_invalidate_area(surface, &a);
                }
            }
        }
        if (!points_enabled) return;
    }
    for (unsigned i = 0; i < shown.count; ++i) {
        const ui_detection_t *b = &shown.objects[i];
        /* Sticker extent includes hat above and whiskers beside the face. */
        lv_area_t a = {b->x-b->width, b->y-b->height,
                      b->x+b->width*2, b->y+b->height*2};
        lv_obj_invalidate_area(surface, &a);
    }
}
static const char *const part_names[] = {"头饰", "眼睛", "鼻子", "嘴巴", "脸颊"};
static const int presets[][STICKER_PARTS] = {
    {0,-1,9,-1,16}, {4,7,-1,-1,15}, {-1,2,-1,12,-1}, {1,-1,-1,-1,15}
};
static const char *const preset_names[] = {"猫咪", "派对", "酷", "兔子"};
static void selection_text(void)
{
    char text[256];
    lv_snprintf(text, sizeof text, "套装：%s",preset < 4 ? preset_names[preset] : "自选");
    ui_text(sticker_name, text);
}
static void selection_changed(lv_event_t *event)
{
    unsigned part=(unsigned)(uintptr_t)lv_event_get_user_data(event);
    invalidate();
    if(part==STICKER_PARTS) {
        preset=(unsigned)lv_obj_get_index(lv_event_get_target_obj(event));
        if(preset<4) memcpy(selected,presets[preset],sizeof selected);
        for(unsigned p=0;p<STICKER_PARTS;++p)
            for(unsigned i=0;i<choice_count[p];++i)
                if(choices[p][i]==selected[p]) {
                    lv_buttonmatrix_set_selected_button(part_select[p],i);
                    lv_buttonmatrix_set_button_ctrl(part_select[p],i,LV_BUTTONMATRIX_CTRL_CHECKED);
                }
    } else {
        selected[part]=choices[part][lv_buttonmatrix_get_selected_button(part_select[part])];
        preset=4;
    }
    for(unsigned i=0;i<4;++i)
        lv_obj_set_state(preset_buttons[i],LV_STATE_CHECKED,preset==i);
    for(unsigned p=0;p<STICKER_PARTS;++p)
        lv_obj_scroll_to_x(lv_obj_get_parent(part_select[p]),
            (int)lv_buttonmatrix_get_selected_button(part_select[p])*82,LV_ANIM_OFF);
    selection_text(); invalidate();
}
static void page(lv_obj_t *p, const char *title)
{
    lv_obj_t *header=ui_camera_layout(p,title);
    metrics=ui_camera_metrics(header);
    lv_obj_t *pause=ui_action_button(header,"暂停画面",0);
    pause_label=lv_obj_get_child(pause,0);
    if(ui_page==11) {
        memset(&stickers,0,sizeof stickers); memcpy(selected,presets[0],sizeof selected);
        preset=0; revision=sticker_revision; frame_tick=lv_tick_get();
    }
    memset(&shown, 0, sizeof shown);

    surface = ui_box(lv_screen_active(), 0, 0, 1280, 720, BG);
    lv_obj_set_style_bg_opa(surface, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_width(surface, 0, 0);
    lv_obj_move_to_index(surface, 0);
    lv_obj_add_event_cb(surface, draw, LV_EVENT_DRAW_MAIN, NULL);
    for (unsigned i = 0; i < 100; ++i) {
        tags[i] = ui_label(surface, "", 0, 0, &sim_font_16, PANEL);
        lv_obj_set_style_bg_opa(tags[i], LV_OPA_COVER, 0);
        lv_obj_set_hidden(tags[i], true);
    }
    lv_obj_t *picker=ui_camera_drawer(p,header,ui_page==11 ? "贴纸" : "设置");
    if(ui_page==11) {
        lv_obj_t *presets_row=ui_stack(picker,LV_FLEX_FLOW_ROW,4);
        for(unsigned i=0;i<4;++i) {
            lv_obj_t *button=lv_button_create(presets_row);
            ui_widget_style(button); lv_obj_set_size(button,70,84);
            lv_obj_set_flex_flow(button,LV_FLEX_FLOW_COLUMN);
            lv_obj_set_style_pad_all(button,4,0);
            lv_obj_t *image=lv_image_create(button);
            unsigned art=i==0 ? 0 : i==1 ? 4 : i==2 ? 2 : 1;
            lv_image_set_src(image,artwork[art][2]);
            lv_obj_set_size(image,54,44);
            lv_image_set_inner_align(image,LV_IMAGE_ALIGN_CONTAIN);
            ui_text_label(button,preset_names[i],&sim_font_14,TEXT);
            lv_obj_add_event_cb(button,selection_changed,LV_EVENT_CLICKED,
                                (void *)STICKER_PARTS);
            ui_control(button); preset_buttons[i]=button;
            lv_obj_set_state(button,LV_STATE_CHECKED,i==preset);
        }
        for(unsigned part=0;part<STICKER_PARTS;++part) {
            ui_text_label(picker,part_names[part],&sim_font_14,MUTED);
            unsigned n=1,selected_index=0; int style=sticker_next(part,-1);
            choices[part][0]=-1; part_maps[part][0]="无";
            while(style>=0) {
                choices[part][n]=style;
                part_maps[part][n]=sticker_styles[style].name;
                if(style==selected[part]) selected_index=n;
                ++n; style=sticker_next(part,style);
            }
            choice_count[part]=n; part_maps[part][n]="";
            lv_obj_t *scroll=ui_stack(picker,LV_FLEX_FLOW_ROW,0);
            lv_obj_set_height(scroll,46); lv_obj_set_scrollable(scroll,true);
            lv_obj_set_scroll_dir(scroll,LV_DIR_HOR);
            part_select[part]=ui_segment(scroll,part_maps[part],selected_index);
            lv_obj_set_width(part_select[part],n*82);
            lv_obj_add_event_cb(part_select[part],selection_changed,LV_EVENT_VALUE_CHANGED,
                                (void *)(uintptr_t)part);
        }
        sticker_name=ui_text_label(picker,"",&sim_font_14,TEXT); selection_text();
        ui_action_button(picker,"关键点",1);
    }
    lv_obj_t *side=ui_camera_card(p);
    if(ui_page==11) lv_obj_set_hidden(side,true);
    if(ui_page==13) {
        ui_live_badge(side,"已戴安全帽",TEAL); helmet_count=ui_text_label(side,"0",&sim_font_20,TEAL);
        ui_live_badge(side,"未戴安全帽",0xdc2626); head_count=ui_number(side,"0",false);
    }
    warning=ui_live_badge(p,"警示：有人未戴安全帽",0xdc2626);
    lv_obj_set_ignore_layout(warning,true);
    lv_obj_set_width(warning,224);
    lv_obj_set_style_text_font(warning,&sim_font_16,0);
    lv_obj_set_pos(warning,12,260);
    lv_obj_set_hidden(warning,true);
    ui_hint(ui_page == 11 ? "五个部位独立选贴纸 · 同步镜像画面 · 调试显示关键点" :
            "绿框 安全帽 · 红框 未戴 · 上板功能验证");
}
void ui_page_face(lv_obj_t *p) { page(p, "人脸贴纸"); }
void ui_page_helmet(lv_obj_t *p) { page(p, "安全帽检测"); }
void ui_demo_action(unsigned action)
{
    if (!action) ui_data_app_pause(ui_data_session().state != UI_STATE_PAUSED);
    else if (ui_page == 11) {
        invalidate();
        if (action == 1) points_enabled = !points_enabled;
        else if (action == 7) {
            preset = preset < 4 ? (preset+1)%4 : 0;
            memcpy(selected, presets[preset], sizeof selected);
        } else {
            unsigned part = action-2;
            selected[part] = sticker_next(part, selected[part]);
            preset = 4;
        }
        selection_text();
        for (unsigned i = 0; i < shown.count; ++i)
            lv_obj_set_hidden(tags[i], !points_enabled);
        invalidate();
    }
}
void ui_demo_update(void)
{
    const ui_demo_t *d = ui_data_demo();
    bool fresh = ui_page == 11 && revision != sticker_revision;
    if (fresh || memcmp(&shown, d, sizeof shown)) {
        invalidate(); shown = *d;
        if (ui_page == 11) {
            static sticker_detection_t detections[100];
            for (unsigned i = 0; i < d->count; ++i)
                for (unsigned k = 0; k < 5; ++k)
                    detections[i].points[k] = (sticker_point_t){
                        (int)d->points[i][k].x, (int)d->points[i][k].y};
            unsigned now = lv_tick_get();
            unsigned ms = now-frame_tick;
            sticker_step(&stickers, detections, d->count, ms);
            frame_tick = now; revision = sticker_revision;
        }
        for (unsigned i = 0; i < 100; ++i) {
            lv_obj_set_hidden(tags[i], i >= shown.count || (ui_page == 11 && !points_enabled));
            if (i >= shown.count) continue;
            const ui_detection_t *b = &shown.objects[i];
            lv_label_set_text_fmt(tags[i], "%s %u%%", b->category, b->confidence);
            lv_obj_set_style_bg_color(tags[i], lv_color_hex(ui_page == 13 ?
                (b->class_id ? 0xdc2626 : 0x059669) : color(b->class_id)), 0);
            lv_obj_set_pos(tags[i], b->x, b->y < 24 ? 0 : b->y-24);
        }
        lv_obj_update_layout(surface); invalidate();
    }
    char detail[80];
    if(ui_page==13) {
        lv_snprintf(detail,sizeof detail,"%u",d->helmet); ui_text(helmet_count,detail);
        lv_snprintf(detail,sizeof detail,"%u",d->head); ui_text(head_count,detail);
    }
    ui_camera_metrics_update(metrics);
    lv_obj_set_hidden(warning, ui_page != 13 || !d->head);
    ui_text(pause_label, ui_data_session().state == UI_STATE_PAUSED ? "继续画面" : "暂停画面");
}
