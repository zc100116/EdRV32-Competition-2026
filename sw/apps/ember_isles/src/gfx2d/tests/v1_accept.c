/* File: v1_accept.c; V1 acceptance. Real normal menu inputs, GPU frames and
 * frame-by-frame comparison with a rendering-free simulation; virtual 60 Hz.
 */
#include "game.h"
#include "core/core.h"
#include "gfx2d/gfx.h"
#include "gfx2d/cache.h"
#include "pc_soc.h"
#include "plat.h"
#include "png.h"
#include "data.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
static unsigned frame_number,started;
static uint16_t keys;
static struct ember_replay replay;
static struct ember_sim reference;
static FILE *audio_capture;
uint32_t pc_frontend_wait(void) { return 800; }
uint32_t pc_frontend_keys(void) { return keys; }
uint32_t pc_frontend_millis(void) { return started?(uint32_t)((uint64_t)frame_number*1000/60):0; }
void pc_frontend_audio(const int16_t *samples,uint32_t count)
{
    if (audio_capture && started && fwrite(samples,4,count,audio_capture)!=count) {
        perror("Record game audio");exit(1);
    }
}
static void input(unsigned k)
{
    keys=(uint16_t)k;
    pc_soc_game_input(keys,(struct plat_pointer_state){0});
    ember_game_tick();
}
static void render(void)
{
    ember_game_render(frame_number);
    plat_wait_vsync();
}
static void capture(const char *out,const char *name)
{
    char path[512];snprintf(path,sizeof(path),"%s/%s.png",out,name);
    pc_png_write(path,pc_soc_pixels());
}
static int aura_photo_lit(const struct ember_sim *s,const struct ember_enemy *e)
{
    int64_t dx=(int64_t)e->x-s->player.x,dy=(int64_t)e->y-s->player.y;
    if (dx*dx+dy*dy<(int64_t)60*60*EMBER_Q*EMBER_Q) return 1;
    int64_t radius=(ember_lighting[0].pillar_radius-50)*(int64_t)EMBER_Q;
    for (unsigned p=0;p<s->pillar_count;++p) if (s->pillars[p].lit) {
        dx=(int64_t)e->x-s->pillars[p].x;dy=(int64_t)e->y-s->pillars[p].y;
        if (dx*dx+dy*dy<radius*radius) return 1;
    }
    return 0;
}
int main(int argc,char **argv)
{
    if (argc!=4) { fputs("v1-accept replay output-directory coast|showcase\n",stderr);return 1; }
    unsigned showcase=!strcmp(argv[3],"showcase");
    ember_replay_load(&replay,argv[1]);
    if (showcase) {
        char path[512];snprintf(path,sizeof(path),"%s/audio.pcm",argv[2]);
        audio_capture=fopen(path,"wb");
        if (!audio_capture) { perror(path);return 1; }
    }
    ember_game_init();
    render();capture(argv[2],"title");
    printf("BOOT,fixed=%u,stream=%u,TEX_LOAD=%u\n",ember_gfx_statistics()->fixed_bytes,
        ember_gfx_statistics()->cache_bytes,ember_gfx_statistics()->load_bytes);
    input(EMBER_START);render();
    if (showcase) capture(argv[2],"weapon-choice");
    input(0);
    if (!showcase) { input(EMBER_RIGHT);input(0); }
    input(EMBER_START);render();
    const struct ember_replay *recording=ember_game_recording();
    ember_sim_begin(&reference,recording->seed,&recording->config);
    ember_sim_step(&reference,EMBER_START);
    char first_expected[2048],first_actual[2048];
    ember_sim_summary(&reference,first_expected,sizeof(first_expected));
    ember_sim_summary(ember_game_state(),first_actual,sizeof(first_actual));
    if (strcmp(first_expected,first_actual)) { fputs("Initial STATE mismatch\n",stderr);return 1; }
    printf("STATE,%s\n",first_actual);
    started=1;
    unsigned limit=showcase?1800:replay.count;
    unsigned upgrade_captured=0,upgrade_wait=0,was_upgrade=0,showcase_lit=0,combat_captured=0,showcase_swapped=0,double_captured=0;
    for (unsigned i=1;i<limit;++i) {
        frame_number=i;
        unsigned k=replay.input[i];
        if (showcase) {
            static const unsigned directions[]={EMBER_DOWN,EMBER_DOWN|EMBER_RIGHT,EMBER_RIGHT,
                EMBER_RIGHT|EMBER_UP,EMBER_UP,EMBER_UP|EMBER_LEFT,EMBER_LEFT,EMBER_LEFT|EMBER_DOWN};
            k=directions[i/100%8]|EMBER_J;
            const struct ember_sim *s=ember_game_state();
            if (!showcase_lit && i<240) {
                unsigned target=0;int64_t best=INT64_MAX;
                for (unsigned p=0;p<s->pillar_count;++p) {
                    if (s->pillars[p].lit) { showcase_lit=1;break; }
                    int64_t dx=(int64_t)s->pillars[p].x-s->player.x,dy=(int64_t)s->pillars[p].y-s->player.y;
                    if (dx*dx+dy*dy<best) { best=dx*dx+dy*dy;target=p; }
                }
                if (!showcase_lit) {
                    k=EMBER_J;
                    int dx=(s->pillars[target].x-s->player.x)/EMBER_Q;
                    int dy=(s->pillars[target].y-s->player.y)/EMBER_Q;
                    if (dx>8) k|=EMBER_RIGHT;
                    if (dx< -8) k|=EMBER_LEFT;
                    if (dy>8) k|=EMBER_DOWN;
                    if (dy< -8) k|=EMBER_UP;
                    if (best<(int64_t)24*24*EMBER_Q*EMBER_Q && i%2) k|=EMBER_INTERACT;
                }
            }
            if (!showcase_swapped && i>=240 && s->player.main_weapon==2 && s->attack_count[2]) {
                k|=EMBER_SWAP;showcase_swapped=1;
            }
            unsigned missing=(~ember_gfx_statistics()->dir16_mask)&65535u;
            if (s->player.main_weapon==0 && missing && s->phase==EMBER_PLAY) {
                int target=-1;int64_t distance=INT64_MAX;
                for (unsigned e=0;e<EMBER_ENEMIES;++e) if (s->enemies[e].alive) {
                    int64_t dx=(int64_t)s->enemies[e].x-s->player.x,dy=(int64_t)s->enemies[e].y-s->player.y;
                    if (dx*dx+dy*dy<distance) { distance=dx*dx+dy*dy;target=(int)e; }
                }
                if (target>=0) {
                    const struct ember_enemy *e=&s->enemies[target];
                    int64_t dx=(int64_t)e->x-s->player.x,dy=(int64_t)e->y-s->player.y;
                    int64_t best=INT64_MIN;unsigned direction=0;
                    for (unsigned d=0;d<16;++d) if (missing&(1u<<d)) {
                        int64_t dot=dx*ember_cos((uint16_t)(d*4096))-dy*ember_sin((uint16_t)(d*4096));
                        if (dot>best) { best=dot;direction=d; }
                    }
                    int cs=ember_cos((uint16_t)(direction*4096)),sn=ember_sin((uint16_t)(direction*4096));
                    int tx=(e->x-cs*96-s->player.x)/EMBER_Q,ty=(e->y+sn*96-s->player.y)/EMBER_Q;
                    k=0;
                    if (tx>6) k|=EMBER_RIGHT;
                    if (tx< -6) k|=EMBER_LEFT;
                    if (ty>6) k|=EMBER_DOWN;
                    if (ty< -6) k|=EMBER_UP;
                    int64_t cross=dx*sn+dy*cs,dot=dx*cs-dy*sn;
                    if (cross<0) cross=-cross;
                    if (dot>0 && cross*6<dot) k|=EMBER_J;
                }
            }
            if (i%300==100) k|=EMBER_K;
            if (i%420==200) k|=EMBER_L;
            if (s->phase==EMBER_UPGRADE) {
                if (!was_upgrade) upgrade_wait=0;
                was_upgrade=1;
                k=++upgrade_wait<120?0:upgrade_wait%2?EMBER_J:0;
            } else was_upgrade=0;
        }
        struct timespec tick_began,tick_ended;
        timespec_get(&tick_began,TIME_UTC);input(k);timespec_get(&tick_ended,TIME_UTC);
        ember_sim_step(&reference,(uint16_t)k);
        char expected[2048],before[2048],after[2048];
        ember_sim_summary(&reference,expected,sizeof(expected));
        ember_sim_summary(ember_game_state(),before,sizeof(before));
        struct timespec began,ended;
        timespec_get(&began,TIME_UTC);render();timespec_get(&ended,TIME_UTC);
        ember_sim_summary(ember_game_state(),after,sizeof(after));
        if (strcmp(expected,before) || strcmp(before,after)) {
            fprintf(stderr,"STATE mismatch at %u\nexpected %s\nbefore %s\nafter %s\n",i,expected,before,after);return 1;
        }
        printf("STATE,%s\n",after);
        const struct ember_gfx_stats *g=ember_gfx_statistics();
        long long ns=(long long)(ended.tv_sec-began.tv_sec)*1000000000LL+ended.tv_nsec-began.tv_nsec+
            (long long)(tick_ended.tv_sec-tick_began.tv_sec)*1000000000LL+tick_ended.tv_nsec-tick_began.tv_nsec;
        printf("GFX,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%lld,%u,%u,%u,%u,%u,%u,%u,%u\n",(unsigned)ember_game_state()->frame,
            (unsigned)ember_game_state()->wave,g->fixed_bytes,g->cache_bytes,g->visible_bytes,g->load_bytes,
            g->particles,g->fixed_peak,g->cache_peak,g->load_peak,ns/1000,g->particle_visible,g->particle_visible_peak,g->number_objects,g->facing_mask,g->dir16_mask,g->elites,g->heads,g->bosses);
        if (showcase && i%2==0) {
            char name[32];snprintf(name,sizeof(name),"video%04u",i/2);capture(argv[2],name);
        }
        if (!double_captured && !showcase && ember_game_state()->phase==EMBER_PLAY &&
            !ember_game_state()->panel && !ember_game_state()->paused) {
            const struct ember_sim *s=ember_game_state();
            for (unsigned e=0;e<EMBER_ENEMIES;++e) if (s->enemies[e].alive && s->enemies[e].affix &&
                s->enemies[e].second_affix && !s->enemies[e].flash && aura_photo_lit(s,&s->enemies[e]) &&
                abs((s->enemies[e].x-s->player.x)/EMBER_Q)<180 &&
                abs((s->enemies[e].y-s->player.y)/EMBER_Q)<100) {
                capture(argv[2],"elite-double");double_captured=1;
                printf("CAPTURE,double-affix,frame=%u,enemy=%u,affix=%u,second=%u,difficulty=%u\n",
                    (unsigned)s->frame,e,s->enemies[e].affix,s->enemies[e].second_affix,s->config.difficulty);
                break;
            }
        }
        if (!combat_captured) {
            const struct ember_sim *s=ember_game_state();
            for (unsigned e=0;e<EMBER_ENEMIES;++e) if (s->enemies[e].alive && s->enemies[e].kind==18 &&
                !s->enemies[e].flash && abs((s->enemies[e].x-s->player.x)/EMBER_Q)<200 &&
                abs((s->enemies[e].y-s->player.y)/EMBER_Q)<120) {
                capture(argv[2],"combat");combat_captured=1;break;
            }
        }
        if (!upgrade_captured && ember_game_state()->phase==EMBER_UPGRADE) {
            capture(argv[2],"upgrade");upgrade_captured=1;
        }
    }
    capture(argv[2],"result");
    char recording_path[512];snprintf(recording_path,sizeof(recording_path),"%s/normal-input.txt",argv[2]);
    ember_replay_save(recording,recording_path);
    if (!showcase && ember_game_state()->phase!=EMBER_WON) {
        fprintf(stderr,"Normal input did not win: phase %u\n",ember_game_state()->phase);return 1;
    }
    printf("PASS V1 normal-input %s frames=%u phase=%u kills=%u seed=%u\n",argv[3],limit,
        ember_game_state()->phase,(unsigned)ember_game_state()->player.kills,recording->seed);
    if (audio_capture) { fclose(audio_capture);audio_capture=NULL; }
    pc_soc_destroy();return 0;
}
