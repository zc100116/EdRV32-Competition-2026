/* File: main.c
 * Spec: soc-testplan SC-08.
 * Description: Select the shared concurrency workload without the latency probe.
 * Clock domain: clk_sys software.
 */
void concurrent(unsigned int probe);
int main(void)
{
    concurrent(0u);
}
