/* live.c — live demo L3/L9/L10; levels and gamma, protocol validation and STATE bytes. */
#include "protocol.h"
#include "state.h"
#include "vision/preprocess.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static unsigned replies, commands, result, phase[3], error;
static uint8_t payload[56];
static void reply(const uint8_t *p, unsigned bytes)
{
    assert(bytes == 16 && p[4] == 0x86 && p[12] == 9);
    phase[replies++] = p[14]; error = p[15];
}
static void state(uint8_t p[56]) { memcpy(p,payload,56); }
static unsigned command(unsigned type,const uint8_t *p,unsigned n,uint32_t seq)
{ assert(type == 9 && n == 4 && seq == 42); (void)p; ++commands; return EDSC_PENDING; }
static unsigned progress(unsigned type) { assert(type == 9); return result; }
static void send(struct edsc *s, unsigned action, unsigned arg, unsigned reserved, unsigned n)
{
    uint8_t message[16] = {'E','D','S','C',9,0,(uint8_t)n,0,42,0,0,0,
                          (uint8_t)action,(uint8_t)arg,(uint8_t)reserved,0};
    replies = 0; edsc_message(s,message,12+n);
}
int main(void)
{
    assert(SHOWCASE_DEFAULT_PRESET == 1 && SHOWCASE_TARGET_LUMA == 110);
    static uint16_t frame[1280*720];
    struct preprocess_stats stats = preprocess_measure(frame,1280);
    assert(stats.mean == 0 && stats.lo == 0 && stats.hi == 0);
    memset(frame,255,sizeof frame);
    stats = preprocess_measure(frame,1280);
    assert(stats.mean == 255 && stats.lo == 255 && stats.hi == 255);
    /* 2% black, 96% middle gray and 2% white: exact percentile ranks. */
    for (unsigned i = 0; i < 3600; ++i)
        frame[(i/80)*16*1280+(i%80)*16] = i < 72 ? 0 : i < 3528 ? 0x8410 : 0xffff;
    stats = preprocess_measure(frame,1280);
    assert(stats.lo == 0 && stats.hi == 130);
    int c, b;
    preprocess_levels(0,80,&c,&b); assert(c == 511 && b == 144);
    preprocess_levels(150,250,&c,&b); assert(c == 511 && b == -155);
    preprocess_levels(100,105,&c,&b); assert(c == 511 && b == -56);
    preprocess_levels(255,255,&c,&b); assert(c == 511 && b == -256);
    preprocess_levels(16,240,&c,&b); assert(c == 256 && b == 0);
    assert(preprocess_gamma(0,10) == 4 && preprocess_gamma(255,4) == 10);
    assert(preprocess_gamma(55,10) == 5);
    assert(preprocess_gamma(80,7) == 7); /* gamma=0.719 lies inside deadband */
    assert(preprocess_gamma(80,9) == 7);
    assert(preprocess_gamma_value(0,4) == 0 && preprocess_gamma_value(255,4) == 255);
    assert(preprocess_gamma_value(128,4) == 194 && preprocess_gamma_value(128,10) == 128);
    assert(preprocess_bc(0,511,-256) == 0);
    assert(preprocess_bc(255,511,255) == 255);
    struct edsc s = {.ops = {.reply=reply,.state=state,.command=command,.progress=progress}};
    for (unsigned action = 0; action <= 4; ++action) {
        unsigned arg = action == 0 ? 11 : action == 3 ? 3 : 0;
        send(&s,action,arg,0,4);
        assert(replies == 1 && phase[0] == 1 && !error);
        result = EDSC_PENDING; edsc_poll(&s,0,100);
        assert(replies == 1);
        result = 0; edsc_poll(&s,0,100);
        assert(replies == 2 && phase[1] == 2 && !error);
    }
    unsigned accepted = commands;
    const unsigned bad[][3] = {{0,0,0},{0,12,0},{3,4,0},{5,0,0},{1,1,0},{2,1,0},
                               {4,1,0},{0,1,1}};
    for (unsigned i = 0; i < sizeof bad/sizeof bad[0]; ++i) {
        send(&s,bad[i][0],bad[i][1],bad[i][2],4);
        assert(replies == 1 && phase[0] == 3 && error == 2 && commands == accepted);
    }
    send(&s,0,1,0,3);
    assert(replies == 1 && phase[0] == 3 && error == 1);
    struct board_state snapshot = {.demo_scene=255,.preset=3,.luma=62};
    board_state_encode(payload,&snapshot);
    assert(payload[5] == 255 && payload[6] == 3 && payload[7] == 62);
    snapshot.demo_scene = 11; board_state_encode(payload,&snapshot); assert(payload[5] == 11);
    snapshot.demo_scene = 0; board_state_encode(payload,&snapshot); assert(payload[5] == 0);
    puts("PASS live demo: percentiles, BC, gamma deadband, clamps, black/white luma, actions, ACK and STATE");
}
