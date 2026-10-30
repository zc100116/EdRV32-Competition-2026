# File: program.mk
# Spec: SoC S3; Task B3-3b. Included by the S3 application's program.mk.
# All LVGL sources are compiled from the locked, unmodified v9.6.0 submodule.
S3_LVGL_SOURCES := $(shell cd $(ROOT) && find third_party/lvgl/src \
                    third_party/lvgl/demos/widgets third_party/lvgl/demos/benchmark \
                    -name '*.c' | sort)
PROGRAM_SOURCES += $(S3_LVGL_SOURCES) sw/apps/s3/lvgl/draw_rnd.c \
                   third_party/lvgl/demos/lv_demos.c \
                   sw/apps/s3/lvgl/s3_lvgl.c sw/apps/s3/lvgl/rn17_compare.c \
                   sw/apps/s3/lvgl/freestanding.c \
                   sw/drivers/mem_xbar.c \
                   build/s3/lvgl_assets.c
CFLAGS_EXTRA += -I$(ROOT)/third_party/lvgl -I$(ROOT)/sw/apps/s3/lvgl \
                -DLV_CONF_INCLUDE_SIMPLE
PROGRAM_LDLIBS += -Wl,--wrap=lv_draw_sw_blend
PROGRAM_LDLIBS += -Wl,--wrap=lv_draw_sw_init -Wl,--wrap=lv_draw_create_unit \
                 -Wl,--wrap=lv_timer_create

$(ROOT)/build/s3/lvgl_assets.c: $(ROOT)/tools/s3/lvgl_assets.py
	python3 $< $@
