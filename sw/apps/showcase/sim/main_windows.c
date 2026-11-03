/* main_windows.c — design P1a §5: native fixed-resolution Windows simulator. */
#include "theme.h"
#include "sim_data.h"
#include <windows.h>
#include <stdlib.h>
#include <stdio.h>

static lv_obj_t *background;
static void update_background(lv_timer_t *timer)
{
    (void)timer;
    const lv_image_dsc_t *image = sim_l0_image();
    lv_obj_set_hidden(background, image == NULL);
    if (image) lv_image_set_src(background, image);
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
    lv_windows_acquire_keypad_indev(display);
    sim_data_init();
    background = lv_image_create(lv_layer_bottom());
    lv_obj_set_size(background, 1280, 720);
    lv_image_set_inner_align(background, LV_IMAGE_ALIGN_STRETCH);
    lv_obj_set_clickable(background, false);
    ui_start();
    lv_timer_create(update_background, 100, NULL);
    lv_unlock();
    for(;;) {
        if(GetForegroundWindow() == lv_windows_get_display_window_handle(display) &&
            (GetAsyncKeyState(VK_F1) & 1)) {
            lv_lock();
            sim_data_toggle_hardware();
            ui_game_open = false;
            ui_tab = 0;
            ui_open(0);
            lv_unlock();
        }
        lv_timer_handler();
        lv_delay_ms(5);
    }
}
