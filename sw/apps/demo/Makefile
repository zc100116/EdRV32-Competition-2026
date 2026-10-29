# File: Makefile
# Spec: Task B2-4b acceptance; CLAUDE.md 9.3.
# Description: Pure C host tests with undefined-behavior checking; no MMIO or simulation.
# Clock domain: none (build tool).
ROOT := $(abspath ../../..)
OUT := $(ROOT)/build/sw/demo
CC := gcc
CFLAGS := -std=c11 -Wall -Wextra -Werror -O2 -fsanitize=undefined \
    -fno-sanitize-recover=all -I$(ROOT)/sw/bsp/include -I$(ROOT)/sw/drivers/include \
    -I$(ROOT)/sw/lib
.PHONY: test
test:
	mkdir -p $(OUT)
	$(CC) $(CFLAGS) logic.c host_test.c -o $(OUT)/host_test
	$(OUT)/host_test
