/* pipeline_exec.h — PIPE-SPEC 3.3/7; IRQ-owned frame and engine queues.
 * Task prepares configuration; IRQ only transfers ownership and starts hardware.
 */
#ifndef SHOWCASE_PIPE_EXEC_H
#define SHOWCASE_PIPE_EXEC_H
#include "pipeline.h"
#include "engine.h"
#include "rnd.h"
#include "mem_xbar.h"
uint32_t pipe_revision(void);
void pipe_enter(void);
void pipe_stop(bool pause);
void pipe_resume(void);
bool pipe_ready(ui_state_t target);
int pipe_service(void);
void pipe_irq(const struct engine_event *event, unsigned engine);
void pipe_display_irq(uint32_t irq);
void pipe_rnd_done(void);
void pipe_npu_done(void);
void pipe_npu_time(uint64_t ticks);
const char *pipe_report(void);
void pipe_detection_release(void);
void pipe_detection_published(uint64_t tick);
void pipe_upload(uint32_t base);
void pipe_cancel_upload(void);
void pipe_memory_sample(const struct mem_xbar_stats *sample);
void pipe_map_detections(ui_detection_t *boxes, unsigned count);
/* platform.c arbitrates GUI batches and the pipeline RND queue. */
void board_pipe_rnd_submit(const struct rnd_batch *batch);
/* vision.c retains the established NPU/POST_CTRL and CPU postprocessing path. */
bool vision_pipe_idle(void);
void vision_pipe_image_done(uint32_t frame);
void pipe_detection_available(void);
bool vision_pipe_start(unsigned input, uint32_t frame, uint64_t tick);
unsigned vision_pipe_boxes(ui_detection_t *boxes);
#endif
