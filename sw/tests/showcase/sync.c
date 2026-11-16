/* sync.c — T-SYNC-STICKER-R3; production LVGL submission and baseline GUI tests.
 * Mock vision consumption and DISP registers; host CPU/GUI domain.
 */
#define _GNU_SOURCE
#define main baseline_gui_test
#include "gui.c"
#undef main
#include <sys/mman.h>
void ui_pose_update(void) {}
void ui_hand_update(void) {}
void ui_grab_update(void) {}
void ui_demo_update(void) {}
static ui_app_t active_app;
static unsigned consumes, submits, page_ready, refreshes;
static bool timers_enabled;
static lv_timer_t *const page_timer = (lv_timer_t *)(uintptr_t)1;
static lv_timer_t *const engine_timer = (lv_timer_t *)(uintptr_t)2;
lv_timer_t *lv_timer_get_next(lv_timer_t *timer)
{
    if (!timers_enabled) return NULL;
    return !timer ? page_timer : timer == page_timer ? engine_timer : NULL;
}
void lv_timer_ready(lv_timer_t *timer) { assert(timer == page_timer); ++page_ready; }
void lv_refr_now(lv_display_t *disp)
{
    (void)disp;
    if (active_app == UI_APP_GRAB) assert(page_ready);
    ++refreshes;
}
ui_session_t ui_data_session(void) { return (ui_session_t){.app = active_app}; }
ui_vision_t ui_data_vision(void) { ++consumes; return (ui_vision_t){0}; }
void vision_gui_submitted(void) { ++submits; }
uint32_t rnd_physical(const void *p) { return (uint32_t)(uintptr_t)p; }
int main(void)
{
    assert(mmap((void *)(uintptr_t)EDRV32_DISP_BASE,4096,PROT_READ|PROT_WRITE,
                MAP_PRIVATE|MAP_ANONYMOUS|MAP_FIXED,-1,0) != MAP_FAILED);
    baseline_gui_test();
    const ui_app_t apps[] = {UI_APP_FACE,UI_APP_GRAB};
    for (unsigned i=0;i<2;++i) {
        active_app=apps[i];
        timers_enabled=active_app==UI_APP_GRAB;
        framework_timer_count=1;
        framework_timers[0]=engine_timer;
        unsigned refresh_before=refreshes;
        unsigned before=submits;
        unsigned reads_before=consumes;
        showcase_gui_step(&gui_task);
        assert(consumes==reads_before+1 && submits==before+1);
        assert(refreshes==refresh_before+1);
        if (active_app==UI_APP_GRAB) assert(page_ready);
        /* Model the last flush block: it stages L1 until FRAME has latched. */
        flush_pending=true;
        sync_flush_waiting=true;
        pending_pixels=(const uint32_t *)(uintptr_t)0x01200000;
        showcase_gui_disp_event(EDRV32_DISP_IRQ_STAT_SWITCH_MASK);
        assert(submits==before+1 && sync_flush_waiting);
        showcase_gui_disp_event(EDRV32_DISP_IRQ_STAT_FRAME_MASK);
        assert(submits==before+2 && !sync_flush_waiting);
        assert(mmio_read32(EDRV32_DISP_BASE+EDRV32_DISP_L1_NEXT_BASE_OFFSET)==0x01200000);
        showcase_gui_disp_event(EDRV32_DISP_IRQ_STAT_FRAME_MASK);
        assert(submits==before+2); /* An outstanding flush is submitted once. */
        showcase_gui_disp_event(EDRV32_DISP_IRQ_STAT_SWITCH1_MASK);
        showcase_gui_step(&gui_task);
        assert(!flush_pending);
    }
    puts("PASS sync GUI: page timers ready, forced refresh, no redraw, paired FRAME stage once");
    return 0;
}
