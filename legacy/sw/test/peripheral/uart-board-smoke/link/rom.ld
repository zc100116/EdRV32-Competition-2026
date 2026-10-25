/* ============================================================================
 * File        : rom.ld
 * Author      : Edward ZC
 * Description : Boot-ROM image with runtime stack in on-chip SRAM.
 * Notes       : .data must remain empty until CRT copy support is added.
 * ========================================================================== */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
    ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 16K
    RAM (rwx) : ORIGIN = 0x10000000, LENGTH = 8K
}

SECTIONS {
    .text : {
        *(.text.startup)
        *(.text*)
        *(.rodata*)
    } > ROM
    .data : {
        *(.data*)
    } > RAM
    ASSERT(SIZEOF(.data) == 0, "UART smoke requires empty .data")
    .bss (NOLOAD) : {
        *(.bss*)
        *(COMMON)
    } > RAM
    .stack (NOLOAD) : {
        . = ALIGN(16);
        . = . + 0x1000;
        _sp = .;
        _end = .;
    } > RAM
}
