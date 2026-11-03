# File: program.mk
# Design: showcase 4.1--4.5; single BIOS-loaded DDR application.
MEMORY := showcase
PROGRAM_SOURCES := sw/apps/showcase/main.c sw/apps/showcase/platform.c sw/apps/showcase/input.c \
    sw/apps/showcase/layers.c $(patsubst $(ROOT)/%,%,$(wildcard $(ROOT)/sw/apps/showcase/board/*.c)) \
    $(patsubst $(ROOT)/%,%,$(wildcard $(ROOT)/sw/apps/showcase/ui/*.c)) \
    sw/lib/sched/sched.c \
    sw/drivers/rnd.c sw/drivers/disp.c sw/drivers/engine.c sw/drivers/plic.c \
    sw/drivers/uart.c sw/drivers/gpio.c sw/drivers/clint.c sw/bsp/cache.c \
    sw/lib/virtual_input.c sw/lib/virtual_input_irq.c \
    sw/lib/eth_monitor.c sw/lib/eth_monitor_pack.c \
    sw/drivers/eth.c sw/boot/info.c
CFLAGS_EXTRA := -I$(ROOT)/sw/lib -I$(ROOT)/sw/lib/sched -I$(ROOT)/sw/boot \
    -I$(ROOT)/sw/drivers/include -I$(ROOT)/sw/apps/showcase
include $(ROOT)/sw/apps/showcase/lvgl/program.mk
include $(ROOT)/sw/apps/showcase/nes/program.mk

# Shared P2 font subset; generated from exactly the shared UI text.
SHOWCASE_FONT_SIZES := 14 16 20 28 40
SHOWCASE_FONTS := $(addprefix build/showcase/fonts/sim_font_,$(addsuffix .c,$(SHOWCASE_FONT_SIZES)))
PROGRAM_SOURCES += $(SHOWCASE_FONTS) build/showcase/fonts/sim_digits_40.c \
    sw/apps/monitor/benchmark.c sw/apps/coremark/core_portme.c sw/apps/coremark/ee_printf.c \
    $(addprefix third_party/coremark/,core_main.c core_list_join.c core_matrix.c core_state.c core_util.c)
CFLAGS_EXTRA += -I$(ROOT)/sw/apps/coremark -I$(ROOT)/sw/apps/monitor \
    -I$(ROOT)/third_party/coremark -DITERATIONS=5000 -DLV_LVGL_H_INCLUDE_SIMPLE
$(OUT)/obj/third_party/coremark/core_main.o: CORE_MAIN_FLAGS := -Dmain=coremark_main
$(addprefix $(ROOT)/,$(SHOWCASE_FONTS) build/showcase/fonts/sim_digits_40.c) &: \
    $(wildcard $(ROOT)/sw/apps/showcase/ui/*.[ch]) $(ROOT)/sw/apps/showcase/main.c \
    $(ROOT)/tools/sw/gen_fonts.py
	python3 $(ROOT)/tools/sw/gen_fonts.py --output-dir $(ROOT)/build/showcase/fonts \
	    --sizes $(SHOWCASE_FONT_SIZES) --digit-sizes 40 -- \
	    $(wildcard $(ROOT)/sw/apps/showcase/ui/*.[ch]) \
	    $(ROOT)/sw/apps/showcase/main.c $(ROOT)/sw/apps/showcase/sim/sim_data.c \
	    $(ROOT)/sw/apps/showcase/games/games.txt

include $(ROOT)/sw/apps/showcase/board/vision/program.mk
# The pack is regenerated from the local manifest/ROMs/covers for every ELF build.
SHOWCASE_GAME_PACK := $(ROOT)/build/showcase/games.bin
SHOWCASE_GAME_OBJECT := $(ROOT)/build/showcase/games.o
$(SHOWCASE_GAME_PACK): $(ROOT)/tools/sw/game_record.py \
    $(ROOT)/sw/apps/showcase/games/games.txt FORCE
	$(HOME)/.local/opt/edrv32-py/bin/python $(ROOT)/tools/sw/game_record.py pack \
	    $(ROOT)/sw/apps/showcase/games/games.txt $@
$(SHOWCASE_GAME_OBJECT): $(SHOWCASE_GAME_PACK)
	riscv-none-elf-objcopy -I binary -O elf32-littleriscv -B riscv \
	    --rename-section .data=.game_pack,alloc,load,readonly,data,contents $< $@
$(OUT)/showcase.elf: $(SHOWCASE_GAME_OBJECT)
PROGRAM_LDLIBS += $(SHOWCASE_GAME_OBJECT)

# Card 40 g15-tuned: apply only to CoreMark algorithms, port and initialization helper.
SHOWCASE_COREMARK_SOURCES := $(addprefix third_party/coremark/,core_main.c core_list_join.c \
    core_matrix.c core_state.c core_util.c) sw/apps/coremark/core_portme.c \
    sw/apps/monitor/benchmark.c
$(addprefix $(OUT)/obj/,$(SHOWCASE_COREMARK_SOURCES:.c=.o)): CFLAGS += \
    -O3 -funroll-all-loops -finline-limit=600 -falign-functions=4 -falign-jumps=4 \
    -falign-loops=4 -fstrict-aliasing -march=rv32im_zicsr_zifencei
PROGRAM_SOURCES += sw/apps/showcase/board/coremark_stack.S
# Keep the locked upstream list code unchanged; GCC 15 diagnoses its local search key.
$(OUT)/obj/third_party/coremark/core_list_join.o: CORE_MAIN_FLAGS := -Wno-maybe-uninitialized

# P5b 9.1: compiler model, decoded exactly like the PC EDNM uploader.
SHOWCASE_MODEL_DIR := $(ROOT)/tasks/win/20261029-09-b3-software/src/npu
PROGRAM_SOURCES += build/showcase/model.c
$(ROOT)/build/showcase/model.c: $(ROOT)/tools/sw/embed_showcase_model.py \
    $(addprefix $(SHOWCASE_MODEL_DIR)/,mem_desc.hex mem_model.hex regs.txt)
	python3 $< $(SHOWCASE_MODEL_DIR) $@
