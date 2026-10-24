/* ============================================================================
 * File        : spi.c
 * Author      : Edward ZC
 * Description : Polling SPI0 driver for basic SPI Flash diagnostics.
 * Notes       : Full-duplex single-lane mode receives Flash MISO on IO1.
 * ========================================================================== */
#include "edrv32_mmio.h"
#include "edrv32_soc_map.h"
#include "edrv32_spi.h"

#define SPI_CTRL_OFFSET   0x00u
#define SPI_STATUS_OFFSET 0x04u
#define SPI_TXDATA_OFFSET 0x08u
#define SPI_RXDATA_OFFSET 0x0cu
#define SPI_CLKDIV_OFFSET 0x10u
#define SPI_CSMASK_OFFSET 0x14u
#define SPI_BITS_OFFSET   0x18u
#define SPI_MODE_OFFSET   0x24u
#define SPI_CMD_OFFSET    0x28u

#define SPI_CTRL_ENABLE     (1u << 0)
#define SPI_CTRL_FIFO_CLEAR (1u << 7)
#define SPI_CTRL_CS_AUTO    (1u << 8)

#define SPI_STATUS_BUSY       (1u << 0)
#define SPI_STATUS_DONE       (1u << 1)
#define SPI_STATUS_TX_FULL    (1u << 3)
#define SPI_STATUS_RX_EMPTY   (1u << 4)
#define SPI_STATUS_ERROR_MASK (0x0fu << 6)

#define SPI_MODE_COMMAND_PHASE (1u << 4)
#define SPI_COMMAND_BITS_8     (8u << 8)
#define SPI_FLASH_JEDEC_ID_CMD 0x9fu

static unsigned int spi_read(unsigned int offset)
{
    return edrv32_mmio_read32(SOC_SPI0_BASE + offset);
}

static void spi_write(unsigned int offset, unsigned int value)
{
    edrv32_mmio_write32(SOC_SPI0_BASE + offset, value);
}

void edrv32_spi_init(unsigned int divider)
{
    spi_write(SPI_CTRL_OFFSET, 0u);
    spi_write(SPI_CLKDIV_OFFSET, divider & 0xffffu);
    spi_write(SPI_CSMASK_OFFSET, 1u);
    spi_write(SPI_BITS_OFFSET, 8u);
    spi_write(SPI_MODE_OFFSET, 0u);
    spi_write(SPI_CMD_OFFSET, 0u);
    spi_write(SPI_CTRL_OFFSET, SPI_CTRL_ENABLE |
                                  SPI_CTRL_FIFO_CLEAR |
                                  SPI_CTRL_CS_AUTO);
}

int edrv32_spi_flash_read_jedec_id(unsigned int *jedec_id,
                                   unsigned int timeout_cycles)
{
    unsigned int status;

    if (jedec_id == (unsigned int *)0)
        return EDRV32_SPI_ERROR;

    spi_write(SPI_CTRL_OFFSET, SPI_CTRL_ENABLE |
                                  SPI_CTRL_FIFO_CLEAR |
                                  SPI_CTRL_CS_AUTO);
    spi_write(SPI_BITS_OFFSET, 24u);
    spi_write(SPI_MODE_OFFSET, SPI_MODE_COMMAND_PHASE);
    spi_write(SPI_CMD_OFFSET, SPI_COMMAND_BITS_8 |
                                 SPI_FLASH_JEDEC_ID_CMD);

    status = spi_read(SPI_STATUS_OFFSET);
    if ((status & SPI_STATUS_TX_FULL) != 0u)
        return EDRV32_SPI_ERROR;
    spi_write(SPI_TXDATA_OFFSET, 0u);

    while (timeout_cycles != 0u) {
        status = spi_read(SPI_STATUS_OFFSET);
        if ((status & SPI_STATUS_ERROR_MASK) != 0u)
            return EDRV32_SPI_ERROR;
        if (((status & SPI_STATUS_BUSY) == 0u) &&
            ((status & SPI_STATUS_DONE) != 0u) &&
            ((status & SPI_STATUS_RX_EMPTY) == 0u)) {
            *jedec_id = spi_read(SPI_RXDATA_OFFSET) & 0x00ffffffu;
            return EDRV32_SPI_OK;
        }
        timeout_cycles--;
    }

    return EDRV32_SPI_TIMEOUT;
}
