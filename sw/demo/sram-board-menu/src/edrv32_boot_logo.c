/* EdRV32 BootROM banner and minimal UART initialisation. */
#include "edrv32_mmio.h"
#include "edrv32_soc_map.h"
#include "edrv32_uart.h"

#ifndef EDRV32_SOC_CLOCK_HZ
#define EDRV32_SOC_CLOCK_HZ 100000000u
#endif
#ifndef EDRV32_UART_BAUD
#define EDRV32_UART_BAUD 115200u
#endif
#ifndef EDRV32_BOARD_NAME
#define EDRV32_BOARD_NAME "PG2L200H Mini"
#endif

#if EDRV32_SOC_CLOCK_HZ == 100000000u
#define EDRV32_CLOCK_LABEL "100MHz"
#else
#define EDRV32_CLOCK_LABEL "50MHz"
#endif

#define BOOT_SECTION __attribute__((section(".text.boot.message")))
#define BOOT_RODATA  __attribute__((section(".rodata.boot.message")))

#define UART_TXDATA_OFFSET 0x00u
#define UART_STATUS_OFFSET 0x08u
#define UART_CTRL_OFFSET   0x0cu
#define UART_CLKDIV_OFFSET 0x10u
#define UART_FORMAT_OFFSET 0x14u

#define UART_STATUS_TX_EMPTY (1u << 0)
#define UART_STATUS_TX_FULL  (1u << 1)
#define UART_STATUS_TX_BUSY  (1u << 4)
#define UART_CTRL_ENABLE     (1u << 0)
#define UART_CTRL_CLEAR_TX   (1u << 2)
#define UART_CTRL_CLEAR_RX   (1u << 3)
#define UART_FORMAT_8N1      3u

static const char edrv32_logo[] BOOT_RODATA =
"\n"
"  EEEEEEE   DDDD    RRRRR   V   V   3333   2222 \n"
"  E         D   D   R   R   V   V      3      2 \n"
"  EEEE      D   D   RRRRR    V V    3333   2222 \n"
"  E         D   D   R  R     V V       3   2    \n"
"  E         D   D   R   R    V V       3   2    \n"
"  EEEEEEE   DDDD    R    R    V     3333   2222 \n"
"\n"
"  EdRV32  RV32IMC  M-mode\n"
"  " EDRV32_BOARD_NAME "\n"
"  " EDRV32_CLOCK_LABEL " cached SRAM code/data, DDR enabled\n\n";

static BOOT_SECTION void boot_uart_write(unsigned int offset,
                                         unsigned int value)
{
    edrv32_mmio_write32(SOC_UART0_BASE + offset, value);
}

static BOOT_SECTION unsigned int boot_uart_read(unsigned int offset)
{
    return edrv32_mmio_read32(SOC_UART0_BASE + offset);
}

static BOOT_SECTION void boot_uart_putc(char value)
{
    while ((boot_uart_read(UART_STATUS_OFFSET) & UART_STATUS_TX_FULL) != 0u) {
    }
    boot_uart_write(UART_TXDATA_OFFSET, (unsigned int)(unsigned char)value);
}

BOOT_SECTION void edrv32_boot_banner(void)
{
    const char *text = edrv32_logo;

    boot_uart_write(UART_CTRL_OFFSET, 0u);
    boot_uart_write(UART_CLKDIV_OFFSET,
                    EDRV32_UART_DIVISOR(EDRV32_SOC_CLOCK_HZ,
                                        EDRV32_UART_BAUD));
    boot_uart_write(UART_FORMAT_OFFSET, UART_FORMAT_8N1);
    boot_uart_write(UART_CTRL_OFFSET, UART_CTRL_ENABLE |
                                      UART_CTRL_CLEAR_TX |
                                      UART_CTRL_CLEAR_RX);

    while (*text != '\0') {
        if (*text == '\n')
            boot_uart_putc('\r');
        boot_uart_putc(*text++);
    }

    // main() reinitialises UART0 and clears its TX FIFO.  Drain the final
    // banner bytes before returning from BootROM so that reinitialisation
    // cannot truncate the startup message.
    while ((boot_uart_read(UART_STATUS_OFFSET) &
            (UART_STATUS_TX_EMPTY | UART_STATUS_TX_BUSY)) !=
           UART_STATUS_TX_EMPTY) {
    }
}
