/* File: apps.h
 * Design: showcase 4.2.
 * Description: Launcher and built-in application callbacks.
 * Clock domain: clk_sys.
 */
#ifndef SHOWCASE_APPS_H
#define SHOWCASE_APPS_H
#include "app.h"
extern const struct app *const showcase_apps[];
extern const unsigned showcase_app_count;
void launcher_show(void);
void launcher_input(uint32_t pressed);
void launcher_request(unsigned index);
void layers_enter(void);
void layers_step(void);
void layers_exit(void);
void status_enter(void);
void status_step(void);
#endif
