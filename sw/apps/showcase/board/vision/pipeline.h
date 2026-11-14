/* pipeline.h — PIPE-SPEC 7.1/7.4; hardware-independent chain compiler.
 * Plans describe DDR hops and asynchronous detection taps; CPU domain.
 */
#ifndef SHOWCASE_PIPELINE_H
#define SHOWCASE_PIPELINE_H
#include "../../ui/ui_data.h"
enum { PIPE_NO_BLOCK = 255 };
struct pipe_plan {
    unsigned count;
    ui_hop_t hop[UI_HOP_MAX];
    uint8_t pix_first[UI_HOP_MAX];
    uint8_t sample[UI_HOP_MAX];
    uint8_t block_hop[UI_BLOCK_MAX];
    uint8_t hide_l1;
};
unsigned pipe_chain_validate(const ui_chain_t *chain);
void pipe_chain_preset(ui_chain_t *chain, unsigned preset);
void pipe_compile(const ui_chain_t *chain, struct pipe_plan *plan);
void pipe_chain_decode(ui_chain_t *chain, const uint8_t bytes[100]);
void pipe_chain_encode(uint8_t bytes[100], const ui_chain_t *chain);
#endif
