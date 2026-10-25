# System peripheral drivers

The C11 drivers use only bases and PLIC source numbers from generated
`sw/bsp/include/soc_map.h`. `include/{uart,gpio,i2c,clint,plic,sysctrl}.h` define
register offsets and fields from sys-subsys-spec section 4. MMIO accesses are
aligned 32-bit volatile accesses, including UART byte data and GPIO fields.
Compile with the BSP include directory and `sw/drivers/include`, using
`-std=c11 -Wall -Wextra -Werror`; the system program make fragments do this.

- UART: enable reset 115200 8N1, set a rounded fractional baud divisor, blocking
  transmit/receive, string output, and drain through the end of the stop bit.
  FIFO and error/IRQ fields are exposed in `uart.h`; the caller owns servicing
  receive errors and FIFO clear operations through the documented registers.
- GPIO: whole-word OUT/OE, debounced input, edge enables, RW1C IRQ acknowledge,
  and debounce period. The boot button is configured in `sw/boot/boot.h`.
- I2C: select port 0/1 only after BUSY clears, set the quarter-period divider,
  execute byte commands and wait for DONE. Write commands return `-1` on the
  specified NACK error and `0` on ACK; no retry is performed. After a NACK the
  caller handles the failure; SCCB helpers return immediately and do not issue
  further commands. `i2c_sccb_write/read(device, reg, ...)` use a 7-bit slave
  address, register high byte then low byte, and 8-bit data. Reads use a repeated
  START, then send NACK and STOP after the received byte. `i2c_command` also
  permits explicit STOP + START sequences. No clock stretching or arbitration.
- CLINT: high/low/high stable RV32 time reads, compare update in low=max/high/low
  order, and MSIP access. Time units are clk_sys cycles; get frequency through
  SYSCTRL `CLK_SYS_HZ`.
- PLIC: source priorities, full enable mask, threshold, pending, claim/complete.
  Source 0 means no interrupt; sources 1–15 and priority/threshold 0–7 follow
  the hardware contract. Clear the peripheral condition before completion.
- SYSCTRL: register definitions and read/write helpers for boot and SC software.

`sw/bsp/include/cache.h` and `sw/bsp/cache.c` provide range clean, invalidate,
clean+invalidate and whole-cache clean through CACHE_CTRL, waiting for BUSY to
clear. This is the BSP interface required by SoC 7.4; SC-06 uses it for DDR aliases.

Driver operations require the specified hardware state and valid API arguments;
there are no added timeouts, recovery paths or input gates. See
`sw/tests/sys/README.md` for SC tests and the software-only Spike checks.
