# G-4 deterministic game-state checks; no RTL/SoC simulation.
ROOT := $(abspath ../../..)
OUT := $(ROOT)/build/gpu_test/generated
CFLAGS := -std=c11 -O2 -Wall -Wextra -Werror -ffunction-sections -fdata-sections \
    -I$(OUT) -I$(ROOT)/sw/apps/gpu_test_common -I$(ROOT)/sw/apps/gpu_test_rogue \
    -I$(ROOT)/sw/drivers/include -I$(ROOT)/sw/bsp/include -I$(ROOT)/sw/lib/plat
.PHONY: assets state-test
assets: $(OUT)/rogue_assets.h
$(OUT)/rogue_assets.h: tools/assets.py assets/actors.png assets/dungeon.png assets/hud.bdf \
    $(ROOT)/sw/apps/gpu_test_common/tools/art.py \
    $(ROOT)/sw/apps/gpu_test_common/assets/palette.json
	python3 tools/assets.py $@
state-test: assets
	mkdir -p $(ROOT)/build/g4
	$(CC) $(CFLAGS) -Wl,--gc-sections tools/state_test.c -o $(ROOT)/build/g4/state_test
	$(ROOT)/build/g4/state_test
