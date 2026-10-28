/* File: sys_spike.c
 * Spec: sys-subsys-plan S-W1; sys-subsys-spec 4; edrv32-soc-spec 7.5
 * Description: Check boot decisions, handoff and driver register computations in Spike RAM.
 * Clock domain: clk_sys (software-only register storage, no peripheral model).
 */
#include "boot.h"
#include "cache.h"
#include "clint.h"
#include "edrv32.h"
#include "gpio.h"
#include "plic.h"
#include "sysctrl.h"
#include "uart.h"

static _Noreturn void application_entry(void)
{
    edrv32_exit(0);
}

static int request(uint32_t gpio, uint32_t scratch)
{
    /* Spike maps these read-only hardware fields as RAM for software checks. */
    mmio_write32(EDRV32_GPIO0_BASE + GPIO_IN, gpio);
    sysctrl_write(SYSCTRL_SCRATCH0, scratch);
    return boot_download_requested(gpio_read(), sysctrl_read(SYSCTRL_SCRATCH0));
}

int main(void)
{
    if (request(1u << BOOT_BUTTON_BIT, 0u) ||
        !request(0u, 0u) ||
        !request(1u << BOOT_BUTTON_BIT, BOOT_DOWNLOAD_MAGIC) ||
        request((1u << BOOT_BUTTON_BIT) | (1u << (BOOT_BUTTON_BIT + 1u)),
                BOOT_DOWNLOAD_MAGIC ^ 1u)) {
        return 1;
    }
    uint64_t deadline = UINT64_C(0x123456789abcdef0);
    clint_set_compare(deadline);
    if (mmio_read32(EDRV32_CLINT_BASE + CLINT_MTIMECMP_LO) != (uint32_t)deadline ||
        mmio_read32(EDRV32_CLINT_BASE + CLINT_MTIMECMP_HI) != (deadline >> 32)) {
        return 2;
    }
    mmio_write32(EDRV32_CLINT_BASE + CLINT_MTIME_HI, 0x12345678u);
    mmio_write32(EDRV32_CLINT_BASE + CLINT_MTIME_LO, 0x9abcdef0u);
    if (clint_time() != deadline) {
        return 3;
    }
    clint_set_software_irq(1u);
    if (mmio_read32(EDRV32_CLINT_BASE + CLINT_MSIP) != 1u) {
        return 4;
    }
    clint_set_software_irq(0u);
    plic_set_priority(EDRV32_PLIC_SOURCE_GPIO0, 7u);
    plic_set_enable(1u << EDRV32_PLIC_SOURCE_GPIO0);
    plic_set_threshold(3u);
    if (mmio_read32(EDRV32_PLIC_BASE + 4u * EDRV32_PLIC_SOURCE_GPIO0) != 7u ||
        mmio_read32(EDRV32_PLIC_BASE + PLIC_ENABLE) != (1u << EDRV32_PLIC_SOURCE_GPIO0) ||
        mmio_read32(EDRV32_PLIC_BASE + PLIC_THRESHOLD) != 3u) {
        return 5;
    }
    mmio_write32(EDRV32_PLIC_BASE + PLIC_PENDING, 1u << EDRV32_PLIC_SOURCE_GPIO0);
    mmio_write32(EDRV32_PLIC_BASE + PLIC_CLAIM, EDRV32_PLIC_SOURCE_GPIO0);
    if (plic_pending() != (1u << EDRV32_PLIC_SOURCE_GPIO0) ||
        plic_claim() != EDRV32_PLIC_SOURCE_GPIO0) {
        return 6;
    }
    plic_complete(EDRV32_PLIC_SOURCE_GPIO0);
    if (mmio_read32(EDRV32_PLIC_BASE + PLIC_CLAIM) != EDRV32_PLIC_SOURCE_GPIO0) {
        return 7;
    }
    uart_set_baud(EDRV32_CLK_SYS_HZ, 115200u);
    if (mmio_read32(EDRV32_UART0_BASE + UART_BAUD_DIV) != 20833u) {
        return 8;
    }
    uart_init();
    gpio_write(0x5a5au);
    gpio_set_output_enable(0x00ffu);
    if (mmio_read32(EDRV32_UART0_BASE + UART_CTRL) != 3u ||
        mmio_read32(EDRV32_GPIO0_BASE + GPIO_OUT) != 0x5a5au ||
        mmio_read32(EDRV32_GPIO0_BASE + GPIO_OE) != 0x00ffu) {
        return 9;
    }
    cache_clean(EDRV32_DDR_BASE + 32u, 64u);
    if (mmio_read32(EDRV32_CACHE_CTRL_BASE + CACHE_CTRL_OP_ADDR) != EDRV32_DDR_BASE + 32u ||
        mmio_read32(EDRV32_CACHE_CTRL_BASE + CACHE_CTRL_OP_SIZE) != 64u ||
        mmio_read32(EDRV32_CACHE_CTRL_BASE + CACHE_CTRL_OP_CMD) != CACHE_CTRL_CMD_CLEAN) {
        return 10;
    }
    cache_invalidate(EDRV32_DDR_BASE, 32u);
    if (mmio_read32(EDRV32_CACHE_CTRL_BASE + CACHE_CTRL_OP_CMD) !=
        CACHE_CTRL_CMD_INVALIDATE) {
        return 11;
    }
    cache_clean_invalidate(EDRV32_DDR_BASE, 32u);
    if (mmio_read32(EDRV32_CACHE_CTRL_BASE + CACHE_CTRL_OP_CMD) !=
        CACHE_CTRL_CMD_CLEAN_INVALIDATE) {
        return 12;
    }
    cache_clean_all();
    if (mmio_read32(EDRV32_CACHE_CTRL_BASE + CACHE_CTRL_OP_CMD) != CACHE_CTRL_CMD_CLEAN_ALL) {
        return 13;
    }
    boot_enter((uintptr_t)application_entry);
}
