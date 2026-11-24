# File: Makefile; S-0b three-target build, all products under build/gpu_pc.
ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../../..)
OUT := $(ROOT)/build/gpu_pc
CC := gcc
ZIG := $(HOME)/.local/opt/zig-0.17.0/zig
CFLAGS := -std=c11 -O2 -Wall -Wextra -Werror -I$(ROOT)/sw/bsp/include \
    -I$(ROOT)/sw/drivers/include -I$(ROOT)/sw/lib -I$(ROOT)/sw/lib/plat \
    -I$(ROOT)/sw/apps/gpu_hello -I$(ROOT)/tools/gpu/emu
MAP := -DEDRV32_SOC_MAP_H -include $(ROOT)/sw/bsp/include/gpu_soc_map.h
PCFLAGS := -I$(ROOT)/sw/bsp/pc/include $(CFLAGS) $(MAP) -O3 \
    -include $(ROOT)/sw/bsp/pc/include/mmio.h
COMMON := sw/apps/gpu_hello/hello.c sw/drivers/gpu.c sw/drivers/aud.c \
    sw/drivers/disp.c sw/drivers/plic.c
PC := $(COMMON) sw/lib/plat/pc.c sw/bsp/pc/soc.c sw/bsp/pc/cache.c \
    tools/gpu/emu/gpu_emu.c
BOARD := $(COMMON) sw/apps/gpu_hello/main.c sw/apps/gpu_hello/runtime.c sw/lib/plat/board.c sw/bsp/start.S \
    sw/bsp/host.c sw/bsp/cache.c sw/drivers/uart.c sw/drivers/gpio.c \
    sw/drivers/clint.c sw/drivers/es8156.c sw/drivers/i2c.c sw/drivers/eth.c \
    sw/lib/virtual_input.c
.PHONY: linux windows board
linux: $(OUT)/gpu_hello
windows: $(OUT)/gpu_hello.exe
board: $(OUT)/gpu_hello.elf
HEADERS := $(wildcard $(ROOT)/sw/bsp/pc/include/*.h $(ROOT)/sw/lib/plat/*.h \
    $(ROOT)/sw/apps/gpu_hello/*.h $(ROOT)/tools/gpu/emu/*.h \
    $(ROOT)/tools/gpu/emu/pc/*.h) $(ROOT)/sw/bsp/pc/Makefile
$(OUT)/gpu_hello: $(addprefix $(ROOT)/,$(PC) tools/gpu/emu/pc/headless.c \
    tools/gpu/emu/pc/png.c) $(HEADERS)
	mkdir -p $(OUT)
	$(CC) -pthread $(PCFLAGS) $(filter %.c,$^) -lm -o $@
$(OUT)/gpu_hello.exe: $(addprefix $(ROOT)/,$(PC) tools/gpu/emu/pc/windows.c) $(HEADERS)
	mkdir -p $(OUT)
	$(ZIG) cc -target x86_64-windows-gnu -static $(PCFLAGS) $(filter %.c,$^) \
	    -lwinmm -lgdi32 -luser32 -lm -o $@
$(OUT)/gpu_hello.elf: $(addprefix $(ROOT)/,$(BOARD)) $(HEADERS)
	mkdir -p $(OUT)
	$(MAKE) -C $(ROOT)/sw $(ROOT)/build/sw/soc_memory.ld
	cd $(ROOT) && riscv-none-elf-gcc $(CFLAGS) $(MAP) -march=rv32im_zicsr -mabi=ilp32 \
	    -ffunction-sections -fdata-sections -nostdlib \
	    -Wl,--gc-sections -Tsw/bsp/ld/ddr.ld $(filter %.c %.S,$^) -lm -lc -lgcc -o $@
.PHONY: test
test: $(OUT)/soc_test $(OUT)/platform_input_test
	$(OUT)/soc_test
	$(OUT)/platform_input_test
$(OUT)/platform_input_test: $(addprefix $(ROOT)/,sw/bsp/pc/soc.c sw/lib/plat/pc.c \
    sw/lib/virtual_input.c tools/gpu/emu/gpu_emu.c tools/gpu/emu/pc/platform_input_test.c \
    sw/drivers/plic.c) $(ROOT)/sw/lib/virtual_input.h $(HEADERS)
	mkdir -p $(OUT)
	$(CC) -pthread $(PCFLAGS) $(filter %.c,$^) -o $@
$(OUT)/soc_test: $(addprefix $(ROOT)/,sw/bsp/pc/soc.c tools/gpu/emu/gpu_emu.c \
    tools/gpu/emu/pc/soc_test.c sw/drivers/plic.c) $(HEADERS)
	mkdir -p $(OUT)
	$(CC) -pthread $(PCFLAGS) $(filter %.c,$^) -o $@
