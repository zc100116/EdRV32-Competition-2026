/* File: rom.S
 * Spec: Task B3-4b; design 2026-10-29-rnd-disp 5.2.
 * Description: Reserve the external iNES image slot without storing bytes in ELF.
 * Clock domain: none.
 */
.section .nes_rom_slot,"aw",@nobits
.balign 64
.global nes_rom_slot
.global nes_rom_slot_end
.type nes_rom_slot,@object
nes_rom_slot:
/* Largest supplied image: 2097168 bytes = 16-byte iNES header + 2 MiB. */
.space 2 * 1024 * 1024 + 16
nes_rom_slot_end:
.size nes_rom_slot, nes_rom_slot_end - nes_rom_slot
.section .note.GNU-stack,"",@progbits
