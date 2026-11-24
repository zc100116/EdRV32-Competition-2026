/* File: audio_test.c
 * Spec: ember_isles tech 3, 5-6; aud-spec 2.1.
 * Description: Host checks for reset, streaming across the score loop and all
 * ten audible/distinct event cues. Writes raw PCM for review under build/.
 * Clock domain: deterministic offline 48 kHz stream.
 */
#include "audio.h"
#include "music.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { LOOP_FRAMES = 960000, FRAMES = LOOP_FRAMES + 800, CUE_FRAMES = 72000 };
static uint32_t reference[FRAMES];
static uint32_t actual[FRAMES];
static uint32_t cues[10][CUE_FRAMES];

static void require(int condition, const char *message)
{
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message);
        exit(1);
    }
}

static void save(const char *path, const uint32_t *samples, unsigned frames)
{
    FILE *file = fopen(path, "wb");
    require(file != NULL, "open PCM output");
    require(fwrite(samples, sizeof(*samples), frames, file) == frames, "write PCM output");
    require(fclose(file) == 0, "close PCM output");
}

int main(void)
{
    for (unsigned i = 0; i < EMBER_MUSIC_VOICES; ++i) {
        unsigned duration = 0;
        for (unsigned j = 0; j < ember_music[i].count; ++j)
            duration += ember_music[i].notes[j].frames;
        require(duration == LOOP_FRAMES, "all score tracks last eight bars");
    }
    ember_audio_reset();
    ember_audio_mix(reference, FRAMES);
    ember_audio_reset();
    unsigned offset = 0;
    static const unsigned chunks[] = {1, 8, 257, 800, 1024};
    for (unsigned i = 0; offset < FRAMES; ++i) {
        unsigned count = chunks[i % 5];
        if (count > FRAMES - offset) count = FRAMES - offset;
        ember_audio_mix(actual + offset, count);
        offset += count;
    }
    require(memcmp(reference, actual, sizeof(reference)) == 0,
            "reset and arbitrary mixing chunks reproduce the stream across a loop");
    int peak = 0;
    unsigned stereo_differences = 0;
    for (unsigned i = 0; i < FRAMES; ++i) {
        int left = (int16_t)(uint16_t)reference[i];
        int right = (int16_t)(uint16_t)(reference[i] >> 16);
        if (abs(left) > peak) peak = abs(left);
        if (abs(right) > peak) peak = abs(right);
        stereo_differences += left != right;
    }
    require(peak > 0 && stereo_differences > 0, "music is audible stereo");
    save("build/ember_isles/audio-music.s16le", reference, LOOP_FRAMES);
    for (unsigned event = 0; event < 10; ++event) {
        ember_audio_reset();
        ember_audio_event(event);
        ember_audio_mix(cues[event], CUE_FRAMES);
        require(memcmp(cues[event], reference, sizeof(cues[event])) != 0,
                "each event changes the music output");
        require(memcmp(cues[event] + 57600, reference + 57600,
                       (CUE_FRAMES - 57600) * sizeof(uint32_t)) == 0,
                "each completed cue leaves the continuing music unchanged");
        ember_audio_reset();
        ember_audio_event(event);
        offset = 0;
        for (unsigned i = 0; offset < CUE_FRAMES; ++i) {
            unsigned count = chunks[i % 5];
            if (count > CUE_FRAMES - offset) count = CUE_FRAMES - offset;
            ember_audio_mix(actual + offset, count);
            offset += count;
        }
        require(memcmp(cues[event], actual, sizeof(cues[event])) == 0,
                "effect reset and chunking are deterministic");
        for (unsigned previous = 0; previous < event; ++previous)
            require(memcmp(cues[event], cues[previous], sizeof(cues[event])) != 0,
                    "event cues are distinct");
    }
    save("build/ember_isles/audio-cues.s16le", &cues[0][0], 10 * CUE_FRAMES);
    ember_audio_reset();
    for (unsigned frame = 0; frame < 2400; ++frame) {
        ember_audio_event(frame % 10);
        ember_audio_mix(actual, 800);
    }
    printf("PASS: 3 tracks, 20 s loop, 10 distinct cues, reset/chunk equality, "
           "40 s overlapping-event run; music peak %d; stereo frames %u\n",
           peak, stereo_differences);
    return 0;
}
