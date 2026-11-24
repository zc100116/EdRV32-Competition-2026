/* File: game.c
 * Spec: ember_isles tech 2-3 and E3 systems.
 * Description: Fixed-step simulation, read-only presentation and audio submission.
 * Clock domain: 60 Hz game frame; 48 kHz audio ring.
 */
#include "game.h"
#include "gfx2d/gfx.h"
#include "audio/audio.h"
#include "ui/ui.h"
#include "plat.h"
#include "aud.h"
#include <stdlib.h>
#include <stdatomic.h>
static struct ember_sim simulation;
static struct aud_ring audio_ring;
static uint32_t samples[1024];
static uint32_t previous_millis;
static unsigned fps_frames, measured_fps = 60;
static unsigned tick_frames;
static uint32_t previous_tick_millis, tick_credit;
static struct ember_ui_state ui;
static uint16_t previous_keys;
static uint8_t previous_pointer_buttons;
static uint16_t pointer_confirm;
static unsigned replay_mode;
static uint32_t run_number;
static struct ember_replay recording;
/* The main loop publishes at most 256 events per frame. LOW refills every
 * 1024 samples; queue capacity covers the frames between LOW refills.
 * Only the refill service owns synthesizer state after startup. */
static uint8_t audio_events[1024];
static _Atomic unsigned audio_head, audio_tail;
static void queue_audio(unsigned event)
{
    unsigned head = atomic_load_explicit(&audio_head, memory_order_relaxed);
    audio_events[head % 1024] = (uint8_t)event;
    atomic_store_explicit(&audio_head, head + 1, memory_order_release);
}
static void refill(struct aud_ring *ring, const struct aud_event *event, void *context)
{
    (void)event;
    (void)context;
    unsigned tail = atomic_load_explicit(&audio_tail, memory_order_relaxed);
    unsigned head = atomic_load_explicit(&audio_head, memory_order_acquire);
    while (tail != head) {
        unsigned command = audio_events[tail % 1024];
        if (command == 10) ember_audio_reset();
        else ember_audio_event(command);
        ++tail;
    }
    atomic_store_explicit(&audio_tail, tail, memory_order_release);
    unsigned count = aud_space(ring) / 4u;
    if (count > 1024) count = 1024;
    count &= ~7u;
    ember_audio_mix(samples, count);
    aud_write(ring, samples, count);
}
static void audio_irq(void *context)
{
    (void)context;
    struct aud_event event = aud_irq_handle(&audio_ring);
    if (event.error) { plat_printf("AUD error %u\n", (unsigned)event.error); abort(); }
}
void ember_game_init(void)
{
    plat_init();
    ember_sim_init(&simulation, 20261124u);
    ember_audio_reset();
    ui.tick_rate = 60;
    ember_gfx_init();
    aud_init(&audio_ring, plat_dma_alloc(16384, 512), 16384, 4096);
    refill(&audio_ring, NULL, NULL);
    refill(&audio_ring, NULL, NULL);
    plat_irq_register(EDRV32_PLIC_SOURCE_AUD, audio_irq, NULL);
    aud_irq_register(1, refill, NULL);
    aud_enable(1);
    previous_tick_millis = previous_millis = plat_millis();
    tick_credit = 1000;
}
void ember_game_replay(uint32_t seed)
{
    replay_mode = 1;
    ember_sim_init(&simulation, seed);
}
const struct ember_replay *ember_game_recording(void) { return &recording; }
const struct ember_sim *ember_game_state(void) { return &simulation; }
/* Menu clicks become recorded keyboard commands; pointer coordinates never enter sim. */
static uint16_t menu_pointer_keys(void)
{
    struct plat_pointer_state pointer = plat_pointer();
    unsigned clicked = pointer.buttons & (uint8_t)~previous_pointer_buttons & 1u;
    previous_pointer_buttons = pointer.buttons;
    uint16_t keys = pointer_confirm;
    pointer_confirm = 0;
    if (!clicked) return keys;
    int x = pointer.x;
    int y = pointer.y;
    if (simulation.phase == EMBER_UPGRADE && y >= 132 && y < 272) {
        for (unsigned i = 0; i < 3; ++i) {
            int left = 40 + (int)i * 190;
            if (x < left || x >= left + 180) continue;
            unsigned delta = (i + 3 - simulation.selected) % 3;
            if (!delta) return EMBER_J;
            pointer_confirm = EMBER_J;
            return delta == 1 ? EMBER_RIGHT : EMBER_LEFT;
        }
    }
    if ((simulation.phase == EMBER_MENU || simulation.phase == EMBER_WON ||
         simulation.phase == EMBER_LOST) && x >= 218 && x < 422 && y >= 237 && y < 267)
        return EMBER_START;
    if (simulation.paused && x >= 218 && x < 422 && y >= 185 && y < 215)
        return EMBER_START;
    return keys;
}
void ember_game_tick(void)
{
    ++tick_frames;
    uint16_t keys = (uint16_t)plat_game_keys();
    if (!replay_mode) keys |= menu_pointer_keys();
    uint16_t pressed = keys & (uint16_t)~previous_keys;
    previous_keys = keys;
    if (pressed & EMBER_SELECT) ui.show_perf ^= 1;
    unsigned returned_to_menu = 0;
    if (!replay_mode && (pressed & EMBER_START)) {
        if (simulation.phase == EMBER_WON || simulation.phase == EMBER_LOST) {
            ember_sim_init(&simulation, recording.seed);
            simulation.previous_input = keys;
            returned_to_menu = 1;
        } else if (simulation.phase == EMBER_MENU) {
            recording.seed = 20261124u + ++run_number + plat_millis();
            recording.count = 0;
            ember_sim_init(&simulation, recording.seed);
            queue_audio(10);
        }
    }
    if (!replay_mode && !returned_to_menu && simulation.phase != EMBER_WON &&
        simulation.phase != EMBER_LOST &&
        (simulation.phase != EMBER_MENU || (pressed & EMBER_START))) {
        if (recording.count == EMBER_REPLAY_FRAMES) {
            plat_printf("Replay recording capacity exhausted\n");
            abort();
        }
        recording.input[recording.count++] = keys;
    }
    ember_sim_step(&simulation, keys);
    for (unsigned i = 0; i < simulation.events.count; ++i) {
        unsigned kind = simulation.events.item[i].kind;
        queue_audio(kind);
    }
}
void ember_game_render(unsigned frame)
{
    uint32_t now = plat_millis();
    ++fps_frames;
    if (now - previous_millis >= 1000) {
        measured_fps = fps_frames * 1000u / (now - previous_millis);
        ui.tick_rate = tick_frames * 1000u / (now - previous_millis);
        tick_frames = 0;
        previous_millis = now;
        fps_frames = 0;
    }
    ember_gfx_prepare(&simulation, measured_fps, &ui);
    ember_gfx_submit(frame);
}

void ember_game_frame(unsigned frame)
{
    ember_game_tick();
    ember_game_render(frame);
}
void ember_game_realtime(unsigned frame)
{
    uint32_t now = plat_millis();
    tick_credit += (now - previous_tick_millis) * 60u;
    previous_tick_millis = now;
    unsigned due = tick_credit / 1000u;
    tick_credit %= 1000u;
    /* Coordinator-approved limit: discard excess debt; the HUD exposes both
     * rates so sustained overload cannot silently reduce simulation speed. */
    for (unsigned i = 0; i < due && i < 4; ++i) ember_game_tick();
    ember_game_render(frame);
}
