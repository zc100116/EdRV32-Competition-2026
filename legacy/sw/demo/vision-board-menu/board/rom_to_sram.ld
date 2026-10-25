/* BootROM startup/banner + image-initialized, cacheable SRAM application. */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
    ROM  (rx)  : ORIGIN = 0x00000000, LENGTH = 16K
    SRAM (rwx) : ORIGIN = 0x10000000, LENGTH = 32K
}

SECTIONS {
    .boot : ALIGN(4) {
        _boot_start = .;
        KEEP(*(.text.boot))
        *(.text.boot.*)
        *(.rodata.boot.*)
        *(.srodata.boot.*)
        . = ALIGN(4);
        _boot_end = .;
    } > ROM

    .runtime : ALIGN(4) {
        _runtime_start = .;
        __global_pointer$ = . + 0x800;
        *(.text.startup)
        *(.text .text.*)
        *(.srodata .srodata.*)
        *(.rodata .rodata.*)
        *(.data .data.*)
        *(.sdata .sdata.*)
        . = ALIGN(4);
        _runtime_end = .;
    } > SRAM

    .bss (NOLOAD) : ALIGN(4) {
        _sbss = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } > SRAM

    .stack 0x10006000 (NOLOAD) : {
        . = . + 0x2000;
        _sp = .;
        _end = .;
    } > SRAM

    /DISCARD/ : {
        *(.comment)
        *(.riscv.attributes)
        *(.eh_frame*)
    }

    ASSERT(_boot_end <= ORIGIN(ROM) + LENGTH(ROM),
           "BootROM startup/banner exceeds 16 KiB")
    ASSERT(_ebss <= 0x10006000,
           "SRAM runtime/BSS overlaps the stack")
}
