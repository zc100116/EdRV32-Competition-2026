/* File: rom.S
 * Spec: Task B3-4b; design 2026-10-29-rnd-disp 5.2.
 * Description: Embed the selected licensed iNES image in application DDR rodata.
 * Clock domain: none.
 */
.section .rodata.nes_rom,"a"
.balign 16
.global nes_rom_start
nes_rom_start:
.incbin NES_ROM_PATH
.section .note.GNU-stack,"",@progbits
