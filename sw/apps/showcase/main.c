/* File: main.c
 * Design: showcase 4.1/4.2.
 * Description: Service registration and nonblocking application/display transitions.
 * Clock domain: clk_sys.
 */
#include "platform.h"
#include "runtime.h"
#include "apps.h"
#include "lvgl/showcase_lvgl.h"
#include "virtual_input_uart.h"
static const struct app *active;
static const struct app *requested;
static uint8_t returning;
static uint8_t stopping;
static uint8_t paused;
static uint32_t step_events;
static uint32_t input_keys;
static struct virtual_input_state previous_virtual;
static void application_step(struct sched_task *task);
struct sched_task communication_task = {
    "通信服务", showcase_communication_step, 0, 1, UINT64_MAX, 0
};
struct sched_task application_task = {
    "当前应用", application_step, 1, 0, UINT64_MAX, 0
};
struct sched_task gui_task = {"图形界面", showcase_gui_step, 2, 1, UINT64_MAX, 0};
void app_wake_at(uint64_t mtime) { sched_wake_at(&application_task, mtime); }
uint32_t app_events(void) { return step_events; }
uint64_t app_busy_ticks(void) { return application_task.busy_ticks; }
uint8_t showcase_launcher_active(void) { return active == NULL; }
uint8_t showcase_gui_paused(void) { return paused; }
void app_gui_pause(uint8_t value)
{
    paused = value;
    if (value) sched_wake_at(&gui_task, UINT64_MAX);
    else showcase_gui_restore();
}
void app_return(void)
{
    returning = 1;
    sched_signal(&application_task, 0x80000000u);
}
void launcher_request(unsigned index)
{
    const struct app *app = showcase_apps[index];
    if (app->needs & ~platform_hardware()) return;
    requested = app;
    sched_signal(&application_task, 0x80000000u);
}
void showcase_input_event(void)
{
    uint32_t keys = platform_keys();
    struct virtual_input_state input = platform_virtual_input();
    if (keys != input_keys || input.keys != previous_virtual.keys ||
        input.x != previous_virtual.x || input.y != previous_virtual.y ||
        input.mouse != previous_virtual.mouse) {
        input_keys = keys;
        previous_virtual = input;
        showcase_lvgl_input(keys);
        sched_signal(&application_task, PLATFORM_INPUT);
        sched_signal(&gui_task, PLATFORM_INPUT);
    }
}
static void application_step(struct sched_task *task)
{
    step_events = sched_take(task);
    uint32_t pressed = (step_events & PLATFORM_INPUT) ? platform_pressed() : 0;
    if (active && !active->owns_display && (pressed & PLATFORM_BACK)) returning = 1;
    if ((requested || returning) && !stopping) {
        if (active) active->exit();
        paused = 1;
        sched_wake_at(&gui_task, UINT64_MAX);
        engine_control(ENGINE_DISP, 0);
        stopping = 1;
    }
    if (stopping) {
        if (!platform_display_idle()) {
            app_wake_at(platform_ticks() + platform_clock_hz() / 1000u);
            return;
        }
        stopping = 0;
        app_wake_at(UINT64_MAX);
        returning = 0;
        active = requested;
        requested = NULL;
        showcase_lvgl_stop_demo();
        if (active) {
            paused = active->owns_display;
            if (!paused) showcase_gui_restore();
            platform_puts("showcase enter "); platform_puts(active->name);
            platform_puts("\r\n");
            active->enter();
        } else {
            paused = 0;
            showcase_gui_restore();
            launcher_show();
            platform_puts("showcase launcher\r\n");
        }
        sched_signal(&gui_task, 1);
        return;
    }
    if (active) active->step();
    else if (step_events & PLATFORM_INPUT) launcher_input(pressed);
}
int main(void)
{
    platform_init();
    platform_puts("Showcase: EdRV32 cooperative demo\r\n");
    sched_add(&communication_task);
    sched_add(&application_task);
    sched_add(&gui_task);
    showcase_lvgl_init();
    launcher_show();
    platform_puts("showcase launcher\r\n");
    sched_run();
    return 0;
}
