/* File: switch.c
 * Spec: Task B3-12; PIX 2.6; DISP 5.3; SoC 7.3.
 * Description: Frame-boundary mode changes and first-new-frame latency reporting.
 * Clock domain: clk_sys; command requests and IRQ completion share the IRQ lock.
 */
#include "runtime.h"

void demo_switch_begin(struct demo_command command)
{
    uint32_t lock = demo_irq_lock();
    demo.switch_start = clint_time();
    unsigned int output = command.kind == DEMO_OUTPUT ? command.value : demo.output;
    demo.switch_start_frames = output == DEMO_ETHERNET ?
        demo.vin_frames : demo.display_frames;
    demo.switch_epoch = demo.epoch + 1u;
    demo.switch_waiting = 1;
    demo.switch_done = 0;
    demo_irq_unlock(lock);
    if (command.kind == DEMO_SCENE || (command.kind == DEMO_OUTPUT &&
        (demo.output == DEMO_ETHERNET || command.value == DEMO_ETHERNET))) {
        if (command.kind == DEMO_OUTPUT) {
            demo_pipeline_stop();
        } else {
            demo_pipeline_pause();
        }
        demo_monitor_flush();
        if (command.kind == DEMO_SCENE) {
            demo.scene = command.value;
        } else {
            demo.output = command.value;
        }
        demo_pipeline_configure(VIN_CAM0);
    } else {
        lock = demo_irq_lock();
        demo.switch_value = command.value;
        demo.switch_pending = (unsigned int)command.kind + 1u;
        demo_irq_unlock(lock);
    }
}

void demo_switch_complete(unsigned int slot)
{
    if (demo.switch_waiting && demo.surface_epoch[slot] == demo.switch_epoch) {
        demo.switch_ticks = clint_time() - demo.switch_start;
        demo.switch_frames = (demo.output == DEMO_ETHERNET ?
            demo.vin_frames : demo.display_frames) - demo.switch_start_frames;
        demo.switch_waiting = 0;
        demo.switch_done = 1;
    }
}

void demo_switch_wait(void)
{
    while (!demo.switch_done) {
        demo_network_service();
        demo_pipeline_service();
    }
}

static void number(uint64_t value)
{
    char digits[20];
    unsigned int count = 0;
    do {
        digits[count++] = (char)('0' + value % 10u);
        value /= 10u;
    } while (value);
    while (count) {
        uart_putc((uint8_t)digits[--count]);
    }
}

void demo_switch_report(void)
{
    uart_puts("Switch: frames=");
    number(demo.switch_frames);
    uart_puts(" mtime_ticks=");
    number(demo.switch_ticks);
    uart_puts(demo.output == DEMO_ETHERNET ? " HDMI off (Surface ready)" : " HDMI FRAME");
    uart_puts("\r\n");
}
