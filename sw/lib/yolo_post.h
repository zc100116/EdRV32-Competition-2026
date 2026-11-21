/* yolo_post.h — npu-spec 2.6/4.5; SoC 7.4/8.9.
 * Hardware candidate YOLO postprocessing; numerical contract: sw/lib/README.md.
 * Clock domain: CPU, caller owns DMA candidate buffers after successful DONE.
 */
#ifndef YOLO_POST_H
#define YOLO_POST_H

#include <stdint.h>

enum { YOLO_ANCHORS = 5040, YOLO_MAX_DETECTIONS = 100, YOLO_OUTPUT_BYTES = 725760,
       YOLO_CANDIDATE_BYTES = YOLO_ANCHORS * 24 };

typedef struct {
    int16_t x0;
    int16_t y0;
    int16_t x1;
    int16_t y1;
    uint16_t class_id;
    uint16_t score;                 /* 0..1000, EDDT wire units */
} yolo_detection;

typedef struct {
    uint32_t box_offset;
    uint32_t class_offset;
    uint32_t plane_stride;
    uint16_t width;
    uint16_t height;
    uint16_t stride;
    int16_t class_threshold;        /* first INT8 value with probability > .25 */
    int16_t box_zero_point;         /* cancels in softmax, retained as metadata */
    int16_t class_zero_point;
    uint32_t exp_q20[256];          /* exp(-difference * box_scale) */
    uint32_t probability_q24[256];  /* signed INT8 index + 128 */
} yolo_head;

typedef struct {
    int32_t xyxy_q8[4];
    uint32_t probability_q24;
    uint16_t class_id;
    uint16_t anchor;
} yolo_candidate;

typedef struct {
    uint32_t class_comparisons;     /* threshold + argmax comparisons */
    uint32_t decoded_anchors;
    uint32_t dfl_bin_comparisons;
    uint32_t exp_lookups;
    uint32_t sort_comparisons;
    uint32_t nms_class_comparisons;
    uint32_t iou_comparisons;
} yolo_post_stats;

/* Generated from build/npu/quantized/quantization.json; see tools/gen/yolo_post.py. */
extern const yolo_head yolo_default_heads[3];

/* npu-spec 2.6/4.5: consumes and sorts the DMA-owned candidates in place after DONE.
 * The caller invalidates count * 24 bytes before calling; no raw cls is accessed.
 */
uint32_t yolo_post_candidates(yolo_candidate workspace[YOLO_ANCHORS], uint32_t count,
                             yolo_detection detections[YOLO_MAX_DETECTIONS],
                             yolo_post_stats *stats);

/* Offline host reference only: fixed-model raw OUTPUT, three heads,
 * 5040 candidates and 100 results are required.
 * No allocation or hardware/cache access. All inputs are trusted internal contracts.
 * Statistics are required and count algorithmic work, not measured CPU cycles.
 */
uint32_t yolo_post_process(const int8_t *output, const yolo_head heads[3],
                           yolo_candidate workspace[YOLO_ANCHORS],
                           yolo_detection detections[YOLO_MAX_DETECTIONS],
                           yolo_post_stats *stats);

#endif
