/* File: mapper_chr.h
 * Spec: T-NES3; mixed CHR-ROM/CHR-RAM cartridge writes.
 * Description: Optional mapper-owned PPU pattern write handler.
 * Clock domain: emulated PPU access.
 */
#ifndef NES_MAPPER_CHR_H
#define NES_MAPPER_CHR_H
extern bool (*nes_chr_write_hook)(uint32 address, uint8 value);
bool nes_chr_write(uint32 address, uint8 value);
#endif
