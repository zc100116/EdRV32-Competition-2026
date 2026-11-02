# Makefile: showcase design 4.4; host build of cooperative NES frame entry.
# Clock domain: host monotonic time.
.DEFAULT_GOAL := all
ROOT := $(abspath ../../../..)
OUT ?= $(ROOT)/build/sw/showcase-nes-host
CC := gcc
include sources.mk
SOURCES := $(NES_CORE) $(NES_COMMON) sw/apps/nes/host.c
OBJECTS := $(addprefix $(OUT)/obj/,$(SOURCES:.c=.o))
CFLAGS := -std=c11 -Wall -Wextra -Werror -ffunction-sections -fdata-sections $(NES_FLAGS)
.PHONY: all FORCE
FORCE:
all: $(OUT)/nes-host
$(OUT)/nes-host: $(OBJECTS)
	$(CC) $(OBJECTS) -Wl,--gc-sections -lm -o $@
$(OUT)/obj/%.o: $(ROOT)/%.c FORCE
	mkdir -p $(@D)
	$(CC) $(CFLAGS) -c $< -o $@
