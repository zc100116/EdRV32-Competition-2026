/* state.c — P5 8.4; verify all fields, signed parameters and reserved bytes. */
#include "state.h"
#include <assert.h>
#include <string.h>
#include <stdio.h>
int main(void)
{
    struct board_state s={.session={.app=UI_APP_PIPELINE,.state=UI_STATE_RUNNING},.error=6,
        .boxes=true,.detection={50,{0x12345678,0x9abcdef0,0x4321}},
        .chain_rev=0x12345678,
        .request=0x12345678,.frame=0x87654321,.image_status=UI_IMAGE_DETECTING};
    const uint8_t exact[56]={1,2,6,1,50,0,0,0,0x78,0x56,0x34,0x12,
        0xf0,0xde,0xbc,0x9a,0x21,0x43,0,0,0x78,0x56,0x34,0x12,
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        0x78,0x56,0x34,0x12,0x21,0x43,0x65,0x87,2,0,0,0};
    uint8_t output[56]; board_state_encode(output,&s);
    assert(!memcmp(output,exact,56));
    s.error = 7; s.session.state = UI_STATE_FAILED;
    board_state_encode(output, &s);
    assert(output[1] == 5 && output[2] == 7);
    puts("PASS STATE exact 56-byte little endian layout");
}
