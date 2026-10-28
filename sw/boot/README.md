# Boot ROM BIOS

Source `. ~/.local/opt/edrv32/env.sh`, then run `make -C sw PROGRAM=bootloader`
(or `make -C sw sys` for the bootloader and SC programs). Outputs are under
`build/sw/bootloader/`: ELF, disassembly, map, raw `.bin`, and byte-oriented
`rom.hex`/`sram.hex`/`ddr.hex`. Code and constants occupy the 16 KiB ROM.
The bootloader has no mutable static data; its private startup only sets GP/SP,
leaving the SRAM application intact. Its stack uses the final 4 KiB of SRAM.

On reset, bootloader enables UART TX/RX, sets 115200 8N1 from SYSCTRL
`CLK_SYS_HZ`, configures GPIO as inputs, prints the ASCII logo, waits for
`STATUS.MEM_READY` and prints system information. Fixed `Key: Value` fields are
`CHIP_ID`, `CLK_SYS_HZ`, `ROM bytes`, `SRAM bytes`, `I-cache bytes`,
`D-cache bytes`, `MEM_READY`, `Build commit`, `Compiler version`.
Memory sizes come from generated `soc_map.h`; cache sizes are cache-spec 2.1
constants. Build information comes from Makefile macros.

After this information, bootloader repeatedly samples KEY1 (GPIO bit0, active
low) for `BOOT_BUTTON_WINDOW_MS=100` ms, measured by CLINT `mtime` using
SYSCTRL `CLK_SYS_HZ`. KEY1 must stay pressed throughout this window to enter
BIOS. Alternatively, `SCRATCH0=BOOT_DOWNLOAD_MAGIC=0x55415254` requests BIOS;
SCRATCH0 is cleared after reading. Applications can set this request then write
`SYSCTRL_RESET_SOC`; scratch survives soft reset. Otherwise bootloader prints
`Boot SRAM`, drains UART, executes FENCE/FENCE.I and enters SRAM base.
There is no SCRATCH1 boot-mode handoff.

## BIOS and UART protocol

Hold KEY1, press and release reset, then wait for these exact lines:

```text
BIOS: EdRV32
BIOS menu: 1=Program SRAM
```

Each line from BIOS ends with CR LF. Every menu selection is one line ending
with CR, LF or CR LF; only the single character `1` selects Program SRAM.
Other selections print `Input error: type 1 then Enter` and return to the menu.

1. Send `1` followed by Enter. BIOS prints `UART download ready`.
2. **The length must be sent only after receiving the complete ready line.**
   Send four bytes of unsigned little-endian length, then exactly that many
   bytes of the raw SRAM image produced by objcopy (`.bin`, not ELF or hex).
   Entry is at `EDRV32_SRAM_BASE`. Length must be 1 through
   `EDRV32_SRAM_SIZE - BOOT_STACK_BYTES` (61440 bytes on B1).
3. An invalid length prints `Program SRAM result: FAIL length` without
   receiving an image, then returns to the menu.
4. After receiving a valid image, BIOS calls BSP `cache_clean_all()` and waits
   for all dirty D$ lines to be written back. It prints
   `Program SRAM bytes: <decimal length>` and
   `Program SRAM result: PASS, press reset to run`, then the menu again.
5. Release KEY1 and press reset to run the installed SRAM program. BIOS never
   jumps directly to a newly programmed image. Reset retains SRAM; power loss
   or bitstream reconfiguration restores the bitstream's SRAM initialization.

There is no checksum, echo, retry or per-byte acknowledgement. The shared
`sw/drivers/uart_input.c` parser keeps its CR LF state on the caller's stack.
At the text/binary boundary, BIOS drains the ready line and consumes an already
queued optional LF from the menu's CR LF before reading the raw binary length;
this also preserves a length whose first byte is `0x0a` after a CR-only command.

The SRAM application's BSP startup restores `.data` from an immutable initial
copy inside the image and clears `.bss` on every entry, including repeated reset.
See `../bsp/README.md` for the LMA/VMA layout. UART host instructions are in
`../../tools/board/README.md`. Simulation and measured sizes for this change
are recorded in `../../docs/debug/2026-10-28-boot-bios.md`.
