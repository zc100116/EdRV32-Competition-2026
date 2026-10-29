/* File: game_logic.c
 * Spec: design rnd-disp 5.2; SoC 3.5; Task B3-3b.
 * Description: Axis-separated tile collision, jumps, patrols, collectibles and menus.
 * Clock domain: clk_sys CPU; one update per 60 Hz FRAME.
 */
#include "game_logic.h"
#include "game_assets.h"
#include "../s3_platform.h"

const struct game_object game_coins[GAME_COINS] = {
    {240, 584, 24, 32}, {480, 584, 24, 32}, {840, 584, 24, 32},
    {1160, 584, 24, 32}, {1504, 536, 24, 32}, {1800, 584, 24, 32},
    {2160, 528, 24, 32}, {2500, 584, 24, 32}, {3090, 584, 24, 32},
    {3510, 536, 24, 32}, {3780, 584, 24, 32}, {4760, 584, 24, 32}
};
const struct game_object game_spikes[2] = {
    {720, 592, 32, 32}, {4016, 592, 32, 32}
};

static int overlap(int x, int y, int w, int h, const struct game_object *o)
{
    return x < o->x + o->w && x + w > o->x && y < o->y + o->h && y + h > o->y;
}

static int solid(int x, int y)
{
    if (x < 0 || x >= GAME_WIDTH || y < 0 || y >= GAME_HEIGHT) {
        return 0; /* Outside the finite level is air; falling causes death below. */
    }
    unsigned int tile = game_map[(y / 16) * 320 + x / 16] & 4095u;
    return tile == 1 || tile == 2;
}

static int body_hits(int x, int y)
{
    for (int py = y; py < y + GAME_PLAYER_H; py += 16) {
        for (int px = x; px < x + GAME_PLAYER_W; px += 16) {
            if (solid(px, py) || solid(x + GAME_PLAYER_W - 1, py)) {
                return 1;
            }
        }
    }
    return solid(x, y + GAME_PLAYER_H - 1) ||
           solid(x + GAME_PLAYER_W - 1, y + GAME_PLAYER_H - 1);
}

void game_reset(struct game_state *g)
{
    *g = (struct game_state){.x = 80, .y = 576, .grounded = 1, .mode = GAME_PLAY};
}

int game_enemy_x(const struct game_state *g, unsigned int enemy)
{
    int phase = (int)((g->frame * 2 + enemy * 47) % 256);
    return (enemy == 0 ? 2800 : 4520) + (phase < 128 ? phase : 256 - phase) - 64;
}

void game_step(struct game_state *g, uint32_t keys)
{
    uint32_t pressed = keys & ~g->previous_keys;
    g->previous_keys = keys;
    if (g->mode == GAME_PAUSE) {
        if (pressed & (S3_KEY_LEFT | S3_KEY_RIGHT)) {
            g->selection ^= 1;
        }
        if (pressed & S3_KEY_PAUSE) {
            g->mode = GAME_PLAY;
        } else if (pressed & S3_KEY_JUMP) {
            g->mode = g->selection ? GAME_EXIT : GAME_PLAY;
        }
        return;
    }
    if (g->mode == GAME_DEAD || g->mode == GAME_WON) {
        if (pressed & S3_KEY_PAUSE) {
            g->mode = GAME_EXIT;
        } else if (pressed & S3_KEY_JUMP) {
            unsigned int deaths = g->deaths;
            game_reset(g);
            g->deaths = deaths;
            g->previous_keys = keys;
        }
        return;
    }
    if (g->mode == GAME_EXIT) {
        return;
    }
    if (pressed & S3_KEY_PAUSE) {
        g->mode = GAME_PAUSE;
        g->selection = 0;
        return;
    }
    ++g->frame;
    int dx = ((keys & S3_KEY_RIGHT) != 0) - ((keys & S3_KEY_LEFT) != 0);
    if (dx) {
        g->facing_left = dx < 0;
    }
    for (int i = 0; i < 6 && dx; ++i) {
        int nx = g->x + dx;
        if (nx >= 0 && nx <= GAME_WIDTH - GAME_PLAYER_W && !body_hits(nx, g->y)) {
            g->x = nx;
        }
    }
    if ((pressed & S3_KEY_JUMP) && g->grounded) {
        g->vy = -18;
        g->grounded = 0;
    }
    ++g->vy;
    if (g->vy > 18) {
        g->vy = 18;
    }
    int old_bottom = g->y + GAME_PLAYER_H;
    int dy = g->vy < 0 ? -1 : 1;
    g->grounded = 0;
    for (int i = 0; i < (g->vy < 0 ? -g->vy : g->vy); ++i) {
        if (body_hits(g->x, g->y + dy)) {
            g->grounded = dy > 0;
            g->vy = 0;
            break;
        }
        g->y += dy;
    }
    for (unsigned int i = 0; i < GAME_COINS; ++i) {
        if (!(g->collected & (1u << i)) &&
            overlap(g->x, g->y, GAME_PLAYER_W, GAME_PLAYER_H, &game_coins[i])) {
            g->collected |= 1u << i;
            g->score += 100;
        }
    }
    int died = g->y > GAME_HEIGHT;
    for (unsigned int i = 0; i < 2; ++i) {
        died |= overlap(g->x, g->y, GAME_PLAYER_W, GAME_PLAYER_H, &game_spikes[i]);
    }
    for (unsigned int i = 0; i < GAME_ENEMIES; ++i) {
        struct game_object enemy = {game_enemy_x(g, i), 592, 32, 32};
        if (!(g->defeated & (1u << i)) &&
            overlap(g->x, g->y, GAME_PLAYER_W, GAME_PLAYER_H, &enemy)) {
            if (dy > 0 && old_bottom <= enemy.y + 6) {
                g->defeated |= 1u << i;
                g->vy = -12;
                g->score += 200;
            } else {
                died = 1;
            }
        }
    }
    if (died) {
        ++g->deaths;
        g->mode = GAME_DEAD;
    } else if (g->x >= 4960) {
        g->mode = GAME_WON;
        g->score += 1000;
    }
    g->camera = g->x - 480;
    if (g->camera < 0) {
        g->camera = 0;
    }
    if (g->camera > GAME_WIDTH - GAME_SCREEN) {
        g->camera = GAME_WIDTH - GAME_SCREEN;
    }
}
