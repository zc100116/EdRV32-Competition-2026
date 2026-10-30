# File: program.mk
# Spec: Task T-BN1; CLAUDE.md 9.2.
# Description: SRAM application using the generated minimal NPU CONV reference.
# Clock domain: none (build tool).
ARCH := rv32im_zicsr_zifencei
MEMORY := sram
PROGRAM_SOURCES := sw/tests/board_npu_smoke/main.c sw/drivers/uart.c sw/drivers/plic.c
CFLAGS_EXTRA := -I$(ROOT)/sw/drivers/include -I$(ROOT)/build/board_npu
