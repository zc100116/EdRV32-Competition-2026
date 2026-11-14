/* post.c — npu-spec 2.6/4.5; SoC 7.4/8.9.
 * Optional CPU decode, candidate ordering, integer class-aware NMS and display mapping.
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

#ifdef SHOWCASE_POST_CPU
static uint32_t distance_q8(const int8_t *bins, const yolo_head *head,
                            yolo_post_stats *stats)
{
    int32_t peak = bins[0];
    uint32_t denominator = 0;
    uint32_t numerator = 0;
    for (uint32_t i = 1; i < 16; ++i) {
        peak = maximum(peak, bins[i]);
    }
    for (uint32_t i = 0; i < 16; ++i) {
        uint32_t weight = head->exp_q20[peak - bins[i]];
        denominator += weight;
        numerator += i * weight;
    }
    stats->dfl_bin_comparisons += 15;
    stats->exp_lookups += 16;
    return (uint32_t)(((uint64_t)numerator * 256 + denominator / 2) / denominator);
}

#endif

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

#ifdef SHOWCASE_POST_CPU
void vision_post_begin(struct vision_post *p, const int8_t *output,
                       yolo_candidate *workspace, yolo_detection *detections)
{
    *p = (struct vision_post){.output = output, .workspace = workspace,
                              .detections = detections};
}

#else
void vision_post_begin(struct vision_post *p, yolo_candidate *candidates, uint32_t count,
                       yolo_detection *detections)
{
    *p = (struct vision_post){.workspace = candidates, .count = count,
        .detections = detections, .stats = {.decoded_anchors = count}};
}

#endif

/* Eight anchors (CPU) or candidate handoff (HW), one heap root, or sixteen NMS comparisons.
 * Every phase returns to the scheduler, including sorting and suppression.
 */
int vision_post_step(struct vision_post *p)
{
    yolo_candidate *workspace = p->workspace;
    yolo_post_stats *stats = &p->stats;
    if (p->phase == 0) {
#ifdef SHOWCASE_POST_CPU
        const yolo_head *head = &yolo_default_heads[p->head];
        uint32_t cells = (uint32_t)head->width * head->height;
        uint32_t row_end = (p->cell / head->width + 1) * head->width;
        for (unsigned part = 0; part < 8 && p->cell < row_end; ++part, ++p->cell) {
            uint32_t cell = p->cell;
            int32_t best = -129;
            uint16_t class_id = 0;
            const int8_t *classes = p->output + head->class_offset + cell * 16;
            for (uint32_t plane = 0; plane < 5; ++plane) {
                for (uint32_t lane = 0; lane < 16; ++lane) {
                    int32_t value = classes[plane * head->plane_stride + lane];
                    if (value > best) {
                        best = value;
                        class_id = (uint16_t)(plane * 16 + lane);
                    }
                }
            }
            stats->class_comparisons += 81;
            if (best < head->class_threshold) {
                continue;
            }
            yolo_candidate *candidate = &workspace[p->count++];
            const int8_t *boxes = p->output + head->box_offset + cell * 16;
            int32_t center_x = (int32_t)(cell % head->width) * 256 + 128;
            int32_t center_y = (int32_t)(cell / head->width) * 256 + 128;
            for (uint32_t side = 0; side < 4; ++side) {
                int32_t distance = (int32_t)distance_q8(
                    boxes + side * head->plane_stride, head, stats);
                int32_t center = (side & 1) ? center_y : center_x;
                candidate->xyxy_q8[side] =
                    (center + (side < 2 ? -distance : distance)) * head->stride;
            }
            candidate->probability_q24 = head->probability_q24[best + 128];
            candidate->class_id = class_id;
            candidate->anchor = (uint16_t)(p->anchor_base + cell);
            ++stats->decoded_anchors;
        }
        if (p->cell == cells) {
            p->anchor_base += cells;
            p->cell = 0;
            if (++p->head == 3) {
                p->phase = 1;
                p->root = p->count / 2;
                p->end = p->count;
            }
        }
#else
        /* decode now measures candidate handoff; class selection/DFL run in NPU. */
        p->phase = 1;
        p->root = p->count / 2;
        p->end = p->count;
#endif
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
