/* frame_host.c: showcase design 4.4; same host callbacks as sw/apps/nes/host.c.
 * Write every frame as RGB888 for direct pixel equality, without checksums.
 * Clock domain: host CLOCK_MONOTONIC in nanoseconds.
 */
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include "nes_port.h"
static char *rom_data;
static FILE *frames;
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
unsigned nes_buttons(void) { return nes_frames == 120 ? 8u : 0; }
void nes_frame(const uint8_t *pixels, const struct nes_rgb *palette, unsigned frame)
{
    (void)frame;
    uint8_t rgb[256 * 240 * 3];
    for (unsigned i = 0; i < 256 * 240; ++i) {
        rgb[i * 3] = palette[pixels[i]].r;
        rgb[i * 3 + 1] = palette[pixels[i]].g;
        rgb[i * 3 + 2] = palette[pixels[i]].b;
    }
    if (fwrite(rgb, sizeof(rgb), 1, frames) != 1) {
        perror("frame write");
        exit(1);
    }
}
int main(int argc, char **argv)
{
    if (argc != 3 && argc != 4)
        return 1;
    FILE *rom = fopen(argv[1], "rb");
    if (!rom || fseek(rom, 0, SEEK_END)) {
        perror(argv[1]);
        return 1;
    }
    long length = ftell(rom);
    rom_data = malloc((size_t)length);
    rewind(rom);
    if (!rom_data || fread(rom_data, (size_t)length, 1, rom) != 1 || fclose(rom)) {
        perror("ROM read");
        return 1;
    }
    frames = fopen(argv[2], "wb");
    if (!frames) {
        perror(argv[2]);
        return 1;
    }
    nes_frame_limit = 600;
    nes_run();
    if (argc == 4)
        nes_run();
    free(rom_data);
    if (fclose(frames)) {
        perror("frame close");
        return 1;
    }
    return 0;
}
