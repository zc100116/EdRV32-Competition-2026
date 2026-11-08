# program.mk — npu-testplan 3.10; software and oracle preparation for PP-SW.
MEMORY := sram
ARCH := rv32im_zicsr
PROGRAM_SOURCES := sw/tests/$(PROGRAM)/main.c sw/drivers/npu.c sw/drivers/engine.c \
    sw/drivers/plic.c sw/drivers/uart.c sw/bsp/cache.c sw/lib/yolo_post.c \
    sw/apps/showcase/board/vision/wire.c
CFLAGS_EXTRA := -I$(ROOT)/sw/drivers/include -I$(ROOT)/sw/lib \
    -I$(ROOT)/sw/apps/showcase/board/vision -I$(ROOT)/sw/tests/npu_post -I$(ROOT)/build/npu/post_sw/data
$(ROOT)/build/npu/post_sw/data/data.h: $(ROOT)/sw/tests/npu_post/prepare.py \
    $(ROOT)/tools/npu/yolo_post_ref.py $(ROOT)/sw/lib/yolo_tables.json \
    $(ROOT)/build/sw/board_npu/data/C-YOLO/ref_out.hex
	python3 $<
$(OUT)/obj/sw/tests/$(PROGRAM)/main.o: $(ROOT)/build/npu/post_sw/data/data.h

PROGRAM_SOURCES += sw/apps/showcase/ui/detection.c
CFLAGS_EXTRA += -I$(ROOT)/sw/apps/showcase/ui -I$(ROOT)/third_party/lvgl \
    -I$(ROOT)/sw/apps/showcase/lvgl -DLV_CONF_INCLUDE_SIMPLE
PROGRAM_LDLIBS := -lc

$(ROOT)/build/sw/board_npu/data/C-YOLO/ref_out.hex:
	$(MAKE) -C $(ROOT)/sw PROGRAM=board_npu -j 1
