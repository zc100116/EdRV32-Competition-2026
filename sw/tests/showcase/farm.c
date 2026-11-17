/* farm.c — R5-11; single-region inventory and timed intrusion acceptance.
 * Deterministic monotonic clock; no LVGL, detector or camera dependency.
 */
#include "farm.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static unsigned events[4];
static void event(const farm_event_t *e) { ++events[e->type]; }
static farm_box_t boxes[]={
    {19,100,100,200,180},{19,1000,140,100,90},
    {17,10,180,90,120},{18,520,80,100,90},
    {14,1000,40,80,60},{0,900,100,100,200}};
static void missing(void)
{
    farm_t f;
    farm_init(&f,0,event);
    farm_frame(&f,boxes,5,0);
    assert(f.counts[0]==2 && f.counts[1]==1 && f.counts[2]==1 && f.counts[3]==1);
    assert(!f.person && !farm_alerts(&f));
    farm_inventory(&f,0);
    assert(!memcmp(f.counts,f.expected,sizeof f.counts));
    boxes[0].class_id=9; /* Other COCO objects do not count as animals or people. */
    farm_frame(&f,boxes,5,100);
    farm_frame(&f,boxes,5,2099);
    assert(!farm_alerts(&f));
    farm_frame(&f,boxes,5,2100);
    assert(farm_alerts(&f)==1 && f.missing[0].active && f.missing_today==1);
    assert(f.events[0].time_ms==2100 && f.events[0].amount==1);
    assert(f.events[0].class_id==19 && f.events[0].type==FARM_MISSING);
    char text[100];
    farm_event_text(&f.events[0],text,sizeof text);
    assert(!strcmp(text,"牛 少 1 头"));
    boxes[0].class_id=19;
    farm_frame(&f,boxes,5,2200);
    assert(!farm_alerts(&f) && f.events[1].type==FARM_MISSING_CLEAR);
    farm_event_text(&f.events[1],text,sizeof text);
    assert(!strcmp(text,"牛 走失解除"));
    boxes[0].class_id=9;
    farm_frame(&f,boxes,5,2300);
    boxes[0].class_id=19;
    farm_frame(&f,boxes,5,2400);
    boxes[0].class_id=9;
    farm_frame(&f,boxes,5,3000);
    farm_frame(&f,boxes,5,4999);
    assert(!farm_alerts(&f));
    farm_frame(&f,boxes,5,5000);
    assert(farm_alerts(&f)==1 && f.missing_today==2);
    farm_inventory(&f,5001);
    assert(!farm_alerts(&f) && f.expected[0]==1);
    boxes[0].class_id=19;
    /* Position no longer assigns animals to a pen. */
    boxes[3].x=0;
    farm_frame(&f,boxes,5,5100);
    boxes[3].x=1200;
    farm_frame(&f,boxes,5,6100);
    assert(f.counts[2]==1 && !farm_alerts(&f));
}
static void intrusion(void)
{
    farm_t f;
    farm_init(&f,0,event);
    farm_frame(&f,boxes,5,0);
    farm_inventory(&f,0);
    farm_frame(&f,boxes,6,100);
    farm_frame(&f,boxes,6,599);
    assert(!farm_alerts(&f));
    farm_frame(&f,boxes,6,600);
    assert(f.intrude.active && farm_alerts(&f)==1 && f.intrude_today==1);
    assert(f.person==1 && f.counts[0]==2 && f.counts[2]==1);
    assert(f.events[0].type==FARM_INTRUDE && f.events[0].class_id==0);
    char text[100];
    farm_event_text(&f.events[0],text,sizeof text);
    assert(!strcmp(text,"有人闯入"));
    farm_frame(&f,boxes,5,700);
    farm_frame(&f,boxes,5,1699);
    assert(f.intrude.active);
    farm_frame(&f,boxes,5,1700);
    assert(!f.intrude.active && f.events[1].type==FARM_INTRUDE_CLEAR);
    farm_event_text(&f.events[1],text,sizeof text);
    assert(!strcmp(text,"闯入解除"));
    farm_frame(&f,boxes,6,1800);
    farm_frame(&f,boxes,5,2100); /* 300 ms appearance must not trigger. */
    farm_frame(&f,boxes,5,2600);
    assert(!farm_alerts(&f) && f.event_count==2 && f.intrude_today==1);
    farm_frame(&f,boxes,6,2700);
    farm_frame(&f,boxes,6,3200);
    farm_frame(&f,boxes,5,3300);
    farm_frame(&f,boxes,6,4200); /* Return before 1 s cancels the clear deadline. */
    assert(f.intrude.active);
    farm_frame(&f,boxes,5,4300);
    farm_frame(&f,boxes,5,5299);
    assert(f.intrude.active);
    farm_frame(&f,boxes,5,5300);
    assert(!f.intrude.active && f.intrude_today==2 && f.event_count==4);
    farm_frame(&f,boxes,5,86400000u);
    assert(f.day==1 && !f.missing_today && !f.intrude_today);
}
static void history(void)
{
    farm_t f;
    farm_init(&f,0,event);
    farm_frame(&f,boxes,5,0);
    farm_inventory(&f,0);
    for(unsigned i=0;i<12;++i) {
        uint32_t now=100+i*4000;
        farm_frame(&f,boxes+1,4,now);
        farm_frame(&f,boxes+1,4,now+2000);
        farm_frame(&f,boxes,5,now+2100);
    }
    assert(f.event_count==20 && f.event_revision==24 && f.event_head==4);
    assert(f.events[f.event_head].time_ms==10100);
    assert(f.events[(f.event_head+19)%20].type==FARM_MISSING_CLEAR);
    assert(f.missing_today==12 && !f.intrude_today);
    farm_init(&f,0,event);
    farm_frame(&f,boxes,5,9999);
    assert(!f.sample_count);
    farm_frame(&f,boxes,5,10000);
    assert(f.sample_count==1 && f.samples[0].time_ms==10000);
    assert(f.samples[0].total[0]==2 && f.samples[0].total[1]==1);
    for(unsigned i=2;i<=61;++i) farm_frame(&f,boxes,5,i*10000);
    assert(f.sample_count==60 && f.sample_head==1 && f.sample_revision==61);
    assert(f.samples[f.sample_head].time_ms==20000);
}
int main(void)
{
    missing();
    intrusion();
    history();
    for(unsigned i=0;i<4;++i) assert(events[i]);
    assert(!strcmp(farm_event_name(FARM_MISSING),"missing"));
    assert(!strcmp(farm_event_name(FARM_MISSING_CLEAR),"missing_clear"));
    assert(!strcmp(farm_event_name(FARM_INTRUDE),"intrude"));
    assert(!strcmp(farm_event_name(FARM_INTRUDE_CLEAR),"intrude_clear"));
    puts("PASS farm: whole-area counts, inventory, 2 s loss/recovery, 0.5 s intrusion, "
         "1 s clear, 0.3 s rejection, daily counts, 20 events and 60 samples");
    return 0;
}
