/* gpu_emu.h — gpu-spec 2–6: synchronous C11 functional reference API.
 * DDR addresses are physical offsets into caller-owned memory. No clock domain.
 */
#ifndef GPU_EMU_H
#define GPU_EMU_H
#include <stdint.h>
struct gpu_emu;
struct gpu_emu *gpu_emu_create(uint8_t *ddr, uint32_t ddr_bytes);
void gpu_emu_destroy(struct gpu_emu *emu);
uint32_t gpu_emu_read(struct gpu_emu *emu, uint32_t offset);
void gpu_emu_write(struct gpu_emu *emu, uint32_t offset, uint32_t value);
int gpu_emu_irq(const struct gpu_emu *emu);
#endif
