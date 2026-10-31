# SC system software

```sh
. ~/.local/opt/edrv32/env.sh
make -C sw sys
python3 sw/tests/sys/run_spike.py
make smoke
```

`make -C sw PROGRAM=sc02` builds an individual program. Every SC application is
linked at generated SRAM base using the existing `sw/bsp/ld/sram.ld`; bootloader
uses `rom.ld`. The program make fragments choose RV32IMC + Zicsr + Zifencei.
C11 builds use `-Wall -Wextra -Werror`. Each output directory
`build/sw/<program>/` contains ELF/disassembly/map/raw `.bin` and
`rom.hex`/`sram.hex`/`ddr.hex`. Existing minimal/CoreMark selections keep their
build behavior; `sys` is the new aggregate build target.

All SC programs call `sc_finish`: fence, write SYSCTRL `SIM_EXIT` (0 passes),
then write tohost using the existing BSP for environments that observe HTIF.
The SC testbench owns the overall timeout. Failure codes identify the failed
interrupt cause, SCCB write, or DDR word. No software timeout/recovery is added.

| Program | SC stimulus and expected result |
|---|---|
| `sc01` | 需 SC 环境. Preload bootloader `rom.hex` and sc01 `sram.hex`, enter ROM. Drive GPIO bit0=1, SCRATCH0=0, release reset after MEM_READY. Check ASCII logo and `Boot SRAM` UART output, then SIM_EXIT=0. The minimal application writes SCRATCH1=0x53430001. |
| `sc02` | 需 SC 环境. Preload SRAM and enter its base, or boot through ROM. CLINT must count each clk_sys cycle and route MTIP to CPU. Software sets deadline `clint_time()+4096`, enables MTIE/MIE, checks mcause=0x80000007, disarms the timer and exits 0. Wrong mcause exits 2. |
| `sc03` | 需 SC 环境. Keep GPIO bit1=0 initially (and bit0=1 when ROM boots). Wait for SCRATCH1=0x53430003, then drive bit1=1 and keep it high. Software checks MEI cause, claims GPIO source 2, checks/clears bit1 IRQ_STAT, completes source 2 and exits 0. Wrong cause/source/status exits 3/4. |
| `sc04` | 需 SC 环境. Preload only bootloader ROM, drive GPIO bit0=0 (or set SCRATCH0=0x55415254). Select 1; after `UART load ready`, send session descriptor (one SRAM segment and entry) then `sc04.bin` as documented in `sw/boot/README.md`. Check logo, ready/PASS/Run messages and automatic entry and SIM_EXIT=0; application marker is SCRATCH1=0x53430004. Repeat with scratch request and bit0=1 to exercise both selectors. |
| `sc05` | 需 SC 环境. Attach two SCCB models, each at 7-bit address 0x3c. On each port p=0,1, expect eight writes: register 0x3000+i receives 0x40+0x10*p+i (i=0..7), 400 kHz nominal. All bytes ACK. Check the unselected port remains released. NACK exits 0x50+8*p+i; success exits 0. |
| `sc06` | 需 SC 环境. Provide DDR backing shared by the cacheable and uncached aliases. At DDR offset 0x1000 software writes 16 words 0x12340000+i through cache, cleans the 64-byte range and compares via uncached alias, then writes 0xabcd0000+i uncached, invalidates, and compares cached. First/second comparison failures exit 0x60+i/0x70+i; success exits 0. |

SC-01/04 load ROM and SRAM as **separate images**. The bootloader's private
startup preserves the preloaded application, and the application's BSP startup
initializes its own data/BSS after the jump. UART download uses the flat binary,
including initialized data and linker padding; BSS is initialized by the app.
The last 4 KiB of SRAM belongs to the bootloader stack during download.

`sys_spike` reaches tohost without real peripherals. `run_spike.py` maps SRAM,
CLINT, PLIC and system APB windows as ordinary Spike RAM using generated address
constants. It checks button/scratch selection, RV32 CLINT split accesses, PLIC
register computations, UART divisor and enable values, GPIO OUT/OE, and BSP cache
command descriptors, then executes the same boot FENCE.I/jump to a test entry
that exits through tohost. This does **not** model FIFO/IRQ/RW1C/timer progression,
PLIC arbitration, SCCB waveforms or cache/DDR aliases; those require SC. The
script also runs the minimal sc01/sc04 applications through SIM_EXIT writes to
RAM and then tohost; it raises an error if Spike fails or exceeds 30 seconds.

## Worker validation (2026-10-25)

Base commit: `7822d701f17175dbcae3cfbd05dd308319729d9d`; branch:
`zc100116/task-sys-sw`. Toolchain: xPack GCC 15.2.0; Spike 1.1.1-dev.

- `make -C sw sys`: bootloader, SC-01–SC-06 and sys_spike all compile/link,
  zero warnings with C11 / `-Wall -Wextra -Werror`.
- Bootloader: 622 bytes of text/rodata, 624 bytes of file-backed ROM image
  including alignment, zero data/BSS; well within the 16384-byte ROM region.
- `python3 sw/tests/sys/run_spike.py`: sys_spike, sc01 and sc04 all reach
  tohost with status 0. Peripheral-dependent SC behavior is compile-only here.
- `make -C sw`: existing minimal ROM program still builds without warnings.
- `make lint`: pass; Verilog style reports 17 files and 0 warnings.
  `git diff --check` also passes.
- Full smoke was **not completed**: existing cache-test C++ compilation exceeded
  its 180-second limit while multiple worktrees compiled on the same host.
  The coordinator directed this worker to stop full smoke and its remaining
  compiler processes; full smoke will run serially during integration.

Raw logs are in `build/sys-sw-build.log`, `build/sys-sw-spike-build.log`,
`build/sys-sw-spike.log`, `build/sys-sw-minimal.log`, `build/sys-sw-lint.log`,
`build/sys-sw-smoke.log` and `build/regress/smoke/` in this worktree.
