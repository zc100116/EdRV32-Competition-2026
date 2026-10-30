/* File: host.c
 * Spec: Task B3-4b; design 2026-10-29-rnd-disp 5.2.
 * Description: Run a fixed number of frames and save each sixtieth frame as PPM.
 * Clock domain: CLOCK_MONOTONIC, nanoseconds.
 */
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include "nes_port.h"
static const char *output_directory;
static char *rom_data;

char *osd_getromdata(void) { return rom_data; }

uint64_t nes_ticks(void)
{
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) {
        perror("clock_gettime");
        exit(1);
    }
    return (uint64_t)now.tv_sec * 1000000000 + (uint64_t)now.tv_nsec;
}
uint64_t nes_tick_hz(void) { return 1000000000; }
uint64_t nes_instructions(void) { return 0; }
unsigned nes_buttons(void) { return 0; }

void nes_frame(const uint8_t *pixels, const struct nes_rgb *palette, unsigned frame)
{
    if (frame % 60 != 0 && frame != nes_frame_limit)
        return;
    char path[1024];
    snprintf(path, sizeof(path), "%s/frame-%06u.ppm", output_directory, frame);
    FILE *file = fopen(path, "wb");
    if (file == NULL) {
        perror(path);
        exit(1);
    }
    fprintf(file, "P6\n256 240\n255\n");
    for (unsigned i = 0; i < 256 * 240; ++i) {
        const struct nes_rgb color = palette[pixels[i]];
        const uint8_t rgb[3] = { color.r, color.g, color.b };
        if (fwrite(rgb, 1, 3, file) != 3) {
            perror(path);
            exit(1);
        }
    }
    if (fclose(file) != 0) {
        perror(path);
        exit(1);
    }
}

int main(int argc, char **argv)
{
    if (argc != 4 && argc != 5) {
        fprintf(stderr, "usage: %s ROM FRAMES OUTPUT_DIRECTORY [skip]\n", argv[0]);
        return 1;
    }
    nes_frame_limit = (unsigned)strtoul(argv[2], NULL, 10);
    if (nes_frame_limit == 0) {
        fputs("FRAMES must be positive\n", stderr);
        return 1;
    }
    FILE *rom = fopen(argv[1], "rb");
    if (rom == NULL || fseek(rom, 0, SEEK_END) != 0) {
        perror(argv[1]);
        return 1;
    }
    long size = ftell(rom);
    if (size < 16) {
        fprintf(stderr, "%s: cannot read 16-byte iNES header\n", argv[1]);
        return 1;
    }
    rom_data = malloc((size_t)size);
    if (rom_data == NULL || fseek(rom, 0, SEEK_SET) != 0 ||
        fread(rom_data, 1, (size_t)size, rom) != (size_t)size || fclose(rom) != 0) {
        perror(argv[1]);
        return 1;
    }
    output_directory = argv[3];
    nes_skip_render = argc == 5;
    nes_run();
    free(rom_data);
    return 0;
}
