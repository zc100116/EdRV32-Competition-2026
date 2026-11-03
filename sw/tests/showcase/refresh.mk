# Run from showcase/sim with -f Makefile -f ../../../tests/showcase/refresh.mk.
.PHONY: measure-vision
measure-vision: $(BUILD)/vision_refresh
	$(BUILD)/vision_refresh
$(BUILD)/vision_refresh: ../../../tests/showcase/vision_refresh.c $(COMMON) $(UI_HEADERS) $(LINUX_LV)
	$(CC) $(FLAGS) -Werror $< $(COMMON) $(LINUX_LV) -lm \
	    -Wl,--wrap=lv_draw_sw_init -Wl,--wrap=lv_draw_create_unit -o $@
