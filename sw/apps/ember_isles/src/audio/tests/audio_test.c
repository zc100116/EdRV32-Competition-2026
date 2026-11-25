/* File: audio_test.c
 * Spec: ember_isles tech 3-5 and G-2.7 acceptance.
 * Description: Reset/chunk/loop equality, 13 cues, outcome routing and master
 * volume; export all three complete stage loops and cue audition WAVs.
 * Clock domain: offline 48 kHz stereo stream.
 */
#include "audio.h"
#include "../../core/core.h"
#include "music.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { CUE_FRAMES = 96000 };
static uint32_t baseline[CUE_FRAMES];
static uint32_t cue[CUE_FRAMES];
static uint32_t actual[CUE_FRAMES];
static const unsigned chunks[] = {1, 8, 257, 800, 1024};

static void require(int condition, const char *message)
{
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message);
        exit(1);
    }
}
static void little32(FILE *file, uint32_t value)
{
    for (unsigned i = 0; i < 4; ++i) require(fputc((value >> (i * 8)) & 255, file) != EOF,
                                           "write WAV integer");
}
static void save(const char *path, const uint32_t *samples, unsigned frames)
{
    FILE *file = fopen(path, "wb");
    require(file != NULL, "open WAV output");
    require(fwrite("RIFF", 1, 4, file) == 4, "write RIFF");
    little32(file, 36 + frames * 4);
    require(fwrite("WAVEfmt ", 1, 8, file) == 8, "write WAV format");
    little32(file, 16);
    little32(file, 0x00020001);
    little32(file, 48000);
    little32(file, 192000);
    little32(file, 0x00100004);
    require(fwrite("data", 1, 4, file) == 4, "write WAV data marker");
    little32(file, frames * 4);
    for (unsigned i = 0; i < frames; ++i) little32(file, samples[i]);
    require(fclose(file) == 0, "close WAV output");
}
static void stream_equal(const uint32_t *reference, unsigned frames)
{
    unsigned offset = 0;
    for (unsigned i = 0; offset < frames; ++i) {
        unsigned count = chunks[i % 5];
        if (count > frames - offset) count = frames - offset;
        ember_audio_mix(actual, count);
        require(memcmp(reference + offset, actual, count * sizeof(*actual)) == 0,
                "arbitrary mix blocks reproduce reference exactly");
        offset += count;
    }
}
int main(void)
{
    ember_audio_volume(100);
    for (unsigned stage = 0; stage < 3; ++stage) {
        unsigned frames = ember_audio_clips[stage].frames + 96000;
        uint32_t *reference = malloc(frames * sizeof(*reference));
        require(reference != NULL, "allocate full loop reference");
        ember_audio_stage(stage);
        ember_audio_reset();
        ember_audio_mix(reference, frames);
        ember_audio_reset();
        stream_equal(reference, frames);
        int peak = 0;
        unsigned stereo = 0;
        for (unsigned i = 0; i < frames; ++i) {
            int l = (int16_t)reference[i];
            int r = (int16_t)(reference[i] >> 16);
            if (abs(l) > peak) peak = abs(l);
            if (abs(r) > peak) peak = abs(r);
            stereo += l != r;
        }
        require(peak > 0 && peak < 11000 && stereo, "audible stereo, music headroom");
        require(memcmp(reference, reference + ember_audio_clips[stage].frames,
                       96000 * sizeof(*reference)) == 0, "loop repeats exactly");
        char path[128];
        snprintf(path, sizeof(path), "outputs/ember_isles/audio/stage-%u.wav", stage);
        save(path, reference, frames);
        printf("stage %u: loop %u frames, peak %d, stereo frames %u\n", stage,
               ember_audio_clips[stage].frames, peak, stereo);
        free(reference);
    }
    ember_audio_stage(0);
    ember_audio_reset();
    ember_audio_mix(baseline, CUE_FRAMES);
    for (unsigned event = 0; event < 13; ++event) {
        ember_audio_reset();
        ember_audio_event(event);
        ember_audio_mix(cue, CUE_FRAMES);
        require(memcmp(cue, baseline, sizeof(cue)) != 0, "each cue is audible");
        unsigned end = ember_audio_clips[3 + event].frames;
        require(memcmp(cue + end, baseline + end, sizeof(cue) - end * 4) == 0,
                "effect completion preserves music position");
        ember_audio_reset();
        ember_audio_event(event);
        stream_equal(cue, CUE_FRAMES);
        char path[128];
        snprintf(path, sizeof(path), "outputs/ember_isles/audio/cue-%02u.wav", event);
        save(path, cue, CUE_FRAMES);
    }
    for (unsigned kind = 1; kind <= 8; kind += 7) {
        ember_audio_reset();
        ember_audio_result(kind, 1, 1);
        ember_audio_mix(actual, CUE_FRAMES);
        require(memcmp(actual, baseline, sizeof(actual)) == 0, "dodge is silent");
        ember_audio_reset();
        ember_audio_result(kind, 1, 2);
        ember_audio_mix(actual, CUE_FRAMES);
        ember_audio_reset();
        ember_audio_event(11);
        ember_audio_mix(cue, CUE_FRAMES);
        require(memcmp(actual, cue, sizeof(actual)) == 0, "block routes to bell");
    }
    ember_audio_reset();
    ember_audio_result(1, 1, 0);
    ember_audio_mix(actual, CUE_FRAMES);
    ember_audio_reset();
    ember_audio_event(12);
    ember_audio_mix(cue, CUE_FRAMES);
    require(memcmp(actual, cue, sizeof(actual)) == 0, "damage type reaches mixer");
    for (unsigned kind = EMBER_EVENT_PICKUP; kind <= EMBER_EVENT_WEAPON_CHANGE; ++kind) {
        ember_audio_reset();
        ember_audio_result(kind, 0, 0);
        ember_audio_mix(actual, CUE_FRAMES);
        ember_audio_reset();
        ember_audio_event(kind == EMBER_EVENT_PICKUP ? 10 : 7);
        ember_audio_mix(cue, CUE_FRAMES);
        require(memcmp(actual, cue, sizeof(actual)) == 0, "pickup/weapon-change events");
    }
    ember_audio_volume(0);
    ember_audio_reset();
    ember_audio_event(5);
    ember_audio_mix(actual, CUE_FRAMES);
    for (unsigned i = 0; i < CUE_FRAMES; ++i) require(actual[i] == 0, "master mute");
    ember_audio_volume(50);
    ember_audio_reset();
    ember_audio_mix(actual, CUE_FRAMES);
    for (unsigned i = 0; i < CUE_FRAMES; ++i) {
        require((int16_t)actual[i] == (int16_t)baseline[i] / 2 &&
                (int16_t)(actual[i] >> 16) == (int16_t)(baseline[i] >> 16) / 2,
                "master half volume scales both channels");
    }
    ember_audio_volume(100);
    ember_audio_reset();
    for (unsigned frame = 0; frame < 2400; ++frame) {
        for (unsigned i = 0; i < 4; ++i) ember_audio_event((frame + i) % 13);
        ember_audio_mix(actual, 800);
        for (unsigned i = 0; i < 800; ++i)
            require(abs((int16_t)actual[i]) < 30000 &&
                    abs((int16_t)(actual[i] >> 16)) < 30000, "four voice headroom");
    }
    puts("PASS: three full loops; reset/chunk equality; 13 cues; dodge/block/type; "
         "mute/half/full volume; 40 s four-effect run; listening NOT verified");
    return 0;
}
