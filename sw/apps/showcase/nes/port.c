/* File: port.c
 * Spec: showcase design 4.4; nofrendo port copied from sw/apps/nes.
 * Description: Cooperative frame entry, cartridge lifecycle and platform callbacks.
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

extern char *osd_getromdata(void);
volatile int nofrendo_ticks;
rgb_t gui_pal[GUI_TOTALCOLORS];
unsigned nes_frames;
volatile unsigned nes_shown;
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
static int controller_registered;
static nes_t *machine;
void nes_emulate_init(void);
void nes_emulate_frame(void);

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
    if (!nes_skip_render) {
        for (unsigned y = 0; y < 240; ++y)
            memcpy(pixels + y * 256, surface[y] + 8, 256);
        nes_frame(pixels, palette, nes_frames + 1);
    }
}

void osd_getinput(void)
{
    ++nes_frames;
    /* Input was latched at nes_step entry, before the CPU emulates this frame. */
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

void nes_start(void)
{
    const unsigned char *rom = (const unsigned char *)osd_getromdata();
    if (memcmp(rom, "NES\x1a", 4) != 0) {
        fprintf(stderr, "NES ROM slot empty or invalid: %02x %02x %02x %02x\n",
                rom[0], rom[1], rom[2], rom[3]);
        exit(1);
    }
    memset(surface, 0, sizeof(surface));
    bitmap_t *bitmap = vid_getbuffer();
    bitmap->width = 256;
    bitmap->height = 240;
    bitmap->pitch = 272;
    bitmap->hardware = true;
    bitmap->data = &surface[0][0];
    for (unsigned y = 0; y < 240; ++y)
        bitmap->line[y] = surface[y] + 8;
    controller.type = INP_JOYPAD0;
    controller.data = 0;
    if (!controller_registered) {
        input_register(&controller);
        controller_registered = 1;
    }
    nes_frames = 0;
    nes_shown = 0;
    machine = nes_create();
    if (machine == NULL) {
        fputs("NES create failed\n", stderr);
        exit(1);
    }
    if (nes_insertcart("external.nes", machine)) {
        fputs("NES insert failed\n", stderr);
        exit(1);
    }
    printf("NES ROM prg=%d chr=%d mapper=%d\n", machine->rominfo->rom_banks * 16,
           machine->rominfo->vrom_banks * 8, machine->rominfo->mapper_number);
    nes_getcontextptr()->autoframeskip = false;
    nes_emulate_init();
}

void nes_step(void)
{
    controller.data = (int)nes_buttons();
    nes_emulate_frame();
}

void nes_stop(void)
{
    nes_destroy(&machine);
}

void nes_run(void)
{
    nes_start();
    while (nes_frames < nes_frame_limit)
        nes_step();
    nes_stop();
}
