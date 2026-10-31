# File: program.mk
# Spec: Task B3-11; SoC 7.5.
# Description: B3F full demo with NPU and RND L1 overlays.
# Clock domain: none (build tool).
include $(ROOT)/sw/apps/demo/common.mk
PROGRAM_SOURCES += $(addprefix sw/apps/demo/,scene_npu.c network_npu.c \
    network_video_npu.c overlay_surface.c \
    overlay_label.c overlay.c) sw/drivers/npu.c sw/drivers/rnd.c \
    sw/lib/yolo_post.c sw/lib/yolo_tables.c
