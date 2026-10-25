/* File: main.c
 * Spec: cpu-testplan 3.8; cpu-spec 2.3.
 * Description: Run a directed instruction loop between retirement-PC markers.
 *              Functional checks return a status through the B2 BSP.
 * Clock domain: clk_sys.
 */
int main(void)
{
    unsigned value;
    unsigned count = 256;
    volatile unsigned source = 7;
    __asm__ volatile (
        ".option push\n.option norvc\n.balign 8\n"
        ".globl b2_perf_begin\nb2_perf_begin:\nnop\n.balign 8\n"
        "1:\n.rept 16\nlw %0, 0(%2)\naddi %0, %0, 1\n.endr\n"
        "addi %1, %1, -1\nbnez %1, 1b\n"
        ".globl b2_perf_end\nb2_perf_end:\nnop\n.option pop"
        : "=&r"(value), "+&r"(count) : "r"(&source) : "memory");
    if (value != 8) return 1;
    value = 1;
    count = 256;
    __asm__ volatile (
        ".option push\n.option norvc\n.balign 8\n"
        ".globl b2_perf2_begin\nb2_perf2_begin:\nnop\n.balign 8\n"
        "1:\n.rept 16\nmul %0, %0, %2\naddi %0, %0, 1\n.endr\n"
        "addi %1, %1, -1\nbnez %1, 1b\n"
        ".globl b2_perf2_end\nb2_perf2_end:\nnop\n.option pop"
        : "+&r"(value), "+&r"(count) : "r"(1));
    return value != 4097;
}
