/* File: audio_bench.c
 * Spec: ember_isles tech 4; standalone retired-instruction measurement.
 * Description: Spike HTIF harness: print music-only then each of 13 four-effect mix counts
 * for 800 stereo frames, repeated for all three stages.
 * Links independently of game, GPU and platform code.
 * Clock domain: RV32 instret; 48 kHz generated stream.
 */
#include <stdint.h>
#include "audio.h"
volatile uint64_t tohost __attribute__((section(".tohost"), aligned(64)));
volatile uint64_t fromhost __attribute__((section(".tohost"), aligned(64)));
uint8_t stack[4096];
static uint32_t samples[800];
__asm__(".section .text.start\n.global _start\n_start:\n"
        ".option push\n.option norelax\nla gp, __global_pointer$\n.option pop\n"
        "la sp, stack\nli t0,4096\nadd sp,sp,t0\ncall main\n1: j 1b\n.text\n");
static uint32_t instructions(void)
{
    uint32_t value;
    __asm__ volatile("csrr %0, instret" : "=r"(value) :: "memory");
    return value;
}
static void print_number(uint32_t n)
{
    char text[16];
    unsigned end = sizeof(text);
    text[--end] = '\n';
    do {
        text[--end] = (char)('0' + n % 10);
        n /= 10;
    } while (n);
    volatile uint64_t request[8] __attribute__((aligned(16))) = {
        64, 1, (uintptr_t)(text + end), sizeof(text) - end, 0, 0, 0, 0
    };
    __asm__ volatile("fence rw,rw" ::: "memory");
    tohost = (uintptr_t)request;
    while (!fromhost) {}
    fromhost = 0;
}
int main(void)
{
    for (unsigned stage = 0; stage < 3; ++stage) {
        ember_audio_stage(stage);
        ember_audio_reset();
        uint32_t start = instructions();
        ember_audio_mix(samples, 800);
        uint32_t end = instructions();
        print_number(end - start);
        for (unsigned cue = 0; cue < 13; ++cue) {
            ember_audio_reset();
            for (unsigned i = 0; i < 4; ++i) ember_audio_event(cue);
            start = instructions();
            ember_audio_mix(samples, 800);
            end = instructions();
            print_number(end - start);
        }
    }
    __asm__ volatile("fence rw,rw" ::: "memory");
    tohost = 1;
    for (;;) {}
}
