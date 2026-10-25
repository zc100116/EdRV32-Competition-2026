#ifndef EDRV32_CORE_PORTME_H
#define EDRV32_CORE_PORTME_H

#define HAS_FLOAT          0
#define HAS_TIME_H         0
#define USE_CLOCK          0
#define HAS_STDIO          0
#define HAS_PRINTF         0
#define MAIN_HAS_NOARGC    1
#define MAIN_HAS_NORETURN  0
#define MULTITHREAD        1
#define MEM_METHOD         MEM_STACK
#define SEED_METHOD        SEED_VOLATILE
#define ITERATIONS         4000

#define COMPILER_VERSION   "GCC " __VERSION__
#define COMPILER_FLAGS     "-march=rv32imc -mabi=ilp32 -O2"
#define MEM_LOCATION       "cached SRAM code/data"

typedef signed short       ee_s16;
typedef unsigned short     ee_u16;
typedef signed int         ee_s32;
typedef unsigned char      ee_u8;
typedef unsigned int       ee_u32;
typedef ee_u32             ee_ptr_int;
typedef ee_u32             ee_size_t;
typedef ee_u32             CORE_TICKS;

#define CORETIMETYPE       ee_u32
#define NULL               ((void *)0)
#define align_mem(x)       (void *)(4u + (((ee_ptr_int)(x) - 1u) & ~3u))

typedef struct CORE_PORTABLE_S {
    ee_u8 portable_id;
} core_portable;

extern ee_u32 default_num_contexts;
extern int edrv32_hpm_profile;

void portable_init(core_portable *port, int *argc, char *argv[]);
void portable_fini(core_portable *port);
int ee_printf(const char *format, ...);

#endif
