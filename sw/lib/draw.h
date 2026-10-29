/* draw.h — SoC spec 7.3; B2 software design 3.2/3.4.
 * RGB565 rectangles and printable 8x16 ASCII detection labels.
 * Clock domain: CPU; caller owns the writable Surface and cache maintenance.
 */
#ifndef DRAW_H
#define DRAW_H

#include <stdint.h>
#include "yolo_post.h"

typedef struct {
    uint16_t *pixels;
    uint32_t stride;               /* bytes, SoC Surface stride */
    uint16_t width;
    uint16_t height;
} draw_surface;

/* Rectangles use exclusive x1/y1; drawing clips to the Surface extent. */
void draw_fill(draw_surface *surface, int32_t x0, int32_t y0, int32_t x1, int32_t y1,
               uint16_t color);
void draw_rect(draw_surface *surface, int32_t x0, int32_t y0, int32_t x1, int32_t y1,
               uint16_t color);
/* text must contain printable ASCII (32..126); unset glyph pixels are transparent. */
void draw_text(draw_surface *surface, int32_t x, int32_t y, const char *text, uint16_t color);
/* Draw a one-pixel box and "COCO class 0.875" with an opaque label background. */
void draw_detection(draw_surface *surface, const yolo_detection *detection,
                    uint16_t color, uint16_t text_color);

#endif
