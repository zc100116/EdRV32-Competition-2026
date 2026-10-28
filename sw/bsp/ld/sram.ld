/* File: sram.ld
 * Spec: edrv32-soc-spec 6.1; CLAUDE.md 9.2
 * Description: Link the SRAM software image and initialize data via BSP startup.
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
    .text : { KEEP(*(.text.start)) *(.text .text.*) } > SRAM :text
    .rodata : { *(.rodata .rodata.* .srodata .srodata.*) } > SRAM :text
    /* SoC 7.5(3b): keep the initial values below their writable run-time copy. */
    __data_image = ALIGN(4);
    .data (__data_image + SIZEOF(.data)) : AT(__data_image)
    {
        __data_start = .;
        __global_pointer$ = . + 0x800;
        *(.data .data.* .sdata .sdata.*)
        . = ALIGN(4);
        __data_end = .;
    } > SRAM :data
    __data_load = LOADADDR(.data);
    .tohost ALIGN(64) (NOLOAD) : AT(ADDR(.tohost))
    {
        __bss_start = .;
        KEEP(*(.tohost))
    } > SRAM :bss
    .bss ALIGN(4) (NOLOAD) : AT(ADDR(.bss))
    {
        *(.bss .bss.* .sbss .sbss.* COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > SRAM :bss
    __stack_top = ORIGIN(SRAM) + LENGTH(SRAM);
    /DISCARD/ : { *(.comment .eh_frame .riscv.attributes) }
}
