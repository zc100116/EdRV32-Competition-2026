/* File: modes.inc; GDD 5/5d/5e/6 and coordinator E5a interaction decisions.
 * Description: Three-stage arena/route, real landmarks, clues, rewards and terrain hazards.
 * Clock domain: fixed 60 Hz; map generation uses its own per-stage random stream.
 */
static struct ember_point map_point(struct ember_sim *s)
{
    int margin = ember_system[0].spawn_boundary_margin;
    return (struct ember_point){
        (margin + (int)(ember_random(&s->map_rng) %
            (unsigned)(s->world_width / EMBER_Q - 2 * margin))) * EMBER_Q,
        (margin + (int)(ember_random(&s->map_rng) %
            (unsigned)(s->world_height / EMBER_Q - 2 * margin))) * EMBER_Q};
}
static void peaks_step(struct ember_sim *s)
{
    unsigned stage = s->config.stage, summons = 0;
    if (s->alive_count > s->peaks[stage].enemies) s->peaks[stage].enemies = s->alive_count;
    if (s->shot_count > s->peaks[stage].shots) s->peaks[stage].shots = s->shot_count;
    if (s->pickup_count > s->peaks[stage].pickups) s->peaks[stage].pickups = s->pickup_count;
    for (unsigned i = 0; i < 8; ++i) summons += !!s->summons[i].life;
    if (summons > s->peaks[stage].summons) s->peaks[stage].summons = summons;
}
static void doors_generate(struct ember_sim *s)
{
    uint8_t pool[6];
    unsigned count = 0;
    for (unsigned reward = 0; reward < 6; ++reward) {
        if (reward == EMBER_REWARD_ALTAR && s->altars_used + s->altars_available >= 2) continue;
        if (reward == EMBER_REWARD_SHOP && s->config.stage == 2 && s->island == 8) continue;
        pool[count++] = (uint8_t)reward;
    }
    for (unsigned door = 0; door < 3; ++door)
        s->door_rewards[s->island][door] = pool[ember_random(&s->map_rng) % count];
    if (ember_route[s->island].side) s->door_rewards[s->island][2] = EMBER_REWARD_SIDE;
    for (unsigned i = 0; i < s->rifts_count; ++i)
        if (s->rift_islands[i] == s->island + 1)
            s->door_rewards[s->island][s->rift_doors[i]] = EMBER_REWARD_RIFT;
}
static void room_rocks(struct ember_sim *s)
{
    for (unsigned i = 0; i < s->hidden_count; ++i) {
        s->hidden[i].obstacle_index = 255;
        if (s->room_kind != EMBER_ROOM_MAIN || s->hidden[i].island != s->island ||
            s->hidden[i].clue || s->hidden[i].found) continue;
        s->hidden[i].obstacle_index = (uint8_t)s->obstacle_count;
        s->obstacles[s->obstacle_count++] = (struct ember_obstacle){
            s->hidden[i].point.x, s->hidden[i].point.y,
            (uint16_t)ember_modes[EMBER_ROUTE].hidden_rock_radius};
    }
}
static void rock_open(struct ember_sim *s, unsigned hidden)
{
    unsigned index = s->hidden[hidden].obstacle_index;
    --s->obstacle_count;
    memmove(&s->obstacles[index], &s->obstacles[index + 1],
        (s->obstacle_count - index) * sizeof(s->obstacles[0]));
    for (unsigned i = 0; i < s->hidden_count; ++i)
        if (s->hidden[i].obstacle_index != 255 && s->hidden[i].obstacle_index > index)
            --s->hidden[i].obstacle_index;
    s->hidden[hidden].obstacle_index = 255;
    s->hidden[hidden].found = 1;
}
static void modes_init(struct ember_sim *s)
{
    const struct ember_modes_row *m = &ember_modes[s->config.mode];
    s->map_rng.state = s->rng_seed * 2u + 7u + s->config.stage * 200002u;
    s->island = s->room_wave = s->room_cleared = s->room_lit = 0;
    s->room_kind = EMBER_ROOM_MAIN;
    s->room_reward = EMBER_REWARD_GOLD;
    s->side_left = s->side_completed = s->stage_clear = 0;
    s->altars_available = s->shop_available = s->altar_generated = 0;
    s->shop_refreshes = 0;
    s->altars_used = 0;
    s->rifts_count = (uint8_t)(m->rifts_min + ember_random(&s->map_rng) %
        (unsigned)(m->rifts_max - m->rifts_min + 1));
    s->rifts_available = s->rifts_count;
    s->rifts_used = 0;
    for (unsigned i = 0; i < s->rifts_count; ++i) {
        s->rifts[i] = map_point(s);
        s->rift_islands[i] = (uint8_t)(1 + ember_random(&s->map_rng) % (unsigned)(m->islands - 1));
        if (i && s->rift_islands[1] == s->rift_islands[0])
            s->rift_islands[1] = (uint8_t)(1 + s->rift_islands[0] % (m->islands - 1));
    }
    if (s->config.mode == EMBER_ROUTE) s->rifts_available = 0;
    for (unsigned i = 0; i < s->rifts_count; ++i) {
        unsigned previous = s->rift_islands[i] - 1;
        unsigned doors = (unsigned)ember_route[previous].exits -
            (unsigned)ember_route[previous].side;
        s->rift_doors[i] = (uint8_t)(ember_random(&s->map_rng) % doors);
    }
    s->hidden_count = s->config.mode == EMBER_ROUTE ?
        (uint8_t)(m->hidden_min + ember_random(&s->map_rng) %
            (unsigned)(m->hidden_max - m->hidden_min + 1)) : 0;
    for (unsigned i = 0; i < s->hidden_count; ++i) {
        s->hidden[i].point = map_point(s);
        s->hidden[i].island = (uint8_t)(ember_random(&s->map_rng) % (unsigned)m->islands);
        s->hidden[i].clue = (uint8_t)(ember_random(&s->map_rng) % 3);
        s->hidden[i].hp = m->hidden_rock_hp;
        s->hidden[i].found = s->hidden[i].visited = 0;
    }
    room_rocks(s);
    s->hazard_point = map_point(s);
    s->hazard_cycle = 0;
    s->hazard_phase = 0;
    ++s->room_serial;
}
static void item_drop(struct ember_sim *s, struct ember_choice c)
{
    unsigned kind = c.kind == EMBER_ITEM_WEAPON ? EMBER_DROP_WEAPON :
        c.kind == EMBER_ITEM_RELIC ? EMBER_DROP_RELIC :
        c.kind == EMBER_ITEM_INSCRIPTION ? EMBER_DROP_INSCRIPTION : EMBER_DROP_PET_WEAPON;
    drop_resource(s, kind, c.id, c.slot, 0, s->player.x, s->player.y);
}
static void chest_cleanse(struct ember_sim *s)
{
    if (!s->cleanse_tokens && ember_random(&s->loot_rng) % 100 <
        (unsigned)ember_modes[s->config.mode].hidden_cleanse_percent)
        drop_resource(s, EMBER_DROP_CLEANSE, 0, 0, 1, s->player.x, s->player.y);
}
static void modes_reward(struct ember_sim *s, unsigned reward)
{
    if (reward == EMBER_REWARD_WEAPON || reward == EMBER_REWARD_RELIC ||
        reward == EMBER_REWARD_LEGENDARY) {
        struct ember_choice pool[200];
        unsigned count = item_pool(s, pool,
            reward == EMBER_REWARD_LEGENDARY ? (unsigned)ember_economy[0].chest_grade : 0, 0);
        if (reward != EMBER_REWARD_LEGENDARY) {
            for (unsigned i = 0; i < count;)
                if (reward == EMBER_REWARD_WEAPON ? (pool[i].kind != EMBER_ITEM_WEAPON &&
                    pool[i].kind != EMBER_ITEM_PET_WEAPON) : pool[i].kind != EMBER_ITEM_RELIC)
                    pool[i] = pool[--count];
                else ++i;
        }
        if (count) item_drop(s, pool[ember_random(&s->loot_rng) % count]);
        if (reward == EMBER_REWARD_LEGENDARY) chest_cleanse(s);
    } else if (reward == EMBER_REWARD_GOLD)
        drop_resource(s, EMBER_DROP_GOLD, 0, 0, (unsigned)ember_economy[0].reward_gold,
            s->player.x, s->player.y);
    else if (reward == EMBER_REWARD_ALTAR) ++s->altars_available;
    else if (reward == EMBER_REWARD_SHOP) { s->shop_available = 1; shop_stock(s); }
    else if (reward == EMBER_REWARD_RIFT) {
        for (unsigned i = 0; i < s->rifts_count; ++i)
            if (s->rift_islands[i] == s->island) s->rifts_available = 1;
    } else if (reward == EMBER_REWARD_WORLD)
        drop_resource(s, EMBER_DROP_WORLD, s->config.stage * 3 +
            ember_random(&s->loot_rng) % 3, 0, 1, s->player.x, s->player.y);
}
static void arena_milestones(struct ember_sim *s)
{
    memset(s->wave_live, 0, sizeof(s->wave_live));
    memset(s->wave_wait, 0, sizeof(s->wave_wait));
    for (unsigned i = 0; i < EMBER_ENEMIES; ++i)
        if (s->enemies[i].alive) ++s->wave_live[s->enemies[i].wave - 1];
    for (unsigned i = 0; i < s->queued_spawns; ++i) ++s->wave_wait[s->spawn_queue[i].wave - 1];
    for (unsigned i = s->config.stage * 10; i < s->wave; ++i) {
        if (s->wave_finished[i] || s->wave_scheduled[i] != ember_waves[i].count ||
            s->wave_live[i] || s->wave_wait[i]) continue;
        s->wave_finished[i] = 1;
        pickups_step(s, 1);
        if (i % 10 == 2 || i % 10 == 6) ++s->altars_available;
        if (i % 10 == 4 || (i % 10 == 9 && (unsigned)s->config.stage + 1 <
            (unsigned)ember_modes[s->config.mode].stages)) {
            s->shop_available = 1;
            shop_stock(s);
        }
    }
}
static void modes_cleared(struct ember_sim *s)
{
    unsigned local = (s->wave - 1) % 10;
    if (s->config.mode == EMBER_ROUTE) {
        unsigned waves = s->room_kind == EMBER_ROOM_SIDE ? 1u :
            (unsigned)ember_route[s->island].waves;
        if ((unsigned)s->room_wave + 1 < waves) {
            ++s->room_wave;
            s->rest = (unsigned)ember_waves[s->wave - 1].rest_frames;
            s->room_wave_pending = 1;
            return;
        }
        s->room_cleared = 1;
        memset(s->shots, 0, sizeof(s->shots));
        s->shot_count = 0;
        modes_reward(s, s->room_reward);
        if (s->room_kind == EMBER_ROOM_MAIN && local != 9) doors_generate(s);
        if (s->room_kind != EMBER_ROOM_MAIN || local != 9) return;
    } else {
        if (local != 9) { s->rest = (unsigned)ember_waves[s->wave - 1].rest_frames; return; }
    }
    s->stage_clear = 1;
    if ((unsigned)s->config.stage + 1 == (unsigned)ember_modes[s->config.mode].stages)
        s->shop_available = 0;
    pickups_step(s, 2);
    s->rest = 0;
}
static void room_enter(struct ember_sim *s)
{
    memset(s->shots, 0, sizeof(s->shots));
    memset(s->pickups, 0, sizeof(s->pickups));
    memset(s->summons, 0, sizeof(s->summons));
    s->shot_count = s->pickup_count = 0;
    s->spawned = s->wave_frame = s->rest = 0;
    s->room_wave = s->room_cleared = s->room_lit = s->room_wave_pending = 0;
    s->altars_available = s->shop_available = s->altar_generated = 0;
    s->rifts_available = 0;
    ++s->room_serial;
    ember_fixed left = s->safe_left, top = s->safe_top;
    ember_fixed right = s->safe_right, bottom = s->safe_bottom;
    uint32_t stage_frame = s->stage_frame;
    world_setup(s);
    s->safe_left = left; s->safe_top = top; s->safe_right = right; s->safe_bottom = bottom;
    s->stage_frame = stage_frame;
    if (s->island == 9 || s->island == 4) s->pillar_count = 3;
    room_rocks(s);
    s->wave = s->config.stage * 10 + s->island + 1;
}
static void stage_exit(struct ember_sim *s)
{
    if ((unsigned)s->config.stage + 1 == (unsigned)ember_modes[s->config.mode].stages) {
        s->phase = EMBER_WON;
        event(s, EMBER_EVENT_VICTORY, s->config.mode, s->player.x, s->player.y);
        return;
    }
    ++s->config.stage;
    memset(s->ground, 0, sizeof(s->ground));
    memset(s->shots, 0, sizeof(s->shots));
    memset(s->pickups, 0, sizeof(s->pickups));
    memset(s->summons, 0, sizeof(s->summons));
    s->shot_count = s->pickup_count = 0;
    s->wave = s->config.stage * 10 + 1;
    s->spawned = s->wave_frame = s->rest = 0;
    s->boss_blackout = s->saved_pillars = 0;
    world_setup(s);
    modes_init(s);
    ember_sim_attributes(s);
}
static int point_near(const struct ember_sim *s, struct ember_point point)
{
    return within(s->player.x, s->player.y, point.x, point.y, ember_lighting[0].interact_radius);
}
static void hidden_open(struct ember_sim *s, unsigned index)
{
    s->hidden[index].visited = 1;
    s->hidden_active = (uint8_t)index;
    s->hidden_return_position = (struct ember_point){s->player.x,s->player.y};
    s->hidden_return_serial = s->room_serial;
    s->hidden_return_pillars = s->pillar_count;
    s->hidden_return_obstacles = s->obstacle_count;
    ++s->room_serial;
    s->pillar_count = 0;
    s->obstacle_count = 0;
    s->world_width = ember_modes[EMBER_ROUTE].hidden_width * EMBER_Q;
    s->world_height = ember_modes[EMBER_ROUTE].hidden_height * EMBER_Q;
    s->safe_left = s->safe_top = 0;
    s->safe_right = s->world_width; s->safe_bottom = s->world_height;
    s->player.x = s->world_width / 2; s->player.y = s->world_height / 2;
    s->pet.x = s->player.x; s->pet.y = s->player.y;
    s->hidden_exit = (struct ember_point){s->world_width / 2,
        (ember_fixed)((int64_t)s->world_height *
            ember_modes[EMBER_ROUTE].hidden_exit_y_percent / 100)};
    s->room_kind = EMBER_ROOM_HIDDEN;
    ++s->hidden_rooms;
    struct ember_choice pool[200];
    unsigned count = item_pool(s, pool, 2, 0);
    panel_open(s, EMBER_PANEL_HIDDEN);
    if (count) s->options[s->option_count++] = pool[ember_random(&s->loot_rng) % count];
    s->options[s->option_count++] = (struct ember_choice){EMBER_ITEM_WORLD,
        (uint8_t)(s->config.stage * 3 + s->hidden[index].clue), 0};
    chest_cleanse(s);
}
static int modes_interact(struct ember_sim *s)
{
    if (s->room_kind == EMBER_ROOM_HIDDEN) {
        if (point_near(s, s->hidden_exit)) {
            s->room_kind = EMBER_ROOM_MAIN;
            s->world_width = ember_modes[EMBER_ROUTE].width * EMBER_Q;
            s->world_height = ember_modes[EMBER_ROUTE].height * EMBER_Q;
            s->safe_left = s->safe_top = 0;
            s->safe_right = s->world_width; s->safe_bottom = s->world_height;
            s->player.x = s->hidden_return_position.x; s->player.y = s->hidden_return_position.y;
            s->pet.x = s->player.x; s->pet.y = s->player.y;
            s->room_serial = s->hidden_return_serial;
            s->pillar_count = s->hidden_return_pillars;
            s->obstacle_count = s->hidden_return_obstacles;
            return 1;
        }
        goto ground_items;
    }
    if (s->stage_clear && (s->config.mode == EMBER_ARENA || s->room_lit) &&
        point_near(s, s->exit)) {
        stage_exit(s);
        return 1;
    }
    for (unsigned i = 0; i < s->hidden_count; ++i)
        if (s->room_cleared && s->room_kind == EMBER_ROOM_MAIN &&
            s->hidden[i].island == s->island && s->hidden[i].found &&
            !s->hidden[i].visited && point_near(s, s->hidden[i].point)) {
            hidden_open(s, i);
            return 1;
        }
    if (s->config.mode == EMBER_ROUTE && s->room_cleared && !s->room_lit &&
        point_near(s, s->lighthouse)) {
        s->room_lit = 1;
        s->pillars[0].x = s->lighthouse.x; s->pillars[0].y = s->lighthouse.y;
        s->pillars[0].lit = 1;
        if (!s->pillar_count) s->pillar_count = 1;
        ++s->pillars_lit;
        return 1;
    }
    if (s->config.mode == EMBER_ROUTE && s->room_lit && !s->stage_clear) {
        unsigned exits = s->room_kind == EMBER_ROOM_SIDE ?
            1u : (unsigned)ember_route[s->island].exits;
        for (unsigned i = 0; i < exits; ++i) if (point_near(s, s->doors[i])) {
            if (s->room_kind == EMBER_ROOM_SIDE) {
                --s->side_left;
                ++s->side_completed;
                if (!s->side_left) { s->room_kind = EMBER_ROOM_MAIN; ++s->island; }
                s->room_reward = s->side_left ? (uint8_t)(ember_random(&s->loot_rng) % 3 == 0 ?
                    EMBER_REWARD_PET : ember_random(&s->loot_rng) % 2 ?
                    EMBER_REWARD_LEGENDARY : EMBER_REWARD_WORLD) : EMBER_REWARD_GOLD;
            } else {
                unsigned reward = s->door_rewards[s->island][i];
                if (reward == EMBER_REWARD_SIDE) {
                    const struct ember_modes_row *m = &ember_modes[EMBER_ROUTE];
                    s->side_left = (uint8_t)(m->side_min + ember_random(&s->loot_rng) %
                        (unsigned)(m->side_max - m->side_min + 1));
                    s->room_kind = EMBER_ROOM_SIDE;
                    s->room_reward = (uint8_t)(ember_random(&s->loot_rng) % 3 == 0 ?
                        EMBER_REWARD_PET : ember_random(&s->loot_rng) % 2 ?
                        EMBER_REWARD_LEGENDARY : EMBER_REWARD_WORLD);
                } else { ++s->island; s->room_reward = (uint8_t)reward; }
            }
            room_enter(s);
            return 1;
        }
    }
    if (s->shop_available && point_near(s, s->merchant)) { shop_open(s); return 1; }
    if (s->altars_available && point_near(s, s->altar)) { altar_open(s); return 1; }
    if (s->cleanse_tokens && point_near(s, s->lighthouse)) { cleanse_open(s); return 1; }
    if (s->rifts_available)
        for (unsigned i = 0; i < s->rifts_count; ++i)
            if (!(s->rifts_used & (1u << i)) &&
                (s->config.mode == EMBER_ARENA || s->rift_islands[i] == s->island) &&
                point_near(s, s->rifts[i]) &&
                !light_zone_at(s, s->rifts[i].x, s->rifts[i].y)) {
                s->chosen_rift = (uint8_t)i;
                contract_open(s);
                return 1;
            }
ground_items:
    for (unsigned i = 0; i < 62; ++i) {
        struct ember_ground_weapon *g = &s->ground[i];
        if (g->alive && g->room == s->room_serial &&
            within(s->player.x, s->player.y, g->x, g->y, ember_lighting[0].interact_radius)) {
            pending_reset(s);
            s->pending_ground = (int16_t)i;
            item_receive(s, (struct ember_choice){g->kind, g->id, 255});
            return 1;
        }
    }
    for (unsigned i = 0; i < EMBER_PICKUPS; ++i) {
        struct ember_pickup *p = &s->pickups[i];
        if (!p->alive || p->room != s->room_serial || p->kind < EMBER_DROP_RELIC ||
            p->kind == EMBER_DROP_GOLD ||
            p->kind == EMBER_DROP_EMBER || !within(s->player.x, s->player.y, p->x, p->y,
                ember_lighting[0].interact_radius)) continue;
        if (p->kind == EMBER_DROP_WORLD || p->kind == EMBER_DROP_CLEANSE) {
            if (p->kind == EMBER_DROP_WORLD) s->discoveries.world[p->id] = 1;
            else s->cleanse_tokens = 1;
            pickup_event(s, EMBER_PICKUP_ITEM, p->id, p->x, p->y);
            p->alive = 0; --s->pickup_count;
            return 1;
        }
        unsigned kind = p->kind == EMBER_DROP_RELIC ? EMBER_ITEM_RELIC :
            p->kind == EMBER_DROP_WEAPON ? EMBER_ITEM_WEAPON :
            p->kind == EMBER_DROP_PET_WEAPON ? EMBER_ITEM_PET_WEAPON : EMBER_ITEM_INSCRIPTION;
        if (inventory_owned(s, kind, p->id)) continue;
        pending_reset(s);
        s->pending_pickup = (int16_t)i;
        item_receive(s, (struct ember_choice){(uint8_t)kind, p->id, p->slot});
        return 1;
    }
    return 0;
}
static int hazard_contains(const struct ember_sim *s, ember_fixed x, ember_fixed y)
{
    const struct ember_hazards_row *h = &ember_hazards[s->config.stage];
    if (!s->config.stage)
        return x < (int64_t)s->world_width * h->region_percent / 100 ||
            y > (int64_t)s->world_height * (100 - h->region_percent) / 100;
    return within(x, y, s->hazard_point.x, s->hazard_point.y, h->radius);
}
static void modes_step(struct ember_sim *s, uint16_t input)
{
    const struct ember_modes_row *m = &ember_modes[s->config.mode];
    if (s->config.mode == EMBER_ROUTE && s->room_kind == EMBER_ROOM_MAIN)
        for (unsigned i = 0; i < s->hidden_count; ++i) {
            if (s->hidden[i].island != s->island || s->hidden[i].found) continue;
            int near = within(s->player.x, s->player.y, s->hidden[i].point.x,
                s->hidden[i].point.y, m->hidden_discover_radius);
            if (s->hidden[i].clue == 0 && near && (input & EMBER_J) &&
                !s->weapon_timer[s->player.main_weapon]) {
                unsigned w = s->player.main_weapon;
                int damage = ember_weapons[w].damage *
                    (100 + (s->player.weapon_level[w] - 1) *
                        ember_weapons[w].damage_per_level) / 100 *
                    s->attributes[EMBER_ATTACK] / 100;
                s->hidden[i].hp -= damage;
                s->weapon_timer[w] = (uint16_t)ember_weapons[w].cooldown;
                player_action(s, EMBER_ATTACKING, ember_system[0].attack_frames);
                s->player.facing8 = (uint8_t)direction8(s->hidden[i].point.x - s->player.x,
                    s->hidden[i].point.y - s->player.y);
                if (s->hidden[i].hp <= 0) rock_open(s, i);
                event(s, EMBER_EVENT_HIT, (unsigned)damage,
                    s->hidden[i].point.x, s->hidden[i].point.y);
                s->events.item[s->events.count - 1].damage_type =
                    (uint8_t)ember_weapons[w].element_index;
                s->events.item[s->events.count - 1].source_weapon = (uint8_t)w;
                s->events.item[s->events.count - 1].source_evolution = s->player.evolution[w];
            } else if (s->hidden[i].clue == 1 && !s->lamp_disabled &&
                within(s->player.x, s->player.y, s->hidden[i].point.x,
                    s->hidden[i].point.y, s->lamp_radius)) s->hidden[i].found = 1;
            else if (s->hidden[i].clue == 2 && s->pet_kind != 255 && near)
                s->hidden[i].found = 1;
        }
    if (s->room_kind == EMBER_ROOM_HIDDEN) { s->hazard_phase = 0; return; }
    if (s->stage_clear) {
        for (unsigned w = 0; w < 50; ++w) if (s->weapon_timer[w]) --s->weapon_timer[w];
        return;
    }
    const struct ember_hazards_row *h = &ember_hazards[s->config.stage];
    unsigned cycle = s->stage_frame / (unsigned)h->period;
    if (cycle != s->hazard_cycle) {
        s->hazard_cycle = cycle;
        s->hazard_point = s->config.stage == 2 ?
            (struct ember_point){s->player.x, s->player.y} : map_point(s);
    }
    unsigned tick = s->stage_frame % (unsigned)h->period;
    s->hazard_phase = tick < (unsigned)h->warning ? 1 :
        tick < (unsigned)(h->warning + h->active_frames) ? 2 : 0;
    s->region = (uint8_t)((s->player.x >= s->world_width / 2) +
        2 * (s->player.y >= s->world_height / 2));
    if (s->hazard_phase != 2) return;
    int damage_tick = s->config.stage == 2 || s->stage_frame % 60 == 0;
    if (hazard_contains(s, s->player.x, s->player.y)) {
        if (!s->config.stage) {
            ember_slow_apply(&s->player.defense, EMBER_SLOW_TIDE, h->slow_percent, h->slow_frames);
            memset(&s->player.defense.status[EMBER_IGNITE], 0,
                sizeof(s->player.defense.status[EMBER_IGNITE]));
        } else if (damage_tick) {
            player_hurt_resolved(s, h->damage, s->wave, s->hazard_point.x,
                s->hazard_point.y, (unsigned)h->damage_type, 0, 0, 0);
            if (h->status != 255) ember_status_apply(&s->player.defense, (unsigned)h->status,
                ember_statuses[h->status].duration, ember_statuses[h->status].strength);
        }
    }
    for (unsigned i = 0; i < EMBER_ENEMIES; ++i) {
        struct ember_enemy *e = &s->enemies[i];
        if (!e->alive || !hazard_contains(s, e->x, e->y)) continue;
        if (!s->config.stage) {
            ember_slow_apply(&e->defense, EMBER_SLOW_TIDE, h->slow_percent, h->slow_frames);
            memset(&e->defense.status[EMBER_IGNITE], 0, sizeof(e->defense.status[EMBER_IGNITE]));
            e->burn = 0;
        } else if (damage_tick) {
            struct ember_attack hit = {.base = h->damage, .attack = 100, .crit_damage = 150};
            hit.share[h->damage_type] = 100;
            ember_sim_hit(s, i, &hit);
            if (h->status != 255) ember_sim_status(s, i, (unsigned)h->status, 0);
        }
    }
}
