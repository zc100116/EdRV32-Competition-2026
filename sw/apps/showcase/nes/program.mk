# program.mk: showcase design 4.4; include after the showcase GUI build fragment.
# Reuse the patched core rules; old standalone NES files remain untouched.
include $(ROOT)/sw/apps/showcase/nes/sources.mk
PROGRAM_SOURCES += $(NES_CORE) $(NES_COMMON) sw/apps/showcase/nes/app.c \
    sw/apps/showcase/nes/display.c sw/apps/showcase/nes/display_command.c \
    sw/apps/showcase/nes/syscalls.c
CFLAGS_EXTRA += $(NES_FLAGS)
PROGRAM_LDLIBS += -Wl,--start-group -lc -lm -lgcc -Wl,--end-group
