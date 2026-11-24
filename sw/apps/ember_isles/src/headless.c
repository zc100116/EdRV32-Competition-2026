/* File: headless.c
 * Spec: ember_isles tech 3-4; E3 replay acceptance.
 * Description: Run recorded keyboard bitmaps through the shared GPU game loop.
 * Clock domain: virtual 60 Hz host frontend.
 */
#include "game.h"
#include "core/core.h"
#include "pc_soc.h"
#include "png.h"
#include "plat.h"
#include "aud.h"
#include "mmio.h"
#include "regs/gpu_regs.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static unsigned frame;
static uint16_t keys;
static struct ember_replay replay;
uint32_t pc_frontend_wait(void) { return 800; }
uint32_t pc_frontend_keys(void) { return keys; }
uint32_t pc_frontend_millis(void) { return (uint32_t)((uint64_t)frame * 1000u / 60u); }
void pc_frontend_audio(const int16_t *samples, uint32_t count)
{
    (void)samples;
    (void)count;
}
static int selected(const char *list, unsigned number)
{
    if (!list) return 0;
    while (*list) {
        char *end;
        unsigned long value = strtoul(list, &end, 10);
        if (end == list || (*end && *end != ',')) {
            fputs("Invalid --dump frame list\n", stderr);
            exit(1);
        }
        if (value == number) return 1;
        list = *end ? end + 1 : end;
    }
    return 0;
}
int main(int argc, char **argv)
{
    const char *input = NULL;
    const char *dump = NULL;
    const char *out = "build/ember_isles/frames";
    unsigned limit = 0;
    for (int i = 1; i < argc; ++i) {
        const char *name = argv[i];
        if (++i == argc) { fputs("Missing option value\n", stderr); return 1; }
        if (!strcmp(name, "--replay")) input = argv[i];
        else if (!strcmp(name, "--dump")) dump = argv[i];
        else if (!strcmp(name, "--out")) out = argv[i];
        else if (!strcmp(name, "--frames")) limit = (unsigned)strtoul(argv[i], NULL, 10);
        else { fprintf(stderr, "Unknown option: %s\n", name); return 1; }
    }
    if (!input) {
        fputs("ember_isles --replay file [--dump frames --out existing-directory]\n", stderr);
        return 1;
    }
    ember_replay_load(&replay, input);
    if (!limit) limit = replay.count;
    if (limit > replay.count) { fputs("Requested frames exceed replay\n", stderr); return 1; }
    ember_game_init();
    ember_game_replay(replay.seed);
    puts("PERF,frame,busy,vertices,triangles,quads,pixels,tex_stall,read_wait,resolve,obj");
    for (frame = 1; frame <= limit; ++frame) {
        keys = replay.input[frame - 1];
        pc_soc_game_input(keys, (struct plat_pointer_state){0});
        ember_game_frame(frame);
        plat_wait_vsync();
        if (frame % 60 == 0) {
            char summary[2048];
            ember_sim_summary(ember_game_state(), summary, sizeof(summary));
            printf("STATE,%s\n", summary);
        }
        printf("PERF,%u", frame);
        for (unsigned i = 0; i < 9; ++i)
            printf(",%u", mmio_read32(EDRV32_GPU_BASE + EDRV32_GPU_PERF_OFFSET(i)));
        putchar('\n');
        if (selected(dump, frame)) {
            char path[512];
            snprintf(path, sizeof(path), "%s/frame%05u.png", out, frame);
            pc_png_write(path, pc_soc_pixels());
        }
    }
    printf("END,%u,%u,%u\n", limit, ember_game_state()->phase, ember_game_state()->wave);
    printf("AUDIO,underruns=%u\n", (unsigned)aud_underruns());
    pc_soc_destroy();
    return 0;
}
