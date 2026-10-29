/* draw.c — SoC spec 7.3; B2 software design 3.2/3.4.
 * CPU RGB565 drawing with an 8x16 ASCII bitmap and COCO class labels.
 * Clock domain: CPU. All geometry uses exclusive right/bottom edges.
 */
#include "draw.h"
#include "font8x16.h"

static const char *const class_names[80] = {
    "person", "bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck", "boat",
    "traffic light", "fire hydrant", "stop sign", "parking meter", "bench", "bird", "cat",
    "dog", "horse", "sheep", "cow", "elephant", "bear", "zebra", "giraffe", "backpack",
    "umbrella", "handbag", "tie", "suitcase", "frisbee", "skis", "snowboard", "sports ball",
    "kite", "baseball bat", "baseball glove", "skateboard", "surfboard", "tennis racket",
    "bottle", "wine glass", "cup", "fork", "knife", "spoon", "bowl", "banana", "apple",
    "sandwich", "orange", "broccoli", "carrot", "hot dog", "pizza", "donut", "cake", "chair",
    "couch", "potted plant", "bed", "dining table", "toilet", "tv", "laptop", "mouse",
    "remote", "keyboard", "cell phone", "microwave", "oven", "toaster", "sink",
    "refrigerator", "book", "clock", "vase", "scissors", "teddy bear", "hair drier",
    "toothbrush"
};

void draw_fill(draw_surface *surface, int32_t x0, int32_t y0, int32_t x1, int32_t y1,
               uint16_t color)
{
    x0 = x0 < 0 ? 0 : x0;
    y0 = y0 < 0 ? 0 : y0;
    x1 = x1 > surface->width ? surface->width : x1;
    y1 = y1 > surface->height ? surface->height : y1;
    for (int32_t y = y0; y < y1; ++y) {
        uint16_t *row = surface->pixels + (uint32_t)y * (surface->stride / 2);
        for (int32_t x = x0; x < x1; ++x) {
            row[x] = color;
        }
    }
}

void draw_rect(draw_surface *surface, int32_t x0, int32_t y0, int32_t x1, int32_t y1,
               uint16_t color)
{
    /* A zero-area decoded detection has no rectangle border. */
    if (x0 >= x1 || y0 >= y1) {
        return;
    }
    draw_fill(surface, x0, y0, x1, y0 + 1, color);
    draw_fill(surface, x0, y1 - 1, x1, y1, color);
    draw_fill(surface, x0, y0, x0 + 1, y1, color);
    draw_fill(surface, x1 - 1, y0, x1, y1, color);
}

void draw_text(draw_surface *surface, int32_t x, int32_t y, const char *text, uint16_t color)
{
    for (; *text; ++text, x += 8) {
        const uint8_t *glyph = font8x16[(uint8_t)*text - 32];
        for (int32_t row = 0; row < 16; ++row) {
            for (int32_t column = 0; column < 8; ++column) {
                if (glyph[row] & (0x80u >> column)) {
                    draw_fill(surface, x + column, y + row, x + column + 1, y + row + 1,
                              color);
                }
            }
        }
    }
}

void draw_detection(draw_surface *surface, const yolo_detection *detection,
                    uint16_t color, uint16_t text_color)
{
    char label[32];
    uint32_t length = 0;
    const char *name = class_names[detection->class_id];
    while (*name) {
        label[length++] = *name++;
    }
    label[length++] = ' ';
    label[length++] = (char)('0' + detection->score / 1000);
    label[length++] = '.';
    label[length++] = (char)('0' + (detection->score / 100) % 10);
    label[length++] = (char)('0' + (detection->score / 10) % 10);
    label[length++] = (char)('0' + detection->score % 10);
    label[length] = '\0';
    int32_t label_y = detection->y0 >= 16 ? detection->y0 - 16 : detection->y0;
    draw_rect(surface, detection->x0, detection->y0, detection->x1, detection->y1, color);
    draw_fill(surface, detection->x0, label_y, detection->x0 + (int32_t)length * 8,
              label_y + 16, color);
    draw_text(surface, detection->x0, label_y, label, text_color);
}
