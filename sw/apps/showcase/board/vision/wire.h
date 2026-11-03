/* wire.h — showcase design 4.5.4; EDNM/EDDT boundary helpers.
 * Caller supplies complete uploaded buffers; CPU domain.
 */
#ifndef SHOWCASE_VISION_WIRE_H
#define SHOWCASE_VISION_WIRE_H
#include "yolo_post.h"
#include <stddef.h>
uint32_t vision_read32(const uint8_t *bytes);
const char *vision_model_header(const uint8_t *header, uint32_t bytes);
size_t vision_detection_pack(uint8_t *out, const yolo_detection *boxes,
                             unsigned count, uint32_t frame, uint32_t request);
#endif
