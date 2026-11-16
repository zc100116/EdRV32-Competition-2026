# Showcase 4.5 host acceptance; no hardware or LVGL dependency.
ROOT := ../../..
BUILD := $(ROOT)/build/sw/tests/showcase
FLAGS := -std=c11 -Wall -Wextra -Werror -I$(ROOT)/sw/apps/showcase/board -I$(ROOT)/sw/lib
.PHONY: test
test: grab
	mkdir -p $(BUILD)
	$(CC) $(FLAGS) main.c $(ROOT)/sw/apps/showcase/board/records.c \
	    $(ROOT)/sw/apps/showcase/board/protocol.c $(ROOT)/sw/lib/virtual_input.c -o $(BUILD)/protocol
	$(BUILD)/protocol
	$(CC) $(FLAGS) -I$(ROOT)/sw/lib/sched sched.c $(ROOT)/sw/lib/sched/sched.c -o $(BUILD)/sched
	$(BUILD)/sched
	$(CC) $(FLAGS) -I$(ROOT)/third_party/lvgl -I$(ROOT)/sw/apps/showcase/lvgl \
	    -I$(ROOT)/sw/apps/showcase/ui -DLV_CONF_INCLUDE_SIMPLE \
	    filter.c $(ROOT)/sw/apps/showcase/ui/detection.c -o $(BUILD)/filter
	$(BUILD)/filter

	$(CC) $(FLAGS) -ffunction-sections -fdata-sections -Wl,--gc-sections \
	    -I$(ROOT)/third_party/lvgl -I$(ROOT)/sw/apps/showcase/lvgl \
	    -I$(ROOT)/sw/apps/showcase -I$(ROOT)/sw/drivers/include \
	    -I$(ROOT)/sw/bsp/include -I$(ROOT)/sw/lib/sched -DLV_CONF_INCLUDE_SIMPLE \
	    sync.c $(ROOT)/sw/apps/showcase/input.c -o $(BUILD)/gui
	$(BUILD)/gui
	$(CC) $(FLAGS) -I$(ROOT)/sw/apps/showcase/ui hpm.c -o $(BUILD)/hpm
	$(BUILD)/hpm

	$(CC) $(FLAGS) -ffunction-sections -fdata-sections -Wl,--gc-sections \
	    -I$(ROOT)/sw/apps/showcase/nes \
	    -I$(ROOT)/third_party/nofrendo/components/nofrendo \
	    -I$(ROOT)/third_party/nofrendo/components/nofrendo/nes \
	    -I$(ROOT)/third_party/nofrendo/components/nofrendo/sndhrdw \
	    -I$(ROOT)/third_party/nofrendo/components/nofrendo/libsnss \
	    -I$(ROOT)/third_party/nofrendo/components/nofrendo/cpu \
	    nes_input.c $(ROOT)/sw/apps/showcase/nes/port.c -o $(BUILD)/nes_input
	$(BUILD)/nes_input
	$(CC) $(FLAGS) -ffunction-sections -fdata-sections -Wl,--gc-sections \
	    -I$(ROOT)/third_party/lvgl -I$(ROOT)/sw/apps/showcase/lvgl \
	    -I$(ROOT)/sw/bsp/include -I$(ROOT)/sw/drivers/include \
	    -DLV_CONF_INCLUDE_SIMPLE nes_lifecycle.c -o $(BUILD)/nes_lifecycle
	$(BUILD)/nes_lifecycle
	$(CC) $(FLAGS) -I$(ROOT)/sw/apps/showcase input.c \
	    $(ROOT)/sw/apps/showcase/input.c -o $(BUILD)/input
	$(BUILD)/input
	$(CC) $(FLAGS) -I$(ROOT)/third_party/lvgl -I$(ROOT)/sw/apps/showcase/lvgl \
	    -DLV_CONF_INCLUDE_SIMPLE session.c $(ROOT)/sw/apps/showcase/board/session.c \
	    -o $(BUILD)/session
	$(BUILD)/session
	$(CC) $(FLAGS) -I$(ROOT)/third_party/lvgl -I$(ROOT)/sw/apps/showcase/lvgl \
	    -DLV_CONF_INCLUDE_SIMPLE state.c $(ROOT)/sw/apps/showcase/board/state.c \
	    $(ROOT)/sw/apps/showcase/board/records.c -o $(BUILD)/state
	$(BUILD)/state
	$(MAKE) -C vision test runtime network
	$(CC) $(FLAGS) -I$(ROOT)/sw/apps/showcase -I$(ROOT)/sw/bsp/include \
	    -I$(ROOT)/sw/drivers/include serial.c $(ROOT)/sw/apps/showcase/board/serial.c \
	    -o $(BUILD)/serial
	$(BUILD)/serial
	$(CC) $(FLAGS) -ffunction-sections -fdata-sections -Wl,--gc-sections \
	    -I$(ROOT)/third_party/lvgl -I$(ROOT)/sw/apps/showcase/lvgl \
	    -I$(ROOT)/sw/apps/showcase -I$(ROOT)/sw/bsp/include -I$(ROOT)/sw/drivers/include \
	    -DLV_CONF_INCLUDE_SIMPLE clear.c $(ROOT)/sw/apps/showcase/lvgl/draw_rnd.c \
	    $(ROOT)/sw/drivers/rnd.c $(ROOT)/third_party/lvgl/src/misc/lv_area.c \
	    $(ROOT)/third_party/lvgl/src/misc/lv_color.c -Wl,--wrap=rnd_read_perf -o $(BUILD)/clear
	$(BUILD)/clear
	$(CC) $(FLAGS) -I$(ROOT)/sw/bsp/include -I$(ROOT)/sw/drivers/include \
	    fabric.c $(ROOT)/sw/apps/showcase/board/fabric.c -o $(BUILD)/fabric
	$(BUILD)/fabric

.PHONY: grab
grab:
	mkdir -p $(BUILD)
	$(CC) $(FLAGS) -I$(ROOT)/third_party/lvgl -I$(ROOT)/sw/apps/showcase/lvgl \
	    -I$(ROOT)/sw/apps/showcase/ui -DLV_CONF_INCLUDE_SIMPLE \
	    grab.c $(ROOT)/sw/apps/showcase/ui/grab.c $(ROOT)/sw/apps/showcase/ui/gesture.c \
	    -lm -o $(BUILD)/grab
	$(BUILD)/grab

.PHONY: sling
sling:
	mkdir -p $(BUILD)
	$(CC) $(FLAGS) -I$(ROOT)/sw/apps/showcase/ui \
	    sling.c $(ROOT)/sw/apps/showcase/ui/sling.c -o $(BUILD)/sling
	$(BUILD)/sling

.PHONY: sticker
sticker:
	mkdir -p $(BUILD)
	$(CC) $(FLAGS) -I$(ROOT)/sw/apps/showcase/ui sticker.c \
	    $(ROOT)/sw/apps/showcase/ui/sticker.c -o $(BUILD)/sticker
	$(BUILD)/sticker
	python3 sticker_alpha.py

# T-GAMES-MORE: pure C rules, no camera, LVGL or simulator dependency.
GAME_UI := $(ROOT)/sw/apps/showcase/ui
GAME_RULES := $(addprefix $(GAME_UI)/,game_math.c rps.c mole.c slice.c catch.c motion.c sling.c)
.PHONY: games rps mole slice catch lobby
games: rps mole slice catch lobby
rps mole slice catch:
	mkdir -p $(BUILD)
	$(CC) $(FLAGS) -I$(GAME_UI) $@.c $(GAME_UI)/$@.c $(GAME_UI)/game_math.c -o $(BUILD)/$@
	$(BUILD)/$@
lobby:
	mkdir -p $(BUILD)
	$(CC) $(FLAGS) -I$(GAME_UI) motion.c $(GAME_RULES) -o $(BUILD)/lobby
	$(BUILD)/lobby

.PHONY: sync
sync:
	mkdir -p $(BUILD)
	$(CC) $(FLAGS) -ffunction-sections -fdata-sections -Wl,--gc-sections \
	    -I$(ROOT)/third_party/lvgl -I$(ROOT)/sw/apps/showcase/lvgl \
	    -I$(ROOT)/sw/apps/showcase -I$(ROOT)/sw/drivers/include \
	    -I$(ROOT)/sw/bsp/include -I$(ROOT)/sw/lib/sched -DLV_CONF_INCLUDE_SIMPLE \
	    sync.c $(ROOT)/sw/apps/showcase/input.c -o $(BUILD)/sync
	$(BUILD)/sync
	$(CC) $(FLAGS) -I$(ROOT)/third_party/lvgl -I$(ROOT)/sw/apps/showcase/lvgl \
	    -DLV_CONF_INCLUDE_SIMPLE session.c $(ROOT)/sw/apps/showcase/board/session.c \
	    -o $(BUILD)/session
	$(BUILD)/session
	$(MAKE) -C vision runtime

# T-TOWER-PHYS: no LVGL or hardware; one build/run at a time.
.PHONY: phys phys-perf
phys:
	mkdir -p $(BUILD)
	$(CC) $(FLAGS) -O2 -I$(GAME_UI) phys.c $(GAME_UI)/phys.c -lm -o $(BUILD)/phys
	$(BUILD)/phys > $(BUILD)/phys.log
	cat $(BUILD)/phys.log
phys-perf:
	mkdir -p $(BUILD)
	bash -c '. ~/.local/opt/edrv32/env.sh && riscv-none-elf-gcc \
	    -march=rv32im -mabi=ilp32 -O2 -std=c11 -Wall -Wextra -Werror \
	    -DPHYS_PERF -I$(GAME_UI) -I$(ROOT)/sw/bsp/include -nostdlib \
	    -T$(ROOT)/tools/cpu/eval/workloads/spike.ld \
	    $(ROOT)/tools/cpu/eval/workloads/start.S phys.c $(GAME_UI)/phys.c \
	    $(ROOT)/sw/bsp/host.c -lc -lgcc -o $(BUILD)/phys-perf.elf && \
	    spike --isa=rv32im_zicsr_zicntr --disable-dtb $(BUILD)/phys-perf.elf' \
	    > $(BUILD)/phys-perf.log 2>&1
	cat $(BUILD)/phys-perf.log

.PHONY: tower
tower:
	mkdir -p $(BUILD)
	$(CC) $(FLAGS) -O2 -I$(GAME_UI) -I$(ROOT)/sw/drivers/include \
	    -I$(ROOT)/sw/bsp/include -ffunction-sections -Wl,--gc-sections \
	    tower.c tower_geo.c $(GAME_UI)/tower.c \
	    $(GAME_UI)/phys.c $(GAME_UI)/sprite_rot.c $(ROOT)/sw/drivers/geo.c -o $(BUILD)/tower
	python3 tower_art.py $(BUILD)/tower-art.bin
	$(BUILD)/tower $(BUILD)/tower-art.bin
	$(CC) $(FLAGS) -O2 -I$(GAME_UI) -I$(ROOT)/sw/lib/sched \
	    -I$(ROOT)/third_party/lvgl -I$(ROOT)/sw/apps/showcase/lvgl \
	    -I$(ROOT)/sw/drivers/include -I$(ROOT)/sw/bsp/include -DLV_CONF_INCLUDE_SIMPLE \
	    tower_loop.c $(GAME_UI)/game_loop.c -o $(BUILD)/tower_loop
	$(BUILD)/tower_loop
