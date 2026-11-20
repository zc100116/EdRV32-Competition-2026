/* mirror.c — live demo L7; real LVGL enumeration, fragmentation and EDSC actions. */
#include "mirror.h"
#include "widgets.h"
#include "protocol.h"
#include "records.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static unsigned parts, next_part, items, clicks, changes, error, phase;
static uint32_t revision;
static bool app_input;
static struct edsc protocol;
bool ui_camera_drawer_contains(lv_obj_t *object) { (void)object; return true; }
static void event(lv_event_t *e)
{
    if (lv_event_get_code(e) == LV_EVENT_CLICKED) ++clicks;
    if (lv_event_get_code(e) == LV_EVENT_VALUE_CHANGED) ++changes;
}
static void reply(const uint8_t *p, unsigned bytes)
{
    if (p[4] == 0x86) { phase = p[14]; error = p[15]; return; }
    assert(p[4] == 0x89 && bytes <= 1012 && bytes == 12u+record_u16(p+6));
    p += 12; unsigned n = bytes-12;
    revision = record_u32(p); assert(revision != 0);
    assert(p[4] == next_part++ && p[5] > 1 && p[6] == 13 && !p[7]);
    parts = p[5];
    assert(p[8] == 9 && !memcmp(p+9,"安全帽",9));
    unsigned offset = 9+p[8];
    while (offset < n) {
        const uint8_t *item = p+offset;
        assert(item[0] == items && item[8] == 1);
        if (items == 0) assert(item[1] == 0 && record_u16(item+2) == 0);
        if (items == 1) assert(item[1] == 1);
        if (items == 2) {
            assert(item[1] == 2 && (int16_t)record_u16(item+4) == -256);
            assert(record_u16(item+6) == 255);
        }
        if (items == 3) {
            assert(item[1] == 3 && item[10+item[9]] == 7);
            assert(!memcmp(item+11+item[9],"one\ntwo",7));
        }
        offset += 11+item[9]+item[10+item[9]];
        ++items;
    }
    assert(offset == n);
}
static void send_items(const uint8_t *p, unsigned n) { edsc_ui_items(&protocol,p,n); }
static unsigned command(unsigned type, const uint8_t *p, unsigned n, uint32_t seq)
{
    assert(type == 10 && n == 8 && seq == 42);
    return ui_mirror_act(record_u32(p),p[4],p[5],(int16_t)record_u16(p+6),app_input);
}
static void act(uint32_t rev, unsigned id, unsigned action, int value)
{
    uint8_t message[20] = {'E','D','S','C',10,0,8,0,42};
    record_put32(message+12,rev); message[16] = id; message[17] = action;
    message[18] = value; message[19] = (unsigned)value >> 8;
    edsc_message(&protocol,message,sizeof message);
}
static void poll(unsigned now)
{
    next_part = items = 0;
    ui_mirror_poll(send_items,now,1000);
    if (next_part) assert(next_part == parts && items == 74);
}
int main(void)
{
    lv_init();
    lv_display_create(1280,720);
    lv_group_t *group = lv_group_create(); lv_group_set_default(group);
    lv_obj_t *screen = lv_screen_active();
    lv_obj_t *button = lv_button_create(screen);
    lv_label_set_text(lv_label_create(button),"按钮");
    lv_obj_t *toggle = lv_switch_create(screen);
    lv_obj_t *slider = lv_slider_create(screen);
    lv_slider_set_range(slider,-256,255);
    lv_obj_t *segment = lv_buttonmatrix_create(screen);
    static const char *const map[] = {"one","two",""};
    lv_buttonmatrix_set_map(segment,map);
    lv_buttonmatrix_set_one_checked(segment,true);
    lv_obj_t *objects[] = {button,toggle,slider,segment};
    for (unsigned i = 0; i < 4; ++i) {
        lv_group_add_obj(group,objects[i]);
        lv_obj_add_event_cb(objects[i],event,LV_EVENT_ALL,NULL);
    }
    for (unsigned i = 0; i < 70; ++i) {
        lv_obj_t *o = lv_button_create(screen);
        lv_label_set_text(lv_label_create(o),"0123456789012345678901234567890123456789");
        lv_group_add_obj(group,o);
    }
    protocol.ops.reply = reply; protocol.ops.command = command;
    ui_mirror_page(13,"安全帽"); poll(0);
    assert(parts > 1);
    uint32_t original = revision;
    act(revision+1,0,0,0); assert(phase == 3 && error == 5 && clicks == 0);
    app_input = true; act(revision,0,0,0); assert(phase == 3 && error == 5);
    app_input = false;
    act(revision,0,0,0); assert(phase == 2 && !error && clicks == 1);
    act(revision,1,0,0); assert(phase == 2 && lv_obj_has_state(toggle,LV_STATE_CHECKED));
    act(revision,2,1,-123); assert(phase == 2 && lv_slider_get_value(slider) == -123);
    act(revision,3,1,1); assert(phase == 2 && lv_buttonmatrix_get_selected_button(segment) == 1);
    assert(changes == 3);
    poll(1); assert(revision == original); /* Values preserve revision; action forces send. */
    poll(2); assert(next_part == 0);
    poll(1001); assert(next_part == parts && revision == original);
    act(revision,2,1,256); assert(phase == 3 && error == 2);
    act(revision,0,1,0); assert(phase == 3 && error == 5);
    act(revision,200,0,0); assert(phase == 3 && error == 5);
    lv_obj_add_state(button,LV_STATE_DISABLED);
    act(revision,0,0,0); assert(phase == 3 && error == 5);
    puts("PASS mirror: multi-part encoding, four kinds, revision, ownership, events and ACK");
}
