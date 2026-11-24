/* gpu_emu.h — gpu-spec 2–6: synchronous C11 functional reference API.
 * DDR addresses are physical offsets into caller-owned memory. No clock domain.
 */
#ifndef GPU_EMU_H
#define GPU_EMU_H
#include <stdint.h>
#ifndef GPU_EMU_TEXTURE_BYTES
#define GPU_EMU_TEXTURE_BYTES (192u * 1024u)
#endif
/* Lifetime high-water marks, including across GPU soft resets. Texture bytes
 * are the highest loaded end offset: the RAM capacity required by the layout. */
struct gpu_emu_usage {
    uint32_t texture_bytes;
    uint32_t object_slots;
    uint32_t objects_alive;
};
struct gpu_emu;
struct gpu_emu *gpu_emu_create(uint8_t *ddr, uint32_t ddr_bytes);
void gpu_emu_destroy(struct gpu_emu *emu);
uint32_t gpu_emu_read(struct gpu_emu *emu, uint32_t offset);
void gpu_emu_write(struct gpu_emu *emu, uint32_t offset, uint32_t value);
int gpu_emu_irq(const struct gpu_emu *emu);
struct gpu_emu_usage gpu_emu_usage(const struct gpu_emu *emu);
#endif
