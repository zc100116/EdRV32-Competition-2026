# Showcase P1a: one shared interface, native Windows and headless Linux mains.
ROOT := $(abspath ../../../..)
BUILD := $(ROOT)/build/sim
LVGL := $(ROOT)/third_party/lvgl
FONT_SIZES := 14 16 20 28 40
FONTS := $(foreach size,$(FONT_SIZES),$(BUILD)/fonts/sim_font_$(size).c)
DIGITS := $(BUILD)/fonts/sim_digits_40.c $(BUILD)/fonts/sim_digits_48.c
LV_SOURCES := $(shell find $(LVGL)/src -name '*.c')
INCLUDES := -I. -I$(LVGL) -DLV_CONF_INCLUDE_SIMPLE -DLV_LVGL_H_INCLUDE_SIMPLE
FLAGS := -std=c11 -O2 -Wall -Wextra $(INCLUDES)
WINCC := zig cc -target x86_64-windows-gnu
LINUX_LV := $(patsubst $(LVGL)/%.c,$(BUILD)/linux/%.o,$(LV_SOURCES))
WIN_LV := $(patsubst $(LVGL)/%.c,$(BUILD)/win/%.o,$(LV_SOURCES))
SHOTS := A-home A-home-focus A-monitor B-home B-monitor C-home C-monitor
.PHONY: win shots
win: $(BUILD)/showcase_sim.exe
shots: $(addprefix $(BUILD)/shots/,$(addsuffix .png,$(SHOTS)))

$(FONTS) $(DIGITS) &: style_samples.c $(ROOT)/tools/sw/gen_fonts.py
	python3 $(ROOT)/tools/sw/gen_fonts.py --output-dir $(BUILD)/fonts --sizes $(FONT_SIZES) \
	    --digit-sizes 40 48 -- $<

$(BUILD)/linux/%.o: $(LVGL)/%.c lv_conf.h
	@mkdir -p $(@D)
	$(CC) $(FLAGS) -D_POSIX_C_SOURCE=200809L -c $< -o $@

$(BUILD)/win/%.o: $(LVGL)/%.c lv_conf.h
	@mkdir -p $(@D)
	$(WINCC) $(FLAGS) -DLV_USE_WINDOWS=1 -c $< -o $@

$(BUILD)/showcase_shots: main_shots.c style_samples.c style_samples.h lv_conf.h \
    $(FONTS) $(DIGITS) $(LINUX_LV)
	$(CC) $(FLAGS) -Werror main_shots.c style_samples.c $(FONTS) $(DIGITS) $(LINUX_LV) -lm -o $@

$(BUILD)/shots/%.png: $(BUILD)/shots/%.rgb565 $(ROOT)/tools/sw/raw2png.py
	python3 $(ROOT)/tools/sw/raw2png.py $< $@

$(addprefix $(BUILD)/shots/,$(addsuffix .rgb565,$(SHOTS))) &: $(BUILD)/showcase_shots
	mkdir -p $(BUILD)/shots
	cd $(BUILD) && ./showcase_shots

$(BUILD)/showcase_sim.exe: main_windows.c style_samples.c style_samples.h lv_conf.h \
    $(FONTS) $(DIGITS) $(WIN_LV)
	$(WINCC) $(FLAGS) -Werror -DLV_USE_WINDOWS=1 main_windows.c style_samples.c \
	    $(FONTS) $(DIGITS) $(WIN_LV) -static -Wl,--subsystem,windows -luser32 -lgdi32 -lkernel32 -o $@
