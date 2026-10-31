# File: program.mk
# Spec: Task T-NETN; SoC 7.2/7.4; npu-spec 2.4; eth-spec 2.4/2.6.
# Description: B3N SRAM network tensor inference, without media engines.
# Clock domain: none (build tool).
ARCH := rv32im_zicsr
MEMORY := sram
PROGRAM_SOURCES := $(addprefix sw/apps/demo/,demo_npu/main.c demo_npu/inference.c \
    logic.c network.c network_npu.c monitor.c) \
    sw/lib/yolo_post.c sw/lib/yolo_tables.c sw/lib/eth_monitor.c \
    sw/lib/eth_monitor_pack.c sw/boot/info.c sw/bsp/cache.c \
    $(addprefix sw/drivers/,uart.c clint.c plic.c engine.c npu.c eth.c mem_xbar.c)
CFLAGS_EXTRA := -I$(ROOT)/sw/apps/demo -I$(ROOT)/sw/drivers/include \
    -I$(ROOT)/sw/boot -I$(ROOT)/sw/lib -DDEMO_NPU_NET -fstack-usage
