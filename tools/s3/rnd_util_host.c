/* File: rnd_util_host.c
 * Spec: rnd 2.6, 5.4, 7; T-RNDMEAS.
 * Description: Observe real benchmark scene boundaries for RN-17 capture.
 * Clock domain: deterministic host milliseconds.
 */
#include "../../sw/apps/s3/lvgl/s3_lvgl.c"

unsigned s3_util_scene(void) { return benchmark_scene; }
const char *s3_util_name(void) { return benchmark_names[benchmark_scene]; }
void s3_util_capture_sync(bool capture)
{
    lv_display_set_sync_cb(display, capture ? sync_buffers : NULL);
}
