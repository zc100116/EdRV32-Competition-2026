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
