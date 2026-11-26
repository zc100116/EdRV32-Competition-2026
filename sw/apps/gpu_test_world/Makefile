# G-4 terrain and exploration checks; shared scene interface lives in rogue/demo.h.
ROOT := $(abspath ../../..)
OUT := $(ROOT)/build/gpu_test/generated
CFLAGS := -std=c11 -O2 -Wall -Wextra -Werror -ffunction-sections -fdata-sections \
    -I$(OUT) -I$(ROOT)/sw/apps/gpu_test_common -I$(ROOT)/sw/apps/gpu_test_rogue \
    -I$(ROOT)/sw/drivers/include -I$(ROOT)/sw/bsp/include -I$(ROOT)/sw/lib/plat
.PHONY: assets state-test
assets: $(OUT)/world_assets.h
$(OUT)/world_assets.h: tools/assets.py assets/terrain.png \
    $(ROOT)/sw/apps/gpu_test_common/tools/art.py \
    $(ROOT)/sw/apps/gpu_test_common/assets/palette.json
	python3 tools/assets.py $@
state-test: assets
	$(MAKE) -C ../gpu_test_rogue assets
	mkdir -p $(ROOT)/build/g4
	$(CC) $(CFLAGS) -Wl,--gc-sections tools/state_test.c -o $(ROOT)/build/g4/world_state_test
	$(ROOT)/build/g4/world_state_test
