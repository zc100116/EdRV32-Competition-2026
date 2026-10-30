# File: Makefile
# Spec: Task B3-4b; CLAUDE.md 9.3.
# Description: Linux reference build using the same emulator and frame interface.
# Clock domain: none (build tool).
.DEFAULT_GOAL := all
ROOT := $(abspath ../../..)
OUT ?= $(ROOT)/build/sw/nes-host
CC := gcc
include sources.mk
SOURCES := $(NES_CORE) $(NES_COMMON) sw/apps/nes/host.c
OBJECTS := $(addprefix $(OUT)/obj/,$(SOURCES:.c=.o))
CFLAGS := -std=c11 -Wall -Wextra -Werror -ffunction-sections -fdata-sections $(NES_FLAGS)
.PHONY: all FORCE
FORCE:
all: $(OUT)/nes-host
$(OUT)/nes-host: $(OBJECTS)
	$(CC) $(OBJECTS) -Wl,--gc-sections $(NES_WRAPS) -lm -o $@
$(OUT)/obj/%.o: $(ROOT)/%.c FORCE
	mkdir -p $(@D)
	$(CC) $(CFLAGS) -c $< -o $@
