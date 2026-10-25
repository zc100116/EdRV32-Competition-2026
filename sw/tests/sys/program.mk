# File: program.mk
# Spec: sys-subsys-testplan 3.6
# Description: Select SRAM startup and system test sources.
# Clock domain: none (build tool).
# SC applications enter at SRAM base; BSP handles application data and BSS.
ARCH := -march=rv32imc_zicsr_zifencei -mabi=ilp32
MEMORY := sram
PROGRAM_SOURCES := sw/tests/sys/$(PROGRAM).c sw/drivers/uart.c sw/drivers/gpio.c \
                   sw/drivers/i2c.c sw/drivers/clint.c sw/drivers/plic.c \
                   sw/bsp/cache.c sw/boot/enter.S
CFLAGS_EXTRA := -I$(ROOT)/sw/drivers/include -I$(ROOT)/sw/boot
