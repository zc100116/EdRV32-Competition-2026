/* File: main.c
 * Spec: cpu-testplan 3.8; cpu-spec 2.3.
 * Description: Run a directed instruction loop between retirement-PC markers.
 *              Functional checks return a status through the B2 BSP.
 * Clock domain: clk_sys.
 */
int main(void)
{
    unsigned count = 256;
    unsigned observed;
    __asm__ volatile (
        ".option push\n.option norvc\n.balign 8\nli %0, 0\n"
        ".globl b2_perf_begin\nb2_perf_begin:\nnop\n.balign 8\n"
        /* Distinct PCs exceed the 32-entry BTB capacity. */
        "1:\n.rept 256\nbeq zero, zero, 2f\naddi %0, %0, 1\n"
        "2:\n.endr\naddi %1, %1, -1\nbnez %1, 1b\n"
        ".globl b2_perf_end\nb2_perf_end:\nnop\n.option pop"
        : "=&r"(observed), "+r"(count));
    return observed != 0;
}
