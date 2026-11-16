# File: program.mk
# Design: showcase 4.1--4.5; single BIOS-loaded DDR application.
# Temporary card 68 R2 option; remove after card 75 board acceptance (CLAUDE.md 1.2).
SHOWCASE_POST ?= hw
ifeq ($(SHOWCASE_POST),cpu)
OUT := $(ROOT)/build/sw/showcase-cpupost
endif
MEMORY := showcase
PROGRAM_SOURCES := sw/apps/showcase/main.c sw/apps/showcase/platform.c sw/apps/showcase/input.c \
    sw/apps/showcase/layers.c $(patsubst $(ROOT)/%,%,$(wildcard $(ROOT)/sw/apps/showcase/board/*.c)) \
    $(patsubst $(ROOT)/%,%,$(wildcard $(ROOT)/sw/apps/showcase/ui/*.c)) \
    sw/lib/sched/sched.c \
    sw/drivers/rnd.c sw/drivers/disp.c sw/drivers/engine.c sw/drivers/plic.c \
    sw/drivers/uart.c sw/drivers/gpio.c sw/drivers/clint.c sw/bsp/cache.c \
    sw/lib/virtual_input.c sw/lib/virtual_input_irq.c \
    sw/lib/eth_monitor.c sw/lib/eth_monitor_pack.c \
    sw/drivers/eth.c sw/boot/info.c
CFLAGS_EXTRA := -I$(ROOT)/sw/lib -I$(ROOT)/sw/lib/sched -I$(ROOT)/sw/boot \
    -I$(ROOT)/sw/drivers/include -I$(ROOT)/sw/apps/showcase
include $(ROOT)/sw/apps/showcase/lvgl/program.mk
# P5 design 11.2: select the upstream RGB565 asset only for showcase.
PROGRAM_SOURCES := $(filter-out \
    third_party/lvgl/demos/benchmark/assets/img_benchmark_lvgl_logo_rgb.c,$(PROGRAM_SOURCES))
PROGRAM_SOURCES += sw/apps/showcase/lvgl/benchmark_logo_rgb565.c
include $(ROOT)/sw/apps/showcase/nes/program.mk

# Shared P2 font subset; generated from exactly the shared UI text.
SHOWCASE_FONT_SIZES := 14 16 20 28 40
SHOWCASE_FONTS := $(addprefix build/showcase/fonts/sim_font_,$(addsuffix .c,$(SHOWCASE_FONT_SIZES)))
PROGRAM_SOURCES += $(SHOWCASE_FONTS) build/showcase/fonts/sim_digits_40.c \
    sw/apps/monitor/benchmark.c sw/apps/coremark/core_portme.c sw/apps/coremark/ee_printf.c \
    $(addprefix third_party/coremark/,core_main.c core_list_join.c core_matrix.c core_state.c core_util.c)
CFLAGS_EXTRA += -I$(ROOT)/sw/apps/coremark -I$(ROOT)/sw/apps/monitor \
    -I$(ROOT)/third_party/coremark -DITERATIONS=5000 -DLV_LVGL_H_INCLUDE_SIMPLE
$(OUT)/obj/third_party/coremark/core_main.o: CORE_MAIN_FLAGS := -Dmain=coremark_main
$(addprefix $(ROOT)/,$(SHOWCASE_FONTS) build/showcase/fonts/sim_digits_40.c) &: \
    $(wildcard $(ROOT)/sw/apps/showcase/ui/*.[ch]) $(ROOT)/sw/apps/showcase/main.c \
    $(ROOT)/tools/sw/gen_fonts.py
	python3 $(ROOT)/tools/sw/gen_fonts.py --output-dir $(ROOT)/build/showcase/fonts \
	    --sizes $(SHOWCASE_FONT_SIZES) --digit-sizes 40 -- \
	    $(wildcard $(ROOT)/sw/apps/showcase/ui/*.[ch]) \
	    $(ROOT)/sw/apps/showcase/main.c $(ROOT)/sw/apps/showcase/sim/sim_data.c \
	    $(ROOT)/sw/apps/showcase/games/games.txt

include $(ROOT)/sw/apps/showcase/board/vision/program.mk
# The pack is regenerated from the local manifest/ROMs/covers for every ELF build.
SHOWCASE_GAME_PACK := $(ROOT)/build/showcase/games.bin
SHOWCASE_GAME_OBJECT := $(ROOT)/build/showcase/games.o
$(SHOWCASE_GAME_PACK): $(ROOT)/tools/sw/game_record.py \
    $(ROOT)/sw/apps/showcase/games/games.txt FORCE
	$(HOME)/.local/opt/edrv32-py/bin/python $(ROOT)/tools/sw/game_record.py pack \
	    $(ROOT)/sw/apps/showcase/games/games.txt $@
$(SHOWCASE_GAME_OBJECT): $(SHOWCASE_GAME_PACK)
	riscv-none-elf-objcopy -I binary -O elf32-littleriscv -B riscv \
	    --rename-section .data=.game_pack,alloc,load,readonly,data,contents $< $@
$(OUT)/showcase.elf: $(SHOWCASE_GAME_OBJECT)
PROGRAM_LDLIBS += $(SHOWCASE_GAME_OBJECT)

# Card 40 g15-tuned: apply only to CoreMark algorithms, port and initialization helper.
SHOWCASE_COREMARK_SOURCES := $(addprefix third_party/coremark/,core_main.c core_list_join.c \
    core_matrix.c core_state.c core_util.c) sw/apps/coremark/core_portme.c \
    sw/apps/monitor/benchmark.c
$(addprefix $(OUT)/obj/,$(SHOWCASE_COREMARK_SOURCES:.c=.o)): CFLAGS += \
    -O3 -funroll-all-loops -finline-limit=600 -falign-functions=4 -falign-jumps=4 \
    -falign-loops=4 -fstrict-aliasing -march=rv32im_zicsr_zifencei
PROGRAM_SOURCES += sw/apps/showcase/board/coremark_stack.S
# Keep the locked upstream list code unchanged; GCC 15 diagnoses its local search key.
$(OUT)/obj/third_party/coremark/core_list_join.o: CORE_MAIN_FLAGS := -Wno-maybe-uninitialized

# Spec npu 2.5/4.4: rebuild tags/tables from the checked-in offline snapshot.
SHOWCASE_MODEL_SOURCE := $(ROOT)/tasks/win/20261029-09-b3-software/src/npu
SHOWCASE_MODEL_DIR := $(ROOT)/build/npu/software_model
PROGRAM_SOURCES += build/showcase/model.c
$(ROOT)/build/showcase/model.c: $(ROOT)/tools/sw/embed_showcase_model.py \
    $(wildcard $(ROOT)/tools/npu/*.py) \
    $(addprefix $(SHOWCASE_MODEL_SOURCE)/,mem_model.hex quantization.json)
	python3 $(ROOT)/tools/npu/compile_yolo.py --model-source $(SHOWCASE_MODEL_SOURCE) \
	    --out $(SHOWCASE_MODEL_DIR)
	python3 $(ROOT)/tools/sw/embed_showcase_model.py $(SHOWCASE_MODEL_DIR) $@

# T-POSE-BOARD: both immutable snapshots rebuild with standard-library Python only.
SHOWCASE_POSE_SOURCE := $(ROOT)/sw/apps/showcase/models/yolov8n-pose
SHOWCASE_POSE_DIR := $(ROOT)/build/npu/software_pose
PROGRAM_SOURCES += build/showcase/pose_model.c
$(ROOT)/build/showcase/pose_model.c: $(ROOT)/tools/sw/embed_showcase_model.py \
    $(wildcard $(ROOT)/tools/npu/*.py) \
    $(addprefix $(SHOWCASE_POSE_SOURCE)/,mem_model.hex quantization.json)
	python3 $(ROOT)/tools/npu/compile_yolo.py --task pose \
	    --model-source $(SHOWCASE_POSE_SOURCE) --out $(SHOWCASE_POSE_DIR)
	python3 $(ROOT)/tools/sw/embed_showcase_model.py $(SHOWCASE_POSE_DIR) $@ \
	    --pose-quantization $(SHOWCASE_POSE_SOURCE)/quantization.json

# T-DEMO-PAGES: immutable gesture compiler snapshot.
PROGRAM_SOURCES += build/showcase/gesture_model.c
$(ROOT)/build/showcase/gesture_model.c: $(ROOT)/tools/sw/embed_showcase_model.py \
    $(wildcard $(ROOT)/sw/apps/showcase/models/gesture/*)
	python3 $(ROOT)/tools/sw/embed_showcase_model.py \
	    $(ROOT)/sw/apps/showcase/models/gesture $@ --name gesture \
	    --quantization $(ROOT)/sw/apps/showcase/models/gesture/quantization.json \
	    --classes 14 --points 21

# T-DEMO-PAGES: immutable face compiler snapshot.
PROGRAM_SOURCES += build/showcase/face_model.c
$(ROOT)/build/showcase/face_model.c: $(ROOT)/tools/sw/embed_showcase_model.py \
    $(wildcard $(ROOT)/sw/apps/showcase/models/face/*)
	python3 $(ROOT)/tools/sw/embed_showcase_model.py \
	    $(ROOT)/sw/apps/showcase/models/face $@ --name face \
	    --quantization $(ROOT)/sw/apps/showcase/models/face/quantization.json \
	    --classes 1 --points 5

# T-DEMO-PAGES: immutable doodle compiler snapshot.
PROGRAM_SOURCES += build/showcase/doodle_model.c
$(ROOT)/build/showcase/doodle_model.c: $(ROOT)/tools/sw/embed_showcase_model.py \
    $(wildcard $(ROOT)/sw/apps/showcase/models/doodle/*)
	python3 $(ROOT)/tools/sw/embed_showcase_model.py \
	    $(ROOT)/sw/apps/showcase/models/doodle $@ --name doodle \
	    --quantization $(ROOT)/sw/apps/showcase/models/doodle/quantization.json \
	    --classes 20 --points 0

# T-DEMO-PAGES: immutable helmet compiler snapshot.
PROGRAM_SOURCES += build/showcase/helmet_model.c
$(ROOT)/build/showcase/helmet_model.c: $(ROOT)/tools/sw/embed_showcase_model.py \
    $(wildcard $(ROOT)/sw/apps/showcase/models/helmet/*)
	python3 $(ROOT)/tools/sw/embed_showcase_model.py \
	    $(ROOT)/sw/apps/showcase/models/helmet $@ --name helmet \
	    --quantization $(ROOT)/sw/apps/showcase/models/helmet/quantization.json \
	    --classes 2 --points 0

# T-GAME-SLING: original alpha sprites, generated ARGB8888 descriptors.
PROGRAM_SOURCES += build/showcase/sling_images.c
$(ROOT)/build/showcase/sling_images.c: $(ROOT)/tools/sw/embed_showcase_images.py \
    $(ROOT)/tools/sw/png2c.py $(wildcard $(ROOT)/sw/apps/showcase/assets/sling/*.png)
	python3 $(ROOT)/tools/sw/embed_showcase_images.py \
	    $(ROOT)/sw/apps/showcase/assets/sling $@ --prefix sling

# T-FACE-STICKER-R2: offline rotations; RND scales immutable ARGB8888 art.
SHOWCASE_STICKERS := $(ROOT)/sw/apps/showcase/assets/stickers
PROGRAM_SOURCES += build/showcase/stickers.c
$(ROOT)/build/showcase/stickers.c: $(wildcard $(SHOWCASE_STICKERS)/*.png) \
    $(ROOT)/tools/sw/rotate_showcase_stickers.py $(ROOT)/tools/sw/embed_showcase_images.py \
    $(ROOT)/tools/sw/png2c.py
	python3 $(ROOT)/tools/sw/rotate_showcase_stickers.py $(SHOWCASE_STICKERS) \
	    $(ROOT)/build/showcase/sticker-frames
	python3 $(ROOT)/tools/sw/embed_showcase_images.py $(ROOT)/build/showcase/sticker-frames \
	    $@ --prefix sticker

# T-GAMES-MORE: separate original alpha packs for each arcade game.
SHOWCASE_ARCADE_ART := rps mole slice catch
PROGRAM_SOURCES += $(addprefix build/showcase/,$(addsuffix _images.c,$(SHOWCASE_ARCADE_ART)))
define SHOWCASE_ARCADE_IMAGE_RULE
$(ROOT)/build/showcase/$(1)_images.c: $(ROOT)/tools/sw/embed_showcase_images.py \
    $(ROOT)/tools/sw/png2c.py $(wildcard $(ROOT)/sw/apps/showcase/assets/$(1)/*.png)
	python3 $(ROOT)/tools/sw/embed_showcase_images.py \
	    $(ROOT)/sw/apps/showcase/assets/$(1) $$@ --prefix $(1)
endef
$(foreach art,$(SHOWCASE_ARCADE_ART),$(eval $(call SHOWCASE_ARCADE_IMAGE_RULE,$(art))))

# T-UI-FRAME: checked-in Bold subsets and original 96px application artwork.
PROGRAM_SOURCES += $(patsubst $(ROOT)/%,%,$(wildcard $(ROOT)/sw/apps/showcase/fonts/showcase_*.c))
PROGRAM_SOURCES += build/showcase/home_images.c
$(ROOT)/build/showcase/home_images.c: $(ROOT)/tools/sw/embed_showcase_images.py \
    $(ROOT)/tools/sw/png2c.py $(wildcard $(ROOT)/sw/apps/showcase/assets/icons/*.png)
	python3 $(ROOT)/tools/sw/embed_showcase_images.py \
	    $(ROOT)/sw/apps/showcase/assets/icons $@ --prefix home

# T-TOWER-GAME: zero-degree art; CPU generates only selected rotation frames at entry.
PROGRAM_SOURCES += build/showcase/tower_images.c
$(ROOT)/build/showcase/tower_images.c: $(ROOT)/tools/sw/embed_showcase_images.py \
    $(ROOT)/tools/sw/png2c.py $(wildcard $(ROOT)/sw/apps/showcase/assets/tower/*.png)
	python3 $(ROOT)/tools/sw/embed_showcase_images.py \
	    $(ROOT)/sw/apps/showcase/assets/tower $@ --prefix tower
