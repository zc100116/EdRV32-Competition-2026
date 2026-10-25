# Boot ROM

Source `. ~/.local/opt/edrv32/env.sh`, then run `make -C sw PROGRAM=bootloader`
(or `make -C sw sys` for the bootloader and all SC programs). Outputs are in
`build/sw/bootloader/`: `bootloader.elf`, `.dis`, `.map`, `.bin`, `rom.hex`,
`sram.hex`, `ddr.hex`. The existing ROM linker places code and constant data in
16 KiB ROM and sets the stack at the end of SRAM; the linker reports ROM overflow.
The bootloader has no mutable static data and its private startup does not copy
or clear SRAM, preserving an application preloaded at SRAM base. Its temporary
stack uses the final 4 KiB of SRAM; download payloads must leave that area free.
The application starts at SRAM base and initializes its own stack/data/BSS.

On reset the bootloader enables UART TX/RX, programs the 115200 baud divisor
from SYSCTRL `CLK_SYS_HZ` (`round(clock_hz * 16 / 115200)`, fixed 8N1),
initializes GPIO as inputs, prints the ASCII logo, and waits for SYSCTRL
`STATUS.MEM_READY`. It then prints the selected boot mode and system fields.
`boot.h` defines the board convention: `BOOT_BUTTON_BIT=0`,
`BOOT_BUTTON_ACTIVE=0` (pressed is low). SC normally drives GPIO bit0 high;
a low value requests download. Board wiring changes belong in these constants.
A `SCRATCH0` value of `BOOT_DOWNLOAD_MAGIC=0x55415254` also requests download.
An application can set that magic and request `SYSCTRL_RESET_SOC`; the scratch
register survives the soft reset. The bootloader clears SCRATCH0 when consuming
a download request, so the request is used once.

Before the SRAM jump it writes `SCRATCH1=0` for a preloaded SRAM application or
`SCRATCH1=1` for a UART-downloaded application. This coordinator-confirmed
convention uses sys-subsys-spec 2.9's scratch handoff mechanism; monitor reads it
to preserve the actual boot mode after SCRATCH0 has been consumed.

Startup fields use the same fixed `Key: Value` format as monitor:
`CHIP_ID`, `CLK_SYS_HZ`, `ROM bytes`, `SRAM bytes`, `I-cache bytes`,
`D-cache bytes`, `MEM_READY`, `Boot mode`, `Build commit`, `Compiler version`.
Memory sizes come from generated `soc_map.h`; the 8 KiB I/D cache capacities
come from cache-spec 2.1 constants in `info.h`, not fictitious registers.
Makefile passes the short git commit and GCC version through build macros.
The measured image has text/data/bss = **3600/0/0 bytes**, including the logo,
and fits in the 16384-byte Boot ROM; monitor README records verification commands.

## UART download protocol

1. Host requests download through the button or scratch magic and resets the SoC.
2. Host waits for ASCII `UART download ready\r\n` following the logo.
3. Host sends a **four-byte unsigned little-endian byte length**, followed by
   exactly that many bytes of a raw SRAM application image. Valid payloads have
   length 1 through `EDRV32_SRAM_SIZE - 4096` and entry at `EDRV32_SRAM_BASE`.
   Use `build/sw/sc04/sc04.bin`, not the ELF or the textual SRAM hex file.
4. There is no echo, checksum, padding, or per-byte acknowledgement. The host
   sends at 115200 8N1 and the bootloader consumes bytes as they arrive.
5. After storing the last byte the bootloader prints
   `UART download complete\r\n`, then `Boot SRAM\r\n`, drains UART TX,
   executes FENCE and FENCE.I, and jumps to SRAM base.

For the normal preload path it prints `Boot SRAM\r\n`, drains UART TX and uses
the same handoff. The sender owns the length/image contract; no extra validation
or timeout is introduced. `rom.hex` is the byte-oriented image produced by the
existing `tools/elf2mem.py`; SC/ROM storage models must use its documented format.
Running this MMIO bootloader directly requires the SC environment (需 SC 环境).
The shared request decision and actual FENCE.I/jump implementation run in the
software-only Spike check described in `../tests/sys/README.md`.
