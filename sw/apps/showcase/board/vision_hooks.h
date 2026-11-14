/* vision_hooks.h — showcase design 4.5.8; BOARD/vision integration contract.
 * Application and bulk callbacks run on clk_sys in cooperative task context.
 */
#ifndef SHOWCASE_VISION_HOOKS_H
#define SHOWCASE_VISION_HOOKS_H
#include "../app.h"
#include "engine.h"
#include "../ui/ui_data.h"
void vision_init(void);
void vision_model_receiving(void);
bool vision_model_ready(void);
int vision_service(void);
bool vision_post_active(void);
void vision_irq(const struct engine_event *event, void *context);
/* 0 accepts asynchronous processing; 1 length error, 2 EDNM format error.
 * BOARD sends successful DONE only after board_bulk_complete(kind).
 */
uint32_t vision_bulk_done(unsigned kind, uint32_t base, uint32_t bytes);
void vision_pause(bool paused);
bool vision_ready(ui_state_t target);
void vision_cancel(unsigned kind);
bool vision_process_applied(void);
void vision_detection_changed(void);
bool vision_detection_applied(void);
const char *vision_report(void);
uint32_t vision_request(void);
void vision_state(uint8_t payload[56]);
uint32_t vision_frame(void);
void vision_image_receiving(uint32_t seq);
void vision_image_info(unsigned index, unsigned total, const uint8_t *name, unsigned bytes);
uint32_t vision_upload_base(void);
/* DISP IRQ only latches events; task context releases L0 via REL_BASE. */
void vision_display_irq(uint32_t irq);
void vision_gui_presented(uint64_t tick);
extern const struct app vision_app_camera;
extern const struct app vision_app_image;
extern const struct app vision_app_process;
#endif
