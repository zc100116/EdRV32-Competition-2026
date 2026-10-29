/* File: game_render.c
 * Spec: rnd 2.1–2.6/5.4; DISP 4.2/5.3; SoC 7.3 R3/7.4.
 * Description: One static level, indexed sprites, glyph HUD and per-buffer dirty rectangles.
 * Clock domain: clk_sys CPU; synchronous batches complete through shared RND IRQ.
 */
#include "game_render.h"
#include "game_assets.h"
#include "../s3_platform.h"

/* ddr_app links all data/rodata/bss in DDR. Each array element starts on 4 KiB. */
_Alignas(4096) static uint16_t background[GAME_HEIGHT][GAME_WIDTH];
_Alignas(4096) static uint32_t overlays[2][GAME_HEIGHT][GAME_SCREEN];
_Alignas(32) static const uint32_t zero_row[GAME_SCREEN];
_Alignas(64) static struct rnd_command commands[256];
static struct rnd_rect previous[2][32];
static unsigned int previous_count[2];
static unsigned int count;
static unsigned int drawing;
static uint64_t render_ticks;

uint64_t game_render_ticks(void)
{
    return render_ticks;
}

const void *game_background(void)
{
    return background;
}

const void *game_overlay(unsigned int buffer)
{
    return overlays[buffer];
}

static struct rnd_common common(struct rnd_rect rect)
{
    struct rnd_common c = {
        .dst_base = rnd_physical(overlays[drawing]), .dst_stride = GAME_SCREEN * 4,
        .dst_fmt = RND_ARGB8888, .src_fmt = RND_I8,
        .clip = {0, 0, GAME_SCREEN - 1, GAME_HEIGHT - 1}, .rect = rect,
        .opa = 255
    };
    return c;
}

static void clear(struct rnd_rect rect)
{
    struct rnd_common c = common(rect);
    c.src_fmt = RND_ARGB8888;
    /* COPY preserves zero alpha. FILL with OPA=0 would preserve old pixels. */
    struct rnd_source source = {.base = rnd_physical(zero_row), .stride = 0};
    rnd_copy(&commands[count++], &c, &source);
}

static void remember(struct rnd_rect rect)
{
    if (rect.x0 < 0) {
        rect.x0 = 0;
    }
    if (rect.y0 < 0) {
        rect.y0 = 0;
    }
    if (rect.x1 >= GAME_SCREEN) {
        rect.x1 = GAME_SCREEN - 1;
    }
    if (rect.y1 >= GAME_HEIGHT) {
        rect.y1 = GAME_HEIGHT - 1;
    }
    previous[drawing][previous_count[drawing]++] = rect;
}

static void sprite(unsigned int kind, int x, int y, int w, int h, int flip)
{
    if (x + w <= 0 || x >= GAME_SCREEN || y + h <= 0 || y >= GAME_HEIGHT) {
        return; /* Only submit visible world objects. */
    }
    struct rnd_rect rect = {x, y, x + w - 1, y + h - 1};
    struct rnd_common c = common(rect);
    c.flags = flip ? RND_HFLIP : 0;
    struct rnd_blit blit = {
        .source = {.base = rnd_physical(game_sprites + kind * 16 * 24), .stride = 16},
        .scale_x = 16u * 65536u / (unsigned int)w,
        .scale_y = 24u * 65536u / (unsigned int)h,
        .palette = rnd_physical(game_palette), .key = 0
    };
    if (kind == 3) {
        c.src_fmt = RND_RGB565;
        c.flags |= RND_COLORKEY;
        blit.source.base = rnd_physical(game_spike_rgb565);
        blit.source.stride = 32;
        blit.key = 0xf81f;
    }
    rnd_blit(&commands[count++], &c, &blit);
    remember(rect);
}

static void panel(struct rnd_rect rect, uint32_t color)
{
    struct rnd_common c = common(rect);
    c.color = color;
    const int32_t steps[4] = {0, 0, 0, 0};
    rnd_fill(&commands[count++], &c, 0, 0, steps);
    remember(rect);
}

static void text(int x, int y, const char *label, uint32_t color)
{
    int start = x;
    for (; *label; ++label, x += 18) {
        unsigned int glyph = *label == ' ' ? 0 : *label <= '9' ?
                             (unsigned int)(*label - '0' + 1) :
                             (unsigned int)(*label - 'A' + 11);
        struct rnd_common c = common((struct rnd_rect){x, y, x + 14, y + 20});
        c.src_fmt = RND_A8;
        c.color = color;
        struct rnd_source source = {
            .base = rnd_physical(game_glyphs + glyph * 15 * 21), .stride = 15
        };
        rnd_glyph(&commands[count++], &c, &source);
    }
    remember((struct rnd_rect){start, y, x - 1, y + 20});
}

static void run(const struct rnd_range *targets, size_t target_count, int initial)
{
    struct rnd_range sources[] = {
        {game_palette, sizeof(game_palette)}, {game_tiles, sizeof(game_tiles)},
        {game_map, sizeof(game_map)}, {game_sprites, sizeof(game_sprites)},
        {game_glyphs, sizeof(game_glyphs)}, {zero_row, sizeof(zero_row)},
        {game_spike_rgb565, sizeof(game_spike_rgb565)},
        {background, sizeof(background)}, {overlays, sizeof(overlays)}
    };
    struct rnd_batch batch = {
        .commands = commands, .count = (uint16_t)count,
        .sources = sources, .source_count = initial ? 9 : 7,
        .targets = targets, .target_count = target_count
    };
    uint64_t start = s3_ticks();
    s3_rnd_run(&batch);
    render_ticks = s3_ticks() - start;
}

void game_render_init(void)
{
    count = 0;
    /* RND CLIP_X is 12 bits. Two 2560-wide views of a 5120-wide Surface keep
     * each clip representable, with the second destination rebased by 5120 B.
     */
    for (unsigned int half = 0; half < 2; ++half) {
        struct rnd_common c = {
            .dst_base = rnd_physical(&background[0][half * 2560]),
            .dst_stride = GAME_WIDTH * 2, .dst_fmt = RND_RGB565, .src_fmt = RND_I8,
            .flags = RND_TILE16, .clip = {0, 0, 2559, GAME_HEIGHT - 1},
            .rect = {0, 0, 2559, GAME_HEIGHT - 1}, .opa = 255
        };
        struct rnd_tilemap tilemap = {
            .tile_base = rnd_physical(game_tiles), .map_base = rnd_physical(game_map),
            .map_stride = 640, .map_x = half * 2560,
            .palette = rnd_physical(game_palette)
        };
        rnd_tilemap(&commands[count++], &c, &tilemap);
    }
    for (drawing = 0; drawing < 2; ++drawing) {
        previous_count[drawing] = 0;
        clear((struct rnd_rect){0, 0, GAME_SCREEN - 1, GAME_HEIGHT - 1});
    }
    struct rnd_range targets[] = {{background, sizeof(background)}, {overlays, sizeof(overlays)}};
    run(targets, 2, 1);
}

void game_render_frame(const struct game_state *g, unsigned int buffer)
{
    drawing = buffer;
    count = 0;
    for (unsigned int i = 0; i < previous_count[buffer]; ++i) {
        clear(previous[buffer][i]);
    }
    previous_count[buffer] = 0;
    for (unsigned int i = 0; i < GAME_COINS; ++i) {
        if (!(g->collected & (1u << i))) {
            sprite(4, game_coins[i].x - g->camera, game_coins[i].y, 24, 32, 0);
        }
    }
    for (unsigned int i = 0; i < 2; ++i) {
        sprite(3, game_spikes[i].x - g->camera, game_spikes[i].y, 32, 32, 0);
    }
    for (unsigned int i = 0; i < GAME_ENEMIES; ++i) {
        if (!(g->defeated & (1u << i))) {
            sprite(2, game_enemy_x(g, i) - g->camera, 592, 32, 32,
                   (g->frame * 2 + i * 47) % 256 >= 128);
        }
    }
    sprite((g->frame / 8) & 1u, g->x - g->camera, g->y,
           GAME_PLAYER_W, GAME_PLAYER_H, g->facing_left);
    panel((struct rnd_rect){24, 24, 1255, 77}, 0x142e48);
    text(42, 41, "AMBER RUN", 0xf5cc68);
    text(284, 41, "SCORE", 0xf5eed6);
    char digits[6];
    unsigned int score = g->score;
    digits[5] = '\0';
    for (int i = 4; i >= 0; --i) {
        digits[i] = (char)('0' + score % 10);
        score /= 10;
    }
    text(404, 41, digits, 0xf5cc68);
    text(638, 41, "AD MOVE  W JUMP  P MENU", 0xa5d6dd);
    if (g->mode != GAME_PLAY) {
        panel((struct rnd_rect){360, 238, 919, 455}, 0x142e48);
        if (g->mode == GAME_PAUSE) {
            text(484, 265, "PAUSED", 0xf5cc68);
            text(420, 320, "CONTINUE", g->selection == 0 ? 0xf5cc68 : 0x667f92);
            text(420, 363, "RETURN TO UI", g->selection == 1 ? 0xf5cc68 : 0x667f92);
            text(420, 414, "AD SELECT  W ACCEPT", 0xa5d6dd);
        } else {
            text(438, 275, g->mode == GAME_WON ? "LEVEL COMPLETE" : "TRY AGAIN", 0xf5cc68);
            text(420, 340, "W RESTART", 0xf5eed6);
            text(420, 389, "P RETURN TO UI", 0xa5d6dd);
        }
    }
    struct rnd_range target = {overlays[buffer], sizeof(overlays[buffer])};
    run(&target, 1, 0);
}
