/* mirror.h — live demo L7; default-group control mirror, GUI objects on clk_sys. */
#ifndef SHOWCASE_UI_MIRROR_H
#define SHOWCASE_UI_MIRROR_H
#include <stdbool.h>
#include <stdint.h>
void ui_mirror_page(unsigned page, const char *title);
void ui_mirror_poll(void (*send)(const uint8_t *, unsigned), uint64_t now, uint32_t hz);
unsigned ui_mirror_act(uint32_t revision, unsigned id, unsigned action, int value,
                       bool application_input);
#endif
