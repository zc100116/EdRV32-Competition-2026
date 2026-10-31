/* File: virtual_input_host.c
 * Spec: Task T-VIN1 host acceptance.
 * Description: Verify protocol overwrite, NES merge and real LVGL input dispatch.
 * Clock domain: deterministic host milliseconds.
 */
#include "virtual_input.h"
#include "lvgl.h"
#include "s3_lvgl.h"
#include "nes_port.h"
#include <assert.h>
#include <stdio.h>

static unsigned clicks;
static void clicked(lv_event_t *event)
{
    (void)event;
    ++clicks;
}

void virtual_input_host_check(void)
{
    assert(virtual_input_serial('j') == 'j');
    uint8_t frame[] = {0xff, 0x0f, 0xff, 4, 0xcf, 2, 3, 0};
    assert(virtual_input_serial(0x1b) == -1);
    assert(virtual_input_serial('V') == -1);
    for (unsigned i = 0; i < 8; ++i) assert(virtual_input_serial(frame[i]) == -1);
    assert(virtual_input_serial('a') == 'a');
    struct virtual_input_state input = virtual_input_get();
    assert(input.keys == 0xfff && input.x == 1279 && input.y == 719 && input.mouse == 3);
    uint8_t released[8] = {0};
    virtual_input_network(released);
    input = virtual_input_get();
    assert(input.keys == 0 && input.mouse == 0 && input.x == 0 && input.y == 0);
    for (unsigned i = 0; i < 8; ++i) {
        unsigned expected = 1u << ((i + 4) % 8);
        assert(nes_merge_virtual(0, 1u << i) == expected);
        assert(nes_merge_virtual(0x81, 1u << i) == (expected | 0x81));
    }
    lv_obj_t *first = lv_button_create(lv_screen_active());
    lv_obj_set_pos(first, 100, 100);
    lv_obj_set_size(first, 200, 100);
    lv_obj_add_event_cb(first, clicked, LV_EVENT_CLICKED, NULL);
    lv_obj_t *second = lv_button_create(lv_screen_active());
    lv_obj_set_pos(second, 400, 100);
    lv_group_t *group = lv_group_get_default();
    lv_group_remove_all_objs(group);
    lv_group_add_obj(group, first);
    lv_group_add_obj(group, second);
    lv_obj_update_layout(lv_screen_active());
    uint8_t pointer[] = {0, 0, 150, 0, 150, 0, 1, 0};
    virtual_input_network(pointer);
    for (lv_indev_t *device = lv_indev_get_next(NULL); device;
         device = lv_indev_get_next(device)) lv_indev_read(device);
    pointer[6] = 0;
    virtual_input_network(pointer);
    for (lv_indev_t *device = lv_indev_get_next(NULL); device;
         device = lv_indev_get_next(device)) lv_indev_read(device);
    assert(clicks == 1);
    assert(lv_group_get_focused(group) == first);
    pointer[1] = 4; /* bit10 Next */
    virtual_input_network(pointer);
    for (lv_indev_t *device = lv_indev_get_next(NULL); device;
         device = lv_indev_get_next(device)) lv_indev_read(device);
    assert(lv_group_get_focused(group) == second);
    virtual_input_network(released);
    puts("PASS serial/legacy mix, network overwrite, NES OR, LVGL pointer click and Next focus");
}
