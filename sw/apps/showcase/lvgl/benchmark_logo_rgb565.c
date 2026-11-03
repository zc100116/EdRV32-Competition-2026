/* benchmark_logo_rgb565.c — showcase P5 design 11.2; RND spec 2.1 source format.
 * Reuse the upstream RGB565 pixels and descriptor for RND BLIT.
 * Host asset compilation; no clock domain.
 */
#include "lvgl.h"

/* Load LVGL types with showcase's configuration before selecting asset data. */
#undef LV_COLOR_DEPTH
#define LV_COLOR_DEPTH 16
#include "../../../../third_party/lvgl/demos/benchmark/assets/img_benchmark_lvgl_logo_rgb.c"
