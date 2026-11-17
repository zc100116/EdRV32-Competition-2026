/* farm.c — R5-4; three vertical pens, inventory and persistent animal alerts.
 * Pure C, caller clock in milliseconds; event and sample rings retain newest data.
 */
#include "farm.h"
#include <stdio.h>
#include <string.h>
const char *const farm_pen_names[FARM_PENS]={"牛栏","羊圈","禽舍"};
const unsigned farm_class_ids[FARM_CLASSES]={19,17,18,14};
const unsigned farm_home_pen[FARM_CLASSES]={0,0,1,2};
static const char *const animals[FARM_CLASSES]={"牛","马","羊","鸟"};
static const char *const units[FARM_CLASSES]={"头","匹","只","只"};
int farm_animal(unsigned class_id)
{
    for(unsigned i=0;i<FARM_CLASSES;++i)
        if(farm_class_ids[i]==class_id) return (int)i;
    return -1;
}
void farm_init(farm_t *f, uint32_t now, void (*event)(const farm_event_t *))
{
    memset(f,0,sizeof *f);
    f->sample_tick=now;
    f->event=event;
}
static void record(farm_t *f, unsigned pen, unsigned animal, unsigned amount,
                   bool crossing, bool active, uint32_t now)
{
    farm_event_t e={now,pen,animal,amount,crossing,active};
    f->events[f->event_head]=e;
    f->event_head=(f->event_head+1)%FARM_EVENTS;
    if(f->event_count<FARM_EVENTS) ++f->event_count;
    ++f->event_revision;
    f->event(&e);
}
static void alarm_update(farm_t *f, farm_alarm_t *a, bool condition,
                         unsigned delay, unsigned pen, unsigned animal,
                         unsigned amount, bool crossing, uint32_t now)
{
    if(!condition) {
        if(a->active) record(f,pen,animal,amount,crossing,false,now);
        *a=(farm_alarm_t){0};
        return;
    }
    if(!a->pending) { a->since=now; a->pending=true; }
    if(!a->active && now-a->since>=delay) {
        a->active=true;
        record(f,pen,animal,amount,crossing,true,now);
    }
}
static void evaluate(farm_t *f, uint32_t now)
{
    for(unsigned p=0;p<FARM_PENS;++p) for(unsigned a=0;a<FARM_CLASSES;++a) {
        bool less=f->counts[p][a]<f->expected[p][a];
        unsigned deficit=less ? f->expected[p][a]-f->counts[p][a] : 0;
        alarm_update(f,&f->missing[p][a],less,2000,p,a,deficit,false,now);
        alarm_update(f,&f->crossing[p][a],p!=farm_home_pen[a] && f->counts[p][a],
                     1000,p,a,f->counts[p][a],true,now);
    }
}
void farm_frame(farm_t *f, const farm_box_t *boxes, unsigned count,
                unsigned width, uint32_t now)
{
    memset(f->counts,0,sizeof f->counts);
    memset(f->total,0,sizeof f->total);
    for(unsigned i=0;i<count;++i) {
        int a=farm_animal(boxes[i].class_id);
        if(a<0) continue;
        /* Bottom midpoint selects a vertical pen; y does not affect membership. */
        unsigned p=(unsigned)(2*boxes[i].x+boxes[i].width)*FARM_PENS/(2*width);
        ++f->counts[p][a];
        ++f->total[a];
    }
    evaluate(f,now);
    if(now-f->sample_tick>=10000) {
        farm_sample_t *s=&f->samples[f->sample_head];
        s->time_ms=now;
        memcpy(s->total,f->total,sizeof s->total);
        f->sample_head=(f->sample_head+1)%FARM_SAMPLES;
        if(f->sample_count<FARM_SAMPLES) ++f->sample_count;
        ++f->sample_revision;
        f->sample_tick=now;
    }
}
void farm_inventory(farm_t *f, uint32_t now)
{
    memcpy(f->expected,f->counts,sizeof f->expected);
    evaluate(f,now);
}
unsigned farm_alerts(const farm_t *f)
{
    unsigned n=0;
    for(unsigned p=0;p<FARM_PENS;++p) for(unsigned a=0;a<FARM_CLASSES;++a)
        n+=f->missing[p][a].active+f->crossing[p][a].active;
    return n;
}
bool farm_pen_alert(const farm_t *f, unsigned p)
{
    for(unsigned a=0;a<FARM_CLASSES;++a)
        if(f->missing[p][a].active || f->crossing[p][a].active) return true;
    return false;
}
void farm_event_text(const farm_event_t *e, char *text, size_t size)
{
    if(!e->active)
        snprintf(text,size,"%s%s%s已解除",farm_pen_names[e->pen],animals[e->animal],
                 e->crossing ? "串栏" : "走失");
    else if(e->crossing)
        snprintf(text,size,"%s进了%s",animals[e->animal],farm_pen_names[e->pen]);
    else
        snprintf(text,size,"%s少 %u %s%s",farm_pen_names[e->pen],e->amount,
                 units[e->animal],animals[e->animal]);
}
