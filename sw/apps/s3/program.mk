# File: program.mk
# Spec: Task B3-3b; SoC S3; DDR application execution.
# Description: One program containing LVGL, the shared runtime and the game.
# Clock domain: none (build tool).
MEMORY := ddr_app
PROGRAM_SOURCES := sw/apps/s3/main.c sw/apps/s3/layers.c sw/apps/s3/menu.c \
    sw/apps/s3/s3_platform.c \
    sw/drivers/rnd.c sw/drivers/disp.c sw/drivers/engine.c sw/drivers/plic.c \
    sw/drivers/uart.c sw/drivers/gpio.c sw/drivers/clint.c sw/bsp/cache.c
PROGRAM_SOURCES += sw/lib/virtual_input.c sw/lib/virtual_input_uart.c sw/lib/virtual_input_irq.c \
    sw/lib/eth_monitor.c sw/lib/eth_monitor_pack.c \
    sw/lib/eth_monitor_board.c sw/drivers/eth.c sw/boot/info.c
CFLAGS_EXTRA := -I$(ROOT)/sw/lib -I$(ROOT)/sw/boot -I$(ROOT)/sw/drivers/include -I$(ROOT)/sw/apps/s3
include $(ROOT)/sw/apps/s3/lvgl/program.mk
include $(ROOT)/sw/apps/s3/game/program.mk
