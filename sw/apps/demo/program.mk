# File: program.mk
# Spec: SoC 7.5; design 2026-10-29-b2-software 3.1.
# Description: BIOS-loadable SRAM demo and the actual media/YOLO libraries.
# Clock domain: none (build tool).
ARCH := rv32im_zicsr
MEMORY := sram
PROGRAM_SOURCES := $(addprefix sw/apps/demo/,main.c logic.c pipeline.c network.c monitor.c) \
    sw/boot/info.c sw/bsp/cache.c \
    $(addprefix sw/drivers/,uart.c gpio.c clint.c i2c.c plic.c engine.c vin.c pix.c \
    geo.c disp.c npu.c eth.c mem_xbar.c ov5640.c) \
    sw/lib/yolo_post.c sw/lib/yolo_tables.c sw/lib/draw.c
CFLAGS_EXTRA := -I$(ROOT)/sw/drivers/include -I$(ROOT)/sw/boot -I$(ROOT)/sw/lib \
    -fstack-usage
