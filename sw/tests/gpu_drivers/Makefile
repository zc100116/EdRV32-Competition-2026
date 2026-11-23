# File: Makefile
# Spec: CLAUDE.md 9.3; gpu-soc-testplan BSP acceptance.
# Description: Host driver behavioral checks; generated outputs remain in build/.
# Clock domain: host.
ROOT := $(abspath ../../..)
OUT := $(ROOT)/build/gpu_drivers
.PHONY: test
test:
	mkdir -p $(OUT)
	$(CC) -std=c11 -Wall -Wextra -Werror -I$(ROOT)/sw/drivers/include \
	    -I$(ROOT)/sw/bsp/include $(ROOT)/sw/tests/gpu_drivers/host_test.c \
	    $(ROOT)/sw/drivers/gpu.c $(ROOT)/sw/drivers/aud.c $(ROOT)/sw/drivers/es8156.c \
	    -o $(OUT)/host_test
	$(OUT)/host_test
