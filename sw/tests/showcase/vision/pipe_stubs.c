/* pipe_stubs.c — legacy vision tests; platform boundaries unused by old pages. */
#include "pipeline_exec.h"
#include <stdlib.h>
const unsigned char _binary_build_showcase_pipe_test_bin_start[1] = {0};
uint32_t vin_write_status(unsigned channel) { (void)channel; return 0; }
void board_pipe_rnd_submit(const struct rnd_batch *batch) { (void)batch; abort(); }
void showcase_gui_pipeline_overlay(bool enabled) { (void)enabled; }
bool showcase_gui_l1_acquire(void) { return true; }
void showcase_gui_l1_release(void) {}
const void *showcase_gui_l1_front(void) { return NULL; }
#ifndef NETWORK_INTEGRATION
void platform_put_hex(uint32_t value) { (void)value; }
#endif
