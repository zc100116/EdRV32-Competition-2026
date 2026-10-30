/* File: mmc3_variants.h
 * Spec: T-NES3; NESdev MMC3 variant descriptions.
 * Description: Shared MMC3 bank wiring with the patched upstream IRQ counter.
 * Clock domain: emulated CPU writes and PPU scanlines.
 */
#ifndef NES_MMC3_VARIANTS_H
#define NES_MMC3_VARIANTS_H
void nes_mmc3_variant_init(void);
void nes_mmc3_variant_hblank(int vblank);
extern map_memwrite nes_mmc3_variant_writes[];
extern map_memread nes_mmc3_ram_reads[];
extern map_memwrite nes_mmc3_ram_writes[];
#endif
