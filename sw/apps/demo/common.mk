# File: common.mk
# Spec: Task B3-11; CLAUDE.md 9.3.
# Description: Common demo/S2 sources; variants append scene and drawing sources.
# Clock domain: none (build tool).
ARCH := rv32im_zicsr
MEMORY := sram
PROGRAM_SOURCES := $(addprefix sw/apps/demo/,main.c logic.c parameters.c parameters_runtime.c \
    pipeline.c switch.c network.c network_video.c monitor.c monitor_video.c) \
    sw/lib/affine.c sw/lib/eth_monitor.c sw/lib/eth_monitor_pack.c sw/boot/info.c sw/bsp/cache.c \
    $(addprefix sw/drivers/,uart.c gpio.c clint.c i2c.c plic.c engine.c vin.c pix.c \
    geo.c disp.c eth.c mem_xbar.c ov5640.c)
CFLAGS_EXTRA := -I$(ROOT)/sw/drivers/include -I$(ROOT)/sw/boot -I$(ROOT)/sw/lib \
    -fstack-usage -Os

PROGRAM_LDLIBS := -lc
