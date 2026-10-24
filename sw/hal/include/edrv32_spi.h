/* ============================================================================
 * File        : edrv32_spi.h
 * Author      : Edward ZC
 * Description : SPI0 polling HAL and non-destructive SPI Flash probes.
 * Notes       : The JEDEC-ID helper performs command 0x9F in SPI mode 0.
 * ========================================================================== */
#ifndef EDRV32_SPI_H
#define EDRV32_SPI_H

#define EDRV32_SPI_OK       0
#define EDRV32_SPI_TIMEOUT -1
#define EDRV32_SPI_ERROR   -2

void edrv32_spi_init(unsigned int divider);
int edrv32_spi_flash_read_jedec_id(unsigned int *jedec_id,
                                   unsigned int timeout_cycles);

#endif /* EDRV32_SPI_H */
