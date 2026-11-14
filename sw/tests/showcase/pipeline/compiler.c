/* compiler.c — PIPE-SPEC 7.1/7.4; exact accepted ranges and frozen hop sequences.
 * Hardware-independent test runner; host CPU clock.
 */
#include "pipeline.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static ui_chain_t chain;
static void block(unsigned type, unsigned flags, int a, int b, int c, int d)
{ chain.block[chain.count++] = (ui_block_t){type, flags, {a,b,c,d,0}}; }
static void reset(unsigned source)
{ chain = (ui_chain_t){.source = source, .view = UI_VIEW_FINAL}; }
static void bad(const ui_chain_t *c) { assert(pipe_chain_validate(c) == 2); }
static void validation(void)
{
    reset(0); assert(!pipe_chain_validate(&chain));
    const unsigned types[] = {1,2,3,4,5,6,7,8,9};
    const int16_t params[][5] = {{0,256,0,0,0},{10,0,0,0,0},{2,0,0,0,0},
        {0},{128,0,0,0,0},{0},{0,100,0,0,0},{0},{0}};
    const unsigned used[] = {2,1,1,0,1,0,4,0,0};
    for (unsigned t = 0; t < 9; ++t) {
        reset(0); block(types[t], types[t] == 9 ? 2 : 0, 0,0,0,0);
        memcpy(chain.block[0].p, params[t], sizeof chain.block[0].p);
        assert(!pipe_chain_validate(&chain));
        for (unsigned j = used[t]; j < 5; ++j) {
            ui_chain_t c = chain; c.block[0].p[j] = 1; bad(&c);
        }
        ui_chain_t c = chain; c.block[0].flags |= 4; bad(&c);
        if (types[t] != 7 && types[t] != 9) {
            c = chain; c.block[0].flags = 1; bad(&c);
        }
    }
    const struct { unsigned type, index; int low, high; } ranges[] = {
        {1,0,-256,255},{1,1,0,512},{2,0,3,30},{3,0,1,6},{5,0,0,255},
        {7,0,-180,180},{7,1,50,400},{7,2,-1280,1280},{7,3,-720,720}};
    for (unsigned i = 0; i < sizeof ranges/sizeof ranges[0]; ++i) {
        unsigned type = ranges[i].type;
        reset(0); block(type, 0, 0, type == 7 ? 100 : 256, 0, 0);
        if (type != 7 && type != 1) chain.block[0].p[1] = 0;
        chain.block[0].p[ranges[i].index] = ranges[i].low;
        assert(!pipe_chain_validate(&chain));
        chain.block[0].p[ranges[i].index] = ranges[i].high;
        assert(!pipe_chain_validate(&chain));
        chain.block[0].p[ranges[i].index] = ranges[i].low - 1; bad(&chain);
        chain.block[0].p[ranges[i].index] = ranges[i].high + 1; bad(&chain);
    }
    reset(0); block(8,0,0,0,0,0); block(8,0,0,0,0,0); bad(&chain);
    reset(0); block(9,1,0,0,0,0); bad(&chain);
    chain.block[0].flags = 0; bad(&chain);
    chain.block[0].flags = 2; assert(!pipe_chain_validate(&chain));
    block(8,0,0,0,0,0); block(9,3,0,0,0,0); assert(!pipe_chain_validate(&chain));
    chain.block[0].type = 0; bad(&chain); chain.block[0].type = 10; bad(&chain);
    reset(0); chain.count = 9; bad(&chain); reset(3); bad(&chain);
    reset(0); chain.view = 0; bad(&chain); block(4,0,0,0,0,0);
    assert(!pipe_chain_validate(&chain)); chain.view = 1; bad(&chain);
    reset(0); chain.preset = 9; bad(&chain);
    for (unsigned i = 0; i < 8; ++i) {
        reset(0); chain.block[i].type = 4; bad(&chain);
        chain.block[i].type = 0; chain.block[i].flags = 1; bad(&chain);
        chain.block[i].flags = 0;
        for (unsigned j = 0; j < 5; ++j) {
            chain.block[i].p[j] = 1; bad(&chain); chain.block[i].p[j] = 0;
        }
    }
    for (unsigned src = 0; src < 3; ++src) {
        reset(src); for (unsigned i = 0; i < 8; ++i) block(7,3,180,400,1280,720);
        assert(!pipe_chain_validate(&chain));
    }
    puts("PASS 7.1 all field ranges, reserved fields, limits, detection and overlay rules");
}
static void expect(unsigned count, const unsigned engines[])
{
    struct pipe_plan p; pipe_compile(&chain, &p);
    assert(!pipe_chain_validate(&chain)); assert(p.count == count);
    for (unsigned i = 0; i < count; ++i) assert(p.hop[i].engine == engines[i]);
}
static void compile(void)
{
    reset(0); block(3,0,2,0,0,0); block(4,0,0,0,0,0); block(3,0,2,0,0,0);
    expect(2, (unsigned[]){0,2});
    struct pipe_plan p; pipe_compile(&chain, &p);
    assert(p.hop[0].first == 0 && p.hop[0].last == 1 && p.hop[1].first == 2);
    reset(0); block(7,0,90,100,0,0); expect(2,(unsigned[]){1,4});
    reset(0); block(2,0,10,0,0,0); block(1,0,0,256,0,0); expect(2,(unsigned[]){0,2});
    reset(1); block(3,0,2,0,0,0); block(3,0,2,0,0,0); block(3,0,2,0,0,0);
    expect(2,(unsigned[]){2,2});
    for (unsigned type = 1; type <= 6; ++type) if (type != 3) {
        reset(2); int a = type == 2 ? 10 : 0, b = type == 1 ? 256 : 0;
        block(type,0,a,b,0,0); block(type,0,a,b,0,0); expect(2,(unsigned[]){2,2});
    }
    reset(1); block(8,0,0,0,0,0); block(4,0,0,0,0,0); expect(1,(unsigned[]){2});
    pipe_compile(&chain,&p); assert(p.sample[0] == 0 && p.pix_first[0] == 1);
    assert(p.block_hop[0] == 0 && p.block_hop[1] == 0);
    reset(1); block(4,0,0,0,0,0); block(8,0,0,0,0,0); expect(2,(unsigned[]){2,3});
    reset(0); block(8,0,0,0,0,0); block(9,3,0,0,0,0); block(7,0,30,75,0,0);
    expect(4,(unsigned[]){1,3,5,4}); pipe_compile(&chain,&p); assert(p.hide_l1);
    reset(0); block(8,0,0,0,0,0); block(7,0,30,75,0,0); block(9,1,0,0,0,0);
    expect(4,(unsigned[]){1,3,4,5}); pipe_compile(&chain,&p); assert(!p.hide_l1);
    reset(1); expect(0,(unsigned[]){0}); reset(2); expect(0,(unsigned[]){0});
    reset(0); expect(1,(unsigned[]){1});
    puts("PASS 7.4 fusion, ordering, repeats, filter slots, taps, overlays and DDR sources");
}
static void presets(void)
{
    const unsigned count[] = {3,4,4,4,4,4,2,1};
    const unsigned engine[][4] = {{1,3,5},{0,2,3,5},{1,4,3,5},{1,4,3,5},
        {1,3,5,4},{0,2,3,5},{0,2},{3}};
    for (unsigned i = 1; i <= 8; ++i) {
        pipe_chain_preset(&chain,i); expect(count[i-1], engine[i-1]);
        assert(chain.preset == i);
        uint8_t bytes[100]; ui_chain_t roundtrip;
        pipe_chain_encode(bytes,&chain); pipe_chain_decode(&roundtrip,bytes);
        assert(!memcmp(&roundtrip,&chain,sizeof chain));
        struct pipe_plan p; pipe_compile(&chain,&p);
        printf("preset %u:",i);
        for (unsigned h = 0; h < p.count; ++h)
            printf(" %u[%u..%u]",p.hop[h].engine,p.hop[h].first,p.hop[h].last);
        puts("");
    }
}
int main(void) { validation(); compile(); presets(); puts("PASS pipeline compiler"); }
