/* File: pc_soc.h
 * Spec: PC design 4.1, 4.3.
 * Description: Host DDR, media frame clock and interrupt delivery.
 * Clock domain: host main loop.
 */
#ifndef EDRV32_PC_SOC_H
#define EDRV32_PC_SOC_H
#include <stdint.h>
#include <stddef.h>
#include "plat.h"
#include "gpu_emu.h"
struct gpu_emu_usage pc_soc_gpu_usage(void);
/* Frontends publish the game bitmap and logical menu pointer together. */
void pc_soc_game_input(uint16_t keys, struct plat_pointer_state pointer);
uint32_t pc_soc_game_keys(void);
struct plat_pointer_state pc_soc_pointer(void);
void pc_soc_init(void);
void pc_soc_destroy(void);
void *pc_soc_alloc(size_t bytes, size_t alignment);
void pc_soc_vsync(uint32_t audio_frames);
void pc_soc_interrupt(void (*handler)(void));
void pc_soc_trace_begin(const char *directory);
void pc_soc_trace_end(void);
const uint32_t *pc_soc_pixels(void);
/* Frontend supplies the display clock, keyboard and audio sink. */
uint32_t pc_frontend_wait(void);
uint32_t pc_frontend_keys(void);
uint32_t pc_frontend_millis(void);
void pc_frontend_audio(const int16_t *samples, uint32_t frames);
#endif
