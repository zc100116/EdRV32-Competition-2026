# File: program.mk
# Spec: Task B3-11; SoC 7.5.
# Description: B3V S2-only demo without NPU or RND.
# Clock domain: none (build tool).
include $(ROOT)/sw/apps/demo/common.mk
PROGRAM_SOURCES += $(addprefix sw/apps/demo/,scene_vision.c)
