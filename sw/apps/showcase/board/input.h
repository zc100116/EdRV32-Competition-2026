/* input.h — P5 3.7/8.5; complete snapshots, exclusive owner and held-key suppression.
 * No hardware access; clk_sys or host tests. */
#ifndef SHOWCASE_INPUT_H
#define SHOWCASE_INPUT_H
#include "virtual_input.h"
#include <stdbool.h>
enum input_owner { INPUT_GUI, INPUT_APP };
void showcase_input_owner(enum input_owner owner);
enum input_owner showcase_input_current_owner(void);
void showcase_input_virtual(struct virtual_input_state input, uint64_t now);
void showcase_input_expire(uint64_t now, uint64_t timeout);
struct virtual_input_state showcase_input_view(enum input_owner owner);
uint32_t showcase_input_keys(enum input_owner owner);
int16_t showcase_input_wheel(void);
void showcase_input_sample(uint32_t keys);
void showcase_input_dispatch(void);
#endif
