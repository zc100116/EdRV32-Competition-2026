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
	    gui.c -o $(BUILD)/gui
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
	$(CC) $(FLAGS) -I$(ROOT)/sw/bsp/include -I$(ROOT)/sw/drivers/include \
	    -include $(ROOT)/sw/apps/nes/tests/input_mmio.h uart_input.c \
	    $(ROOT)/sw/lib/virtual_input.c $(ROOT)/sw/lib/virtual_input_uart.c -o $(BUILD)/uart_input
	$(BUILD)/uart_input
