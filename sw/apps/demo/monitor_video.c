/* File: monitor_video.c
 * Spec: Task T-NETN-R; SoC 7.2/7.4; eth-spec 2.4/2.6.
 * Description: VIN/DISP interval counters for video-capable demos.
 * Clock domain: clk_sys; CPU-built DDR objects use the uncached alias.
 */
#include "runtime.h"

static uint32_t previous_vin[4];
static uint32_t previous_underruns;
static uint32_t previous_submitted;

void demo_monitor_media(struct eth_monitor *record)
{
    const unsigned int vin_counters[] = {3, 5, 6, 8};
    for (unsigned int i = 0; i < 4; ++i) {
        uint32_t value = engine_perf(ENGINE_VIN, vin_counters[i]);
        record->vin[i] = value - previous_vin[i];
        previous_vin[i] = value;
    }
    uint32_t underruns = engine_perf(ENGINE_DISP, 1);
    record->disp[0] = underruns - previous_underruns;
    previous_underruns = underruns;
    record->disp[1] = demo.submitted - previous_submitted;
    previous_submitted = demo.submitted;
}
