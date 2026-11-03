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
    hot PT_LOAD FLAGS(5);
    games PT_LOAD FLAGS(4);
}
SECTIONS
{
    .sram_text ORIGIN(SRAM) :
    {
        __sram_code_start = .;
        *sched.o(.text .text.*)
        *platform.o(.text .text.*)
        *virtual_input*.o(.text .text.*)
        *clint.o(.text .text.*)
        *plic.o(.text .text.*)
        *rnd.o(.text.rnd_irq_handle)
        *engine.o(.text.engine_irq_handle)
        *libc.a:libc_a-memcpy.o(.text .text.*)
        *libc.a:libc_a-memset.o(.text .text.*)
        __sram_code_end = .;
    } > SRAM :hot
    .text.nes ORIGIN(DDR_APP) :
    {
        __ddr_code_start = .;
        KEEP(*(.text.start))
        *nofrendo/*(.text .text.*)
        *showcase/nes/*(.text .text.*)
    } > DDR_APP :text
    .text.lvgl ALIGN(32) : { *lvgl/src/draw/*(.text .text.*)
        *lvgl/src/core/lv_refr.o(.text .text.*) } > DDR_APP :text
    .text.ui ALIGN(32) : { *showcase/ui/*(.text .text.*) } > DDR_APP :text
    .text ALIGN(32) : { *(.text .text.*) __ddr_code_end = .; } > DDR_APP :text
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
    .game_pack ALIGN(64) : AT(ADDR(.game_pack))
    {
        __game_pack_start = .;
        KEEP(*(.game_pack))
        __game_pack_end = .;
    } > DDR_APP :games
    __stack_top = ORIGIN(DDR_APP) + LENGTH(DDR_APP);
    /DISCARD/ : { *(.comment .eh_frame .riscv.attributes) }
}
