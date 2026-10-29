/* File: runtime.h
 * Spec: design 2026-10-29-b2-software 3.3–3.5a; SoC 7.3–7.4.
 * Description: Interrupt-serialized Surface ownership and DDR transmission storage.
 * Clock domain: clk_sys.
 */
#ifndef EDRV32_DEMO_RUNTIME_H
#define EDRV32_DEMO_RUNTIME_H
#include "demo.h"
#include "clint.h"
#include "vin.h"
#include "disp.h"
#include "eth.h"
#include "geo.h"
#include "gpio.h"
#include "info.h"
#include "npu.h"
#include "ov5640.h"
#include "pix.h"
#include "plic.h"
#include "sysctrl.h"
#include "uart.h"
#include "draw.h"

enum demo_reference { REF_READY = 1, REF_PAIR = 2, REF_NPU = 4,
    REF_GEO = 8, REF_DISPLAY = 16, REF_ETH = 32, REF_POST = 64 };
enum demo_buffer_state { BUFFER_FREE, BUFFER_RUNNING, BUFFER_READY, BUFFER_PROCESSING };
struct demo_inference {
    volatile enum demo_buffer_state state;
    unsigned int image_slot;
    unsigned int input_slot;
    uint32_t frame_id;
    unsigned int checking;
};
struct demo_state {
    uint32_t clock_hz;
    volatile unsigned int scene;
    unsigned int pix;
    unsigned int geo;
    unsigned int output;
    unsigned int fps;
    volatile unsigned int sample_hz;
    volatile unsigned int transitioning;
    volatile unsigned int checking;
    unsigned int image_window;
    volatile uint32_t references[6];
    volatile uint32_t input_busy;
    volatile int pair_image;
    volatile int pair_input;
    uint32_t pair_image_id;
    uint32_t pair_input_id;
    volatile int ready_surface;
    uint32_t surface_frame[6];
    volatile int active_npu;
    struct demo_inference inference[2];
    volatile int active_geo;
    unsigned int geo_source;
    volatile int display_current;
    volatile int display_next;
    volatile int display_queue;
    volatile unsigned int display_enabled;
    volatile unsigned int tx_active;
    uint32_t tx_done;
    unsigned int tx_count;
    uint32_t tx_lengths[3];
    int tx_surface;
    int tx_check_buffer;
    volatile uint32_t received;
    volatile uint32_t monitor_sequence;
    volatile uint32_t monitor_dropped;
    volatile uint32_t monitor_produced;
    volatile uint32_t monitor_consumed;
    volatile unsigned int monitor_flush;
    volatile uint32_t video_skips;
    volatile uint32_t inference_count;
    volatile uint32_t inference_cycles;
    volatile uint32_t post_cycles;
    volatile uint32_t detection_count;
    volatile uint32_t submitted;
    volatile uint32_t sent_bytes;
    volatile uint32_t idle_cycles;
    volatile unsigned int sleeping;
    uint64_t sleep_start;
    volatile uint32_t keys;
    uint64_t deadline;
};
extern struct demo_state demo;

static inline void *demo_uncached(uint32_t physical)
{
    return (void *)(uintptr_t)(EDRV32_DDR_UNCACHED_BASE + physical);
}
static inline uintptr_t demo_cached(uint32_t physical)
{
    return (uintptr_t)(EDRV32_DDR_BASE + physical);
}
static inline uint32_t demo_irq_lock(void)
{
    uint32_t old;
    __asm__ volatile ("csrrci %0, mstatus, 8" : "=r"(old) :: "memory");
    return old;
}
static inline void demo_irq_unlock(uint32_t old)
{
    if (old & 8u) {
        __asm__ volatile ("csrsi mstatus, 8" ::: "memory");
    }
}
uint32_t demo_surface_address(unsigned int slot);
void demo_reference(unsigned int slot, unsigned int add, unsigned int remove);
_Noreturn void demo_fail(const char *reason, enum engine_id engine);
void demo_wait_idle(enum engine_id engine);
void demo_present(unsigned int slot, uint32_t frame_id, unsigned int detection_bytes,
                  int check_buffer);
void demo_pipeline_init(void);
void demo_pipeline_stop(void);
void demo_pipeline_configure(enum vin_source source);
void demo_pipeline_service(void);
void demo_pix_configure(void);
void demo_try_inference(void);
void demo_network_init(void);
uint32_t demo_network_bytes(void);
int demo_network_available(void);
void demo_network_submit(unsigned int count, int surface, int check_buffer);
void demo_network_service(void);
void demo_network_wait(void);
void demo_network_receive(void);
void demo_network_event(const struct engine_event *event, void *context);
void demo_monitor_tick(void);
void demo_monitor_send(void);
void demo_monitor_flush(void);
void demo_command_apply(struct demo_command command);
void demo_status(void);
#endif
