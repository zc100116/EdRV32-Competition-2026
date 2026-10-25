/* File: main.c
 * Spec: cpu-plan C-R3; cpu-spec 2, 4, 5
 * Description: Exercise arithmetic, memory, control flow, M extension and CSRs.
 *              Return a failing status through the common BSP tohost convention.
 * Clock: clk_sys.
 */
int main(void)
{
    volatile int a = -12345;
    volatile int b = 37;
    volatile unsigned word = 0x87654321u;
    volatile unsigned char byte = 0;
    volatile short half = 0;
    unsigned old;
    unsigned readback;
    unsigned forwarded;
    unsigned sum = 0;
    unsigned i;
    volatile unsigned code[3] __attribute__((aligned(8)));
    int (*generated)(void) = (int (*)(void))(void *)code;
    if (a * b != -456765 || a / b != -333 || a % b != -24)
        return 1;
    byte = (unsigned char)word;
    half = (short)(word >> 16);
    if (byte != 0x21 || half != (short)0x8765)
        return 2;
    for (i = 0; i < 25; ++i)
        sum += (i ^ 7u) + (i << 1);
    if (sum != 907)
        return 3;
    __asm__ volatile ("csrrw %0, mscratch, %1" : "=r"(old) : "r"(word));
    __asm__ volatile ("csrr %0, mscratch" : "=r"(readback));
    if (readback != word)
        return 4;
    __asm__ volatile ("csrw mscratch, %0" :: "r"(old));
    __asm__ volatile ("fence rw, rw\n.word 0x0000100f" ::: "memory");
    __asm__ volatile ("sw %1, 0(%2)\nlw %0, 0(%2)"
                      : "=r"(forwarded) : "r"(0xdeadbeefu), "r"(&word) : "memory");
    if (forwarded != 0xdeadbeefu)
        return 6;
    /* Train a return at the second word, then replace it with an independent ALU.
     * F2 still sees the same boundary/length; E must recover lane 1's stale prediction.
     */
    code[0] = 0x00300593u; /* addi a1, zero, 3 */
    code[1] = 0x00008067u; /* ret */
    code[2] = 0x00008067u;
    __asm__ volatile ("fence rw, rw\n.word 0x0000100f" ::: "memory");
    (void)generated();
    code[1] = 0x00700513u; /* addi a0, zero, 7 */
    __asm__ volatile ("fence rw, rw\n.word 0x0000100f" ::: "memory");
    if (generated() != 7)
        return 5;
    return 0;
}
