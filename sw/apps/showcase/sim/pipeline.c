/* pipeline.c — vision pipeline design 7; editable simulator contract and hop estimates.
 * UI/LVGL thread only; numbers are fixed illustration data, not hardware measurements.
 */
#include "sim_data.h"
#include <string.h>
static ui_chain_t chain;
ui_chain_t ui_data_chain(void) { return chain; }
unsigned ui_data_chain_set(const ui_chain_t *c)
{
    if(c->source>2 || c->count>8 || c->preset>8 ||
       (c->view!=UI_VIEW_FINAL && c->view!=UI_VIEW_SOURCE && c->view>=c->count)) return 2;
    unsigned detect=0;
    for(unsigned i=0;i<UI_BLOCK_MAX;++i) {
        const ui_block_t *b=&c->block[i];
        if(i>=c->count) {
            const ui_block_t zero={0};
            if(memcmp(b,&zero,sizeof zero)) return 2;
            continue;
        }
        if(b->type<1 || b->type>9) return 2;
        if(b->type!=UI_BLOCK_GEO && b->type!=UI_BLOCK_OVERLAY && b->flags) return 2;
        unsigned used=0;
        switch(b->type) {
            case UI_BLOCK_LEVEL:
                used=2;
                if(b->p[0]<-256 || b->p[0]>255 || b->p[1]<0 || b->p[1]>512) return 2;
                break;
            case UI_BLOCK_GAMMA:
                used=1; if(b->p[0]<3 || b->p[0]>30) return 2; break;
            case UI_BLOCK_FILTER:
                used=1; if(b->p[0]<1 || b->p[0]>6) return 2; break;
            case UI_BLOCK_BINARY:
                used=1; if(b->p[0]<0 || b->p[0]>255) return 2; break;
            case UI_BLOCK_GEO:
                used=4;
                if(b->flags>3 || b->p[0]<-180 || b->p[0]>180 || b->p[1]<50 ||
                    b->p[1]>400 || b->p[2]<-1280 || b->p[2]>1280 ||
                    b->p[3]<-720 || b->p[3]>720) return 2;
                break;
            case UI_BLOCK_DETECT: if(++detect>1) return 2; break;
            case UI_BLOCK_OVERLAY:
                if(!b->flags || b->flags>3 || ((b->flags&1) && !detect)) return 2;
                break;
            default: break;
        }
        for(unsigned j=used;j<5;++j) if(b->p[j]) return 2;
    }
    chain=*c; chain.preset=0;
    return 0;
}
void ui_data_chain_preset(unsigned preset)
{
    static const ui_chain_t presets[]={
        {.count=2,.block={{.type=8},{.type=9,.flags=1}}},
        {.count=4,.block={{.type=4},{.type=3,.p={4}},{.type=8},{.type=9,.flags=1}}},
        {.count=3,.block={{.type=7,.p={90,100}},{.type=8},{.type=9,.flags=1}}},
        {.count=3,.block={{.type=7,.p={0,200,-160,-90}},{.type=8},{.type=9,.flags=1}}},
        {.count=3,.block={{.type=8},{.type=9,.flags=3},{.type=7,.p={30,75}}}},
        {.count=5,.block={{.type=2,.p={18}},{.type=1,.p={16,320}},{.type=3,.p={2}},
            {.type=8},{.type=9,.flags=1}}},
        {.count=5,.block={{.type=3,.p={2}},{.type=3,.p={4}},{.type=5,.p={128}},
            {.type=3,.p={6}},{.type=3,.p={2}}}},
        {.source=1,.count=2,.block={{.type=8},{.type=9,.flags=1}}}
    };
    chain=presets[preset-1]; chain.view=UI_VIEW_FINAL; chain.preset=(uint8_t)preset;
}
ui_pipe_stats_t ui_data_pipe_stats(void)
{
    ui_pipe_stats_t s={.fps=28,.box_lag_us=37000,.npu_us=35000,.ddr_limit_mbps=1950};
    unsigned at=0;
    bool first=true;
    while(at<chain.count) {
        ui_block_t b=chain.block[at];
        unsigned start=at, engine, cost;
        if(b.type<=UI_BLOCK_INVERT) {
            unsigned used=0, rank=0, filters=0;
            while(at<chain.count && chain.block[at].type<=UI_BLOCK_INVERT) {
                unsigned t=chain.block[at].type;
                unsigned next=t==UI_BLOCK_FILTER ? 3 : t;
                if(next<rank || (t!=UI_BLOCK_FILTER && (used&(1u<<t))) ||
                    (t==UI_BLOCK_FILTER && filters==2)) break;
                rank=next; used|=1u<<t;
                if(t==UI_BLOCK_FILTER) ++filters;
                ++at;
            }
            engine=first && chain.source==UI_SOURCE_CAMERA ? UI_HOP_CAM_PIX : UI_HOP_MEM_PIX;
            cost=engine==UI_HOP_CAM_PIX ? 0 : 3700;
        } else {
            ++at;
            engine=b.type==UI_BLOCK_GEO ? UI_HOP_GEO : b.type==UI_BLOCK_DETECT ?
                UI_HOP_MEM_NPU : UI_HOP_RND;
            cost=engine==UI_HOP_GEO ? 15200 : engine==UI_HOP_MEM_NPU ? 39000 : 4100;
        }
        if(first && chain.source==UI_SOURCE_CAMERA && engine!=UI_HOP_CAM_PIX)
            s.hop[s.hop_count++]=(ui_hop_t){UI_HOP_CAM_RAW,UI_VIEW_FINAL,UI_VIEW_FINAL,0};
        /* Detection shares its input read with a following memory PIX pass (§7.4.4). */
        if(engine==UI_HOP_MEM_NPU && at<chain.count &&
            chain.block[at].type<=UI_BLOCK_INVERT) cost=0;
        s.hop[s.hop_count++]=(ui_hop_t){(uint8_t)engine,(uint8_t)start,(uint8_t)(at-1),cost};
        s.e2e_us+=cost; first=false;
    }
    if(!chain.count && chain.source==UI_SOURCE_CAMERA)
        s.hop[s.hop_count++]=(ui_hop_t){UI_HOP_CAM_RAW,UI_VIEW_FINAL,UI_VIEW_FINAL,0};
    s.ddr_mbps=1250+110*s.hop_count;
    if(s.ddr_mbps>1950) s.fps=28*1950/s.ddr_mbps;
    return s;
}
