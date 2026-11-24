/* File: combat.c; gdd 2.2a/2.3/4.2. Shared player/enemy damage resolution.
 * Clock domain: fixed 60 Hz; 64-bit intermediates retain fractional damage through defense.
 */
#include "combat.h"
#include "data.h"
#include <string.h>
static int32_t min(int32_t a, int32_t b) { return a < b ? a : b; }
static int32_t max(int32_t a, int32_t b) { return a > b ? a : b; }
int32_t ember_attribute_value(unsigned id, int32_t base, int32_t flat, int32_t increased,
                              const int32_t more[4], int32_t cap_raise)
{
    const struct ember_attributes_row *a = &ember_attributes[id];
    if (!strcmp(a->calculation, "flat_more")) increased = 0;
    int64_t value = (int64_t)(base + flat) * (100 + increased) / 100;
    for (unsigned i = 0; i < 4; ++i) value = value * (100 + more[i]) / 100;
    int32_t cap = min(a->maximum + cap_raise, a->range_maximum);
    return (int32_t)(value < a->minimum ? a->minimum : value > cap ? cap : value);
}
void ember_defense_init(struct ember_defense *d, int32_t max_hp)
{
    memset(d, 0, sizeof(*d));
    d->max_hp = max_hp;
    d->weakness = 255;
    for (unsigned i = 0; i < 4; ++i) d->resistance_cap[i] =
        ember_attributes[EMBER_DATA_ATTR_FIRE_RESIST + i].maximum;
    d->reduction_cap = ember_attributes[EMBER_DATA_ATTR_REDUCTION].maximum;
    d->shield_delay = (uint16_t)ember_system[0].shield_delay;
    d->shield_recovery = ember_system[0].shield_recovery;
}
static void posture(struct ember_defense *d, int damage)
{
    if (!d->posture_max || d->broken) return;
    if (d->status[EMBER_STUN].frames) damage = damage * ember_system[0].stun_posture_percent / 100;
    d->posture = max(0, d->posture - damage);
    if (!d->posture) d->broken = (uint16_t)ember_system[0].broken_frames;
}
unsigned ember_status_apply(struct ember_defense *d, unsigned status, int duration, int strength)
{
    const struct ember_statuses_row *row = &ember_statuses[status];
    struct ember_status_state *state = &d->status[status];
    if (d->rank >= 2 && status == EMBER_STUN) {
        posture(d, row->posture * strength / 100);
        return 0;
    }
    if (d->rank >= 2 && status == EMBER_CHILL)
        posture(d, row->posture * strength / 100);
    unsigned reaction = 0;
    if (status == EMBER_IGNITE && d->status[EMBER_WET].frames) {
        d->status[EMBER_WET] = (struct ember_status_state){0};
        reaction |= 1u; /* steam */
    }
    state->frames = (uint16_t)(duration *
        ((status == EMBER_CHILL || status == EMBER_STUN || status == EMBER_BLIND) ?
            100 - d->tenacity : 100) / 100);
    state->stacks = (uint8_t)min(row->stacks, state->stacks + 1);
    if (status == EMBER_CHILL && d->rank < 2 && state->stacks == row->stacks)
        d->frozen = (uint16_t)(row->freeze_frames * (100 - d->tenacity) / 100);
    if (status == EMBER_SHOCK) reaction |= 2u;
    return reaction;
}
void ember_defense_step(struct ember_defense *d)
{
    if (d->invulnerable) --d->invulnerable;
    if (d->frozen) --d->frozen;
    if (d->broken && !--d->broken) d->posture = d->posture_max;
    if (d->since_hurt < d->shield_delay) ++d->since_hurt;
    else d->permanent_shield = min(d->shield_max, d->permanent_shield + d->shield_recovery);
    for (unsigned i = 0; i < EMBER_DAMAGE_TYPES + 1; ++i)
        if (d->shield_frames[i] && !--d->shield_frames[i]) d->temporary[i] = 0;
    for (unsigned i = 0; i < EMBER_STATUS_COUNT; ++i) {
        struct ember_status_state *st = &d->status[i];
        if (st->frames && !--st->frames) *st = (struct ember_status_state){0};
    }
}
static int32_t absorb(int32_t *shield, int32_t amount)
{
    int32_t used = min(*shield, amount);
    *shield -= used;
    return amount - used;
}
struct ember_damage_result ember_damage(struct ember_rng *rng, const struct ember_attack *h,
                                        struct ember_defense *d, int32_t *hp)
{
    struct ember_damage_result r = {0};
    if (d->invulnerable) return r;
    if (!(h->flags & EMBER_UNDODGEABLE) &&
        (int32_t)(ember_random(rng) % 100) < d->dodge) {
        r.dodged = 1;
        return r;
    }
    int64_t total = (int64_t)(h->base + h->flat) * EMBER_Q;
    total = total * h->attack / 100;
    total = total * (100 + h->increased) / 100;
    for (unsigned i = 0; i < 4; ++i) total = total * (100 + h->more[i]) / 100;
    if (!(h->flags & EMBER_DOT) || (h->flags & EMBER_DOT_CRIT)) {
        if ((int32_t)(ember_random(rng) % 100) < h->crit || (h->flags & EMBER_FORCE_CRIT)) {
            total = total * h->crit_damage / 100;
            r.crit = 1;
            if (h->crit > 100 && (int32_t)(ember_random(rng) % 100) < h->crit - 100) {
                total = total * (100 + (h->crit_damage - 100) *
                    ember_system[0].super_decay / 100) / 100;
                r.crit = 2;
            }
        }
    }
    int vulnerability = d->vulnerability;
    if (d->status[EMBER_SHOCK].frames) vulnerability += ember_statuses[EMBER_SHOCK].strength;
    if (d->broken) vulnerability += ember_system[0].broken_vulnerability;
    total = total * (100 + vulnerability) / 100;
    r.before_defense = (int32_t)(total / EMBER_Q);
    int blockable = 0;
    for (unsigned i = 0; i < EMBER_DAMAGE_TRUE; ++i)
        blockable |= h->share[i] + h->added[i];
    if (blockable && !(h->flags & EMBER_IGNORE_BLOCK) &&
        (d->active_block || (d->front_block && (h->flags & EMBER_FRONT)) ||
         (int32_t)(ember_random(rng) % 100) < d->block_chance)) r.blocked = 1;
    int64_t taken = 100000000;
    for (unsigned i = 0; i < 4; ++i) taken = taken * (100 - d->reduction[i]) / 100;
    taken = max((int32_t)taken, 1000000 * (100 - d->reduction_cap));
    int32_t shares[EMBER_DAMAGE_TYPES];
    memcpy(shares, h->share, sizeof(shares));
    int converted = shares[EMBER_DAMAGE_IRON] * h->conversion / 100;
    shares[EMBER_DAMAGE_IRON] -= converted;
    shares[EMBER_DAMAGE_FIRE] += converted;
    int dominant = -1;
    for (unsigned i = 0; i < EMBER_DAMAGE_TYPES; ++i) {
        int share = shares[i] + h->added[i];
        if (share > dominant) { dominant = share; r.dominant = (uint8_t)i; }
        int64_t part = total * share / 100;
        part = part * (100 + h->element_more[i]) / 100;
        if (i != EMBER_DAMAGE_TRUE) {
            if (r.blocked) part = part * (100 - d->block_strength) / 100;
            if (i == EMBER_DAMAGE_IRON) {
                int armor = d->armor;
                if (!d->immune_break) armor -= d->status[EMBER_BREAK_ARMOR].stacks *
                    (ember_statuses[EMBER_BREAK_ARMOR].strength + d->break_bonus);
                if (d->status[EMBER_WET].frames) armor = armor * (100 - d->rust) / 100;
                armor = max(0, armor);
                if (!d->immune_pierce) armor = armor * (100 - h->penetration) / 100;
                part = part * ember_system[0].armor_k / (ember_system[0].armor_k + armor);
            } else {
                int resistance = d->resistance[i - 1] + d->all_resistance;
                if (i == EMBER_DAMAGE_FIRE && d->status[EMBER_WET].frames)
                    resistance -= ember_statuses[EMBER_WET].strength;
                resistance = min(resistance, d->resistance_cap[i - 1]);
                part = part * (100 - resistance) / 100;
            }
        }
        part = (part / 100000000) * taken + (part % 100000000) * taken / 100000000;
        int32_t amount = (int32_t)(part / EMBER_Q);
        r.part[i] = amount;
        int32_t remaining = absorb(&d->temporary[i], amount);
        if (i != EMBER_DAMAGE_TRUE) {
            remaining = absorb(&d->temporary[EMBER_DAMAGE_TYPES], remaining);
            remaining = absorb(&d->permanent_shield, remaining);
        }
        r.absorbed += amount - remaining;
        r.damage += remaining;
    }
    *hp = max(0, *hp - r.damage);
    if (r.damage || r.absorbed) {
        d->since_hurt = 0;
        d->invulnerable = d->hurt_frames;
        int loss = h->posture + r.damage + r.absorbed;
        if (d->weakness < EMBER_DAMAGE_TYPES && r.part[d->weakness])
            loss = loss * ember_system[0].posture_weakness / 100;
        if (h->status_strength) loss = loss * h->status_strength / 100;
        posture(d, loss);
    }
    return r;
}
