/* state.c — P5 8.3/8.4; little endian board and host codec, CPU clock domain. */
#include "state.h"
#include "records.h"
#include <string.h>
static void put16(uint8_t *p, int v) { p[0] = (uint8_t)v; p[1] = (uint8_t)(v >> 8); }
void board_state_encode(uint8_t p[56], const struct board_state *s)
{
    const ui_process_config_t *c = &s->process;
    memset(p, 0, 56);
    p[0] = s->session.app; p[1] = s->session.state; p[2] = s->error;
    p[3] = s->boxes; p[4] = s->detection.threshold;
    for (unsigned i = 0; i < 3; ++i) record_put32(p+8+4*i, s->detection.classes[i]);
    record_put32(p+20, c->enabled);
    put16(p+24, c->brightness); put16(p+26, c->contrast); put16(p+28, c->gamma_tenths);
    p[30] = c->stage1; p[31] = c->stage2; p[32] = c->threshold; p[33] = c->original;
    put16(p+34, c->angle); put16(p+36, c->scale_percent);
    put16(p+38, c->translate_x); put16(p+40, c->translate_y);
    record_put32(p+44, s->request); record_put32(p+48, s->frame);
    p[52] = s->image_status;
}
