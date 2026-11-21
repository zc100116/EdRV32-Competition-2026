/* farm.c — R5-11; stable animal inventory and timed intrusion alerts.
 * Pure C, monotonic caller clock; event/sample rings retain newest entries.
 */
#include "farm.h"
#include <stdio.h>
#include <string.h>
const unsigned farm_class_ids[FARM_CLASSES]={19,17,18,14};
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
    f->day=now/86400000u;
    f->sample_tick=now;
    f->event=event;
}
const char *farm_event_name(farm_event_type_t type)
{
    static const char *const names[]={"missing","missing_clear","intrude","intrude_clear"};
    return names[type];
}
static void record(farm_t *f, farm_event_type_t type, unsigned class_id,
                   unsigned amount, uint32_t now)
{
    farm_event_t e={now,class_id,amount,type};
    f->events[f->event_head]=e;
    f->event_head=(f->event_head+1)%FARM_EVENTS;
    if(f->event_count<FARM_EVENTS) ++f->event_count;
    ++f->event_revision;
    if(type==FARM_MISSING) ++f->missing_today;
    if(type==FARM_INTRUDE) ++f->intrude_today;
    f->event(&e);
}
static void evaluate(farm_t *f, uint32_t now)
{
    for(unsigned a=0;a<FARM_CLASSES;++a) {
        farm_alarm_t *alarm=&f->missing[a];
        bool less=f->counts[a]<f->expected[a];
        if(!less) {
            if(alarm->active) record(f,FARM_MISSING_CLEAR,farm_class_ids[a],0,now);
            *alarm=(farm_alarm_t){0};
        } else {
            if(!alarm->pending) { alarm->since=now; alarm->pending=true; }
            if(!alarm->active && now-alarm->since>=3000) {
                alarm->active=true;
                record(f,FARM_MISSING,farm_class_ids[a],f->expected[a]-f->counts[a],now);
            }
        }
    }
}
static void intrusion(farm_t *f, uint32_t now)
{
    farm_alarm_t *alarm=&f->intrude;
    bool change=alarm->active ? f->person==0 : f->person!=0;
    if(!change) {
        alarm->pending=false;
        return;
    }
    if(!alarm->pending) { alarm->since=now; alarm->pending=true; }
    unsigned delay=alarm->active ? 1000 : 500;
    if(now-alarm->since>=delay) {
        alarm->active=!alarm->active;
        alarm->pending=false;
        record(f,alarm->active ? FARM_INTRUDE : FARM_INTRUDE_CLEAR,0,f->person,now);
    }
}
void farm_frame(farm_t *f, const farm_box_t *boxes, unsigned count, uint32_t now)
{
    unsigned day=now/86400000u;
    if(day!=f->day) {
        f->day=day;
        f->missing_today=f->intrude_today=0;
    }
    unsigned raw[FARM_CLASSES]={0};
    f->person=0;
    for(unsigned i=0;i<count;++i) {
        int a=farm_animal(boxes[i].class_id);
        if(a>=0) ++raw[a];
        if(boxes[i].class_id==0) ++f->person;
    }
    /* L13.2: display, inventory and history all consume the same stable counts. */
    for (unsigned a=0;a<FARM_CLASSES;++a) {
        if (raw[a]!=f->candidate_counts[a]) {
            f->candidate_counts[a]=raw[a];
            f->count_since[a]=now;
        }
        if (now-f->count_since[a]>=1000) f->counts[a]=raw[a];
    }
    evaluate(f,now);
    intrusion(f,now);
    if(now-f->sample_tick>=10000) {
        farm_sample_t *sample=&f->samples[f->sample_head];
        sample->time_ms=now;
        memcpy(sample->total,f->counts,sizeof sample->total);
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
    unsigned n=f->intrude.active;
    for(unsigned a=0;a<FARM_CLASSES;++a) n+=f->missing[a].active;
    return n;
}
void farm_event_text(const farm_event_t *e, char *text, size_t size)
{
    if(e->type==FARM_INTRUDE || e->type==FARM_INTRUDE_CLEAR)
        snprintf(text,size,"%s",e->type==FARM_INTRUDE ? "有人闯入" : "闯入解除");
    else {
        unsigned a=(unsigned)farm_animal(e->class_id);
        if(e->type==FARM_MISSING_CLEAR)
            snprintf(text,size,"%s 走失解除",animals[a]);
        else
            snprintf(text,size,"%s 走失：少 %u %s",animals[a],e->amount,units[a]);
    }
}
