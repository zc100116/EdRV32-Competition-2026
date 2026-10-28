# File: program.mk
# Spec: sys-subsys-plan S-W1; edrv32-soc-spec 7.5
# Description: Select ROM startup and bootloader sources.
# Clock domain: none (build tool).
# ROM-only startup uses SRAM solely for its stack, preserving the preloaded app.
ARCH := rv32im_zicsr_zifencei
MEMORY := rom
PROGRAM_BSP := sw/boot/start.S
PROGRAM_SOURCES := sw/boot/main.c sw/boot/info.c sw/boot/enter.S sw/drivers/uart.c \
                   sw/drivers/gpio.c
CFLAGS_EXTRA := -I$(ROOT)/sw/drivers/include -I$(ROOT)/sw/boot
