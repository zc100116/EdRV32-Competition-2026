/* gesture.c — T-DEMO-PAGES; model class names and three-frame debounce, CPU domain. */
#include "ui_data.h"
const char *const ui_gesture_ids[14] = {
    "palm", "fist", "peace", "point", "grabbing", "grip", "thumb_index", "ok",
    "like", "dislike", "three", "four", "call", "no_gesture"
};
const char *const ui_gesture_names[14] = {
    "张开", "握拳", "剪刀手", "指点", "爪形", "抓紧", "八", "OK",
    "点赞", "倒赞", "三", "四", "六", "普通"
};
const char *const ui_gesture_numbers[14] = {
    "5", "0", "2", "1", "—", "7（近似）", "8", "—", "—", "—", "3", "4", "6", "—"
};
const char *const ui_gesture_rps[14] = {
    "布", "石头", "剪刀", "—", "—", "—", "—", "—", "—", "—", "—", "—", "—", "—"
};
const char *const ui_doodle_names[20] = {
    "猫", "狗", "鱼", "鸟", "兔子", "蝴蝶", "太阳", "月亮", "星星", "云",
    "闪电", "彩虹", "树", "花", "房子", "汽车", "飞机", "帆船", "苹果", "笑脸"
};
bool ui_gesture_debounce(ui_hand_state_t *s, int cls)
{
    if (cls < 0) { s->candidate = -1; s->frames = 0; return false; }
    if (cls != s->candidate) { s->candidate = cls; s->frames = 1; }
    else if (s->frames < 3) ++s->frames;
    if (s->frames == 3 && cls != s->cls) { s->cls = cls; return true; }
    return false;
}
