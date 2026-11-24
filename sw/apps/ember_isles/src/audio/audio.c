/* File: audio.c
 * Spec: ember_isles tech 2, 3, 5-6; aud-spec 2.1.
 * Description: Integer square/triangle/noise voices, attack/decay envelopes,
 * original coastal sequence and ten layered game effects. No platform access.
 * Clock domain: caller-owned 48 kHz stream, independent of game frame size.
 */
#include "audio.h"
#include "music.h"
#include <string.h>

enum { SQUARE, TRIANGLE, NOISE, EFFECT_VOICES = 4, ATTACK_FRAMES = 240 };
#define HZ(hz) ((uint32_t)(((uint64_t)(hz) << 32) / 48000u))

struct voice {
    uint32_t phase;
    uint32_t step;
    uint32_t noise;
    int32_t glide;
    int32_t gain;
    int32_t peak;
    int32_t rise;
    int32_t fall;
    unsigned attack;
    unsigned frames;
    unsigned wave;
    unsigned pan;
};

struct effect_note {
    uint32_t start;
    uint32_t end;
    unsigned frames;
    int peak;
    unsigned wave;
    unsigned pan;
};

struct effect {
    unsigned count;
    struct effect_note notes[4];
};

/* Original cues: ember chirp, impact, falling cinder, rush, planted seed,
 * furnace blast, rising bells, confirmation, low hurt buzz, lighthouse fanfare.
 * Peak sum <= 3170 music + 4*3600 effects, below signed PCM full scale.
 */
static const struct effect effects[10] = {
    {1, {{HZ(1100), HZ(320), 2880, 1900, SQUARE, 112}}},
    {1, {{0, 0, 2160, 2600, NOISE, 144}}},
    {2, {{HZ(660), HZ(330), 3840, 2100, TRIANGLE, 144},
         {HZ(220), HZ(110), 4320, 1300, TRIANGLE, 112}}},
    {1, {{0, 0, 7200, 1900, NOISE, 176}}},
    {2, {{HZ(220), HZ(440), 3840, 2000, TRIANGLE, 96},
         {HZ(880), HZ(880), 5760, 1500, SQUARE, 160}}},
    {3, {{HZ(80), HZ(180), 5760, 3600, TRIANGLE, 128},
         {0, 0, 11520, 3300, NOISE, 128},
         {HZ(110), HZ(45), 14400, 2600, TRIANGLE, 128}}},
    {3, {{HZ(587), HZ(587), 4800, 2100, TRIANGLE, 80},
         {HZ(740), HZ(740), 4800, 2100, TRIANGLE, 128},
         {HZ(880), HZ(880), 14400, 2400, TRIANGLE, 176}}},
    {2, {{HZ(660), HZ(660), 2160, 1400, SQUARE, 128},
         {HZ(880), HZ(880), 3840, 1600, TRIANGLE, 128}}},
    {1, {{HZ(150), HZ(55), 10560, 2900, SQUARE, 128}}},
    {4, {{HZ(587), HZ(587), 7200, 2400, TRIANGLE, 96},
         {HZ(698), HZ(698), 7200, 2400, TRIANGLE, 160},
         {HZ(880), HZ(880), 7200, 2600, TRIANGLE, 96},
         {HZ(1175), HZ(1175), 28800, 2800, TRIANGLE, 160}}}
};

static struct voice music_voices[EMBER_MUSIC_VOICES];
static unsigned music_notes[EMBER_MUSIC_VOICES];
static struct voice effect_voices[EFFECT_VOICES];
static unsigned effect_ids[EFFECT_VOICES];
static unsigned effect_notes[EFFECT_VOICES];
static unsigned next_effect;

static void start_voice(struct voice *v, uint32_t start, uint32_t end, unsigned frames,
                        int peak, unsigned wave, unsigned pan)
{
    v->phase = 0;
    v->step = start;
    v->glide = ((int32_t)end - (int32_t)start) / (int32_t)frames;
    v->gain = 0;
    v->peak = peak * 4096;
    v->rise = v->peak / ATTACK_FRAMES;
    v->fall = v->peak / (int32_t)(frames - ATTACK_FRAMES);
    v->attack = ATTACK_FRAMES;
    v->frames = frames;
    v->wave = wave;
    v->pan = pan;
}

static void start_effect(unsigned slot)
{
    const struct effect_note *n = &effects[effect_ids[slot]].notes[effect_notes[slot]++];
    start_voice(&effect_voices[slot], n->start, n->end, n->frames,
                n->peak, n->wave, n->pan);
}

static int sample_voice(struct voice *v)
{
    int wave;
    v->phase += v->step;
    v->step += (uint32_t)v->glide;
    if (v->wave == NOISE) {
        v->noise ^= v->noise << 13;
        v->noise ^= v->noise >> 17;
        v->noise ^= v->noise << 5;
        wave = (int)(v->noise >> 24) - 128;
    } else if (v->wave == TRIANGLE) {
        unsigned ramp = v->phase >> 23;
        wave = (int)(ramp < 256 ? ramp : 511 - ramp) - 128;
    } else {
        wave = v->phase < UINT32_C(0x80000000) ? 127 : -128;
    }
    int value = wave * v->gain / 524288;
    if (v->attack) {
        v->gain += v->rise;
        if (--v->attack == 0) v->gain = v->peak;
    } else {
        v->gain -= v->fall;
    }
    --v->frames;
    return value;
}

void ember_audio_reset(void)
{
    memset(music_voices, 0, sizeof(music_voices));
    memset(music_notes, 0, sizeof(music_notes));
    memset(effect_voices, 0, sizeof(effect_voices));
    for (unsigned i = 0; i < EMBER_MUSIC_VOICES; ++i)
        music_voices[i].noise = UINT32_C(0x6d2b79f5) + i;
    for (unsigned i = 0; i < EFFECT_VOICES; ++i) {
        effect_voices[i].noise = UINT32_C(0x1b873593) + i;
        effect_ids[i] = 0;
        effect_notes[i] = effects[0].count;
    }
    next_effect = 0;
}

void ember_audio_event(unsigned event)
{
    unsigned slot = next_effect;
    next_effect = (next_effect + 1) % EFFECT_VOICES;
    effect_ids[slot] = event;
    effect_notes[slot] = 0;
    start_effect(slot);
}

void ember_audio_mix(uint32_t *stereo, unsigned frames)
{
    for (unsigned frame = 0; frame < frames; ++frame) {
        int left = 0;
        int right = 0;
        for (unsigned i = 0; i < EMBER_MUSIC_VOICES; ++i) {
            struct voice *v = &music_voices[i];
            const struct ember_music_track *track = &ember_music[i];
            if (v->frames == 0) {
                const struct ember_music_note *n = &track->notes[music_notes[i]];
                if (++music_notes[i] == track->count) music_notes[i] = 0;
                start_voice(v, n->step, n->step, n->frames,
                            n->step ? track->peak : 0, track->wave, track->pan);
            }
            int value = sample_voice(v);
            left += value * (int)(256 - v->pan) / 256;
            right += value * (int)v->pan / 256;
        }
        for (unsigned i = 0; i < EFFECT_VOICES; ++i) {
            struct voice *v = &effect_voices[i];
            if (v->frames == 0 && effect_notes[i] < effects[effect_ids[i]].count)
                start_effect(i);
            if (v->frames) {
                int value = sample_voice(v);
                left += value * (int)(256 - v->pan) / 256;
                right += value * (int)v->pan / 256;
            }
        }
        stereo[frame] = (uint16_t)left | (uint32_t)(uint16_t)right << 16;
    }
}
