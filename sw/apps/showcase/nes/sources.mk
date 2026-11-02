# File: sources.mk
# Spec: showcase design 4.4; CLAUDE.md 9.3.
# Description: Shared nofrendo source selection and compiler/linker configuration.
# Clock domain: none (build tool).
NOF := third_party/nofrendo/components/nofrendo
NES_OPT ?= -O2
NES_CORE := $(addprefix $(NOF)/,cpu/nes6502.c nes/nes.c nes/nes_ppu.c \
    nes/nes_mmc.c nes/nes_rom.c nes/nes_pal.c nes/nesinput.c nes/mmclist.c) \
    $(patsubst $(ROOT)/%,%,$(wildcard $(ROOT)/$(NOF)/mappers/*.c)) \
    $(patsubst $(ROOT)/%,%,$(wildcard $(ROOT)/$(NOF)/sndhrdw/*.c))
# Our J87 implements both bank bits; the unregistered upstream version only has D1.
NES_CORE := $(filter-out $(NOF)/mappers/map087.c,$(NES_CORE))
NES_CORE += $(patsubst $(ROOT)/%,%,$(wildcard $(ROOT)/sw/apps/showcase/nes/mappers/*.c))
NES_COMMON := sw/apps/showcase/nes/port.c
NES_INCLUDES := -I$(OUT)/core/cpu
NES_INCLUDES += $(addprefix -I$(ROOT)/$(NOF),/ /cpu /nes /sndhrdw /libsnss)
NES_INCLUDES += -I$(ROOT)/sw/apps/showcase/nes/mappers
NES_FLAGS := $(NES_OPT) -fno-strict-aliasing $(NES_INCLUDES)

$(OUT)/obj/$(NOF)/nes/nes_ppu.o: NES_WARNINGS := -Wno-implicit-fallthrough -Wno-maybe-uninitialized

$(OUT)/obj/$(NOF)/nes/nes_rom.o: NES_WARNINGS := -Wno-unused-parameter \
    -Wno-unused-result -Wno-unused-function -Wno-stringop-truncation \
    -Wno-unused-but-set-variable -Wno-misleading-indentation

$(OUT)/obj/$(NOF)/mappers/map005.o: NES_WARNINGS := -Wno-unused-but-set-variable

# Core changes are applied only to build-local copies; the submodule stays untouched.
NES_PATCHED := nes/nes.c cpu/nes6502.c cpu/nes6502.h nes/nes_ppu.c nes/nes_rom.c \
    nes/mmclist.c mappers/map019.c mappers/map004.c
$(OUT)/core/.patched: $(ROOT)/sw/apps/showcase/nes/sources.mk \
    $(addprefix $(ROOT)/$(NOF)/,$(NES_PATCHED)) \
    $(wildcard $(ROOT)/sw/apps/showcase/nes/patches/*.patch)
	$(foreach file,$(NES_PATCHED),mkdir -p $(OUT)/core/$(dir $(file)); \
        cp $(ROOT)/$(NOF)/$(file) $(OUT)/core/$(file);)
	cd $(OUT)/core && git apply $(sort $(wildcard $(ROOT)/sw/apps/showcase/nes/patches/*.patch))
	touch $@

define NES_PATCH_RULE
$(OUT)/obj/$(NOF)/$(1:.c=.o): $(OUT)/core/.patched FORCE
	mkdir -p $$(@D)
	$$(CC) $$(CFLAGS) $$(NES_WARNINGS) -c $(OUT)/core/$(1) -o $$@
endef
$(foreach file,$(filter %.c,$(NES_PATCHED)),$(eval $(call NES_PATCH_RULE,$(file))))

$(OUT)/obj/$(NOF)/%.o: $(ROOT)/$(NOF)/%.c FORCE
	mkdir -p $(@D)
	$(CC) $(CFLAGS) $(NES_WARNINGS) -c $< -o $@
