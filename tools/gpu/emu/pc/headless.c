/* File: headless.c
 * Spec: PC design 4.5; S-0b deterministic input, PNG and PERF capture.
 * Description: Virtual 60 Hz clock with frame-indexed controller scripts.
 * Clock domain: host, virtual media time.
 */
#include "pc_soc.h"
#include "plat.h"
#include "hello.h"
#include "png.h"
#include "mmio.h"
#include "regs/gpu_regs.h"
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
static uint32_t frame, keys;
uint32_t pc_frontend_wait(void) { return 800; }
uint32_t pc_frontend_keys(void) { return keys; }
uint32_t pc_frontend_millis(void) { return (uint32_t)((uint64_t)frame * 1000u / 60u); }
void pc_frontend_audio(const int16_t *samples, uint32_t frames)
{
    (void)samples; (void)frames;
}
static _Noreturn void usage(void)
{
    fputs("gpu_hello --frames N [--input script] [--dump 1,150,300 --out directory]\n", stderr);
    exit(1);
}
static int selected(const char *list, unsigned number)
{
    if (!list) return 0;
    while (*list) {
        char *end;
        unsigned long value = strtoul(list, &end, 10);
        if (end == list || (*end && *end != ',')) usage();
        if (value == number) return 1;
        list = *end ? end + 1 : end;
    }
    return 0;
}
static int read_event(FILE *script, unsigned *number, unsigned *bits)
{
    if (!script) return 0;
    char line[128], extra;
    int value;
    if (!fgets(line, sizeof(line), script)) {
        if (ferror(script)) { perror("input script"); exit(1); }
        return 0;
    }
    if (sscanf(line, "%u %i %c", number, &value, &extra) != 2) {
        fprintf(stderr, "Invalid input script line: %s", line);
        exit(1);
    }
    *bits = (unsigned)value;
    return 1;
}
int main(int argc, char **argv)
{
    unsigned frames = 0;
    const char *input = NULL, *dump = NULL, *out = NULL;
    for (int i = 1; i < argc; ++i) {
        if (i + 1 == argc) usage();
        const char *arg = argv[++i];
        if (!strcmp(argv[i - 1], "--frames")) frames = (unsigned)strtoul(arg, NULL, 10);
        else if (!strcmp(argv[i - 1], "--input")) input = arg;
        else if (!strcmp(argv[i - 1], "--dump")) dump = arg;
        else if (!strcmp(argv[i - 1], "--out")) out = arg;
        else usage();
    }
    if (!frames || (dump && !out)) usage();
    if (out && mkdir(out, 0777) && errno != EEXIST) { perror(out); return 1; }
    FILE *script = NULL;
    unsigned next_frame = 0, next_keys = 0;
    if (input) {
        script = fopen(input, "r");
        if (!script) { perror(input); return 1; }
    }
    int has_event = read_event(script, &next_frame, &next_keys);
    hello_init();
    fputs("frame", stdout);
    for (unsigned i = 0; i < EDRV32_GPU_PERF_N_COUNT; ++i) printf(",perf%u", i);
    putchar('\n');
    for (frame = 1; frame <= frames; ++frame) {
        while (has_event && next_frame <= frame) {
            keys = next_keys;
            has_event = read_event(script, &next_frame, &next_keys);
        }
        if (frame == 150 && selected(dump, frame)) pc_soc_trace_begin(out);
        hello_frame(frame);
        if (frame == 150 && selected(dump, frame)) pc_soc_trace_end();
        plat_wait_vsync();
        if (selected(dump, frame)) {
            char path[1024];
            snprintf(path, sizeof(path), "%s/frame%03u.png", out, frame);
            pc_png_write(path, pc_soc_pixels());
        }
        printf("%u", frame);
        for (unsigned i = 0; i < EDRV32_GPU_PERF_N_COUNT; ++i)
            printf(",%u", mmio_read32(EDRV32_GPU_BASE + EDRV32_GPU_PERF_OFFSET(i)));
        putchar('\n');
    }
    if (script) fclose(script);
    pc_soc_destroy();
    return 0;
}
