/* File: peripherals.c
 * Spec: edrv32-soc-spec 7.5; sys-subsys-spec 2.4, 2.7, 2.8.
 * Description: GPIO LED walk and 10 s button edge test, CLINT interrupt, two-port I2C probe.
 *              Board pin choices are development values pending user confirmation.
 * Clock domain: clk_sys.
 */
#include "monitor.h"
#include "clint.h"
#include "gpio.h"
#include "i2c.h"
#include "uart.h"

/* SoC 3.5 GPIO0 bit map: KEY1 bit0, LED0-LED4 bits 4-8. */
#define LED_MASK 0x01f0u
#define TIMER_DELAY_CYCLES 4096u
#define BUTTON_WAIT_SECONDS 10u

static volatile uint32_t timer_seen;
static volatile uint64_t timer_arrival;
static volatile uint32_t timer_cause;

static void __attribute__((interrupt("machine"), aligned(4))) timer_handler(void)
{
    __asm__ volatile ("csrr %0, mcause" : "=r"(timer_cause));
    timer_arrival = clint_time();
    if (timer_cause != 0x80000007u) {
        info_hex("Trap cause", timer_cause);
        info_text("Timer result", "FAIL: unexpected trap");
        uart_drain();
        for (;;) {
            __asm__ volatile ("wfi");
        }
    }
    clint_set_compare(UINT64_MAX);
    timer_seen = 1u;
}

static void gpio_test(uint32_t clock_hz)
{
    info_hex("GPIO LED mask", LED_MASK);
    info_number("GPIO button bit", 0u);
    gpio_write(0u);
    gpio_set_output_enable(LED_MASK);
    for (unsigned int pin = 4u; pin <= 8u; ++pin) {
        gpio_write((uint16_t)(1u << pin));
        info_hex("GPIO LED output", 1u << pin);
        uint64_t start = clint_time();
        while (clint_time() - start < clock_hz / 10u) {
        }
    }
    /* Button: LEDs follow the active-low key; report each edge until press and release. */
    info_number("GPIO button wait seconds", BUTTON_WAIT_SECONDS);
    info_text("GPIO button action", "press and release KEY1 now; LEDs light while pressed");
    uint32_t ticks_per_ms = clock_hz / 1000u;
    uint64_t start = clint_time();
    uint64_t limit = (uint64_t)clock_hz * BUTTON_WAIT_SECONDS;
    uint32_t pressed = 0u;
    uint32_t presses = 0u;
    uint32_t releases = 0u;
    while (clint_time() - start < limit && releases == 0u) {
        uint32_t level = (gpio_read() & 1u) == 0u;
        gpio_write(level ? LED_MASK : 0u);
        if (level != pressed) {
            pressed = level;
            uint32_t elapsed_ms = (uint32_t)((clint_time() - start) / ticks_per_ms);
            if (level) {
                ++presses;
                info_number("GPIO button pressed at ms", elapsed_ms);
            } else if (presses != 0u) {
                ++releases;
                info_number("GPIO button released at ms", elapsed_ms);
            }
        }
    }
    gpio_write(0u);
    gpio_set_output_enable(0u);
    info_text("GPIO LED result", "OBSERVE: LED0-LED4 lit one at a time, then followed KEY1");
    info_text("GPIO button result", releases != 0u ? "PASS" :
        (presses != 0u ? "FAIL: still pressed at timeout" : "NOT PRESSED within wait"));
}

static void timer_test(void)
{
    uintptr_t handler = (uintptr_t)timer_handler;
    uintptr_t saved_vector;
    uint32_t saved_status;
    uint32_t saved_enable;
    __asm__ volatile ("csrrc %0, mstatus, %1" : "=r"(saved_status) : "r"(8u) : "memory");
    __asm__ volatile ("csrrw %0, mtvec, %1" : "=r"(saved_vector) : "r"(handler) : "memory");
    __asm__ volatile ("csrrw %0, mie, %1" : "=r"(saved_enable) : "r"(1u << 7) : "memory");
    timer_seen = 0u;
    uint64_t start = clint_time();
    uint64_t deadline = start + TIMER_DELAY_CYCLES;
    clint_set_compare(deadline);
    __asm__ volatile ("csrsi mstatus, 8" ::: "memory");
    while (timer_seen == 0u) {
    }
    __asm__ volatile ("csrci mstatus, 8" ::: "memory");
    __asm__ volatile ("csrw mie, %0" :: "r"(saved_enable) : "memory");
    __asm__ volatile ("csrw mtvec, %0" :: "r"(saved_vector) : "memory");
    __asm__ volatile ("csrw mstatus, %0" :: "r"(saved_status) : "memory");
    info_number("Timer requested cycles", TIMER_DELAY_CYCLES);
    info_number("Timer elapsed cycles", timer_arrival - start);
    info_number("Timer lateness cycles", timer_arrival - deadline);
    info_hex("Timer mcause", timer_cause);
    info_number("Timer interrupts", timer_seen);
    info_text("Timer result", timer_arrival >= deadline ? "PASS" : "FAIL");
}

static void i2c_test(uint32_t clock_hz)
{
    info_number("I2C SCL Hz", 100000u);
    /* Legal 7-bit unicast addresses: omit the reserved 0x00..07 and 0x78..7f. */
    info_hex("I2C first address", 0x08u);
    info_hex("I2C last address", 0x77u);
    for (unsigned int port = 0u; port < 2u; ++port) {
        unsigned int found = 0u;
        i2c_init(port, clock_hz, 100000u);
        info_number("I2C port", port);
        for (unsigned int address = 0x08u; address <= 0x77u; ++address) {
            /* One address byte plus STOP even on NACK: no device register is written. */
            if (i2c_command(I2C_CMD_START | I2C_CMD_STOP | (address << 1)) == 0) {
                info_hex("I2C ACK address", address);
                ++found;
            }
        }
        info_number("I2C devices", found);
    }
    info_text("I2C result", "SCAN COMPLETE (zero devices is a valid observation)");
}

void monitor_peripherals(uint32_t clock_hz)
{
    gpio_test(clock_hz);
    timer_test();
    i2c_test(clock_hz);
}
