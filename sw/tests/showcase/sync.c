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
void ui_farm_update(void) {}
static ui_app_t active_app;
static unsigned consumes, submits, page_ready, refreshes;
static bool timers_enabled;
static unsigned resumed;
static bool pending_result = true;
bool vision_result_pending(void) { return pending_result; }
uint64_t vision_result_taken(void) { pending_result = false; return 0; }
lv_timer_t *lv_timer_get_next(lv_timer_t *timer);
void lv_timer_pause(lv_timer_t *timer) { (void)timer; }
static lv_timer_t *const page_timer = (lv_timer_t *)(uintptr_t)1;
static lv_timer_t *const engine_timer = (lv_timer_t *)(uintptr_t)2;
void lv_timer_resume(lv_timer_t *timer) { assert(timer == page_timer); ++resumed; }
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
static bool model_l0;
static bool expect_atomic;
void vision_gui_submitted(void)
{
    ++submits;
    if (expect_atomic) assert(input_lock_depth);
    if (model_l0)
        mmio_write32(EDRV32_DISP_BASE + EDRV32_DISP_NEXT_BASE_OFFSET, 0x01400000);
}
void cache_clean(uintptr_t address, uint32_t size) { (void)address; (void)size; }
void cache_clean_all(void) {}
bool lv_display_flush_is_last(lv_display_t *disp) { (void)disp; return true; }
const struct showcase_draw_rnd_stats *showcase_draw_rnd_stats(void)
{
    static const struct showcase_draw_rnd_stats stats;
    return &stats;
}
uint32_t rnd_physical(const void *p) { return (uint32_t)(uintptr_t)p; }
static void submission_window_test(void)
{
    active_app = UI_APP_FACE;
    model_l0 = true;
    const lv_area_t area = {0,0,0,0};
    const uint32_t l0 = EDRV32_DISP_BASE + EDRV32_DISP_NEXT_BASE_OFFSET;
    const uint32_t l1 = EDRV32_DISP_BASE + EDRV32_DISP_L1_NEXT_BASE_OFFSET;
    for (unsigned outside = 0; outside < 2; ++outside) {
        mmio_write32(l0, 0x01000000);
        mmio_write32(l1, 0x01200000);
        host_ticks = 10000000;
        showcase_gui_disp_event(EDRV32_DISP_IRQ_STAT_FRAME_MASK);
        uint64_t edge = host_ticks;
        host_ticks += (uint64_t)platform_clock_hz() * SYNC_SUBMIT_WINDOW_US / 1000000u;
        if (!outside) --host_ticks; /* Last tick inside, then exact threshold outside. */
        unsigned before = submits;
        expect_atomic = !outside;
        flush(NULL, &area, (uint8_t *)(uintptr_t)0x01600000);
        expect_atomic = false;
        assert(flush_pending && sync_flush_waiting == (bool)outside);
        assert(submits == before + !outside);
        if (outside) {
            /* The next latch sees both old bases; its IRQ stages both new bases. */
            assert(mmio_read32(l0) == 0x01000000 && mmio_read32(l1) == 0x01200000);
            host_ticks = edge + (uint64_t)platform_clock_hz() * 16683 / 1000000u;
            showcase_gui_disp_event(EDRV32_DISP_IRQ_STAT_FRAME_MASK);
        }
        assert(!sync_flush_waiting && submits == before + 1);
        assert(mmio_read32(l0) == 0x01400000 && mmio_read32(l1) == 0x01600000);
        /* Next latch applies both, and SWITCH1 completes the asynchronous flush. */
        unsigned completed = completions;
        showcase_gui_disp_event(EDRV32_DISP_IRQ_STAT_FRAME_MASK |
                                EDRV32_DISP_IRQ_STAT_SWITCH1_MASK);
        showcase_gui_step(&gui_task);
        assert(!flush_pending && completions == completed + 1);
    }
    model_l0 = false;
    puts("PASS sync window: immediate/deferred paired L0/L1 latch and SWITCH1 completion");
}
int main(void)
{
    assert(mmap((void *)(uintptr_t)EDRV32_DISP_BASE,4096,PROT_READ|PROT_WRITE,
                MAP_PRIVATE|MAP_ANONYMOUS|MAP_FIXED,-1,0) != MAP_FAILED);
    baseline_gui_test();
    submission_window_test();
    const ui_app_t apps[] = {UI_APP_FACE,UI_APP_GRAB};
    for (unsigned i=0;i<2;++i) {
        active_app=apps[i];
        pending_result=true;
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
        unsigned ready_before = page_ready;
        showcase_gui_step(&gui_task);
        assert(consumes==reads_before+1 && refreshes==refresh_before+1);
        assert(page_ready==ready_before); /* No timer work or L1 flip between results. */
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
    active_app = UI_APP_NONE;
    unsigned before_resume = resumed;
    assert(sync_timers_paused);
    showcase_gui_step(&gui_task);
    assert(!sync_timers_paused && resumed == before_resume + 1);
    showcase_gui_step(&gui_task);
    assert(resumed == before_resume + 1);
    puts("PASS sync exit returns page timer ownership once; framework timers unchanged");
    puts("PASS sync GUI: page timers ready, forced refresh, no redraw, paired FRAME stage once");
    return 0;
}
