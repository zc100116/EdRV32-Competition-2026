/* gui.c — showcase 4.6.1; an input IRQ during L1 flush waits for SWITCH1.
 * Production GUI dispatcher with host stubs at LVGL and hardware boundaries.
 */
#include "../../apps/showcase/lvgl/showcase_lvgl.c"
#include <assert.h>
#include <stdio.h>
static unsigned reads;
static unsigned completions;
struct sched_task gui_task;
struct sched_task application_task;
unsigned ui_page;
bool ui_detection_settings;
uint8_t showcase_gui_paused(void) { return 0; }
uint32_t virtual_input_lock(void) { return 0; }
void virtual_input_unlock(uint32_t state) { (void)state; }
uint64_t platform_ticks(void) { return 0; }
uint32_t platform_clock_hz(void) { return 125000000; }
void platform_puts(const char *text) { (void)text; }
void platform_put_u32(uint32_t value) { (void)value; }
uint32_t sched_take(struct sched_task *task)
{
    uint32_t events = task->events;
    task->events = 0;
    return events;
}
void sched_signal(struct sched_task *task, uint32_t events) { task->events |= events; }
void sched_wake_at(struct sched_task *task, uint64_t time) { task->wake_at = time; }
lv_indev_t *lv_indev_get_next(lv_indev_t *indev)
{ return indev ? NULL : (lv_indev_t *)(uintptr_t)1; }
void lv_indev_read(lv_indev_t *indev) { (void)indev; ++reads; }
uint32_t lv_timer_handler(void) { return LV_NO_TIMER_READY; }
void lv_display_flush_ready(lv_display_t *disp) { (void)disp; ++completions; }
void ui_vision_frame(bool batch) { (void)batch; }
void ui_process_update(void) {}
int main(void)
{
    scan_started = true;
    flush_pending = true;
    gui_task.events = PLATFORM_INPUT;
    showcase_gui_step(&gui_task);
    assert(reads == 0 && completions == 0);
    showcase_gui_disp_event(EDRV32_DISP_IRQ_STAT_SWITCH1_MASK);
    showcase_gui_step(&gui_task);
    assert(reads == 1 && completions == 1);
    showcase_gui_step(&gui_task);
    assert(reads == 1); /* A consumed wakeup is not replayed. */
    showcase_input_sample(PLATFORM_LEFT);
    lv_indev_data_t key = {0}; read_keys(NULL,&key);
    assert(key.key==LV_KEY_PREV && key.state==LV_INDEV_STATE_PRESSED);
    showcase_input_sample(PLATFORM_ENTER); read_keys(NULL,&key);
    assert(key.key==LV_KEY_PREV && key.state==LV_INDEV_STATE_RELEASED);
    read_keys(NULL,&key); assert(key.key==LV_KEY_ENTER && key.state==LV_INDEV_STATE_PRESSED);
    showcase_input_sample(PLATFORM_BACK); read_keys(NULL,&key);
    assert(key.key==LV_KEY_ENTER && key.state==LV_INDEV_STATE_RELEASED);
    read_keys(NULL,&key); assert(key.key==LV_KEY_ESC && key.state==LV_INDEV_STATE_PRESSED);
    showcase_input_owner(INPUT_APP); read_keys(NULL,&key);
    assert(key.key==LV_KEY_ESC && key.state==LV_INDEV_STATE_RELEASED);
    showcase_input_owner(INPUT_GUI); read_keys(NULL,&key);
    assert(key.state==LV_INDEV_STATE_RELEASED);
    showcase_input_sample(0); showcase_input_sample(PLATFORM_RIGHT); read_keys(NULL,&key);
    assert(key.key==LV_KEY_NEXT && key.state==LV_INDEV_STATE_PRESSED);
    puts("PASS LVGL current-key release, NEXT/PREV/ENTER/ESC and owner handoff");
    puts("PASS GUI input survives pending L1 flush and is consumed once after SWITCH1");
    return 0;
}
