/* File: ddr.ld
 * Spec: edrv32-soc-spec 6.1; CLAUDE.md 9.2
 * Description: Link the DDR software image and initialize data via BSP startup.
 *              Addresses are generated from the shared SoC address map.
 * Clock domain: clk_sys.
 */
INCLUDE build/sw/soc_memory.ld
OUTPUT_ARCH(riscv)
ENTRY(_start)
PHDRS
{
    text PT_LOAD FLAGS(5);
    data PT_LOAD FLAGS(6);
    bss PT_LOAD FLAGS(6);
}
SECTIONS
{
    .text : { KEEP(*(.text.start)) *(.text .text.*) } > DDR :text
    .rodata : { *(.rodata .rodata.* .srodata .srodata.*) } > DDR :text
    /* Preserve initial values across re-entry, as for SRAM applications. */
    __data_image = ALIGN(4);
    .data (__data_image + SIZEOF(.data)) : AT(__data_image)
    {
        __data_start = .;
        __global_pointer$ = . + 0x800;
        *(.data .data.* .sdata .sdata.*)
        . = ALIGN(4);
        __data_end = .;
    } > DDR :data
    __data_load = LOADADDR(.data);
    .tohost ALIGN(64) (NOLOAD) : AT(ADDR(.tohost))
    {
        __bss_start = .;
        KEEP(*(.tohost))
    } > DDR :bss
    .bss ALIGN(4) (NOLOAD) : AT(ADDR(.bss))
    {
        *(.bss .bss.* .sbss .sbss.* COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > DDR :bss
    __stack_top = ORIGIN(DDR) + LENGTH(DDR);
    /DISCARD/ : { *(.comment .eh_frame .riscv.attributes) }
}
