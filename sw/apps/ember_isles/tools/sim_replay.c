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
static uint8_t demo_input(void)
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
    uint8_t input = leg == 0 ? EMBER_RIGHT : leg == 1 ? EMBER_DOWN :
                    leg == 2 ? EMBER_LEFT : EMBER_UP;
    if (sim.player.charge == 1000 && sim.combat_frame % 120 == 0)
        input |= EMBER_A | EMBER_B;
    else if (sim.combat_frame % 240 == 0) input |= EMBER_B;
    else if (sim.combat_frame % 180 == 0) input |= EMBER_A;
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
    memset(sim.player.weapon_level, 0, sizeof(sim.player.weapon_level));
}
static void target(unsigned index, int offset, int hp)
{
    sim.enemies[index] = (struct ember_enemy){0};
    sim.enemies[index].alive = 1;
    sim.enemies[index].hp = hp;
    sim.enemies[index].x = sim.player.x + offset * EMBER_Q;
    sim.enemies[index].y = sim.player.y;
    sim.enemies[index].wave = 1;
    ++sim.alive_count;
}
static unsigned kind_count(unsigned kind)
{
    unsigned count = 0;
    for (unsigned i = 0; i < EMBER_SHOTS; ++i)
        count += sim.shots[i].alive && sim.shots[i].kind == kind;
    return count;
}
static void tests(void)
{
    ember_sim_init(&sim, 0);
    ember_sim_step(&sim, EMBER_A);
    require(sim.phase == EMBER_MENU, "menu only accepts START");
    ember_sim_step(&sim, EMBER_START);
    require(sim.phase == EMBER_PLAY, "START begins combat");
    ember_sim_step(&sim, 0);
    unsigned combat = sim.combat_frame;
    ember_sim_step(&sim, EMBER_START);
    require(sim.paused && sim.combat_frame == combat, "START pauses simulation");
    ember_sim_step(&sim, 0);
    ember_sim_step(&sim, EMBER_START);
    require(!sim.paused && sim.combat_frame == combat + 1, "START resumes simulation");
    setup();
    ember_fixed x = sim.player.x;
    ember_sim_step(&sim, EMBER_A | EMBER_RIGHT);
    require(sim.player.x > x && sim.player.dash && sim.player.invulnerable,
            "dash moves and grants its invulnerability");
    require(kind_count(2) == 1 && sim.player.cooldown_a, "dash leaves burning trail");
    ember_sim_step(&sim, 0);
    require(!sim.events.count, "events clear each simulation step");
    setup();
    ember_sim_step(&sim, EMBER_B);
    require(kind_count(4) == 1 && sim.player.cooldown_b, "B plants timed explosive seed");
    for (unsigned i = 0; i < 89; ++i) ember_sim_step(&sim, 0);
    require(!kind_count(4) && kind_count(1), "seed detonates after ninety combat frames");
    setup();
    sim.player.charge = 1000;
    target(0, 40, 100);
    ember_sim_step(&sim, EMBER_A | EMBER_B);
    require(kind_count(5) && sim.player.kills == 1 && !sim.player.cooldown_a &&
            !sim.player.cooldown_b, "charged A+B casts burst instead of either skill");
    setup();
    target(0, 100, 10000);
    for (unsigned w = 0; w < 4; ++w) sim.player.weapon_level[w] = 1;
    ember_sim_step(&sim, 0);
    require(kind_count(0) && kind_count(1) && kind_count(2) && kind_count(3),
            "all four automatic weapon shapes fire");
    memset(sim.player.weapon_level, 0, sizeof(sim.player.weapon_level));
    require(sim.shots[3].z > 0, "fire pot follows a positive height arc");
    for (unsigned i = 0; i < 59; ++i) ember_sim_step(&sim, 0);
    require(!kind_count(3) && kind_count(1), "fire pot lands and explodes");
    setup();
    target(0, 100, 10000);
    sim.player.weapon_level[0] = 1;
    sim.player.inscription[0][0] = 1;
    ember_sim_step(&sim, 0);
    require(kind_count(0) == 3, "projectile inscription splits into three sparks");
    setup();
    sim.player.weapon_level[2] = 1;
    sim.player.inscription[2][0] = 2;
    ember_sim_step(&sim, 0);
    ember_sim_step(&sim, EMBER_RIGHT);
    require(sim.shots[0].x == sim.player.x, "area inscription follows player");
    setup();
    target(0, 20, 1000);
    sim.enemies[0].burn = 180;
    sim.player.weapon_level[0] = 1;
    sim.player.inscription[0][0] = 3;
    ember_sim_step(&sim, 0);
    ember_sim_step(&sim, 0);
    require(sim.enemies[0].hp == 965, "scorch applies a separate 25 percent multiplier");
    setup();
    sim.player.weapon_level[0] = 1;
    sim.player.inscription[0][0] = 4;
    for (unsigned i = 0; i < 5; ++i) target(i, 20 + (int)i * 55, i ? 10 : 1);
    ember_sim_step(&sim, 0);
    ember_sim_step(&sim, 0);
    require(sim.player.kills == 4 && sim.enemies[4].alive,
            "wildfire radius propagates death explosions through exactly three layers");
    setup();
    sim.phase = EMBER_UPGRADE;
    sim.choices[0] = (struct ember_choice){1, 0, 0};
    ember_sim_step(&sim, EMBER_A);
    require(sim.player.max_hp == 300 && sim.player.hp == 300, "health relic adds flat forty");
    sim.phase = EMBER_UPGRADE;
    sim.choices[0] = (struct ember_choice){1, 2, 0};
    ember_sim_step(&sim, 0);
    ember_sim_step(&sim, EMBER_A);
    require(sim.player.speed == 138, "speed relic adds fifteen percent increased");
    setup();
    sim.phase = EMBER_UPGRADE;
    sim.choices[0] = (struct ember_choice){1, 1, 0};
    ember_sim_step(&sim, EMBER_A);
    require(sim.player.armor == 30, "armor relic adds ten flat armor");
    sim.phase = EMBER_UPGRADE;
    sim.choices[0] = (struct ember_choice){1, 3, 0};
    ember_sim_step(&sim, 0);
    ember_sim_step(&sim, EMBER_A);
    require(sim.attributes[EMBER_AREA] == 120, "lens adds twenty percent area");
    setup();
    target(0, 20, 1000);
    sim.player.relic_level[4] = 1;
    sim.player.relic_level[5] = 1;
    sim.player.weapon_level[0] = 1;
    sim.player.weapon_level[1] = 1;
    ember_sim_step(&sim, 0);
    require(sim.weapon_timer[0] == 29 && sim.weapon_timer[1] == 149,
            "fletching attack speed applies only to projectile weapons");
    require(sim.enemies[0].burn == 270, "coal adds fifty percent ignite duration");
    setup();
    sim.player.relic_level[5] = 1;
    target(0, 100, 1000);
    sim.enemies[0].burn = 180;
    for (unsigned i = 0; i < 150; ++i) ember_sim_step(&sim, 0);
    require(sim.enemies[0].hp == 982, "coal preserves fractional twenty percent burn damage");
    setup();
    x = sim.obstacles[0].x - (sim.obstacles[0].radius + 8) * EMBER_Q;
    sim.player.x = x;
    sim.player.y = sim.obstacles[0].y;
    ember_sim_step(&sim, EMBER_RIGHT);
    require(sim.player.x <= x + EMBER_Q, "circular reefs block player movement");
    setup();
    sim.combat_frame = 43259;
    sim.player.x = 16 * EMBER_Q;
    sim.safe_left = 32 * EMBER_Q;
    int hp = sim.player.hp;
    ember_sim_step(&sim, 0);
    require(sim.safe_left == 34 * EMBER_Q && sim.player.hp < hp,
            "twelve minute tide shrinks the safe zone and damages outside players");
    setup();
    sim.player.hp = 1;
    target(0, 1, 100);
    ember_sim_step(&sim, 0);
    require(sim.phase == EMBER_LOST && !sim.player.hp, "zero health loses the run");
    puts("PASS menu pause skills weapons inscriptions relics tide reefs loss");
}
int main(int argc, char **argv)
{
    if (argc == 2 && !strcmp(argv[1], "--test")) tests();
    else if (argc == 3 && !strcmp(argv[1], "--generate")) run(1, argv[2]);
    else if (argc == 2) run(0, argv[1]);
    else { fputs("usage: sim_replay --test | [--generate] replay.txt\n", stderr); return 1; }
    return 0;
}
