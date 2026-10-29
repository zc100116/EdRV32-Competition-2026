# File: Makefile
# Spec: Task B2-3b; CLAUDE.md 9.3.
# Description: Host-only pure logic tests, no engine MMIO or SoC simulation.
# Clock domain: none (build tool).
ROOT := $(abspath ../../..)
OUT := $(ROOT)/build/sw/drivers_build
CC := gcc
CFLAGS := -std=c11 -Wall -Wextra -Werror -O2 \
          -I$(ROOT)/sw/bsp/include -I$(ROOT)/sw/drivers/include
DRIVERS := engine vin pix geo disp npu eth mem_xbar perf_mon ov5640 plic i2c gpio clint
SOURCES := host_test.c host_bsp.c $(addprefix $(ROOT)/sw/drivers/,$(addsuffix .c,$(DRIVERS)))
.PHONY: test

test:
	mkdir -p $(OUT)
	$(CC) $(CFLAGS) $(SOURCES) -o $(OUT)/host_test
	$(OUT)/host_test
