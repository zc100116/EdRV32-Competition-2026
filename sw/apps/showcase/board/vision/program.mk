# showcase design 4.5; include from the BOARD showcase build.
PROGRAM_SOURCES += $(addprefix sw/apps/showcase/board/vision/,vision.c post.c wire.c) \
    sw/lib/yolo_tables.c sw/lib/geo_matrix.c \
    $(addprefix sw/drivers/,vin.c npu.c pix.c geo.c ov5640.c i2c.c)
CFLAGS_EXTRA += -I$(ROOT)/sw/apps/showcase/board -I$(ROOT)/sw/apps/showcase/board/vision

PROGRAM_LDLIBS += -lm
