/* File: cache.c; tech 5b. Compact I4/I8 -> block-aligned power-of-two pages.
 * CPU clock; immutable DDR frames, LRU excludes every current-frame reference.
 */
#include "gfx2d/cache.h"
#include "ui/ui.h"
#include "ui/font.h"
#include "plat.h"
#include "atlas.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
enum { MAX_PAGES = EMBER_CACHE_PAGE_CAPACITY, FONT_PAGE = 3, FONT_BYTES = 4096, GLYPHS = 200 };
struct page { uint32_t offset; uint16_t w,h; uint8_t lw,lh; };
struct resident { struct ember_art_slot slot; uint32_t used,uploaded; uint8_t present,loaded,required,visible,selected,equipment,branch; };
static struct page pages[MAX_PAGES];
static struct resident entries[EMBER_ART_FRAMES];
static uint16_t occupied[MAX_PAGES][8192];
static unsigned page_count, clock_tick, font_interface, font_dirty;
static unsigned font_valid;
static uint32_t glyph_used[GLYPHS];
static uint32_t glyph_codes[GLYPHS];
static const uint8_t *pixels;
static uint8_t *texture_pages, *font_pixels;
static uint8_t dirty[8192];
static unsigned texture_capacity;
static struct gpu_range sources[1];
static struct ember_gfx_stats stats;
static void fail(const struct ember_art_frame *f)
{
    plat_printf("Texture cache exhausted: %s/%s/%s/%u (%u bytes), visible %u\n",
        f->actor, f->action, f->direction, f->frame, f->bytes, stats.visible_bytes);
    fflush(stdout);abort();
}
static int place(unsigned id, unsigned first, unsigned end)
{
    const struct ember_art_frame *f = &ember_art_frames[id];
    unsigned block_h=f->format?2:4;
    unsigned w = f->bw / 4, h = f->bh / block_h;
    for (unsigned p = first; p < end; ++p) {
        unsigned pw = pages[p].w / 4, ph = pages[p].h / 2;
        if (w > pw || h > ph) continue;
        for (unsigned y = 0; y + h <= ph; ++y) {
            for (unsigned x = 0; x + w <= pw; ++x) {
                unsigned yy, xx = 0;
                for (yy = 0; yy < h; ++yy) {
                    for (xx = 0; xx < w; ++xx)
                        if (occupied[p][(y + yy) * pw + x + xx]) break;
                    if (xx != w) break;
                }
                if (yy != h) { x += xx; continue; }
                for (yy = 0; yy < h; ++yy)
                    for (xx = 0; xx < w; ++xx)
                        occupied[p][(y + yy) * pw + x + xx] = (uint16_t)(id + 1);
                entries[id].slot = (struct ember_art_slot){(uint16_t)p,(uint16_t)(x * 4),(uint16_t)(y * block_h)};
                entries[id].present = 1;
                return 1;
            }
        }
    }
    return 0;
}
void ember_cache_init(void)
{
    memset(entries, 0, sizeof(entries));
    memset(occupied, 0, sizeof(occupied));
    pages[0] = (struct page){0,256,128,8,7};
    pages[1] = (struct page){32768,128,128,7,7};
    pages[2] = (struct page){0,0,0,0,0};
    /* The final 4 KiB of page 1 is a separate I4 font descriptor. */
    for (unsigned i = 48 * 32; i < 64 * 32; ++i) occupied[1][i] = UINT16_MAX;
    pages[3] = (struct page){45056,128,64,7,6};
    /* 16 KiB byte pages: 128x128 I8 or 128x256 I4, both legal <=256.
     * Formats share eight-byte physical groups; a frame's UV selects its view. */
    page_count=EMBER_FPGA_ART?13:MAX_PAGES;
    for (unsigned i=4;i<page_count;++i)
        pages[i]=(struct page){49152+(i-4)*16384,128,128,7,7};
    static const char *branches[]={"base","evolution_a","evolution_b"};
    static const char *projectiles[]={"staff_projectile","staff_cluster_projectile","staff_core_projectile"};
    for (unsigned i=0;i<EMBER_ART_FRAMES;++i) {
        const struct ember_art_frame *f=&ember_art_frames[i];
        if (!strcmp(f->actor,"weapon_sword")) entries[i].equipment=1;
        else if (!strcmp(f->actor,"weapon_staff")) entries[i].equipment=2;
        for (unsigned branch=0;branch<3;++branch) {
            if (entries[i].equipment && !strcmp(f->action,branches[branch])) entries[i].branch=(uint8_t)branch;
            if (!strcmp(f->actor,"coast_small_fx") && !strcmp(f->action,projectiles[branch])) {
                entries[i].equipment=3;entries[i].branch=(uint8_t)branch;
            }
        }
    }
    texture_capacity = EMBER_FPGA_ART ? 196608 : 262144;
    pixels = ember_art_pixels;
    texture_pages = plat_dma_alloc(texture_capacity, 32);
    memset(texture_pages, 0, texture_capacity);
    memset(dirty, 0, sizeof(dirty));
    font_pixels = plat_dma_alloc(FONT_BYTES, 32);
    memset(font_pixels, 0, FONT_BYTES);
    memset(font_pixels + FONT_BYTES - 32, 255, 32);
    sources[0] = (struct gpu_range){(uintptr_t)texture_pages,texture_capacity};
    font_valid = clock_tick = 0;
    font_dirty = 1;
    memset(&stats, 0, sizeof(stats));
}
const struct ember_art_frame *ember_art_frame(unsigned id) { return &ember_art_frames[id]; }
static int compare(const struct ember_art_frame *f, const char *actor, const char *action, const char *direction)
{
    int c = strcmp(f->actor, actor);
    if (!c) c = strcmp(f->action, action);
    if (!c) c = strcmp(f->direction, direction);
    return c;
}
int ember_art_find(const char *actor, const char *action, const char *direction, unsigned tick, unsigned period)
{
    static unsigned recent_first,recent_count;
    if (recent_count && !compare(&ember_art_frames[recent_first],actor,action,direction))
        return (int)(recent_first+tick/period%recent_count);
    unsigned lo = 0, hi = EMBER_ART_FRAMES;
    while (lo < hi) {
        unsigned mid = lo + (hi - lo) / 2;
        if (compare(&ember_art_frames[mid], actor, action, direction) < 0) lo = mid + 1;
        else hi = mid;
    }
    if (lo == EMBER_ART_FRAMES || compare(&ember_art_frames[lo], actor, action, direction)) return -1;
    unsigned end = lo + 1;
    while (end < EMBER_ART_FRAMES && !compare(&ember_art_frames[end], actor, action, direction)) ++end;
    recent_first=lo;recent_count=end-lo;
    return (int)(lo + tick / period % (end - lo));
}
int ember_art_phase(const char *actor,const char *action,unsigned phase,unsigned tick,unsigned period)
{
    int first=ember_art_find(actor,action,"down",0,1);
    if (first<0) return first;
    unsigned count=0;
    for (unsigned i=(unsigned)first;i<EMBER_ART_FRAMES && !compare(&ember_art_frames[i],actor,action,"down");++i)
        if (ember_art_frames[i].effect_phase==phase) ++count;
    if (!count) return -1;
    unsigned selected=tick/period%count;
    for (unsigned i=(unsigned)first;i<EMBER_ART_FRAMES && !compare(&ember_art_frames[i],actor,action,"down");++i)
        if (ember_art_frames[i].effect_phase==phase && !selected--) return (int)i;
    return -1;
}
int ember_art_timed(const char *actor,const char *action,const char *direction,unsigned tick,unsigned duration)
{
    int first=ember_art_find(actor,action,direction,0,1);
    if (first<0) return first;
    unsigned end=(unsigned)first+1;
    while (end<EMBER_ART_FRAMES && !compare(&ember_art_frames[end],actor,action,direction)) ++end;
    unsigned count=end-(unsigned)first;
    unsigned index=duration?tick*count/duration:tick/4;
    if (index>=count) index=count-1;
    return first+(int)index;
}
void ember_cache_begin(void)
{
    ++clock_tick;
    for (unsigned i = 0; i < EMBER_ART_FRAMES; ++i) entries[i].required = entries[i].visible = entries[i].selected = 0;
    stats.visible_bytes = stats.load_bytes = 0;
}
static void evict(unsigned id);
static int equipment(const struct ember_art_frame *f)
{
    return entries[f-ember_art_frames].equipment;
}
void ember_cache_equipment(unsigned sword_evolution, unsigned staff_evolution)
{
    for (unsigned i=0;i<EMBER_ART_FRAMES;++i) {
        struct resident *r=&entries[i];
        if (r->equipment && r->branch==(r->equipment==1?sword_evolution:staff_evolution)) {
            r->selected=r->required=1;r->used=clock_tick;
        }
    }
}
void ember_cache_require(unsigned id)
{
    if (!entries[id].visible) stats.visible_bytes += ember_art_frames[id].bytes;
    entries[id].visible=1;
    entries[id].required = 1;
    entries[id].used = clock_tick;
}
static void evict(unsigned id)
{
    struct resident *r = &entries[id];
    const struct ember_art_frame *f = &ember_art_frames[id];
    unsigned pw = pages[r->slot.page].w / 4;
    for (unsigned y = 0; y < f->bh / (f->format?2:4); ++y)
        for (unsigned x = 0; x < f->bw / 4; ++x)
            occupied[r->slot.page][(r->slot.y / (f->format?2:4) + y) * pw + r->slot.x / 4 + x] = 0;
    r->present = r->loaded = 0;
}
static int fixed_required(unsigned i)
{
    const struct ember_art_frame *f=&ember_art_frames[i];
    return f->ui || (equipment(f)?entries[i].selected:f->fixed);
}
static void repack_fixed(void)
{
    /* Branch bodies can grow beyond the holes left by their predecessors.
     * Repack native rectangles without reducing frames, dimensions or quality. */
    for (unsigned i=0;i<EMBER_ART_FRAMES;++i) {
        if (entries[i].present && entries[i].slot.page<4) {
            if (!ember_art_frames[i].ui || entries[i].required) entries[i].required=1;
            evict(i);
        }
    }
    for (;;) {
        unsigned best=EMBER_ART_FRAMES;
        for (unsigned i=0;i<EMBER_ART_FRAMES;++i)
            if (entries[i].required && !entries[i].present && fixed_required(i) &&
                (best==EMBER_ART_FRAMES || ember_art_frames[i].bh*512u+ember_art_frames[i].bw>
                 ember_art_frames[best].bh*512u+ember_art_frames[best].bw)) best=i;
        if (best==EMBER_ART_FRAMES) break;
        if (!place(best,0,3)) fail(&ember_art_frames[best]);
    }
}
void ember_cache_resolve(void)
{
    /* All visible references are pinned before migration or LRU eviction. */
    for (unsigned i=0;i<EMBER_ART_FRAMES;++i)
        if (entries[i].present && equipment(&ember_art_frames[i]) &&
            ((entries[i].slot.page<4) != (entries[i].selected!=0))) evict(i);
    /* Frequent animations enter the fixed region as complete groups, on first
     * actual use. Unused projectile/skill groups consume no texture RAM. */
    for (unsigned i=0;i<EMBER_ART_FRAMES;++i) {
        const struct ember_art_frame *f=&ember_art_frames[i];
        if (!entries[i].visible || entries[i].loaded || !f->fixed || f->ui || equipment(f)) continue;
        for (unsigned j=0;j<EMBER_ART_FRAMES;++j)
            if (!strcmp(f->actor,ember_art_frames[j].actor) && !strcmp(f->action,ember_art_frames[j].action))
                entries[j].required=1;
    }
    for (;;) {
        unsigned best=EMBER_ART_FRAMES;
        for (unsigned i=0;i<EMBER_ART_FRAMES;++i)
            if (entries[i].required && !entries[i].present && fixed_required(i) &&
                (best==EMBER_ART_FRAMES || ember_art_frames[i].bh*512u+ember_art_frames[i].bw>
                 ember_art_frames[best].bh*512u+ember_art_frames[best].bw)) best=i;
        if (best==EMBER_ART_FRAMES) break;
        while (!place(best,0,3)) {
            unsigned victim=EMBER_ART_FRAMES;
            for (unsigned j=0;j<EMBER_ART_FRAMES;++j)
                if (entries[j].present && entries[j].slot.page<4 && ember_art_frames[j].ui && !entries[j].required &&
                    (victim==EMBER_ART_FRAMES || entries[j].used<entries[victim].used)) victim=j;
            if (victim==EMBER_ART_FRAMES) { repack_fixed();break; }
            evict(victim);
        }
    }
    for (unsigned i=0;i<EMBER_ART_FRAMES;++i) {
        if (!entries[i].required || entries[i].present) continue;
        while (!place(i,4,page_count)) {
            unsigned victim=EMBER_ART_FRAMES;
            for (unsigned j=0;j<EMBER_ART_FRAMES;++j)
                if (entries[j].present && !entries[j].required && entries[j].slot.page>=4 &&
                    (victim==EMBER_ART_FRAMES || entries[j].used<entries[victim].used)) victim=j;
            if (victim==EMBER_ART_FRAMES) fail(&ember_art_frames[i]);
            evict(victim);
        }
    }
}
struct ember_art_slot ember_cache_slot(unsigned id) { return entries[id].slot; }
void ember_cache_texture_filtered(struct gpu_command *command,unsigned page,unsigned palette,unsigned sample,unsigned format)
{
    const struct page *p=&pages[page];
    gpu_set_tex(command,&(struct gpu_set_tex_args){.offset=p->offset,.log2_w=p->lw,
        .log2_h=p->lh+(page!=FONT_PAGE && !format),.format=format,.levels=1,.pal_group=palette,.sample=sample});
}
void ember_cache_texture(struct gpu_command *command,unsigned page,unsigned palette)
{
    ember_cache_texture_filtered(command,page,palette,0,page==FONT_PAGE?0:1);
}
unsigned ember_cache_uploads(struct gpu_command *commands)
{
    unsigned n = 0;
    for (unsigned i = 0; i < EMBER_ART_FRAMES; ++i) {
        struct resident *r = &entries[i];
        const struct ember_art_frame *f = &ember_art_frames[i];
        if (!r->required || r->loaded) continue;
        const struct page *p = &pages[r->slot.page];
        unsigned block_h=f->format?2:4;
        for (unsigned y = 0; y < f->bh; y += block_h) {
            unsigned destination = p->offset + (r->slot.y + y)/block_h * p->w * 2 + r->slot.x * 2;
            unsigned bytes = f->bw * 2;
            memcpy(texture_pages + destination, pixels + f->offset + y/block_h * f->bw * 2, bytes);
            for (unsigned block = destination / 32; block < (destination + bytes + 31) / 32; ++block) dirty[block] = 1;
        }
        r->loaded = 1;r->uploaded=clock_tick;
    }
    if (font_dirty) {
        memcpy(texture_pages + pages[FONT_PAGE].offset, font_pixels, FONT_BYTES);
        for (unsigned block = pages[FONT_PAGE].offset / 32; block < (pages[FONT_PAGE].offset + FONT_BYTES) / 32; ++block) dirty[block] = 1;
        font_dirty = 0;
    }
    /* TEX_LOAD addresses/counts are 32-byte units. Merge complete dirty lines;
     * their untouched neighboring groups come from the CPU page shadow. */
    for (unsigned block = 0; block < texture_capacity / 32;) {
        if (!dirty[block]) { ++block; continue; }
        unsigned first = block;
        while (block < texture_capacity / 32 && dirty[block]) dirty[block++] = 0;
        unsigned bytes = (block - first) * 32;
        gpu_tex_load(&commands[n++], &(struct gpu_tex_load_args){
            .src=gpu_physical(texture_pages + first * 32),.bytes=bytes,.dst=first * 32});
        stats.load_bytes += bytes;
    }
    if (stats.load_bytes>32768) {
        plat_printf("ERROR TEX_LOAD budget: tick=%u bytes=%u limit=32768 (tech5b provisional)\n",clock_tick,stats.load_bytes);
        for (unsigned i=0;i<EMBER_ART_FRAMES;++i) if (entries[i].uploaded==clock_tick) {
            const struct ember_art_frame *f=&ember_art_frames[i];
            plat_printf("LOAD_ITEM,%s,%s,%s,%u,%u\n",f->actor,f->action,f->direction,f->frame,f->bytes);
        }
    }
    stats.fixed_bytes = FONT_BYTES;
    stats.cache_bytes = 0;
    for (unsigned i = 0; i < EMBER_ART_FRAMES; ++i) {
        if (!entries[i].loaded) continue;
        if (entries[i].slot.page<4) stats.fixed_bytes += ember_art_frames[i].bytes;
        else stats.cache_bytes += ember_art_frames[i].bytes;
    }
    if (stats.fixed_bytes > stats.fixed_peak) stats.fixed_peak = stats.fixed_bytes;
    if (stats.cache_bytes > stats.cache_peak) stats.cache_peak = stats.cache_bytes;
    if (stats.visible_bytes > stats.visible_peak) stats.visible_peak = stats.visible_bytes;
    if (stats.load_bytes > stats.load_peak) stats.load_peak = stats.load_bytes;
    return n;
}
static void write_glyph(uint32_t cp,unsigned index)
{
    unsigned width;
    const uint16_t *rows=ember_font_rows(cp,&width);
    unsigned cell=index/4,bit=1u<<(index%4);
    unsigned left=cell%10*12,top=cell/10*12;
    for (unsigned y=0;y<12;++y) for (unsigned x=0;x<12;++x) {
        unsigned u=left+x,v=top+y;
        unsigned address=8*((v/4)*32+u/4)+2*((u/2&1)+2*(v/2&1));
        unsigned shift=4*((u&1)+2*(v&1));
        uint16_t mask=(uint16_t)(bit<<shift);
        uint16_t value=(uint16_t)(font_pixels[address]|font_pixels[address+1]<<8);
        value=(uint16_t)(value&~mask);
        if (x<width && (rows[y]&(1u<<(11-x)))) value|=mask;
        font_pixels[address]=(uint8_t)value;font_pixels[address+1]=(uint8_t)(value>>8);
    }
}
static void write_number(unsigned digit,unsigned critical)
{
    unsigned advance;
    const uint16_t *rows=ember_font_rows('0'+digit,&advance);
    uint8_t ink[24][12]={{0}};
    unsigned height=critical?24:12;
    for (unsigned y=0;y<height;++y) for (unsigned x=1;x<=(critical?9u:6u);++x) {
        if (critical && (!y || y>18)) continue;
        unsigned sx=critical?(x-1)*2/3:x-1,sy=critical?(y-1)*2/3:y;
        ink[y][x]=(uint8_t)!!(rows[sy]&(1u<<(11-sx)));
    }
    for (unsigned y=0;y<height;++y) for (unsigned x=0;x<12;++x) {
        unsigned outline=0;
        for (int dy=-1;dy<=1;++dy) for (int dx=-1;dx<=1;++dx) {
            int xx=(int)x+dx,yy=(int)y+dy;
            if (xx>=0 && xx<12 && yy>=0 && yy<(int)height) outline|=ink[yy][xx];
        }
        unsigned u=digit*12+x,v=(critical?12:0)+y;
        unsigned address=8*((v/4)*32+u/4)+2*((u/2&1)+2*(v/2&1));
        unsigned shift=4*((u&1)+2*(v&1));
        uint16_t value=(uint16_t)(font_pixels[address]|font_pixels[address+1]<<8);
        value=(uint16_t)(value&~(3u<<shift));
        value|=(uint16_t)((ink[y][x]?1u:outline?2u:0u)<<shift);
        font_pixels[address]=(uint8_t)value;font_pixels[address+1]=(uint8_t)(value>>8);
    }
}
void ember_cache_glyphs(struct ember_ui_canvas *canvas,unsigned interface)
{
    if (!font_valid || interface!=font_interface) {
        font_valid=1;font_interface=interface;
        memset(glyph_codes,0,sizeof(glyph_codes));memset(glyph_used,0,sizeof(glyph_used));
        memset(font_pixels,0,FONT_BYTES-32);
        for (unsigned digit=0;digit<10;++digit) {
            glyph_codes[digit*4]='0'+digit;write_number(digit,0);write_number(digit,1);
        }
        font_dirty=1;
    }
    unsigned slots[EMBER_UI_GLYPHS];
    uint8_t needed[GLYPHS]={0};
    /* Two bitplanes in the first three cell rows hold outlined normal and
     * 1.5x critical digits. Other glyph planes remain independently cached. */
    for (unsigned cell=0;cell<30;++cell) needed[cell*4]=needed[cell*4+1]=1;
    for (unsigned i=0;i<canvas->glyph_count;++i) {
        unsigned index=0;
        while (index<GLYPHS && glyph_codes[index]!=canvas->codepoints[i]) ++index;
        slots[i]=index;
        if (index<GLYPHS) { needed[index]=1;glyph_used[index]=clock_tick; }
    }
    for (unsigned i=0;i<canvas->glyph_count;++i) {
        unsigned index=slots[i];
        if (index==GLYPHS) {
            index=0;
            while (index<GLYPHS && glyph_codes[index]!=canvas->codepoints[i]) ++index;
            if (index==GLYPHS) {
                unsigned victim=GLYPHS;
                for (unsigned j=0;j<GLYPHS;++j) if (!needed[j] &&
                    (victim==GLYPHS || !glyph_codes[j] || glyph_used[j]<glyph_used[victim])) {
                    victim=j;if (!glyph_codes[j]) break;
                }
                if (victim==GLYPHS) { plat_printf("Visible interface glyphs exceed cache (%u)\n",interface);fflush(stdout);abort(); }
                index=victim;glyph_codes[index]=canvas->codepoints[i];
                write_glyph(canvas->codepoints[i],index);font_dirty=1;
            }
            needed[index]=1;glyph_used[index]=clock_tick;
        }
        struct gpu_quad *q=&canvas->glyphs[i];
        unsigned width=(q->word[EDRV32_GPU_QUAD_W_OFFSET/4]&EDRV32_GPU_QUAD_W_MASK)>>EDRV32_GPU_QUAD_W_POS;
        struct gpu_quad_args args={
            .x=q->word[0]&EDRV32_GPU_QUAD_X_MASK,
            .y=(q->word[0]&EDRV32_GPU_QUAD_Y_MASK)>>EDRV32_GPU_QUAD_Y_POS,
            .w=width,.h=12,.alpha=255,.pal_group=12+index%4,
            .u0=index/4%10*12,.v0=index/4/10*12};
        gpu_quad(q,&args);
    }
}
unsigned ember_cache_font_page(void) { return FONT_PAGE; }
const struct gpu_range *ember_cache_sources(unsigned *count) { *count = 1; return sources; }
struct ember_gfx_stats *ember_cache_stats(void) { return &stats; }
void ember_cache_new_stage(void)
{
    stats.fixed_peak = stats.cache_peak = stats.visible_peak = stats.load_peak = stats.particle_peak = 0;
    stats.particle_visible_peak = 0;
    stats.facing_mask = stats.dir16_mask = 0;
}
/* Palette copies remain CPU resources; scene draws upload the requested bank. */
const uint32_t *ember_cache_palette(unsigned id) { return ember_art_palettes[id]; }
unsigned ember_cache_palette_count(void) { return EMBER_ART_PALETTES; }

uint32_t ember_art_corner(unsigned id)
{
    const struct ember_art_frame *f=&ember_art_frames[id];
    return ember_art_palettes[f->palette][f->format?pixels[f->offset]:pixels[f->offset]&15];
}
