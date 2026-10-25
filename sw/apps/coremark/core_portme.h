/* File: core_portme.h
 * Spec: infra-plan I-07; cpu-spec 2, 4
 * Description: Single-context integer CoreMark port using static work memory.
 *              This infrastructure build is not a reported performance result.
 * Clock domain: clk_sys.
 */
#ifndef CORE_PORTME_H
#define CORE_PORTME_H
#include <stddef.h>
#include <stdint.h>
#define HAS_FLOAT 0
#define HAS_TIME_H 0
#define USE_CLOCK 0
#define HAS_STDIO 0
#define HAS_PRINTF 0
#define COMPILER_VERSION "GCC " __VERSION__
#define COMPILER_FLAGS "-O2 -march=rv32imc_zicsr -mabi=ilp32"
#define MEM_LOCATION "SRAM"
#define SEED_METHOD SEED_VOLATILE
#define MEM_METHOD MEM_STATIC
#define MULTITHREAD 1
#define MAIN_HAS_NOARGC 1
#define MAIN_HAS_NORETURN 0
#define PERFORMANCE_RUN 1
#define VALIDATION_RUN 0
#define PROFILE_RUN 0
#define align_mem(x) ((void *)(((uintptr_t)(x) + 3u) & ~(uintptr_t)3u))
typedef int16_t ee_s16;
typedef uint16_t ee_u16;
typedef int32_t ee_s32;
typedef uint32_t ee_u32;
typedef uint8_t ee_u8;
typedef uintptr_t ee_ptr_int;
typedef size_t ee_size_t;
typedef uint64_t CORE_TICKS;
extern ee_u32 default_num_contexts;
typedef struct {
    ee_u8 portable_id;
} core_portable;
void portable_init(core_portable *port, int *argc, char *argv[]);
void portable_fini(core_portable *port);
int ee_printf(const char *format, ...);
#endif
