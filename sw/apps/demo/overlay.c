/* File: overlay.c
 * Spec: rnd-disp design 3.5–3.6; rnd 2.6/5.4; DISP 5.3; SoC 7.3 R3.
 * Description: RND detection overlays with per-buffer dirty rectangles and L1 ownership.
 * Clock domain: clk_sys; display ownership changes in the FRAME interrupt.
 */
#include "runtime.h"
#include "cache.h"
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

static volatile int current;
static volatile int next;
static volatile int queued;
static int rendered;
static struct rnd_rect dirty[2][2u * DEMO_MAX_BOXES];
static unsigned int dirty_count[2];

static uint32_t address(unsigned int slot)
{
    return DEMO_OVERLAY_BASE + slot * DEMO_OVERLAY_SPACING;
}

void demo_overlay_init(void)
{
    /* DISP is stopped; initialization is the only full-Surface CPU write. */
    for (unsigned int buffer = 0; buffer < 3; ++buffer) {
        uint32_t base = buffer < 2u ? address(buffer) : DEMO_OVERLAY_ZERO;
        uint32_t *pixels = (uint32_t *)demo_cached(base);
        for (unsigned int i = 0; i < DEMO_OVERLAY_BYTES / 4u; ++i) {
            pixels[i] = 0;
        }
        cache_clean((uintptr_t)pixels, DEMO_OVERLAY_BYTES);
    }
    uint8_t *font = (uint8_t *)demo_cached(DEMO_OVERLAY_FONT);
    const uint8_t *source = (const uint8_t *)&font8x16;
    for (unsigned int i = 0; i < sizeof(font8x16); ++i) {
        font[i] = source[i];
    }
    cache_clean((uintptr_t)font, sizeof(font8x16));
    disp_l1_geometry(0, 0, DEMO_WIDTH, DEMO_HEIGHT, 255);
    demo_overlay_stop();
}

void demo_overlay_stop(void)
{
    /* Called only after DISP IDLE, so both buffers are now writable. */
    disp_layer_enable(DISP_L1, 0);
    current = -1;
    next = -1;
    queued = -1;
    rendered = -1;
}

void demo_overlay_present(unsigned int initial)
{
    /* Called with the L0 submission lock held: camera and overlay latch together. */
    if (initial) {
        next = rendered;
        disp_submit(DISP_L1, address((unsigned int)next), DEMO_OVERLAY_STRIDE);
        disp_layer_enable(DISP_L1, 1);
    } else {
        queued = rendered;
    }
    rendered = -1;
}

void demo_overlay_frame(uint32_t irq)
{
    if ((irq & EDRV32_DISP_IRQ_STAT_SWITCH1_MASK) && current >= 0 &&
        disp_released(DISP_L1) == address((unsigned int)current)) {
        current = -1;
    }
    if (!(irq & EDRV32_DISP_IRQ_STAT_FRAME_MASK)) {
        return;
    }
    if (next >= 0 && disp_current(DISP_L1) == address((unsigned int)next)) {
        current = next;
        next = -1;
    }
    if (!demo.transitioning && next < 0 && queued >= 0) {
        next = queued;
        queued = -1;
        disp_submit(DISP_L1, address((unsigned int)next), DEMO_OVERLAY_STRIDE);
        disp_layer_enable(DISP_L1, 1);
    }
}

static unsigned int label_make(char label[32], const yolo_detection *detection)
{
    unsigned int length = 0;
    const char *name = class_names[detection->class_id];
    while (*name) {
        label[length++] = *name++;
    }
    label[length++] = ' ';
    label[length++] = (char)('0' + detection->score / 1000);
    label[length++] = '.';
    label[length++] = (char)('0' + detection->score / 100 % 10);
    label[length++] = (char)('0' + detection->score / 10 % 10);
    label[length++] = (char)('0' + detection->score % 10);
    return length;
}

void demo_overlay_draw(const yolo_detection *detections, unsigned int count)
{
    int buffer;
    /* FRAME/SWITCH1 interrupts release a slot; never draw current or shadow-next. */
    for (;;) {
        uint32_t lock = demo_irq_lock();
        buffer = -1;
        for (int i = 0; i < 2; ++i) {
            if (current != i && next != i && queued != i) {
                buffer = i;
                break;
            }
        }
        demo_irq_unlock(lock);
        if (buffer >= 0) {
            break;
        }
    }
    struct rnd_command *commands = (struct rnd_command *)demo_cached(DEMO_OVERLAY_COMMANDS);
    unsigned int n = 0;
    struct rnd_common c;
    c.dst_base = address((unsigned int)buffer);
    c.dst_stride = DEMO_OVERLAY_STRIDE;
    c.dst_fmt = RND_ARGB8888;
    c.src_fmt = RND_ARGB8888;
    c.flags = 0;
    c.clip = (struct rnd_rect){0, 0, DEMO_WIDTH - 1, DEMO_HEIGHT - 1};
    c.color = 0;
    c.opa = 255;
    /* FILL alpha=0 is over, so clear by bitwise COPY from the transparent Surface. */
    for (unsigned int i = 0; i < dirty_count[buffer]; ++i) {
        c.rect = dirty[buffer][i];
        struct rnd_source zero = {DEMO_OVERLAY_ZERO, DEMO_OVERLAY_STRIDE,
                                  (uint16_t)c.rect.x0, (uint16_t)c.rect.y0};
        rnd_copy(&commands[n++], &c, &zero);
    }
    dirty_count[buffer] = 0;
    const int32_t steps[4] = {0};
    for (unsigned int i = 0; i < count; ++i) {
        const yolo_detection *d = &detections[i];
        char label[32];
        unsigned int length = label_make(label, d);
        int16_t y = d->y0 >= 16 ? (int16_t)(d->y0 - 16) : d->y0;
        c.rect = (struct rnd_rect){d->x0, d->y0, (int16_t)(d->x1 - 1),
                                   (int16_t)(d->y1 - 1)};
        c.color = 0x00ff00;
        rnd_border(&commands[n++], &c, 0, 1, 15);
        dirty[buffer][dirty_count[buffer]++] = c.rect;
        c.rect = (struct rnd_rect){d->x0, y, (int16_t)(d->x0 + length * 8u - 1u),
                                   (int16_t)(y + 15)};
        rnd_fill(&commands[n++], &c, 0, 0, steps);
        dirty[buffer][dirty_count[buffer]++] = c.rect;
        c.color = 0xffffff;
        c.src_fmt = RND_A1;
        for (unsigned int j = 0; j < length; ++j) {
            c.rect = (struct rnd_rect){(int16_t)(d->x0 + j * 8u), y,
                                       (int16_t)(d->x0 + j * 8u + 7u), (int16_t)(y + 15)};
            struct rnd_source glyph = {DEMO_OVERLAY_FONT + ((uint8_t)label[j] - 32u) * 16u,
                                       1, 0, 0};
            rnd_glyph(&commands[n++], &c, &glyph);
        }
    }
    const struct rnd_range sources[] = {
        {(void *)demo_cached(DEMO_OVERLAY_ZERO), DEMO_OVERLAY_BYTES},
        {(void *)demo_cached(DEMO_OVERLAY_FONT), sizeof(font8x16)}
    };
    const struct rnd_range target = {(void *)demo_cached(c.dst_base), DEMO_OVERLAY_BYTES};
    const struct rnd_batch batch = {commands, (uint16_t)n, sources, 2, &target, 1};
    rnd_submit(&batch);
    struct rnd_result result = rnd_wait();
    if (result.error) {
        info_hex("RND ERR_CODE", result.error);
        info_number("RND CUR_DESC", result.cur_desc);
        __asm__ volatile ("csrci mstatus, 8" ::: "memory");
        info_text("DEMO stopped", "RND error; reset to restart");
        for (;;) {
            __asm__ volatile ("wfi");
        }
    }
    uint32_t lock = demo_irq_lock();
    rendered = buffer;
    demo_irq_unlock(lock);
}
