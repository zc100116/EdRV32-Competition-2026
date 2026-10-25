#include "edrv32_ddr.h"
#include "edrv32_mmio.h"
#include "edrv32_uart.h"

static int fail(const char *message, unsigned int value)
{
    edrv32_uart_puts(message);
    edrv32_uart_put_hex32(value);
    edrv32_uart_puts("\n");
    return 1;
}

int main(void)
{
    volatile unsigned char *byte_ptr;
    volatile unsigned short *half_ptr;
    unsigned int bad_index;
    unsigned int expected;
    unsigned int actual;
    int result;

    edrv32_uart_init(EDRV32_UART_DIVISOR(100000000u, 115200u));
    edrv32_uart_puts("DDR_SMOKE_START\n");

    result = edrv32_ddr_test_alias(0x00002000u, 0x13579bdfu, &actual);
    if (result != EDRV32_DDR_OK)
        return fail("DDR_ALIAS_FAIL ", actual);

    result = edrv32_ddr_test_uncached(0x00004000u, 256u,
                                      0x20260918u, &bad_index,
                                      &expected, &actual);
    if (result != EDRV32_DDR_OK) {
        edrv32_uart_puts("DDR_WORD_FAIL index=");
        edrv32_uart_put_hex32(bad_index);
        edrv32_uart_puts(" expected=");
        edrv32_uart_put_hex32(expected);
        return fail(" actual=", actual);
    }

    byte_ptr = (volatile unsigned char *)
        edrv32_ddr_uncached_address(0x00008001u);
    half_ptr = (volatile unsigned short *)
        edrv32_ddr_uncached_address(0x00008006u);
    *byte_ptr = 0xa5u;
    *half_ptr = 0x5aa5u;
    edrv32_mmio_fence();
    if (*byte_ptr != 0xa5u)
        return fail("DDR_BYTE_FAIL ", *byte_ptr);
    if (*half_ptr != 0x5aa5u)
        return fail("DDR_HALF_FAIL ", *half_ptr);

    edrv32_uart_puts("DDR_SMOKE_PASS\n");
    for (;;) {
        __asm__ __volatile__("wfi");
    }
}
