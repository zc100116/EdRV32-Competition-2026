/* farm.h — R5-11; single-area inventory, missing animals and intrusion alerts.
 * Caller supplies monotonic milliseconds; pure C without LVGL ownership.
 */
#ifndef SHOWCASE_FARM_H
#define SHOWCASE_FARM_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
enum { FARM_CLASSES=4, FARM_EVENTS=20, FARM_SAMPLES=60, FARM_PAGE=19 };
typedef struct { unsigned class_id; int x, y, width, height; } farm_box_t;
typedef enum {
    FARM_MISSING, FARM_MISSING_CLEAR, FARM_INTRUDE, FARM_INTRUDE_CLEAR
} farm_event_type_t;
typedef struct {
    uint32_t time_ms;
    unsigned class_id, amount;
    farm_event_type_t type;
} farm_event_t;
typedef struct { uint32_t time_ms; unsigned total[FARM_CLASSES]; } farm_sample_t;
typedef struct { uint32_t since; bool pending, active; } farm_alarm_t;
typedef struct {
    unsigned counts[FARM_CLASSES];
    unsigned candidate_counts[FARM_CLASSES];
    uint32_t count_since[FARM_CLASSES];
    unsigned expected[FARM_CLASSES];
    unsigned person;
    farm_alarm_t missing[FARM_CLASSES];
    farm_alarm_t intrude;
    unsigned day, missing_today, intrude_today;
    farm_event_t events[FARM_EVENTS];
    farm_sample_t samples[FARM_SAMPLES];
    unsigned event_head, event_count, event_revision;
    unsigned sample_head, sample_count, sample_revision;
    uint32_t sample_tick;
    void (*event)(const farm_event_t *event);
} farm_t;
extern const unsigned farm_class_ids[FARM_CLASSES];
int farm_animal(unsigned class_id);
void farm_init(farm_t *farm, uint32_t now, void (*event)(const farm_event_t *));
void farm_frame(farm_t *farm, const farm_box_t *boxes, unsigned count, uint32_t now);
void farm_inventory(farm_t *farm, uint32_t now);
unsigned farm_alerts(const farm_t *farm);
const char *farm_event_name(farm_event_type_t type);
void farm_event_text(const farm_event_t *event, char *text, size_t size);
#endif
