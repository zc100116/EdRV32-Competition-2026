/* File: economy.inc; GDD 5f/6: unique inventory, real replacements and shops.
 * Included by sim.c; all acquisition commits emit the frozen pickup/change events.
 * Clock domain: fixed 60 Hz input decisions; panel idle does not advance simulation.
 */
static int inventory_owned(const struct ember_sim *s, unsigned kind, unsigned id)
{
    const struct ember_player *p = &s->player;
    if (kind == EMBER_ITEM_WEAPON && p->weapon_level[id]) return 1;
    if (kind == EMBER_ITEM_RELIC) return !!p->relic_level[id];
    if (kind == EMBER_ITEM_PET_WEAPON && p->pet_weapon_level[id]) return 1;
    if (kind == EMBER_ITEM_INSCRIPTION) {
        for (unsigned w = 0; w < 50; ++w) if (inscription(s, w, id)) return 1;
        for (unsigned w = 0; w < 12; ++w) if (p->pet_inscription[w] == id + 1) return 1;
    }
    for (unsigned i = 0; i < 62; ++i) {
        const struct ember_ground_weapon *g = &s->ground[i];
        if (!g->alive) continue;
        if (g->kind == kind && g->id == id) return 1;
        if (kind == EMBER_ITEM_INSCRIPTION &&
            (g->inscription[0] == id + 1 || g->inscription[1] == id + 1)) return 1;
    }
    return 0;
}
static int rune_allowed(const struct ember_sim *s, unsigned id, unsigned target)
{
    if (target >= 50) {
        unsigned category = (unsigned)ember_pet_weapons[target - 50].category;
        if (id == 10) return 0;
        if (id == 9) return category == 3;
        if (id == 0 || id == 1 || id == 6 || id == 7 || id == 8)
            return category == 1 || category == 2;
        return 1;
    }
    if (id == 10 && !charging_weapon(s, target)) return 0;
    if (id == 9 && !tagged(target, "area")) return 0;
    if ((id == 0 || id == 1 || id == 6 || id == 7 || id == 8) &&
        !tagged(target, "projectile")) return 0;
    return 1;
}
static unsigned item_pool(const struct ember_sim *s, struct ember_choice *pool,
                           unsigned minimum_grade, int shop)
{
    unsigned count = 0;
    if (!shop)
        for (unsigned w = 0; w < 50; ++w)
            if (!inventory_owned(s, EMBER_ITEM_WEAPON, w) &&
                (unsigned)ember_weapons[w].grade >= minimum_grade)
                pool[count++] = (struct ember_choice){EMBER_ITEM_WEAPON, (uint8_t)w, 255};
    for (unsigned r = 0; r < 38; ++r)
        if (!inventory_owned(s, EMBER_ITEM_RELIC, r) &&
            (unsigned)ember_relics[r].grade >= minimum_grade)
            pool[count++] = (struct ember_choice){EMBER_ITEM_RELIC, (uint8_t)r, 255};
    unsigned targets[3] = {s->player.main_weapon, s->player.sub_weapon,
        s->player.pet_weapon == 255 ? 255 : 50u + s->player.pet_weapon};
    for (unsigned i = 0; i < 18; ++i) {
        if (inventory_owned(s, EMBER_ITEM_INSCRIPTION, i) ||
            (unsigned)ember_inscriptions[i].grade < minimum_grade) continue;
        for (unsigned t = 0; t < 3; ++t)
            if (targets[t] != 255 && rune_allowed(s, i, targets[t]))
                pool[count++] = (struct ember_choice){EMBER_ITEM_INSCRIPTION,
                    (uint8_t)i, (uint8_t)targets[t]};
    }
    if (!shop && !minimum_grade && s->pet_kind != 255)
        for (unsigned w = 0; w < 12; ++w)
            if (!inventory_owned(s, EMBER_ITEM_PET_WEAPON, w))
                pool[count++] = (struct ember_choice){EMBER_ITEM_PET_WEAPON, (uint8_t)w, 255};
    return count;
}
static void ground_drop(struct ember_sim *s, unsigned kind, unsigned id)
{
    for (unsigned i = 0; i < 62; ++i) if (!s->ground[i].alive) {
        struct ember_ground_weapon *g = &s->ground[i];
        *g = (struct ember_ground_weapon){.alive = 1, .kind = (uint8_t)kind,
            .id = (uint8_t)id, .x = s->player.x, .y = s->player.y, .room = s->room_serial};
        if (kind == EMBER_ITEM_WEAPON) {
            g->level = s->player.weapon_level[id];
            g->evolution = s->player.evolution[id];
            memcpy(g->inscription, s->player.inscription[id], 2);
            s->player.weapon_level[id] = s->player.evolution[id] = 0;
            memset(s->player.inscription[id], 0, 2);
        } else {
            g->level = s->player.pet_weapon_level[id];
            g->inscription[0] = s->player.pet_inscription[id];
            s->player.pet_weapon_level[id] = s->player.pet_inscription[id] = 0;
        }
        return;
    }
    fputs("Ground weapon pool exhausted\n", stderr);
    abort();
}
static void item_grant(struct ember_sim *s, struct ember_choice c, unsigned replacement)
{
    struct ember_player *p = &s->player;
    int old_hp = p->max_hp;
    struct ember_ground_weapon incoming = {0};
    if (s->pending_ground >= 0) incoming = s->ground[s->pending_ground];
    if (c.kind == EMBER_ITEM_WEAPON) {
        unsigned slot = replacement == 255 ? (p->sub_weapon == 255 ? 1 : 0) : replacement;
        unsigned old = slot ? p->sub_weapon : p->main_weapon;
        if (old != 255) ground_drop(s, c.kind, old);
        if (slot) p->sub_weapon = c.id; else p->main_weapon = c.id;
        p->weapon_level[c.id] = incoming.alive ? incoming.level : 1;
        p->evolution[c.id] = incoming.evolution;
        memcpy(p->inscription[c.id], incoming.inscription, 2);
        s->discoveries.weapons[c.id] = 1;
        weapon_change_event(s, slot, c.id);
    } else if (c.kind == EMBER_ITEM_PET_WEAPON) {
        if (p->pet_weapon != 255) ground_drop(s, c.kind, p->pet_weapon);
        p->pet_weapon = c.id;
        p->pet_weapon_level[c.id] = incoming.alive ? incoming.level : 1;
        p->pet_inscription[c.id] = incoming.inscription[0];
        s->discoveries.pet_weapons[c.id] = 1;
        if (s->pet_kind != 255) {
            unsigned level = s->pet_level;
            ember_sim_pet(s, s->pet_kind, c.id);
            s->pet_level = (uint8_t)level;
        }
        weapon_change_event(s, EMBER_WEAPON_SLOT_PET, c.id);
    } else if (c.kind == EMBER_ITEM_RELIC) {
        if (replacement != 255) {
            p->relic_level[replacement] = 0;
            unsigned refund = (unsigned)ember_sim_price(s, ember_relics[replacement].price) *
                (unsigned)ember_economy[0].refund_percent / 100;
            s->gold += refund;
            pickup_event(s, EMBER_PICKUP_GOLD, refund, p->x, p->y);
        }
        p->relic_level[c.id] = 1;
        s->discoveries.relics[c.id] = 1;
    } else if (c.kind == EMBER_ITEM_INSCRIPTION) {
        if (c.slot >= 50) p->pet_inscription[c.slot - 50] = (uint8_t)(c.id + 1);
        else {
            unsigned slot = replacement == 255 ? !!p->inscription[c.slot][0] : replacement;
            p->inscription[c.slot][slot] = (uint8_t)(c.id + 1);
        }
        s->discoveries.inscriptions[c.id] = 1;
    }
    s->gold -= (unsigned)s->pending_price;
    if (s->pending_shop >= 0) s->shop_sold[s->pending_shop] = 1;
    if (s->pending_ground >= 0) s->ground[s->pending_ground].alive = 0;
    if (s->pending_pickup >= 0) {
        s->pickups[s->pending_pickup].alive = 0;
        --s->pickup_count;
    }
    s->pending_ground = s->pending_pickup = s->pending_shop = -1;
    s->pending_price = 0;
    pickup_event(s, EMBER_PICKUP_ITEM, c.id, p->x, p->y);
    ember_sim_attributes(s);
    p->hp = minimum(p->max_hp, p->hp + maximum(0, p->max_hp - old_hp));
}
static void panel_open(struct ember_sim *s, unsigned panel)
{
    s->panel = (uint8_t)panel;
    s->panel_selected = s->option_count = 0;
    s->transaction_result = 0;
}
static void item_receive(struct ember_sim *s, struct ember_choice c)
{
    unsigned count = 0;
    if (c.kind == EMBER_ITEM_WEAPON && s->player.sub_weapon != 255) {
        s->options[count++] = (struct ember_choice){c.kind, s->player.main_weapon, 0};
        s->options[count++] = (struct ember_choice){c.kind, s->player.sub_weapon, 1};
    } else if (c.kind == EMBER_ITEM_PET_WEAPON && s->player.pet_weapon != 255)
        s->options[count++] = (struct ember_choice){c.kind, s->player.pet_weapon, 0};
    else if (c.kind == EMBER_ITEM_RELIC) {
        unsigned held = 0;
        for (unsigned i = 0; i < 38; ++i) held += !!s->player.relic_level[i];
        if (held == 6)
            for (unsigned i = 0; i < 38; ++i) if (s->player.relic_level[i])
                s->options[count++] = (struct ember_choice){c.kind, (uint8_t)i, (uint8_t)i};
    } else if (c.kind == EMBER_ITEM_INSCRIPTION) {
        if (c.slot >= 50) {
            if (s->player.pet_inscription[c.slot - 50])
                s->options[count++] = (struct ember_choice){c.kind,
                    (uint8_t)(s->player.pet_inscription[c.slot - 50] - 1), 0};
        } else if (s->player.inscription[c.slot][1])
            for (unsigned i = 0; i < 2; ++i)
                s->options[count++] = (struct ember_choice){c.kind,
                    (uint8_t)(s->player.inscription[c.slot][i] - 1), (uint8_t)i};
    }
    if (!count) { item_grant(s, c, 255); return; }
    s->pending_item = c;
    s->panel_return = s->panel;
    s->panel = EMBER_PANEL_REPLACE;
    s->panel_selected = 0;
    s->option_count = (uint8_t)count;
}
static void shop_stock(struct ember_sim *s)
{
    struct ember_choice pool[200];
    unsigned count = item_pool(s, pool, 0, 1);
    for (unsigned i = 0; i < 3; ++i) {
        s->shop_sold[i] = count == 0;
        if (!count) continue;
        struct ember_choice c = pool[ember_random(&s->loot_rng) % count];
        s->shop_stock[i] = c;
        for (unsigned n = 0; n < count;)
            if (pool[n].kind == c.kind && pool[n].id == c.id) pool[n] = pool[--count];
            else ++n;
    }
}
static void shop_open(struct ember_sim *s)
{
    panel_open(s, EMBER_PANEL_SHOP);
    for (unsigned i = 0; i < 3; ++i) if (!s->shop_sold[i]) {
        struct ember_choice c = s->shop_stock[i];
        s->options[s->option_count] = c;
        s->options[s->option_count].slot = c.slot;
        s->option_prices[s->option_count++] = ember_sim_price(s,
            c.kind == EMBER_ITEM_RELIC ? ember_relics[c.id].price : ember_inscriptions[c.id].price);
    }
    s->options[s->option_count] = (struct ember_choice){EMBER_ITEM_REFRESH, 0, 0};
    s->option_prices[s->option_count++] = ember_sim_price(s, ember_economy[0].refresh_base +
        (int)s->shop_refreshes * ember_economy[0].refresh_growth);
}
static void altar_open(struct ember_sim *s)
{
    if (!s->altar_generated) {
        struct ember_altar_choice c[3];
        s->altar_count = (uint8_t)ember_sim_altar_choices(s, c);
        for (unsigned i = 0; i < s->altar_count; ++i)
            s->altar_stock[i] = (struct ember_choice){c[i].kind ? EMBER_ITEM_RESONANCE :
                EMBER_ITEM_BLESSING, c[i].id, 0};
        s->altar_generated = 1;
    }
    panel_open(s, EMBER_PANEL_ALTAR);
    s->option_count = s->altar_count;
    memcpy(s->options, s->altar_stock, sizeof(s->altar_stock));
}
static void pending_reset(struct ember_sim *s)
{
    s->pending_ground = s->pending_pickup = s->pending_shop = -1;
    s->pending_price = 0;
}
static void contract_open(struct ember_sim *s)
{
    panel_open(s, EMBER_PANEL_CURSE);
    uint8_t pool[6];
    unsigned count = 0;
    for (unsigned i = 0; i < 6; ++i) if (!s->curses[i]) pool[count++] = (uint8_t)i;
    unsigned offered = count < 3 ? count : 3;
    for (unsigned i = 0; i < offered; ++i) {
        unsigned pick = ember_random(&s->loot_rng) % count;
        s->options[s->option_count++] = (struct ember_choice){EMBER_ITEM_CURSE, pool[pick], 0};
        pool[pick] = pool[--count];
    }
}
static void contract_rewards(struct ember_sim *s)
{
    panel_open(s, EMBER_PANEL_REWARD);
    uint8_t pool[6];
    unsigned count = 0;
    for (unsigned i = 0; i < 6; ++i) {
        if (!ember_sim_contract_reward_available(s, i)) continue;
        if (i == 5 && s->pet_kind == 255) continue;
        pool[count++] = (uint8_t)i;
    }
    unsigned offered = count < 3 ? count : 3;
    for (unsigned i = 0; i < offered; ++i) {
        unsigned pick = ember_random(&s->loot_rng) % count;
        s->options[s->option_count++] = (struct ember_choice){EMBER_ITEM_CONTRACT, pool[pick], 0};
        pool[pick] = pool[--count];
    }
}
static void cleanse_open(struct ember_sim *s)
{
    panel_open(s, EMBER_PANEL_CLEANSE);
    for (unsigned i = 0; i < 6; ++i) if (s->curses[i])
        s->options[s->option_count++] = (struct ember_choice){EMBER_ITEM_CLEANSE, (uint8_t)i, 0};
}
static void panel_step(struct ember_sim *s, uint16_t pressed)
{
    if (pressed & (EMBER_INTERACT | EMBER_SELECT)) {
        unsigned parent = s->panel == EMBER_PANEL_REPLACE ? s->panel_return : EMBER_PANEL_NONE;
        pending_reset(s);
        s->panel = EMBER_PANEL_NONE;
        if (parent == EMBER_PANEL_SHOP) shop_open(s);
        return;
    }
    unsigned count = s->option_count;
    if (!count) return;
    if (pressed & (EMBER_UP | EMBER_LEFT)) s->panel_selected =
        (uint8_t)((s->panel_selected + count - 1) % count);
    if (pressed & (EMBER_DOWN | EMBER_RIGHT)) s->panel_selected =
        (uint8_t)((s->panel_selected + 1) % count);
    if (!(pressed & (EMBER_J | EMBER_START))) return;
    struct ember_choice c = s->options[s->panel_selected];
    if (s->panel == EMBER_PANEL_SHOP) {
        unsigned price = (unsigned)s->option_prices[s->panel_selected];
        if (s->gold < price) { s->transaction_result = 1; return; }
        if (c.kind == EMBER_ITEM_REFRESH) {
            s->gold -= price;
            ++s->shop_refreshes;
            shop_stock(s);
            shop_open(s);
        } else {
            pending_reset(s);
            s->pending_price = (int32_t)price;
            for (unsigned i = 0; i < 3; ++i)
                if (!s->shop_sold[i] && s->shop_stock[i].kind == c.kind &&
                    s->shop_stock[i].id == c.id) s->pending_shop = (int16_t)i;
            item_receive(s, c);
            if (s->panel != EMBER_PANEL_REPLACE) shop_open(s);
        }
    } else if (s->panel == EMBER_PANEL_REPLACE) {
        unsigned parent = s->panel_return;
        item_grant(s, s->pending_item, c.slot);
        s->panel = EMBER_PANEL_NONE;
        if (parent == EMBER_PANEL_SHOP) shop_open(s);
    } else if (s->panel == EMBER_PANEL_ALTAR) {
        if (c.kind == EMBER_ITEM_BLESSING) ember_sim_blessing(s, c.id);
        else ember_sim_resonance(s, c.id);
        --s->altars_available;
        ++s->altars_used;
        s->altar_generated = 0;
        s->panel = EMBER_PANEL_NONE;
        pickup_event(s, EMBER_PICKUP_ITEM, c.id, s->player.x, s->player.y);
    } else if (s->panel == EMBER_PANEL_CURSE) {
        s->chosen_curse = c.id;
        contract_rewards(s);
    } else if (s->panel == EMBER_PANEL_REWARD) {
        ember_sim_contract(s, s->chosen_curse, c.id);
        s->rifts_used |= (uint8_t)(1u << s->chosen_rift);
        --s->rifts_available;
        s->panel = EMBER_PANEL_NONE;
        pending_reset(s);
        if (c.id == 0) {
            s->has_reward_relic = 0;
            item_receive(s, (struct ember_choice){EMBER_ITEM_RELIC, s->reward_relic, 255});
        } else if (c.id == 3) {
            s->has_reward_inscription = 0;
            unsigned targets[3] = {s->player.main_weapon, s->player.sub_weapon,
                s->player.pet_weapon == 255 ? 255 : 50u + s->player.pet_weapon};
            for (unsigned i = 0; i < 3; ++i)
                if (targets[i] != 255 && rune_allowed(s, s->reward_inscription, targets[i])) {
                    item_receive(s, (struct ember_choice){EMBER_ITEM_INSCRIPTION,
                        s->reward_inscription, (uint8_t)targets[i]});
                    break;
                }
            pickup_event(s, EMBER_PICKUP_GOLD, (unsigned)ember_contracts[3].reward_gold,
                s->player.x, s->player.y);
        } else if (c.id == 4) {
            panel_open(s, EMBER_PANEL_CAP);
            for (unsigned i = 0; i < EMBER_ATTRIBUTE_COUNT; ++i)
                s->options[s->option_count++] = (struct ember_choice){EMBER_ITEM_CAP,
                    (uint8_t)i, 0};
        }
    } else if (s->panel == EMBER_PANEL_CAP) {
        ember_sim_reward_cap(s, c.id);
        s->panel = EMBER_PANEL_NONE;
    } else if (s->panel == EMBER_PANEL_HIDDEN) {
        s->panel = EMBER_PANEL_NONE;
        if (c.kind == EMBER_ITEM_WORLD) {
            s->discoveries.world[c.id] = 1;
            pickup_event(s, EMBER_PICKUP_ITEM, c.id, s->player.x, s->player.y);
        } else { pending_reset(s); item_receive(s, c); }
    } else if (s->panel == EMBER_PANEL_CLEANSE) {
        ember_sim_cleanse(s, c.id);
        s->cleanse_tokens = 0;
        s->panel = EMBER_PANEL_NONE;
    }
    ember_sim_attributes(s);
}
