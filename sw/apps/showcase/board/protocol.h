/* protocol.h — showcase 4.5.4; EDSC message framing and bulk lifecycle, host-testable. */
#ifndef SHOWCASE_PROTOCOL_H
#define SHOWCASE_PROTOCOL_H
#include <stdint.h>
struct edsc_ops {
    unsigned (*reserve)(unsigned kind,uint32_t total,uint32_t *base);
    unsigned (*complete)(unsigned kind,uint32_t base,uint32_t bytes,uint32_t *index);
    void (*camera)(void);
    void (*reply)(const uint8_t *message,unsigned bytes);
};
struct edsc {
    struct edsc_ops ops;
    unsigned kind;
    uint32_t total,base,seq,bulk_seq;
    unsigned active;
};
void edsc_message(struct edsc *s,const uint8_t *data,unsigned bytes);
void edsc_finish(struct edsc *s,unsigned kind);
void edsc_bulk(struct edsc *s,uint32_t bytes);
#endif
