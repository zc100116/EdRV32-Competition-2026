/* File: main.c
 * Spec: Task B3-3b C; SoC 1.2/7.3; DISP 5.3.
 * Description: One LVGL program launches the game, demonstrations and RN-17 check.
 * Clock domain: clk_sys CPU.
 */
#include "menu.h"
#include "s3_platform.h"
#include "lvgl/s3_lvgl.h"
#include "game/game.h"

int main(void)
{
    s3_platform_init();
    s3_puts("S3: KEY1/2 select, KEY3 launch, KEY4 back; UART a/d/w/p\r\n");
    s3_lvgl_init();
    s3_menu_show();
    enum s3_application active = S3_APP_NONE;
    uint32_t previous = 0;
    for (;;) {
        uint32_t keys = s3_input();
        uint32_t pressed = keys & ~previous;
        previous = keys;
        if (active == S3_APP_NONE) {
            enum s3_application application = s3_menu_input(pressed);
            switch (application) {
            case S3_APP_GAME:
                /* No LVGL timer handling while the game owns both display layers. */
                s3_game_run();
                s3_lvgl_restore_display();
                s3_menu_show();
                previous = s3_input();
                break;
            case S3_APP_WIDGETS:
                s3_lvgl_start_widgets();
                active = application;
                break;
            case S3_APP_BENCHMARK:
                s3_lvgl_start_benchmark();
                active = application;
                break;
            case S3_APP_COMPARE:
                s3_lvgl_self_compare();
                s3_lvgl_stop_demo();
                s3_lvgl_restore_display();
                s3_menu_show();
                break;
            case S3_APP_NONE:
            case S3_APP_COUNT:
                break;
            }
        } else if (pressed & S3_KEY_PAUSE) {
            s3_lvgl_stop_demo();
            s3_menu_show();
            active = S3_APP_NONE;
        }
        s3_lvgl_step();
    }
}
