/* File: audio.h
 * Spec: ember_isles tech 3-5, GDD 2.3 and 7; aud-spec 2.1.
 * Description: Common PC/board recording mixer and presentation-event interface.
 * Clock domain: serialized 48 kHz stream; volume/stage requests are atomic.
 */
#ifndef EMBER_AUDIO_H
#define EMBER_AUDIO_H
#include <stdint.h>

/* Clear effects and restart the requested stage; preserve the chosen volume. */
void ember_audio_reset(void);
/* Main-loop settings interface: percent is 0..100, initially 100. */
void ember_audio_volume(unsigned percent);
/* Stage rows in assets/music/stages.csv: 0 coast, 1 forest, 2 crater.
 * A change starts the new track at the next mix call. */
void ember_audio_stage(unsigned stage);
/* Cues: 0 shot, 1 physical hit, 2 kill, 3 dash, 4 seed, 5 explosion,
 * 6 levelup, 7 choose/swap, 8 hurt, 9 victory, 10 pickup, 11 block,
 * 12 elemental hit. Four voices rotate; a new cue replaces that voice. */
void ember_audio_event(unsigned event);
/* Preserve sim metadata: damage_type 0 iron, 1..5 elemental/true;
 * outcome 0 hit, 1 dodge (silent), 2 block (bell). Sim PICKUP and
 * WEAPON_CHANGE route to pickup/choose; subtypes share these cues. */
void ember_audio_result(unsigned kind, unsigned damage_type, unsigned outcome);
/* Packed signed PCM16: left low, right high. Arbitrary block sizes continue
 * the same sample stream, including across track loop and effect boundaries. */
void ember_audio_mix(uint32_t *stereo, unsigned frames);
#endif
