/* File: showcase.ld
 * Spec: edrv32-soc-spec 6.1; CLAUDE.md 9.2
 * Description: Link a BIOS-loaded DDR application into the 64 MiB application window at
 *              DDR + 256 MiB (b2-software 3.3), clear of the engine buffers below it.
 *              Addresses are generated from the shared SoC address map.
 * Clock domain: clk_sys.
 */
INCLUDE build/sw/soc_memory.ld
OUTPUT_ARCH(riscv)
ENTRY(_start)
/* b2-software 3.3: application window, physical 0x1000_0000, 64 MiB. */
MEMORY
{
    DDR_APP (rwx) : ORIGIN = ORIGIN(DDR) + 0x10000000, LENGTH = 0x04000000
}
PHDRS
{
    text PT_LOAD FLAGS(5);
    data PT_LOAD FLAGS(6);
    bss PT_LOAD FLAGS(6);
}
SECTIONS
{
    .text : { KEEP(*(.text.start)) *(.text .text.*) } > DDR_APP :text
    .rodata : { *(.rodata .rodata.* .srodata .srodata.*) } > DDR_APP :text
    /* Preserve initial values across re-entry, as for SRAM applications. */
    __data_image = ALIGN(MAX(4, ALIGNOF(.data)));
    .data (__data_image + SIZEOF(.data)) : AT(__data_image)
    {
        __data_start = .;
        __global_pointer$ = . + 0x800;
        *(.data .data.* .sdata .sdata.*)
        . = ALIGN(MAX(4, ALIGNOF(.data)));
        __data_end = .;
    } > DDR_APP :data
    __data_load = LOADADDR(.data);
    .tohost ALIGN(64) (NOLOAD) : AT(ADDR(.tohost))
    {
        __bss_start = .;
        KEEP(*(.tohost))
    } > DDR_APP :bss
    .bss ALIGN(4) (NOLOAD) : AT(ADDR(.bss))
    {
        *(.bss .bss.* .sbss .sbss.* COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > DDR_APP :bss
    .noinit ALIGN(4096) (NOLOAD) : AT(ADDR(.noinit))
    {
        *(.noinit .noinit.*)
    } > DDR_APP :bss
    /* Design showcase 4.5: fixed slot below the final 16 MiB stack region. */
    .game_pack (ORIGIN(DDR_APP) + 0x03000000) (NOLOAD) :
    {
        __game_pack_start = .;
        . += 0x01000000;
        __game_pack_end = .;
    } > DDR_APP :NONE
    __stack_top = ADDR(.game_pack);
    /DISCARD/ : { *(.comment .eh_frame .riscv.attributes) }
}
