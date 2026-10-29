/* File: menu.h
 * Spec: Task B3-3b C; SoC 1.2 S3.
 * Description: LVGL application list shared by the board and host capture.
 * Clock domain: clk_sys CPU.
 */
#ifndef S3_MENU_H
#define S3_MENU_H

#include <stdint.h>

enum s3_application {
    S3_APP_NONE = -1,
    S3_APP_GAME,
    S3_APP_WIDGETS,
    S3_APP_BENCHMARK,
    S3_APP_COMPARE,
    S3_APP_COUNT
};

void s3_menu_show(void);
enum s3_application s3_menu_input(uint32_t pressed);

#endif
