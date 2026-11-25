/* File: audio.c
 * Spec: ember_isles tech 3-5, 7; GDD 2.3.8/11; aud-spec 2.1.
 * Description: Linked licensed 48 kHz stereo recordings, integer mu-law decode,
 * four effect voices and atomic main-volume/stage requests. No sim RNG access.
 * Clock domain: serialized 48 kHz stream; settings may be requested by main loop.
 */
#include "audio.h"
#include "../core/core.h"
#include "music.h"
#include <stdatomic.h>
#include <string.h>

__asm__(EMBER_AUDIO_ASSEMBLY);

enum { EFFECT_VOICES = 4, MUSIC_CLIPS = 3 };
struct voice {
    unsigned clip;
    unsigned position;
    unsigned remaining;
};
static struct voice voices[EFFECT_VOICES];
static unsigned next_voice;
static unsigned music_stage;
static unsigned music_position;
static _Atomic unsigned requested_stage;
static _Atomic unsigned master_volume = 100;

void ember_audio_reset(void)
{
    memset(voices, 0, sizeof(voices));
    next_voice = 0;
    music_position = 0;
    music_stage = atomic_load_explicit(&requested_stage, memory_order_relaxed);
}

void ember_audio_volume(unsigned percent)
{
    atomic_store_explicit(&master_volume, percent, memory_order_relaxed);
}

void ember_audio_stage(unsigned stage)
{
    atomic_store_explicit(&requested_stage, stage, memory_order_relaxed);
}

void ember_audio_event(unsigned event)
{
    struct voice *voice = &voices[next_voice];
    next_voice = (next_voice + 1) % EFFECT_VOICES;
    voice->clip = MUSIC_CLIPS + event;
    voice->position = 0;
    voice->remaining = ember_audio_clips[voice->clip].frames;
}

void ember_audio_result(unsigned kind, unsigned damage_type, unsigned outcome)
{
    if ((kind == EMBER_EVENT_HIT || kind == EMBER_EVENT_HURT) && outcome == 1) return;
    if ((kind == EMBER_EVENT_HIT || kind == EMBER_EVENT_HURT) && outcome == 2) {
        ember_audio_event(11);
    } else if (kind == EMBER_EVENT_HIT && damage_type != 0) {
        ember_audio_event(12);
    } else {
        static const unsigned cues[EMBER_EVENT_COUNT] = {
            [EMBER_EVENT_SHOT] = 0, [EMBER_EVENT_HIT] = 1, [EMBER_EVENT_KILL] = 2,
            [EMBER_EVENT_DASH] = 3, [EMBER_EVENT_SEED] = 4, [EMBER_EVENT_ULTIMATE] = 5,
            [EMBER_EVENT_LEVELUP] = 6, [EMBER_EVENT_CHOOSE] = 7, [EMBER_EVENT_HURT] = 8,
            [EMBER_EVENT_VICTORY] = 9, [EMBER_EVENT_PICKUP] = 10,
            [EMBER_EVENT_WEAPON_CHANGE] = 7
        };
        ember_audio_event(cues[kind]);
    }
}

void ember_audio_mix(uint32_t *stereo, unsigned frames)
{
    unsigned stage = atomic_load_explicit(&requested_stage, memory_order_relaxed);
    if (stage != music_stage) {
        music_stage = stage;
        music_position = 0;
    }
    const struct ember_audio_clip *music = &ember_audio_clips[music_stage];
    unsigned volume = atomic_load_explicit(&master_volume, memory_order_relaxed);
    unsigned offset = 0;
    while (offset < frames) {
        unsigned count = frames - offset;
        if (count > music->frames - music_position) count = music->frames - music_position;
        for (unsigned i = 0; i < EFFECT_VOICES; ++i)
            if (voices[i].remaining && count > voices[i].remaining) count = voices[i].remaining;
        const unsigned char *source = ember_audio_blob + music->offset + music_position * 2;
        int left[256];
        int right[256];
        if (count > 256) count = 256;
        for (unsigned j = 0; j < count; ++j) {
            left[j] = ember_ulaw[source[j * 2]];
            right[j] = ember_ulaw[source[j * 2 + 1]];
        }
        for (unsigned i = 0; i < EFFECT_VOICES; ++i) {
            struct voice *voice = &voices[i];
            if (!voice->remaining) continue;
            source = ember_audio_blob + ember_audio_clips[voice->clip].offset +
                     voice->position * 2;
            for (unsigned j = 0; j < count; ++j) {
                left[j] += ember_ulaw[source[j * 2]];
                right[j] += ember_ulaw[source[j * 2 + 1]];
            }
            voice->remaining -= count;
            voice->position += count;
        }
        for (unsigned j = 0; j < count; ++j) {
            int l = left[j] * (int)volume / 100;
            int r = right[j] * (int)volume / 100;
            stereo[offset + j] = (uint16_t)l | (uint32_t)(uint16_t)r << 16;
        }
        offset += count;
        music_position += count;
        if (music_position == music->frames) music_position = 0;
    }
}
