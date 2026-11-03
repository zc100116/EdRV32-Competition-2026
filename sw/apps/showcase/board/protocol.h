/* protocol.h — P5 8.2–8.5; host-testable EDSC v3 and asynchronous completion. */
#ifndef SHOWCASE_PROTOCOL_H
#define SHOWCASE_PROTOCOL_H
#include <stdint.h>
enum { EDSC_PENDING = 256, EDSC_STATE_BYTES = 56 };
struct edsc_ops {
    unsigned (*reserve)(unsigned kind, uint32_t total, uint32_t *base);
    unsigned (*complete)(unsigned kind, uint32_t base, uint32_t bytes, uint32_t *index);
    void (*reply)(const uint8_t *message, unsigned bytes);
    void (*state)(uint8_t payload[EDSC_STATE_BYTES]);
    unsigned (*command)(unsigned type, const uint8_t *payload, unsigned bytes, uint32_t seq);
    unsigned (*progress)(unsigned type);
    void (*cancel)(unsigned kind);
};
struct edsc {
    struct edsc_ops ops;
    unsigned kind, active, peer, image_info;
    uint32_t total, base, seq, bulk_seq;
    unsigned pending[3];
    uint32_t pending_seq[3];
    uint8_t previous[EDSC_STATE_BYTES];
    uint64_t state_time;
    const char *build;
};
void edsc_message(struct edsc *s, const uint8_t *data, unsigned bytes);
void edsc_finish(struct edsc *s, unsigned kind, uint32_t index);
void edsc_bulk(struct edsc *s, uint32_t bytes);
void edsc_cancel(struct edsc *s);
void edsc_poll(struct edsc *s, uint64_t now, uint32_t hz);
void edsc_image_step(struct edsc *s, int direction);
#endif
