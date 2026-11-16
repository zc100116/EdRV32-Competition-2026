# Host scheduler acceptance, design showcase 4.1.
ROOT := ../../..
.PHONY: test
test:
	mkdir -p $(ROOT)/build/sw/tests/sched
	$(CC) -std=c11 -Wall -Wextra -Werror -I$(ROOT)/sw/lib/sched \
	    main.c $(ROOT)/sw/lib/sched/sched.c -o $(ROOT)/build/sw/tests/sched/test
	$(ROOT)/build/sw/tests/sched/test

	$(CC) -std=c11 -Wall -Wextra -Werror -I$(ROOT)/sw/apps/showcase \
	    -I$(ROOT)/sw/lib/sched -I$(ROOT)/sw/lib -I$(ROOT)/sw/drivers/include \
	    -I$(ROOT)/sw/bsp/include input.c $(ROOT)/sw/apps/showcase/input.c \
	    -o $(ROOT)/build/sw/tests/sched/input-test
	$(ROOT)/build/sw/tests/sched/input-test

# Uses upstream FreeRTOS declarations and mocks only the host hardware/kernel boundary.
.PHONY: rtos
rtos:
	mkdir -p $(ROOT)/build/sw/tests/sched
	$(CC) -std=c11 -Wall -Wextra -Werror -ffunction-sections -fdata-sections \
	    -Wl,--gc-sections -D__riscv_xlen=32 -I$(ROOT)/sw/lib/sched/freertos \
	    -I$(ROOT)/third_party/freertos-kernel/include \
	    -I$(ROOT)/third_party/freertos-kernel/portable/GCC/RISC-V \
	    -I$(ROOT)/sw/lib/sched -I$(ROOT)/sw/apps/showcase -I$(ROOT)/sw/lib \
	    -I$(ROOT)/sw/bsp/include -I$(ROOT)/sw/drivers/include rtos.c \
	    -o $(ROOT)/build/sw/tests/sched/rtos
	$(ROOT)/build/sw/tests/sched/rtos
