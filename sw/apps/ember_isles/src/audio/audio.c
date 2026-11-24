/* File: audio.c
 * Spec: ember_isles tech 2, 3, 5-6; aud-spec 2.1.
 * Description: Integer wavetable/noise voices with 32-sample envelope/pan updates,
 * original coastal sequence and ten layered game effects. No platform access.
 * Clock domain: caller-owned 48 kHz stream, independent of game frame size.
 */
#include "audio.h"
#include "music.h"
#include <string.h>

enum {
    SQUARE, TRIANGLE, NOISE, EFFECT_VOICES = 4, ATTACK_FRAMES = 240,
    BLOCK_FRAMES = 32, MIX_FRAMES = 256
};
#define HZ(hz) ((uint32_t)(((uint64_t)(hz) << 32) / 48000u))

struct voice {
    uint32_t phase;
    uint32_t step;
    uint32_t noise;
    uint32_t block_step;
    int32_t glide;
    int32_t gain;
    int32_t peak;
    int32_t rise;
    int32_t fall;
    unsigned attack;
    unsigned frames;
    unsigned wave;
    unsigned pan;
    unsigned block_left;
    int left_gain;
    int right_gain;
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
static int8_t waves[2][256];

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
    v->block_left = 0;
}

static void start_effect(unsigned slot)
{
    const struct effect_note *n = &effects[effect_ids[slot]].notes[effect_notes[slot]++];
    start_voice(&effect_voices[slot], n->start, n->end, n->frames,
                n->peak, n->wave, n->pan);
}

/* Control blocks belong to each voice, so splitting mix calls cannot move an
 * envelope or pitch update. Note and attack boundaries still land on exact samples. */
static void control_voice(struct voice *v)
{
    unsigned count = BLOCK_FRAMES;
    if (count > v->frames) count = v->frames;
    if (v->attack && count > v->attack) count = v->attack;
    int change = v->attack ? v->rise : -v->fall;
    int gain = (v->gain + change * (int)(count / 2)) >> 12;
    v->left_gain = gain * (int)(256 - v->pan) >> 8;
    v->right_gain = gain * (int)v->pan >> 8;
    v->gain += change * (int)count;
    if (v->attack) {
        v->attack -= count;
        if (v->attack == 0) v->gain = v->peak;
    }
    v->block_step = v->step + (uint32_t)(v->glide * (int)(count / 2));
    v->step += (uint32_t)(v->glide * (int)count);
    v->block_left = count;
}

static void mix_voice(struct voice *v, int *left, int *right, int *middle, unsigned count)
{
    if (v->peak == 0) {
        v->frames -= count;
        return;
    }
    unsigned offset = 0;
    while (offset < count && v->frames) {
        if (v->block_left == 0) control_voice(v);
        unsigned n = count - offset;
        if (n > v->block_left) n = v->block_left;
        uint32_t phase = v->phase;
        uint32_t step = v->block_step;
        int lg = v->left_gain;
        int rg = v->right_gain;
        /* Centered voices share a mono bus. Small unrolled loops amortize RV32
         * loop branches; oscillator, gain and pan selection stay outside them. */
        if (lg == rg && v->wave != NOISE) {
            const int8_t *table = waves[v->wave];
#pragma GCC unroll 4
            for (unsigned j = offset; j < offset + n; ++j) {
                phase += step;
                int value = table[phase >> 24];
                middle[j] += value * lg >> 7;
            }
        } else if (lg == rg) {
            uint32_t noise = v->noise;
#pragma GCC unroll 4
            for (unsigned j = offset; j < offset + n; ++j) {
                noise ^= noise << 13;
                noise ^= noise >> 17;
                noise ^= noise << 5;
                int value = (int)(noise >> 24) - 128;
                middle[j] += value * lg >> 7;
            }
            v->noise = noise;
        } else if (v->wave == NOISE) {
            uint32_t noise = v->noise;
#pragma GCC unroll 4
            for (unsigned j = offset; j < offset + n; ++j) {
                noise ^= noise << 13;
                noise ^= noise >> 17;
                noise ^= noise << 5;
                int value = (int)(noise >> 24) - 128;
                left[j] += value * lg >> 7;
                right[j] += value * rg >> 7;
            }
            v->noise = noise;
        } else {
            const int8_t *table = waves[v->wave];
#pragma GCC unroll 4
            for (unsigned j = offset; j < offset + n; ++j) {
                phase += step;
                int value = table[phase >> 24];
                left[j] += value * lg >> 7;
                right[j] += value * rg >> 7;
            }
        }
        v->phase = phase;
        v->frames -= n;
        v->block_left -= n;
        offset += n;
    }
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
    for (unsigned i = 0; i < 256; ++i) {
        waves[SQUARE][i] = i < 128 ? 127 : -128;
        waves[TRIANGLE][i] = (int8_t)((int)(i < 128 ? i : 255 - i) * 2 - 128);
    }
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
    while (frames) {
        unsigned count = frames < MIX_FRAMES ? frames : MIX_FRAMES;
        int left[MIX_FRAMES] = {0};
        int right[MIX_FRAMES] = {0};
        int middle[MIX_FRAMES] = {0};
        /* End this shared work span at the nearest note boundary. */
        for (unsigned i = 0; i < EMBER_MUSIC_VOICES; ++i) {
            struct voice *v = &music_voices[i];
            const struct ember_music_track *track = &ember_music[i];
            if (v->frames == 0) {
                const struct ember_music_note *n = &track->notes[music_notes[i]];
                if (++music_notes[i] == track->count) music_notes[i] = 0;
                start_voice(v, n->step, n->step, n->frames,
                            n->step ? track->peak : 0, track->wave, track->pan);
            }
            if (count > v->frames) count = v->frames;
        }
        for (unsigned i = 0; i < EFFECT_VOICES; ++i) {
            struct voice *v = &effect_voices[i];
            if (v->frames == 0 && effect_notes[i] < effects[effect_ids[i]].count)
                start_effect(i);
            if (v->frames && count > v->frames) count = v->frames;
        }
        for (unsigned i = 0; i < EMBER_MUSIC_VOICES; ++i)
            mix_voice(&music_voices[i], left, right, middle, count);
        for (unsigned i = 0; i < EFFECT_VOICES; ++i)
            if (effect_voices[i].frames) mix_voice(&effect_voices[i], left, right, middle, count);
        for (unsigned j = 0; j < count; ++j)
            stereo[j] = (uint16_t)(left[j] + middle[j]) |
                        (uint32_t)(uint16_t)(right[j] + middle[j]) << 16;
        stereo += count;
        frames -= count;
    }
}
