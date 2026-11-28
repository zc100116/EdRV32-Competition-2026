/* File: link.ld; SoC spec 6.1; B1 ROM reset, DDR code and SRAM data; clock: host. */
OUTPUT_ARCH(riscv)
ENTRY(edrv32_reset)
MEMORY
{
    ROM (rx) : ORIGIN = 0x00000000, LENGTH = 16K
    DDR (rwx) : ORIGIN = 0x80000000, LENGTH = 0x40000000
    SRAM (rwx) : ORIGIN = 0x10000000, LENGTH = 64K
}
SECTIONS
{
    .boot : { *(.boot) } > ROM
    .text : { *(.text.init) *(.text .text.*) } > DDR
    .tohost : ALIGN(64) { *(.tohost) } > SRAM
    .data : ALIGN(16) { *(.data .data.*) *(.rodata .rodata.*) } > SRAM
    .bss : ALIGN(16) { *(.bss .bss.*) *(COMMON) } > SRAM
    _end = .;
}
