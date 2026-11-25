/* File: cache.h; tech 5b. Native compact frames in pinned LRU pages; CPU clock. */
#ifndef EMBER_GFX_CACHE_H
#define EMBER_GFX_CACHE_H
#include "gpu.h"
enum { EMBER_CACHE_PAGE_CAPACITY=17 };
struct ember_art_frame {
    const char *actor, *action, *direction;
    uint16_t frame,w,h,bw,bh;
    int16_t ax,ay,hx,hy;
    uint16_t palette,fixed;
    uint32_t offset,bytes;
    uint16_t variants[6];
    uint8_t blend_fs,blend_fd,blend_op,sample,ui,source_dir16,effect_phase,global_alpha,format;
};
struct ember_art_slot { uint16_t page,x,y; };
struct ember_gfx_stats {
    uint32_t fixed_bytes, cache_bytes, visible_bytes, load_bytes, particles;
    uint32_t particle_visible, particle_visible_peak, number_objects;
    uint32_t facing_mask, dir16_mask;
    uint32_t elites, heads, bosses;
    uint32_t fixed_peak, cache_peak, visible_peak, load_peak, particle_peak;
};
struct ember_ui_canvas;
void ember_cache_init(void);
void ember_cache_begin(void);
void ember_cache_equipment(unsigned sword_evolution, unsigned staff_evolution);
int ember_art_phase(const char *actor,const char *action,unsigned phase,unsigned tick,unsigned period);
int ember_art_timed(const char *actor,const char *action,const char *direction,unsigned tick,unsigned duration);
int ember_art_find(const char *actor, const char *action, const char *direction, unsigned tick, unsigned period);
const struct ember_art_frame *ember_art_frame(unsigned id);
void ember_cache_require(unsigned id);
void ember_cache_resolve(void);
struct ember_art_slot ember_cache_slot(unsigned id);
void ember_cache_texture_filtered(struct gpu_command *command,unsigned page,unsigned palette,unsigned sample,unsigned format);
void ember_cache_texture(struct gpu_command *command, unsigned page, unsigned palette);
unsigned ember_cache_uploads(struct gpu_command *commands);
void ember_cache_glyphs(struct ember_ui_canvas *canvas, unsigned interface);
unsigned ember_cache_font_page(void);
const struct gpu_range *ember_cache_sources(unsigned *count);
struct ember_gfx_stats *ember_cache_stats(void);
void ember_cache_new_stage(void);
const uint32_t *ember_cache_palette(unsigned id);
uint32_t ember_art_corner(unsigned id);
unsigned ember_cache_palette_count(void);
#endif
