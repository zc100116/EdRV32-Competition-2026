# File: program.mk
# Spec: gpu-soc-testplan ST-10-ST-14; CLAUDE.md 9.3.
# Description: Compile GPU SoC test with BSP and generated register headers.
# Clock domain: host build.
CFLAGS_EXTRA += -I$(ROOT)/sw/drivers/include -I$(ROOT)/sw/tests/gpu_drivers
PROGRAM_SOURCES := sw/tests/gpu_audio/main.c sw/drivers/gpu.c sw/drivers/aud.c \
                   sw/drivers/es8156.c sw/drivers/i2c.c sw/drivers/plic.c \
                   sw/drivers/uart.c sw/bsp/cache.c sw/tests/gpu_drivers/memory.c
