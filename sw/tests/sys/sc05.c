/* File: sc05.c
 * Spec: sys-subsys-testplan 3.6 SC-05; sys-subsys-spec 2.8
 * Description: Write eight 16-bit-address SCCB registers on each camera port.
 * Clock domain: clk_sys.
 */
#include "i2c.h"
#include "sc.h"

int main(void)
{
    uint32_t clock_hz = sysctrl_read(SYSCTRL_CLK_SYS_HZ);
    for (unsigned int port = 0u; port < 2u; ++port) {
        i2c_init(port, clock_hz, 400000u);
        for (unsigned int index = 0u; index < 8u; ++index) {
            uint16_t reg = (uint16_t)(0x3000u + index);
            uint8_t value = (uint8_t)(0x40u + port * 0x10u + index);
            if (i2c_sccb_write(0x3cu, reg, value) != 0) {
                sc_finish(0x50u + port * 8u + index);
            }
        }
    }
    sc_finish(0u);
}
