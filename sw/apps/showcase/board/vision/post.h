/* post.h — showcase design 4.5.2; resumable integer YOLO postprocessing.
 * Caller retains raw OUTPUT (CPU build) and candidates until completion; CPU task domain.
 */
#ifndef SHOWCASE_VISION_POST_H
#define SHOWCASE_VISION_POST_H
#include "yolo_post.h"
struct vision_post {
#ifdef SHOWCASE_POST_CPU
    const int8_t *output;
    uint32_t head, cell, anchor_base;
#endif
    const yolo_head *heads;
    uint16_t anchors[YOLO_MAX_DETECTIONS];
    yolo_candidate *workspace;
    yolo_detection *detections;
    yolo_post_stats stats;
    uint32_t count, kept, phase, root, end, i, j;
};
#ifdef SHOWCASE_POST_CPU
void vision_post_begin(struct vision_post *p, const int8_t *output,
                       yolo_candidate *workspace, yolo_detection *detections);
#else
void vision_post_begin(struct vision_post *p, yolo_candidate *candidates, uint32_t count,
                       yolo_detection *detections);
#endif
int vision_post_step(struct vision_post *p);
#endif
