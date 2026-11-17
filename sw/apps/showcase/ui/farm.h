/* farm.h — R5-4; camera-independent farm counts, timed alerts and daily samples.
 * Caller supplies frame coordinates and monotonic milliseconds; no LVGL ownership.
 */
#ifndef SHOWCASE_FARM_H
#define SHOWCASE_FARM_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
enum { FARM_PENS=3, FARM_CLASSES=4, FARM_EVENTS=20, FARM_SAMPLES=60, FARM_PAGE=19 };
typedef struct { unsigned class_id; int x, y, width, height; } farm_box_t;
typedef struct {
    uint32_t time_ms;
    unsigned pen, animal, amount;
    bool crossing, active;
} farm_event_t;
typedef struct { uint32_t time_ms; unsigned total[FARM_CLASSES]; } farm_sample_t;
typedef struct { uint32_t since; bool pending, active; } farm_alarm_t;
typedef struct {
    unsigned counts[FARM_PENS][FARM_CLASSES];
    unsigned expected[FARM_PENS][FARM_CLASSES];
    unsigned total[FARM_CLASSES];
    farm_alarm_t missing[FARM_PENS][FARM_CLASSES];
    farm_alarm_t crossing[FARM_PENS][FARM_CLASSES];
    farm_event_t events[FARM_EVENTS];
    farm_sample_t samples[FARM_SAMPLES];
    unsigned event_head, event_count, event_revision;
    unsigned sample_head, sample_count, sample_revision;
    uint32_t sample_tick;
    void (*event)(const farm_event_t *event);
} farm_t;
extern const char *const farm_pen_names[FARM_PENS];
extern const unsigned farm_class_ids[FARM_CLASSES];
extern const unsigned farm_home_pen[FARM_CLASSES];
int farm_animal(unsigned class_id);
void farm_init(farm_t *farm, uint32_t now, void (*event)(const farm_event_t *));
void farm_frame(farm_t *farm, const farm_box_t *boxes, unsigned count,
                unsigned width, uint32_t now);
void farm_inventory(farm_t *farm, uint32_t now);
unsigned farm_alerts(const farm_t *farm);
bool farm_pen_alert(const farm_t *farm, unsigned pen);
void farm_event_text(const farm_event_t *event, char *text, size_t size);
#endif
