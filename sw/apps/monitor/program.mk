# File: program.mk
# Spec: edrv32-soc-spec 7.5; cpu-spec 7.1.
# Description: Build the UART monitor with the existing CoreMark port and upstream algorithms.
# Clock domain: none (build tool).
ARCH := rv32im_zicsr_zifencei
MEMORY := sram
CORE := third_party/coremark
# Board builds raise the iteration count to meet CoreMark's 10 s minimum run time
# and may append the tuned optimisation flags (CoreMark options: CLAUDE.md 9.3).
COREMARK_ITERATIONS ?= 10
MONITOR_OPT_FLAGS ?=
PROGRAM_SOURCES := sw/apps/monitor/benchmark.c sw/apps/monitor/hpm.c \
                   sw/apps/coremark/core_portme.c sw/apps/coremark/ee_printf.c \
                   $(addprefix $(CORE)/,core_main.c core_list_join.c core_matrix.c \
                   core_state.c core_util.c) sw/boot/info.c
CFLAGS_EXTRA := -I$(ROOT)/sw/drivers/include -I$(ROOT)/sw/boot \
                -I$(ROOT)/sw/apps/coremark -I$(ROOT)/$(CORE) \
                -DITERATIONS=$(COREMARK_ITERATIONS) $(MONITOR_OPT_FLAGS)
# Upstream iterate() is reused verbatim; its standalone main is discarded by the linker.
$(OUT)/obj/third_party/coremark/core_main.o: CORE_MAIN_FLAGS := -Dmain=coremark_main
ifeq ($(MONITOR_SPIKE),1)
PROGRAM_SOURCES += sw/apps/monitor/spike.c
else
PROGRAM_SOURCES += sw/apps/monitor/main.c sw/apps/monitor/peripherals.c \
                   sw/drivers/uart.c sw/drivers/gpio.c sw/drivers/clint.c sw/drivers/i2c.c
endif
