# Unified RV32 software build; invoke from any directory with make -C sw.
.DEFAULT_GOAL := all
ROOT := $(abspath ..)
PROGRAM ?= minimal
MEMORY ?= rom
CC := riscv-none-elf-gcc
OBJDUMP := riscv-none-elf-objdump
OBJCOPY := riscv-none-elf-objcopy
OUT := $(ROOT)/build/sw/$(PROGRAM)
ARCH ?= rv32im_zicsr
SYS_PROGRAMS := sc01 sc02 sc03 sc04 sc05 sc06 sys_spike
PROGRAM_DIR := $(if $(filter demo_vision demo_vnpu demo_npu,$(PROGRAM)),sw/apps/demo/$(PROGRAM),$(if \
               $(filter bootloader,$(PROGRAM)),sw/boot,$(if \
               $(filter monitor demo nes s3,$(PROGRAM)),sw/apps/$(PROGRAM),$(if \
               $(filter $(SYS_PROGRAMS),$(PROGRAM)),sw/tests/sys,sw/tests/$(PROGRAM)))))
-include $(ROOT)/$(PROGRAM_DIR)/program.mk
ISA_FLAGS := -march=$(ARCH) -mabi=ilp32
CFLAGS := $(ISA_FLAGS) -std=c11 -Wall -Wextra -Werror -O2 -ffreestanding -fno-builtin \
          -ffunction-sections -fdata-sections -I$(ROOT)/sw/bsp/include
CFLAGS += $(CFLAGS_EXTRA)
LDFLAGS := -nostdlib -Wl,--gc-sections \
           -Wl,-T,sw/bsp/ld/$(MEMORY).ld -Wl,-Map,$(OUT)/$(PROGRAM).map
BSP := sw/bsp/start.S sw/bsp/host.c
ifneq ($(PROGRAM_SOURCES),)
SOURCES := $(if $(PROGRAM_BSP),$(PROGRAM_BSP),$(BSP)) $(PROGRAM_SOURCES)
else ifeq ($(PROGRAM),coremark)
CORE := third_party/coremark
SOURCES := $(BSP) $(addprefix $(CORE)/,core_main.c core_list_join.c core_matrix.c \
           core_state.c core_util.c) sw/apps/coremark/core_portme.c sw/apps/coremark/ee_printf.c
CFLAGS += -I$(ROOT)/sw/apps/coremark -I$(ROOT)/$(CORE) -DITERATIONS=1
else
SOURCES := $(BSP) sw/tests/$(PROGRAM)/main.c
endif
OBJECTS := $(addprefix $(OUT)/obj/,$(patsubst %.S,%.o,$(SOURCES:.c=.o)))
# Report the compile flags used below without host include paths; metadata is separate.
CPPFLAGS := '-DBUILD_COMMIT="$(shell git -C $(ROOT) rev-parse --short HEAD)"' \
            '-DBUILD_COMPILER="GCC $(shell $(CC) -dumpfullversion)"' \
            '-DBUILD_CFLAGS="$(filter-out -I%,$(CFLAGS))"' '-DBUILD_ISA="$(ARCH)"'

.PHONY: all coremark sys FORCE
FORCE:
all: $(OUT)/$(PROGRAM).elf
	cd $(ROOT) && $(OBJDUMP) -d -S $< > $(OUT)/$(PROGRAM).dis
	cd $(ROOT) && python3 tools/elf2mem.py $< $(OUT)
ifneq ($(filter bootloader monitor demo demo_vision demo_vnpu demo_npu nes rnd_board $(SYS_PROGRAMS),$(PROGRAM)),)
	$(OBJCOPY) -O binary $< $(OUT)/$(PROGRAM).bin
endif

$(ROOT)/build/sw/soc_memory.ld: $(ROOT)/rtl/include/soc_address_map.json
	mkdir -p $(@D)
	cd $(ROOT) && python3 -c 'import json; from pathlib import Path; m=json.loads(Path("rtl/include/soc_address_map.json").read_text()); Path("build/sw/soc_memory.ld").write_text("MEMORY {\n" + "".join("  " + r["name"] + " (rwx) : ORIGIN = " + r["base"] + ", LENGTH = " + r["size"] + "\n" for r in m["regions"] if r["name"] in ("ROM", "SRAM", "DDR")) + "}\n")'

$(OUT)/$(PROGRAM).elf: $(OBJECTS) $(ROOT)/sw/bsp/ld/$(MEMORY).ld \
                      $(ROOT)/build/sw/soc_memory.ld FORCE
	cd $(ROOT) && $(CC) $(ISA_FLAGS) $(LDFLAGS) $(OBJECTS) $(PROGRAM_LDLIBS) -lgcc -o $@

# The coordinator exempts unmodified third-party code from -Werror.
$(OUT)/obj/third_party/coremark/%.o: $(ROOT)/third_party/coremark/%.c FORCE
	mkdir -p $(@D)
	$(CC) $(CPPFLAGS) $(filter-out -Werror,$(CFLAGS)) $(CORE_MAIN_FLAGS) -c $< -o $@

$(OUT)/obj/%.o: $(ROOT)/%.c FORCE
	mkdir -p $(@D)
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

$(OUT)/obj/%.o: $(ROOT)/%.S FORCE
	mkdir -p $(@D)
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

coremark:
	$(MAKE) PROGRAM=coremark MEMORY=sram

# ROM bootloader and the SC-01--SC-06 applications, plus software-only Spike checks.
sys:
	$(MAKE) PROGRAM=bootloader
	$(foreach program,$(SYS_PROGRAMS),$(MAKE) PROGRAM=$(program) &&) true
