/* File: font.h; tech 5b/7. Native Fusion Pixel CPU glyph lookup; CPU clock. */
#ifndef EMBER_UI_FONT_H
#define EMBER_UI_FONT_H
#include <stdint.h>
const uint16_t *ember_font_rows(uint32_t codepoint, unsigned *advance);
uint32_t ember_utf8_next(const char **text);
unsigned ember_text_width(const char *text);
#endif
