/* File: e5a_replay.c; tech 3/6: ordinary keyboard inputs for both complete modes.
 * Description: Read-only pilot generates a replay; playback uses only its snapshot/inputs.
 * Clock domain: fixed 60 Hz, no HP/damage/invulnerability mutations.
 */
#include "sim/sim.h"
#include "data.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
static struct ember_sim simulation;
static struct ember_replay replay;
static unsigned shop_stage = UINT_MAX, shop_wave = UINT_MAX;
static int relic_score(unsigned id)
{
    static const int values[38] = {45,60,30,25,35,5,30,15,100,110,120,5,25,75,10,
        40,35,30,20,160,80,80,10,20,5,75,30,80,60,180,70,-100,100,130,10,45,50,140};
    return values[id];
}
static int item_score(const struct ember_sim *s, struct ember_choice c)
{
    if (c.kind == EMBER_ITEM_WEAPON)
        return s->player.weapon_level[c.id] ? (c.id == s->player.main_weapon ? 400 : 80) :
            c.id == 1 ? 90 : 0;
    if (c.kind == EMBER_ITEM_RELIC) return relic_score(c.id);
    if (c.kind == EMBER_ITEM_INSCRIPTION) {
        int score = c.id == 1 ? 250 : c.id == 6 ? 200 : c.id == 16 ? 180 :
            c.id == 7 ? 160 : c.id == 5 ?
            (s->config.mode == EMBER_ROUTE ? 400 : 120) : 50;
        return score + (c.slot == s->player.main_weapon ? 50 : 0);
    }
    if (c.kind == EMBER_ITEM_EVOLUTION) return c.id == 1 ? 500 : -20;
    if (c.kind == EMBER_ITEM_PET_LEVEL || c.kind == EMBER_ITEM_PET_WEAPON_LEVEL) return 80;
    if (c.kind == EMBER_ITEM_PET_WEAPON) return 80;
    if (c.kind == EMBER_ITEM_RESOURCE) return c.id == 0 ?
        (s->player.hp * 100 / s->player.max_hp < 70 ? 600 : 0) : c.id == 1 ? 70 :
        s->oil < 3000 ? 100 : 0;
    if (c.kind == EMBER_ITEM_RESONANCE) return 200;
    if (c.kind == EMBER_ITEM_BLESSING) return c.id == 8 ? 180 : c.id == 9 ? 150 :
        c.id == 7 ? 150 : c.id == 10 && s->pet_kind != 255 ? 180 : 100;
    return 0;
}
static uint16_t choose(const struct ember_sim *s, unsigned selected, unsigned count,
                        const struct ember_choice *choices)
{
    unsigned best = 0;
    for (unsigned i = 1; i < count; ++i)
        if (item_score(s, choices[i]) > item_score(s, choices[best])) best = i;
    if (best != selected) return s->previous_input & EMBER_DOWN ? 0 : EMBER_DOWN;
    return s->previous_input & EMBER_J ? 0 : EMBER_J;
}
static uint16_t to_point(const struct ember_sim *s, struct ember_point p, int interact)
{
    int x = (p.x - s->player.x) / EMBER_Q, y = (p.y - s->player.y) / EMBER_Q;
    if (interact && abs(x) <= 18 && abs(y) <= 18)
        return s->previous_input & EMBER_INTERACT ? 0 : EMBER_INTERACT;
    return (x > 5 ? EMBER_RIGHT : x < -5 ? EMBER_LEFT : 0) |
        (y > 5 ? EMBER_DOWN : y < -5 ? EMBER_UP : 0);
}
static struct ember_point steer(const struct ember_sim *s, struct ember_point goal)
{
    if (s->stage_clear) return goal;
    const struct ember_shot *incoming = NULL;
    int64_t earliest = 31;
    for (unsigned i = 0; i < EMBER_SHOTS; ++i) {
        const struct ember_shot *p = &s->shots[i];
        if (!p->alive || p->room != s->room_serial) continue;
        int64_t dx = (int64_t)s->player.x - p->x, dy = (int64_t)s->player.y - p->y;
        if (p->kind == 2 && p->enemy_kind != 255) {
            int64_t radius = (p->radius + 24) * EMBER_Q;
            if (dx*dx + dy*dy < radius*radius) {
                if (!dx && !dy) dx = goal.x >= s->player.x ? EMBER_Q : -EMBER_Q;
                if (p->enemy_kind == 20) {
                    int64_t scale = llabs(dx) > llabs(dy) ? llabs(dx) : llabs(dy);
                    return (struct ember_point){
                        s->player.x + (ember_fixed)(dx * 120 * EMBER_Q / scale),
                        s->player.y + (ember_fixed)(dy * 120 * EMBER_Q / scale)};
                }
                return (struct ember_point){s->player.x + (ember_fixed)(dx * 3),
                    s->player.y + (ember_fixed)(dy * 3)};
            }
        }
        if (!p->hostile || p->delay) continue;
        int64_t speed = (int64_t)p->vx * p->vx + (int64_t)p->vy * p->vy;
        int64_t approach = dx * p->vx + dy * p->vy;
        if (!speed || approach <= 0) continue;
        int64_t time = approach / speed;
        if (time > earliest) continue;
        int64_t x = dx - p->vx * time, y = dy - p->vy * time;
        int64_t radius = (p->radius + 24) * EMBER_Q;
        if (x*x + y*y < radius*radius) { earliest = time; incoming = p; }
    }
    if (incoming) {
        int64_t side = (int64_t)(goal.x - s->player.x) * -incoming->vy +
            (int64_t)(goal.y - s->player.y) * incoming->vx;
        int sign = side >= 0 ? 1 : -1;
        goal.x = s->player.x - incoming->vy * 45 * sign;
        goal.y = s->player.y + incoming->vx * 45 * sign;
    }
    return goal;
}
static uint16_t progress_input(const struct ember_sim *s, struct ember_point p)
{
    int x = (p.x - s->player.x) / EMBER_Q, y = (p.y - s->player.y) / EMBER_Q;
    uint16_t input = abs(x) <= 18 && abs(y) <= 18 ? to_point(s, p, 1) :
        to_point(s, steer(s, p), 0);
    input |= EMBER_J;
    if (s->alive_count && !s->player.cooldown_k) input |= EMBER_K;
    return input;
}
static uint16_t panel_input(const struct ember_sim *s)
{
    if (s->panel == EMBER_PANEL_SHOP) {
        unsigned best = UINT_MAX;
        int value = -1;
        for (unsigned i = 0; i < s->option_count; ++i) {
            struct ember_choice c = s->options[i];
            if ((unsigned)s->option_prices[i] > s->gold) continue;
            int score = item_score(s, c);
            if (c.kind == EMBER_ITEM_RELIC) {
                unsigned held = 0; int worst = INT_MAX;
                for (unsigned r = 0; r < 38; ++r) if (s->player.relic_level[r]) {
                    ++held; if (relic_score(r) < worst) worst = relic_score(r);
                }
                if (held == 6) score -= worst;
            }
            if (c.kind == EMBER_ITEM_INSCRIPTION) {
                if (c.slot != s->player.main_weapon) score = -1;
                else if (s->player.inscription[c.slot][1]) {
                    int worst = INT_MAX;
                    for (unsigned r = 0; r < 2; ++r) {
                        struct ember_choice old = {EMBER_ITEM_INSCRIPTION,
                            (uint8_t)(s->player.inscription[c.slot][r] - 1), c.slot};
                        int old_score = item_score(s, old);
                        if (old_score < worst) worst = old_score;
                    }
                    score -= worst;
                }
            }
            if (c.kind == EMBER_ITEM_REFRESH)
                score = s->shop_refreshes < 4 && s->gold >
                    (unsigned)s->option_prices[i] + 100 ? 1 : -1;
            if (score > value && score > 0) { value = score; best = i; }
        }
        if (best == UINT_MAX) {
            shop_stage = s->config.stage; shop_wave = s->wave;
            return s->previous_input & EMBER_INTERACT ? 0 : EMBER_INTERACT;
        }
        if (best != s->panel_selected) return s->previous_input & EMBER_DOWN ? 0 : EMBER_DOWN;
        return s->previous_input & EMBER_J ? 0 : EMBER_J;
    }
    if (s->panel == EMBER_PANEL_REPLACE) {
        unsigned best = 0;
        if (s->pending_item.kind == EMBER_ITEM_WEAPON) best = s->option_count - 1;
        else if (s->pending_item.kind == EMBER_ITEM_RELIC) {
            for (unsigned i = 1; i < s->option_count; ++i)
                if (relic_score(s->options[i].id) < relic_score(s->options[best].id)) best = i;
        } else if (s->pending_item.kind == EMBER_ITEM_INSCRIPTION) {
            for (unsigned i = 1; i < s->option_count; ++i) {
                struct ember_choice a = s->options[i], b = s->options[best];
                a.slot = b.slot = s->pending_item.slot;
                if (item_score(s, a) < item_score(s, b)) best = i;
            }
        }
        if (best != s->panel_selected) return s->previous_input & EMBER_DOWN ? 0 : EMBER_DOWN;
        return s->previous_input & EMBER_J ? 0 : EMBER_J;
    }
    if (s->panel == EMBER_PANEL_ALTAR || s->panel == EMBER_PANEL_HIDDEN)
        return choose(s, s->panel_selected, s->option_count, s->options);
    return s->previous_input & EMBER_INTERACT ? 0 : EMBER_INTERACT;
}
static uint16_t pilot(const struct ember_sim *s)
{
    if (s->panel) return panel_input(s);
    if (s->phase == EMBER_MENU) return EMBER_START;
    if (s->phase == EMBER_UPGRADE) return choose(s, s->selected, 3, s->choices);
    if (s->phase != EMBER_PLAY) return 0;
    if (s->room_kind == EMBER_ROOM_HIDDEN) return to_point(s, s->hidden_exit, 1);
    if (s->stage_clear) {
        if (s->shop_available && (shop_stage != s->config.stage || shop_wave != s->wave))
            return progress_input(s, s->merchant);
        if (s->config.mode == EMBER_ROUTE && !s->room_lit)
            return to_point(s, s->lighthouse, 1);
        return to_point(s, s->exit, 1);
    }
    if (s->altars_available)
        return progress_input(s, s->altar);
    if (s->shop_available && shop_stage != s->config.stage)
        return progress_input(s, s->merchant);
    if (s->config.mode == EMBER_ROUTE && s->room_cleared) {
        if (!s->room_lit) return to_point(s, s->lighthouse, 1);
        unsigned best = 0;
        int value = -1;
        for (unsigned i = 0; i < (unsigned)ember_route[s->island].exits; ++i) {
            unsigned reward = s->door_rewards[s->island][i];
            int score = reward == EMBER_REWARD_ALTAR ? 100 :
                reward == EMBER_REWARD_SHOP && s->gold > 200 ? 110 :
                reward == EMBER_REWARD_RELIC ? 80 : reward == EMBER_REWARD_GOLD ? 60 :
                reward == EMBER_REWARD_PET && s->pet_kind == 255 ? 90 :
                reward == EMBER_REWARD_WEAPON ? 30 : 0;
            if (score > value) { value = score; best = i; }
        }
        return to_point(s, s->doors[best], 1);
    }
    uint16_t input = EMBER_J;
    int closest = -1; int64_t closest_distance = INT64_MAX;
    for (unsigned i = 0; i < EMBER_ENEMIES; ++i) if (s->enemies[i].alive) {
        int64_t x = (s->enemies[i].x - s->player.x) / EMBER_Q;
        int64_t y = (s->enemies[i].y - s->player.y) / EMBER_Q;
        if (x*x + y*y < closest_distance) { closest_distance = x*x + y*y; closest = (int)i; }
    }
    if (closest >= 0) {
        const struct ember_enemy *e = &s->enemies[closest];
        if (e->affix == 4 || e->second_affix == 4 || (e->extra_affixes & (1u << 3)))
            input &= (uint16_t)~EMBER_J;
    }
    if (!s->player.cooldown_k && s->alive_count) input |= EMBER_K;
    if (!s->player.cooldown_b && s->alive_count) input |= EMBER_L;
    if (s->player.charge == 100) input |= EMBER_U;
    for (unsigned i = 0; i < EMBER_ENEMIES; ++i) {
        const struct ember_enemy *e = &s->enemies[i];
        int dx = (e->x - s->player.x) / EMBER_Q, dy = (e->y - s->player.y) / EMBER_Q;
        if (e->alive && e->capturable && dx * dx + dy * dy < 100 * 100)
            return input | to_point(s, (struct ember_point){e->x,e->y}, 1);
    }
    int boss = -1;
    for (unsigned i = 0; i < EMBER_ENEMIES; ++i)
        if (s->enemies[i].alive && s->enemies[i].defense.rank == 3 && !s->enemies[i].illusion)
            boss = (int)i;
    if (boss < 0 && s->wave % 10 == 0 && s->alive_count) {
        int target = -1; int64_t distance = INT64_MAX;
        for (unsigned i = 0; i < EMBER_ENEMIES; ++i) if (s->enemies[i].alive) {
            int64_t x = (s->enemies[i].x - s->player.x) / EMBER_Q;
            int64_t y = (s->enemies[i].y - s->player.y) / EMBER_Q;
            if (x*x + y*y < distance) { distance = x*x + y*y; target = (int)i; }
        }
        if (target >= 0) return input | to_point(s,
            (struct ember_point){s->enemies[target].x - 70 * EMBER_Q,s->enemies[target].y}, 0);
    }
    struct ember_point center = {s->world_width / 2, s->world_height / 2};
    int rx = s->config.mode == EMBER_ROUTE ? 260 : 280;
    int ry = s->config.mode == EMBER_ROUTE ? 140 : 170;
    if (s->config.mode == EMBER_ROUTE && boss < 0 && s->alive_count <= 3 && closest >= 0) {
        center = (struct ember_point){s->enemies[closest].x, s->enemies[closest].y};
        rx = 100; ry = 80;
    }
    if (boss >= 0 && (s->enemies[boss].stage >= 2 ||
        (s->config.mode == EMBER_ROUTE && s->enemies[boss].kind == 20 &&
         s->enemies[boss].stage == 1))) {
        int nearest = -1, distance = INT_MAX;
        for (unsigned i = 0; i < s->pillar_count; ++i) {
            int dx = (s->pillars[i].x - s->player.x) / EMBER_Q;
            int dy = (s->pillars[i].y - s->player.y) / EMBER_Q;
            int d = dx * dx + dy * dy;
            if (d < distance) { distance = d; nearest = (int)i; }
        }
        if (s->config.mode == EMBER_ROUTE && s->enemies[boss].kind == 20 &&
            s->oil >= ember_lighting[0].pillar_cost) {
            int unlit = -1; distance = INT_MAX;
            for (unsigned i = 0; i < s->pillar_count; ++i) if (!s->pillars[i].lit) {
                int dx = (s->pillars[i].x - s->player.x) / EMBER_Q;
                int dy = (s->pillars[i].y - s->player.y) / EMBER_Q;
                if (dx * dx + dy * dy < distance) {
                    distance = dx * dx + dy * dy; unlit = (int)i;
                }
            }
            if (unlit >= 0) nearest = unlit;
        }
        if (nearest >= 0) {
            center = (struct ember_point){s->pillars[nearest].x,s->pillars[nearest].y};
            if (!s->pillars[nearest].lit && s->oil >= ember_lighting[0].pillar_cost)
                return input | to_point(s, center, 1);
            rx = 68; ry = 60;
        }
    }
    uint16_t angle = (uint16_t)(s->combat_frame * (rx < 100 ? 240u : 91u));
    struct ember_point goal = {center.x + ember_cos(angle) * rx,
        center.y + ember_sin(angle) * ry};
    if (s->hazard_phase && s->config.stage > 0) {
        int x = (s->hazard_point.x - s->player.x) / EMBER_Q;
        int y = (s->hazard_point.y - s->player.y) / EMBER_Q;
        int radius = ember_hazards[s->config.stage].radius + 24;
        if (x*x + y*y < radius*radius) {
            goal.x = s->player.x - x * EMBER_Q * 2;
            goal.y = s->player.y - y * EMBER_Q * 2;
            if (!x && !y) goal.x += s->player.x < s->world_width / 2 ?
                120 * EMBER_Q : -120 * EMBER_Q;
        }
    }
    input |= to_point(s, steer(s, goal), 0);
    return input;
}
static void end_record(void)
{
    printf("END,%u,%u,%u,%u,%u\n", replay.count, simulation.phase, simulation.wave,
        simulation.config.mode, simulation.config.stage);
    fflush(stdout);
    fprintf(stderr, "mode=%u frames=%u combat=%u phase=%u stage=%u wave=%u "
        "hp=%d kills=%u bosses=%u gold=%u level=%u\n", simulation.config.mode,
        replay.count, simulation.combat_frame, simulation.phase, simulation.config.stage,
        simulation.wave, simulation.player.hp, simulation.player.kills,
        simulation.bosses_defeated, simulation.gold, simulation.player.level);
}
int main(int argc, char **argv)
{
    int generate = argc == 4 && !strcmp(argv[1], "--generate");
    const char *path;
    if (generate) {
        path = argv[3];
        replay.seed = 20261125;
        ember_run_config_default(&replay.config);
        replay.config.mode = (uint8_t)strtoul(argv[2], NULL, 10);
        replay.count = EMBER_REPLAY_FRAMES;
    } else if (argc == 2) { path = argv[1]; ember_replay_load(&replay, path); }
    else { fputs("e5a-replay --generate mode path | replay-path\n", stderr); return 1; }
    ember_sim_begin(&simulation, replay.seed, &replay.config);
    printf("RUN,mode=%u,stage=%u,seed=%u\n", replay.config.mode, replay.config.stage, replay.seed);
    unsigned won = 0, limit = replay.count;
    for (unsigned frame = 0; frame < limit; ++frame) {
        if (generate) replay.input[frame] = pilot(&simulation);
        ember_sim_step(&simulation, replay.input[frame]);
        unsigned types = 0, medium = 0;
        for (unsigned k = 0; k < 21; ++k) if (simulation.ordinary_count[k]) {
            ++types; medium += ember_enemies[k].body_class == 1;
        }
        if (types > 3 || medium > 2) {
            fputs("Ordinary species budget exceeded\n", stderr);
            return 1;
        }
        if ((frame + 1) % 60 == 0) {
            char summary[2048];
            ember_sim_summary(&simulation, summary, sizeof(summary));
            printf("STATE,%s\n", summary);
        }
        if (simulation.phase == EMBER_WON && !won) won = frame + 1;
        if (generate && ((won && (frame + 1) % 60 == 0) || simulation.phase == EMBER_LOST)) {
            replay.count = frame + 1;
            break;
        }
    }
    if (generate) ember_replay_save(&replay, path);
    end_record();
    if (simulation.phase != EMBER_WON || simulation.config.stage != 2 ||
        simulation.wave != 30 || simulation.alive_count || simulation.queued_spawns ||
        simulation.bosses_defeated != ((1u << 18) | (1u << 19) | (1u << 20))) {
        fputs("Replay did not win all three stages through normal input\n", stderr);
        return 1;
    }
    return 0;
}
