/* File: vin.h
 * Spec: vin-spec 2.6, 4.2–4.4, 5.1
 * Description: B2 media engine software interface.
 * Clock domain: clk_sys CPU; engine registers in clk_mem.
 */
#ifndef EDRV32_VIN_H
#define EDRV32_VIN_H
#include "engine.h"
enum vin_source { VIN_CAM0, VIN_CAM1, VIN_MEMORY };
struct vin_channel {
    enum vin_source source;
    unsigned int ring_count;
    uint32_t stride;
    uint32_t base[4];
    uint32_t busy_slots;
};
struct vin_frame {
    uint32_t info;
    uint32_t frame_id;
};
/* VIN 4.2: set one camera's expected width/height before its next frame. */
void vin_camera_size(unsigned int camera, unsigned int width, unsigned int height);
/* VIN 4.3: configure bases/stride/ownership before enabling the selected channel. */
void vin_channel_configure(unsigned int channel, const struct vin_channel *config);
/* VIN 4.3, 5.2: enable/disable one channel, retaining its source and ring settings. */
void vin_channel_enable(unsigned int channel, unsigned int enabled);
/* VIN 4.3: write the complete ownership bitmap; caller serializes IRQ/main updates. */
void vin_slots_busy(unsigned int channel, uint32_t slots);
/* VIN 4.3, 5.1: read the last frame's raw flags/slot/source and matching frame_id. */
struct vin_frame vin_frame_done(unsigned int channel);
/* VIN 4.3: extract the ring slot from CHn_DONE_INFO. */
unsigned int vin_frame_slot(uint32_t info);
/* VIN 4.2: configure and start one RGB565 memory frame (physical address). */
void vin_memory_start(uint32_t base, uint32_t stride, unsigned int width, unsigned int height);
/* VIN 4.2: read memory-source busy independently of channel writes. */
uint32_t vin_memory_status(void);
/* VIN 4.3: read ACTIVE and in-progress SLOT; caller uses it for ownership handoff. */
uint32_t vin_write_status(unsigned int channel);
#endif
