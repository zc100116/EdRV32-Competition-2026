/* File: main.c
 * Spec: soc-testplan SC-09.
 * Description: Select the shared concurrency workload with the latency probe.
 * Clock domain: clk_sys software.
 */
void concurrent(unsigned int probe);
int main(void)
{
    concurrent(1u);
}
