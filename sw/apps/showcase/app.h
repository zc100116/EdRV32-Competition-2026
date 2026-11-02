/* File: app.h
 * Design: 2026-11-02-showcase-software 4.2.
 * Description: Application table contract; callbacks execute in application task context.
 * Clock domain: clk_sys.
 */
#ifndef SHOWCASE_APP_H
#define SHOWCASE_APP_H
#include "lvgl.h"
enum app_hardware {
    APP_HW_RND = 1u << 0,
    APP_HW_NPU = 1u << 1,
    APP_HW_VIN = 1u << 2,
    APP_HW_PIX = 1u << 3,
    APP_HW_GEO = 1u << 4,
    APP_HW_ETH = 1u << 5
};
struct app {
    const char *name;
    const lv_image_dsc_t *icon;
    uint32_t needs;
    uint8_t owns_display;
    void (*enter)(void);
    void (*step)(void);
    void (*exit)(void);
};
/* enter/step may schedule the current app; UINT64_MAX means events only.
 * exit returns after requesting peripheral stop; core waits for DISP IDLE before GUI restore.
 * app_return requests exit to the launcher; callbacks must then return normally.
 */
void app_wake_at(uint64_t mtime);
void app_return(void);
uint32_t app_events(void);
uint64_t app_busy_ticks(void);
/* Cooperative execution and synchronous GUI RND callbacks guarantee that
 * pause(1) returns with no GUI RND batch in flight, before app callbacks register. */
void app_gui_pause(uint8_t paused);
#endif
