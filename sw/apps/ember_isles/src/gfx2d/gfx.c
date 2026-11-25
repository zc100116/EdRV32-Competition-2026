/* File: gfx.c; tech 2/4/5b. Read-only native ART rendering and GPU submission.
 * CPU prepares DMA records; GPU owns object movement, lifetime and rasterization.
 */
#include "gfx2d/gfx.h"
#include "gfx2d/cache.h"
#include "gfx2d/particles.h"
#include "ui/ui.h"
#include "plat.h"
#include "disp.h"
#include "mmio.h"
#include "regs/disp_gpu_regs.h"
#include "data.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
enum { DRAWS = EMBER_PARTICLES + EMBER_ENEMIES + EMBER_SHOTS + 1024, COMMANDS = 131072 };
struct draw { uint16_t id,scale,palette; int16_t x,y; uint8_t mirror,flash,dim,angle,alpha,additive,mode,particle;
    uint8_t hero_facing,projectile,shot_dir;
    int16_t corners[4][2];
    uint16_t span_w,span_h; };
static struct draw draws[DRAWS];
static unsigned quad_index[DRAWS];
static unsigned quad_count;
static struct gpu_command *commands;
static struct gpu_quad *quads;
static struct gpu_vertex *vertices;
static struct ember_ui_canvas canvas;
static uint32_t *palettes;
static uint16_t *surface[2];
static int32_t *matrix;
static unsigned world_draws,terrain_count;
static unsigned draw_count, command_count, resolve_command[2], last_stage;
static unsigned last_frame, last_combat, have_frame;
static uint32_t *released;
static unsigned advance,consume,particle_visible;
static uint8_t prior_lit[8];
static unsigned lamp_started[8];
static int camera_x,camera_y;
static uint32_t perf[16], raw_perf[16];
static const char *directions[] = {"down","down_right","right","up_right","up"};
static const char *coast_enemies[] = {"tide_biter","salt_charger","drowned_watcher","reef_crab","mist_jellyfish"};
static int visible(int x, int y, int radius)
{
    return x + radius >= 0 && x - radius < 640 && y + radius >= 0 && y - radius < 360;
}
static void draw(int id, int x, int y, unsigned scale, unsigned mirror, unsigned flash, unsigned dim)
{
    if (id < 0) return; /* Unproduced art is omitted, never replaced with a placeholder. */
    const struct ember_art_frame *f = ember_art_frame((unsigned)id);
    if (!visible(x, y, (int)(f->w + f->h) * (int)scale / 100)) return;
    if (draw_count == DRAWS) { plat_printf("Scene draw capacity exhausted\n"); fflush(stdout);abort(); }
    draws[draw_count++] = (struct draw){.id=(uint16_t)id,.scale=(uint16_t)scale,.palette=f->palette,
        .x=(int16_t)x,.y=(int16_t)y,.mirror=(uint8_t)mirror,.flash=(uint8_t)flash,.dim=(uint8_t)dim,.alpha=f->global_alpha};
}
static int frame(const char *actor,const char *action,unsigned facing,unsigned tick,unsigned period)
{
    return ember_art_find(actor,action,directions[facing],tick,period);
}
static unsigned ground_type(int x,int y,const struct ember_sim *s)
{
    int w = s->world_width / EMBER_Q / 32, h = (s->world_height / EMBER_Q + 31) / 32;
    if (x < 1 || y < 1 || x >= w - 1 || y >= h - 1) return 1;
    if (x < 3 || y < 3 || x >= w - 3 || y >= h - 3) return 2;
    if (x >= w / 2 - 1 && x <= w / 2 + 1) return 3;
    if (y >= h / 2 - 1 && y <= h / 2 + 1) return 3;
    if ((x / 9 + y / 7) % 5 == 0) return 4;
    return 0;
}
static void coast(const struct ember_sim *s)
{
    static const char *terrain[] = {"terrain_sand","terrain_shallow","terrain_reef","terrain_ruins","terrain_grass"};
    static const int dx[] = {0,1,0,-1},dy[] = {-1,0,1,0};
    for (int y = camera_y / 32; y <= (camera_y + 360) / 32; ++y)
        for (int x = camera_x / 32; x <= (camera_x + 640) / 32; ++x) {
            unsigned type = ground_type(x,y,s), mask = 0;
            for (unsigned i = 0; i < 4; ++i) if (ground_type(x+dx[i],y+dy[i],s) == type) mask |= 1u << i;
            int id = ember_art_find(terrain[type],mask == 15 ? "variation" : "autotile","down",
                mask == 15 ? (unsigned)(x * 17 + y * 31) % 4 : mask,1);
            draw(id,x*32+16-camera_x,y*32+16-camera_y,100,0,0,0);
        }
    terrain_count=draw_count;
    for (unsigned i = 0; i < s->obstacle_count; ++i) {
        const struct ember_obstacle *o = &s->obstacles[i];
        draw(frame("coast_props",i % 2 ? "rock" : "ruined_wall",0,0,1),
            o->x / EMBER_Q-camera_x,o->y / EMBER_Q-camera_y,100,0,0,0);
    }
    if (!have_frame || s->combat_frame<last_combat) memset(prior_lit,0,sizeof(prior_lit));
    for (unsigned i=0;i<s->pillar_count;++i) {
        if (s->pillars[i].lit && !prior_lit[i]) lamp_started[i]=s->combat_frame;
        unsigned age=s->combat_frame-lamp_started[i];
        const char *action=!s->pillars[i].lit?"lamp_off":age<24?"lamp_ignite":"lamp_lit";
        draw(frame("coast_landmarks",action,0,s->pillars[i].lit && age<24?age:s->combat_frame,
             s->pillars[i].lit && age<24?4:8),s->pillars[i].x/EMBER_Q-camera_x,s->pillars[i].y/EMBER_Q-camera_y,100,0,0,0);
        if (s->pillars[i].lit && age<24)
            draw(frame("coast_large_fx","lamp_ignite_halo",0,age,4),
                s->pillars[i].x/EMBER_Q-camera_x,s->pillars[i].y/EMBER_Q-camera_y,100,0,0,0);
        prior_lit[i]=s->pillars[i].lit;
    }
    if (s->shop_available) draw(frame("coast_landmarks",s->panel==EMBER_PANEL_SHOP?"merchant_barter":"merchant",0,s->combat_frame,8),
        s->merchant.x/EMBER_Q-camera_x,s->merchant.y/EMBER_Q-camera_y,100,0,0,0);
    if (s->altars_available) draw(frame("coast_landmarks","altar",0,s->combat_frame,8),
        s->altar.x/EMBER_Q-camera_x,s->altar.y/EMBER_Q-camera_y,100,0,0,0);

}
static int scene_point_lit(const struct ember_sim *s,ember_fixed x,ember_fixed y)
{
    int64_t radius=(int64_t)ember_lighting[0].pillar_radius*EMBER_Q;
    for (unsigned i=0;i<s->pillar_count;++i) if (s->pillars[i].lit) {
        int64_t dx=(int64_t)x-s->pillars[i].x,dy=(int64_t)y-s->pillars[i].y;
        if (dx*dx+dy*dy<=radius*radius) return 1;
    }
    if (s->player.relic_level[EMBER_DATA_RELICS_EMBER_LAMP]) {
        radius=(int64_t)ember_relics[EMBER_DATA_RELICS_EMBER_LAMP].value2*EMBER_Q;
        for (unsigned i=0;i<EMBER_ENEMIES;++i) if (s->enemies[i].alive && s->enemies[i].burn) {
            int64_t dx=(int64_t)x-s->enemies[i].x,dy=(int64_t)y-s->enemies[i].y;
            if (dx*dx+dy*dy<=radius*radius) return 1;
        }
    }
    return 0;
}
static struct {
    struct ember_pickup previous;
    int icon,x,y;
    uint8_t age,flying;
} pickup_visual[EMBER_PICKUPS];
static int pickup_icon(const struct ember_pickup *p)
{
    const char *action=NULL;
    switch (p->kind) {
    case EMBER_DROP_XP: action="xp";break;
    case EMBER_DROP_GOLD: action="gold";break;
    case EMBER_DROP_EMBER: action="ember";break;
    case EMBER_DROP_RELIC: action=ember_relics[p->id].id;break;
    case EMBER_DROP_WEAPON: case EMBER_DROP_PET_WEAPON:
        action=p->id==2?"sword_ember":"staff_ember";break;
    case EMBER_DROP_INSCRIPTION: action=ember_inscriptions[p->id].id;break;
    }
    return action?frame("coast_ui_icons",action,0,0,1):-1;
}
static void pickups(const struct ember_sim *s)
{
    if (!have_frame || s->combat_frame<last_combat) memset(pickup_visual,0,sizeof(pickup_visual));
    unsigned collected=0;
    for (unsigned e=0;e<s->events.count;++e) collected|=s->events.item[e].kind==EMBER_EVENT_PICKUP;
    for (unsigned i=0;i<EMBER_PICKUPS;++i) {
        const struct ember_pickup *p=&s->pickups[i],*previous=&pickup_visual[i].previous;
        if (consume && collected && previous->alive && !p->alive && previous->room==s->room_serial) {
            pickup_visual[i].icon=pickup_icon(previous);
            pickup_visual[i].x=previous->x/EMBER_Q;pickup_visual[i].y=previous->y/EMBER_Q;
            pickup_visual[i].age=0;pickup_visual[i].flying=1;
        }
        if (p->alive && p->room==s->room_serial) {
            int bob=ember_sin((uint16_t)(s->combat_frame*900+i*7000))*2/EMBER_Q;
            draw(pickup_icon(p),p->x/EMBER_Q-camera_x,p->y/EMBER_Q-camera_y+bob,100,0,
                (s->combat_frame+i*7)%60<4,0);
        }
        if (pickup_visual[i].flying) {
            unsigned age=pickup_visual[i].age;
            int x=pickup_visual[i].x+(s->player.x/EMBER_Q-pickup_visual[i].x)*(int)age/12;
            int y=pickup_visual[i].y+(s->player.y/EMBER_Q-pickup_visual[i].y)*(int)age/12;
            draw(pickup_visual[i].icon,x-camera_x,y-camera_y,100,0,0,0);
            if (advance && ++pickup_visual[i].age>=12) pickup_visual[i].flying=0;
        }
        if (consume && (p->alive || previous->alive)) pickup_visual[i].previous=*p;
    }
}
static void entities(const struct ember_sim *s)
{
    for (unsigned i = 0; i < EMBER_ENEMIES; ++i) {
        const struct ember_enemy *e = &s->enemies[i];
        if (!e->alive) {
            if (e->presentation_action==EMBER_ENEMY_DEATH && e->action_ticks<(ember_enemies[e->kind].rank>=2?24u:8u)) {
                if (e->kind<5) draw(frame(coast_enemies[e->kind],"death",EMBER_FPGA_ART?0:e->facing_frame,e->action_ticks/4,1),
                    e->x/EMBER_Q-camera_x,e->y/EMBER_Q-camera_y,100,e->flip_x,0,!scene_point_lit(s,e->x,e->y));
                else if (ember_enemies[e->kind].rank==2)
                    draw(ember_art_timed("lighthouse_guardian_body","death",directions[e->facing_frame],e->action_ticks,24),
                        e->x/EMBER_Q-camera_x,e->y/EMBER_Q-camera_y,100,e->flip_x,0,!scene_point_lit(s,e->x,e->y));
                else if (ember_enemies[e->kind].rank==3)
                    draw(ember_art_timed("tide_lord_body","death","down",e->action_ticks,24),
                        e->x/EMBER_Q-camera_x,e->y/EMBER_Q-camera_y,100,0,0,!scene_point_lit(s,e->x,e->y));
            }
            continue;
        }
        int x=e->x/EMBER_Q-camera_x,y=e->y/EMBER_Q-camera_y;
        if (!visible(x,y,192)) continue;
        unsigned dark=!scene_point_lit(s,e->x,e->y);
        unsigned facing=e->facing_frame,mirror=e->flip_x;
        unsigned rank=(unsigned)ember_enemies[e->kind].rank;
        const char *actor=e->kind<5 ? coast_enemies[e->kind] : rank==2 ? "lighthouse_guardian_body" : "tide_lord_body";
        static const char *ordinary_actions[]={"idle","walk","hit","death","attack","attack","idle"};
        const char *action=e->presentation_action<7?ordinary_actions[e->presentation_action]:"attack";
        unsigned tick=rank>=2 || e->affix?e->action_ticks:s->combat_frame;
        unsigned attacking=e->presentation_action>=EMBER_ENEMY_ATTACK && e->presentation_action!=EMBER_ENEMY_SHIELD && e->presentation_action!=EMBER_ENEMY_TIDE_EBB;
#if EMBER_FPGA_ART
        /* tech 5b, coordinator-frozen subset map: coast mobile species retain
         * walk+attack; idle/stationary hit uses walk frame 0. Moving hit shares
         * the species walk clock and flashes white. Stationary species retain
         * idle+attack and map walk/hit back to idle. PC uses native idle/hit.
         */
        unsigned stationary=ember_enemies[e->kind].ai==9 || ember_enemies[e->kind].ai==16;
        if (!rank && (e->presentation_action==EMBER_ENEMY_IDLE || e->presentation_action==EMBER_ENEMY_HIT ||
            e->presentation_action==EMBER_ENEMY_WALK)) {
            action=stationary?"idle":"walk";
            if (!(e->vx || e->vy)) tick=0;
        }
#endif
        if (e->kind == 4) {
            facing=0;
            if (!strcmp(action,"walk") && e->vx) {
                int id=ember_art_find(actor,"walk","lean_right",tick,6);
                draw(id,x,y,e->affix?125:100,e->vx<0,e->flash!=0,dark);
                goto enemy_aura;
            }
        }
        if (rank==2) action=e->presentation_action==EMBER_ENEMY_HIT?"hit":
            e->presentation_action==EMBER_ENEMY_SUMMON?"summon":attacking?"attack_shield":e->vx || e->vy?"walk":"idle";
        char boss_action[32];
        if (rank==3) {
            snprintf(boss_action,sizeof(boss_action),"phase%u_%s",e->stage+1,e->presentation_action==EMBER_ENEMY_HIT?"hit":attacking?"attack":"idle");
            action=boss_action; facing=0; mirror=0;
            draw(frame("tide_lord_tail",e->presentation_action==EMBER_ENEMY_TIDE_SWEEP_COLUMN?"tail_sweep":"idle",0,tick,6),x,y,100,0,0,dark);
            draw(frame("tide_lord_fin",attacking?"attack":e->stage==2?"phase3_idle":"idle",0,tick,6),x,y,100,0,0,dark);
        }
        int body=(rank>=2 || e->affix) && (attacking || e->presentation_action==EMBER_ENEMY_HIT)?
            ember_art_timed(actor,action,directions[facing],tick,e->presentation_action==EMBER_ENEMY_HIT?
                (unsigned)ember_system[0].enemy_flash_frames:(unsigned)ember_system[0].attack_frames):frame(actor,action,facing,tick,6);
        draw(body,x,y,e->affix && !rank?125:100,mirror,e->flash!=0,dark);
        enemy_aura:;
        unsigned affixes[]={e->affix,e->second_affix};
        for (unsigned a=0;a<2;++a) if (affixes[a]) {
            char aura[64];snprintf(aura,sizeof(aura),"elite_aura_%s",ember_affixes[affixes[a]-1].id);
            unsigned before=draw_count;
            draw(frame("coast_small_fx",aura,0,s->combat_frame,6),x,y,100,0,0,0);
            if (affixes[a]==7 && before!=draw_count)
                draws[draw_count-1].palette=ember_art_frame(draws[draw_count-1].id)->variants[ember_enemies[e->kind].element_index];
        }
        if (rank==2) {
            draw(frame("lighthouse_guardian_shield",attacking?"attack_shield":e->defense.front_block || e->defense.active_block?"guard":"idle",facing,tick,6),x,y,100,mirror,e->flash!=0,dark);
            draw(frame("lighthouse_guardian_weapon",attacking?"attack_shield":"idle",facing,tick,6),x,y,100,mirror,e->flash!=0,dark);
        }
        if (rank==3) {
            if (e->presentation_action==EMBER_ENEMY_TIDE_BLACKTIDE && e->action_ticks<24)
                draw(frame("coast_large_fx","boss_blacktide_surge",0,e->action_ticks,4),x,y,100,0,0,0);
            snprintf(boss_action,sizeof(boss_action),"phase%u_idle",e->stage+1);
            draw(frame("tide_lord_mouth",attacking?(e->stage==0?"water_column":e->stage==1?"vortex":"blacktide_roar"):boss_action,0,tick,6),x,y,100,0,e->flash!=0,dark);
            draw(frame("tide_lord_fin",attacking?"attack":e->stage==2?"phase3_idle":"idle",0,tick,6),x,y,100,1,0,dark);
        }
    }
    if (s->phase != EMBER_MENU) {
        const struct ember_player *p=&s->player;
        static const char *actions[]={"idle","walk","dash","hit","death","interact","skill_l","attack_spell","attack_spell"};
        const char *action=actions[p->action];
        if (p->action==EMBER_DASHING && s->flame_dash) action="skill_k";
        if (p->action==EMBER_CAST) {
            static const char *skills[]={"skill_k","skill_l","skill_u"};
            action=skills[p->cast_skill];
        }
        if (p->action==EMBER_ATTACKING && p->main_weapon==2) action="attack_slash";
        int id=p->action==EMBER_IDLE || p->action==EMBER_MOVE?
            frame("keeper",action,p->facing_frame,p->action_ticks,6):
            ember_art_timed("keeper",action,directions[p->facing_frame],p->action_ticks,p->action_time?p->action_time+p->action_ticks:0);
        if (p->action==EMBER_ATTACKING && p->main_weapon==2) {
            unsigned duration=p->action_ticks+p->action_time;
            id=frame("keeper","attack_slash",p->facing_frame,((p->combo+2)%3)*4+p->action_ticks*4/duration,1);
        }
        if (p->action==EMBER_CHARGING) id=frame("keeper","attack_spell",p->facing_frame,3,1);
        if (p->action==EMBER_ATTACKING && p->main_weapon==0) {
            /* Keeper's staff affinity adds its native finish pose. The charged
             * branch releases from the second half of the spell animation. */
            unsigned duration=p->action_ticks+p->action_time;
            unsigned release=p->evolution[0]==2?duration/2:duration*2/3;
            if (p->action_ticks<release) {
                unsigned first=p->evolution[0]==2?4:0,count=p->evolution[0]==2?4:8;
                id=frame("keeper","attack_spell",p->facing_frame,first+p->action_ticks*count/(release?release:1),1);
            } else id=ember_art_timed("keeper","finish_staff",directions[p->facing_frame],
                p->action_ticks-release,duration-release);
        }
        int x=p->x/EMBER_Q-camera_x,y=p->y/EMBER_Q-camera_y;
        unsigned before=draw_count;
        draw(id,x,y,100,p->flip_x,p->flash!=0,!s->in_light);
        if (draw_count!=before) draws[draw_count-1].hero_facing=(uint8_t)(1u<<p->facing8);
        if (id>=0) {
            const struct ember_art_frame *f=ember_art_frame((unsigned)id);
            if (f->hx!=-32768) {
                int hx=x+(p->flip_x?f->ax-f->hx:f->hx-f->ax),hy=y+f->hy-f->ay;
                const char *evolution=p->evolution[p->main_weapon]==1?"evolution_a":p->evolution[p->main_weapon]==2?"evolution_b":"base";
                draw(frame(p->main_weapon==2?"weapon_sword":"weapon_staff",evolution,p->facing_frame,0,1),hx,hy,100,p->flip_x,p->flash!=0,!s->in_light);
            }
        }
    }
}
void ember_gfx_init(void)
{
    ember_cache_init();
    ember_particles_init();
    released=plat_dma_alloc(EMBER_PARTICLES*sizeof(*released),32);
    commands=plat_dma_alloc(COMMANDS*sizeof(*commands),64);
    quads=plat_dma_alloc(DRAWS*2*sizeof(*quads),32);
    vertices=plat_dma_alloc(DRAWS*6*sizeof(*vertices),32);
    canvas.rects=plat_dma_alloc(EMBER_UI_RECTS*sizeof(*canvas.rects),32);
    canvas.glyphs=plat_dma_alloc(EMBER_UI_GLYPHS*sizeof(*canvas.glyphs),32);
    matrix=plat_dma_alloc(64,32);
    unsigned count=ember_cache_palette_count();
    palettes=plat_dma_alloc((count*3+30)*1024,32);
    for (unsigned i=0;i<count;++i) {
        const uint32_t *source=ember_cache_palette(i);
        for (unsigned j=0;j<256;++j) {
            uint32_t v=source[j];
            palettes[i*256+j]=v;
            palettes[(count+i)*256+j]=(v & 0xf0000)|65535;
            unsigned r=(v>>11&31)*3/4,g=(v>>5&63)*3/4,b=(v&31)*3/4;
            palettes[(count*2+i)*256+j]=(v&0xf0000)|(r<<11)|(g<<5)|b;
        }
    }
    static const uint16_t colors[]={0xffec,0xbdd7,0x1084,0x5acd,0xfbc7,0x6e5b,0xff7b,0xeb49,0x18a5,0x0001,0xa6df,0xa37b};
    for (unsigned p=0;p<16;++p) for (unsigned i=0;i<256;++i)
        palettes[(count*3+p)*256+i]=p<12 ? (0xf0000|colors[p]) :
            i & (1u<<(p-12)) ? 0xfffff : 0;
    static const uint16_t damage_colors[]={0xffff,0xfbc7,0x4e9e,0x9e3f,0xb57f,0xffed};
    for (unsigned p=0;p<13;++p) for (unsigned i=0;i<256;++i) {
        uint16_t color=p==12?0xff20:damage_colors[p%6];
        if (p>=6 && p<12) color|=0x4228;
        palettes[(count*3+16+p)*256+i]=i&1 ? (0xf0000|color):i&2?0xf0000:0;
    }
    int view=frame("coast_light","lantern_view",0,0,1);
    if (view>=0) for (unsigned i=0;i<256;++i) palettes[(count*3+29)*256+i]=ember_art_corner((unsigned)view);
    memset(matrix,0,64);matrix[0]=205;matrix[5]=364;matrix[10]=matrix[15]=65536;
    surface[0]=plat_dma_alloc(640*360*2,4096);surface[1]=plat_dma_alloc(640*360*2,4096);
    have_frame=0;
    memset(perf,0,sizeof(perf));memset(raw_perf,0,sizeof(raw_perf));
}
static void draw_direction(int id,int x,int y,unsigned dir16,unsigned alpha)
{
    unsigned before=draw_count;
    draw(id,x,y,100,0,0,0);
    if (draw_count!=before) {
        draws[draw_count-1].angle=(uint8_t)((dir16+16-ember_art_frame((unsigned)id)->source_dir16)&15);
        draws[draw_count-1].alpha=(uint8_t)alpha;
    }
}
enum { TRANSIENT_EFFECTS=EMBER_EVENTS*32 };
static struct { const char *action; int x,y; unsigned age; uint8_t alive,large; } transient[TRANSIENT_EFFECTS];
static void transient_start(const char *action,int x,int y,unsigned large)
{
    if (frame(large?"coast_large_fx":"coast_small_fx",action,0,0,1)<0) return;
    for (unsigned i=0;i<TRANSIENT_EFFECTS;++i) if (!transient[i].alive) {
        transient[i].action=action;transient[i].x=x;transient[i].y=y;
        transient[i].age=0;transient[i].alive=1;transient[i].large=(uint8_t)large;
        return;
    }
    plat_printf("Transient effect capacity exhausted\n");fflush(stdout);abort();
}
static void friendly_projectile(int id,int x,int y,unsigned dir16,unsigned alpha)
{
    unsigned before=draw_count;
    draw_direction(id,x,y,dir16,alpha);
    if (draw_count!=before) { draws[draw_count-1].projectile=1;draws[draw_count-1].shot_dir=(uint8_t)dir16; }
}
static void effects(const struct ember_sim *s)
{
    if (have_frame && s->combat_frame<last_combat) memset(transient,0,sizeof(transient));
    if (consume) for (unsigned i=0;i<s->events.count;++i) {
        const struct ember_event *e=&s->events.item[i];
        const char *action=NULL;
        if (e->kind==EMBER_EVENT_HIT && e->outcome!=1) action=e->damage_type==EMBER_DAMAGE_FIRE?"impact_ember":
            e->damage_type==EMBER_DAMAGE_WATER?"impact_tide":e->damage_type==EMBER_DAMAGE_SHADOW?"impact_shadow":"impact_iron";
        else if (e->kind==EMBER_EVENT_KILL) action="kill_burst";
        if (action) transient_start(action,e->x/EMBER_Q,e->y/EMBER_Q,0);
        if (e->kind==EMBER_EVENT_HIT && e->outcome!=1 && e->source_evolution) {
            const char *signature=e->source_weapon==2?(e->source_evolution==1?"sword_whirl_impact":"sword_rift_impact"):
                e->source_weapon==0?(e->source_evolution==1?"staff_cluster_impact":"staff_core_blast"):NULL;
            if (signature) transient_start(signature,e->x/EMBER_Q,e->y/EMBER_Q,1);
        }
        if (e->kind==EMBER_EVENT_HURT && s->phase==EMBER_LOST) transient_start("kill_burst",e->x/EMBER_Q,e->y/EMBER_Q,0);
        if (e->kind==EMBER_EVENT_DASH && s->flame_dash) transient_start("keeper_dash_launch",e->x/EMBER_Q,e->y/EMBER_Q,1);
        if (e->kind==EMBER_EVENT_ULTIMATE) transient_start("keeper_furnace_eruption",e->x/EMBER_Q,e->y/EMBER_Q,1);
        if (e->kind==EMBER_EVENT_HIT && e->tier) transient_start("critical",e->x/EMBER_Q,e->y/EMBER_Q,0);
    }
    for (unsigned i=0;i<TRANSIENT_EFFECTS;++i) {
        if (!transient[i].alive) continue;
        if (advance && ++transient[i].age>=24) { transient[i].alive=0;continue; }
        draw(frame(transient[i].large?"coast_large_fx":"coast_small_fx",transient[i].action,0,transient[i].age,4),
            transient[i].x-camera_x,transient[i].y-camera_y,100,0,0,0);
    }
    for (unsigned i=0;i<EMBER_SHOTS;++i) {
        const struct ember_shot *p=&s->shots[i];
        if (!p->alive) continue;
        int x=p->x/EMBER_Q-camera_x,y=(p->y-p->z)/EMBER_Q-camera_y;
        if (!visible(x,y,96)) continue;
        if (p->hostile && (p->kind==6 || p->kind==0)) {
            const char *action=p->enemy_kind<EMBER_ENEMIES_COUNT && ember_enemies[p->enemy_kind].rank>=2?
                "hostile_tide_orb":"hostile_tide_projectile";
            int projectile=ember_art_find("coast_small_fx",action,"right",s->combat_frame,3);
            for (unsigned t=3;t>0;--t)
                draw_direction(projectile,x-(p->x-p->previous_x)/EMBER_Q*(int)t,
                    y-(p->y-p->previous_y)/EMBER_Q*(int)t,p->dir16,200-t*45);
            draw_direction(projectile,x,y,p->dir16,255);
        } else if (p->kind==2 && p->effect==7) {
            unsigned age=p->delay?(unsigned)ember_enemies[p->enemy_kind].charge_frames-p->delay:
                (unsigned)ember_enemies[p->enemy_kind].wave_life-p->life;
            draw(ember_art_phase("coast_small_fx","hostile_tide_column",p->delay?1:2,age,4),x,y,100,0,0,0);
        } else if (p->kind==2 && p->effect==8) {
            draw(frame("coast_large_fx","boss_vortex",0,s->combat_frame,4),x,y,100,0,0,0);
        } else if (p->kind==1 && p->trigger_radius) {
            draw(frame("coast_large_fx","fire_seed_explosion",0,(unsigned)ember_weapons[1].area_frames-p->life,2),x,y,100,0,0,0);
        } else if (p->kind==2 && !p->effect && p->weapon==255) {
            draw(frame("coast_large_fx","keeper_dash_trail",0,s->combat_frame,4),x,y,100,0,0,0);
        } else if (p->kind==4) draw(frame("fire_seed","idle",0,s->combat_frame,6),x,y,100,0,0,0);
        else if (p->weapon==0 && !p->hostile) {
            static const char *projectiles[]={"staff_projectile","staff_cluster_projectile","staff_core_projectile"};
            int projectile=frame("coast_small_fx",projectiles[p->presentation_evolution],0,s->combat_frame,3);
            int trail=projectile;
            for (unsigned t=3;t>0;--t)
                friendly_projectile(trail,x-(p->x-p->previous_x)/EMBER_Q*(int)t,
                    y-(p->y-p->previous_y)/EMBER_Q*(int)t,p->dir16,200-t*45);
            friendly_projectile(projectile,x,y,p->dir16,255);
        }
        /* Hostile projectile/ground layers require their authored resources. */
    }
    const struct ember_player *p=&s->player;
    int x=p->x/EMBER_Q-camera_x,y=p->y/EMBER_Q-camera_y-24;
    unsigned dir=(p->facing8*2+12)&15;
    if (p->action==EMBER_CHARGING && p->main_weapon==0 && p->evolution[0]==2)
        draw_direction(frame("coast_large_fx","staff_core_charge",0,p->action_ticks,4),x,y,dir,255);
    if (p->action==EMBER_ATTACKING) {
        const char *action=p->main_weapon==2?"sword_trail":"staff_cast";
        draw_direction(frame("coast_small_fx",action,0,p->action_ticks,2),x,y,dir,255);
        unsigned evolution=p->evolution[p->main_weapon];
        if (evolution && (p->main_weapon==2?p->combo==0:evolution==1)) {
            const char *release=p->main_weapon==2?(evolution==1?"sword_whirl_release":"sword_rift_release"):
                evolution==1?"staff_cluster_cast":"staff_core_charge";
            draw_direction(frame("coast_large_fx",release,0,p->action_ticks,2),x,y,dir,255);
        }
    }

}
static const char *item_icon(const struct ember_choice *c)
{
    if (c->kind==EMBER_ITEM_WEAPON || c->kind==EMBER_ITEM_EVOLUTION)
        return (c->kind==EMBER_ITEM_WEAPON?c->id:c->slot)==2?"sword_ember":"staff_ember";
    if (c->kind==EMBER_ITEM_RELIC) return ember_relics[c->id].id;
    if (c->kind==EMBER_ITEM_INSCRIPTION) return ember_inscriptions[c->id].id;
    if (c->kind==EMBER_ITEM_BLESSING) return ember_blessings[c->id].id;
    if (c->kind==EMBER_ITEM_RESOURCE) return ember_upgrade_fillers[c->id].id;
    return NULL;
}
static void ui_border(int left,int top,unsigned width,unsigned height,const char *rarity)
{
    int first=frame("coast_card_borders",rarity,0,0,1);
    if (first<0) return;
    for (int x=left+8;x<left+(int)width-8;x+=8) {
        const struct ember_art_frame *a=ember_art_frame((unsigned)first+4),*b=ember_art_frame((unsigned)first+6);
        draw(first+4,x+a->ax,top+a->ay,100,0,0,0);
        draw(first+6,x+b->ax,top+(int)height-4+b->ay,100,0,0,0);
    }
    for (int y=top+8;y<top+(int)height-8;y+=8) {
        const struct ember_art_frame *a=ember_art_frame((unsigned)first+5),*b=ember_art_frame((unsigned)first+7);
        draw(first+5,left+(int)width-4+a->ax,y+a->ay,100,0,0,0);
        draw(first+7,left+b->ax,y+b->ay,100,0,0,0);
    }
    draw(first,left,top,100,0,0,0);draw(first+1,left+(int)width-8,top,100,0,0,0);
    draw(first+2,left,top+(int)height-8,100,0,0,0);
    draw(first+3,left+(int)width-8,top+(int)height-8,100,0,0,0);
}
static void ui_art(const struct ember_sim *s,const struct ember_ui_state *ui)
{
    if (s->phase==EMBER_MENU) ui_border(112,54,416,250,"common");
    else if (s->phase==EMBER_WON || s->phase==EMBER_LOST) ui_border(128,86,384,202,"common");
    if (s->panel) ui_border(40,76,560,240,"common");
    else if (s->paused) ui_border(192,135,256,86,"common");
    if (s->phase==EMBER_MENU && ui->menu_page==EMBER_WEAPON_MENU) {
        draw(frame("coast_ui_icons","sword_ember",0,0,1),174,204,100,0,0,0);
        draw(frame("coast_ui_icons","staff_ember",0,0,1),354,204,100,0,0,0);
    }
    if (s->phase!=EMBER_MENU) {
        draw(frame("coast_ui_icons",s->player.main_weapon==2?"sword_ember":"staff_ember",0,0,1),24,310,100,0,0,0);
        draw(frame("coast_ui_icons",s->player.sub_weapon==2?"sword_ember":"staff_ember",0,0,1),192,310,100,0,0,0);
        draw(frame("coast_ui_icons","keeper_k",0,0,1),24,336,100,0,0,0);
        draw(frame("coast_ui_icons","keeper_l",0,0,1),176,336,100,0,0,0);
        draw(frame("coast_ui_icons","keeper_u",0,0,1),328,336,100,0,0,0);
    }
    if (s->panel) {
        unsigned start=s->panel_selected/6*6;
        for (unsigned i=start;i<s->option_count && i<start+6;++i) {
            const char *icon=item_icon(&s->options[i]);
            if (icon) draw(frame("coast_ui_icons",icon,0,0,1),574,146+(int)(i-start)*25,100,0,0,0);
        }
    }
    if (s->phase!=EMBER_UPGRADE) return;
    for (unsigned c=0;c<3;++c) {
        const struct ember_choice *choice=&s->choices[c];
        const char *rarity=choice->kind==EMBER_ITEM_WEAPON?ember_weapons[choice->id].rarity:
            choice->kind==EMBER_ITEM_RELIC?ember_relics[choice->id].rarity:
            choice->kind==EMBER_ITEM_INSCRIPTION?ember_inscriptions[choice->id].rarity:"common";
        int left=40+(int)c*190,top=112;
        ui_border(left,top,180,194,rarity);
        const char *icon=item_icon(choice);
        if (icon) draw(frame("coast_ui_icons",icon,0,0,1),left+28,top+28,100,0,0,0);
    }
}
static void light_disk(int id,int x,int y,unsigned radius,unsigned mode)
{
    if (id<0) return;
    unsigned before=draw_count;
    draw(id,x-camera_x,y-camera_y,(radius*200+ember_art_frame((unsigned)id)->w-1)/ember_art_frame((unsigned)id)->w,0,0,0);
    if (draw_count!=before) { draws[draw_count-1].mode=(uint8_t)mode;draws[draw_count-1].additive=mode==0; }
}
static void scene_lights(const struct ember_sim *s,int id,unsigned mode)
{
    for (unsigned i=0;i<s->pillar_count;++i) if (s->pillars[i].lit)
        light_disk(id,s->pillars[i].x/EMBER_Q,s->pillars[i].y/EMBER_Q,(unsigned)ember_lighting[0].pillar_radius,mode);
    if (s->player.relic_level[EMBER_DATA_RELICS_EMBER_LAMP])
        for (unsigned i=0;i<EMBER_ENEMIES;++i) if (s->enemies[i].alive && s->enemies[i].burn)
            light_disk(id,s->enemies[i].x/EMBER_Q,s->enemies[i].y/EMBER_Q,
                (unsigned)ember_relics[EMBER_DATA_RELICS_EMBER_LAMP].value2,mode);
}
static void light_outer(int id,int x,int y,unsigned width,unsigned height)
{
    if (!height) return;
    /* Continue the authored mask's constant corner outside its disk. Uniform
     * palette quads avoid interpolating triangles across the entire screen. */
    while (width) {
        unsigned part=width>511?511:width,before=draw_count;
        draw(id,320,180,100,0,0,0);
        if (draw_count!=before) {
            struct draw *d=&draws[draw_count-1];
            d->x=(int16_t)x;d->y=(int16_t)y;d->span_w=(uint16_t)part;d->span_h=(uint16_t)height;
            d->mode=2;d->palette=(uint16_t)(ember_cache_palette_count()*3+29);
        }
        width-=part;x+=(int)part;
    }
}
static void lighting(const struct ember_sim *s)
{
    if (s->phase==EMBER_MENU) return;
    int zone=frame("coast_light","light_zone",0,0,1);
    int view=frame("coast_light","lantern_view",0,0,1);
    scene_lights(s,zone,1); /* Native mask alpha writes the union of scene light regions. */
    if (view>=0) {
        int x=s->player.x/EMBER_Q-camera_x,y=s->player.y/EMBER_Q-camera_y;
        unsigned radius=s->lamp_disabled?0:(unsigned)s->lamp_radius;
        if (radius) light_disk(view,s->player.x/EMBER_Q,s->player.y/EMBER_Q,radius,2);
        int left=x-(int)radius,right=x+(int)radius,top=y-(int)radius,bottom=y+(int)radius;
        if (left<0) left=0;
        if (right>640) right=640;
        if (top<0) top=0;
        if (bottom>360) bottom=360;
        light_outer(view,0,0,640,(unsigned)top);
        light_outer(view,0,bottom,640,(unsigned)(360-bottom));
        light_outer(view,0,top,(unsigned)left,(unsigned)(bottom-top));
        light_outer(view,right,top,(unsigned)(640-right),(unsigned)(bottom-top));
    }
    scene_lights(s,zone,0);
}
static void particle_draw(int id,int x,int y,unsigned scale,unsigned alpha,unsigned additive,unsigned element)
{
    unsigned before=draw_count;
    draw(id,x-camera_x,y-camera_y,scale,0,0,0);
    if (draw_count!=before) { draws[draw_count-1].particle=1;draws[draw_count-1].alpha=(uint8_t)alpha;draws[draw_count-1].additive=(uint8_t)additive;
        draws[draw_count-1].palette=ember_art_frame((unsigned)id)->variants[element]; }
}
static int submitted_bounds(struct draw *d)
{
    const struct ember_art_frame *f=ember_art_frame(d->id);
    if (!d->angle) {
        int left=d->x-(d->mirror?(int)f->w-f->ax:f->ax)*d->scale/100;
        int top=d->y-f->ay*d->scale/100;
        int right=left+(int)f->w*d->scale/100,bottom=top+(int)f->h*d->scale/100;
        if (d->span_w) { left=d->x;top=d->y;right=left+d->span_w;bottom=top+d->span_h; }
        d->corners[0][0]=d->corners[3][0]=(int16_t)left;
        d->corners[1][0]=d->corners[2][0]=(int16_t)right;
        d->corners[0][1]=d->corners[1][1]=(int16_t)top;
        d->corners[2][1]=d->corners[3][1]=(int16_t)bottom;
        return right>0 && bottom>0 && left<640 && top<360;
    }
    int min_x=32767,min_y=32767,max_x=-32768,max_y=-32768;
    int cs=d->angle?ember_cos((uint16_t)(d->angle*4096)):EMBER_Q;
    int sn=d->angle?ember_sin((uint16_t)(d->angle*4096)):0;
    for (unsigned corner=0;corner<4;++corner) {
        unsigned right=corner==1 || corner==2,bottom=corner>=2;
        int vx=(right?(int)f->w:0)-(d->mirror?(int)f->w-f->ax:f->ax);
        int vy=(bottom?(int)f->h:0)-f->ay;
        int x=d->x+(vx*cs+vy*sn)/EMBER_Q*d->scale/100;
        int y=d->y+(vy*cs-vx*sn)/EMBER_Q*d->scale/100;
        if (d->span_w) { x=d->x+(right?d->span_w:0);y=d->y+(bottom?d->span_h:0); }
        d->corners[corner][0]=(int16_t)x;d->corners[corner][1]=(int16_t)y;
        if (x<min_x) min_x=x;
        if (x>max_x) max_x=x;
        if (y<min_y) min_y=y;
        if (y>max_y) max_y=y;
    }
    return max_x>0 && max_y>0 && min_x<640 && min_y<360;
}
static void collect_visible(void)
{
    unsigned count=0,world=0,terrain=0;
    particle_visible=0;
    for (unsigned i=0;i<draw_count;++i) {
        if (!submitted_bounds(&draws[i])) continue;
        if (i<world_draws) ++world;
        if (i<terrain_count) ++terrain;
        if (draws[i].particle) ++particle_visible;
        struct ember_gfx_stats *stats=ember_cache_stats();
        stats->facing_mask|=draws[i].hero_facing;
        if (draws[i].projectile) stats->dir16_mask|=1u<<draws[i].shot_dir;
        ember_cache_require(draws[i].id);
        draws[count++]=draws[i];
    }
    draw_count=count;world_draws=world;terrain_count=terrain;
}
static void terrain_batches(void)
{
    /* Tiles occupy disjoint 32px cells and share their authored palette.
     * Grouping their resident pages preserves every pixel and avoids repeatedly
     * switching/decoding the same page for each row of the visible map. */
    static struct draw ordered[(640/32+1)*(360/32+2)];
    unsigned counts[EMBER_CACHE_PAGE_CAPACITY]={0},heads[EMBER_CACHE_PAGE_CAPACITY];
    for (unsigned i=0;i<terrain_count;++i) ++counts[ember_cache_slot(draws[i].id).page];
    unsigned next=0;
    for (unsigned p=0;p<EMBER_CACHE_PAGE_CAPACITY;++p) { heads[p]=next;next+=counts[p]; }
    for (unsigned i=0;i<terrain_count;++i) ordered[heads[ember_cache_slot(draws[i].id).page]++]=draws[i];
    memcpy(draws,ordered,terrain_count*sizeof(*draws));
}
static void geometry(unsigned i)
{
    const struct draw *d=&draws[i];
    const struct ember_art_frame *f=ember_art_frame(d->id);
    struct ember_art_slot slot=ember_cache_slot(d->id);
    int x=d->x-(d->mirror?(int)f->w-f->ax:f->ax)*d->scale/100;
    int y=d->y-f->ay*d->scale/100;
    if (d->scale==100 && !d->angle) {
        if (d->span_w) { x=d->x;y=d->y; }
        gpu_quad(&quads[quad_index[i]],&(struct gpu_quad_args){.x=(uint32_t)x,.y=(uint32_t)y,
            .w=d->span_w?d->span_w:f->w,.h=d->span_w?d->span_h:f->h,.u0=slot.x,.v0=slot.y,.pal_group=0,.alpha=d->alpha,.flip_h=d->mirror});
        return;
    }
    static const unsigned order[]={0,1,2,0,2,3};
    for (unsigned v=0;v<6;++v) {
        unsigned corner=order[v],right=corner==1 || corner==2,bottom=corner>=2;
        unsigned u=(slot.x+((right!=d->mirror)?f->w:0))*256;
        unsigned tex_v=(slot.y+(bottom?f->h:0))*256;
        if (f->sample) {
            u+=right!=d->mirror?-128:128;tex_v+=bottom?-128:128;
        } else {
            /* Q8.8 endpoints encode the outer edge of a 256-texel page as
             * 255+255/256; 256 itself would wrap the vertex's 16-bit field. */
            u-=u==65536;tex_v-=tex_v==65536;
        }
        gpu_vertex(&vertices[i*6+v],&(struct gpu_vertex_args){
            .x=(uint32_t)(d->corners[corner][0]-320),
            .y=(uint32_t)(180-d->corners[corner][1]),.color=65535,.nz=127,.u=u,.v=tex_v});
    }
}
void ember_gfx_prepare(const struct ember_sim *s,unsigned fps,const struct ember_ui_state *ui)
{
    if (!have_frame || s->config.stage!=last_stage || s->frame<last_frame) ember_cache_new_stage();
    consume=!have_frame || s->frame!=last_frame;
    advance=(!have_frame || s->combat_frame!=last_combat) && !s->paused && s->phase!=EMBER_UPGRADE;
    struct ember_gfx_stats *stats=ember_cache_stats();
    stats->elites=stats->heads=stats->bosses=0;
    for (unsigned i=0;i<EMBER_ENEMIES;++i) if (s->enemies[i].alive) {
        unsigned rank=(unsigned)ember_enemies[s->enemies[i].kind].rank;
        if (rank==3) ++stats->bosses;
        else if (rank==2) ++stats->heads;
        else if (s->enemies[i].affix) ++stats->elites;
    }
    ember_cache_begin();
    ember_cache_equipment(s->player.evolution[2],s->player.evolution[0]);
    camera_x=s->player.x/EMBER_Q-320;camera_y=s->player.y/EMBER_Q-180;
    if (camera_x<0) camera_x=0;
    if (camera_y<0) camera_y=0;
    if (camera_x>s->world_width/EMBER_Q-640) camera_x=s->world_width/EMBER_Q-640;
    if (camera_y>s->world_height/EMBER_Q-360) camera_y=s->world_height/EMBER_Q-360;
    draw_count=0;
    coast(s);pickups(s);entities(s);effects(s);
    particle_visible=0;
    ember_particles_prepare(s,advance,consume,particle_draw);
    lighting(s);
    world_draws=draw_count;
    ember_ui_build(&canvas,s,ui,fps,perf,ember_particles_alive());
    ui_art(s,ui);
    collect_visible();
    ember_cache_glyphs(&canvas,s->phase*32+s->panel*4+(s->phase==EMBER_MENU?ui->menu_page:0));
    ember_cache_resolve();
    terrain_batches();
    quad_count=0;
    for (unsigned i=0;i<draw_count;++i) {
        const struct draw *d=&draws[i];
        if (d->scale==100 && !d->angle) {
            unsigned separate=!i || i==world_draws;
            if (i && !separate) {
                const struct draw *previous=&draws[i-1];
                separate=previous->scale!=100 || previous->angle || previous->mode!=d->mode || previous->flash!=d->flash ||
                    previous->dim!=d->dim || previous->additive!=d->additive ||
                    previous->palette!=d->palette ||
                    ember_cache_slot(previous->id).page!=ember_cache_slot(d->id).page ||
                    ember_art_frame(previous->id)->format!=ember_art_frame(d->id)->format;
            }
            if (separate) quad_count=(quad_count+1)&~1u;
            quad_index[i]=quad_count++;
        } else quad_index[i]=0;
        geometry(i);
    }
    unsigned n=ember_cache_uploads(commands);
    unsigned palette_count=ember_cache_palette_count();
#define EMIT(name,...) gpu_##name(&commands[n++],&(struct gpu_##name##_args){__VA_ARGS__})
    n+=ember_particles_commands(commands+n,advance);
    EMIT(set_matrix,.addr=gpu_physical(matrix));
    EMIT(set_light,.amb_rgb=0xffffff);
    for (unsigned stripe=0;stripe<2;++stripe) {
        unsigned y=stripe*180;
        EMIT(set_target,.tgt_y0=y,.sc_x1=640,.sc_y0=y,.sc_y1=y+180,.vp_w=640,.vp_h=360);
        EMIT(clear,.color=0x0843,.depth=65535,.en_color=1,.en_depth=1,.en_stencil=1);
        EMIT(set_pixel,.depth_func=1,.color_write=1,.st_func=7,.bl_fs=2,.bl_fd=3);
        for (unsigned pass=0;pass<2;++pass) {
        if (pass) {
            if (ember_numbers_alive()) {
                for (unsigned p=0;p<13;++p)
                    EMIT(pal_load,.group=p,.src=gpu_physical(palettes+(palette_count*3+16+p)*256),.entries=256);
                ember_cache_texture(&commands[n++],ember_cache_font_page(),0);
                n+=ember_particles_numbers(commands+n,stripe);
            }
            for (unsigned p=0;p<12;++p)
                EMIT(pal_load,.group=p,.src=gpu_physical(palettes+(palette_count*3+p)*256),.entries=256);
            EMIT(set_tex,.offset=49152-32,.log2_w=3,.log2_h=3,.format=0,.levels=1);
            EMIT(draw_quad,.addr=gpu_physical(canvas.rects),.count=canvas.rect_count);
        }
        unsigned active_page=UINT32_MAX,texture_palette=UINT32_MAX,texture_sample=UINT32_MAX,texture_format=UINT32_MAX;
        unsigned bank_palette[16],bank_used[16]={0};
        for (unsigned bank=0;bank<16;++bank) bank_palette[bank]=UINT32_MAX;
        for (unsigned i=pass?world_draws:0;i<(pass?draw_count:world_draws);++i) {
            const struct draw *d=&draws[i];
            unsigned pal=d->palette+(d->flash?palette_count:d->dim?palette_count*2:0);
            struct ember_art_slot slot=ember_cache_slot(d->id);
            unsigned bank=0;
            while (bank<16 && bank_palette[bank]!=pal) ++bank;
            if (bank==16) {
                bank=0;
                for (unsigned candidate=1;candidate<16;++candidate)
                    if (bank_used[candidate]<bank_used[bank]) bank=candidate;
                bank_palette[bank]=pal;
                EMIT(pal_load,.group=bank,.src=gpu_physical(palettes+pal*256),.entries=256);
            }
            bank_used[bank]=i+1;
            unsigned native=d->scale==100 && !d->angle;
            unsigned sample=d->span_w?0:ember_art_frame(d->id)->sample;
            unsigned end=i+1,pass_end=pass?draw_count:world_draws;
            if (native) while (end<pass_end) {
                const struct draw *next=&draws[end];
                if (next->scale!=100 || next->angle || next->mode!=d->mode || next->flash!=d->flash || next->dim!=d->dim ||
                    next->additive!=d->additive || next->palette!=d->palette ||
                    ember_cache_slot(next->id).page!=slot.page ||
                    ember_art_frame(next->id)->format!=ember_art_frame(d->id)->format) break;
                ++end;
            }
            for (unsigned q=i;q<end && native;++q) {
                quads[quad_index[q]].word[EDRV32_GPU_QUAD_PAL_GROUP_OFFSET/4]&=~EDRV32_GPU_QUAD_PAL_GROUP_MASK;
                quads[quad_index[q]].word[EDRV32_GPU_QUAD_PAL_GROUP_OFFSET/4]|=bank<<EDRV32_GPU_QUAD_PAL_GROUP_POS;
            }
            if (slot.page!=active_page || (!native && bank!=texture_palette) || sample!=texture_sample || ember_art_frame(d->id)->format!=texture_format) {
                ember_cache_texture_filtered(&commands[n++],slot.page,bank,sample,ember_art_frame(d->id)->format);
                active_page=slot.page;texture_palette=bank;texture_sample=sample;texture_format=ember_art_frame(d->id)->format;
            }
            if (d->mode==1)
                EMIT(set_pixel,.depth_func=1,.st_func=7,.st_zpass=2,.st_ref=1,.st_wmask=1);
            else if (d->mode==2) {
                const struct ember_art_frame *f=ember_art_frame(d->id);
                EMIT(set_pixel,.depth_func=1,.color_write=1,.st_func=2,.st_rmask=1,
                    .bl_fs=f->blend_fs,.bl_fd=f->blend_fd,.bl_op=f->blend_op);
            } else if (d->additive || (d->alpha<255 && !native))
                EMIT(set_pixel,.depth_func=1,.color_write=1,.st_func=7,
                    .bl_fs=!native && d->alpha<255?8:2,.bl_fd=d->additive?1:9,.bl_const_a=d->alpha);
            if (native) { EMIT(draw_quad,.addr=gpu_physical(quads+quad_index[i]),.count=end-i); }
            else { EMIT(draw_tri,.addr=gpu_physical(vertices+i*6),.count=2); }
            if (d->mode || d->additive || (d->alpha<255 && !native))
                EMIT(set_pixel,.depth_func=1,.color_write=1,.st_func=7,.bl_fs=2,.bl_fd=3);
            i=end-1;
        }
        }
        for (unsigned p=0;p<16;++p)
            EMIT(pal_load,.group=p,.src=gpu_physical(palettes+(palette_count*3+p)*256),.entries=256);
        ember_cache_texture(&commands[n++],ember_cache_font_page(),0);
        EMIT(draw_quad,.addr=gpu_physical(canvas.glyphs),.count=canvas.glyph_count);
        resolve_command[stripe]=n;
        EMIT(resolve,.stride=1280,.x1=640,.y0=y,.y1=y+180);
    }
#undef EMIT
    if (n>COMMANDS) { plat_printf("GPU command capacity exhausted\n");fflush(stdout);abort(); }
    command_count=n;
    last_combat=s->combat_frame;
    last_frame=s->frame;last_stage=s->config.stage;have_frame=1;
}
const struct ember_gfx_stats *ember_gfx_statistics(void) { return ember_cache_stats(); }
void ember_gfx_submit(unsigned frame_number)
{
    for (unsigned stripe=0;stripe<2;++stripe)
        gpu_resolve(&commands[resolve_command[stripe]],&(struct gpu_resolve_args){
            .base=gpu_physical(surface[frame_number&1]),.stride=1280,.x1=640,
            .y0=stripe*180,.y1=stripe*180+180});
    unsigned source_count;
    const struct gpu_range *cache_sources=ember_cache_sources(&source_count);
    struct gpu_range sources[10];
    memcpy(sources,cache_sources,source_count*sizeof(*sources));
    sources[source_count++]=(struct gpu_range){(uintptr_t)matrix,64};
    sources[source_count++]=(struct gpu_range){(uintptr_t)quads,quad_count*sizeof(*quads)};
    sources[source_count++]=(struct gpu_range){(uintptr_t)vertices,draw_count*6*sizeof(*vertices)};
    sources[source_count++]=(struct gpu_range){(uintptr_t)canvas.rects,canvas.rect_count*sizeof(*canvas.rects)};
    sources[source_count++]=(struct gpu_range){(uintptr_t)canvas.glyphs,canvas.glyph_count*sizeof(*canvas.glyphs)};
    sources[source_count++]=(struct gpu_range){(uintptr_t)palettes,(ember_cache_palette_count()*3+30)*1024};
    sources[source_count++]=ember_particles_source();sources[source_count++]=ember_numbers_source();
    struct gpu_range results[]={ember_particles_result(),{(uintptr_t)released,EMBER_PARTICLES*sizeof(*released)}};
    gpu_live_rect(-128,-128,4096,2400);
    gpu_object_lists(released,0,released,EMBER_PARTICLES);
    struct gpu_batch batch={commands,command_count,sources,source_count,results,2};
    gpu_submit(&batch);
    struct gpu_event event=gpu_wait();
    if (event.error) { plat_printf("Ember Isles GPU error %u\n",event.error);fflush(stdout);abort(); }
    struct ember_gfx_stats *stats=ember_cache_stats();
    stats->particles=ember_particles_alive();
    stats->particle_visible=particle_visible;
    stats->number_objects=ember_numbers_alive();
    if (particle_visible>stats->particle_visible_peak) stats->particle_visible_peak=particle_visible;
    if (stats->particles>stats->particle_peak) stats->particle_peak=stats->particles;
    for (unsigned i=0;i<16;++i) {
        uint32_t value=mmio_read32(EDRV32_GPU_BASE+EDRV32_GPU_PERF_OFFSET(i));
        perf[i]=value-raw_perf[i];raw_perf[i]=value;
    }
    mmio_write32(EDRV32_DISP_BASE+EDRV32_DISP_GPU_LAYER_CTRL_OFFSET,
        EDRV32_DISP_GPU_LAYER_CTRL_L0_EN_MASK|EDRV32_DISP_GPU_LAYER_CTRL_L0_X2_MASK);
    disp_submit(DISP_L0,gpu_physical(surface[frame_number&1]),1280);
    mmio_write32(EDRV32_DISP_BASE+EDRV32_DISP_GPU_CTRL_OFFSET,EDRV32_DISP_GPU_CTRL_ENABLE_MASK);
}
