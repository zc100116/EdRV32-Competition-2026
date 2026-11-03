/* vision_stub.c — integration-only placeholder, removed when T-SHOW-VISION lands. */
#include "vision_hooks.h"
#include "../ui/ui_data.h"
uint32_t vision_bulk_done(unsigned kind,uint32_t base,uint32_t bytes)
{ (void)kind; (void)base; (void)bytes; return 0; }
void vision_camera(void) {}
void vision_init(void) {}
int vision_service(void) { return 0; }
void vision_irq(const struct engine_event *event,void *context) { (void)event;(void)context; }
void vision_frame_presented(void) {}
static void empty(void) {}
const struct app vision_app_camera={"camera",0,APP_HW_VIN|APP_HW_NPU,0,empty,empty,empty};
const struct app vision_app_image={"image",0,APP_HW_NPU|APP_HW_ETH,0,empty,empty,empty};
const struct app vision_app_process={"process",0,APP_HW_VIN|APP_HW_PIX|APP_HW_GEO,0,
    empty,empty,empty};
ui_vision_t ui_data_vision(bool batch) { (void)batch; return (ui_vision_t){.waiting=true}; }
void ui_data_pause(void) {}
void ui_data_boxes(void) {}
void ui_data_batch_stop(void) {}
const lv_image_dsc_t *ui_data_process(unsigned mode) { (void)mode; return 0; }
