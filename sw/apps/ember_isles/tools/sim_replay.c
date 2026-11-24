/* File: sim_replay.c
 * Spec: ember_isles tech 3; E2 deterministic replay acceptance.
 * Description: Original demo input recording and field/state comparison on a host.
 * Clock domain: fixed 60 Hz simulation.
 */
#include "sim/sim.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static struct ember_sim sim, twin;
static struct ember_replay replay;
static void require(int condition, const char *message)
{
    if (!condition) { fprintf(stderr, "FAIL frame %u: %s\n", sim.frame, message); exit(1); }
}
static int choice_score(const struct ember_choice *c)
{
    if (c->kind == 0) return sim.player.weapon_level[c->id] ? (c->id == 0 ? 90 : 80) : 100;
    if (c->kind == 2) return c->id == 0 ? 90 : c->id == 2 ? 75 : 60;
    return c->id == 0 && sim.player.hp < 80 ? 95 : c->id == 3 ? 75 : 50;
}
static uint16_t demo_input(void)
{
    if (sim.phase == EMBER_MENU) return EMBER_START;
    if (sim.phase == EMBER_UPGRADE) {
        unsigned best = 0;
        for (unsigned i = 1; i < 3; ++i)
            if (choice_score(&sim.choices[i]) > choice_score(&sim.choices[best])) best = i;
        if (sim.selected != best)
            return sim.previous_input & EMBER_RIGHT ? 0 : EMBER_RIGHT;
        return sim.previous_input & EMBER_A ? 0 : EMBER_A;
    }
    if (sim.phase != EMBER_PLAY) return 0;
    /* A compact clockwise route gathers XP while leaving burning ground to pursue through. */
    unsigned leg = (sim.combat_frame / 120) % 4;
    uint16_t input = leg == 0 ? EMBER_RIGHT : leg == 1 ? EMBER_DOWN :
                    leg == 2 ? EMBER_LEFT : EMBER_UP;
    if (sim.combat_frame < 81) {
        int32_t distance = sim.pillars[2].y - sim.player.y;
        input = distance < -24 * EMBER_Q ? EMBER_UP :
                distance > 24 * EMBER_Q ? EMBER_DOWN : EMBER_INTERACT;
    }
    input |= sim.combat_frame % 120 == 119 ? 0 : EMBER_J;
    if (sim.combat_frame == 1500 || sim.combat_frame == 1620) input |= EMBER_SWAP;
    if (sim.player.charge == 1000) input |= EMBER_U;
    if (sim.combat_frame % 240 == 0) input |= EMBER_L;
    if (sim.combat_frame % 180 == 0) input |= EMBER_K;
    if (sim.combat_frame % 600 == 0) input |= EMBER_DASH;
    if (sim.combat_frame == 100) input |= EMBER_INTERACT;
    return input;
}
static void run(int generate, const char *path)
{
    if (generate) {
        replay.seed = 20261124;
        replay.count = EMBER_DEMO_FRAMES;
    } else ember_replay_load(&replay, path);
    ember_sim_init(&sim, replay.seed);
    ember_sim_init(&twin, replay.seed);
    unsigned first_wave = 0, elite = 0, upgrade = 0, won = 0;
    unsigned events[10] = {0};
    unsigned peak_enemies = 0, peak_shots = 0;
    for (unsigned frame = 0; frame < replay.count; ++frame) {
        if (generate) replay.input[frame] = demo_input();
        ember_sim_step(&sim, replay.input[frame]);
        ember_sim_step(&twin, replay.input[frame]);
        require(!memcmp(&sim, &twin, sizeof(sim)), "same seed/input state differs");
        for (unsigned i = 0; i < sim.events.count; ++i) {
            require(sim.events.item[i].kind < 10, "unfrozen event kind");
            ++events[sim.events.item[i].kind];
        }
        if (sim.alive_count > peak_enemies) peak_enemies = sim.alive_count;
        if (sim.shot_count > peak_shots) peak_shots = sim.shot_count;
        if (!first_wave && sim.wave == 1 && sim.alive_count > 3) first_wave = sim.frame;
        if (!elite && sim.wave == 5 && sim.alive_count > 3) elite = sim.frame;
        if (!upgrade && sim.phase == EMBER_UPGRADE) upgrade = sim.frame;
        if (!won && sim.phase == EMBER_WON) won = sim.frame;
        if (sim.frame % 60 == 0) {
            char summary[2048], other[2048];
            ember_sim_summary(&sim, summary, sizeof(summary));
            ember_sim_summary(&twin, other, sizeof(other));
            require(!strcmp(summary, other), "field summaries differ");
            puts(summary);
        }
    }
    fprintf(stderr, "frames=%u victory=%u wave1=%u elite=%u wave5=%u upgrade=%u "
            "peak_enemies=%u peak_shots=%u hp=%d kills=%u level=%u\n",
            replay.count, won, first_wave, elite, elite + 1, upgrade,
            peak_enemies, peak_shots, sim.player.hp, sim.player.kills, sim.player.level);
    fprintf(stderr, "events shot=%u hit=%u kill=%u dash=%u seed=%u ultimate=%u "
            "levelup=%u choose=%u hurt=%u victory=%u\n",
            events[0], events[1], events[2], events[3], events[4], events[5],
            events[6], events[7], events[8], events[9]);
    require(sim.phase == EMBER_WON && sim.wave == 5 && sim.alive_count == 0,
            "demo must clear five waves");
    require(events[6] && events[7], "demo must offer and confirm upgrades");
    require(events[3] && events[4] && events[5], "demo must demonstrate all active skills");
    if (generate) ember_replay_save(&replay, path);
}
static void setup(void)
{
    ember_sim_init(&sim, 7);
    sim.phase = EMBER_PLAY;
    sim.wave = 1;
    sim.rest = 10000;
    sim.attributes[EMBER_CRIT] = 0;
    sim.player.pet_weapon = 255;
}
static void target(unsigned i, int offset, int hp)
{
    sim.enemies[i] = (struct ember_enemy){0};
    sim.enemies[i].alive = 1;
    sim.enemies[i].hp = hp;
    sim.enemies[i].x = sim.player.x + offset * EMBER_Q;
    sim.enemies[i].y = sim.player.y;
    sim.enemies[i].wave = 1;
    ember_defense_init(&sim.enemies[i].defense, hp);
    ++sim.alive_count;
}
static unsigned shots(void)
{
    return sim.shot_count;
}
static void tests(void)
{
    struct ember_rng rng = {11};
    struct ember_defense d;
    struct ember_attack h = {.base = 100, .attack = 100, .crit_damage = 150,
                            .share = {100,0,0,0,0,0}};
    struct ember_damage_result r;
    int32_t hp;
#define RESET() do { ember_defense_init(&d, 1000000); hp = 1000000; } while (0)
#define HIT(expected, message) do { r = ember_damage(&rng, &h, &d, &hp); \
    require(r.damage == (expected), message); } while (0)
    int32_t more[4] = {20, 25, 0, 0};
    require(ember_attribute_value(EMBER_ATTACK_SPEED, 300, 0, 100, more, 0) == 300,
            "table default cap");
    require(ember_attribute_value(EMBER_CRIT, 110, 0, 0, (int32_t[4]){0}, 30) == 110,
            "raised crit cap permits super critical");
    require(ember_attribute_value(EMBER_ATTACK, 100, 20, 50, more, 0) == 270,
            "flat/increased/independent more ordering");
    require(ember_attribute_value(EMBER_CRIT, 1000001, 0, 0, (int32_t[4]){0},
            2000000) == 1000000, "numeric range cap");
    RESET(); h.flat = 20; h.attack = 150; h.increased = 50; h.more[0] = 20;
    h.more[1] = 25; d.vulnerability = 20; d.armor = 100;
    HIT(243, "gdd steps one through seven");
    h = (struct ember_attack){.base=800,.attack=100,.crit_damage=150,.crit=200,
                              .share={100,0,0,0,0,0}};
    RESET(); HIT(1500, "super critical uses attenuated second multiplier");
    require(r.crit == 2, "super critical presentation tier");
    RESET(); h.flags = EMBER_DOT; HIT(800, "dot cannot crit by default");
    RESET(); h.flags |= EMBER_DOT_CRIT; HIT(1500, "relic enables dot critical");
    h.crit=0; h.flags=0; h.base=100;
    RESET(); d.armor=100; d.status[EMBER_BREAK_ARMOR].stacks=5; h.penetration=50;
    HIT(80, "armor break precedes penetration");
    RESET(); d.armor=100; d.immune_break=1; d.status[EMBER_BREAK_ARMOR].stacks=5;
    HIT(66, "separate break immunity");
    RESET(); d.armor=100; d.immune_pierce=1; d.status[EMBER_BREAK_ARMOR].stacks=5;
    HIT(66, "separate penetration immunity");
    h.penetration=0;
    for (unsigned i=1; i<5; ++i) {
        RESET(); memset(h.share,0,sizeof(h.share)); h.share[i]=100;
        d.resistance[i-1]=50; d.all_resistance=10; HIT(40, "four elemental resistances");
        RESET(); d.resistance[i-1]=-50; HIT(150, "negative resistance weakness");
        RESET(); d.resistance[i-1]=100; HIT(25, "default resistance cap");
        RESET(); d.resistance[i-1]=100; d.resistance_cap[i-1]=90;
        HIT(10, "raised resistance cap");
    }
    RESET(); h.share[4]=0; h.share[0]=70; h.share[1]=30; h.crit=200;
    h.base=800; d.armor=100; d.resistance[0]=50;
    HIT(750, "mixed shares use one shared super critical then separate defenses");
    require(r.crit==2 && r.part[0]==525 && r.part[1]==225, "mixed shares and dominant");
    RESET(); h.crit=0; h.base=100; h.share[0]=100; h.share[1]=0;
    h.conversion=50; h.added[2]=20; d.armor=100; HIT(95,"conversion and added share");
    h.conversion=0; h.added[2]=0;
    RESET(); d.reduction[0]=20; d.reduction[1]=30; HIT(56,"independent reductions");
    RESET(); d.reduction[0]=90; HIT(20,"total reduction default cap");
    RESET(); d.dodge=100; HIT(0,"dodge before damage"); require(r.dodged,"dodge flag");
    h.flags=EMBER_UNDODGEABLE; HIT(100,"boss heavy undodgeable"); h.flags=0;
    RESET(); d.block_chance=100; d.block_strength=50; HIT(50,"probability block");
    RESET(); d.front_block=1; d.block_strength=50; HIT(100,"rear bypasses front block");
    h.flags=EMBER_FRONT; HIT(50,"front block"); h.flags|=EMBER_IGNORE_BLOCK;
    HIT(100,"ignore block"); h.flags=0;
    RESET(); d.invulnerable=1; HIT(0,"phase or hit invulnerability");
    ember_defense_step(&d); HIT(100,"invulnerability expires");
    RESET(); d.temporary[0]=10; d.temporary[6]=20; d.permanent_shield=30;
    HIT(40,"element temporary then mixed temporary then permanent shield");
    require(r.absorbed==60,"absorbed damage reporting");
    RESET(); memset(h.share,0,sizeof(h.share)); h.share[5]=100;
    d.armor=999; d.resistance[0]=100; d.block_chance=100; d.block_strength=100;
    d.vulnerability=20; d.reduction[0]=50; d.temporary[0]=1000;
    d.temporary[6]=1000; d.permanent_shield=1000; d.temporary[5]=10;
    HIT(50,"true damage skips defense and block; vulnerability reduction true shield remain");
    RESET(); d.shield_max=100; d.shield_recovery=10; d.temporary[0]=50;
    d.shield_frames[0]=2; ember_defense_step(&d); ember_defense_step(&d);
    require(!d.temporary[0],"temporary shield expires");
    for (unsigned i=2;i<180;++i) ember_defense_step(&d);
    require(!d.permanent_shield,"permanent shield waits three seconds");
    ember_defense_step(&d); require(d.permanent_shield==10,"shield recovers after delay");
    RESET(); d.tenacity=50;
    for (unsigned i=0;i<3;++i) ember_status_apply(&d,EMBER_CHILL,180,100);
    require(d.frozen==45 && d.status[EMBER_CHILL].frames==90,"chill stacks freeze tenacity");
    RESET(); d.rank=3; d.posture=d.posture_max=100;
    ember_status_apply(&d,EMBER_STUN,30,100);
    require(!d.status[EMBER_STUN].frames && d.posture==60,"boss stun becomes posture");
    ember_status_apply(&d,EMBER_CHILL,180,100);
    ember_status_apply(&d,EMBER_STUN,30,100);
    require(d.broken && !d.posture,"boss posture break");
    for (unsigned i=0;i<180;++i) ember_defense_step(&d);
    require(!d.broken && d.posture==100,"broken state ends and restores posture");
    setup(); target(0,100,10000);
    ember_sim_step(&sim,0); require(!shots(),"main and sub do not auto attack");
    ember_sim_step(&sim,EMBER_J); require(shots()==1,"J attacks nearest with main weapon");
    ember_sim_step(&sim,EMBER_SWAP); require(sim.player.main_weapon==1,"Q swaps slots");
    unsigned old=shots(); ember_sim_step(&sim,EMBER_J);
    require(shots()>old,"new main attacks");
    old=shots(); ember_sim_step(&sim,0);
    require(shots()<=old,"release J does not add an undecided charge attack");
    setup(); int32_t x=sim.player.x; ember_sim_step(&sim,EMBER_DASH|EMBER_RIGHT);
    require(sim.player.x>x && sim.player.action==EMBER_DASHING,"space dash action");
    setup(); sim.player.x=sim.pillars[0].x; sim.player.y=sim.pillars[0].y;
    ember_sim_step(&sim,EMBER_INTERACT);
    require(sim.pillars[0].lit && sim.oil==6999,"F consumes CSV pillar cost");
    sim.oil=0; ember_sim_step(&sim,0); require(sim.in_light,"pillar is independent light source");
    setup(); for(unsigned i=0;i<60;++i) ember_sim_step(&sim,0);
    require(sim.oil==9900,"CSV oil drain per second");
    setup(); target(0,100,10000); sim.player.pet_weapon=0;
    ember_sim_step(&sim,0); require(shots()==1,"pet weapon autonomous attack");
    setup(); target(0,100,10000); ember_sim_status(&sim,0,EMBER_WET,0);
    ember_sim_status(&sim,0,EMBER_IGNITE,0);
    require(!sim.enemies[0].defense.status[EMBER_WET].frames,"steam clears wet");
    for(unsigned i=0;i<10;++i) ember_sim_status(&sim,0,EMBER_IGNITE,0);
    require(sim.enemies[0].defense.status[EMBER_IGNITE].stacks==5,"ignite stack cap");
    setup(); target(0,20,10000); target(1,70,10000); ember_sim_status(&sim,0,EMBER_SHOCK,0);
    require(sim.enemies[1].hp<10000,"shock chains into adjacent enemy");
    setup(); target(0,20,10000); ember_sim_status(&sim,0,EMBER_CORRODE,0);
    ember_sim_step(&sim,0); require(sim.enemies[0].hp==9500,"corrosion reduces maximum life");
    for (unsigned bonus=0;bonus<2;++bonus) {
        setup(); sim.trigger_bonus=(uint8_t)bonus;
        for (unsigned i=0;i<6;++i) {
            target(i,20+(int)i*40,1);
            ember_sim_status(&sim,i,EMBER_IGNITE,0);
        }
        ember_sim_step(&sim,0);
        h=(struct ember_attack){.base=100,.attack=100,.share={0,100,0,0,0,0}};
        ember_sim_hit(&sim,0,&h);
        require(sim.player.kills==4+bonus && sim.trigger_peak==3+bonus,
                "death trigger chain three layers; relic adds one");
    }
    RESET(); d.temporary[0]=30; d.temporary[1]=10; d.temporary[6]=20;
    d.permanent_shield=10;
    h=(struct ember_attack){.base=100,.attack=100,.share={50,50,0,0,0,0}};
    HIT(30,"mixed shield absorption is ordered per share");
    RESET(); h.base=1000000; h.share[0]=100; h.share[1]=0; d.armor=100;
    HIT(500000,"32 bit large damage");
    setup(); target(0,20,10000); target(1,60,10000);
    ember_sim_step(&sim,0);
    sim.enemies[0].defense.frozen=90;
    h=(struct ember_attack){.base=10,.attack=100,.share={100,0,0,0,0,0}};
    ember_sim_hit(&sim,0,&h);
    require(!sim.enemies[0].defense.frozen && sim.enemies[1].hp<10000,
            "iron shatters frozen target into nearby shards");
    setup(); target(0,20,10000);
    ember_sim_status(&sim,0,EMBER_BREAK_ARMOR,0);
    h=(struct ember_attack){.base=100,.attack=100,.crit=100,.crit_damage=150,
                           .share={100,0,0,0,0,0}};
    int32_t before=sim.enemies[0].hp;
    ember_sim_hit(&sim,0,&h);
    require(before-sim.enemies[0].hp>150,"critical against armor break triggers heavy hit");
    setup(); target(0,200,10000); ember_sim_status(&sim,0,EMBER_BLIND,0);
    before=sim.enemies[0].hp; ember_sim_hit(&sim,0,&h);
    require(before-sim.enemies[0].hp>150,"blind target critical in darkness adds damage");
    setup(); target(0,20,1); ember_sim_status(&sim,0,EMBER_CORRODE,0);
    sim.player.hp=100; h.crit=0; ember_sim_hit(&sim,0,&h);
    require(sim.player.hp==103,"corroded enemy kill restores life");
    setup(); target(0,0,10000); sim.player.dash=2;
    before=sim.player.hp; ember_sim_step(&sim,0);
    require(sim.player.hp==before,"dash gives contact invulnerability");
    setup(); sim.player.charge=1000; ember_sim_step(&sim,EMBER_U);
    require(!sim.player.charge && sim.player.action==EMBER_CAST,"U casts ultimate");
    setup(); ember_sim_step(&sim,EMBER_K); require(sim.player.cooldown_k,"K skill");
    setup(); ember_sim_step(&sim,EMBER_L); require(sim.player.cooldown_b,"L skill");
    setup(); target(0,100,10000); sim.weapon_system[1].rarity=2;
    sim.weapon_system[1].offhand=1; ember_sim_step(&sim,0);
    require(shots(),"rare sub weapon mechanism executes only in sub slot");
    setup(); sim.weapon_system[1].rarity=1;
    sim.weapon_system[1].offhand_attribute=EMBER_ARMOR;
    sim.weapon_system[1].offhand_flat=10; ember_sim_attributes(&sim);
    require(sim.player.armor==30,"fine offhand grants configured small stat");
    setup(); target(0,20,10000); sim.tag_damage[0]=20;
    sim.attributes[EMBER_EMBER_DAMAGE]=120;
    ember_sim_step(&sim,EMBER_J); ember_sim_step(&sim,EMBER_J);
    require(sim.enemies[0].hp==9957,"element and tag bonuses share increased damage zone");
    RESET(); h=(struct ember_attack){.base=100,.attack=100,.share={100,0,0,0,0,0}};
    d.active_block=1; d.block_strength=50; HIT(50,"active block");
    setup(); target(0,100,10000); ember_sim_status(&sim,0,EMBER_IGNITE,0);
    for(unsigned i=0;i<180;++i) ember_sim_step(&sim,0);
    require(sim.enemies[0].hp==9982 && !sim.enemies[0].burn,
            "ignite includes final interval tick then expires");
    setup(); target(0,100,10000);
    sim.weapon_system[0].share[EMBER_DAMAGE_FIRE]=0;
    sim.weapon_system[0].share[EMBER_DAMAGE_IRON]=100;
    sim.enemies[0].defense.armor=900;
    ember_sim_status(&sim,0,EMBER_IGNITE,0);
    for(unsigned i=0;i<30;++i) ember_sim_step(&sim,0);
    require(sim.enemies[0].hp==9997,"ignite remains fire damage with physical source weapon");
    puts("PASS E3 attributes damage steps1-9 types immunities shields posture "
         "statuses lights slots input");
}
int main(int argc, char **argv)
{
    if (argc == 2 && !strcmp(argv[1], "--test")) tests();
    else if (argc == 3 && !strcmp(argv[1], "--generate")) run(1, argv[2]);
    else if (argc == 2) run(0, argv[1]);
    else { fputs("usage: sim_replay --test | [--generate] replay.txt\n", stderr); return 1; }
    return 0;
}
