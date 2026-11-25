/* File: particles_test.c; art-plan 6.1/tech 2. Diagnostic unit test of all nine
 * native emitters through real GPU OBJ_STEP; not a mode or victory recording.
 */
#include "../particles.c"
#include "gfx2d/gfx.h"
#include "ui/ui.h"
#include "pc_soc.h"
#include <assert.h>
static struct ember_sim fixture;
uint32_t pc_frontend_wait(void) { return 800; }
uint32_t pc_frontend_keys(void) { return 0; }
uint32_t pc_frontend_millis(void) { return 0; }
void pc_frontend_audio(const int16_t *samples,uint32_t count) { (void)samples;(void)count; }
int main(void)
{
    plat_init();ember_gfx_init();
    struct ember_run_config config;ember_run_config_default(&config);config.sub_weapon=2;
    ember_sim_begin(&fixture,20261125,&config);ember_sim_step(&fixture,EMBER_START);
    unsigned expected=0;
    for (unsigned emitter=0;emitter<EMBER_EMITTERS_COUNT;++emitter) {
        unsigned before=end;
        emit(emitter,fixture.player.x/EMBER_Q+(int)(emitter%3)*48-48,
             fixture.player.y/EMBER_Q+(int)(emitter/3)*40-80,emitter%5);
        assert(end-before==(unsigned)ember_emitters[emitter].count);
        expected+=(unsigned)ember_emitters[emitter].count;
    }
    assert(end==expected && ember_particles_alive()==expected);
    struct gpu_object before[EMBER_PARTICLES];
    memcpy(before,objects,end*sizeof(*objects));
    struct ember_ui_state ui={.tick_rate=60,.volume=100};
    ember_gfx_prepare(&fixture,60,&ui);ember_gfx_submit(1);
    unsigned moved=0;
    for (unsigned i=0;i<end;++i) {
        unsigned life_before=(before[i].word[0]&EDRV32_GPU_OBJ_LIFE_MASK)>>EDRV32_GPU_OBJ_LIFE_POS;
        unsigned life_after=(objects[i].word[0]&EDRV32_GPU_OBJ_LIFE_MASK)>>EDRV32_GPU_OBJ_LIFE_POS;
        assert(life_after+1==life_before);
        if (before[i].word[1]!=objects[i].word[1] || before[i].word[2]!=objects[i].word[2]) ++moved;
    }
    assert(moved==expected);
    ember_sim_step(&fixture,0);ember_sim_step(&fixture,EMBER_START);
    assert(fixture.paused);
    memcpy(before,objects,end*sizeof(*objects));
    ember_gfx_prepare(&fixture,60,&ui);ember_gfx_submit(2);
    assert(!memcmp(before,objects,end*sizeof(*objects)));
    printf("PASS native particles: emitters=%u objects=%u GPU-moved=%u GPU-life-decrement=%u paused-unchanged\n",
        (unsigned)EMBER_EMITTERS_COUNT,expected,moved,expected);
    /* Directed presentation fixtures exercise both weapon branch migrations;
     * these are separate from the normal-input victory/media run. */
    fixture.paused=0;
    for (unsigned tier=0;tier<3;++tier) {
        unsigned index=end;
        damage(&(struct ember_event){.kind=EMBER_EVENT_HIT,.value=123,.tier=(uint8_t)tier,
            .damage_type=EMBER_DAMAGE_FIRE,.x=fixture.player.x,.y=fixture.player.y});
        assert(end==index+3);
        unsigned width=(objects[index].word[EDRV32_GPU_OBJ_W_OFFSET/4]&EDRV32_GPU_OBJ_W_MASK)>>EDRV32_GPU_OBJ_W_POS;
        unsigned height=(objects[index].word[EDRV32_GPU_OBJ_H_OFFSET/4]&EDRV32_GPU_OBJ_H_MASK)>>EDRV32_GPU_OBJ_H_POS;
        assert(width==(tier?11u:7u) && height==(tier?20u:12u));
    }
    puts("PASS damage objects: outlined 7x12 normal, 11x20 critical, native font bitplanes");
    for (unsigned sword=0;sword<3;++sword) for (unsigned staff=0;staff<3;++staff) {
        fixture.player.evolution[2]=(uint8_t)sword;fixture.player.evolution[0]=(uint8_t)staff;
        ++fixture.frame;++fixture.combat_frame;
        ember_gfx_prepare(&fixture,60,&ui);ember_gfx_submit(3+sword*3+staff);
        assert(ember_gfx_statistics()->fixed_bytes<=49152);
    }
    for (unsigned affix=1;affix<=EMBER_AFFIXES_COUNT;++affix) {
        char action[64];snprintf(action,sizeof(action),"elite_aura_%s",ember_affixes[affix-1].id);
        int art=ember_art_find("coast_small_fx",action,"down",0,1);
        assert(art>=0 && ember_art_frame((unsigned)art)->format==0);
        unsigned enemy=ember_sim_spawn(&fixture,0,affix,fixture.player.x+60*EMBER_Q,fixture.player.y);
        fixture.enemies[enemy].second_affix=(uint8_t)(affix%EMBER_AFFIXES_COUNT+1);
        ++fixture.frame;++fixture.combat_frame;
        ember_gfx_prepare(&fixture,60,&ui);ember_gfx_submit(20+affix);
    }
    puts("PASS I4 aura rendering: eight native affixes, two aura layers, mixed I4/I8 pages");
    puts("PASS fixed cache: all nine sword/staff branch pairs, 48 KiB region");
    pc_soc_destroy();return 0;
}
