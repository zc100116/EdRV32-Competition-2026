/* File: content.inc; gdd 3.3, 4.6 and 5b: concrete character/build/pet rules.
 * Included by sim.c to share its deterministic hit, movement and pool operations.
 * Clock domain: fixed 60 Hz.
 */
static void heal(struct ember_sim *s, int amount)
{
    int64_t healing = (int64_t)amount * s->attributes[EMBER_HEALING] *
        (100 - (s->curses[3] ? ember_contracts[3].value : 0)) + s->healing_fraction;
    amount = (int32_t)(healing / 10000);
    s->healing_fraction = (int32_t)(healing % 10000);
    int overflow = maximum(0, s->player.hp + amount - s->player.max_hp);
    s->player.hp = minimum(s->player.max_hp, s->player.hp + amount);
    if (s->resonances[8] && overflow) {
        s->player.defense.temporary[6] += overflow;
        s->player.defense.shield_frames[6] = (uint16_t)ember_resonances[8].lifetime;
    }
}
void ember_sim_character(struct ember_sim *s, unsigned id)
{
    s->player.character = (uint8_t)id;
    memset(s->player.weapon_level, 0, sizeof(s->player.weapon_level));
    s->player.main_weapon = (uint8_t)ember_characters[id].initial_weapon;
    s->player.sub_weapon = (uint8_t)(s->player.main_weapon == 0 ? 1 : 0);
    s->player.weapon_level[s->player.main_weapon] = 1;
    s->player.weapon_level[s->player.sub_weapon] = 1;
    ember_sim_attributes(s);
    s->player.hp = s->player.max_hp;
}
void ember_sim_pet(struct ember_sim *s, unsigned kind, unsigned weapon)
{
    s->pet_kind = (uint8_t)kind;
    s->discoveries.pets[kind] = 1;
    if (weapon != 255) s->discoveries.pet_weapons[weapon] = 1;
    s->pet_level = 1;
    if (s->player.pet_weapon != weapon) weapon_change_event(s, EMBER_WEAPON_SLOT_PET, weapon);
    s->player.pet_weapon = (uint8_t)weapon;
    if (weapon != 255 && !s->player.pet_weapon_level[weapon])
        s->player.pet_weapon_level[weapon] = 1;
    s->pet.x = s->player.x + ember_pets[kind].follow_x * EMBER_Q;
    s->pet.y = s->player.y;
    struct ember_pet_weapons_row data = pet_weapon_data(s);
    s->pet.category = (uint8_t)data.category;
    s->pet.damage = data.damage;
    s->pet.cooldown = (uint16_t)data.attack_cooldown;
    ember_sim_attributes(s);
}
void ember_sim_blessing(struct ember_sim *s, unsigned id)
{ s->blessings[id] = 1; s->discoveries.blessings[id] = 1; }
void ember_sim_resonance(struct ember_sim *s, unsigned id)
{ s->resonances[id] = 1; s->discoveries.resonances[id] = 1; }
void ember_sim_contract(struct ember_sim *s, unsigned curse, unsigned reward)
{
    s->curses[curse] = 1;
    switch (reward) {
    case 0: {
        unsigned choices[38], count = 0;
        for (unsigned i = 0; i < EMBER_RELICS_COUNT; ++i)
            if (!strcmp(ember_relics[i].rarity, "legendary") &&
                !inventory_owned(s, EMBER_ITEM_RELIC, i)) choices[count++] = i;
        s->reward_relic = (uint8_t)choices[ember_random(&s->loot_rng) % count];
        s->has_reward_relic = 1;
        break;
    }
    case 1: ++s->free_evolution; break;
    case 2: s->guaranteed_resonance = 1; break;
    case 3: {
        unsigned choices[18], count = 0;
        for (unsigned i = 0; i < EMBER_INSCRIPTIONS_COUNT; ++i)
            if (!strcmp(ember_inscriptions[i].rarity, "rare") &&
                !inventory_owned(s, EMBER_ITEM_INSCRIPTION, i) &&
                (rune_allowed(s, i, s->player.main_weapon) ||
                 (s->player.sub_weapon != 255 && rune_allowed(s, i, s->player.sub_weapon)) ||
                 (s->player.pet_weapon != 255 && rune_allowed(s, i, 50u + s->player.pet_weapon))))
                choices[count++] = i;
        s->reward_inscription = (uint8_t)choices[ember_random(&s->loot_rng) % count];
        s->has_reward_inscription = 1;
        s->gold += (uint32_t)ember_contracts[3].reward_gold;
        break;
    }
    case 4: s->contract_cap_choice = 1; break;
    case 5: s->pet_level = (uint8_t)ember_pets[s->pet_kind].level_max; break;
    }
    ember_sim_attributes(s);
    s->player.hp = minimum(s->player.hp, s->player.max_hp);
}
void ember_sim_cleanse(struct ember_sim *s, unsigned curse)
{
    s->curses[curse] = 0;
    ember_sim_attributes(s);
}
void ember_sim_evolve(struct ember_sim *s, unsigned weapon, unsigned branch)
{
    s->player.evolution[weapon] = (uint8_t)branch;
}
static void summon(struct ember_sim *s, unsigned kind, int life, ember_fixed x, ember_fixed y)
{
    for (unsigned i = 0; i < 8; ++i) if (!s->summons[i].life) {
        s->summons[i].room = s->room_serial;
        s->summons[i].x = x;
        s->summons[i].y = y;
        const struct ember_summons_row *d = &ember_summons[kind];
        s->summons[i].hp = d->hp;
        s->summons[i].armor = d->armor + (d->inherit_armor ? s->attributes[EMBER_ARMOR] : 0);
        s->summons[i].damage = d->damage * (kind == 2 ?
            100 + (s->pet_level - 1) * ember_pets[0].damage_per_level : 100) / 100;
        s->summons[i].base_armor = s->summons[i].armor;
        s->summons[i].base_damage = s->summons[i].damage;
        s->summons[i].life = (uint16_t)life;
        s->summons[i].kind = (uint8_t)kind;
        s->summons[i].timer = 0;
        return;
    }
    fputs("ember summon pool exhausted\n", stderr);
    abort();
}
static void skill_hit_tags(struct ember_sim *s, unsigned index, unsigned type, int damage,
                             unsigned status, uint32_t tags, unsigned depth)
{
    struct ember_attack hit = {.base = damage, .attack = s->attributes[EMBER_ATTACK],
        .crit = s->attributes[EMBER_CRIT], .crit_damage = s->attributes[EMBER_CRIT_DAMAGE],
        .depth = (uint8_t)depth};
    hit.share[type] = 100;
    player_modifiers(s, index, &hit, tags);
    content_before_hit(s, index, 255, &hit);
    struct ember_damage_result result = ember_sim_hit(s, index, &hit);
    player_hit_effects(s, index, result, tags);
    content_after_hit(s, index, 255, result, depth);
    if (s->enemies[index].alive && status < EMBER_STATUS_COUNT)
        ember_sim_status(s, index, status, depth);
}
static void skill_hit(struct ember_sim *s, unsigned index, unsigned type, int damage,
                       unsigned status)
{
    skill_hit_tags(s, index, type, damage, status, TAG_SINGLE | TAG_PROJECTILE, 0);
}
static void skill_area_tags(struct ember_sim *s, ember_fixed x, ember_fixed y, int radius,
                             int damage, unsigned type, unsigned status, uint32_t tags)
{
    radius = radius * s->attributes[EMBER_AREA] / 100;
    for (unsigned i = 0; i < EMBER_ENEMIES; ++i)
        if (s->enemies[i].alive && within(x, y, s->enemies[i].x, s->enemies[i].y, radius))
            skill_hit_tags(s, i, type, damage, status, tags, 0);
}
static void skill_area(struct ember_sim *s, ember_fixed x, ember_fixed y, int radius,
                        int damage, unsigned type, unsigned status)
{
    skill_area_tags(s, x, y, radius, damage, type, status, TAG_AREA | TAG_GROUP);
}
static void content_skill(struct ember_sim *s, unsigned key)
{
    struct ember_player *p = &s->player;
    const struct ember_characters_row *c = &ember_characters[p->character];
    int target = nearest(s);
    ember_fixed tx = target >= 0 ? s->enemies[target].x :
        p->x + ember_system[0].shadow_default_aim_range * EMBER_Q;
    ember_fixed ty = target >= 0 ? s->enemies[target].y : p->y;
    player_action(s, EMBER_CAST, ember_system[0].cast_frames);
    if (key == 2) s->ultimate_time = (uint16_t)c->ultimate_duration;
    else if (key == 1) s->skill_time = (uint16_t)c->skill_duration;
    switch (c->mechanism) {
    case 0: /* 铸铁匠 */
        if (key == 0) {
            velocity(tx - p->x, ty - p->y, p->speed * c->skill_k_speed_percent / 100,
                &s->dash_vx, &s->dash_vy);
            p->dash = (uint16_t)c->skill_k_frames;
            skill_area_tags(s, p->x, p->y, c->skill_k_radius, c->skill_damage, 0,
                EMBER_STATUS_COUNT, TAG_AREA | TAG_GROUP | TAG_MELEE);
            for (unsigned i = 0; i < EMBER_ENEMIES; ++i)
                if (s->enemies[i].alive && within(p->x, p->y,
                    s->enemies[i].x, s->enemies[i].y, c->skill_k_radius)) {
                    s->enemies[i].taunted = (uint16_t)c->skill_k_control_frames;
                    ember_fixed vx, vy;
                    velocity(s->enemies[i].x - p->x, s->enemies[i].y - p->y,
                        c->skill_k_knockback_speed, &vx, &vy);
                    s->enemies[i].x += vx * c->skill_k_knockback_frames;
                    s->enemies[i].y += vy * c->skill_k_knockback_frames;
                }
        } else if (key == 2)
            for (int n = 0; n < c->ultimate_count; ++n)
                summon(s, 0, c->ultimate_duration, p->x +
                    (n * 2 - c->ultimate_count + 1) * ember_summons[0].spawn_spacing * EMBER_Q,
                    p->y);
        break;
    case 1: /* 碎浪者 */
        if (key == 0) for (int n = 0; n < c->skill_k_count; ++n) {
            ember_fixed vx, vy;
            velocity(tx - p->x, ty - p->y, c->skill_k_step_speed, &vx, &vy);
            p->x += vx * c->skill_k_step_frames; p->y += vy * c->skill_k_step_frames;
            skill_area_tags(s, p->x, p->y, c->skill_k_radius, c->skill_damage, 2,
                EMBER_CHILL, TAG_AREA | TAG_GROUP | TAG_MELEE);
        }
        if (key == 1) {
            p->defense.temporary[2] += c->skill_l_value;
            p->defense.shield_frames[2] = (uint16_t)c->skill_duration;
            s->tide_shield = 1;
        }
        if (key == 2) for (unsigned i = 0; i < EMBER_ENEMIES; ++i) {
            struct ember_enemy *e = &s->enemies[i];
            if (e->alive && within(p->x, p->y, e->x, e->y,
                c->ultimate_radius * s->attributes[EMBER_AREA] / 100) &&
                (int64_t)(e->x - p->x) * (tx - p->x) +
                (int64_t)(e->y - p->y) * (ty - p->y) > 0) {
                skill_hit_tags(s, i, 2, c->ultimate_damage, EMBER_CHILL, TAG_AREA | TAG_GROUP, 0);
                if (e->defense.rank < 2) e->defense.frozen = (uint16_t)c->ultimate_freeze_frames;
                else {
                    e->defense.posture = maximum(0, e->defense.posture -
                        e->defense.posture_max * c->ultimate_posture_percent / 100);
                    if (!e->defense.posture)
                        e->defense.broken = (uint16_t)c->ultimate_broken_frames;
                }
            }
        }
        break;
    case 2: /* 潮汐猎手 */
        if (key == 0) {
            velocity(tx - p->x, ty - p->y, p->speed * c->skill_k_speed_percent / 100,
                &s->dash_vx, &s->dash_vy);
            p->dash = p->invulnerable = (uint16_t)c->skill_k_frames;
            s->next_crit = 1;
        }
        if (key == 1 && target >= 0) {
            s->marked_target = (int16_t)target;
            s->enemies[target].marked = s->enemies[target].hunter_mark =
                (uint16_t)c->skill_duration;
        }
        break;
    case 3: /* 焰铳手 */
        if (key == 0) s->loaded = 1;
        if (key == 1) {
            struct ember_shot *mine = shot(s, 4, p->x, p->y, c->skill_l_damage,
                c->skill_l_radius, c->skill_l_lifetime);
            mine->trigger_radius = (uint16_t)c->skill_l_trigger_radius;
            velocity(p->x - tx, p->y - ty, p->speed * c->skill_l_speed_percent / 100,
                &s->dash_vx, &s->dash_vy);
            p->dash = (uint16_t)c->skill_l_move_frames;
        }
        if (key == 2 && target >= 0) for (int n = 0; n < c->ultimate_count; ++n) {
            struct ember_enemy *e = &s->enemies[target];
            if (e->alive) skill_hit(s, (unsigned)target, 1,
                c->ultimate_damage * (100 + c->ultimate_value *
                    (e->defense.max_hp - e->hp) / e->defense.max_hp) / 100, EMBER_IGNITE);
        }
        break;
    case 4: /* 守火人 */
        if (key == 0) {
            velocity(tx - p->x, ty - p->y, p->speed * c->skill_k_speed_percent / 100,
                &s->dash_vx, &s->dash_vy);
            p->dash = (uint16_t)c->skill_k_frames; s->flame_dash = 1;
        }
        if (key == 1) for (int n = 0; n < c->skill_l_count; ++n) {
            struct ember_shot *seed = shot(s, 4,
                p->x + (n * 2 - c->skill_l_count + 1) * c->skill_l_spread * EMBER_Q / 2,
                p->y, c->skill_l_damage, c->skill_l_radius, c->skill_l_lifetime);
            seed->trigger_radius = (uint16_t)c->skill_l_trigger_radius;
        }
        if (key == 2) skill_area(s, p->x, p->y, c->ultimate_radius,
            c->ultimate_damage, 1, EMBER_IGNITE);
        break;
    case 5: /* 观星者 */
        if (key == 0) {
            struct ember_shot *zone = shot(s, 2, p->x, p->y, 0,
                c->skill_k_radius, c->skill_k_lifetime);
            zone->effect = 1;
            ember_fixed vx, vy;
            velocity(tx - p->x, ty - p->y, c->skill_k_step_speed, &vx, &vy);
            p->x += vx * c->skill_k_step_frames; p->y += vy * c->skill_k_step_frames;
            zone = shot(s, 2, p->x, p->y, 0, c->skill_k_radius, c->skill_k_lifetime);
            zone->effect = 1;
        }
        if (key == 1) {
            int done = 0;
            for (unsigned i = 0; i < EMBER_ENEMIES && done < c->skill_l_count; ++i)
                if (s->enemies[i].alive && within(p->x, p->y,
                    s->enemies[i].x, s->enemies[i].y, c->skill_l_radius)) {
                    skill_hit(s, i, 3, c->skill_l_damage, EMBER_STATUS_COUNT);
                    ember_status_apply(&s->enemies[i].defense, EMBER_SHOCK,
                        ember_statuses[EMBER_SHOCK].duration, 100);
                    ++done;
                }
        }
        break;
    case 6: /* 无名者 */
        if (key == 0 && target >= 0) {
            struct ember_enemy *e = &s->enemies[target];
            ember_fixed vx, vy;
            const uint16_t angles[8] = {16384,8192,0,57344,49152,40960,32768,24576};
            velocity(ember_cos(angles[e->facing8]), ember_sin(angles[e->facing8]),
                c->skill_k_step_speed, &vx, &vy);
            p->x = e->x - vx * c->skill_k_step_frames;
            p->y = e->y - vy * c->skill_k_step_frames;
            s->next_crit = 1;
            e->facing_lock = (uint16_t)c->facing_lock_frames;
        }
        if (key == 1) p->hp -= p->hp * c->skill_l_value / 100;
        if (key == 2) {
            s->stealth = (uint16_t)c->ultimate_duration;
            s->saved_oil = s->oil; s->saved_pillars = 0;
            for (unsigned i = 0; i < 8; ++i) s->saved_pillars |= s->pillars[i].lit << i;
            s->oil = 0;
            for (unsigned i = 0; i < 8; ++i)
                if (within(p->x, p->y, s->pillars[i].x, s->pillars[i].y, c->ultimate_radius))
                    s->pillars[i].lit = 0;
        }
        break;
    case 7: /* 灯匠 */
        if (key == 0) summon(s, 1, c->skill_k_lifetime, p->x, p->y);
        if (key == 1) {
            for (unsigned i = 0; i < 8; ++i) if (s->summons[i].life &&
                s->summons[i].room == s->room_serial &&
                within(p->x, p->y, s->summons[i].x, s->summons[i].y, c->skill_l_radius)) {
                s->summons[i].hp = ember_summons[s->summons[i].kind].hp;
                s->summons[i].armor = s->summons[i].base_armor + c->skill_l_value2;
                s->summons[i].damage = s->summons[i].base_damage * (100 + c->skill_l_value) / 100;
            }
            p->defense.permanent_shield = p->defense.shield_max;
        }
        break;
    }
    p->facing8 = (uint8_t)direction8(tx - p->x, ty - p->y);
    p->facing_frame = (uint8_t)direction_frame(p->facing8);
    p->flip_x = p->facing8 >= 5;
}
static void content_before_hit(struct ember_sim *s, unsigned index,
                               unsigned weapon, struct ember_attack *h)
{
    struct ember_enemy *e = &s->enemies[index];
    const struct ember_characters_row *c = &ember_characters[s->player.character];
    unsigned character = (unsigned)c->mechanism;
    int curses = 0;
    for (unsigned i = 0; i < 6; ++i) curses += !!s->curses[i];
    if (curses && relic(s, R_DARK_HEART)) {
        for (int i = 0; i < curses; ++i)
            h->base = h->base * (100 + relic(s, R_DARK_HEART)) / 100;
    }
    if (s->next_crit && weapon < EMBER_WEAPONS_COUNT &&
        (character != 2 || s->weapon_system[weapon].category == EMBER_BOW ||
         s->weapon_system[weapon].category == EMBER_CROSSBOW) &&
        (character != 3 || tagged(weapon, "projectile"))) {
        h->flags |= EMBER_FORCE_CRIT; s->next_crit = 0;
    }
    if (character == 2) h->crit = minimum(100 + s->cap_raise[EMBER_CRIT],
        h->crit + minimum(ember_characters[s->player.character].moving_crit_maximum,
            s->moving_frames * talent_passive(s, c->moving_crit_per_second, 3) / 60));
    if (character == 6 && !s->in_light)
        h->crit_damage += talent_passive(s, c->passive_value, 1) *
            (100 + relic(s, R_NIGHT)) / 100;
    if (s->dash_buff && s->blessings[1]) h->increased += ember_blessings[1].value;
    if (s->blessings[8]) {
        unsigned count = 0;
        for (unsigned i = 0; i < EMBER_ENEMIES; ++i)
            count += s->enemies[i].alive && within(s->player.x, s->player.y,
                s->enemies[i].x, s->enemies[i].y, ember_blessings[8].radius);
        h->increased += minimum(ember_blessings[8].value2,
            (int)count / ember_blessings[8].value3 * ember_blessings[8].value);
    }
    if (s->blessings[9] && e->hp == e->defense.max_hp) h->base = h->base * (100 + ember_blessings[9].value) / 100;
    if (s->blessings[0]) h->element_increased[EMBER_DAMAGE_FIRE] +=
        (s->attributes[EMBER_TIDE_DAMAGE] - 100) * ember_blessings[0].value / 100;
    if (s->resonances[0]) h->element_increased[EMBER_DAMAGE_FIRE] +=
        (s->attributes[EMBER_TIDE_DAMAGE] - 100) * ember_resonances[0].value / 100;
    if (s->resonances[1] && e->burn) h->element_increased[EMBER_DAMAGE_IRON] +=
        s->attributes[EMBER_EMBER_DAMAGE] - 100;
    if (s->resonances[1] && (h->flags & EMBER_DOT)) h->element_increased[EMBER_DAMAGE_FIRE] +=
        e->defense.status[EMBER_BREAK_ARMOR].stacks * ember_resonances[1].value;
    if (s->resonances[7]) h->element_increased[EMBER_DAMAGE_STAR] +=
        s->attributes[EMBER_ARMOR] * ember_resonances[7].value / 100;
    if (s->resonances[9] && !(s->in_light && relic(s, R_NIGHT)))
        h->element_increased[s->in_light ? EMBER_DAMAGE_SHADOW : EMBER_DAMAGE_STAR] +=
            ember_resonances[9].value * (!s->in_light ? 100 + relic(s, R_NIGHT) : 100) / 100;
    if (character == 6 && s->skill_time) h->leech += c->skill_l_value2;
    if (weapon < EMBER_WEAPONS_COUNT && s->player.evolution[weapon] == 2 &&
        s->weapon_system[weapon].category == EMBER_STAFF) {
        unsigned status = ember_weapons[weapon].element_index == 1 ? EMBER_IGNITE :
            ember_weapons[weapon].element_index == 2 ? EMBER_WET :
            ember_weapons[weapon].element_index == 0 ? EMBER_BREAK_ARMOR :
            ember_weapons[weapon].element_index == 3 ? EMBER_SHOCK : EMBER_CORRODE;
        h->base += h->base * e->defense.status[status].stacks *
            ember_weapons[weapon].evo_b_status_damage_percent / 100;
        e->defense.status[status] = (struct ember_status_state){0};
        e->burn = e->defense.status[EMBER_IGNITE].frames;
    }
}
static void content_after_hit(struct ember_sim *s, unsigned index, unsigned weapon,
                              struct ember_damage_result r, unsigned depth)
{
    struct ember_enemy *e = &s->enemies[index];
    const struct ember_characters_row *c = &ember_characters[s->player.character];
    unsigned character = (unsigned)c->mechanism;
    if (!r.damage && !r.absorbed) return;
    if (weapon < EMBER_WEAPONS_COUNT && s->player.evolution[weapon] == 1 &&
        s->weapon_system[weapon].category == EMBER_BLADES &&
        s->hit_count[weapon] % ember_weapons[weapon].evo_a_interval == 0 && depth < 3u + s->trigger_bonus) {
        const struct ember_weapons_row *w = &ember_weapons[weapon];
        int damage = w->damage * (100 + (s->player.weapon_level[weapon] - 1) *
            w->damage_per_level) / 100;
        for (int n = 0; n < w->evo_a_count; ++n) {
            struct ember_shot *blade = shot(s, 0, s->player.x, s->player.y,
                damage, w->projectile_radius, w->evo_a_duration);
            blade->weapon = (uint8_t)weapon;
            blade->depth = (uint8_t)(depth + 1);
            blade->speed = w->evo_a_speed;
            blade->vx = ember_cos((uint16_t)(n * 65536 / w->evo_a_count)) * w->evo_a_speed / 60;
            blade->vy = ember_sin((uint16_t)(n * 65536 / w->evo_a_count)) * w->evo_a_speed / 60;
        }
    }
    if (e->alive && character == 1 && weapon < EMBER_WEAPONS_COUNT && tagged(weapon, "melee"))
        ember_sim_status(s, index, EMBER_CHILL, depth);
    if (e->alive && character == 6 && s->skill_time)
        ember_sim_status(s, index, EMBER_CORRODE, depth);
    if (character == 3 && e->alive && !depth) {
        if (s->fuse_target != (int)index) { s->fuse_target = (int16_t)index; s->fuse_stacks = 0; }
        if (s->fuse_stacks == c->passive_value) {
            s->fuse_stacks = 0;
            e->defense.status[EMBER_IGNITE] = (struct ember_status_state){0};
            skill_hit_tags(s, index, 1,
                r.damage * talent_passive(s, c->passive_value2, 2) / 100, EMBER_STATUS_COUNT,
                TAG_SINGLE, depth + 1);
        } else ++s->fuse_stacks;
    }
    if (weapon < EMBER_WEAPONS_COUNT && e->alive && !depth) {
        unsigned category = s->weapon_system[weapon].category;
        if (s->player.evolution[weapon] == 2 && category == EMBER_CROSSBOW)
            ember_sim_status(s, index, EMBER_SHOCK, depth + 1);
        if (s->player.evolution[weapon] == 2 && category == EMBER_BLADES &&
            !enemy_front(e, s->player.x, s->player.y)) {
            unsigned state = ember_weapons[weapon].element_index == 4 ? EMBER_CORRODE :
                ember_weapons[weapon].element_index == 1 ? EMBER_IGNITE :
                ember_weapons[weapon].element_index == 2 ? EMBER_CHILL :
                ember_weapons[weapon].element_index == 3 ? EMBER_SHOCK : EMBER_BREAK_ARMOR;
            for (int n = 0; n < ember_weapons[weapon].evo_b_status_stacks; ++n)
                ember_sim_status(s, index, state, depth);
        }
        if (s->player.evolution[weapon] == 1 && category == EMBER_STAFF) {
            for (unsigned i = 0; i < EMBER_ENEMIES; ++i)
                if (i != index && s->enemies[i].alive && within(e->x, e->y,
                    s->enemies[i].x, s->enemies[i].y, ember_weapons[weapon].evo_a_range)) {
                    unsigned state = ember_weapons[weapon].element_index == 1 ? EMBER_IGNITE :
                        ember_weapons[weapon].element_index == 2 ? EMBER_WET :
                        ember_weapons[weapon].element_index == 0 ? EMBER_BREAK_ARMOR :
                        ember_weapons[weapon].element_index == 3 ? EMBER_SHOCK : EMBER_CORRODE;
                    ember_sim_status(s, i, state, depth + 1);
                }
        }
    }

}
static void content_step(struct ember_sim *s)
{
    struct ember_player *p = &s->player;
    const struct ember_characters_row *c = &ember_characters[p->character];
    unsigned character = (unsigned)c->mechanism;
    int moving = p->x != s->previous_player_x || p->y != s->previous_player_y;
    s->previous_player_x = p->x; s->previous_player_y = p->y;
    if (moving) { ++s->moving_frames;
        s->standing_frames = 0; }
    else { s->moving_frames = 0; ++s->standing_frames; }
    if (s->skill_time) --s->skill_time;
    if (s->ultimate_time) --s->ultimate_time;
    if (s->dash_buff) --s->dash_buff;
    if (s->stealth && !--s->stealth) {
        s->oil = s->saved_oil;
        for (unsigned i = 0; i < 8; ++i) s->pillars[i].lit = (s->saved_pillars >> i) & 1;
    }
    if (s->resonances[9] && s->previous_light != s->in_light)
        inherited_area(s, p->x, p->y, ember_resonances[9].radius,
            ember_resonances[9].damage, 0);
    s->previous_light = s->in_light;
    if (p->dash) s->dash_buff = (uint16_t)ember_blessings[1].duration;
    else s->flame_dash = 0;
    p->defense.reduction[1] = character == 0 && s->skill_time ? c->skill_l_value : 0;
    p->defense.reduction[2] = s->blessings[11] && s->standing_frames >= (unsigned)ember_blessings[11].duration ?
        ember_blessings[11].value : 0;
    if (character == 6 && !s->in_light)
        p->speed = s->attributes[EMBER_SPEED] * (100 + c->passive_value2 *
            (100 + relic(s, R_NIGHT)) / 100) / 100;
    else p->speed = s->attributes[EMBER_SPEED];
    if (character == 5 && s->combat_frame % c->passive_interval == 0) {
        heal(s, talent_passive(s, c->passive_value, 1));
        for (unsigned i = 0; i < 8; ++i)
            if (s->summons[i].life && s->summons[i].room == s->room_serial && within(p->x, p->y,
                    s->summons[i].x, s->summons[i].y, c->passive_radius))
                    s->summons[i].hp = minimum(ember_summons[s->summons[i].kind].hp,
                        s->summons[i].hp + talent_passive(s, c->passive_value, 1));
    }
    if (s->tide_shield && !p->defense.temporary[2]) {
        s->tide_shield = 0;
        for (unsigned i = 0; i < EMBER_ENEMIES; ++i)
            if (s->enemies[i].alive && within(p->x, p->y,
                s->enemies[i].x, s->enemies[i].y, c->skill_l_radius)) {
                ember_sim_status(s, i, EMBER_CHILL, 0);
                if (s->enemies[i].defense.rank < 2) s->enemies[i].defense.frozen = (uint16_t)c->skill_l_freeze_frames;
            }
    }
    for (unsigned i = 0; i < 8; ++i) if (s->summons[i].life &&
        s->summons[i].room == s->room_serial) {
        const struct ember_summons_row *d = &ember_summons[s->summons[i].kind];
        --s->summons[i].life;
        for (unsigned n = 0; n < EMBER_ENEMIES; ++n) {
            struct ember_enemy *foe = &s->enemies[n];
            if (foe->alive && within(s->summons[i].x, s->summons[i].y, foe->x, foe->y, d->contact_radius) &&
                s->combat_frame % d->hurt_interval == 0) {
                s->summons[i].hp -= ember_enemies[foe->kind].damage * ember_system[0].armor_k /
                    (ember_system[0].armor_k + s->summons[i].armor);
                if (s->summons[i].hp <= 0) { s->summons[i].life = 0; break; }
            }
        }
        int target = nearest(s);
        if (target < 0) continue;
        struct ember_enemy *e = &s->enemies[target];
        if (s->summons[i].kind != 1) {
            ember_fixed vx, vy;
            velocity(e->x - s->summons[i].x, e->y - s->summons[i].y, d->speed, &vx, &vy);
            s->summons[i].x += vx; s->summons[i].y += vy;
        }
        if (s->summons[i].timer) --s->summons[i].timer;
        else if (within(s->summons[i].x, s->summons[i].y, e->x, e->y,
            d->range_pixels)) {
            struct ember_attack h = {.base = s->summons[i].damage,
                .attack = d->attack, .crit = d->crit, .crit_damage = d->crit_damage};
            h.share[d->element_index] = 100;
            if (s->summons[i].kind == 2) {
                memset(h.share, 0, sizeof(h.share));
                h.share[ember_pets[0].element_index] = 100;
                h.crit = ember_pets[0].crit; h.crit_damage = ember_pets[0].crit_damage;
            }
            if (character == 7 && s->summons[i].kind != 2 &&
                light_zone_at(s, s->summons[i].x, s->summons[i].y))
                h.added[3] = talent_passive(s, c->passive_value, 1);
            ember_sim_hit(s, (unsigned)target, &h);
            if (s->resonances[7] && e->alive) ember_sim_status(s, target, EMBER_SHOCK, 1);
            s->summons[i].timer = (uint16_t)(d->attack_cooldown * 100 /
                (100 + (character == 5 && s->ultimate_time ? c->ultimate_value : 0)));
        }
    }
    if (character == 7 && s->ultimate_time && s->combat_frame % c->ultimate_interval == 0)
        for (unsigned a = 0; a < 8; ++a) for (unsigned b = a + 1; b < 8; ++b) {
            if (!s->summons[a].life || !s->summons[b].life ||
                s->summons[a].room != s->room_serial ||
                s->summons[b].room != s->room_serial) continue;
            int64_t dx = (s->summons[b].x - s->summons[a].x) / EMBER_Q;
            int64_t dy = (s->summons[b].y - s->summons[a].y) / EMBER_Q;
            for (unsigned i = 0; i < EMBER_ENEMIES; ++i) {
                struct ember_enemy *e = &s->enemies[i];
                int64_t x = (e->x - s->summons[a].x) / EMBER_Q;
                int64_t y = (e->y - s->summons[a].y) / EMBER_Q;
                int64_t dot = x * dx + y * dy;
                if (e->alive && dot >= 0 && dot <= dx * dx + dy * dy &&
                    llabs(x * dy - y * dx) <= c->ultimate_value * square_root(dx * dx + dy * dy))
                    skill_hit_tags(s, i, 3, c->ultimate_damage, EMBER_SHOCK, TAG_AREA | TAG_GROUP, 0);
            }
        }
}
static void pet_hit_depth(struct ember_sim *s, unsigned target, int damage, unsigned depth)
{
    struct ember_pet_weapons_row data = pet_weapon_data(s);
    const struct ember_pet_weapons_row *w = &data;
    struct ember_attack hit = {.base = damage, .attack = 100,
        .crit = ember_pets[s->pet_kind].crit,
        .crit_damage = ember_pets[s->pet_kind].crit_damage, .depth = (uint8_t)depth};
    unsigned rune = pet_rune(s);
    unsigned type = (unsigned)w->element_index;
    if (rune == 18) {
        const unsigned types[] = {1,2,0,3,4};
        type = types[(s->pet_attack_count - 1) % 5];
    }
    hit.share[type] = 100;
    if (rune == 5 && (s->pet_hit_count + 1) % ember_inscriptions[4].value == 0) hit.flags |= EMBER_FORCE_CRIT;
    if (rune == 6) hit.leech = ember_inscriptions[5].value;
    if (rune == 15) hit.status_strength = 100 + ember_inscriptions[14].value;
    if (rune == 16) hit.flags = EMBER_IGNORE_BLOCK;
    struct ember_damage_result result = ember_sim_hit(s, target, &hit);
    struct ember_enemy *e = &s->enemies[target];
    if (!result.damage && !result.absorbed) return;
    ++s->pet_hit_count;
    if (e->alive && (result.damage || result.absorbed)) {
        if (rune == 3 && ember_random(&s->combat_rng) % 100 < (unsigned)ember_inscriptions[2].value) {
            ember_status_apply(&e->defense, EMBER_IGNITE, ember_inscriptions[2].duration, 100);
            e->burn_pet = 1;
        }
        if (rune == 4) ember_status_apply(&e->defense, EMBER_WET, ember_inscriptions[3].duration, 100);
        if (rune == 12 && result.crit && depth < 3u + s->trigger_bonus) {
            unsigned jumps = 0;
            for (unsigned n = 0; n < EMBER_ENEMIES && jumps < (unsigned)ember_inscriptions[11].value; ++n)
                if (n != target && s->enemies[n].alive && within(e->x, e->y,
                    s->enemies[n].x, s->enemies[n].y, ember_system[0].chain_range)) {
                    struct ember_attack linked = {.base = ember_statuses[EMBER_SHOCK].damage, .attack = 100,
                        .share = {0,0,0,100,0,0}, .depth = (uint8_t)(depth + 1)};
                    ember_sim_hit(s, n, &linked); ++jumps;
                }
        }
    }
    if (!e->alive && rune == 13 && depth < 3u + s->trigger_bonus)
        for (unsigned n = 0; n < EMBER_ENEMIES; ++n)
            if (s->enemies[n].alive && within(e->x, e->y,
                s->enemies[n].x, s->enemies[n].y, ember_inscriptions[12].value2)) {
                hit.base = damage * ember_inscriptions[12].value / 100; hit.depth = (uint8_t)(depth + 1); hit.crit = 0;
                memcpy(hit.share, s->weapon_system[s->player.main_weapon].share,
                    sizeof(hit.share));
                ember_sim_hit(s, n, &hit);
            }
    if (rune == 14 && depth < 3u + s->trigger_bonus) {
        struct ember_shot *ground = shot(s, 2, e->x, e->y, damage * ember_inscriptions[13].value2 / 100,
            ember_inscriptions[13].value3, ember_inscriptions[13].duration);
        ground->pet = 1; ground->effect = 12; ground->depth = (uint8_t)(depth + 1);
    }
}
static void pet_hit(struct ember_sim *s, unsigned target, int damage)
{
    pet_hit_depth(s, target, damage, 0);
}
static void pet_step(struct ember_sim *s)
{
    struct ember_player *p = &s->player;
    if (s->pet_kind == 255) return;
    struct ember_pet_weapons_row data = pet_weapon_data(s);
    const struct ember_pet_weapons_row *w = &data;
    const struct ember_pets_row *pet = &ember_pets[s->pet_kind];
    if (w->category != 0) {
        s->pet.x = p->x + pet->follow_x * EMBER_Q;
        s->pet.y = p->y + pet->follow_y * EMBER_Q;
    }
    s->pet.category = (uint8_t)w->category;
    if (s->pet_skill_timer) --s->pet_skill_timer;
    if (s->pet_skill_time) --s->pet_skill_time;
    if (p->pet_timer) --p->pet_timer;
    int target = nearest(s);
    if (target >= 0 && w->category == 0) {
        ember_fixed vx, vy;
        velocity(s->enemies[target].x - s->pet.x, s->enemies[target].y - s->pet.y,
            pet->speed, &vx, &vy);
        s->pet.x += vx; s->pet.y += vy;
    }
    if (target >= 0 && !p->pet_timer) {
        struct ember_enemy *e = &s->enemies[target];
        int damage = w->damage * (100 + (s->pet_level - 1) * pet->damage_per_level) / 100;
        ++s->pet_attack_count;
        p->pet_timer = (uint16_t)(w->attack_cooldown * 100 /
            (100 + (s->blessings[10] ? ember_blessings[10].value : 0) +
             (ember_characters[p->character].mechanism == 5 && s->ultimate_time ? ember_characters[p->character].ultimate_value : 0)));
        if (w->category != 1 && w->category != 2 && pet_rune(s) == 17)
            damage = damage * (100 - ember_inscriptions[16].value) / 100;
        if (w->category == 0) {
            /* A melee pet approaches its target independently of the character. */
            if (within(s->pet.x, s->pet.y, e->x, e->y, w->range_pixels)) {
                pet_hit(s, (unsigned)target, damage);
                if (pet_rune(s) == 17) pet_hit(s, (unsigned)target, damage);
            }
            else p->pet_timer = 0;
        } else if (w->category == 3) {
            for (unsigned i = 0; i < EMBER_ENEMIES; ++i)
                if (s->enemies[i].alive && within(s->pet.x, s->pet.y,
                    s->enemies[i].x, s->enemies[i].y, w->range_pixels)) {
                    pet_hit(s, i, damage);
                    if (pet_rune(s) == 17) pet_hit(s, i, damage);
                }
        } else {
            unsigned count = pet_rune(s) == 2 ? 1u + (unsigned)ember_inscriptions[1].value :
                pet_rune(s) == 17 ? (unsigned)ember_inscriptions[16].value2 : 1;
            if (pet_rune(s) == 2) damage = damage * (100 - ember_inscriptions[1].value2) / 100;
            if (pet_rune(s) == 17) damage = damage * (100 - ember_inscriptions[16].value) / 100;
            for (unsigned n = 0; n < count; ++n) {
                struct ember_shot *q = shot(s, 0, s->pet.x, s->pet.y, damage, w->projectile_radius, w->range_pixels * 60 / w->speed);
                q->pet = 1; q->speed = w->speed;
                q->pierce = pet_rune(s) == 1 ? ember_inscriptions[0].value : 0;
                velocity(e->x - q->x, e->y - q->y, w->speed, &q->vx, &q->vy);
                uint16_t a = (uint16_t)(((int)n * 2 - (int)count + 1) * w->spread_angle);
                ember_fixed vx = ember_mul(q->vx, ember_cos(a)) - ember_mul(q->vy, ember_sin(a));
                q->vy = ember_mul(q->vx, ember_sin(a)) + ember_mul(q->vy, ember_cos(a));
                q->vx = vx;
            }
        }
    }
    if (s->pet_skill_timer) return;
    if (s->pet_kind != 5 && (target < 0 || !within(s->pet.x, s->pet.y,
        s->enemies[target].x, s->enemies[target].y, pet->range_pixels))) return;
    switch (s->pet_kind) {
    case 0:
        for (unsigned i = 0; i < (unsigned)pet->skill_count; ++i)
            summon(s, 2, pet->skill_duration, s->pet.x + (int)i * pet->skill_spacing * EMBER_Q, s->pet.y);
        break;
    case 1: {
        int shields = 0;
        for (unsigned i = 0; i < 7; ++i) shields += p->defense.temporary[i];
        if (shields) return;
        p->defense.temporary[6] += pet->skill_value;
        p->defense.shield_frames[6] = (uint16_t)pet->skill_duration;
        break;
    }
    case 2:
        for (unsigned i = 0; i < EMBER_ENEMIES; ++i) if (s->enemies[i].alive &&
            within(s->pet.x, s->pet.y, s->enemies[i].x, s->enemies[i].y, pet->skill_radius))
            ember_status_apply(&s->enemies[i].defense, EMBER_BLIND, pet->skill_duration, 100);
        break;
    case 3: {
        unsigned count = 0;
        for (unsigned i = 0; i < EMBER_ENEMIES && count < (unsigned)pet->skill_count; ++i)
            if (s->enemies[i].alive && within(s->pet.x, s->pet.y,
                s->enemies[i].x, s->enemies[i].y, pet->skill_radius)) {
                s->enemies[i].marked = s->enemies[i].owl_mark =
                    (uint16_t)pet->skill_duration; ++count;
            }
        break;
    }
    case 4:
        for (unsigned n = 0; n < (unsigned)pet->skill_count; ++n) {
            struct ember_shot *q = shot(s, 2, s->pet.x + (int)n * pet->skill_spacing * EMBER_Q,
                s->pet.y, pet->skill_damage, pet->skill_patch_radius, pet->skill_duration);
            q->pet = 1; q->effect = 10;
        }
        break;
    case 5: {
        int pillar = -1;
        int64_t best = INT64_MAX;
        for (unsigned i = 0; i < s->pillar_count; ++i) if (!s->pillars[i].lit) {
            int64_t distance = distance2(s->pet.x, s->pet.y, s->pillars[i].x, s->pillars[i].y);
            if (distance < best) { best = distance; pillar = (int)i; }
        }
        if (pillar >= 0) s->pillars[pillar].lit = 1;
        else if (s->oil < 10000) s->oil = minimum(10000, s->oil + pet->skill_value);
        else return;
        break;
    }
    }
    s->pet_skill_timer = (uint16_t)(pet->skill_cooldown * (100 - (s->blessings[10] ? ember_blessings[10].value2 : 0)) / 100);
}
static void ground_effect(struct ember_sim *s, struct ember_shot *p)
{
    if ((p->effect == 5 || p->effect == 8) &&
        within(p->x, p->y, s->player.x, s->player.y, p->radius))
        s->lamp_radius = s->lamp_radius * ember_enemies[p->enemy_kind].ground_lamp_percent / 100;
    if (p->tick) { --p->tick; return; }
    p->tick = (uint16_t)ember_system[0].ground_interval;
    if (p->effect >= 4 && p->effect <= 9) {
        const struct ember_enemies_row *d = &ember_enemies[p->enemy_kind];
        if (!within(p->x, p->y, s->player.x, s->player.y, p->radius)) return;
        if (p->effect == 4) ember_status_apply(&s->player.defense, EMBER_WET, d->ground_slow_frames, 100);
        if (p->effect == 5 || p->effect == 8) {
            ember_slow_apply(&s->player.defense,
                p->effect == 5 ? EMBER_SLOW_WEB : EMBER_SLOW_VORTEX,
                d->ground_slow_percent, d->ground_slow_frames);
            if (p->effect == 8) {
                s->player.x += (p->x - s->player.x) * d->ground_pull_percent / 100;
                s->player.y += (p->y - s->player.y) * d->ground_pull_percent / 100;
            }
        }
        if (p->effect >= 6 && p->effect != 8)
            player_hurt_typed(s, p->damage, p->weapon, p->x, p->y,
                p->effect == 9 ? 5 : p->effect == 7 ? 2 : 1,
                p->effect == 9 ? EMBER_UNDODGEABLE : 0);
        return;
    }
    for (unsigned i = 0; i < EMBER_ENEMIES; ++i) {
        struct ember_enemy *e = &s->enemies[i];
        if (!e->alive || !within(p->x, p->y, e->x, e->y, p->radius)) continue;
        if (p->effect == 1) ember_slow_apply(&e->defense, EMBER_SLOW_GATE,
            ember_characters[EMBER_DATA_CHARACTERS_SEER].skill_k_slow_percent,
            ember_characters[EMBER_DATA_CHARACTERS_SEER].skill_k_slow_frames);
        if (p->effect == 2) {
            struct ember_attack hit = {.base = p->damage, .attack = 100,
                .share = {0,0,0,0,100,0}, .leech = ember_resonances[3].value,
                .crit = s->attributes[EMBER_CRIT],
                .crit_damage = s->attributes[EMBER_CRIT_DAMAGE],
                .flags = EMBER_DOT | (s->dot_can_crit ? EMBER_DOT_CRIT : 0),
                .depth = p->depth};
            ember_sim_hit(s, i, &hit);
            if (e->alive) ember_sim_status(s, i, EMBER_CORRODE, 0);
        }
        if (p->effect == 3) {
            ember_slow_apply(&e->defense, EMBER_SLOW_ABYSS,
                ember_resonances[6].value, ember_resonances[6].slow_frames);
            ember_sim_status(s, i, EMBER_CORRODE, p->depth);
        }
        if (p->effect == 10) {
            struct ember_attack hit = {.base = p->damage * (100 + (s->pet_level - 1) *
                ember_pets[s->pet_kind].damage_per_level) / 100, .attack = 100,
                .share = {0,100,0,0,0,0}, .crit = ember_pets[s->pet_kind].crit,
                .crit_damage = ember_pets[s->pet_kind].crit_damage,
                .flags = EMBER_DOT | (s->dot_can_crit ? EMBER_DOT_CRIT : 0),
                .depth = p->depth};
            ember_sim_hit(s, i, &hit);
        }
        if (p->effect == 12) {
            struct ember_attack hit = {.base = p->damage, .attack = 100,
                .share = {0,100,0,0,0,0}, .flags = EMBER_DOT, .depth = p->depth};
            ember_sim_hit(s, i, &hit);
        }
        if (p->effect == 11) ember_sim_status(s, i, EMBER_BLIND, p->depth);
    }
}

static void energy_add(struct ember_sim *s, int amount)
{
    s->energy_fraction += amount * (100 + (s->blessings[6] ? ember_blessings[6].value : 0));
    s->player.charge = (uint16_t)minimum(100, s->player.charge + s->energy_fraction / 100);
    s->energy_fraction %= 100;
}

void ember_sim_reward_cap(struct ember_sim *s, unsigned attr)
{
    s->contract_caps[attr] += ember_attributes[attr].maximum * ember_contracts[4].reward_cap_percent / 100;
    s->contract_cap_choice = 0;
    ember_sim_attributes(s);
}
int32_t ember_sim_price(const struct ember_sim *s, int32_t base)
{
    return base * (100 + (s->curses[5] ? ember_contracts[5].value : 0) +
        (s->config.difficulty >= 7 ? ember_difficulty[6].price_percent : 0)) / 100;
}

unsigned ember_sim_tag_count(const struct ember_sim *s, const char *tag)
{
    unsigned pieces = 0;
    for (unsigned i = 0; i < EMBER_RELICS_COUNT; ++i)
        pieces += s->player.relic_level[i] && tag_present(ember_relics[i].tags, tag);
    for (unsigned w = 0; w < EMBER_WEAPONS_COUNT; ++w) {
        if (!s->player.weapon_level[w]) continue;
        for (unsigned i = 0; i < EMBER_TAGS_COUNT; ++i)
            if (!strcmp(ember_tags[i].id, tag))
                pieces += !!(ember_sim_weapon_tags(s, w) & (1u << i));
        for (unsigned slot = 0; slot < 2; ++slot) {
            unsigned rune = s->player.inscription[w][slot];
            if (rune) pieces += tag_present(ember_inscriptions[rune - 1].tags, tag);
        }
    }
    for (unsigned i = 0; i < EMBER_BLESSINGS_COUNT; ++i)
        pieces += s->blessings[i] && tag_present(ember_blessings[i].tags, tag);
    if (s->pet_kind != 255 && s->player.pet_weapon != 255)
        pieces += tag_present(ember_pet_weapons[s->player.pet_weapon].tags, tag);
    if (s->pet_kind != 255 && pet_rune(s))
        pieces += tag_present(ember_inscriptions[pet_rune(s) - 1].tags, tag);
    return pieces;
}
int ember_sim_evolution_ready(const struct ember_sim *s, unsigned w, unsigned branch)
{
    const char *condition = branch == 1 ? ember_weapons[w].condition_a :
        ember_weapons[w].condition_b;
    return s->player.weapon_level[w] == ember_weapons[w].level_max && !s->player.evolution[w] &&
        (s->free_evolution || ember_sim_tag_count(s, condition) >= (unsigned)ember_system[0].element_item_requirement);
}
int ember_sim_resonance_ready(const struct ember_sim *s, unsigned id)
{
    const char *elements[] = {"ember", "tide", "iron", "star", "shadow"};
    const unsigned pairs[10][2] = {{0,1},{0,2},{0,3},{0,4},{1,2},
        {1,3},{1,4},{2,3},{2,4},{3,4}};
    unsigned count = 0;
    for (unsigned i = 0; i < 10; ++i) count += !!s->resonances[i];
    return count < (unsigned)ember_system[0].resonance_limit && !s->resonances[id] &&
        ember_sim_tag_count(s, elements[pairs[id][0]]) >= (unsigned)ember_system[0].element_item_requirement &&
        ember_sim_tag_count(s, elements[pairs[id][1]]) >= (unsigned)ember_system[0].element_item_requirement;
}

static void inherited_hit_tags(struct ember_sim *s, unsigned target, int damage,
                                 unsigned depth, uint32_t tags)
{
    struct ember_attack h = {.base = damage, .attack = s->attributes[EMBER_ATTACK],
        .crit = s->attributes[EMBER_CRIT], .crit_damage = s->attributes[EMBER_CRIT_DAMAGE],
        .depth = (uint8_t)depth};
    memcpy(h.share, s->weapon_system[s->player.main_weapon].share, sizeof(h.share));
    player_modifiers(s, target, &h, tags);
    content_before_hit(s, target, 255, &h);
    struct ember_damage_result r = ember_sim_hit(s, target, &h);
    player_hit_effects(s, target, r, tags);
    content_after_hit(s, target, 255, r, depth);
}
static void inherited_hit(struct ember_sim *s, unsigned target, int damage, unsigned depth)
{
    inherited_hit_tags(s, target, damage, depth, TAG_SINGLE);
}
static void inherited_area(struct ember_sim *s, ember_fixed x, ember_fixed y,
                            int radius, int damage, unsigned depth)
{
    radius = radius * s->attributes[EMBER_AREA] / 100;
    for (unsigned i = 0; i < EMBER_ENEMIES; ++i)
        if (s->enemies[i].alive && within(x, y, s->enemies[i].x, s->enemies[i].y, radius))
            inherited_hit_tags(s, i, damage, depth, TAG_AREA | TAG_GROUP);
}

int ember_sim_contract_reward_available(const struct ember_sim *s, unsigned reward)
{
    unsigned count = 0;
    for (unsigned i = 0; i < 10; ++i) count += !!s->resonances[i];
    if (reward == 2) return count < (unsigned)ember_system[0].resonance_limit;
    if (reward == 5) return s->pet_kind != 255;
    if (reward == 3) {
        for (unsigned i = 0; i < 18; ++i)
            if (ember_inscriptions[i].grade == 2 &&
                !inventory_owned(s, EMBER_ITEM_INSCRIPTION, i) &&
                (rune_allowed(s, i, s->player.main_weapon) ||
                 (s->player.sub_weapon != 255 && rune_allowed(s, i, s->player.sub_weapon)) ||
                 (s->player.pet_weapon != 255 && rune_allowed(s, i, 50u + s->player.pet_weapon))))
                return 1;
        return 0;
    }
    return 1;
}
unsigned ember_sim_altar_choices(struct ember_sim *s, struct ember_altar_choice choices[3])
{
    struct ember_altar_choice pool[23];
    unsigned score[23], count = 0;
    const char *elements[] = {"ember", "tide", "iron", "star", "shadow"};
    if (!s->guaranteed_resonance)
        for (unsigned i = 0; i < EMBER_BLESSINGS_COUNT; ++i)
            if (!s->blessings[i] && item_allowed(s, EMBER_ITEM_BLESSING, i)) {
            pool[count] = (struct ember_altar_choice){0, (uint8_t)i}; score[count++] = 0;
        }
    for (unsigned i = 0; i < 10 && s->config.mode == EMBER_ROUTE; ++i) {
        if (s->resonances[i]) continue;
        if (!s->guaranteed_resonance && !ember_sim_resonance_ready(s, i)) continue;
        pool[count] = (struct ember_altar_choice){1, (uint8_t)i};
        score[count++] = s->guaranteed_resonance ?
            !!ember_sim_tag_count(s, elements[ember_resonances[i].element_a]) +
            !!ember_sim_tag_count(s, elements[ember_resonances[i].element_b]) : 0;
    }
    unsigned offered = count < 3 ? count : 3;
    for (unsigned pick = 0; pick < offered; ++pick) {
        unsigned best = 0, indices[23], candidates = 0;
        for (unsigned i = 0; i < count; ++i) if (score[i] > best) best = score[i];
        for (unsigned i = 0; i < count; ++i) if (score[i] == best) indices[candidates++] = i;
        unsigned index = indices[ember_random(&s->loot_rng) % candidates];
        choices[pick] = pool[index];
        pool[index] = pool[--count]; score[index] = score[count];
    }
    s->guaranteed_resonance = 0;
    return offered;
}

static void leech(struct ember_sim *s, int damage, int percent)
{
    s->leech_fraction += damage * percent;
    heal(s, s->leech_fraction / 100);
    s->leech_fraction %= 100;
}
