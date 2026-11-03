/* style_samples.h — design P1a, shared disposable sample; no hardware clock. */
#ifndef STYLE_SAMPLES_H
#define STYLE_SAMPLES_H
#include "lvgl.h"
void samples_start(void);
void samples_key(uint32_t key);
void samples_state(unsigned style, bool monitor, unsigned focus);
#endif
