/* gui_call.c — T-VIS-RTOS; synchronous GUI ownership transfer, clk_sys.
 * Callers publish stack-resident requests, release backend state, then block.
 */
#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "sched_policy.h"
#include "sched.h"
#include "runtime.h"
#include "ui/ui_data.h"
#include <stddef.h>

struct gui_request {
    uintptr_t (*call)(uintptr_t, uintptr_t);
    uintptr_t a, b, result;
    TaskHandle_t caller;
    volatile unsigned done;
};
static QueueHandle_t requests;
extern unsigned sched_shared_release(void);
extern void sched_shared_restore(unsigned depth);
static uintptr_t gui_call(uintptr_t (*call)(uintptr_t, uintptr_t), uintptr_t a, uintptr_t b)
{
    TaskHandle_t self = xTaskGetCurrentTaskHandle();
    extern TaskHandle_t sched_gui_handle(void);
    if (self == sched_gui_handle()) return call(a, b);
    struct gui_request request = {call, a, b, 0, self, 0};
    struct gui_request *pointer = &request;
    unsigned depth = sched_shared_release();
    (void)xQueueSend(requests, &pointer, portMAX_DELAY);
    sched_signal(&gui_task, 0x400);
    while (!request.done) ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
    sched_shared_restore(depth);
    return request.result;
}
void sched_gui_queue_init(void)
{
    requests = xQueueCreate(4, sizeof(struct gui_request *));
}
void sched_gui_service(void)
{
    struct gui_request *request;
    while (xQueueReceive(requests, &request, 0) == pdPASS) {
        {
            SHOWCASE_SHARED();
            request->result = request->call(request->a, request->b);
        }
        request->done = 1;
        xTaskNotifyGive(request->caller);
    }
}
#define GUI_VOID(name) \
    void __real_##name(void); \
    static uintptr_t call_##name(uintptr_t a, uintptr_t b) \
    { (void)a; (void)b; __real_##name(); return 0; } \
    void __wrap_##name(void) { (void)gui_call(call_##name, 0, 0); }
#define GUI_ARG(name, type) \
    void __real_##name(type a); \
    static uintptr_t call_##name(uintptr_t a, uintptr_t b) \
    { (void)b; __real_##name((type)a); return 0; } \
    void __wrap_##name(type a) { (void)gui_call(call_##name, (uintptr_t)a, 0); }
GUI_VOID(showcase_gui_restore)
GUI_VOID(showcase_benchmark_start)
GUI_VOID(showcase_benchmark_stop)
GUI_VOID(ui_refresh)
GUI_VOID(board_overlay_enter)
GUI_VOID(board_overlay_step)
GUI_VOID(board_overlay_exit)
GUI_VOID(layers_enter)
GUI_VOID(layers_step)
GUI_VOID(layers_exit)
GUI_VOID(board_games_step)
GUI_VOID(board_render_step)
GUI_ARG(ui_suspend, bool)
GUI_ARG(ui_benchmark_controls, bool)
GUI_ARG(ui_open, unsigned)
GUI_ARG(ui_hint, const char *)
bool __real_ui_restore_interface(void);
static uintptr_t call_restore(uintptr_t a, uintptr_t b)
{ (void)a; (void)b; return __real_ui_restore_interface(); }
bool __wrap_ui_restore_interface(void) { return gui_call(call_restore, 0, 0) != 0; }
void __real_ui_show_app(ui_app_t app, unsigned arg);
static uintptr_t call_show(uintptr_t app, uintptr_t arg)
{ __real_ui_show_app((ui_app_t)app, (unsigned)arg); return 0; }
void __wrap_ui_show_app(ui_app_t app, unsigned arg)
{ (void)gui_call(call_show, app, arg); }

static uintptr_t barrier(uintptr_t a, uintptr_t b) { (void)a; (void)b; return 0; }
void sched_gui_barrier(void) { (void)gui_call(barrier, 0, 0); }

unsigned __real_board_game_append(uint32_t bytes, uint32_t *index);
static uintptr_t append(uintptr_t bytes, uintptr_t index)
{ return __real_board_game_append((uint32_t)bytes, (uint32_t *)index); }
unsigned __wrap_board_game_append(uint32_t bytes, uint32_t *index)
{ return (unsigned)gui_call(append, bytes, (uintptr_t)index); }
void __real_board_coremark_stack(void (*run)(void), const void *top);
void __wrap_board_coremark_stack(void (*run)(void), const void *top)
{
    sched_exclusive(2);
    __real_board_coremark_stack(run, top);
    sched_exclusive(0);
}
