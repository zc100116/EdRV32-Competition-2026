# File: Makefile; ember_isles tech 2-6. All products stay in build/ember_isles.
ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../../..)
APP := $(ROOT)/sw/apps/ember_isles
OUT := $(ROOT)/build/ember_isles
CC := gcc
ZIG := $(HOME)/.local/opt/zig-0.17.0/zig
CFLAGS := -std=c11 -O2 -Wall -Wextra -Werror -I$(APP)/src -I$(OUT)/generated \
    -I$(ROOT)/sw/bsp/include -I$(ROOT)/sw/drivers/include -I$(ROOT)/sw/lib \
    -I$(ROOT)/sw/lib/plat -I$(ROOT)/tools/gpu/emu -I$(ROOT)/tools/gpu/emu/pc
MAP := -DEDRV32_SOC_MAP_H -include $(ROOT)/sw/bsp/include/gpu_soc_map.h
FPGA_ART ?= 0
TEXTURE_BYTES ?= 262144
PCFLAGS := -I$(ROOT)/sw/bsp/pc/include $(CFLAGS) $(MAP) -O3 \
    -DGPU_EMU_TEXTURE_BYTES=$(TEXTURE_BYTES) -DEMBER_FPGA_ART=$(FPGA_ART) \
    -include $(ROOT)/sw/bsp/pc/include/mmio.h
DRIVERS := sw/drivers/gpu.c sw/drivers/aud.c sw/drivers/disp.c sw/drivers/plic.c
SOURCES = $(wildcard $(APP)/src/core/*.c $(APP)/src/sim/*.c $(APP)/src/meta/*.c \
    $(APP)/src/gfx2d/*.c $(APP)/src/ui/*.c $(APP)/src/audio/*.c)
PC := sw/lib/plat/pc.c sw/bsp/pc/soc.c sw/bsp/pc/cache.c tools/gpu/emu/gpu_emu.c
BOARD := sw/lib/plat/board.c sw/bsp/start.S sw/bsp/host.c sw/bsp/cache.c \
    sw/drivers/uart.c sw/drivers/gpio.c sw/drivers/clint.c sw/drivers/es8156.c \
    sw/drivers/i2c.c sw/drivers/eth.c sw/lib/virtual_input.c sw/apps/gpu_hello/runtime.c
HEADERS = $(APP)/Makefile $(wildcard $(APP)/src/*.h $(APP)/src/*/*.h $(APP)/src/*/*.inc \
    $(ROOT)/sw/drivers/include/*.h $(ROOT)/sw/drivers/include/regs/*.h \
    $(ROOT)/sw/bsp/include/*.h $(ROOT)/sw/bsp/pc/include/*.h \
    $(ROOT)/sw/lib/plat/*.h $(ROOT)/tools/gpu/emu/*.h $(ROOT)/tools/gpu/emu/pc/*.h)
GEN := $(OUT)/generated/data.h $(OUT)/generated/atlas.h \
    $(OUT)/generated/music.h $(OUT)/generated/replay.h $(OUT)/generated/font.h
.PHONY: all linux windows board spike assets
all: linux windows board spike
linux: $(OUT)/ember_isles
windows: $(OUT)/ember_isles.exe
board: $(OUT)/ember_isles.elf
spike: $(OUT)/ember_isles-spike.elf
assets: $(GEN)
$(OUT)/generated/data.h: $(wildcard $(APP)/data/*.csv) $(APP)/tools/data_convert.py
	python3 $(APP)/tools/data_convert.py
$(OUT)/generated/atlas.h: $(wildcard $(APP)/assets/art_coast/*.json $(APP)/assets/art_coast/*.png $(APP)/tools/art/*.py $(ROOT)/tools/gpu/model/*.py) $(APP)/tools/atlas_convert.py
	python3 $(APP)/tools/art/coast_production.py
	python3 $(APP)/tools/atlas_convert.py
$(OUT)/generated/font.h: $(APP)/tools/font_convert.py $(wildcard $(APP)/assets/fonts/* $(APP)/data/*.csv $(APP)/src/ui/*.[ch] $(APP)/src/gfx2d/*.[ch]) $(APP)/src/game.c
	python3 $(APP)/tools/font_convert.py
$(OUT)/generated/music.h: $(wildcard $(APP)/assets/music/* $(APP)/assets/audio/*) \
    $(APP)/tools/music_convert.py
	python3 $(APP)/tools/music_convert.py
$(OUT)/generated/replay.h: $(wildcard $(APP)/assets/replays/*) $(APP)/tools/replay_convert.py
	python3 $(APP)/tools/replay_convert.py
$(OUT)/ember_isles: $(SOURCES) $(APP)/src/game.c $(APP)/src/headless.c $(GEN) $(HEADERS) \
    $(addprefix $(ROOT)/,$(DRIVERS) $(PC) tools/gpu/emu/pc/png.c)
	mkdir -p $(OUT)
	$(CC) -pthread $(PCFLAGS) $(SOURCES) $(APP)/src/game.c $(APP)/src/headless.c \
	    $(addprefix $(ROOT)/,$(DRIVERS) $(PC) tools/gpu/emu/pc/png.c) -o $@
$(OUT)/ember_isles.exe: $(SOURCES) $(APP)/src/game.c $(APP)/src/windows.c $(GEN) $(HEADERS) \
    $(addprefix $(ROOT)/,$(DRIVERS) $(PC))
	mkdir -p $(OUT)
	$(ZIG) cc -target x86_64-windows-gnu -static $(PCFLAGS) \
	    $(SOURCES) $(APP)/src/game.c $(APP)/src/windows.c \
	    $(addprefix $(ROOT)/,$(DRIVERS) $(PC)) \
	    -lwinmm -lgdi32 -luser32 -o $@
$(OUT)/ember_isles.elf: $(SOURCES) $(APP)/src/game.c $(APP)/src/main.c $(GEN) $(HEADERS) \
    $(addprefix $(ROOT)/,$(DRIVERS) $(BOARD))
	mkdir -p $(OUT)
	$(MAKE) -C $(ROOT)/sw $(ROOT)/build/sw/soc_memory.ld -j1
	cd $(ROOT) && riscv-none-elf-gcc $(CFLAGS) $(MAP) -DEMBER_FPGA_ART=1 -march=rv32im_zicsr -mabi=ilp32 \
	    -ffunction-sections -fdata-sections -nostdlib -Wl,--gc-sections \
	    -Tsw/bsp/ld/ddr.ld $(SOURCES) $(APP)/src/game.c $(APP)/src/main.c \
	    $(addprefix $(ROOT)/,$(DRIVERS) $(BOARD)) -lc -lgcc -o $@
$(OUT)/ember_isles-spike.elf: $(SOURCES) $(APP)/src/spike.c $(GEN) $(HEADERS) \
    $(ROOT)/sw/drivers/gpu.c $(ROOT)/sw/bsp/start.S $(ROOT)/sw/bsp/host.c
	mkdir -p $(OUT)
	$(MAKE) -C $(ROOT)/sw $(ROOT)/build/sw/soc_memory.ld -j1
	cd $(ROOT) && riscv-none-elf-gcc $(CFLAGS) $(MAP) -DEMBER_FPGA_ART=1 -march=rv32im_zicsr_zicntr \
	    -mabi=ilp32 -ffunction-sections -fdata-sections -nostdlib -Wl,--gc-sections \
	    -Tsw/bsp/ld/ddr.ld $(SOURCES) $(APP)/src/spike.c \
	    sw/drivers/gpu.c sw/bsp/start.S sw/bsp/host.c -lc -lgcc -o $@
.PHONY: test
test: $(OUT)/game-flow-test $(OUT)/sim-replay $(OUT)/audio-test $(OUT)/audio-ring-test \
    $(OUT)/pacing-test
	cd $(ROOT) && $(OUT)/game-flow-test
	cd $(ROOT) && $(OUT)/sim-replay --test
	cd $(ROOT) && $(OUT)/audio-test
	cd $(ROOT) && $(OUT)/audio-ring-test
	cd $(ROOT) && $(OUT)/pacing-test
$(OUT)/game-flow-test: $(APP)/tools/game_flow_test.c $(APP)/src/game.c \
    $(APP)/src/sim/sim.c $(APP)/src/sim/combat.c $(APP)/src/core/core.c \
    $(APP)/src/meta/meta.c $(OUT)/generated/data.h $(HEADERS)
	$(CC) $(CFLAGS) $(filter %.c,$^) -o $@
$(OUT)/sim-replay: $(APP)/tools/sim_replay.c $(APP)/src/sim/sim.c \
    $(APP)/src/sim/combat.c $(APP)/src/core/core.c $(APP)/src/core/replay.c $(OUT)/generated/data.h $(HEADERS)
	$(CC) $(CFLAGS) $(filter %.c,$^) -o $@
$(OUT)/audio-test: $(APP)/src/audio/tests/audio_test.c $(APP)/src/audio/audio.c \
    $(OUT)/generated/music.h $(HEADERS)
	$(CC) $(CFLAGS) -I$(APP)/src/audio $(filter %.c,$^) -o $@
$(OUT)/audio-ring-test: $(SOURCES) $(APP)/src/game.c $(APP)/tools/audio_ring_test.c \
    $(GEN) $(HEADERS) $(addprefix $(ROOT)/,$(DRIVERS) $(PC))
	$(CC) -pthread $(PCFLAGS) $(SOURCES) $(APP)/src/game.c $(APP)/tools/audio_ring_test.c \
	    $(addprefix $(ROOT)/,$(DRIVERS) $(PC)) -o $@
$(OUT)/pacing-test: $(SOURCES) $(APP)/src/game.c $(GEN) $(HEADERS) \
    $(ROOT)/tools/gpu/emu/pc/ember_pacing_test.c $(addprefix $(ROOT)/,$(DRIVERS) $(PC))
	$(CC) -pthread $(PCFLAGS) $(SOURCES) $(APP)/src/game.c \
	    $(ROOT)/tools/gpu/emu/pc/ember_pacing_test.c $(addprefix $(ROOT)/,$(DRIVERS) $(PC)) \
	    -Wl,--wrap=ember_gfx_prepare -Wl,--wrap=ember_gfx_submit -o $@

.PHONY: e5a-grid e5a-stress
e5a-grid: $(OUT)/e5a-grid-test
	$(OUT)/e5a-grid-test
e5a-stress: $(OUT)/e5a-stress
	$(OUT)/e5a-stress > $(OUT)/e5a-stress.csv
$(OUT)/e5a-grid-test: $(APP)/tools/e5a_grid_test.c $(APP)/src/sim/sim.c \
    $(APP)/src/sim/combat.c $(APP)/src/core/core.c $(OUT)/generated/data.h $(HEADERS)
	$(CC) $(CFLAGS) $(APP)/tools/e5a_grid_test.c $(APP)/src/sim/combat.c \
	    $(APP)/src/core/core.c -o $@
$(OUT)/e5a-stress: $(APP)/tools/e5a_stress.c $(APP)/src/sim/sim.c \
    $(APP)/src/sim/combat.c $(APP)/src/core/core.c $(OUT)/generated/data.h $(HEADERS)
	$(CC) $(CFLAGS) $(APP)/tools/e5a_stress.c $(APP)/src/sim/sim.c $(APP)/src/sim/combat.c \
	    $(APP)/src/core/core.c -o $@
$(OUT)/e5a-stress-profile: $(APP)/tools/e5a_stress.c $(APP)/src/sim/sim.c \
    $(APP)/src/sim/combat.c $(APP)/src/core/core.c $(OUT)/generated/data.h $(HEADERS)
	$(CC) $(CFLAGS) -pg $(APP)/tools/e5a_stress.c $(APP)/src/sim/sim.c $(APP)/src/sim/combat.c \
	    $(APP)/src/core/core.c -o $@

$(OUT)/ember_isles-stress-spike.elf: $(SOURCES) $(APP)/src/spike.c $(GEN) $(HEADERS) \
    $(ROOT)/sw/drivers/gpu.c $(ROOT)/sw/bsp/start.S $(ROOT)/sw/bsp/host.c
	$(MAKE) -C $(ROOT)/sw $(ROOT)/build/sw/soc_memory.ld -j1
	cd $(ROOT) && riscv-none-elf-gcc $(CFLAGS) $(MAP) -DEMBER_FPGA_ART=1 -DEMBER_STRESS_DIAGNOSTIC \
	    -march=rv32im_zicsr_zicntr -mabi=ilp32 -ffunction-sections -fdata-sections \
	    -nostdlib -Wl,--gc-sections -Tsw/bsp/ld/ddr.ld \
	    $(SOURCES) $(APP)/src/spike.c sw/drivers/gpu.c sw/bsp/start.S sw/bsp/host.c \
	    -lc -lgcc -o $@
.PHONY: e5a-upgrade
e5a-upgrade: $(OUT)/e5a-upgrade-test
	$(OUT)/e5a-upgrade-test
$(OUT)/e5a-upgrade-test: $(APP)/tools/e5a_upgrade_test.c $(APP)/src/sim/sim.c \
    $(APP)/src/sim/combat.c $(APP)/src/core/core.c $(OUT)/generated/data.h $(HEADERS)
	$(CC) $(CFLAGS) $(APP)/tools/e5a_upgrade_test.c $(APP)/src/sim/combat.c \
	    $(APP)/src/core/core.c -o $@
$(OUT)/e5a-replay: $(APP)/tools/e5a_replay.c $(APP)/src/sim/sim.c \
    $(APP)/src/sim/combat.c $(APP)/src/core/core.c $(APP)/src/core/replay.c \
    $(OUT)/generated/data.h $(HEADERS)
	$(CC) $(CFLAGS) $(filter %.c,$^) -o $@
$(OUT)/e5a-content-test: $(APP)/tools/e5a_content_test.c $(APP)/src/sim/sim.c \
    $(APP)/src/sim/combat.c $(APP)/src/core/core.c $(APP)/src/meta/meta.c \
    $(OUT)/generated/data.h $(HEADERS)
	$(CC) $(CFLAGS) $(APP)/tools/e5a_content_test.c $(APP)/src/sim/combat.c \
	    $(APP)/src/core/core.c $(APP)/src/meta/meta.c -o $@
$(OUT)/e4-content-test: $(APP)/tools/e4_content_test.c $(APP)/src/sim/sim.c \
    $(APP)/src/sim/combat.c $(APP)/src/core/core.c $(OUT)/generated/data.h $(HEADERS)
	$(CC) $(CFLAGS) $(APP)/tools/e4_content_test.c $(APP)/src/sim/combat.c \
	    $(APP)/src/core/core.c -o $@
$(OUT)/e5a-coast-test: $(APP)/tools/e5a_coast_test.c $(APP)/src/sim/sim.c \
    $(APP)/src/sim/combat.c $(APP)/src/core/core.c $(OUT)/generated/data.h $(HEADERS)
	$(CC) $(CFLAGS) $(APP)/tools/e5a_coast_test.c $(APP)/src/sim/combat.c \
	    $(APP)/src/core/core.c -o $@

$(OUT)/v1-accept: $(SOURCES) $(APP)/src/game.c $(APP)/src/gfx2d/tests/v1_accept.c $(GEN) $(HEADERS) \
    $(addprefix $(ROOT)/,$(DRIVERS) $(PC) tools/gpu/emu/pc/png.c)
	$(CC) -pthread $(PCFLAGS) $(SOURCES) $(APP)/src/game.c $(APP)/src/gfx2d/tests/v1_accept.c \
	    $(addprefix $(ROOT)/,$(DRIVERS) $(PC) tools/gpu/emu/pc/png.c) -o $@

FPGA_PCFLAGS = $(filter-out -DGPU_EMU_TEXTURE_BYTES=% -DEMBER_FPGA_ART=%,$(PCFLAGS)) \
    -DGPU_EMU_TEXTURE_BYTES=196608 -DEMBER_FPGA_ART=1
.PHONY: linux-fpga
linux-fpga: $(OUT)/ember_isles-fpga
$(OUT)/ember_isles-fpga: $(SOURCES) $(APP)/src/game.c $(APP)/src/headless.c $(GEN) $(HEADERS) \
    $(addprefix $(ROOT)/,$(DRIVERS) $(PC) tools/gpu/emu/pc/png.c)
	$(CC) -pthread $(FPGA_PCFLAGS) $(SOURCES) $(APP)/src/game.c $(APP)/src/headless.c \
	    $(addprefix $(ROOT)/,$(DRIVERS) $(PC) tools/gpu/emu/pc/png.c) -o $@
$(OUT)/v1-accept-fpga: $(SOURCES) $(APP)/src/game.c $(APP)/src/gfx2d/tests/v1_accept.c $(GEN) $(HEADERS) \
    $(addprefix $(ROOT)/,$(DRIVERS) $(PC) tools/gpu/emu/pc/png.c)
	$(CC) -pthread $(FPGA_PCFLAGS) $(SOURCES) $(APP)/src/game.c $(APP)/src/gfx2d/tests/v1_accept.c \
	    $(addprefix $(ROOT)/,$(DRIVERS) $(PC) tools/gpu/emu/pc/png.c) -o $@

$(OUT)/v1-particles-test: $(SOURCES) $(APP)/src/gfx2d/tests/particles_test.c $(GEN) $(HEADERS) \
    $(addprefix $(ROOT)/,$(DRIVERS) $(PC))
	$(CC) -pthread $(PCFLAGS) $(filter-out $(APP)/src/gfx2d/particles.c,$(SOURCES)) \
	    $(APP)/src/gfx2d/tests/particles_test.c $(addprefix $(ROOT)/,$(DRIVERS) $(PC)) -o $@

$(OUT)/v1-ui-test: $(APP)/src/gfx2d/tests/ui_test.c $(APP)/src/ui/ui.c $(APP)/src/ui/font.c \
    $(APP)/src/sim/sim.c $(APP)/src/sim/combat.c $(APP)/src/core/core.c \
    $(APP)/src/core/replay.c $(APP)/src/meta/meta.c $(ROOT)/sw/drivers/gpu.c \
    $(OUT)/generated/data.h $(OUT)/generated/font.h $(HEADERS)
	$(CC) $(PCFLAGS) -ffunction-sections -fdata-sections -Wl,--gc-sections $(filter %.c,$^) -o $@
