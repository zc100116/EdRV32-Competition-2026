# File: program.mk
# Spec: CLAUDE.md 9.2/9.3; design/2026-10-30-board-npu-test section 4.
# Description: Link the DDR board checker and generated read-only NPU images.
# Clock domain: none (build tool).
ARCH := rv32im_zicsr_zifencei
MEMORY := ddr
PROGRAM_SOURCES := sw/tests/board_npu/main.c sw/drivers/npu.c sw/drivers/uart.c \
    sw/drivers/gpio.c sw/bsp/cache.c
CFLAGS_EXTRA := -I$(ROOT)/sw/drivers/include -I$(OUT)/data
PROGRAM_LDLIBS := $(OUT)/data/cases.o
BOARD_PYTHON := $(HOME)/.local/opt/edrv32-py/bin/python
BOARD_GENERATORS := $(wildcard $(ROOT)/tools/npu/*.py $(ROOT)/tools/npu/ref/*.py) \
    $(ROOT)/verif/block/npu/cases.py $(ROOT)/verif/block/npu/prepare.py

$(OUT)/data/board_data.h $(OUT)/data/cases.o &: $(BOARD_GENERATORS)
	cd $(ROOT) && $(BOARD_PYTHON) tools/npu/board_cases.py

$(OUT)/obj/sw/tests/board_npu/main.o: $(OUT)/data/board_data.h
$(OUT)/$(PROGRAM).elf: $(OUT)/data/cases.o
