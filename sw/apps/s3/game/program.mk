# Included by sw/apps/s3/program.mk; resource generation belongs to build/ only.
PROGRAM_SOURCES += sw/apps/s3/game/game.c sw/apps/s3/game/game_logic.c \
                   sw/apps/s3/game/game_render.c build/s3/game/game_assets.c
CFLAGS_EXTRA += -I$(ROOT)/build/s3/game -I$(ROOT)/sw/apps/s3/game

$(ROOT)/build/s3/game/game_assets.c: $(ROOT)/tools/s3/game_assets.py
	cd $(ROOT) && python3 tools/s3/game_assets.py

$(OUT)/obj/sw/apps/s3/game/game_logic.o \
$(OUT)/obj/sw/apps/s3/game/game_render.o: $(ROOT)/build/s3/game/game_assets.c
