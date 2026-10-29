/* File: port.c
 * Spec: design 2026-10-29-rnd-disp 5.2; Task B3-4b.
 * Description: Adapt nofrendo video, controller, allocation and sound callbacks.
 * Clock domain: clk_sys on board; host monotonic clock on Linux.
 */
#include <stdarg.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <noftypes.h>
#include <nes.h>
#include <nesinput.h>
#include <nofrendo.h>
#include <gui.h>
#include <osd.h>
#include <vid_drv.h>
#include "nes_port.h"
#undef malloc
#undef free

extern const unsigned char nes_rom_start[];
volatile int nofrendo_ticks;
rgb_t gui_pal[GUI_TOTALCOLORS];
struct nes_stats nes_stats;
unsigned nes_frames;
unsigned nes_shown;
unsigned nes_frame_limit;
int nes_skip_render;
static uint8_t surface[240][272] __attribute__((aligned(16)));
static uint8_t pixels[240 * 256] __attribute__((aligned(64)));
static struct nes_rgb palette[256] __attribute__((aligned(64)));
static union {
    max_align_t alignment;
    unsigned char bytes[sizeof(bitmap_t) + 240 * sizeof(uint8_t *)];
} bitmap_storage;
static nesinput_t controller;
static uint64_t frame_start;
static uint64_t report_start;
static uint64_t instruction_start;

void *_my_malloc(int size)
{
    void *result = malloc((size_t)size);
    if (result == NULL) {
        fprintf(stderr, "NES allocation failed: %d bytes\n", size);
        exit(1);
    }
    return result;
}

void _my_free(void **data)
{
    free(*data);
    *data = NULL;
}

char *osd_getromdata(void) { return (char *)nes_rom_start; }
bitmap_t *vid_getbuffer(void) { return (bitmap_t *)bitmap_storage.bytes; }

void vid_setpalette(rgb_t *source)
{
    for (unsigned i = 0; i < 256; ++i) {
        palette[i].r = (uint8_t)source[i].r;
        palette[i].g = (uint8_t)source[i].g;
        palette[i].b = (uint8_t)source[i].b;
    }
}

void vid_flush(void)
{
    nes_stats.frame_ticks += nes_ticks() - frame_start;
    if (!nes_skip_render) {
        for (unsigned y = 0; y < 240; ++y)
            memcpy(pixels + y * 256, surface[y] + 8, 256);
        nes_frame(pixels, palette, nes_frames + 1);
    }
}

void osd_getinput(void)
{
    ++nes_frames;
    controller.data = (int)nes_buttons();
    if (nes_frames % 60 == 0) {
        uint64_t now = nes_ticks();
        uint64_t instructions = nes_instructions();
        nes_report(now - report_start, instructions - instruction_start);
        memset(&nes_stats, 0, sizeof(nes_stats));
        nes_shown = 0;
        report_start = nes_ticks();
        instruction_start = nes_instructions();
    }
    if (nes_frame_limit && nes_frames == nes_frame_limit)
        nes_poweroff();
    frame_start = nes_ticks();
}

void osd_getsoundinfo(sndinfo_t *info)
{
    info->sample_rate = 8000;
    info->bps = 8;
}

/* The callback is never invoked: APU register state remains, samples cost nothing. */
void osd_setsound(void (*playfunc)(void *, int)) { (void)playfunc; }
void gui_tick(int ticks) { (void)ticks; }
void gui_frame(bool draw) { (void)draw; }

void gui_sendmsg(int color, char *format, ...)
{
    va_list arguments;
    va_start(arguments, format);
    FILE *stream = color == GUI_RED ? stderr : stdout;
    vfprintf(stream, format, arguments);
    va_end(arguments);
    fputc('\n', stream);
    if (color == GUI_RED)
        exit(1);
}

int log_printf(const char *format, ...)
{
    va_list arguments;
    va_start(arguments, format);
    int result = vprintf(format, arguments);
    va_end(arguments);
    return result;
}

char *osd_newextension(char *path, char *extension)
{
    char *dot = strrchr(path, '.');
    strcpy(dot ? dot : path + strlen(path), extension);
    return path;
}

void nes_report(uint64_t elapsed, uint64_t instructions)
{
    uint64_t fps10 = 600 * nes_tick_hz() / elapsed;
    uint64_t shown10 = 10 * (uint64_t)nes_shown * nes_tick_hz() / elapsed;
    unsigned cpu = (unsigned)(100 * nes_stats.cpu_ticks / nes_stats.frame_ticks);
    unsigned ppu = (unsigned)(100 * nes_stats.ppu_ticks / nes_stats.frame_ticks);
#ifdef NES_SPIKE
    const char *label = "NES estimate IPC1 fps=";
#else
    const char *label = "NES fps=";
#endif
    printf("%s%lu.%lu shown=%lu.%lu cpu=%u%% ppu=%u%%\n", label,
           (unsigned long)(fps10 / 10), (unsigned long)(fps10 % 10),
           (unsigned long)(shown10 / 10), (unsigned long)(shown10 % 10), cpu, ppu);
    if (instructions)
        printf("NES RV32 instructions/frame=%lu\n", (unsigned long)(instructions / 60));
}

void nes_run(void)
{
    bitmap_t *bitmap = vid_getbuffer();
    bitmap->width = 256;
    bitmap->height = 240;
    bitmap->pitch = 272;
    bitmap->hardware = true;
    bitmap->data = &surface[0][0];
    for (unsigned y = 0; y < 240; ++y)
        bitmap->line[y] = surface[y] + 8;
    controller.type = INP_JOYPAD0;
    input_register(&controller);
    nes_t *machine = nes_create();
    if (machine == NULL) {
        fputs("NES create failed\n", stderr);
        exit(1);
    }
    if (nes_insertcart("embedded.nes", machine)) {
        fputs("NES insert failed\n", stderr);
        exit(1);
    }
    nes_getcontextptr()->autoframeskip = false;
    report_start = nes_ticks();
    instruction_start = nes_instructions();
    frame_start = report_start;
    nes_emulate();
}
