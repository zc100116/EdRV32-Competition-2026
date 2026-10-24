# Camera/HDMI UART control menu

This PG2L200H board program runs from BootROM plus initialized SRAM and uses
UART0 at 115200 baud to exercise the implemented CAM and DISP APB controls.
It can enable/disable each capture channel, blank/unblank HDMI at a frame
boundary, inspect frame/error counters and display-buffer ownership, and clear
sticky status. It also submits runtime OV5640 SCCB writes to either sensor for
automatic/manual exposure, gain, automatic white balance, mirror, flip and the
sensor color-bar pattern. KEY1 remains a temporary RTL-only left/right source
debug key.

SDA is an open-drain bidirectional signal. Runtime register reads are supported,
including verification of the OV5640 chip ID at registers `0x300A/0x300B`.
SCCB write-phase ninth bits are Don’t-Care bits, not mandatory I2C ACKs, so a
floating-high ninth bit is not reported as an error. The hardware instead
reports a stuck-low bus or timeout, while software uses register/chip-ID
readback to verify the selected sensor. Camera frame-rate/resolution and HDMI
timing-mode changes are not advertised: those operations require coordinated
reconfiguration of the sensor timing, capture geometry, framebuffer stride,
pixel clock and HDMI timing generator.

Build with:

```sh
make sw-build CASE=demo/vision-board-menu \
  RISCV_PREFIX=$HOME/.local/riscv-none-elf-gcc/bin/riscv-none-elf-
```

Outputs are `build/bootrom.hex`, `build/sram.hex`, the ELF, map and disassembly.

For the PG2L200H PDS project, copy `build/bootrom.hex` to
`fpga/pango_200h/edrv32_soc/bootrom.dat` and `build/sram.hex` to
`fpga/pango_200h/edrv32_soc/sram.dat`. The `boot_rom` and `sram` Pango IPs
convert these files into generated `rtl/*_init_param.v` files when the IPs are
generated. Replacing only the two `.dat` files and rerunning synthesis is not
enough: regenerate both memory IPs first, then rerun synthesis, place-and-route
and bitstream generation. Otherwise the new bitstream continues to contain the
previous program even though the `.dat` files on disk are current.

Before starting PDS, the following pairs should have identical content:

```text
sw/demo/vision-board-menu/build/bootrom.hex
fpga/pango_200h/edrv32_soc/bootrom.dat

sw/demo/vision-board-menu/build/sram.hex
fpga/pango_200h/edrv32_soc/sram.dat
```

The generated IP files must also be newer than the copied images:

```text
fpga/pango_200h/edrv32_soc/ipcore/boot_rom/rtl/boot_rom_init_param.v
fpga/pango_200h/edrv32_soc/ipcore/sram/rtl/sram_init_param.v
```
