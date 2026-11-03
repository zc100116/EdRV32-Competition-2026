/* main.c — showcase 4.5.1/4.5.2; shared shell and cooperative application lifetime.
 * UI actions commit before exclusive applications start; clk_sys. */
#include "platform.h"
#include "runtime.h"
#include "apps.h"
#include "lvgl/showcase_lvgl.h"
#include "ui/theme.h"
#include "board/games.h"
#include "board/vision_hooks.h"
#include "board/board.h"
static const struct app *active;
static const struct app *requested;
static unsigned last_page;
static uint8_t returning;
static uint8_t exiting;
static uint8_t paused;
static uint8_t transition;
static uint32_t transition_frame;
static uint32_t step_events;
static uint32_t input_keys;
static struct virtual_input_state previous_virtual;
struct sched_task communication_task = {
    "通信服务", showcase_communication_step, 0, 1, UINT64_MAX, 0, 0
};
static void application_step(struct sched_task *task);
struct sched_task application_task = {
    "当前应用", application_step, 1, 1, UINT64_MAX, 0, 0
};
struct sched_task gui_task={"图形界面",showcase_gui_step,2,1,UINT64_MAX,0,0};
void app_wake_at(uint64_t t) { sched_wake_at(&application_task,t); }
uint32_t app_events(void) { return step_events; }
uint64_t app_busy_ticks(void) { return application_task.busy_ticks; }
uint8_t showcase_launcher_active(void) { return active==0; }
uint8_t showcase_gui_paused(void) { return paused; }
void app_gui_pause(uint8_t p)
{
    paused=p;
    if(p) sched_wake_at(&gui_task,UINT64_MAX);
    else showcase_gui_restore();
}
void app_return(void) { returning=1; sched_signal(&application_task,0x80000000u); }
void board_request(const struct app *app)
{
    requested=app; transition=1; transition_frame=showcase_gui_frames();
    sched_signal(&application_task,0x80000000u);
}
void showcase_input_event(void)
{
    uint32_t keys=platform_keys(); struct virtual_input_state v=platform_virtual_input();
    if(keys!=input_keys || v.keys!=previous_virtual.keys || v.x!=previous_virtual.x ||
       v.y!=previous_virtual.y || v.mouse!=previous_virtual.mouse ||
       v.wheel!=previous_virtual.wheel) {
        input_keys=keys; previous_virtual=v; showcase_lvgl_input(keys);
        sched_signal(&application_task,PLATFORM_INPUT); sched_signal(&gui_task,PLATFORM_INPUT);
    }
}
static void application_step(struct sched_task *task)
{
    step_events=sched_take(task); showcase_input_dispatch();
    if(returning) {
        if(!exiting) { active->exit(); exiting=1; }
        if(!platform_display_idle()) {
            app_wake_at(platform_ticks()+platform_clock_hz()/1000); return;
        }
        active=0; returning=0; exiting=0; app_gui_pause(0);
        if(ui_page==5) ui_game_open=false;
        ui_open(ui_page); last_page=ui_page;
    }
    if(transition && showcase_gui_frames()==transition_frame) {
        app_wake_at(platform_ticks()+platform_clock_hz()/1000); return;
    }
    if(transition) {
        if(active) active->exit();
        active=requested; requested=0; transition=0;
        if(active) {
            if(active->owns_display) { app_gui_pause(1); engine_control(ENGINE_DISP,0); }
            active->enter();
        }
    }
    if(!paused && ui_page!=last_page) {
        if(active) active->exit();
        active=ui_page==1 ? &vision_app_camera : ui_page==2 ? &vision_app_image :
               ui_page==3 ? &vision_app_process : 0;
        last_page=ui_page; if(active) active->enter();
    }
    if(!paused && ui_page==5 && ui_game_open && active!=&nes_app) {
        board_nes_select(ui_mode); ui_hint("游戏中按返回两次退出");
        board_request(&nes_app);
    }
    board_games_step(); board_step();
    if(vision_service()) app_wake_at(platform_ticks());
    if(active) active->step();
    if(!paused) sched_defer_ready(task,platform_ticks(),platform_clock_hz()/1000);
}
int main(void)
{
    platform_init(); sched_add(&communication_task); sched_add(&application_task);
    sched_add(&gui_task); showcase_lvgl_init(); board_games_init();
    ui_start(); vision_init(); board_init(); showcase_cpu_report_init(); sched_run();
    return 0;
}
