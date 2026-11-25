/* File: font.c; tech 5b/7. Licensed native glyphs, no substitute font; CPU clock. */
#include "ui/font.h"
#include <font.h>
#include "plat.h"
#include <stdlib.h>
#include <stdio.h>
const uint16_t *ember_font_rows(uint32_t cp, unsigned *advance)
{
    unsigned lo = 0, hi = EMBER_FONT_GLYPHS;
    while (lo < hi) {
        unsigned mid = lo + (hi - lo) / 2;
        if (ember_font[mid].codepoint < cp) lo = mid + 1;
        else hi = mid;
    }
    if (lo == EMBER_FONT_GLYPHS || ember_font[lo].codepoint != cp) {
        plat_printf("Missing font glyph U+%04x\n", cp);
        fflush(stdout);abort();
    }
    *advance = ember_font[lo].advance;
    return ember_font[lo].rows;
}
uint32_t ember_utf8_next(const char **text)
{
    const unsigned char *p = (const unsigned char *)*text;
    uint32_t cp = *p++;
    if (cp >= 0xf0) { cp &= 7; cp = cp << 6 | (*p++ & 63); cp = cp << 6 | (*p++ & 63); cp = cp << 6 | (*p++ & 63); }
    else if (cp >= 0xe0) { cp &= 15; cp = cp << 6 | (*p++ & 63); cp = cp << 6 | (*p++ & 63); }
    else if (cp >= 0xc0) { cp &= 31; cp = cp << 6 | (*p++ & 63); }
    *text = (const char *)p;
    return cp;
}
unsigned ember_text_width(const char *text)
{
    unsigned width = 0;
    while (*text && *text != '\n') {
        unsigned advance;
        ember_font_rows(ember_utf8_next(&text), &advance);
        width += advance;
    }
    return width;
}
