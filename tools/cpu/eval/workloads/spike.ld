/* spike.ld — cpu-spec 4.1–4.4 evaluation; Spike RAM, CPU instruction/data domain. */
OUTPUT_ARCH(riscv)
ENTRY(_start)
PHDRS
{
    text PT_LOAD FLAGS(5);
    data PT_LOAD FLAGS(6);
}
SECTIONS
{
    . = 0x80000000;
    .text : { KEEP(*(.text.start)) *(.text .text.*) } :text
    .rodata : { *(.rodata .rodata.*) } :text
    .data : { __global_pointer$ = . + 0x800; *(.data .data.* .sdata .sdata.*) } :data
    .bss : { *(.bss .bss.* .sbss .sbss.* COMMON) } :data
    __stack_top = 0x82000000;
}
