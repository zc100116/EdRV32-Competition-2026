/* helmet.c — T-HELMET-STABLE: synthetic inference frames and warning timing.
 * Host test; no camera, hardware, or simulator VM.
 */
#include "track.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static const ui_detection_t head = {"未戴", 78, 100, 120, 80, 90, 1};
static void frame(helmet_state_t *s, bool detected, unsigned now)
{
    helmet_step(s, &head, detected ? 1 : 0);
    helmet_warning(s, now);
}
int main(void)
{
    helmet_state_t s = {0};
    frame(&s, true, 0);
    assert(s.head == 0 && !s.warning);
    frame(&s, false, 50);
    assert(s.head == 0); /* A one-frame false positive never becomes visible. */
    frame(&s, true, 100);
    assert(s.head == 0);
    frame(&s, true, 150);
    assert(s.head == 1 && !s.warning);
    assert(!helmet_warning(&s, 449));
    assert(helmet_warning(&s, 450));
    for (unsigned i = 0; i < 20; ++i) {
        frame(&s, (i & 1) != 0, 500+i*50);
        assert(s.head == 1 && s.warning);
        assert(s.tracks[0].box.x == head.x && s.tracks[0].box.y == head.y);
    }
    for (unsigned i = 1; i <= 4; ++i) {
        frame(&s, false, 1500+i*50);
        assert(s.head == (i < 4 ? 1u : 0u));
        assert(s.warning);
    }
    assert(helmet_warning(&s, 2199));
    assert(!helmet_warning(&s, 2200));

    /* Same geometry matches across classes; the last five hits vote. */
    memset(&s, 0, sizeof s);
    frame(&s, true, 0);
    frame(&s, true, 50);
    ui_detection_t helmet = head;
    helmet.class_id = 0;
    helmet.category = "安全帽";
    helmet.x += 10;
    helmet_step(&s, &helmet, 1);
    assert(s.head == 1 && s.helmet == 0 && s.tracks[0].box.x == helmet.x);
    helmet_step(&s, &helmet, 1);
    assert(s.head == 1 && s.helmet == 0); /* Tie retains the previous class. */
    helmet_step(&s, &helmet, 1);
    assert(s.head == 0 && s.helmet == 1);
    assert(strcmp(s.tracks[0].box.category, "安全帽") == 0);
    frame(&s, true, 300);
    assert(s.head == 0 && s.helmet == 1);
    frame(&s, true, 350);
    assert(s.head == 0 && s.helmet == 1);
    frame(&s, true, 400);
    assert(s.head == 1 && s.helmet == 0);

    /* Two detections cannot consume the same preceding track. */
    ui_detection_t boxes[2] = {head, head};
    boxes[1].x = 500;
    memset(&s, 0, sizeof s);
    helmet_step(&s, boxes, 2);
    assert(s.head == 0);
    helmet_step(&s, boxes, 2);
    assert(s.head == 2);
    ui_detection_t swapped[2] = {boxes[1], boxes[0]};
    helmet_step(&s, swapped, 2);
    assert(s.head == 2);
    memset(&s, 0, sizeof s);
    helmet.confidence = 59;
    helmet_step(&s, &helmet, 1); helmet_step(&s, &helmet, 1);
    assert(s.helmet == 0);
    helmet.confidence = 60;
    helmet_step(&s, &helmet, 1); helmet_step(&s, &helmet, 1);
    assert(s.helmet == 1);
    memset(&s, 0, sizeof s);
    ui_detection_t low_head = head;
    low_head.confidence = 30;
    helmet_step(&s, &low_head, 1); helmet_step(&s, &low_head, 1);
    assert(s.head == 1);
    puts("helmet: PASS (2-hit confirmation, 4-miss expiry, 5-hit vote, 300/500 ms warning)");
    return 0;
}
