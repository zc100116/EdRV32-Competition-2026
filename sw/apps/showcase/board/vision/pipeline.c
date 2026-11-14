/* pipeline.c — PIPE-SPEC 7.1/7.4; whole-chain validation and greedy PIX packing.
 * No device access, scheduling, or allocation; CPU domain and host tests.
 */
#include "pipeline.h"
#include <string.h>
static int in(int value, int low, int high) { return value >= low && value <= high; }
unsigned pipe_chain_validate(const ui_chain_t *c)
{
    if (c->source > UI_SOURCE_TEST_IMAGE || c->count > UI_BLOCK_MAX || c->preset > 8 ||
        (c->view != UI_VIEW_FINAL && c->view != UI_VIEW_SOURCE && c->view >= c->count)) return 2;
    unsigned detected = 0;
    for (unsigned i = 0; i < UI_BLOCK_MAX; ++i) {
        const ui_block_t *b = &c->block[i];
        if (i >= c->count) {
            if (b->type || b->flags) return 2;
            for (unsigned j = 0; j < 5; ++j) if (b->p[j]) return 2;
            continue;
        }
        unsigned used = 0;
        switch (b->type) {
        case UI_BLOCK_LEVEL:
            if (!in(b->p[0], -256, 255) || !in(b->p[1], 0, 512)) return 2;
            used = 2; break;
        case UI_BLOCK_GAMMA:
            if (!in(b->p[0], 3, 30)) return 2;
            used = 1; break;
        case UI_BLOCK_FILTER:
            if (!in(b->p[0], 1, 6)) return 2;
            used = 1; break;
        case UI_BLOCK_BINARY:
            if (!in(b->p[0], 0, 255)) return 2;
            used = 1; break;
        case UI_BLOCK_GEO:
            if (!in(b->p[0], -180, 180) || !in(b->p[1], 50, 400) ||
                !in(b->p[2], -1280, 1280) || !in(b->p[3], -720, 720) ||
                (b->flags & ~3u)) return 2;
            used = 4; break;
        case UI_BLOCK_DETECT:
            if (detected++) return 2;
            break;
        case UI_BLOCK_OVERLAY:
            if (!b->flags || (b->flags & ~3u) || ((b->flags & 1) && !detected)) return 2;
            break;
        case UI_BLOCK_GRAY: case UI_BLOCK_INVERT: break;
        default: return 2;
        }
        if (b->type != UI_BLOCK_GEO && b->type != UI_BLOCK_OVERLAY && b->flags) return 2;
        for (unsigned j = used; j < 5; ++j) if (b->p[j]) return 2;
    }
    return 0;
}
static void add(ui_chain_t *c, unsigned type, unsigned flags, int p0, int p1, int p2)
{
    c->block[c->count++] = (ui_block_t){type, flags, {p0, p1, p2, 0, 0}};
}
void pipe_chain_preset(ui_chain_t *c, unsigned preset)
{
    *c = (ui_chain_t){.view = UI_VIEW_FINAL, .preset = preset};
    switch (preset) {
    case 2: add(c, UI_BLOCK_GRAY, 0, 0, 0, 0);
        add(c, UI_BLOCK_FILTER, 0, 4, 0, 0); break;
    case 3: add(c, UI_BLOCK_GEO, 0, 90, 100, 0); break;
    case 4: add(c, UI_BLOCK_GEO, 0, 0, 200, -160); c->block[0].p[3] = -90; break;
    case 6: add(c, UI_BLOCK_GAMMA, 0, 18, 0, 0);
        add(c, UI_BLOCK_LEVEL, 0, 16, 320, 0);
        add(c, UI_BLOCK_FILTER, 0, 2, 0, 0); break;
    case 7: add(c, UI_BLOCK_FILTER, 0, 2, 0, 0);
        add(c, UI_BLOCK_FILTER, 0, 4, 0, 0);
        add(c, UI_BLOCK_BINARY, 0, 128, 0, 0);
        add(c, UI_BLOCK_FILTER, 0, 6, 0, 0);
        add(c, UI_BLOCK_FILTER, 0, 2, 0, 0); return;
    case 8: c->source = UI_SOURCE_PC_IMAGE; break;
    default: break;
    }
    add(c, UI_BLOCK_DETECT, 0, 0, 0, 0);
    if (preset != 8) add(c, UI_BLOCK_OVERLAY, preset == 5 ? 3 : 1, 0, 0, 0);
    if (preset == 5) add(c, UI_BLOCK_GEO, 0, 30, 75, 0);
}
static int pix(unsigned type) { return type >= UI_BLOCK_LEVEL && type <= UI_BLOCK_INVERT; }
static unsigned pix_end(const ui_chain_t *c, unsigned start)
{
    unsigned rank = 0, filters = 0, used = 0, i = start;
    for (; i < c->count && pix(c->block[i].type); ++i) {
        unsigned type = c->block[i].type;
        unsigned next = type == UI_BLOCK_FILTER ? 3 + filters :
            type < UI_BLOCK_FILTER ? type : type + 1;
        if (next < rank || (type == UI_BLOCK_FILTER ? filters == 2 : (used & (1u << type))))
            break;
        rank = next; used |= 1u << type;
        if (type == UI_BLOCK_FILTER) ++filters;
    }
    return i;
}
static unsigned hop(struct pipe_plan *p, unsigned engine, unsigned first, unsigned last)
{
    unsigned n = p->count++;
    p->hop[n] = (ui_hop_t){.engine = engine, .first = first, .last = last};
    p->pix_first[n] = first;
    if (first != PIPE_NO_BLOCK)
        for (unsigned i = first; i <= last; ++i) p->block_hop[i] = n;
    return n;
}
void pipe_compile(const ui_chain_t *c, struct pipe_plan *p)
{
    memset(p, 0, sizeof *p);
    memset(p->sample, PIPE_NO_BLOCK, sizeof p->sample);
    unsigned i = 0;
    if (c->source == UI_SOURCE_CAMERA) {
        if (c->count && pix(c->block[0].type)) {
            i = pix_end(c, 0); hop(p, UI_HOP_CAM_PIX, 0, i - 1);
        } else hop(p, UI_HOP_CAM_RAW, PIPE_NO_BLOCK, PIPE_NO_BLOCK);
    }
    while (i < c->count) {
        unsigned first = i, type = c->block[i].type;
        if (pix(type)) { i = pix_end(c, i); hop(p, UI_HOP_MEM_PIX, first, i - 1); }
        else if (type == UI_BLOCK_DETECT) {
            if (i + 1 < c->count && pix(c->block[i + 1].type)) {
                i = pix_end(c, first + 1);
                unsigned n = hop(p, UI_HOP_MEM_PIX, first, i - 1);
                p->sample[n] = first; p->pix_first[n] = first + 1;
            } else {
                unsigned n = hop(p, UI_HOP_MEM_NPU, i, i); p->sample[n] = i++;
            }
        } else {
            hop(p, type == UI_BLOCK_GEO ? UI_HOP_GEO : UI_HOP_RND, i, i);
            if (type == UI_BLOCK_OVERLAY && (c->block[i].flags & 2)) p->hide_l1 = 1;
            ++i;
        }
    }
}
void pipe_chain_decode(ui_chain_t *c, const uint8_t bytes[100])
{
    c->source = bytes[0]; c->count = bytes[1]; c->view = bytes[2]; c->preset = bytes[3];
    for (unsigned i = 0; i < UI_BLOCK_MAX; ++i) {
        const uint8_t *b = bytes + 4 + 12 * i;
        c->block[i].type = b[0]; c->block[i].flags = b[1];
        for (unsigned j = 0; j < 5; ++j)
            c->block[i].p[j] = (int16_t)((unsigned)b[2+2*j] | ((unsigned)b[3+2*j] << 8));
    }
}
void pipe_chain_encode(uint8_t bytes[100], const ui_chain_t *c)
{
    bytes[0] = c->source; bytes[1] = c->count; bytes[2] = c->view; bytes[3] = c->preset;
    for (unsigned i = 0; i < UI_BLOCK_MAX; ++i) {
        uint8_t *b = bytes + 4 + 12 * i;
        b[0] = c->block[i].type; b[1] = c->block[i].flags;
        for (unsigned j = 0; j < 5; ++j) {
            unsigned v = (uint16_t)c->block[i].p[j]; b[2+2*j] = v; b[3+2*j] = v >> 8;
        }
    }
}
