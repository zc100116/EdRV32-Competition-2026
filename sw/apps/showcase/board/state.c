/* state.c — P5 8.3/8.4; little endian board and host codec, CPU clock domain. */
#include "state.h"
#include "records.h"
#include <string.h>
void board_state_encode(uint8_t p[56], const struct board_state *s)
{
    memset(p, 0, 56);
    p[0] = s->session.app; p[1] = s->session.state; p[2] = s->error;
    p[3] = s->boxes; p[4] = s->detection.threshold;
    for (unsigned i = 0; i < 3; ++i) record_put32(p+8+4*i, s->detection.classes[i]);
    record_put32(p+20, s->chain_rev);
    record_put32(p+44, s->request); record_put32(p+48, s->frame);
    p[52] = s->image_status;
}
