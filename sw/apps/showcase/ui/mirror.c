/* mirror.c — live demo L7; enumerate LVGL default group and encode 1000 B parts.
 * The shared GUI/communication scheduler owns objects and snapshots; clk_sys.
 */
#include "mirror.h"
#include "widgets.h"
#include <string.h>
struct item {
    lv_obj_t *object;
    uint8_t id, kind, area;
    int16_t value, min, max;
    char label[49], options[97];
};
static struct item previous[256];
static unsigned count, page;
static uint32_t revision;
static uint64_t sent;
static bool changed_page, force;
static char title[49];
/* Length limits are bytes; never split a UTF-8 codepoint. */
static void copy_text(char *to, const char *from, unsigned max)
{
    unsigned n = strlen(from);
    if (n > max) {
        n = max;
        while (((unsigned char)from[n]&0xc0) == 0x80) --n;
    }
    memcpy(to,from,n); to[n] = 0;
}
static const char *first_label(lv_obj_t *o)
{
    if (lv_obj_check_type(o,&lv_label_class)) return lv_label_get_text(o);
    for (unsigned i = 0; i < lv_obj_get_child_count(o); ++i) {
        const char *text = first_label(lv_obj_get_child(o,(int)i));
        if (text) return text;
    }
    return NULL;
}
static void describe(struct item *item, lv_obj_t *o, unsigned id)
{
    memset(item,0,sizeof *item);
    item->object = o; item->id = id;
    item->area = ui_camera_drawer_contains(o);
    const char *label = first_label(o);
    if (lv_obj_check_type(o,&lv_switch_class) || lv_obj_check_type(o,&lv_checkbox_class)) {
        item->kind = 1; item->value = lv_obj_has_state(o,LV_STATE_CHECKED);
        if (lv_obj_check_type(o,&lv_checkbox_class)) label = lv_checkbox_get_text(o);
    } else if (lv_obj_check_type(o,&lv_slider_class)) {
        item->kind = 2; item->value = lv_slider_get_value(o);
        item->min = lv_slider_get_min_value(o); item->max = lv_slider_get_max_value(o);
    } else if (lv_obj_check_type(o,&lv_spinbox_class)) {
        item->kind = 2; item->value = lv_spinbox_get_value(o);
        item->min = lv_spinbox_get_min_value(o); item->max = lv_spinbox_get_max_value(o);
    } else if (lv_obj_check_type(o,&lv_arc_class)) {
        item->kind = 2; item->value = lv_arc_get_value(o);
        item->min = lv_arc_get_min_value(o); item->max = lv_arc_get_max_value(o);
    } else if (lv_obj_check_type(o,&lv_buttonmatrix_class)) {
        item->kind = 3; item->value = lv_buttonmatrix_get_selected_button(o);
        const char *const *map = lv_buttonmatrix_get_map(o);
        unsigned used = 0;
        for (unsigned i = 0; map[i][0]; ++i) {
            if (!strcmp(map[i],"\n")) continue;
            unsigned n = strlen(map[i]);
            if (used+n+(used != 0) > 96) break;
            if (used) item->options[used++] = '\n';
            memcpy(item->options+used,map[i],n); used += n;
        }
    } else if (lv_obj_check_type(o,&lv_dropdown_class)) {
        item->kind = 3; item->value = lv_dropdown_get_selected(o);
        copy_text(item->options,lv_dropdown_get_options(o),96);
    }
    if (!label) {
        lv_obj_t *parent = lv_obj_get_parent(o);
        for (int i = lv_obj_get_index(o)-1; i >= 0; --i) {
            lv_obj_t *sibling = lv_obj_get_child(parent,i);
            if (lv_obj_check_type(sibling,&lv_label_class)) {
                label = lv_label_get_text(sibling); break;
            }
        }
        /* Sliders with a heading row use that preceding row's first label. */
        if (!label && lv_obj_get_index(o) > 0)
            label = first_label(lv_obj_get_child(parent,lv_obj_get_index(o)-1));
    }
    if (label) copy_text(item->label,label,48);
}
static void put16(uint8_t *p, unsigned value) { p[0] = value; p[1] = value >> 8; }
static void put32(uint8_t *p, uint32_t value)
{ put16(p,value); put16(p+2,value >> 16); }
static unsigned item_bytes(const struct item *item)
{ return 11+strlen(item->label)+strlen(item->options); }
static unsigned encode(uint8_t *p, const struct item *item)
{
    unsigned label = strlen(item->label), options = strlen(item->options);
    p[0] = item->id; p[1] = item->kind;
    put16(p+2,item->value); put16(p+4,item->min); put16(p+6,item->max);
    p[8] = item->area; p[9] = label;
    memcpy(p+10,item->label,label); p[10+label] = options;
    memcpy(p+11+label,item->options,options);
    return 11+label+options;
}
void ui_mirror_page(unsigned next, const char *name)
{ page = next; copy_text(title,name,48); changed_page = true; }
static bool snapshot(void)
{
    lv_group_t *group = lv_group_get_default();
    unsigned next_count = 0;
    bool structure = changed_page, values = false;
    for (unsigned id = 0; id < lv_group_get_obj_count(group); ++id) {
        lv_obj_t *o = lv_group_get_obj_by_index(group,id);
        if (lv_obj_has_state(o,LV_STATE_DISABLED)) continue;
        struct item item;
        describe(&item,o,id);
        if (next_count < count) {
            struct item old = previous[next_count];
            values |= old.value != item.value;
            old.value = item.value;
            structure |= memcmp(&old,&item,sizeof item) != 0;
        } else structure = true;
        previous[next_count++] = item;
    }
    structure |= next_count != count;
    count = next_count; changed_page = false;
    if (structure) ++revision;
    return structure || values;
}
void ui_mirror_poll(void (*send)(const uint8_t *, unsigned), uint64_t now, uint32_t hz)
{
    bool changed = snapshot();
    if (!changed && !force && now-sent < hz) return;
    unsigned header = 9+strlen(title), parts = 1, size = header;
    for (unsigned i = 0; i < count; ++i) {
        unsigned bytes = item_bytes(&previous[i]);
        if (size+bytes > 1000) { ++parts; size = header; }
        size += bytes;
    }
    unsigned item = 0;
    for (unsigned part = 0; part < parts; ++part) {
        uint8_t payload[1000] = {0};
        put32(payload,revision); payload[4] = part; payload[5] = parts;
        payload[6] = page; payload[8] = strlen(title);
        memcpy(payload+9,title,strlen(title)); size = header;
        while (item < count && size+item_bytes(&previous[item]) <= 1000)
            size += encode(payload+size,&previous[item++]);
        send(payload,size);
    }
    sent = now; force = false;
}
unsigned ui_mirror_act(uint32_t requested, unsigned id, unsigned action, int value,
                       bool application_input)
{
    snapshot();
    if (application_input || requested != revision) return 5;
    if (id >= lv_group_get_obj_count(lv_group_get_default())) return 5;
    lv_obj_t *o = lv_group_get_obj_by_index(lv_group_get_default(),id);
    if (lv_obj_has_state(o,LV_STATE_DISABLED)) return 5;
    struct item item;
    describe(&item,o,id);
    if (action > 1 || (action == 0 ? item.kind > 1 : item.kind < 2)) return 5;
    if (action == 1) {
        if (item.kind == 2 && (value < item.min || value > item.max)) return 2;
        if (item.kind == 3) {
            unsigned options = 1;
            for (const char *p = item.options; *p; ++p) options += *p == '\n';
            if (value < 0 || (unsigned)value >= options) return 2;
            if (lv_obj_check_type(o,&lv_buttonmatrix_class) &&
                lv_buttonmatrix_has_button_ctrl(o,value,LV_BUTTONMATRIX_CTRL_DISABLED)) return 5;
        }
    }
    if (action == 0) {
        if (item.kind == 1) {
            lv_obj_set_state(o,LV_STATE_CHECKED,!lv_obj_has_state(o,LV_STATE_CHECKED));
            lv_obj_send_event(o,LV_EVENT_VALUE_CHANGED,NULL);
        } else lv_obj_send_event(o,LV_EVENT_CLICKED,NULL);
    } else {
        if (lv_obj_check_type(o,&lv_slider_class)) lv_slider_set_value(o,value,LV_ANIM_OFF);
        else if (lv_obj_check_type(o,&lv_spinbox_class)) lv_spinbox_set_value(o,value);
        else if (lv_obj_check_type(o,&lv_arc_class)) lv_arc_set_value(o,value);
        else if (lv_obj_check_type(o,&lv_dropdown_class)) lv_dropdown_set_selected(o,value);
        else {
            lv_buttonmatrix_set_selected_button(o,value);
            lv_buttonmatrix_set_button_ctrl(o,value,LV_BUTTONMATRIX_CTRL_CHECKED);
        }
        lv_obj_send_event(o,LV_EVENT_VALUE_CHANGED,NULL);
    }
    force = true;
    return 0;
}
