# Showcase 4.5.2; host numerical equivalence, all artifacts under build/.
ROOT := $(abspath ../../../..)
OUT := $(ROOT)/build/sw/showcase/vision
VISION := $(ROOT)/sw/apps/showcase/board/vision
CC := gcc
LVGL_ROOT ?= $(ROOT)/third_party/lvgl
UI_CONTRACT ?= $(ROOT)/sw/apps/showcase/ui/ui_data.h
CFLAGS := -std=c11 -O2 -g -Wall -Wextra -Werror -fsanitize=undefined \
    -fno-sanitize-recover=all -I$(VISION) -I$(ROOT)/sw/lib \
    -I$(ROOT)/sw/apps/showcase/board
.PHONY: test cpu
test:
	mkdir -p $(OUT)
	$(CC) $(CFLAGS) post_test.c $(VISION)/post.c $(VISION)/wire.c \
	    $(ROOT)/sw/lib/yolo_post.c $(ROOT)/sw/lib/yolo_tables.c -o $(OUT)/post_test
	$(OUT)/post_test

cpu:
	$(MAKE) test OUT=$(ROOT)/build/sw/showcase-cpupost/vision \
	    CFLAGS='$(CFLAGS) -DSHOWCASE_POST_CPU'

RUNTIME_TEST ?= runtime_test
.PHONY: runtime network
network:
	$(MAKE) runtime RUNTIME_TEST=network_test EXTRA_FLAGS=-DNETWORK_INTEGRATION
runtime: $(ROOT)/build/showcase/model.c
	mkdir -p $(OUT)
	$(CC) $(CFLAGS) $(EXTRA_FLAGS) -DLV_CONF_INCLUDE_SIMPLE -I$(LVGL_ROOT) \
	    -I$(ROOT)/sw/apps/showcase/lvgl -I$(ROOT)/sw/apps/showcase -I$(ROOT)/sw/bsp/include \
	    -I$(ROOT)/sw/drivers/include -I$(ROOT)/sw/lib/sched -I. \
	    -include $(UI_CONTRACT) $(RUNTIME_TEST).c pipe_stubs.c 	    $(VISION)/pipeline.c $(VISION)/pipeline_exec.c $(VISION)/vision.c $(VISION)/post.c \
	    $(VISION)/wire.c $(ROOT)/sw/lib/yolo_tables.c $(ROOT)/sw/drivers/rnd.c \
	    $(ROOT)/sw/apps/showcase/ui/detection.c $(ROOT)/sw/lib/geo_matrix.c \
	    $(ROOT)/build/showcase/model.c $(ROOT)/sw/apps/showcase/board/session.c \
	    $(ROOT)/sw/apps/showcase/board/protocol.c $(ROOT)/sw/apps/showcase/board/records.c \
	    $(ROOT)/sw/apps/showcase/board/state.c -lm \
	    -ffunction-sections -fdata-sections -Wl,--gc-sections -o $(OUT)/$(RUNTIME_TEST)
	$(OUT)/$(RUNTIME_TEST)

SHOWCASE_MODEL_SOURCE := $(ROOT)/tasks/win/20261029-09-b3-software/src/npu
SHOWCASE_MODEL_DIR := $(ROOT)/build/npu/software_model
$(ROOT)/build/showcase/model.c: $(ROOT)/tools/sw/embed_showcase_model.py \
    $(wildcard $(ROOT)/tools/npu/*.py) \
    $(addprefix $(SHOWCASE_MODEL_SOURCE)/,mem_model.hex quantization.json)
	python3 $(ROOT)/tools/npu/compile_yolo.py --model-source $(SHOWCASE_MODEL_SOURCE) \
	    --out $(SHOWCASE_MODEL_DIR)
	python3 $(ROOT)/tools/sw/embed_showcase_model.py $(SHOWCASE_MODEL_DIR) $@
