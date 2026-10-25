/* File: main.c
 * Spec: cpu-testplan 3.8; cpu-spec 2.3.
 * Description: Run a directed instruction loop between retirement-PC markers.
 *              Functional checks return a status through the B2 BSP.
 * Clock domain: clk_sys.
 */
int main(void)
{
    unsigned a;
    unsigned b;
    unsigned count = 256;
    __asm__ volatile (
        ".option push\n.option norvc\n.balign 8\n"
        "li %0, 0\nli %1, 0\n"
        ".globl b2_perf_begin\nb2_perf_begin:\nnop\n.balign 8\n"
        "1:\n.rept 32\naddi %0, %0, 1\naddi %1, %1, 1\n.endr\n"
        "addi %2, %2, -1\nbnez %2, 1b\n"
        ".globl b2_perf_end\nb2_perf_end:\nnop\n.option pop"
        : "=&r"(a), "=&r"(b), "+r"(count));
    return a != 8192 || b != 8192;
}
