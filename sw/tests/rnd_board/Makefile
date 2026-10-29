# File: Makefile
# Spec: Task B3-3a host acceptance.
# Description: Actual C encoder/driver tests; no RTL or SoC simulation.
# Clock domain: none (build tool).
ROOT := $(abspath ../../..)
OUT := $(ROOT)/build/sw/rnd_board/host
CFLAGS := -std=c11 -Wall -Wextra -Werror -O2 \
    -I$(ROOT)/sw/bsp/include -I$(ROOT)/sw/drivers/include
.PHONY: test
test:
	python3 test_encode.py
	mkdir -p $(OUT)
	gcc $(CFLAGS) host_runtime.c $(ROOT)/sw/drivers/rnd.c \
	    $(ROOT)/sw/drivers/disp.c $(ROOT)/sw/drivers/plic.c -o $(OUT)/runtime
	$(OUT)/runtime
	python3 test_expect.py
