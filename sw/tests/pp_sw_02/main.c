/* main.c — npu-testplan 3.10 PP-SW-02; SoC 7.4.4/5.
 * Dirty two cached candidate regions; overlap frame-zero CPU work with frame one DMA.
 * Clock domain: clk_sys.
 */
#include "common.h"
int main(void)
{
    pp_init();
    pp_dirty(0);
    pp_dirty(1);
    pp_start(0);
    uint32_t count0 = pp_wait();
    pp_equal(count0, npu_post_acquire(PP_POST));
    pp_start(1);
    /* POST_COUNT is now zero. Saved count and buffer zero remain frame-zero owned. */
    pp_equal(0, npu_post_count());
    pp_results(0, count0, 0);
    uint32_t count1 = pp_wait();
    pp_equal(count1, npu_post_acquire(PP_POST + PP_POST_STEP));
    pp_results(1, count1, 1);
    /* Sorted frame zero was dirty: reuse it only through the full-region release. */
    pp_start(0);
    uint32_t count2 = pp_wait();
    pp_equal(count2, npu_post_acquire(PP_POST));
    pp_results(0, count2, 0);
    pp_pass();
}
