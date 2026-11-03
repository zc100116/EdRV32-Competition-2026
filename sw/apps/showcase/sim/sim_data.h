/* sim_data.h — showcase design §5.1; simulator-only setup and configuration. */
#ifndef SIM_DATA_H
#define SIM_DATA_H
#include "ui_data.h"
void sim_data_init(void);
void sim_data_toggle_hardware(void);
const lv_image_dsc_t *sim_process_image(const ui_process_config_t *config);
const lv_image_dsc_t *sim_l0_image(void);
uint32_t sim_composite(const lv_image_dsc_t *l0, uint32_t foreground, unsigned x, unsigned y);
#endif
