/* File: gfx.h
 * Spec: ember_isles tech 2, 4-5; GPU 2.1, 2.8-2.10.
 * Description: Read-only CPU presentation preparation and media submission.
 * Clock domain: CPU frame; GPU and DISP clocks behind the drivers.
 */
#ifndef EMBER_GFX_H
#define EMBER_GFX_H
struct ember_sim;
struct ember_ui_state;
void ember_gfx_init(void);
void ember_gfx_prepare(const struct ember_sim *sim, unsigned fps, const struct ember_ui_state *ui);
void ember_gfx_submit(unsigned frame);
#endif
