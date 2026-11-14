/* main.c — P5 3.1/3.2/8.1; exclusive application manager and service scheduling.
 * The shell consumes backend sessions, never UI page globals; clk_sys. */
#include "platform.h"
#include "runtime.h"
#include "board/input.h"
#include "apps.h"
#include "lvgl/showcase_lvgl.h"
#include "ui/theme.h"
#include "board/session.h"
#include "board/games.h"
#include "board/vision_hooks.h"
#include "board/board.h"
#include "board/serial.h"
static const struct app *active, *graphics;
static uint8_t gui_suspended;
static uint32_t step_events;
static struct session media;
struct sched_task communication_task = {
    "通信服务", showcase_communication_step, 0, 1, UINT64_MAX, 0, 0
};
static void application_step(struct sched_task *task);
struct sched_task application_task = {
    "当前应用", application_step, 1, 1, UINT64_MAX, 0, 0
};
struct sched_task gui_task = {"图形界面", showcase_gui_step, 2, 1, UINT64_MAX, 0, 0};
void app_wake_at(uint64_t t) { sched_wake_at(&application_task, t); }
uint32_t app_events(void) { return step_events; }
uint64_t app_busy_ticks(void) { return application_task.busy_ticks; }
uint8_t showcase_launcher_active(void) { return !gui_suspended; }
uint8_t showcase_gui_paused(void) { return gui_suspended; }
void app_gui_pause(uint8_t p)
{
    gui_suspended = p;
    if (p) sched_wake_at(&gui_task, UINT64_MAX);
    else showcase_gui_restore();
}
static const char *const errors[] = {
    NULL, "Length mismatch", "Invalid format", "Insufficient space",
    "Hardware unavailable", "Invalid state", "Cancelled", "未加载模型"
};
ui_session_t ui_data_session(void)
{
    return (ui_session_t){media.app, media.state, errors[media.error], board_peer()};
}
unsigned board_session_error(void) { return media.error; }
ui_app_t board_session_target(void) { return media.pending ? media.requested : media.app; }
void board_session_fail(unsigned error)
{
    if (active) active->exit();
    session_fail(&media, error); platform_gui_wake();
}
void ui_data_app_open(ui_app_t app, unsigned arg)
{
    if (!media.pending && media.app == app && media.arg == arg &&
        (media.state == UI_STATE_RUNNING || media.state == UI_STATE_STARTING)) return;
    showcase_input_owner(INPUT_GUI);
    showcase_lvgl_input(0);
    session_open(&media, app, arg);
    app_wake_at(platform_ticks());
}
void ui_data_app_pause(bool p) { session_pause(&media, p); app_wake_at(platform_ticks()); }
void ui_data_app_retry(void) { session_retry(&media); app_wake_at(platform_ticks()); }
void app_return(void)
{
    /* The application has requested its own stop; retain app after natural completion. */
    session_open(&media, UI_APP_NONE, 0);
    media.pending = false;
    app_wake_at(platform_ticks());
}
void board_request(const struct app *app)
{
    graphics = app;
    session_open(&media, UI_APP_GRAPHICS, 1);
    app_wake_at(platform_ticks());
}
void showcase_input_event(void)
{
    static uint32_t keys_before;
    static struct virtual_input_state before;
    uint32_t keys = platform_keys();
    struct virtual_input_state v = platform_virtual_input();
    if ((keys || v.keys || v.mouse) && ui_restore_interface()) {
        showcase_input_owner(INPUT_GUI);
        platform_gui_wake();
    }
    showcase_lvgl_input(showcase_input_keys(INPUT_GUI));
    if (keys != keys_before || v.keys != before.keys || v.x != before.x ||
        v.y != before.y || v.mouse != before.mouse || v.wheel != before.wheel) {
        keys_before = keys; before = v;
        sched_signal(&application_task, PLATFORM_INPUT);
        sched_signal(&gui_task, PLATFORM_INPUT);
    }
}
static void start(ui_app_t app, unsigned arg)
{
    active = app == UI_APP_PIPELINE ? &vision_app_camera :
        app == UI_APP_IMAGE ? &vision_app_image : app == UI_APP_PROCESS ? &vision_app_process :
        app == UI_APP_GAME ? &nes_app : app == UI_APP_GRAPHICS && arg == 1 ? graphics : NULL;
    if (active && (active->needs & platform_hardware()) != active->needs) {
        active = NULL; board_session_fail(4); return;
    }
    if (app == UI_APP_GAME) board_nes_select(arg);
    if (active && active->owns_display) {
        app_gui_pause(1); engine_control(ENGINE_DISP,0);
    }
    if (active) active->enter();
    if (app == UI_APP_COREMARK) board_coremark_begin();
    if (app == UI_APP_GAME || app == UI_APP_COREMARK || (active && active->owns_display))
        showcase_input_owner(INPUT_APP);
}
static void stop(ui_app_t app)
{
    if (app <= UI_APP_PROCESS) board_bulk_cancel();
    if (active) active->exit();
    if (app == UI_APP_GRAPHICS) board_graphics_stop();
    if (app == UI_APP_COREMARK) board_coremark_stop();
}
static void pause_app(ui_app_t app, bool p) { (void)app; vision_pause(p); }
static bool ready(ui_app_t app, ui_state_t target)
{
    bool complete;
    if (app >= UI_APP_PIPELINE && app <= UI_APP_PROCESS) complete = vision_ready(target);
    else if (app == UI_APP_GAME) complete = board_nes_ready(target);
    else complete = !active || !active->owns_display || platform_display_idle();
    if (target == UI_STATE_IDLE && complete) {
        active = NULL;
        showcase_input_owner(INPUT_GUI); showcase_lvgl_input(0);
        if (gui_suspended) app_gui_pause(0);
        platform_gui_wake();
    }
    return complete;
}
static void application_step(struct sched_task *task)
{
    step_events = sched_take(task);
    showcase_input_dispatch();
    if (ui_data_benchmark_running() && (platform_pressed() & PLATFORM_BACK))
        ui_data_benchmark_stop();
    if (vision_service()) app_wake_at(platform_ticks());
    session_step(&media);
    board_games_step(); board_step();
    if (active && (media.state == UI_STATE_STARTING || media.state == UI_STATE_RUNNING))
        active->step();
    if (media.state == UI_STATE_STARTING || media.state == UI_STATE_STOPPING || media.pausing)
        app_wake_at(platform_ticks() + platform_clock_hz() / 1000);
    if (!gui_suspended && !vision_post_active())
        sched_defer_for(task, &gui_task, platform_ticks(), platform_clock_hz() / 1000);
}
int main(void)
{
    media.ops = (struct session_ops){start, stop, pause_app, ready};
    platform_init(); sched_add(&communication_task); sched_add(&application_task);
    sched_add(&gui_task); showcase_lvgl_init(); board_games_init();
    ui_start(); vision_init(); board_init(); showcase_cpu_report_init();
    board_serial_drain(true);
    sched_run();
    return 0;
}
