/* post.h — showcase design 4.5.2; resumable integer YOLO postprocessing.
 * Caller retains OUTPUT/workspace until completion; CPU task clock domain.
 */
#ifndef SHOWCASE_VISION_POST_H
#define SHOWCASE_VISION_POST_H
#include "yolo_post.h"
struct vision_post {
    const int8_t *output;
    yolo_candidate *workspace;
    yolo_detection *detections;
    yolo_post_stats stats;
    uint32_t head, cell, anchor_base, count, kept, phase, root, end, i, j;
};
void vision_post_begin(struct vision_post *p, const int8_t *output,
                       yolo_candidate *workspace, yolo_detection *detections);
int vision_post_step(struct vision_post *p);
#endif
