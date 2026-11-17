/* farm.c — R5-4; host acceptance for farm counts, timers and retained history.
 * Deterministic caller clock; no LVGL or camera dependency.
 */
#include "farm.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static unsigned starts, clears;
static void event(const farm_event_t *e)
{
    if(e->active) ++starts;
    else ++clears;
}
int main(void)
{
    farm_t f;
    farm_init(&f,0,event);
    farm_box_t boxes[]={
        {19,100,100,200,180},{19,240,140,100,90},
        {17,10,180,90,120},{18,520,80,100,90},
        {14,1000,40,80,60},{0,900,100,100,200}};
    assert(f.boundaries[0]==33 && f.boundaries[1]==67);
    farm_frame(&f,boxes,6,1280,0);
    assert(f.counts[0][0]==2 && f.counts[0][1]==1);
    assert(f.counts[1][2]==1 && f.counts[2][3]==1);
    assert(farm_alerts(&f)==0);
    assert(f.sample_count==0);
    farm_inventory(&f,0);
    assert(!memcmp(f.counts,f.expected,sizeof f.counts));
    boxes[0].class_id=0;
    farm_frame(&f,boxes,6,1280,100);
    farm_frame(&f,boxes,6,1280,2099);
    assert(farm_alerts(&f)==0);
    farm_frame(&f,boxes,6,1280,2100);
    assert(farm_alerts(&f)==1 && farm_pen_alert(&f,0));
    char text[100];
    farm_event_text(&f.events[0],text,sizeof text);
    assert(!strcmp(text,"牛栏少 1 头牛"));
    assert(f.events[0].time_ms==2100);
    boxes[0].class_id=19;
    farm_frame(&f,boxes,6,1280,2200);
    assert(farm_alerts(&f)==0 && clears==1);
    /* A short loss must restart the continuous two-second deadline. */
    boxes[0].class_id=0;
    farm_frame(&f,boxes,6,1280,2300);
    boxes[0].class_id=19;
    farm_frame(&f,boxes,6,1280,2400);
    boxes[0].class_id=0;
    farm_frame(&f,boxes,6,1280,3000);
    farm_frame(&f,boxes,6,1280,4999);
    assert(farm_alerts(&f)==0);
    farm_frame(&f,boxes,6,1280,5000);
    assert(farm_alerts(&f)==1);
    farm_inventory(&f,5001);
    assert(farm_alerts(&f)==0);
    /* Sheep bottom midpoint enters pen zero even though its box crosses a line. */
    boxes[3].x=350; boxes[3].width=100;
    farm_frame(&f,boxes,6,1280,6000);
    farm_frame(&f,boxes,6,1280,6999);
    assert(!f.crossing[0][2].active);
    farm_frame(&f,boxes,6,1280,7000);
    assert(f.crossing[0][2].active);
    farm_event_text(&f.events[(f.event_head+FARM_EVENTS-1)%FARM_EVENTS],text,sizeof text);
    assert(!strcmp(text,"羊进了牛栏"));
    boxes[3].x=520;
    farm_frame(&f,boxes,6,1280,7100);
    assert(!f.crossing[0][2].active);
    /* Exact vertical boundaries belong to the pen on the right. */
    farm_box_t boundaries[]={{18,310,10,40,20},{14,650,10,40,20}};
    farm_init(&f,0,event);
    farm_frame(&f,boundaries,2,1000,0);
    assert(f.counts[1][2]==1 && f.counts[2][3]==1);
    farm_inventory(&f,0);
    for(unsigned i=0;i<12;++i) {
        uint32_t now=100+i*4000;
        farm_frame(&f,boundaries+1,1,1000,now);
        farm_frame(&f,boundaries+1,1,1000,now+2000);
        farm_frame(&f,boundaries,2,1000,now+2100);
    }
    assert(f.event_count==20 && f.event_revision==24 && f.event_head==4);
    assert(f.events[f.event_head].time_ms==10100);
    assert(!f.events[(f.event_head+19)%20].active);
    farm_init(&f,0,event);
    farm_frame(&f,boxes,6,1280,9999);
    assert(f.sample_count==0);
    farm_frame(&f,boxes,6,1280,10000);
    assert(f.sample_count==1 && f.samples[0].time_ms==10000);
    assert(f.samples[0].total[0]==1 && f.samples[0].total[1]==1);
    for(unsigned i=2;i<=61;++i) farm_frame(&f,boxes,6,1280,i*10000);
    assert(f.sample_count==60 && f.sample_head==1 && f.sample_revision==61);
    assert(f.samples[f.sample_head].time_ms==20000);
    farm_init(&f,0,event);
    assert(f.boundaries[0]==33 && f.boundaries[1]==67);
    farm_box_t edges[]={{19,310,0,40,80},{18,650,0,40,80}};
    farm_frame(&f,edges,2,1000,0);
    assert(f.counts[1][0]==1 && f.counts[2][2]==1);
    f.boundaries[0]=40;
    f.boundaries[1]=75;
    farm_frame(&f,edges,2,1000,1);
    assert(f.counts[0][0]==1 && f.counts[1][2]==1);
    f.boundaries[0]=25;
    f.boundaries[1]=60;
    farm_frame(&f,edges,2,1000,2);
    assert(f.counts[1][0]==1 && f.counts[2][2]==1);
    assert(starts>0 && clears>0);
    puts("PASS farm: pen counts, inventory, loss/recovery, crossing, 20 events, 60 samples");
    return 0;
}
