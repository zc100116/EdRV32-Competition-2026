/* live.c — live demo L3–L5; gain limits, protocol validation and STATE bytes. */
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
    assert(preprocess_gain(384,102,110) == 384);
    assert(preprocess_gain(384,118,110) == 384);
    assert(preprocess_gain(256,55,110) == 384);
    assert(preprocess_gain(640,220,110) == 480);
    assert(preprocess_gain(256,255,110) == 256);
    assert(preprocess_gain(600,20,110) == 640);
    assert(preprocess_gain(256,0,110) == 640);
    static uint16_t frame[1280*720];
    assert(preprocess_luma(frame,1280) == 0);
    memset(frame,255,sizeof frame);
    assert(preprocess_luma(frame,1280) == 255);
    struct edsc s = {.ops = {.reply=reply,.state=state,.command=command,.progress=progress}};
    for (unsigned action = 0; action <= 4; ++action) {
        unsigned arg = action == 0 ? 10 : action == 3 ? 3 : 0;
        send(&s,action,arg,0,4);
        assert(replies == 1 && phase[0] == 1 && !error);
        result = EDSC_PENDING; edsc_poll(&s,0,100);
        assert(replies == 1);
        result = 0; edsc_poll(&s,0,100);
        assert(replies == 2 && phase[1] == 2 && !error);
    }
    unsigned accepted = commands;
    const unsigned bad[][3] = {{0,0,0},{0,11,0},{3,4,0},{5,0,0},{1,1,0},{2,1,0},
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
    snapshot.demo_scene = 10; board_state_encode(payload,&snapshot); assert(payload[5] == 10);
    snapshot.demo_scene = 0; board_state_encode(payload,&snapshot); assert(payload[5] == 0);
    puts("PASS live demo: deadband, half-step, clamps, black/white luma, actions, ACK and STATE");
}
