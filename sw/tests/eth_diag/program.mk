# File: program.mk
# Spec: eth-spec 2.4/2.6/2.7; Task T-ETHDIAG.
# Description: BIOS-loadable SRAM Ethernet diagnostic, using DDR for DMA.
# Clock domain: none (build tool).
MEMORY := sram
PROGRAM_SOURCES := sw/tests/eth_diag/main.c sw/drivers/eth.c sw/drivers/uart.c \
                   sw/drivers/clint.c
CFLAGS_EXTRA := -I$(ROOT)/sw/drivers/include
