/* File: chr_memory.c
 * Spec: T-NES3; mixed CHR-ROM/CHR-RAM cartridge writes.
 * Description: Let cartridge wiring distinguish writable RAM from ROM banks.
 * Clock domain: emulated PPU access.
 */
#include <noftypes.h>
#include "mapper_chr.h"
bool (*nes_chr_write_hook)(uint32 address, uint8 value);
bool nes_chr_write(uint32 address, uint8 value)
{
    return nes_chr_write_hook && nes_chr_write_hook(address, value);
}
