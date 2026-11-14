/* post.c — npu-spec 2.6/4.5; SoC 7.4/8.9.
 * Hardware candidate ordering, integer class-aware NMS and display mapping.
 * Clock domain: CPU. Numerical contract: sw/lib/README.md.
 */
#include "post.h"

_Static_assert(sizeof(yolo_detection) == 12, "EDDT detection must be 12 bytes");

static int32_t minimum(int32_t a, int32_t b)
{
    return a < b ? a : b;
}

static int32_t maximum(int32_t a, int32_t b)
{
    return a > b ? a : b;
}

static int better(const yolo_candidate *a, const yolo_candidate *b, yolo_post_stats *stats)
{
    ++stats->sort_comparisons;
    if (a->probability_q24 != b->probability_q24) {
        return a->probability_q24 > b->probability_q24;
    }
    return a->anchor < b->anchor;
}

static void swap(yolo_candidate *a, yolo_candidate *b)
{
    yolo_candidate temporary = *a;
    *a = *b;
    *b = temporary;
}

static void sift(yolo_candidate *items, uint32_t count, uint32_t root,
                 yolo_post_stats *stats)
{
    while (2 * root + 1 < count) {
        uint32_t child = 2 * root + 1;
        if (child + 1 < count && better(&items[child], &items[child + 1], stats)) {
            ++child;
        }
        if (!better(&items[root], &items[child], stats)) {
            break;
        }
        swap(&items[root], &items[child]);
        root = child;
    }
}

static int overlaps(const yolo_candidate *a, const yolo_candidate *b)
{
    int32_t width = maximum(0, minimum(a->xyxy_q8[2], b->xyxy_q8[2]) -
                               maximum(a->xyxy_q8[0], b->xyxy_q8[0]));
    int32_t height = maximum(0, minimum(a->xyxy_q8[3], b->xyxy_q8[3]) -
                                maximum(a->xyxy_q8[1], b->xyxy_q8[1]));
    uint64_t intersection = (uint64_t)width * (uint32_t)height;
    uint64_t area_a = (uint64_t)(a->xyxy_q8[2] - a->xyxy_q8[0]) *
                     (uint32_t)(a->xyxy_q8[3] - a->xyxy_q8[1]);
    uint64_t area_b = (uint64_t)(b->xyxy_q8[2] - b->xyxy_q8[0]) *
                     (uint32_t)(b->xyxy_q8[3] - b->xyxy_q8[1]);
    return intersection * 20 > (area_a + area_b - intersection) * 9;
}

static int16_t display_coordinate(int32_t coordinate, int32_t padding, int32_t limit)
{
    /* Clamp is the specified display transform; NMS uses the unclipped Q8 box. */
    int32_t mapped = maximum(0, minimum((coordinate - padding * 256) * 2, limit * 256));
    return (int16_t)((mapped + 128) / 256);
}

void vision_post_begin(struct vision_post *p, yolo_candidate *candidates, uint32_t count,
                       yolo_detection *detections)
{
    *p = (struct vision_post){.workspace = candidates, .count = count,
        .detections = detections, .stats = {.decoded_anchors = count}};
}

/* Candidate handoff, one heap root, or sixteen NMS comparisons.
 * Every phase returns to the scheduler, including sorting and suppression.
 */
int vision_post_step(struct vision_post *p)
{
    yolo_candidate *workspace = p->workspace;
    yolo_post_stats *stats = &p->stats;
    if (p->phase == 0) {
        /* decode now measures candidate handoff; class selection/DFL run in NPU. */
        p->phase = 1;
        p->root = p->count / 2;
        p->end = p->count;
    } else if (p->phase == 1) {
        if (p->root) {
            sift(workspace, p->count, --p->root, stats);
        } else {
            p->phase = 2;
        }
    } else if (p->phase == 2) {
        if (p->end > 1) {
            swap(&workspace[0], &workspace[--p->end]);
            sift(workspace, p->end, 0, stats);
        } else {
            p->phase = 3;
        }
    } else if (p->phase == 3) {
        if (p->i == p->count || p->kept == YOLO_MAX_DETECTIONS) {
            p->phase = 5;
            return 1;
        }
        yolo_candidate *candidate = &workspace[p->i];
        if (candidate->probability_q24 == 0) {
            ++p->i;
            return 0;
        }
        yolo_detection *result = &p->detections[p->kept++];
        result->x0 = display_coordinate(candidate->xyxy_q8[0], 0, 1280);
        result->y0 = display_coordinate(candidate->xyxy_q8[1], 12, 720);
        result->x1 = display_coordinate(candidate->xyxy_q8[2], 0, 1280);
        result->y1 = display_coordinate(candidate->xyxy_q8[3], 12, 720);
        result->class_id = candidate->class_id;
        result->score = (uint16_t)(((uint64_t)candidate->probability_q24 * 1000 +
                                    (1u << 23)) >> 24);
        p->j = p->i + 1;
        p->phase = 4;
    } else if (p->phase == 4) {
        yolo_candidate *candidate = &workspace[p->i];
        for (unsigned part = 0; part < 16 && p->j < p->count; ++part, ++p->j) {
            yolo_candidate *other = &workspace[p->j];
            if (other->probability_q24 == 0) {
                continue;
            }
            ++stats->nms_class_comparisons;
            if (candidate->class_id == other->class_id) {
                ++stats->iou_comparisons;
                if (overlaps(candidate, other)) {
                    other->probability_q24 = 0;
                }
            }
        }
        if (p->j == p->count) {
            ++p->i;
            p->phase = 3;
        }
    }
    return p->phase == 5;
}
