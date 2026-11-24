/* File: audio_bench.ld; tech 4 standalone Spike measurement, DDR load image. */
OUTPUT_ARCH(riscv)
ENTRY(_start)
PHDRS { text PT_LOAD FLAGS(5); data PT_LOAD FLAGS(6); }
SECTIONS
{
    . = 0x80000000;
    .text : { *(.text.start) *(.text .text.*) } :text
    .rodata : { *(.rodata .rodata.*) } :text
    . = ALIGN(4096);
    .data : {
        __global_pointer$ = . + 0x800;
        *(.data .data.* .sdata .sdata.*)
    } :data
    .tohost : { *(.tohost) } :data
    .bss : { *(.bss .bss.* .sbss .sbss.* COMMON) } :data
}
