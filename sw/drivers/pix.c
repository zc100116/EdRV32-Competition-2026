/* File: pix.c
 * Spec: pix-spec 2.3, 2.6, 4.2
 * Description: B2 engine operations; caller owns buffer lifetime and valid configuration.
 * Clock domain: clk_sys CPU; engine registers in clk_mem.
 */
#include "pix.h"

/* PIX 4.2: CFG selections retain hardware-defined encoding. */
uint32_t pix_config_word(const struct pix_config *config)
{
    return config->flags | ((uint32_t)config->stage1 << EDRV32_PIX_CFG_S1_OP_POS) |
           ((uint32_t)config->stage2 << EDRV32_PIX_CFG_S2_OP_POS) |
           (config->gamma_bank << EDRV32_PIX_CFG_GAMMA_BANK_POS);
}

/* PIX 2.6: caller writes the shadow group between frames for a consistent update. */
void pix_configure(const struct pix_config *config)
{
    uint32_t brightness = ((uint32_t)config->brightness << EDRV32_PIX_BC_BRIGHTNESS_POS) &
                          EDRV32_PIX_BC_BRIGHTNESS_MASK;
    mmio_write32(EDRV32_PIX_BASE + EDRV32_PIX_BC_OFFSET, config->contrast | brightness);
    mmio_write32(EDRV32_PIX_BASE + EDRV32_PIX_THRESH_OFFSET, config->threshold);
    mmio_write32(EDRV32_PIX_BASE + EDRV32_PIX_CFG_OFFSET, pix_config_word(config));
}

/* PIX 2.3: bank contents become valid only after the whole table has been written. */
void pix_gamma_load(unsigned int bank, const uint8_t values[256])
{
    for (unsigned int index = 0; index < 256u; ++index) {
        mmio_write32(EDRV32_PIX_BASE + EDRV32_PIX_GAMMA_WR_OFFSET,
                     (bank << EDRV32_PIX_GAMMA_WR_BANK_POS) | index |
                     ((uint32_t)values[index] << EDRV32_PIX_GAMMA_WR_VALUE_POS));
    }
}
