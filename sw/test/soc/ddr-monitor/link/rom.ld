OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
    ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 16K
    RAM (rwx) : ORIGIN = 0x10000000, LENGTH = 32K
}

SECTIONS {
    .text : {
        *(.text.startup)
        *(.text*)
        *(.rodata*)
    } > ROM

    .data : {
        _sdata = .;
        *(.data*)
        *(.sdata*)
        _edata = .;
    } > RAM AT> ROM
    _sidata = LOADADDR(.data);

    .bss (NOLOAD) : {
        _sbss = .;
        *(.bss*)
        *(.sbss*)
        *(COMMON)
        _ebss = .;
    } > RAM

    .stack (NOLOAD) : {
        . = ALIGN(16);
        . = . + 0x2000;
        _sp = .;
        _end = .;
    } > RAM
}
