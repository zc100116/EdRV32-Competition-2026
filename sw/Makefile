# Unified RV32 software build; invoke from any directory with make -C sw.
.DEFAULT_GOAL := all
ROOT := $(abspath ..)
PROGRAM ?= minimal
MEMORY ?= rom
CC := riscv-none-elf-gcc
OBJDUMP := riscv-none-elf-objdump
OUT := $(ROOT)/build/sw/$(PROGRAM)
ARCH ?= rv32imc_zicsr
include $(wildcard $(ROOT)/sw/tests/$(PROGRAM)/program.mk)
ISA_FLAGS := -march=$(ARCH) -mabi=ilp32
CFLAGS := $(ISA_FLAGS) -std=c11 -Wall -Wextra -Werror -O2 -ffreestanding -fno-builtin \
          -ffunction-sections -fdata-sections -I$(ROOT)/sw/bsp/include
LDFLAGS := -nostdlib -Wl,--gc-sections \
           -Wl,-T,sw/bsp/ld/$(MEMORY).ld -Wl,-Map,$(OUT)/$(PROGRAM).map
BSP := sw/bsp/start.S sw/bsp/host.c
ifeq ($(PROGRAM),coremark)
CORE := third_party/coremark
SOURCES := $(BSP) $(addprefix $(CORE)/,core_main.c core_list_join.c core_matrix.c \
           core_state.c core_util.c) sw/apps/coremark/core_portme.c sw/apps/coremark/ee_printf.c
CFLAGS += -I$(ROOT)/sw/apps/coremark -I$(ROOT)/$(CORE) -DITERATIONS=1
else
SOURCES := $(BSP) sw/tests/$(PROGRAM)/main.c
endif
OBJECTS := $(addprefix $(OUT)/obj/,$(patsubst %.S,%.o,$(SOURCES:.c=.o)))

.PHONY: all coremark FORCE
FORCE:
all: $(OUT)/$(PROGRAM).elf
	cd $(ROOT) && $(OBJDUMP) -d -S $< > $(OUT)/$(PROGRAM).dis
	cd $(ROOT) && python3 tools/elf2mem.py $< $(OUT)

$(ROOT)/build/sw/soc_memory.ld: $(ROOT)/rtl/include/soc_address_map.json
	mkdir -p $(@D)
	cd $(ROOT) && python3 -c 'import json; from pathlib import Path; m=json.loads(Path("rtl/include/soc_address_map.json").read_text()); Path("build/sw/soc_memory.ld").write_text("MEMORY {\n" + "".join("  " + r["name"] + " (rwx) : ORIGIN = " + r["base"] + ", LENGTH = " + r["size"] + "\n" for r in m["regions"] if r["name"] in ("ROM", "SRAM", "DDR")) + "}\n")'

$(OUT)/$(PROGRAM).elf: $(OBJECTS) $(ROOT)/sw/bsp/ld/$(MEMORY).ld \
                      $(ROOT)/build/sw/soc_memory.ld FORCE
	cd $(ROOT) && $(CC) $(ISA_FLAGS) $(LDFLAGS) $(OBJECTS) -lgcc -o $@

# The coordinator exempts unmodified third-party code from -Werror.
$(OUT)/obj/third_party/coremark/%.o: $(ROOT)/third_party/coremark/%.c FORCE
	mkdir -p $(@D)
	$(CC) $(filter-out -Werror,$(CFLAGS)) -c $< -o $@

$(OUT)/obj/%.o: $(ROOT)/%.c FORCE
	mkdir -p $(@D)
	$(CC) $(CFLAGS) -c $< -o $@

$(OUT)/obj/%.o: $(ROOT)/%.S FORCE
	mkdir -p $(@D)
	$(CC) $(CFLAGS) -c $< -o $@

coremark:
	$(MAKE) PROGRAM=coremark MEMORY=sram
