/* File: meta.c; GDD 3.3/6, tech 2: progression and real host save files.
 * Description: Unlock achievements, one-time purchases and free pre-run selection.
 * Clock domain: host menu/run completion, outside fixed-step simulation.
 */
#include "meta.h"
#include "sim/sim.h"
#include "data.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>
void ember_meta_init(struct ember_meta *m)
{
    memset(m, 0, sizeof(*m));
    for (unsigned c = 0; c < 8; ++c) {
        if (ember_meta_characters[c].initial) m->characters |= (uint8_t)(1u << c);
        m->unlocked[c] = 1;
        m->selected[c][0] = 0;
        for (unsigned row = 1; row < 4; ++row) m->selected[c][row] = 255;
    }
}
int ember_meta_character_ready(const struct ember_meta *m, unsigned character)
{
    const struct ember_meta_characters_row *c = &ember_meta_characters[character];
    switch (c->unlock_kind) {
    case 0: return 1;
    case 1: return !!(m->bosses & (1u << c->unlock_target));
    case 2: return m->hidden_rooms >= (unsigned)c->unlock_required;
    case 3: return m->arena_pillars >= (unsigned)c->unlock_required;
    }
    abort();
}
int ember_meta_unlock_character(struct ember_meta *m, unsigned character)
{
    if (m->characters & (1u << character)) return 1;
    unsigned cost = (unsigned)ember_meta_characters[character].unlock_cost;
    if (!ember_meta_character_ready(m, character) || m->fragments < cost) return 0;
    m->fragments -= cost;
    m->characters |= (uint8_t)(1u << character);
    return 1;
}
int ember_meta_unlock_talent(struct ember_meta *m, unsigned character, unsigned node)
{
    if (!(m->characters & (1u << character))) return 0;
    if (m->unlocked[character] & (1u << node)) return 1;
    const struct ember_talents_row *t = &ember_talents[node];
    if (t->row && !(m->unlocked[character] & (3u << (2 * (t->row - 1))))) return 0;
    if (m->fragments < (unsigned)t->cost) return 0;
    m->fragments -= (unsigned)t->cost;
    m->unlocked[character] |= (uint8_t)(1u << node);
    if (m->selected[character][t->row] == 255)
        m->selected[character][t->row] = (uint8_t)t->option;
    return 1;
}
int ember_meta_select_talent(struct ember_meta *m, unsigned character, unsigned node)
{
    if (!(m->unlocked[character] & (1u << node))) return 0;
    m->selected[character][ember_talents[node].row] = (uint8_t)ember_talents[node].option;
    return 1;
}
void ember_meta_config(const struct ember_meta *m, unsigned character, unsigned pet,
                        unsigned difficulty, struct ember_run_config *c)
{
    if (!(m->characters & (1u << character)) || difficulty > m->difficulty ||
        (pet != 255 && !m->codex.pets[pet])) {
        fputs("Unavailable character, difficulty or pet in run configuration\n", stderr);
        abort();
    }
    ember_run_config_default(c);
    c->character = (uint8_t)character;
    c->pet = (uint8_t)pet;
    c->difficulty = (uint8_t)difficulty;
    memcpy(c->talents, m->selected[character], sizeof(c->talents));
    c->main_weapon = (uint8_t)(c->talents[0] == 0 ?
        ember_meta_characters[character].weapon_a : ember_meta_characters[character].weapon_b);
}
void ember_meta_commit(struct ember_meta *m, const struct ember_sim *s)
{
    const struct ember_meta_rules_row *r = &ember_meta_rules[0];
    m->fragments += s->boss_kills * (unsigned)r->boss_fragments +
        s->hidden_rooms * (unsigned)r->hidden_fragments;
    m->bosses |= s->bosses_defeated;
    if (s->config.mode == EMBER_ROUTE) m->hidden_rooms += s->hidden_rooms;
    if (s->config.mode == EMBER_ARENA) m->arena_pillars += s->pillars_lit;
    for (unsigned i = 0; i < 6; ++i)
        if (s->discoveries.pets[i] && !m->codex.pets[i])
            m->fragments += (unsigned)r->pet_fragments;
    if (s->phase == EMBER_WON) {
        m->fragments += (unsigned)r->win_fragments;
        if (m->difficulty <= s->config.difficulty &&
            m->difficulty < (unsigned)r->difficulty_affixes) ++m->difficulty;
    }
#define MERGE(field) \
    for (unsigned i = 0; i < sizeof(m->codex.field); ++i) \
        m->codex.field[i] |= s->discoveries.field[i]
    MERGE(enemies); MERGE(weapons); MERGE(relics); MERGE(inscriptions);
    MERGE(blessings); MERGE(resonances); MERGE(pet_weapons); MERGE(pets); MERGE(world);
#undef MERGE
}
static void save_bytes(FILE *f, const uint8_t *p, size_t count)
{
    for (size_t i = 0; i < count; ++i) fprintf(f, "%u%c", p[i], i + 1 == count ? '\n' : ' ');
}
static void load_bytes(FILE *f, uint8_t *p, size_t count, const char *path)
{
    for (size_t i = 0; i < count; ++i) {
        unsigned value;
        if (fscanf(f, "%u", &value) != 1 || value > 255) {
            fprintf(stderr, "Invalid save field in %s\n", path);
            exit(1);
        }
        p[i] = (uint8_t)value;
    }
}
void ember_meta_save(const struct ember_meta *m, const char *path)
{
    FILE *f = fopen(path, "w");
    if (!f) { perror(path); exit(1); }
    fprintf(f, "EMBERMETA1 %" PRIu32 " %" PRIu32 " %" PRIu32 " %" PRIu32 " %u %u\n",
        m->fragments, m->hidden_rooms, m->arena_pillars, m->bosses, m->characters, m->difficulty);
    save_bytes(f, m->unlocked, sizeof(m->unlocked));
    for (unsigned c = 0; c < 8; ++c) save_bytes(f, m->selected[c], 4);
#define SAVE(field) save_bytes(f, m->codex.field, sizeof(m->codex.field))
    SAVE(enemies); SAVE(weapons); SAVE(relics); SAVE(inscriptions); SAVE(blessings);
    SAVE(resonances); SAVE(pet_weapons); SAVE(pets); SAVE(world);
#undef SAVE
    if (ferror(f) || fclose(f)) { perror(path); exit(1); }
}
void ember_meta_load(struct ember_meta *m, const char *path)
{
    FILE *f = fopen(path, "r");
    if (!f) { perror(path); exit(1); }
    char magic[16];
    unsigned characters, difficulty;
    if (fscanf(f, "%15s %" SCNu32 " %" SCNu32 " %" SCNu32 " %" SCNu32 " %u %u",
        magic, &m->fragments, &m->hidden_rooms, &m->arena_pillars, &m->bosses,
        &characters, &difficulty) != 7 || strcmp(magic, "EMBERMETA1") ||
        characters > 255 || difficulty > (unsigned)ember_meta_rules[0].difficulty_affixes) {
        fprintf(stderr, "Invalid save header: %s\n", path);
        exit(1);
    }
    m->characters = (uint8_t)characters;
    m->difficulty = (uint8_t)difficulty;
    load_bytes(f, m->unlocked, sizeof(m->unlocked), path);
    for (unsigned c = 0; c < 8; ++c) load_bytes(f, m->selected[c], 4, path);
#define LOAD(field) load_bytes(f, m->codex.field, sizeof(m->codex.field), path)
    LOAD(enemies); LOAD(weapons); LOAD(relics); LOAD(inscriptions); LOAD(blessings);
    LOAD(resonances); LOAD(pet_weapons); LOAD(pets); LOAD(world);
#undef LOAD
    if (fclose(f)) { perror(path); exit(1); }
}
