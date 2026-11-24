# File: Makefile; ember_isles E1/E2 real-driver presentation verification.
ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../../../../../..)
APP := $(ROOT)/sw/apps/ember_isles
OUT := $(ROOT)/build/ember_isles
CC := gcc
CFLAGS := -std=c11 -O2 -Wall -Wextra -Werror -I$(ROOT)/sw/bsp/pc/include \
    -I$(APP)/src -I$(OUT)/generated -I$(ROOT)/sw/drivers/include \
    -I$(ROOT)/sw/bsp/include -I$(ROOT)/sw/lib/plat -I$(ROOT)/tools/gpu/emu \
    -I$(ROOT)/tools/gpu/emu/pc -DEDRV32_SOC_MAP_H \
    -include $(ROOT)/sw/bsp/include/gpu_soc_map.h -include $(ROOT)/sw/bsp/pc/include/mmio.h
SOURCES := $(APP)/src/gfx2d/tests/preview.c $(APP)/src/gfx2d/gfx.c $(APP)/src/ui/ui.c \
    $(ROOT)/sw/drivers/gpu.c $(ROOT)/sw/drivers/disp.c $(ROOT)/sw/drivers/plic.c \
    $(ROOT)/sw/lib/plat/pc.c $(ROOT)/sw/bsp/pc/soc.c $(ROOT)/sw/bsp/pc/cache.c \
    $(ROOT)/tools/gpu/emu/gpu_emu.c $(ROOT)/tools/gpu/emu/pc/png.c
HEADERS := $(APP)/src/gfx2d/gfx.h $(APP)/src/ui/ui.h $(APP)/src/sim/sim.h
GENERATED := $(OUT)/generated/atlas.h $(OUT)/generated/data.h
.PHONY: check asan
check: $(OUT)/gfx-preview
	cd $(ROOT) && $(OUT)/gfx-preview
asan: $(OUT)/gfx-preview-asan
	cd $(ROOT) && $(OUT)/gfx-preview-asan
$(OUT)/gfx-preview: $(SOURCES) $(HEADERS) $(GENERATED)
	$(CC) $(CFLAGS) $(SOURCES) -o $@
$(OUT)/gfx-preview-asan: $(SOURCES) $(HEADERS) $(GENERATED)
	$(CC) $(CFLAGS) -g -fsanitize=address -fno-omit-frame-pointer $(SOURCES) -o $@
$(OUT)/generated/atlas.h: $(APP)/tools/atlas_convert.py $(wildcard $(APP)/assets/art/*.png)
	python3 $(APP)/tools/atlas_convert.py
$(OUT)/generated/data.h: $(APP)/tools/data_convert.py $(wildcard $(APP)/data/*.csv)
	python3 $(APP)/tools/data_convert.py
