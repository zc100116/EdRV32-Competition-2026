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
.PHONY: test
test:
	mkdir -p $(OUT)
	$(CC) $(CFLAGS) post_test.c $(VISION)/post.c $(VISION)/wire.c \
	    $(ROOT)/sw/lib/yolo_post.c $(ROOT)/sw/lib/yolo_tables.c -o $(OUT)/post_test
	$(OUT)/post_test

.PHONY: runtime
runtime:
	mkdir -p $(OUT)
	$(CC) $(CFLAGS) -DLV_CONF_INCLUDE_SIMPLE -I$(LVGL_ROOT) \
	    -I$(ROOT)/sw/apps/showcase/lvgl -I$(ROOT)/sw/bsp/include \
	    -I$(ROOT)/sw/drivers/include -I$(ROOT)/sw/lib/sched -I. \
	    -include $(UI_CONTRACT) runtime_test.c $(VISION)/vision.c $(VISION)/post.c \
	    $(VISION)/wire.c $(ROOT)/sw/lib/yolo_tables.c \
	    $(ROOT)/sw/apps/showcase/ui/detection.c $(ROOT)/sw/lib/geo_matrix.c -lm \
	    -o $(OUT)/runtime_test
	$(OUT)/runtime_test
