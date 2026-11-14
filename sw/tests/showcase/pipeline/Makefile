# PIPE-SPEC 7.1/7.4 host acceptance; no device or simulation dependency.
ROOT := $(abspath ../../../..)
OUT := $(ROOT)/build/sw/tests/showcase/pipeline
VISION := $(ROOT)/sw/apps/showcase/board/vision
FLAGS := -std=c11 -O2 -g -Wall -Wextra -Werror -fsanitize=undefined \
    -fno-sanitize-recover=all -DLV_CONF_INCLUDE_SIMPLE -I$(ROOT)/third_party/lvgl \
    -I$(ROOT)/sw/apps/showcase/lvgl -I$(VISION)
.PHONY: test
test:
	mkdir -p $(OUT)
	$(CC) $(FLAGS) compiler.c $(VISION)/pipeline.c -o $(OUT)/compiler
	$(OUT)/compiler
	$(CC) $(FLAGS) -I$(ROOT)/sw/bsp/include -I$(ROOT)/sw/drivers/include \
	    -I$(ROOT)/sw/lib -I$(ROOT)/sw/lib/sched -I$(ROOT)/sw/apps/showcase \
	    -ffunction-sections -fdata-sections -Wl,--gc-sections runtime.c \
	    $(VISION)/pipeline.c $(ROOT)/sw/lib/geo_matrix.c $(ROOT)/sw/drivers/rnd.c \
	    -lm -o $(OUT)/runtime
	$(OUT)/runtime
