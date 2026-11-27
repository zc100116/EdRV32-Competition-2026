/* demo.h — G-4 and gpu-spec 2; original dungeon/world scene interface.
 * CPU frame thread builds the shared GPU draw buffers.
 */
#ifndef GPU_DEMO_H
#define GPU_DEMO_H
#include "test.h"
void rogue_init(void);
void rogue_update(uint32_t keys);
void rogue_scene(void);
void rogue_capture(unsigned event);
void world_init(void);
void world_update(uint32_t keys);
void world_scene(void);
void world_capture(unsigned event);
void demo_load(void);
void demo_text(int x, int y, const char *text, unsigned color);
void demo_diagnostics(unsigned blocks);
extern unsigned world_lod;
extern unsigned world_time;
#endif
