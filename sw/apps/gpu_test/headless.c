/* headless.c — gpu-spec 7; deterministic PC preview and per-frame GPU counters.
 * Clock domain: host wall-clock measurements, virtual 60 Hz simulation ticks.
 */
#include "test.h"
#include "pc_soc.h"
#include "png.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
static unsigned frame;
static uint32_t input_keys;
uint64_t test_clock_us(void)
{
    struct timespec now;
    timespec_get(&now, TIME_UTC);
    return (uint64_t)now.tv_sec*1000000 + (unsigned)now.tv_nsec/1000;
}
uint32_t pc_frontend_wait(void) { return 800; }
uint32_t pc_frontend_keys(void) { return input_keys; }
uint32_t pc_frontend_millis(void) { return frame*1000/60; }
void pc_frontend_audio(const int16_t *samples, uint32_t frames)
{
    (void)samples;
    (void)frames;
}
static _Noreturn void usage(void)
{
    fputs("gpu_test --scene 0|1|2 --mode 0|1|2 --level 0..6 --filter 0|1|2 "
          "--frames N --out existing-dir [--sequence 0|1] [--input script]\n", stderr);
    exit(1);
}
int main(int argc, char **argv)
{
    unsigned scene = 1, mode = 0, level = 0, filter = 2, frames = 3, sequence = 0;
    const char *out = NULL;
    const char *input = NULL;
    for (int i = 1; i < argc; ++i) {
        if (i+1 == argc) usage();
        const char *key = argv[i++];
        const char *value = argv[i];
        if (!strcmp(key, "--out")) out = value;
        else if (!strcmp(key, "--input")) input = value;
        else {
            char *end;
            unsigned n = (unsigned)strtoul(value, &end, 10);
            if (*end) usage();
            if (!strcmp(key, "--scene")) scene = n;
            else if (!strcmp(key, "--mode")) mode = n;
            else if (!strcmp(key, "--level")) level = n;
            else if (!strcmp(key, "--filter")) filter = n;
            else if (!strcmp(key, "--frames")) frames = n;
            else if (!strcmp(key, "--sequence")) sequence = n;
            else usage();
        }
    }
    if (scene > 2 || mode > 2 || level > 6 || filter > 2 || !frames || !out) usage();
    FILE *script = NULL;
    unsigned next_frame = 0;
    unsigned next_keys = 0;
    int event = 0;
    if (input) {
        script = fopen(input, "r");
        if (!script) { perror(input); return 1; }
        event = fscanf(script, "%u %u", &next_frame, &next_keys);
    }
    test_init();
    test_select(scene, mode, level, filter);
    puts("frame,objects,triangles,commands,passed_pixels,cpu_us,gpu_us,fps10,texture_bytes,"
         "game,mode,level,filter,cpu,aa,score,health");
    for (frame = 1; frame <= frames; ++frame) {
        while (event == 2 && next_frame <= frame) {
            input_keys = next_keys;
            event = fscanf(script, "%u %u", &next_frame, &next_keys);
        }
        if (script && event != EOF && event != 2) {
            fputs("Malformed headless input event\n", stderr);
            return 1;
        }
        test_frame();
        plat_wait_vsync();
        if (sequence || frame == frames) {
            char path[1024];
            snprintf(path, sizeof(path), "%s/frame%04u.png", out, frame);
            pc_png_write(path, pc_soc_pixels());
        }
        struct gpu_emu_usage usage = pc_soc_gpu_usage();
        printf("%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u\n",
               frame, test.alive_count,
               test.triangles/3, test.command_count, test.pixels, test.cpu_us,
               test.gpu_us, test.fps10, usage.texture_bytes, test.game, test.mode, test.level,
               test.filter, test.cpu, test.aa, test.score, test.health);
        fflush(stdout);
    }
    if (script) fclose(script);
    pc_soc_destroy();
    return 0;
}
