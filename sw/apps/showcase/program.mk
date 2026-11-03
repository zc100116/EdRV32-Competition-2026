# File: program.mk
# Design: showcase 4.1--4.5; single BIOS-loaded DDR application.
MEMORY := showcase
PROGRAM_SOURCES := sw/apps/showcase/main.c sw/apps/showcase/platform.c sw/apps/showcase/input.c \
    sw/apps/showcase/layers.c $(patsubst $(ROOT)/%,%,$(wildcard $(ROOT)/sw/apps/showcase/board/*.c)) \
    $(patsubst $(ROOT)/%,%,$(wildcard $(ROOT)/sw/apps/showcase/ui/*.c)) \
    sw/lib/sched/sched.c \
    sw/drivers/rnd.c sw/drivers/disp.c sw/drivers/engine.c sw/drivers/plic.c \
    sw/drivers/uart.c sw/drivers/gpio.c sw/drivers/clint.c sw/bsp/cache.c \
    sw/lib/virtual_input.c sw/lib/virtual_input_uart.c sw/lib/virtual_input_irq.c \
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
$(OUT)/obj/third_party/coremark/core_list_join.o: CORE_MAIN_FLAGS := -Wno-maybe-uninitialized
$(addprefix $(ROOT)/,$(SHOWCASE_FONTS) build/showcase/fonts/sim_digits_40.c) &: \
    $(wildcard $(ROOT)/sw/apps/showcase/ui/*.[ch]) $(ROOT)/tools/sw/gen_fonts.py
	python3 $(ROOT)/tools/sw/gen_fonts.py --output-dir $(ROOT)/build/showcase/fonts \
	    --sizes $(SHOWCASE_FONT_SIZES) --digit-sizes 40 -- \
	    $(wildcard $(ROOT)/sw/apps/showcase/ui/*.[ch]) \
	    $(ROOT)/sw/apps/showcase/sim/sim_data.c $(ROOT)/sw/apps/showcase/games/games.txt
