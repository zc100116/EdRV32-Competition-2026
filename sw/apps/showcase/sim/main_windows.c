/* main_windows.c — design P1a §5: native fixed-resolution Windows simulator. */
#include "style_samples.h"
#include <windows.h>
#include <stdlib.h>
#include <stdio.h>

static void keyboard(lv_event_t *event)
{
    lv_indev_t *indev = lv_event_get_target(event);
    if(lv_indev_get_state(indev) == LV_INDEV_STATE_PRESSED)
        samples_key(lv_indev_get_key(indev));
}

int WINAPI WinMain(HINSTANCE instance, HINSTANCE previous, LPSTR command, int show)
{
    (void)instance;
    (void)previous;
    (void)command;
    (void)show;
    lv_init();
    lv_display_t *display = lv_windows_create_display(
        L"EdRV32 演示系统", 1280, 720, 100, false, true);
    if(!display) {
        fputs("LVGL Windows display creation failed\n", stderr);
        return EXIT_FAILURE;
    }
    lv_lock();
    lv_windows_acquire_pointer_indev(display);
    lv_indev_t *keypad = lv_windows_acquire_keypad_indev(display);
    lv_indev_add_event_cb(keypad, keyboard, LV_EVENT_KEY, NULL);
    samples_start();
    lv_unlock();
    for(;;) {
        lv_timer_handler();
        lv_delay_ms(5);
    }
}
