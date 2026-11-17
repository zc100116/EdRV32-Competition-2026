# Showcase design P1b/P2: shared pages, headless captures and native Windows.
ROOT := $(abspath ../../../..)
BUILD := $(ROOT)/build/sim
LVGL := $(ROOT)/third_party/lvgl
UI := $(wildcard ../ui/*.c)
UI_HEADERS := $(wildcard ../ui/*.h)
FONT_SIZES := 14 16 20 28 40
FONTS := $(foreach size,$(FONT_SIZES),$(BUILD)/fonts/sim_font_$(size).c)
DIGITS := $(BUILD)/fonts/sim_digits_40.c
ASSETS := $(BUILD)/sample_images.c
GAMES := $(BUILD)/game_data.c
GAME_LIST := ../games/games.txt
LV_SOURCES := $(shell find $(LVGL)/src -name '*.c')
INCLUDES := -I. -I../ui -I$(ROOT)/sw/lib -I$(LVGL) -DLV_CONF_INCLUDE_SIMPLE -DLV_LVGL_H_INCLUDE_SIMPLE \
    -I$(ROOT)/sw/drivers/include -I$(ROOT)/sw/bsp/include -I$(ROOT)/sw/lib/sched
FLAGS := -std=c11 -O2 -Wall -Wextra $(INCLUDES)
WINCC := zig cc -target x86_64-windows-gnu
LINUX_LV := $(patsubst $(LVGL)/%.c,$(BUILD)/linux/%.o,$(LV_SOURCES))
WIN_LV := $(patsubst $(LVGL)/%.c,$(BUILD)/win/%.o,$(LV_SOURCES))
PROCESS_HELPERS := $(ROOT)/sw/lib/geo_matrix.c $(ROOT)/sw/lib/geo_matrix.h
BOLD_FONTS := $(wildcard ../fonts/showcase_*.c)
ART_NAMES := sling rps mole slice catch home ws tower
ART := $(addprefix $(BUILD)/,$(addsuffix _images.c,$(ART_NAMES))) $(BUILD)/stickers.c
COMMON := $(BOLD_FONTS) $(ART) $(UI) sim_data.c game_loop_port.c geo_host.c process.c $(ROOT)/sw/lib/geo_matrix.c $(ASSETS) $(GAMES) $(FONTS) $(DIGITS)
SHOTS := home home-vrn vision image process graphics games chip debug \
    game-running renderer-list renderer-result benchmark-results overlay-home chip-coremark \
    coremark-counters games-last-row detection-settings process-collapsed \
    process-stage-off process-editing process-geo image-waiting image-receiving image-detecting \
    image-done image-failed keyboard-focus mouse-hover session-failed session-starting \
    session-stopping \
    vision-hidden vision-categories overlay-cpu
.PHONY: win shots
win: $(BUILD)/showcase_sim.exe
shots: $(addprefix $(BUILD)/shots/,$(addsuffix .png,$(SHOTS)))

$(FONTS) $(DIGITS) &: $(UI) $(UI_HEADERS) sim_data.c $(GAME_LIST) $(ROOT)/tools/sw/gen_fonts.py
	python3 $(ROOT)/tools/sw/gen_fonts.py --output-dir $(BUILD)/fonts --sizes $(FONT_SIZES) \
	    --digit-sizes 40 -- $(UI) $(UI_HEADERS) sim_data.c $(GAME_LIST)

$(ASSETS): $(wildcard assets/*.png) $(ROOT)/tools/sw/png2c.py
	python3 $(ROOT)/tools/sw/png2c.py $@

$(GAMES): $(GAME_LIST) $(ROOT)/tools/sw/gen_sim_games.py $(ROOT)/tools/sw/png2c.py
	python3 $(ROOT)/tools/sw/gen_sim_games.py $@

-include $(BUILD)/game_data.d

$(BUILD)/linux/%.o: $(LVGL)/%.c lv_conf.h
	@mkdir -p $(@D)
	$(CC) $(FLAGS) -D_POSIX_C_SOURCE=200809L -c $< -o $@

$(BUILD)/win/%.o: $(LVGL)/%.c lv_conf.h
	@mkdir -p $(@D)
	$(WINCC) $(FLAGS) -DLV_USE_WINDOWS=1 -c $< -o $@

$(BUILD)/showcase_shots: main_shots.c sim_data.c process.c sim_data.h $(PROCESS_HELPERS) $(UI) $(UI_HEADERS) \
    lv_conf.h $(ASSETS) $(GAMES) $(FONTS) $(DIGITS) $(ART) $(BOLD_FONTS) $(LINUX_LV)
	$(CC) $(FLAGS) -Werror main_shots.c $(COMMON) $(LINUX_LV) -lm -o $@

$(BUILD)/shots/%.png: $(BUILD)/shots/%.rgb565 $(ROOT)/tools/sw/raw2png.py
	python3 $(ROOT)/tools/sw/raw2png.py $< $@

$(addprefix $(BUILD)/shots/,$(addsuffix .rgb565,$(SHOTS))) &: $(BUILD)/showcase_shots
	mkdir -p $(BUILD)/shots
	cd $(BUILD) && ./showcase_shots

$(BUILD)/showcase_sim.exe: main_windows.c sim_data.c process.c sim_data.h $(PROCESS_HELPERS) $(UI) \
    $(UI_HEADERS) lv_conf.h $(ASSETS) $(GAMES) $(FONTS) $(DIGITS) $(ART) $(BOLD_FONTS) $(WIN_LV)
	$(WINCC) $(FLAGS) -Werror -DLV_USE_WINDOWS=1 main_windows.c $(COMMON) \
	    $(WIN_LV) -static -Wl,--subsystem,windows -luser32 -lgdi32 -lkernel32 -o $@

# Override only the pose page to measure a git-extracted baseline with this fixture.
POSE_PAGE ?= ../ui/page_pose.c
.PHONY: pose-bench $(BUILD)/showcase_pose_bench
pose-bench: $(BUILD)/showcase_pose_bench
	cd $(BUILD) && ./showcase_pose_bench

$(BUILD)/showcase_pose_bench: main_pose_bench.c $(COMMON) $(POSE_PAGE) $(LINUX_LV)
	$(CC) $(FLAGS) -Werror main_pose_bench.c \
	    $(filter-out ../ui/page_pose.c,$(COMMON)) $(POSE_PAGE) $(LINUX_LV) -lm -o $@

.PHONY: demos
demos: $(BUILD)/showcase_demo_shots
	mkdir -p $(BUILD)/shots
	cd $(BUILD) && ./showcase_demo_shots $(ROOT)/build/npu/demo_pages_test
	$(foreach name,gesture face helmet,python3 $(ROOT)/tools/sw/raw2png.py $(BUILD)/shots/demo-$(name).rgb565 $(BUILD)/shots/demo-$(name).png;)

$(BUILD)/showcase_demo_shots: main_demo_shots.c $(COMMON) $(LINUX_LV)
	$(CC) $(FLAGS) -Werror main_demo_shots.c $(COMMON) $(LINUX_LV) -lm -o $@

.PHONY: grab-shot
GRAB_FIXTURE ?= $(ROOT)/build/npu/demo_pages_test
grab-shot: $(BUILD)/showcase_grab_shot
	mkdir -p $(BUILD)/shots
	cd $(BUILD) && ./showcase_grab_shot $(GRAB_FIXTURE)
	python3 $(ROOT)/tools/sw/raw2png.py $(BUILD)/shots/demo-grab.rgb565 \
	    $(ROOT)/docs/reports/assets/demo-grab.png

$(BUILD)/showcase_grab_shot: main_grab_shot.c $(COMMON) $(LINUX_LV)
	$(CC) $(FLAGS) -Werror main_grab_shot.c $(COMMON) $(LINUX_LV) -lm -o $@

# Original game sprites are shared with the board UI (no simulated replacement art).
define SIM_ART_RULE
$(BUILD)/$(1)_images.c: $(ROOT)/tools/sw/embed_showcase_images.py \
    $$(wildcard ../assets/$(2)/*.png)
	python3 $(ROOT)/tools/sw/embed_showcase_images.py ../assets/$(2) $$@ --prefix $(1)
endef
$(foreach art,sling rps mole slice catch tower,$(eval $(call SIM_ART_RULE,$(art),$(art))))
$(eval $(call SIM_ART_RULE,home,icons))
$(eval $(call SIM_ART_RULE,ws,workshop))
$(BUILD)/stickers.c: $(wildcard ../assets/stickers/*.png)
	python3 $(ROOT)/tools/sw/rotate_showcase_stickers.py ../assets/stickers $(BUILD)/sticker-frames
	python3 $(ROOT)/tools/sw/embed_showcase_images.py $(BUILD)/sticker-frames $@ --prefix sticker

FRAME_SHOTS := home-ai home-motion home-media home-system settings game-start
FRAME_OUTPUT ?= $(ROOT)/build/sim/ui-frame
.PHONY: frame-shots
frame-shots: $(BUILD)/showcase_frame_shots
	mkdir -p $(BUILD)/ui-frame $(FRAME_OUTPUT)
	$(BUILD)/showcase_frame_shots $(BUILD)/ui-frame
	$(foreach name,$(FRAME_SHOTS),python3 $(ROOT)/tools/sw/raw2png.py $(BUILD)/ui-frame/$(name).rgb565 $(FRAME_OUTPUT)/$(name).png;)
	rm $(addprefix $(BUILD)/ui-frame/,$(addsuffix .rgb565,$(FRAME_SHOTS)))
$(BUILD)/showcase_frame_shots: main_frame_shots.c $(COMMON) $(UI_HEADERS) $(LINUX_LV)
	$(CC) $(FLAGS) -Werror main_frame_shots.c $(COMMON) $(LINUX_LV) -lm -o $@

PAGES_SHOTS := vision image process graphics games chip debug pose hand face helmet settings monitor vision-categories detection-settings debug-network graphics-renderers image-loading chip-running hand-debug face-debug helmet-warning session-failed
PAGES_OUTPUT ?= $(ROOT)/build/sim/ui-pages
.PHONY: pages-shots
pages-shots: $(BUILD)/showcase_pages_shots
	mkdir -p $(BUILD)/ui-pages $(PAGES_OUTPUT)
	$(BUILD)/showcase_pages_shots $(BUILD)/ui-pages
	$(foreach name,$(PAGES_SHOTS),python3 $(ROOT)/tools/sw/raw2png.py $(BUILD)/ui-pages/$(name).rgb565 $(PAGES_OUTPUT)/$(name).png;)
	rm $(addprefix $(BUILD)/ui-pages/,$(addsuffix .rgb565,$(PAGES_SHOTS)))
$(BUILD)/showcase_pages_shots: main_pages_shots.c $(COMMON) $(UI_HEADERS) $(LINUX_LV)
	$(CC) $(FLAGS) $(PAGES_FLAGS) -Werror main_pages_shots.c $(COMMON) $(LINUX_LV) -lm -o $@

# T-GAMES-LOOP: all six games, three states each, using application snapshots.
GAMES_OUTPUT ?= $(ROOT)/build/sim/games-loop
GAMES_SHOTS := $(foreach game,sling rps mole slice catch,\
    $(addprefix $(game)-,start playing result)) process-s1-open home-ai
.PHONY: games-shots
games-shots: $(BUILD)/showcase_games_shots
	mkdir -p $(GAMES_OUTPUT)
	$(BUILD)/showcase_games_shots $(GAMES_OUTPUT)
	$(foreach name,$(GAMES_SHOTS),python3 $(ROOT)/tools/sw/raw2png.py $(GAMES_OUTPUT)/$(name).rgb565 $(GAMES_OUTPUT)/$(name).png;)
	rm $(addprefix $(GAMES_OUTPUT)/,$(addsuffix .rgb565,$(GAMES_SHOTS)))
$(BUILD)/showcase_games_shots: main_games_shots.c $(COMMON) $(UI_HEADERS) $(LINUX_LV)
	$(CC) $(FLAGS) -Werror main_games_shots.c $(COMMON) $(LINUX_LV) -lm -o $@

COMPACT_NAMES := vision image process pose hand face helmet
COMPACT_OUTPUT ?= $(ROOT)/build/sim/ui-compact
.PHONY: compact-shots
compact-shots: $(BUILD)/showcase_compact_shots
	mkdir -p $(BUILD)/ui-compact $(COMPACT_OUTPUT)
	$(BUILD)/showcase_compact_shots $(BUILD)/ui-compact
	$(foreach name,$(COMPACT_NAMES) $(addsuffix -drawer,$(COMPACT_NAMES)),python3 $(ROOT)/tools/sw/raw2png.py $(BUILD)/ui-compact/$(name).rgb565 $(COMPACT_OUTPUT)/$(name).png;)
	rm $(BUILD)/ui-compact/*.rgb565
$(BUILD)/showcase_compact_shots: main_compact_shots.c $(COMMON) $(UI_HEADERS) $(LINUX_LV)
	$(CC) $(FLAGS) -Werror main_compact_shots.c $(COMMON) $(LINUX_LV) -lm -o $@

WORKSHOP_OUTPUT ?= $(ROOT)/build/sim/workshop
WORKSHOP_SHOTS := selection clearing-day house-day castle-day house-dusk house-night \
    inventory crack-4 falling animal-lift animal-stun slope-preview castle-night
.PHONY: workshop-shots
workshop-shots: $(BUILD)/showcase_workshop_shots
	mkdir -p $(WORKSHOP_OUTPUT)
	$(BUILD)/showcase_workshop_shots $(WORKSHOP_OUTPUT)
	$(foreach name,$(WORKSHOP_SHOTS),python3 $(ROOT)/tools/sw/raw2png.py $(WORKSHOP_OUTPUT)/$(name).rgb565 $(WORKSHOP_OUTPUT)/$(name).png;)
	rm $(addprefix $(WORKSHOP_OUTPUT)/,$(addsuffix .rgb565,$(WORKSHOP_SHOTS)))
$(BUILD)/showcase_workshop_shots: main_workshop_shots.c $(COMMON) $(UI_HEADERS) $(LINUX_LV)
	$(CC) $(FLAGS) -Werror main_workshop_shots.c $(COMMON) $(LINUX_LV) -lm -o $@

TOWER_OUTPUT ?= $(ROOT)/build/sim/tower
.PHONY: tower-shots
tower-shots: $(BUILD)/showcase_tower_shots
	mkdir -p $(TOWER_OUTPUT)
	$(BUILD)/showcase_tower_shots $(TOWER_OUTPUT)
	$(foreach name,initial steel-held mode-d full-platform,python3 $(ROOT)/tools/sw/raw2png.py $(TOWER_OUTPUT)/$(name).rgb565 $(TOWER_OUTPUT)/$(name).png;)
	rm $(addprefix $(TOWER_OUTPUT)/,$(addsuffix .rgb565,initial steel-held mode-d full-platform))
$(BUILD)/showcase_tower_shots: main_tower_shots.c $(COMMON) $(UI_HEADERS) $(LINUX_LV)
	$(CC) $(FLAGS) -Werror main_tower_shots.c $(COMMON) $(LINUX_LV) -lm -o $@

# R5-4: host camera detections and four farm acceptance captures.
FARM_OUTPUT ?= $(ROOT)/outputs/farm
FARM_SHOTS := normal missing dashboard home-ai
.PHONY: farm-shots
farm-shots: $(BUILD)/showcase_farm_shots
	mkdir -p $(FARM_OUTPUT)
	$(BUILD)/showcase_farm_shots $(FARM_OUTPUT)
	$(foreach name,$(FARM_SHOTS),python3 $(ROOT)/tools/sw/raw2png.py $(FARM_OUTPUT)/$(name).rgb565 $(FARM_OUTPUT)/$(name).png;)
	rm $(addprefix $(FARM_OUTPUT)/,$(addsuffix .rgb565,$(FARM_SHOTS)))
$(BUILD)/showcase_farm_shots: main_farm_shots.c $(COMMON) $(UI_HEADERS) $(LINUX_LV)
	$(CC) $(FLAGS) -Werror main_farm_shots.c $(COMMON) $(LINUX_LV) -lm -o $@

DRAW_OUTPUT ?= $(ROOT)/outputs/draw
.PHONY: draw-shots
draw-shots: $(BUILD)/showcase_draw_shots
	mkdir -p $(DRAW_OUTPUT)
	$(BUILD)/showcase_draw_shots $(DRAW_OUTPUT)
	$(foreach name,writing smooth eraser motion-tab,python3 $(ROOT)/tools/sw/raw2png.py $(DRAW_OUTPUT)/$(name).rgb565 $(DRAW_OUTPUT)/$(name).png;)
	rm $(addprefix $(DRAW_OUTPUT)/,$(addsuffix .rgb565,writing smooth eraser motion-tab))
$(BUILD)/showcase_draw_shots: main_draw_shots.c $(COMMON) $(UI_HEADERS) $(LINUX_LV)
	$(CC) $(FLAGS) -Werror main_draw_shots.c $(COMMON) $(LINUX_LV) -lm -o $@
