/* File: monitor.c
 * Spec: Task T-NETN-R; SoC 7.2/7.4; eth-spec 2.4/2.6.
 * Description: EDTM VIN/DISP fields are zero on B3N without media engines.
 * Clock domain: clk_sys; CPU-built DDR objects use the uncached alias.
 */
#include "runtime.h"

void demo_monitor_media(struct eth_monitor *record)
{
    for (unsigned int i = 0; i < 4; ++i) {
        record->vin[i] = 0;
    }
    record->disp[0] = 0;
    record->disp[1] = 0;
}
