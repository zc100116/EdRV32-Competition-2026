/* File: overlay_label.c
 * Spec: Task B3-11; design 2026-10-29-b2-software 3.4.
 * Description: Shared COCO class names and thousandths labels for both renderers.
 * Clock domain: none (pure software).
 */
#include "overlay.h"

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

unsigned int demo_overlay_label(char label[32], const yolo_detection *detection)
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
