/* File: audio.h
 * Spec: ember_isles tech 2, 5-6; aud-spec 2.1.
 * Description: Platform-independent E1/E2 synthesizer interface.
 * Clock domain: caller-owned, serialized 48 kHz sample stream.
 */
#ifndef EMBER_AUDIO_H
#define EMBER_AUDIO_H

#include <stdint.h>

/* Reset starts the original coastal music loop and clears all effects. */
void ember_audio_reset(void);
/* Valid events: 0 shot, 1 hit, 2 kill, 3 dash, 4 seed, 5 ultimate,
 * 6 levelup, 7 choose, 8 hurt, 9 victory. Calls are serialized with mix.
 * Four effect voices rotate in event order; a new event replaces that voice. */
void ember_audio_event(unsigned event);
/* Write frames packed as signed 16-bit left (low) and right (high), at 48 kHz.
 * Calls of any frame count continue the same sample-accurate music stream. */
void ember_audio_mix(uint32_t *stereo, unsigned frames);

#endif
