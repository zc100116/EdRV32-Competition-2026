# File: program.mk
# Spec: SoC 7.5; Task B3-4b; CLAUDE.md 9.3.
# Description: BIOS-loadable DDR emulator, or bounded Spike instruction measurement.
# Clock domain: none (build tool).
include $(ROOT)/sw/apps/nes/sources.mk
PROGRAM_SOURCES := $(NES_CORE) $(NES_COMMON) sw/apps/nes/main.c sw/apps/nes/syscalls.c
CFLAGS_EXTRA := $(NES_FLAGS) -I$(ROOT)/sw/drivers/include \
    -DNES_SKIP=$(NES_SKIP) -DNES_FRAMES=$(NES_FRAMES)
PROGRAM_LDLIBS := $(NES_WRAPS) -Wl,--start-group -lc -lm -lgcc -Wl,--end-group
ifeq ($(NES_SPIKE),1)
CFLAGS_EXTRA += -DNES_SPIKE
else
PROGRAM_SOURCES += sw/drivers/uart.c sw/drivers/gpio.c sw/drivers/clint.c
endif
