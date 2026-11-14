/* state.h — P5 8.3/8.4; explicit 56-byte STATE wire layout, independent of C padding. */
#ifndef SHOWCASE_STATE_H
#define SHOWCASE_STATE_H
#include "../ui/ui_data.h"
struct board_state {
    ui_session_t session;
    unsigned error;
    bool boxes;
    ui_detection_config_t detection;
    uint32_t chain_rev;
    uint32_t request, frame;
    ui_image_status_t image_status;
};
void board_state_encode(uint8_t payload[56], const struct board_state *state);
#endif
