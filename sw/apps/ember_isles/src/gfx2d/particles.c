/* File: particles.c; art-plan 6.1, tech 2/5b. GPU advances Q8 positions and life.
 * CPU only emits, selects native animation frames and applies opacity/size curves.
 */
#include "gfx2d/particles.h"
#include "gfx2d/cache.h"
#include "sim/sim.h"
#include "plat.h"
#include "data.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static struct gpu_object *objects,*numbers;
static struct { uint16_t age,life; uint8_t kind,tier,type,digit; } metadata[EMBER_PARTICLES];
static unsigned end,number_count,visual_sequence,last_combat,have_combat;
static int signed24(uint32_t v) { return (int32_t)(v << 8) >> 8; }
static unsigned allocate(void)
{
    for (unsigned i=0;i<end;++i) if (!(objects[i].word[0]&EDRV32_GPU_OBJ_ALIVE_MASK)) return i;
    if (end==EMBER_PARTICLES) { plat_printf("GPU particle capacity exhausted\n");fflush(stdout);abort(); }
    return end++;
}
static unsigned variation(unsigned low,unsigned high)
{
    /* Independent presentation sequence: never reads or changes any sim RNG. */
    visual_sequence=visual_sequence*1664525u+1013904223u;
    return low+visual_sequence%(high-low+1);
}
static void emit(unsigned emitter,int x,int y,unsigned element)
{
    const struct ember_emitters_row *e=&ember_emitters[emitter];
    if (ember_art_find("coast_particles",e->effect,"down",0,1)<0) return;
    for (unsigned p=0;p<(unsigned)e->count;++p) {
        unsigned i=allocate(),life=variation((unsigned)e->life_min,(unsigned)e->life_max);
        unsigned direction=variation((unsigned)e->angle_min,(unsigned)e->angle_max);
        int speed=(int)variation((unsigned)e->speed_min,(unsigned)e->speed_max);
        int vx=(int)((int64_t)ember_cos((uint16_t)(direction*4096))*speed/EMBER_Q);
        int vy=-(int)((int64_t)ember_sin((uint16_t)(direction*4096))*speed/EMBER_Q);
        gpu_object(&objects[i],&(struct gpu_object_args){.alive=1,.life=life,
            .px=(uint32_t)(x*256),.py=(uint32_t)(y*256),.vx=(uint32_t)vx,.vy=(uint32_t)vy,
            .ay=(uint32_t)e->gravity,.w=1,.h=1,.alpha=255});
        metadata[i].age=0;metadata[i].life=(uint16_t)life;metadata[i].kind=(uint8_t)emitter;metadata[i].type=(uint8_t)element;
    }
}
static void damage(const struct ember_event *event)
{
    if (event->outcome==1 || !event->value) return;
    char text[16];snprintf(text,sizeof(text),"%u",(unsigned)event->value);
    unsigned width=event->tier?11:7,height=event->tier?20:12;
    int x=event->x/EMBER_Q-(int)strlen(text)*(int)width/2,y=event->y/EMBER_Q-24;
    for (unsigned p=0;text[p];++p) {
        unsigned i=allocate(),life=38+event->tier*6;
        gpu_object(&objects[i],&(struct gpu_object_args){.alive=1,.life=life,
            .px=(uint32_t)((x+(int)p*(int)width)*256),.py=(uint32_t)(y*256),.vy=(uint32_t)-160,
            .w=width,.h=height,.alpha=255});
        metadata[i].age=0;metadata[i].life=(uint16_t)life;metadata[i].kind=9;
        metadata[i].digit=(uint8_t)(text[p]-'0');metadata[i].tier=event->tier;metadata[i].type=event->damage_type;
    }
}
void ember_particles_init(void)
{
    objects=plat_dma_alloc(EMBER_PARTICLES*sizeof(*objects),32);
    numbers=plat_dma_alloc(EMBER_PARTICLES*sizeof(*numbers),32);
    memset(objects,0,EMBER_PARTICLES*sizeof(*objects));
    end=number_count=0;visual_sequence=1;have_combat=0;
}
void ember_particles_prepare(const struct ember_sim *s,unsigned advance,unsigned consume,ember_particle_draw draw)
{
    if (have_combat && s->combat_frame<last_combat) {
        memset(objects,0,EMBER_PARTICLES*sizeof(*objects));end=0;
    }
    int camera_x=s->player.x/EMBER_Q-320,camera_y=s->player.y/EMBER_Q-180;
    if (camera_x<0) camera_x=0;
    if (camera_y<0) camera_y=0;
    if (camera_x>s->world_width/EMBER_Q-640) camera_x=s->world_width/EMBER_Q-640;
    if (camera_y>s->world_height/EMBER_Q-360) camera_y=s->world_height/EMBER_Q-360;
    for (unsigned i=0;i<end;++i) {
        if (!(objects[i].word[0]&EDRV32_GPU_OBJ_ALIVE_MASK)) continue;
        if (advance && ++metadata[i].age>=metadata[i].life) objects[i].word[0]&=~EDRV32_GPU_OBJ_ALIVE_MASK;
    }
    if (consume) {
        for (unsigned i=0;i<s->events.count;++i) {
            const struct ember_event *e=&s->events.item[i];
            int x=e->x/EMBER_Q,y=e->y/EMBER_Q;
            if (x<camera_x-32 || x>camera_x+672 || y<camera_y-32 || y>camera_y+392) continue;
            if (e->kind==EMBER_EVENT_HIT) {
                damage(e);
                unsigned emitter=e->damage_type==EMBER_DAMAGE_FIRE?2:e->damage_type==EMBER_DAMAGE_WATER?3:
                    e->damage_type==EMBER_DAMAGE_STAR?5:e->damage_type==EMBER_DAMAGE_SHADOW?6:7;
                emit(emitter,x,y,e->damage_type);
                if (e->tier) emit(0,x,y,e->damage_type);
            } else if (e->kind==EMBER_EVENT_KILL) emit(8,x,y,0);
            else if (e->kind==EMBER_EVENT_SHOT || e->kind==EMBER_EVENT_SEED || e->kind==EMBER_EVENT_DASH) emit(2,x,y,1);
            else if (e->kind==EMBER_EVENT_PICKUP) emit(e->subtype==EMBER_PICKUP_EMBER?2:0,x,y,1);
            else if (e->kind==EMBER_EVENT_WEAPON_CHANGE || e->kind==EMBER_EVENT_ULTIMATE) emit(5,x,y,3);
        }
        if (advance && s->combat_frame%12==0) for (unsigned p=0;p<s->pillar_count;++p) if (s->pillars[p].lit) {
            int x=s->pillars[p].x/EMBER_Q,y=s->pillars[p].y/EMBER_Q;
            if (x>=camera_x-32 && x<=camera_x+672 && y>=camera_y-32 && y<=camera_y+392) emit(1,x,y-36,1);
        }
    }
    if (advance && s->combat_frame%12==0) for (unsigned i=0;i<EMBER_ENEMIES;++i) {
        const struct ember_enemy *e=&s->enemies[i];
        if (e->alive && e->defense.frozen && e->x/EMBER_Q>=camera_x && e->x/EMBER_Q<camera_x+640 &&
            e->y/EMBER_Q>=camera_y && e->y/EMBER_Q<camera_y+360) emit(4,e->x/EMBER_Q,e->y/EMBER_Q,2);
    }
    number_count=0;
    for (unsigned i=0;i<end;++i) {
        if (!(objects[i].word[0]&EDRV32_GPU_OBJ_ALIVE_MASK)) continue;
        int x=signed24(objects[i].word[EDRV32_GPU_OBJ_PX_OFFSET/4]&EDRV32_GPU_OBJ_PX_MASK)/256;
        int y=signed24(objects[i].word[EDRV32_GPU_OBJ_PY_OFFSET/4]&EDRV32_GPU_OBJ_PY_MASK)/256;
        unsigned age=metadata[i].age,life=metadata[i].life;
        if (metadata[i].kind<9) {
            const struct ember_emitters_row *e=&ember_emitters[metadata[i].kind];
            int id=ember_art_find("coast_particles",e->effect,"down",age,4);
            unsigned scale=(unsigned)(e->scale_start+(e->scale_end-e->scale_start)*(int)age/(int)life);
            unsigned alpha=(unsigned)(e->alpha_start+(e->alpha_end-e->alpha_start)*(int)age/(int)life);
            draw(id,x,y,scale,alpha,(unsigned)e->blend,metadata[i].type);
        } else {
            struct gpu_object object=objects[i];
            object.word[EDRV32_GPU_OBJ_PX_OFFSET/4]=(uint32_t)((x-camera_x)*256)&EDRV32_GPU_OBJ_PX_MASK;
            object.word[EDRV32_GPU_OBJ_PY_OFFSET/4]=(uint32_t)((y-camera_y)*256)&EDRV32_GPU_OBJ_PY_MASK;
            unsigned palette=metadata[i].tier>=2?12:metadata[i].type+(metadata[i].tier?6:0);
            object.word[EDRV32_GPU_OBJ_PAL_GROUP_OFFSET/4]&=~EDRV32_GPU_OBJ_PAL_GROUP_MASK;
            object.word[EDRV32_GPU_OBJ_PAL_GROUP_OFFSET/4]|=palette<<EDRV32_GPU_OBJ_PAL_GROUP_POS;
            object.word[EDRV32_GPU_OBJ_U0_OFFSET/4]&=~(EDRV32_GPU_OBJ_U0_MASK|EDRV32_GPU_OBJ_V0_MASK);
            object.word[EDRV32_GPU_OBJ_U0_OFFSET/4]|=(metadata[i].digit*12u)<<EDRV32_GPU_OBJ_U0_POS;
            object.word[EDRV32_GPU_OBJ_V0_OFFSET/4]|=(metadata[i].tier?12u:0u)<<EDRV32_GPU_OBJ_V0_POS;
            object.word[EDRV32_GPU_OBJ_ALPHA_OFFSET/4]&=~EDRV32_GPU_OBJ_ALPHA_MASK;
            object.word[EDRV32_GPU_OBJ_ALPHA_OFFSET/4]|=(255u*(life-age)/life)<<EDRV32_GPU_OBJ_ALPHA_POS;
            numbers[number_count++]=object;
        }
    }
    last_combat=s->combat_frame;have_combat=1;
}
unsigned ember_particles_commands(struct gpu_command *commands,unsigned advance)
{
    if (!end) return 0;
    gpu_obj_step(commands,&(struct gpu_obj_step_args){.step=advance,.addr=gpu_physical(objects),.count=end});
    return 1;
}
unsigned ember_particles_numbers(struct gpu_command *commands,unsigned stripe)
{
    (void)stripe;
    if (!number_count) return 0;
    gpu_obj_step(commands,&(struct gpu_obj_step_args){.draw=1,.addr=gpu_physical(numbers),.count=number_count});
    return 1;
}
struct gpu_range ember_particles_source(void) { return (struct gpu_range){(uintptr_t)objects,end*sizeof(*objects)}; }
struct gpu_range ember_particles_result(void) { return (struct gpu_range){(uintptr_t)objects,end*sizeof(*objects)}; }
struct gpu_range ember_numbers_source(void) { return (struct gpu_range){(uintptr_t)numbers,number_count*sizeof(*numbers)}; }
unsigned ember_particles_alive(void)
{
    unsigned alive=0;
    for (unsigned i=0;i<end;++i) if (metadata[i].kind<9 && (objects[i].word[0]&EDRV32_GPU_OBJ_ALIVE_MASK)) ++alive;
    return alive;
}
unsigned ember_numbers_alive(void) { return number_count; }
