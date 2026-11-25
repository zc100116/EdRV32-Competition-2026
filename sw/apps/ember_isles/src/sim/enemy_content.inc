/* File: enemy_content.inc; gdd 5e: species AI, elite rules and phased bosses.
 * Included by sim.c; all attacks use its integer damage and stable pools.
 * Clock domain: fixed 60 Hz.
 */
unsigned ember_sim_spawn(struct ember_sim *s, unsigned kind, unsigned affix,
                          ember_fixed x, ember_fixed y)
{
    const struct ember_enemies_row *d = &ember_enemies[kind];
    for (unsigned i = 0; i < EMBER_ENEMIES; ++i)
        if (!s->enemies[i].alive && !s->enemies[i].retiring) {
        struct ember_enemy *e = &s->enemies[i];
        *e = (struct ember_enemy){0};
        /* Pool slot reuse starts a new target lifetime for hit and distinct-target rules. */
        s->hourglass_seen[i] = 0;
        for (unsigned shot_id = 0; shot_id < EMBER_SHOTS; ++shot_id)
            if (s->shots[shot_id].alive)
                s->shots[shot_id].hit_bits[i / 32] &= ~(1u << (i % 32));
        e->alive = 1; e->kind = (uint8_t)kind; e->affix = (uint8_t)affix;
        e->x = x; e->y = y;
        e->hp = d->hp * (100 + (s->config.difficulty >= 2 ?
            ember_difficulty[1].hp_percent : 0)) / 100;
        e->wave = s->wave;
        ember_defense_init(&e->defense, e->hp);
        e->defense.armor = d->armor;
        e->defense.rank = (uint8_t)d->rank;
        e->defense.posture = e->defense.posture_max = d->posture;
        e->defense.immune_break = (uint8_t)d->immune_break;
        e->defense.immune_pierce = (uint8_t)d->immune_pierce;
        e->defense.weakness = (uint8_t)d->weakness;
        e->defense.resistance[0] = d->fire_resist;
        e->defense.resistance[1] = d->tide_resist;
        e->defense.resistance[2] = d->star_resist;
        e->defense.resistance[3] = d->shadow_resist;
        if (affix) {
            e->defense.rank = 1;
            if (s->curses[1]) e->second_affix = (uint8_t)(affix % EMBER_AFFIXES_COUNT + 1);
            e->defense.tenacity = ember_affixes[affix - 1].tenacity;
            if (affix == 2 || e->second_affix == 2)
                e->defense.temporary[6] = ember_affixes[1].shield;
            if (affix == 7 || e->second_affix == 7) {
                e->defense.temporary[d->element_index] = ember_affixes[6].value;
                e->defense.shield_frames[d->element_index] = (uint16_t)ember_affixes[6].duration;
            }
        }
        if (affix && s->config.difficulty >= 6)
            elite_extra(e, (unsigned)ember_difficulty[5].extra_affixes);
        if (s->config.difficulty >= 8 && d->rank >= 2)
            e->defense.temporary[6] = e->hp * ember_difficulty[7].guardian_shield_percent / 100;
        ++s->alive_count;
        if (!e->defense.rank) ++s->ordinary_count[kind];
        if (s->alive_count > s->peaks[s->config.stage].enemies)
            s->peaks[s->config.stage].enemies = s->alive_count;
        return i;
    }
    fputs("ember enemy pool exhausted\n", stderr);
    abort();
}
static void enemy_projectile(struct ember_sim *s, struct ember_enemy *e,
                              uint16_t angle, int speed, int type, unsigned flags)
{
    const struct ember_enemies_row *d = &ember_enemies[e->kind];
    if (e->defense.status[EMBER_BLIND].frames && ember_random(&s->combat_rng) % 100 <
        (unsigned)ember_statuses[EMBER_BLIND].strength) return;
    struct ember_shot *p = shot(s, 6, e->x, e->y, d->damage,
        d->projectile_radius, d->projectile_life);
    e->attacking = (uint16_t)ember_system[0].attack_frames;
    enemy_present(e,EMBER_ENEMY_ATTACK);
    p->hostile = 1; p->weapon = (uint8_t)e->wave; p->enemy_kind = e->kind;
    p->damage_type = (uint8_t)type; p->hit_flags = (uint8_t)flags;
    p->enemy_increased = enemy_in_dark(s, e->x, e->y) ? ember_lighting[0].dark_damage : 0;
    p->vx = (ember_fixed)((int64_t)ember_cos(angle) * speed / 60);
    p->vy = (ember_fixed)((int64_t)ember_sin(angle) * speed / 60);
}
static void enemy_ground(struct ember_sim *s, struct ember_enemy *e, int effect, int radius)
{
    const struct ember_enemies_row *d = &ember_enemies[e->kind];
    struct ember_shot *p = shot(s, 2, e->x, e->y, d->ground_damage, radius, d->ground_life);
    enemy_present(e,EMBER_ENEMY_ATTACK);
    p->effect = (uint8_t)effect; p->enemy_kind = e->kind;
    p->weapon = (uint8_t)e->wave;
}
static int content_enemy(struct ember_sim *s, unsigned index)
{
    struct ember_enemy *e = &s->enemies[index];
    const struct ember_enemies_row *d = &ember_enemies[e->kind];
    ember_fixed tx, ty;
    enemy_target(s, e, &tx, &ty);
    ember_fixed dx = tx - e->x, dy = ty - e->y;
    if (!e->facing_lock) e->facing8 = (uint8_t)direction8(dx, dy);
    ++e->ai_timer;
    int speed = enemy_speed(s, e);
    if ((enemy_affix(e, 5)) &&
        within(e->x, e->y, s->player.x, s->player.y, ember_affixes[4].radius))
        s->lamp_radius = s->lamp_radius * (100 - ember_affixes[4].value) / 100;
    if ((enemy_affix(e, 8)) && e->ai_timer % ember_affixes[7].duration == 0) {
        e->x = s->player.x + ember_affixes[7].teleport_radius * ember_cos((uint16_t)ember_random(&s->spawn_rng));
        e->y = s->player.y + ember_affixes[7].teleport_radius * ember_sin((uint16_t)ember_random(&s->spawn_rng));
    }
    if (e->illusion) {
        e->vx = e->vy = 0;
        if (e->ai_timer % d->illusion_interval == 0)
            for (unsigned n = 0; n < (unsigned)d->illusion_shots; ++n)
                enemy_projectile(s, e, (uint16_t)(n * 65536 / d->illusion_shots), d->radial_speed, 3, 0);
        return 1;
    }
    if (d->rank >= 2) {
        unsigned stage = e->hp * 100LL < e->defense.max_hp * (int64_t)d->phase_second_percent ? 2 :
            e->hp * 100LL < e->defense.max_hp * (int64_t)d->phase_first_percent ? 1 : 0;
        if (d->rank == 2) stage = e->hp * 100LL < e->defense.max_hp * (int64_t)d->miniboss_phase_percent;
        if (stage != e->stage) {
            e->stage = (uint8_t)stage;
            if (d->ai==18 && stage) enemy_present(e,stage==1?EMBER_ENEMY_TIDE_EBB:EMBER_ENEMY_TIDE_BLACKTIDE);
            if (d->rank == 3) e->defense.invulnerable = (uint16_t)d->phase_invulnerable;
            if (d->ai == 19 && stage == 2) {
                for (unsigned i = 0; i < 8; ++i) s->pillars[i].lit = 0;
                s->boss_blackout = 1;
                s->lamp_disabled = 1;
            }
            if (d->ai == 20 && stage == 1)
                for (unsigned i = 0; i < (unsigned)d->pillar_count; ++i) {
                    s->pillars[i].lit = 0;
                    s->pillars[i].x = clamp(e->x + d->pillar_radius *
                        ember_cos((uint16_t)(i * 65536 / d->pillar_count)), 0, s->world_width);
                    s->pillars[i].y = clamp(e->y + d->pillar_radius *
                        ember_sin((uint16_t)(i * 65536 / d->pillar_count)), 0, s->world_height);
                }
        }
    }
    int interval = d->attack_cooldown;
    if (d->rank == 2 && e->stage) interval = interval * 100 / (100 + d->phase_attack_more);
    if (enemy_affix(e, 6) && e->hp * 100LL <
        e->defense.max_hp * (int64_t)ember_affixes[5].threshold_percent)
        interval = interval * 100 / (100 + ember_affixes[5].value);
    if (d->rank == 3 && e->ai_timer >= (uint32_t)d->enrage_frames) interval = interval * 100 / (100 + d->enrage_attack_more);
    if (s->config.mode == EMBER_ROUTE && e->affix && d->pet_kind != 255 &&
        e->hp * 100LL <= e->defense.max_hp * (int64_t)ember_system[0].elite_capture_percent)
        e->capturable = 1;
    if (e->capturable) { e->vx = e->vy = 0; return 1; }
    if (e->kind < 3) return 0;
    velocity(dx, dy, speed, &e->vx, &e->vy);
    switch (d->ai) {
    case 3: e->defense.front_block = 1; e->defense.block_strength = d->block_percent; break;
    case 4: break; /* 漂浮水母的死亡雾在 content_death。 */
    case 5:
        if (e->ai_timer % interval == 0 && within(e->x, e->y,
            s->player.x, s->player.y, d->skill_radius)) {
            ember_slow_apply(&s->player.defense, EMBER_SLOW_VINE,
                d->slow_percent, d->slow_frames);
        }
        break;
    case 6:
        if (e->ai_timer % interval == 0 && within(e->x, e->y,
            s->player.x, s->player.y, d->shock_radius))
            ember_status_apply(&s->player.defense, EMBER_SHOCK, d->status_frames, 100);
        break;
    case 7: case 12:
        if (e->ai_timer % interval < (unsigned)d->charge_frames) e->vx = e->vy = 0;
        else velocity(dx, dy, speed * d->charge_speed / d->speed, &e->vx, &e->vy);
        if (d->ai == 7 && within(e->x, e->y, s->player.x, s->player.y, d->contact_status_radius))
            ember_status_apply(&s->player.defense, EMBER_BREAK_ARMOR, d->status_frames, 100);
        break;
    case 8: case 13: {
        if (within(e->x, e->y, s->player.x, s->player.y, d->keep_distance)) e->vx = e->vy = 0;
        if (e->ai_timer % interval == 0) {
            struct ember_shot *p = shot(s, 6, e->x, e->y, d->damage, d->projectile_radius, d->projectile_life);
            e->attacking = (uint16_t)ember_system[0].attack_frames;
    enemy_present(e,EMBER_ENEMY_ATTACK);
    p->hostile = 1; p->weapon = (uint8_t)e->wave; p->enemy_kind = e->kind;
            p->damage_type = d->ai == 13 ? EMBER_DAMAGE_TRUE : EMBER_DAMAGE_STAR;
            p->enemy_increased = enemy_in_dark(s, e->x, e->y) ?
                ember_lighting[0].dark_damage : 0;
            p->pierce = d->ai == 8 ? d->pass_through : 0;
            velocity(dx, dy, d->projectile_speed, &p->vx, &p->vy);
        }
        break;
    }
    case 9:
        e->vx = e->vy = 0;
        if (e->ai_timer % interval == 0)
            for (unsigned n = 0; n < (unsigned)d->shot_count; ++n)
                enemy_projectile(s, e, (uint16_t)(n * 65536 / d->shot_count), d->radial_speed, 3, 0);
        break;
    case 10: case 11: break;
    case 14:
        if (e->ai_timer % d->ground_interval == 0) enemy_ground(s, e, 6, d->ground_radius);
        break;
    case 15:
        e->defense.front_block = 1; e->defense.block_strength = d->block_percent;
        if (e->stage && e->ai_timer % interval == 0) {
            enemy_present(e,EMBER_ENEMY_SUMMON);
            ember_sim_spawn(s, 0, 0, e->x + d->summon_offset * EMBER_Q, e->y);
        }
        break;
    case 16:
        e->vx = e->vy = 0;
        if (e->ai_timer % interval == 0) enemy_ground(s, e, 5, d->ground_radius);
        break;
    case 17:
        e->defense.active_block = e->ai_timer % d->block_cycle < (unsigned)d->block_frames;
        e->defense.block_strength = d->block_percent;
        e->defense.vulnerability = e->defense.active_block ? 0 : d->vulnerability;
        break;
    case 18:
        if (e->ai_timer % interval == 0) {
            if (!e->stage) {
                enemy_present(e,EMBER_ENEMY_TIDE_SWEEP_COLUMN);
                if (within(e->x, e->y, s->player.x, s->player.y, d->tail_radius))
                    player_hurt_typed(s, d->tail_damage, e->wave, e->x, e->y, 2, 0);
                struct ember_shot *p = shot(s, 2, s->player.x, s->player.y, d->wave_damage, d->wave_radius, d->wave_life);
                p->effect = 7; p->enemy_kind = e->kind; p->weapon = (uint8_t)e->wave;
            } else if (e->stage == 1) {
                e->defense.vulnerability = d->vulnerability;
                enemy_ground(s, e, 8, d->ground_radius);
                enemy_present(e,EMBER_ENEMY_TIDE_VORTEX);
            } else {
                enemy_present(e,EMBER_ENEMY_TIDE_BLACKTIDE);
                if (s->player.x < s->world_width / 2 && !s->in_light)
                    player_hurt_typed(s, d->dark_damage, e->wave, e->x, e->y, 4, 0);
            }
        }
        break;
    case 19:
        if (e->ai_timer % interval == 0)
            for (unsigned n = 0; n < (unsigned)d->shot_count; ++n)
                enemy_projectile(s, e, (uint16_t)(n * 65536 / d->shot_count + e->ai_timer * d->spiral_step), d->radial_speed, 3, 0);
        if (e->stage == 1) {
            /* The real entity retains a shadow flag; decoys are separate attack sources. */
            e->real_shadow = 1;
            if (e->ai_timer % d->clone_interval == 0) {
                unsigned decoy = ember_sim_spawn(s, e->kind, 0, e->x + d->clone_offset * EMBER_Q, e->y);
                s->enemies[decoy].illusion = 1;
            }
        }
        break;
    case 20:
        if (e->stage == 1) {
            unsigned lit = 0;
            for (unsigned i = 0; i < (unsigned)d->pillar_count; ++i) lit += !!s->pillars[i].lit;
            e->defense.vulnerability = (int)lit * d->pillar_vulnerability;
        }
        if (e->ai_timer % interval == 0) {
            if (e->stage < 2)
                for (unsigned n = 0; n < (unsigned)d->shot_count; ++n)
                    enemy_projectile(s, e, (uint16_t)(n * 65536 / d->shot_count), d->radial_speed, 1, 0);
            else {
                struct ember_shot *p = shot(s, 2, s->player.x, s->player.y, d->rain_damage, d->rain_radius, d->rain_life);
                p->effect = 9; p->enemy_kind = e->kind; p->weapon = (uint8_t)e->wave;
            }
        }
        break;
    }
    return 1;
}
static void content_death(struct ember_sim *s, unsigned index, unsigned depth,
                          unsigned source_weapon, int damage)
{
    struct ember_enemy copy = s->enemies[index];
    struct ember_enemy *e = &copy;
    const struct ember_enemies_row *d = &ember_enemies[e->kind];
    unsigned ai = (unsigned)d->ai;
    if (s->fuse_target == (int)index) { s->fuse_target = -1; s->fuse_stacks = 0; }
    if (ember_characters[s->player.character].mechanism == 6 && s->stealth)
        s->player.cooldown_k = 0;
    if (s->blessings[3] && !player_in_light_zone(s))
        s->oil = minimum(10000, s->oil + (ember_blessings[3].value * (100 + relic(s, R_NIGHT)) / 100));
    if (s->resonances[3] && e->burn && e->defense.status[EMBER_CORRODE].frames &&
        depth < 3u + s->trigger_bonus) {
        struct ember_shot *ground = shot(s, 2, e->x, e->y, ember_resonances[3].damage, ember_resonances[3].radius, ember_resonances[3].lifetime);
        ground->effect = 2; ground->depth = (uint8_t)(depth + 1);
    }
    if (s->resonances[6] && e->defense.frozen && depth < 3u + s->trigger_bonus) {
        struct ember_shot *ground = shot(s, 2, e->x, e->y, ember_resonances[6].damage, ember_resonances[6].radius, ember_resonances[6].lifetime);
        ground->effect = 3; ground->depth = (uint8_t)(depth + 1);
    }
    if (source_weapon && inscription(s, source_weapon - 1, 12))
        inherited_area(s, e->x, e->y, ember_inscriptions[12].value2, damage * ember_inscriptions[12].value / 100, depth + 1);
    if (s->blessings[4] && e->affix) {
        unsigned choices[38], count = 0;
        for (unsigned n = 0; n < EMBER_RELICS_COUNT; ++n)
            if (!strcmp(ember_relics[n].rarity, "common") && !s->player.relic_level[n])
                if (item_allowed(s, EMBER_ITEM_RELIC, n)) choices[count++] = n;
        if (count) drop_resource(s, EMBER_DROP_RELIC,
            choices[ember_random(&s->loot_rng) % count], 0, 0, e->x, e->y);
    }
    if (ai == 4) enemy_ground(s, e, 4, d->ground_radius);
    if (ai == 10) enemy_ground(s, e, 6, d->ground_radius);
    if ((enemy_affix(e, 3)) && depth < 3u + s->trigger_bonus)
        for (unsigned n = 0; n < (unsigned)ember_affixes[2].split_count; ++n)
            split_spawn(s, e, n);
}
static void skill_reflect(struct ember_sim *s, ember_fixed x, ember_fixed y, int damage)
{
    int target = -1;
    int64_t dist = INT64_MAX;
    for (unsigned i = 0; i < EMBER_ENEMIES; ++i) if (s->enemies[i].alive) {
        int64_t d = distance2(x, y, s->enemies[i].x, s->enemies[i].y);
        if (d < dist) { dist = d; target = (int)i; }
    }
    if (target < 0) return;
    inherited_hit(s, (unsigned)target, damage, 1);
    if (s->resonances[8]) ember_sim_status(s, (unsigned)target, EMBER_CORRODE, 1);
}
