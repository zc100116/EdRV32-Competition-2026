# File: sources.mk
# Spec: Task B3-4b; CLAUDE.md 9.3.
# Description: Shared nofrendo source selection and compiler/linker configuration.
# Clock domain: none (build tool).
NOF := third_party/nofrendo/components/nofrendo
NES_OPT ?= -O2
NES_SKIP ?= 0
NES_FRAMES ?= 0
NES_CORE := $(addprefix $(NOF)/,cpu/nes6502.c nes/nes.c nes/nes_ppu.c \
    nes/nes_mmc.c nes/nes_rom.c nes/nes_pal.c nes/nesinput.c nes/mmclist.c) \
    $(patsubst $(ROOT)/%,%,$(wildcard $(ROOT)/$(NOF)/mappers/*.c)) \
    $(patsubst $(ROOT)/%,%,$(wildcard $(ROOT)/$(NOF)/sndhrdw/*.c))
NES_COMMON := sw/apps/nes/port.c sw/apps/nes/profile.c
NES_INCLUDES := $(addprefix -I$(ROOT)/$(NOF),/ /cpu /nes /sndhrdw /libsnss)
NES_FLAGS := $(NES_OPT) -fno-strict-aliasing $(NES_INCLUDES)
NES_WRAPS := -Wl,--wrap=nes6502_execute,--wrap=ppu_scanline,--wrap=ppu_endscanline

$(OUT)/obj/$(NOF)/nes/nes_ppu.o: NES_WARNINGS := -Wno-implicit-fallthrough -Wno-maybe-uninitialized

$(OUT)/obj/$(NOF)/nes/nes_rom.o: NES_WARNINGS := -Wno-unused-parameter \
    -Wno-unused-result -Wno-unused-function -Wno-stringop-truncation \
    -Wno-unused-but-set-variable -Wno-misleading-indentation

$(OUT)/obj/$(NOF)/mappers/map005.o: NES_WARNINGS := -Wno-unused-but-set-variable

# Core changes are applied only to build-local copies; the submodule stays untouched.
NES_PATCHED := cpu/nes6502.c nes/nes_ppu.c nes/nes_rom.c mappers/map019.c
$(OUT)/core/.patched: $(addprefix $(ROOT)/$(NOF)/,$(NES_PATCHED)) \
    $(wildcard $(ROOT)/sw/apps/nes/patches/*.patch)
	$(foreach file,$(NES_PATCHED),mkdir -p $(OUT)/core/$(dir $(file)); \
        cp $(ROOT)/$(NOF)/$(file) $(OUT)/core/$(file);)
	cd $(OUT)/core && git apply $(sort $(wildcard $(ROOT)/sw/apps/nes/patches/*.patch))
	touch $@

define NES_PATCH_RULE
$(OUT)/obj/$(NOF)/$(1:.c=.o): $(OUT)/core/.patched FORCE
	mkdir -p $$(@D)
	$$(CC) $$(CFLAGS) $$(NES_WARNINGS) -c $(OUT)/core/$(1) -o $$@
endef
$(foreach file,$(NES_PATCHED),$(eval $(call NES_PATCH_RULE,$(file))))

$(OUT)/obj/$(NOF)/%.o: $(ROOT)/$(NOF)/%.c FORCE
	mkdir -p $(@D)
	$(CC) $(CFLAGS) $(NES_WARNINGS) -c $< -o $@
