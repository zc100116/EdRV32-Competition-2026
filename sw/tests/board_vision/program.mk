# File: program.mk
# Spec: Task B3-7; CLAUDE.md 9.2.
# Description: SRAM application for the vision-only board connectivity test.
# Clock domain: none (build tool).
ARCH := rv32im_zicsr_zifencei
MEMORY := sram
PROGRAM_SOURCES := sw/tests/board_vision/main.c sw/drivers/uart.c sw/drivers/plic.c
CFLAGS_EXTRA := -I$(ROOT)/sw/drivers/include
