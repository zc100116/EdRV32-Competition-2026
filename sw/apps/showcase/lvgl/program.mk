# File: program.mk
# Design: showcase 4.3; locked LVGL v9.6.0, copied S3 drawing unit.
SHOWCASE_LVGL_SOURCES := $(shell cd $(ROOT) && find third_party/lvgl/src \
    third_party/lvgl/demos/widgets third_party/lvgl/demos/benchmark -name '*.c' | sort)
PROGRAM_SOURCES += $(SHOWCASE_LVGL_SOURCES) third_party/lvgl/demos/lv_demos.c \
    sw/apps/showcase/lvgl/draw_rnd.c sw/apps/showcase/lvgl/showcase_lvgl.c \
    sw/apps/showcase/lvgl/freestanding.c sw/drivers/mem_xbar.c \
    sw/apps/showcase/fonts/title_24.c sw/apps/showcase/fonts/title_32.c \
    build/showcase/lvgl_assets.c
CFLAGS_EXTRA += -I$(ROOT)/third_party/lvgl -I$(ROOT)/sw/apps/showcase/lvgl \
    -DLV_CONF_INCLUDE_SIMPLE
PROGRAM_LDLIBS += -Wl,--wrap=lv_draw_sw_init \
    -Wl,--wrap=lv_draw_create_unit -Wl,--wrap=lv_timer_create
$(ROOT)/build/showcase/lvgl_assets.c: $(ROOT)/tools/s3/lvgl_assets.py
	python3 $< $@
