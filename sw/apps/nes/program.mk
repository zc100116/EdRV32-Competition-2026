# File: program.mk
# Spec: SoC 7.5; Task B3-4b; CLAUDE.md 9.3.
# Description: BIOS-loadable DDR emulator, or bounded Spike instruction measurement.
# Clock domain: none (build tool).
include $(ROOT)/sw/apps/nes/sources.mk
NES_DISPLAY ?= $(if $(filter 1,$(NES_SPIKE)),0,1)
PROGRAM_SOURCES := $(NES_CORE) $(NES_COMMON) sw/apps/nes/rom.S \
    sw/apps/nes/main.c sw/apps/nes/syscalls.c
CFLAGS_EXTRA := $(NES_FLAGS) -I$(ROOT)/sw/lib -I$(ROOT)/sw/drivers/include \
    -DNES_SKIP=$(NES_SKIP) -DNES_FRAMES=$(NES_FRAMES) -DNES_DISPLAY=$(NES_DISPLAY)
PROGRAM_LDLIBS := $(NES_WRAPS) -Wl,--start-group -lc -lm -lgcc -Wl,--end-group
ifeq ($(NES_SPIKE),1)
CFLAGS_EXTRA += -DNES_SPIKE
else
PROGRAM_SOURCES += sw/apps/nes/input.c sw/drivers/uart.c sw/drivers/gpio.c sw/drivers/clint.c \
    sw/lib/virtual_input.c sw/lib/virtual_input_uart.c sw/lib/virtual_input_irq.c \
    sw/lib/eth_monitor.c sw/drivers/eth.c
ifneq ($(NES_DISPLAY),1)
PROGRAM_SOURCES += sw/drivers/engine.c sw/drivers/plic.c
endif
endif

ifeq ($(NES_DISPLAY),1)
PROGRAM_SOURCES += sw/apps/nes/display.c sw/apps/nes/display_command.c \
    sw/drivers/rnd.c sw/drivers/disp.c sw/drivers/engine.c sw/drivers/plic.c sw/bsp/cache.c
endif
