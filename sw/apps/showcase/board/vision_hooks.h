/* vision_hooks.h — showcase design 4.5.8; BOARD/vision integration contract.
 * Application and bulk callbacks run on clk_sys in cooperative task context.
 */
#ifndef SHOWCASE_VISION_HOOKS_H
#define SHOWCASE_VISION_HOOKS_H
#include "../app.h"
#include "engine.h"
void vision_init(void);
int vision_service(void);
void vision_irq(const struct engine_event *event, void *context);
/* 0 accepts asynchronous processing; 1 length error, 2 EDNM format error.
 * BOARD sends successful DONE only after board_bulk_complete(kind).
 */
uint32_t vision_bulk_done(unsigned kind, uint32_t base, uint32_t bytes);
void vision_camera(void);
/* Call after LV_EVENT_RENDER_READY; all RND source reads must have completed. */
void vision_frame_presented(void);
extern const struct app vision_app_camera;
extern const struct app vision_app_image;
extern const struct app vision_app_process;
#endif
