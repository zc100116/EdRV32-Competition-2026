/* File: pix.h
 * Spec: pix-spec 2.2–2.6, 4.2
 * Description: B2 media engine software interface.
 * Clock domain: clk_sys CPU; engine registers in clk_mem.
 */
#ifndef EDRV32_PIX_H
#define EDRV32_PIX_H
#include "engine.h"
enum pix_operation {
    PIX_BYPASS, PIX_MEAN, PIX_GAUSSIAN, PIX_SHARPEN, PIX_SOBEL, PIX_ERODE, PIX_DILATE
};
struct pix_config {
    uint32_t flags; /* CFG masks except S1_OP/S2_OP/GAMMA_BANK. */
    enum pix_operation stage1;
    enum pix_operation stage2;
    unsigned int gamma_bank;
    uint16_t contrast; /* Q8, 0x100 = unity. */
    int16_t brightness; /* signed 9-bit. */
    uint8_t threshold;
};
/* PIX 4.2: pack the shadow CFG fields using generated masks. */
uint32_t pix_config_word(const struct pix_config *config);
/* PIX 2.6, 4.2: write point operations and both 3x3 stages; effective at next SOF. */
void pix_configure(const struct pix_config *config);
/* PIX 2.3: write all 256 entries of the caller-selected inactive Gamma bank. */
void pix_gamma_load(unsigned int bank, const uint8_t values[256]);
#endif
