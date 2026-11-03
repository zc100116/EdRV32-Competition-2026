# Showcase 4.5 host acceptance; no hardware or LVGL dependency.
ROOT := ../../..
BUILD := $(ROOT)/build/sw/tests/showcase
FLAGS := -std=c11 -Wall -Wextra -Werror -I$(ROOT)/sw/apps/showcase/board -I$(ROOT)/sw/lib
.PHONY: test
test:
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
	    gui.c $(ROOT)/sw/apps/showcase/input.c -o $(BUILD)/gui
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
	$(MAKE) -C vision test runtime
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
