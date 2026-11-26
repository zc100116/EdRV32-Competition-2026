# GPU test games; gpu-spec 2–7. Build one target at a time on the shared host.
ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../../..)
APP := $(ROOT)/sw/apps/gpu_test
COMMON := $(ROOT)/sw/apps/gpu_test_common
OUT := $(ROOT)/build/gpu_test
CC := gcc
ZIG := $(HOME)/.local/opt/zig-0.17.0/zig
CFLAGS := -std=c11 -O2 -Wall -Wextra -Werror -I$(COMMON) -I$(OUT)/generated \
    -I$(ROOT)/sw/bsp/include -I$(ROOT)/sw/drivers/include -I$(ROOT)/sw/lib \
    -I$(ROOT)/sw/lib/plat -I$(ROOT)/tools/gpu/emu -I$(ROOT)/tools/gpu/emu/pc
CFLAGS += -I$(ROOT)/sw/apps/gpu_test_rogue
MAP := -DEDRV32_SOC_MAP_H -include $(ROOT)/sw/bsp/include/gpu_soc_map.h
PCFLAGS := -I$(ROOT)/sw/bsp/pc/include $(CFLAGS) $(MAP) -O3 \
    -DGPU_TEST_PC -DGPU_EMU_TEXTURE_BYTES=196608 -include $(ROOT)/sw/bsp/pc/include/mmio.h
SOURCES := $(COMMON)/runtime.c $(ROOT)/sw/apps/gpu_test2d/patrol.c \
    $(ROOT)/sw/apps/gpu_test3d/canyon.c
SOURCES += $(ROOT)/sw/apps/gpu_test_rogue/rogue.c $(ROOT)/sw/apps/gpu_test_world/world.c
DRIVERS := sw/drivers/gpu.c sw/drivers/aud.c sw/drivers/disp.c sw/drivers/plic.c
PC := sw/lib/plat/pc.c sw/bsp/pc/soc.c sw/bsp/pc/cache.c tools/gpu/emu/gpu_emu.c
BOARD := sw/lib/plat/board.c sw/bsp/start.S sw/bsp/host.c sw/bsp/cache.c \
    sw/drivers/uart.c sw/drivers/gpio.c sw/drivers/clint.c sw/drivers/es8156.c \
    sw/drivers/i2c.c sw/drivers/eth.c sw/lib/virtual_input.c sw/apps/gpu_hello/runtime.c
HEADERS := $(COMMON)/test.h $(wildcard $(ROOT)/sw/bsp/include/regs/*.h)
ASSETS := $(OUT)/generated/assets.h
ASSET_INPUTS := $(wildcard $(ROOT)/sw/apps/gpu_test2d/assets/imagegen/*.png) \
    $(wildcard $(ROOT)/sw/apps/gpu_test3d/assets/imagegen/*.png) \
    $(wildcard $(COMMON)/assets/fusion-pixel/*.bdf) \
    $(COMMON)/assets/palette.json $(COMMON)/tools/art.py
.PHONY: board linux windows hud-test
board: $(OUT)/gpu_test.elf
linux: $(OUT)/gpu_test
windows: $(OUT)/gpu_test.exe
hud-test: $(OUT)/hud_test
	$<
$(OUT)/hud_test: $(SOURCES) $(COMMON)/tools/hud_test.c $(APP)/headless.c $(ASSETS) $(HEADERS)
	$(CC) -pthread $(PCFLAGS) $(SOURCES) $(COMMON)/tools/hud_test.c \
	    $(addprefix $(ROOT)/,$(DRIVERS) $(PC) tools/gpu/emu/pc/png.c) -o $@
$(ASSETS): $(COMMON)/tools/assets.py $(ASSET_INPUTS)
	python3 $< $@
$(OUT)/gpu_test: $(SOURCES) $(APP)/headless.c $(ASSETS) $(HEADERS) $(APP)/Makefile
	mkdir -p $(OUT)
	$(CC) -pthread $(PCFLAGS) $(SOURCES) $(APP)/headless.c \
	    $(addprefix $(ROOT)/,$(DRIVERS) $(PC) tools/gpu/emu/pc/png.c) -o $@
$(OUT)/gpu_test.exe: $(SOURCES) $(APP)/windows.c $(ASSETS) $(HEADERS) $(APP)/Makefile
	mkdir -p $(OUT)
	$(ZIG) cc -target x86_64-windows-gnu -static $(PCFLAGS) \
	    $(SOURCES) $(APP)/windows.c $(addprefix $(ROOT)/,$(DRIVERS) $(PC)) \
	    -lwinmm -lgdi32 -luser32 -o $@
$(OUT)/gpu_test.elf: $(SOURCES) $(APP)/main.c $(ASSETS) $(HEADERS) $(APP)/Makefile
	mkdir -p $(OUT)
	$(MAKE) -C $(ROOT)/sw $(ROOT)/build/sw/soc_memory.ld -j1
	cd $(ROOT) && riscv-none-elf-gcc $(CFLAGS) $(MAP) -march=rv32im_zicsr -mabi=ilp32 \
	    -ffunction-sections -fdata-sections -nostdlib -Wl,--gc-sections \
	    -Tsw/bsp/ld/ddr.ld $(SOURCES) $(APP)/main.c \
	    $(addprefix $(ROOT)/,$(DRIVERS) $(BOARD)) -lc -lgcc -o $@

G4_HEADERS := $(OUT)/generated/rogue_assets.h $(OUT)/generated/world_assets.h
$(OUT)/gpu_test $(OUT)/gpu_test.exe $(OUT)/gpu_test.elf $(OUT)/hud_test: $(G4_HEADERS) \
    $(ROOT)/sw/apps/gpu_test_rogue/demo.h
$(OUT)/generated/rogue_assets.h: $(ROOT)/sw/apps/gpu_test_rogue/tools/assets.py \
    $(wildcard $(ROOT)/sw/apps/gpu_test_rogue/assets/*) $(COMMON)/tools/art.py \
    $(COMMON)/assets/palette.json
	python3 $(ROOT)/sw/apps/gpu_test_rogue/tools/assets.py $@
$(OUT)/generated/world_assets.h: $(ROOT)/sw/apps/gpu_test_world/tools/assets.py \
    $(ROOT)/sw/apps/gpu_test_world/assets/terrain.png $(COMMON)/tools/art.py \
    $(COMMON)/assets/palette.json
	python3 $(ROOT)/sw/apps/gpu_test_world/tools/assets.py $@
