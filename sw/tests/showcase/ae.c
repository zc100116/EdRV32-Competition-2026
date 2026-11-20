/* ae.c — live demo L9; actual driver register writes for three exposure targets. */
#include "ov5640.h"
#include <assert.h>
#include <stdio.h>
static unsigned position;
static const unsigned addresses[] = {0x3a0f,0x3a1b,0x3a10,0x3a1e,0x3a11,0x3a1f};
static const unsigned expected[][6] = {{47,47,40,40,94,20},
                                     {86,86,73,73,172,36},
                                     {129,129,110,110,255,55}};
static unsigned test;
void i2c_init(unsigned camera, unsigned hz, unsigned baud)
{ assert(camera == 0 && hz == 100000000 && baud == 100000); }
int i2c_sccb_write(unsigned char device, unsigned short address, unsigned char value)
{
    assert(device == 0x3c && position < 6);
    assert(address == addresses[position] && value == expected[test][position]);
    ++position; return 0;
}
int main(void)
{
    const unsigned targets[] = {44,80,120};
    for (test = 0; test < 3; ++test) {
        position = 0;
        assert(ov5640_set_ae_target(0,100000000,targets[test]) == 0 && position == 6);
    }
    puts("PASS AEC: six real driver writes for targets 44, 80, 120");
}
