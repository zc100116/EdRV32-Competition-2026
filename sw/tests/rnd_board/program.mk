# File: program.mk
# Spec: Task B3-3a; DDR application execution.
# Description: Build scene data into build/ and link the board checker in DDR.
# Clock domain: none (build tool).
MEMORY := ddr_app
PROGRAM_SOURCES := sw/tests/rnd_board/main.c sw/drivers/rnd.c sw/drivers/disp.c \
    sw/drivers/engine.c sw/drivers/plic.c sw/drivers/uart.c sw/bsp/cache.c
CFLAGS_EXTRA := -I$(ROOT)/sw/drivers/include -I$(OUT)
$(OUT)/scenes.h: $(ROOT)/sw/tests/rnd_board/scenes.py
	python3 $< --header $@
$(OUT)/obj/sw/tests/rnd_board/main.o: $(OUT)/scenes.h
