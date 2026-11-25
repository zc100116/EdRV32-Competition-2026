/* File: spike.c
 * Spec: ember_isles tech 3-4; deterministic replay and retired-instruction budget.
 * Description: Time actual simulation, CPU display preparation and audio mixing.
 *              GPU submission is excluded: Spike has no media peripherals.
 * Clock domain: Spike retired instructions and fixed 60 Hz replay.
 */
#include "core/core.h"
#include "sim/sim.h"
#include "gfx2d/gfx.h"
#include "audio/audio.h"
#include "ui/ui.h"
#include "edrv32.h"
#include "replay.h"
#include "data.h"
#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
static struct ember_sim simulation;
static struct ember_ui_state ui;
static uint16_t previous_input;
static uint32_t samples[800];
static uint8_t dma[8 * 1024 * 1024] __attribute__((aligned(4096)));
static size_t dma_used;
static uint8_t heap[65536] __attribute__((aligned(16)));
static ptrdiff_t heap_used;
static uint32_t instret(void)
{
    uint32_t value;
    __asm__ volatile ("csrr %0, instret" : "=r"(value) :: "memory");
    return value;
}
void *plat_dma_alloc(size_t bytes, size_t alignment)
{
    dma_used = (dma_used + alignment - 1) & ~(alignment - 1);
    void *result = dma + dma_used;
    dma_used += bytes;
    return result;
}
uint32_t ddr_physical(const void *address) { return (uint32_t)(uintptr_t)address; }
int plat_printf(const char *format, ...)
{
    va_list args;
    va_start(args, format);
    int count = vprintf(format, args);
    va_end(args);
    return count;
}
int _write(int file, const void *buffer, size_t size)
{
    volatile uint64_t request[8] __attribute__((aligned(16))) = {
        64, (uint32_t)file, (uintptr_t)buffer, size, 0, 0, 0, 0
    };
    __asm__ volatile ("fence rw, rw" ::: "memory");
    tohost = (uintptr_t)request;
    while (!fromhost) {}
    fromhost = 0;
    __asm__ volatile ("fence rw, rw" ::: "memory");
    return (int)size;
}
void *_sbrk(ptrdiff_t increment)
{
    ptrdiff_t next = heap_used + increment;
    if (next < 0 || (size_t)next > sizeof(heap)) { errno = ENOMEM; return (void *)-1; }
    void *result = heap + heap_used;
    heap_used = next;
    return result;
}
int _read(int file, void *buffer, size_t size)
{
    (void)file; (void)buffer; (void)size;
    errno = ENOSYS;
    return -1;
}
int _fstat(int file, struct stat *status)
{
    (void)file;
    memset(status, 0, sizeof(*status));
    status->st_mode = S_IFCHR;
    return 0;
}
_Noreturn void _exit(int status) { edrv32_exit(status); }
int _getpid(void) { return 1; }
int _kill(int pid, int signal)
{
    (void)pid; (void)signal;
    errno = EINVAL;
    return -1;
}
int _isatty(int file) { (void)file; return 1; }
int _close(int file) { (void)file; return 0; }
off_t _lseek(int file, off_t offset, int origin)
{
    (void)file; (void)offset; (void)origin;
    errno = ESPIPE;
    return -1;
}
int main(void)
{
#ifdef EMBER_STRESS_DIAGNOSTIC
    ember_sim_stress(&simulation);
    unsigned frame_count = (unsigned)ember_stress[0].frames;
#else
    ember_sim_begin(&simulation, ember_demo_seed, &ember_demo_config);
    unsigned frame_count = ember_demo_count;
#endif
    ember_audio_stage(simulation.config.stage);
    ember_audio_reset();
    ember_gfx_init();
    printf("RUN,mode=%u,stage=%u,seed=%lu", simulation.config.mode, simulation.config.stage,
        (unsigned long)simulation.rng_seed);
#ifdef EMBER_STRESS_DIAGNOSTIC
    printf(",diagnostic=stress");
#endif
    putchar('\n');
    puts("INST,frame,sim,gfx,audio,total,mode,stage");
    for (unsigned i = 0; i < frame_count; ++i) {
#ifdef EMBER_STRESS_DIAGNOSTIC
        uint16_t input = simulation.phase == EMBER_UPGRADE &&
            !(simulation.previous_input & EMBER_J) ? EMBER_J : 0;
#else
        uint16_t input = ember_demo_input[i];
#endif
        unsigned previous_stage = simulation.config.stage;
        uint32_t begin = instret();
        ember_sim_step(&simulation, input);
        uint32_t after_sim = instret();
        if (simulation.config.stage != previous_stage) ember_audio_stage(simulation.config.stage);
        uint16_t pressed = input & (uint16_t)~previous_input;
        previous_input = input;
        if (pressed & EMBER_SELECT) ui.show_perf ^= 1;
        ember_gfx_prepare(&simulation, 60, &ui);
        uint32_t after_gfx = instret();
        for (unsigned j = 0; j < simulation.events.count; ++j) {
            const struct ember_event *event = &simulation.events.item[j];
            ember_audio_result(event->kind, event->damage_type, event->outcome);
        }
        ember_audio_mix(samples, 800);
        uint32_t after_audio = instret();
        printf("INST,%u,%lu,%lu,%lu,%lu,%u,%u\n", i + 1,
               (unsigned long)(after_sim - begin), (unsigned long)(after_gfx - after_sim),
               (unsigned long)(after_audio - after_gfx), (unsigned long)(after_audio - begin),
               simulation.config.mode, simulation.config.stage);
        if ((i + 1) % 60 == 0) {
            char summary[2048];
            ember_sim_summary(&simulation, summary, sizeof(summary));
            printf("STATE,%s\n", summary);
        }
    }
    printf("END,%lu,%u,%lu,%u,%u\n", (unsigned long)frame_count, simulation.phase,
           (unsigned long)simulation.wave, simulation.config.mode, simulation.config.stage);
    fflush(stdout);
    return 0;
}
