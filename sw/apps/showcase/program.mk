# File: program.mk
# Design: showcase 4.1--4.5; single BIOS-loaded DDR application.
MEMORY := showcase
PROGRAM_SOURCES := sw/apps/showcase/main.c sw/apps/showcase/platform.c sw/apps/showcase/input.c \
    sw/apps/showcase/launcher.c sw/apps/showcase/layers.c sw/apps/showcase/status.c \
    sw/lib/sched/sched.c \
    sw/drivers/rnd.c sw/drivers/disp.c sw/drivers/engine.c sw/drivers/plic.c \
    sw/drivers/uart.c sw/drivers/gpio.c sw/drivers/clint.c sw/bsp/cache.c \
    sw/lib/virtual_input.c sw/lib/virtual_input_uart.c sw/lib/virtual_input_irq.c \
    sw/lib/eth_monitor.c sw/lib/eth_monitor_pack.c sw/lib/eth_monitor_board.c \
    sw/drivers/eth.c sw/boot/info.c
CFLAGS_EXTRA := -I$(ROOT)/sw/lib -I$(ROOT)/sw/lib/sched -I$(ROOT)/sw/boot \
    -I$(ROOT)/sw/drivers/include -I$(ROOT)/sw/apps/showcase
include $(ROOT)/sw/apps/showcase/lvgl/program.mk
include $(ROOT)/sw/apps/showcase/nes/program.mk
