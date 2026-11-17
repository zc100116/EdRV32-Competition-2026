/* page_home.c — R4 design §4/§8.1 D6; two scenes and 20 classified applications.
 * GUI clock; focus follows the same card order across all four tab pages.
 */
#include "widgets.h"
#define ICON(name) LV_IMAGE_DECLARE(home_##name)
ICON(detection); ICON(helmet); ICON(pose); ICON(gesture); ICON(stickers);
ICON(image); ICON(tower); ICON(sling); ICON(rps); ICON(mole); ICON(slice); ICON(catch);
ICON(process); ICON(graphics); ICON(nes); ICON(monitor); ICON(chip); ICON(debug); ICON(settings);
ICON(farm);
ICON(draw);
ICON(scene_vision); ICON(scene_tower);
typedef struct {
    const char *name;
    const char *description;
    const lv_image_dsc_t *icon;
    unsigned action;
    unsigned hardware;
} application_t;
#define CAMERA (UI_VIN | UI_NPU)
#define MOTION (CAMERA | UI_RND)
static const application_t applications[] = {
    {"目标检测计数","实时识别与数量统计",&home_detection,1,CAMERA},
    {"智慧农场","分栏计数与农场告警",&home_farm,19,CAMERA},
    {"安全帽检测","看见安全，及时提醒",&home_helmet,13,CAMERA},
    {"人体姿态","骨骼关键点与动作",&home_pose,9,CAMERA},
    {"手势识别","让双手成为控制器",&home_gesture,10,CAMERA},
    {"人脸贴纸","跟随表情的趣味装扮",&home_stickers,11,MOTION},
    {"图片识别","上传图片，探索结果",&home_image,2,CAMERA | UI_ETH},
    {"方块工坊","手势搭房子、挖方块",&home_tower,17,MOTION},
    {"抓取实验","方块和球，体验抓取模式",&home_tower,18,MOTION},
    {"空中画板","伸出食指，自由画写",&home_draw,20,MOTION},
    {"弹弓打靶","后拉瞄准，松开发射",&home_sling,101,MOTION},
    {"石头剪刀布","亮出手势，与芯片对战",&home_rps,102,MOTION},
    {"打地鼠","眼疾手快，击中目标",&home_mole,103,MOTION},
    {"切图形","挥动双手，切出高分",&home_slice,104,MOTION},
    {"接物篮","左右移动，接住水果",&home_catch,105,MOTION},
    {"图像处理","滤镜与几何变换",&home_process,3,UI_VIN | UI_PIX | UI_GEO},
    {"图形引擎","渲染对照与性能测试",&home_graphics,4,UI_RND | UI_DISP},
    {"经典游戏","重温 NES 经典",&home_nes,5,UI_RND | UI_DISP},
    {"系统监控","实时观察芯片状态",&home_monitor,6,0},
    {"芯片信息","架构参数与 CoreMark",&home_chip,7,0},
    {"调试助手","串口与网络工具",&home_debug,8,0},
    {"设置","显示与抓取判定",&home_settings,16,0}
};
static const unsigned starts[] = {0,7,15,18,22};
static lv_obj_t *tabs, *cards[24];
static unsigned selected_tab, selected_card;
static void card_focused(lv_event_t *event)
{
    selected_card = (unsigned)(uintptr_t)lv_event_get_user_data(event);
    if (selected_card >= 2) {
        unsigned app = selected_card-2;
        for (unsigned tab = 0; tab < 4; ++tab)
            if (app >= starts[tab] && app < starts[tab+1]) {
                selected_tab = tab;
                lv_tabview_set_active(tabs,tab,LV_ANIM_OFF);
                break;
            }
    }
}
static void tab_changed(lv_event_t *event)
{
    (void)event;
    selected_tab = lv_tabview_get_tab_active(tabs);
    selected_card = starts[selected_tab]+2;
}
void ui_home_select_tab(unsigned tab)
{
    selected_tab = tab;
    selected_card = starts[tab]+2;
    if (ui_page == 0) lv_tabview_set_active(tabs,tab,LV_ANIM_OFF);
}
unsigned ui_home_tab(void) { return selected_tab; }
void ui_home_focus(void) { lv_group_focus_obj(cards[selected_card]); }
bool ui_home_key(uint32_t key)
{
    if (key != LV_KEY_NEXT && key != LV_KEY_PREV) return false;
    int direction = key == LV_KEY_NEXT ? 1 : -1;
    selected_card = (selected_card+24+direction)%24;
    lv_group_focus_obj(cards[selected_card]);
    lv_obj_add_state(cards[selected_card],LV_STATE_FOCUS_KEY);
    return true;
}
void ui_page_home(lv_obj_t *parent)
{
    lv_obj_set_style_pad_all(parent,UI_SPACE_LG,0);
    lv_obj_set_style_pad_gap(parent,UI_SPACE_MD,0);
    lv_obj_set_flex_flow(parent,LV_FLEX_FLOW_COLUMN);
    lv_obj_t *scenes = ui_stack(parent,LV_FLEX_FLOW_ROW,UI_SPACE_MD);
    lv_obj_set_flex_align(scenes,LV_FLEX_ALIGN_SPACE_BETWEEN,
                          LV_FLEX_ALIGN_CENTER,LV_FLEX_ALIGN_CENTER);
    cards[0] = ui_scene_card(scenes,&home_scene_vision,"智能视觉 · 检测计数",
                             "看见目标，读懂现场",CAMERA,1);
    cards[1] = ui_scene_card(scenes,&home_scene_tower,"体感积木",
                             "手势搭房子、挖方块",MOTION,17);
    tabs = lv_tabview_create(parent);
    lv_obj_set_width(tabs,LV_PCT(100));
    lv_obj_set_flex_grow(tabs,1);
    lv_tabview_set_tab_bar_size(tabs,48);
    static const char *const names[] = {"AI 视觉","体感互动","图形多媒体","系统"};
    for (unsigned tab = 0; tab < 4; ++tab) {
        lv_obj_t *page = lv_tabview_add_tab(tabs,names[tab]);
        lv_obj_remove_style_all(page);
        lv_obj_set_size(page,LV_PCT(100),LV_PCT(100));
        lv_obj_set_style_pad_all(page,UI_SPACE_SM,0);
        lv_obj_set_style_pad_gap(page,UI_SPACE_SM,0);
        lv_obj_set_flex_flow(page,LV_FLEX_FLOW_ROW_WRAP);
        lv_obj_set_flex_align(page,LV_FLEX_ALIGN_START,LV_FLEX_ALIGN_START,LV_FLEX_ALIGN_START);
        lv_obj_t *button = lv_tabview_get_tab_button(tabs,(int)tab);
        lv_group_remove_obj(button);
        lv_obj_remove_style_all(lv_obj_get_child(button,0));
        lv_obj_center(lv_obj_get_child(button,0));
        lv_obj_set_style_text_font(button,&sim_font_20,0);
        lv_obj_set_style_bg_color(button,lv_color_hex(SELECTED),LV_STATE_CHECKED);
        lv_obj_set_style_text_color(button,lv_color_hex(ACCENT),LV_STATE_CHECKED);
        for (unsigned i = starts[tab]; i < starts[tab+1]; ++i) {
            const application_t *app = &applications[i];
            cards[i+2] = ui_app_card(page,app->icon,app->name,app->description,
                                     app->hardware,app->action);
        }
    }
    for (unsigned i = 0; i < 24; ++i)
        lv_obj_add_event_cb(cards[i],card_focused,LV_EVENT_FOCUSED,(void *)(uintptr_t)i);
    lv_tabview_set_active(tabs,selected_tab,LV_ANIM_OFF);
    lv_obj_add_event_cb(tabs,tab_changed,LV_EVENT_VALUE_CHANGED,NULL);
    ui_hint("下一个 / 上一个：遍历应用与分类    确认：进入    返回：首页");
}
