/* File: ui.c
 * Spec: ember_isles gdd 3-5 and tech 2, E1/E2; GPU 2.8.
 * Description: Original pixel-font HUD, start, pause, upgrade and result screens.
 * Clock domain: CPU frame; builders perform no MMIO or platform calls.
 */
#include "ui/ui.h"
#include "data.h"
#include <stdio.h>
#include <string.h>

static void rect(struct ember_ui_canvas *out, int x, int y, unsigned w, unsigned h,
                 unsigned color, unsigned alpha)
{
    /* GPU quad width is nine bits; a full-width overlay is two rectangles. */
    while (w) {
        unsigned part = w > 511 ? 511 : w;
        gpu_quad(&out->rects[out->rect_count++], &(struct gpu_quad_args){
            .x = (uint32_t)x, .y = (uint32_t)y, .w = part, .h = h,
            .pal_group = color, .alpha = alpha
        });
        x += (int)part;
        w -= part;
    }
}

void ember_ui_text(struct ember_ui_canvas *out, int x, int y, const char *text, unsigned big)
{
    int origin = x;
    for (; *text; ++text) {
        unsigned c = (unsigned char)*text;
        if (c == '\n') { x = origin; y += big ? 19 : 12; continue; }
        if (c == '_') c = ' ';
        if (c >= 'a' && c <= 'z') c -= 'a' - 'A';
        if (c != ' ') {
            gpu_quad(&out->glyphs[out->glyph_count++], &(struct gpu_quad_args){
                .x = (uint32_t)x, .y = (uint32_t)y, .w = big ? 16 : 8,
                .h = big ? 16 : 8, .alpha = 255,
                .u0 = big ? 128 + (c - 32) % 8 * 16 : (c - 32) % 16 * 8,
                .v0 = big ? (c - 32) / 8 * 16 : 128 + (c - 32) / 16 * 8
            });
        }
        x += big ? 12 : 6;
    }
}

static void center(struct ember_ui_canvas *out, int y, const char *text, unsigned big)
{
    ember_ui_text(out, 320 - (int)strlen(text) * (big ? 6 : 3), y, text, big);
}

static void panel(struct ember_ui_canvas *out, int x, int y, unsigned w, unsigned h,
                  unsigned active)
{
    rect(out, x, y, w, h, active ? EMBER_FIRE : EMBER_EDGE, 255);
    rect(out, x + 1, y + 1, w - 2, h - 2, EMBER_PANEL, 249);
}

static void bar(struct ember_ui_canvas *out, int x, int y, unsigned w, unsigned h,
                unsigned value, unsigned maximum, unsigned color)
{
    rect(out, x, y, w, h, EMBER_TRACK, 255);
    /* Banked XP can fund several upgrades; the gauge stays full above its threshold. */
    unsigned fill = value >= maximum ? w : w * value / maximum;
    if (fill) rect(out, x, y, fill, h, color, 255);
}

static void choice(struct ember_ui_canvas *out, const struct ember_sim *sim, unsigned i)
{
    const struct ember_choice *c = &sim->choices[i];
    int x = 40 + (int)i * 190;
    const char *name;
    const char *tag;
    const char *effect;
    static const char *weapon_effects[4] = {
        "AUTO AIM / EMBER SHOT", "PULSE / AREA DAMAGE",
        "LINGERING / BURN", "LOBBED / EXPLOSION"
    };
    static const char *inscription_effects[4] = {
        "SPLIT INTO 3 SHOTS", "AREA FOLLOWS YOU",
        "+25% VS BURNING", "LARGER DEATH BLAST"
    };
    char detail[64];
    if (c->kind == 0) {
        name = ember_weapons[c->id].name;
        tag = "WEAPON";
        effect = weapon_effects[c->id];
        (void)snprintf(detail, sizeof(detail), "LEVEL %u / %d",
                       sim->player.weapon_level[c->id] + 1, (int)ember_weapons[c->id].level_max);
    } else if (c->kind == 1) {
        name = ember_relics[c->id].name;
        tag = "RELIC";
        effect = "PASSIVE STAT BONUS";
        (void)snprintf(detail, sizeof(detail), "%s +%d%s", ember_relics[c->id].attribute,
                       (int)(ember_relics[c->id].flat ? ember_relics[c->id].flat :
                       ember_relics[c->id].increased),
                       ember_relics[c->id].flat ? "" : "%");
    } else {
        name = ember_inscriptions[c->id].name;
        tag = "INSCRIPTION";
        effect = inscription_effects[c->id];
        (void)snprintf(detail, sizeof(detail), "FOR %s", ember_weapons[c->slot].name);
    }
    panel(out, x, 132, 180, 140, sim->selected == i);
    rect(out, x + 12, 148, 18, 3, sim->selected == i ? EMBER_FIRE : EMBER_TIDE, 255);
    ember_ui_text(out, x + 12, 163, tag, 0);
    ember_ui_text(out, x + 12, 185, name, 0);
    ember_ui_text(out, x + 12, 207, effect, 0);
    ember_ui_text(out, x + 12, 227, detail, 0);
    ember_ui_text(out, x + 12, 251, sim->selected == i ? "[ A ] CHOOSE" : "", 0);
}

void ember_ui_build(struct ember_ui_canvas *out, const struct ember_sim *sim,
                    const struct ember_ui_state *state, unsigned fps, const uint32_t *perf,
                    unsigned particles)
{
    char text[128];
    unsigned remaining = 0;
    if (sim->wave) {
        unsigned limit = (unsigned)ember_waves[sim->wave - 1].time_limit;
        remaining = sim->wave_frame < limit ? (limit - sim->wave_frame + 59) / 60 : 0;
        if (sim->rest) remaining = (sim->rest + 59) / 60;
    }
    out->rect_count = 0;
    out->glyph_count = 0;
    if (sim->phase == EMBER_PLAY || sim->phase == EMBER_UPGRADE) {
        panel(out, 10, 9, 204, 40, 0);
        ember_ui_text(out, 20, 17, "KEEPER", 0);
        (void)snprintf(text, sizeof(text), "%d / %d", (int)sim->player.hp,
                       (int)sim->player.max_hp);
        ember_ui_text(out, 112, 17, text, 0);
        bar(out, 20, 33, 184, 6, (unsigned)sim->player.hp,
            (unsigned)sim->player.max_hp, EMBER_HEALTH);
        panel(out, 230, 9, 180, 40, 0);
        (void)snprintf(text, sizeof(text), "WAVE %u / 5    %02u:%02u", (unsigned)sim->wave,
                       remaining / 60, remaining % 60);
        ember_ui_text(out, 242, 17, text, 0);
        ember_ui_text(out, 242, 33, sim->rest ? "GATHER THE EMBERS" : "THE TIDE APPROACHES", 0);
        panel(out, 426, 9, 204, 40, 0);
        (void)snprintf(text, sizeof(text), "LEVEL %u    XP %u/%u", (unsigned)sim->player.level,
                       (unsigned)sim->player.xp, (unsigned)sim->player.next_xp);
        ember_ui_text(out, 438, 17, text, 0);
        bar(out, 438, 33, 180, 6, sim->player.xp, sim->player.next_xp, EMBER_TIDE);
        panel(out, 10, 319, 408, 31, 0);
        (void)snprintf(text, sizeof(text), "Z DASH %u    X SEED %u    Z+X BURST %u%%",
                       sim->player.cooldown_a / 60, sim->player.cooldown_b / 60,
                       sim->player.charge / 10);
        ember_ui_text(out, 20, 330, text, 0);
        (void)snprintf(text, sizeof(text), "BOLT %u RING %u BED %u POT %u",
                       sim->player.weapon_level[0], sim->player.weapon_level[1],
                       sim->player.weapon_level[2], sim->player.weapon_level[3]);
        ember_ui_text(out, 430, 330, text, 0);
    }
    if (sim->phase == EMBER_MENU) {
        rect(out, 0, 0, 640, 360, EMBER_SHADE, 110);
        panel(out, 128, 66, 384, 228, 0);
        rect(out, 304, 87, 32, 3, EMBER_FIRE, 255);
        center(out, 109, "EMBER ISLES", 1);
        center(out, 139, "THE LAST LIGHT ON THE SHORE", 0);
        center(out, 177, "KEEP THE FIRE. HOLD THE COAST.", 0);
        center(out, 203, "5 WAVES / 4 WEAPONS / ONE KEEPER", 0);
        panel(out, 218, 237, 204, 30, 1);
        center(out, 248, "ENTER / START TO BEGIN", 0);
        center(out, 314, "ARROWS MOVE    Z DASH    X SEED    Z+X BURST", 0);
    } else if (sim->phase == EMBER_UPGRADE) {
        rect(out, 0, 50, 640, 265, EMBER_SHADE, 215);
        center(out, 77, "FEED THE FLAME", 1);
        center(out, 108, "CHOOSE ONE GIFT FOR THIS RUN", 0);
        for (unsigned i = 0; i < 3; ++i) choice(out, sim, i);
        center(out, 278, "LEFT / RIGHT SELECT    Z / A CONFIRM", 0);
    } else if (sim->phase == EMBER_WON || sim->phase == EMBER_LOST) {
        rect(out, 0, 0, 640, 360, EMBER_SHADE, 185);
        panel(out, 128, 83, 384, 200, sim->phase == EMBER_WON);
        center(out, 108, sim->phase == EMBER_WON ? "THE LIGHT ENDURES" : "LOST TO THE TIDE", 1);
        center(out, 143, sim->phase == EMBER_WON ? "THE COAST IS SAFE TONIGHT" :
                                                 "ANOTHER EMBER WILL RISE", 0);
        (void)snprintf(text, sizeof(text), "KILLS %u    DAMAGE %u", (unsigned)sim->player.kills,
                       (unsigned)sim->damage_total);
        center(out, 178, text, 0);
        (void)snprintf(text, sizeof(text), "LEVEL %u    TIME %02u:%02u",
                       (unsigned)sim->player.level,
                       (unsigned)sim->combat_frame / 3600, (unsigned)sim->combat_frame / 60 % 60);
        center(out, 201, text, 0);
        center(out, 249, "ENTER / START TO RETURN", 0);
    } else if (sim->paused) {
        rect(out, 0, 50, 640, 265, EMBER_SHADE, 180);
        panel(out, 192, 130, 256, 100, 0);
        center(out, 152, "PAUSED", 1);
        center(out, 197, "ENTER / START TO CONTINUE", 0);
    }
    if (state->show_perf) {
        panel(out, 10, 55, 294, 60, 0);
        (void)snprintf(text, sizeof(text), "FPS %u E %u S %u P %u", fps,
                       (unsigned)sim->alive_count, (unsigned)sim->shot_count, particles);
        ember_ui_text(out, 20, 65, text, 0);
        (void)snprintf(text, sizeof(text), "GPU %u Q %u PX %u", (unsigned)perf[0],
                       (unsigned)perf[3], (unsigned)perf[4]);
        ember_ui_text(out, 20, 81, text, 0);
        (void)snprintf(text, sizeof(text), "OBJ %u TEX %u DDR %u", (unsigned)perf[8],
                       (unsigned)perf[5], (unsigned)perf[6]);
        ember_ui_text(out, 20, 97, text, 0);
    }
}
