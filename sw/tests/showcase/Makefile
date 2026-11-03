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
