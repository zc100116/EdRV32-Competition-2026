/* File: es8156.c
 * Spec: aud-spec 9 A-3; ES8156 datasheet rev 5 registers 02, 08, 11.
 * Description: Manufacturer PMOD power sequence with software slave and 16-bit I2S.
 * Clock domain: clk_sys software; codec MCLK 12.288 MHz (256 Fs).
 */
#include "es8156.h"
#include "i2c.h"

/* PMOD ES8156_reg_config.v sequence; 02=04 selects software slave (MS_MODE=0).
 * 08=2b/2f keeps external SCLK/LRCK on and master clock outputs off.
 * 11=30 selects 16-bit standard I2S; 01=21 uses the supplied 256 Fs MCLK. */
static const uint8_t configuration[][2] = {
    {0x10, 0x00}, {0x00, 0x3c}, {0x00, 0x05}, {0x00, 0x1c},
    {0x02, 0x04}, {0x03, 0x01}, {0x04, 0x00}, {0x05, 0x08},
    {0x06, 0x00}, {0x08, 0x2b}, {0x13, 0x00}, {0x20, 0x2a},
    {0x21, 0x3c}, {0x22, 0x02}, {0x24, 0x07}, {0x23, 0x3a},
    {0x0a, 0x01}, {0x0b, 0x01}, {0x14, 0xbd}, {0x01, 0x21},
    {0x0d, 0x14}, {0x18, 0x00}, {0x08, 0x2f}, {0x25, 0x20},
    {0x00, 0x02}, {0x00, 0x03}, {0x11, 0x30}
};

int es8156_init(void)
{
    i2c_init(0u, EDRV32_CLK_SYS_HZ, 100000u);
    for (unsigned int i = 0; i < sizeof(configuration) / sizeof(configuration[0]); ++i) {
        /* Device write address 0x12; codec has an 8-bit register address. */
        if (i2c_command(I2C_CMD_START | 0x12u) != 0) {
            return -1;
        }
        if (i2c_command(configuration[i][0]) != 0) {
            return -1;
        }
        if (i2c_command(I2C_CMD_STOP | configuration[i][1]) != 0) {
            return -1;
        }
    }
    return 0;
}
