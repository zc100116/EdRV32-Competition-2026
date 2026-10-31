# File: Makefile
# Spec: Task B2-4b acceptance; CLAUDE.md 9.3.
# Description: Pure C host tests with undefined-behavior checking; no MMIO or simulation.
# Clock domain: none (build tool).
ROOT := $(abspath ../../..)
OUT := $(ROOT)/build/sw/demo
CC := gcc
CFLAGS := -std=c11 -Wall -Wextra -Werror -O2 -fsanitize=undefined \
    -fno-sanitize-recover=all -I$(ROOT)/sw/bsp/include -I$(ROOT)/sw/drivers/include \
    -I$(ROOT)/sw/lib -I$(ROOT)/sw/boot -DDEMO_HOST_TEST -include host_mmio.h \
    -ffunction-sections -fdata-sections
DRIVERS := $(addprefix $(ROOT)/sw/drivers/,vin.c pix.c geo.c disp.c eth.c npu.c)
.PHONY: test
test:
	mkdir -p $(OUT)
	$(CC) $(CFLAGS) logic.c overlay_label.c overlay_cpu.c host_test.c switch_host_test.c \
	    $(ROOT)/sw/lib/eth_monitor_pack.c $(ROOT)/sw/lib/eth_monitor.c \
	    pipeline.c switch.c network.c scene_npu.c overlay_surface.c $(DRIVERS) \
	    -Wl,--gc-sections -o $(OUT)/host_test
	$(OUT)/host_test
	$(CC) $(CFLAGS) $(ROOT)/sw/lib/eth_monitor_test.c $(ROOT)/sw/lib/eth_monitor.c \
	    $(ROOT)/sw/lib/eth_monitor_pack.c $(ROOT)/sw/lib/eth_monitor_board.c \
	    $(ROOT)/sw/drivers/eth.c -Wl,--gc-sections -o $(OUT)/eth_monitor_test
	$(OUT)/eth_monitor_test
