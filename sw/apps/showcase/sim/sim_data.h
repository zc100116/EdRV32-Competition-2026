/* sim_data.h — showcase design §5.1; simulator-only setup and configuration. */
#ifndef SIM_DATA_H
#define SIM_DATA_H
#include "ui_data.h"
void sim_data_init(void);
void sim_data_many_categories(bool enabled);
void sim_data_session(ui_app_t app,ui_state_t state,const char *error);
void sim_data_image_status(int status);
void sim_data_toggle_hardware(void);
const lv_image_dsc_t *sim_pipeline_image(void);
const lv_image_dsc_t *sim_l0_image(void);
uint32_t sim_composite(const lv_image_dsc_t *l0, uint32_t foreground, unsigned x, unsigned y);
#endif
