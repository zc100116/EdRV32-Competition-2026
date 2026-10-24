/* ============================================================================
 * soc.ld - link CoreMark at the simulation memory base (0x8000_0000).
 * The stack grows down from _sp (16 KiB reserved after BSS).
 * ========================================================================== */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
    RAM (rwx) : ORIGIN = 0x10000000, LENGTH = 2M
}

SECTIONS {
    . = 0x10000000;
    .text : {
        *(.text.startup)
        *(.text*)
    } > RAM
    .rodata : {
        *(.rodata*)
    } > RAM
    .data : {
        *(.data*)
    } > RAM
    .bss (NOLOAD) : {
        *(.bss*)
        *(COMMON)
    } > RAM
    . = ALIGN(16);
    . = . + 0x4000;             /* 16 KiB stack */
    _sp = .;
    _end = .;
}
