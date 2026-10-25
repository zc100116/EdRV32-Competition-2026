/* File: main.c
 * Spec: infra-plan I-07; CLAUDE.md 9.2
 * Description: Check initialized and zero data through the common BSP startup.
 *              Return the result to the host through main's exit status.
 * Clock domain: clk_sys.
 */
static volatile unsigned initialized = 0x12345678;
static volatile unsigned zeroed;

int main(void)
{
    if (initialized != 0x12345678 || zeroed != 0) {
        return 1;
    }
    zeroed = initialized;
    return zeroed != 0x12345678;
}
