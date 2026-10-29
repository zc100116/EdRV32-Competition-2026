# File: program.mk
# Spec: Task B2-3b; CLAUDE.md 9.2–9.3
# Description: Link all driver implementations and BSP cache maintenance for RV32IM.
# Clock domain: none (build tool).
MEMORY := sram
PROGRAM_SOURCES := sw/tests/drivers_build/main.c \
                   $(patsubst $(ROOT)/%,%,$(wildcard $(ROOT)/sw/drivers/*.c)) \
                   sw/bsp/cache.c
CFLAGS_EXTRA := -I$(ROOT)/sw/drivers/include
