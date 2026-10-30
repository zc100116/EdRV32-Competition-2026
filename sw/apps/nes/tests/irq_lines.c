/* File: irq_lines.c
 * Spec: T-NES3; NESdev MMC3 IRQ and APU $4015/$4017 acknowledgement.
 * Description: Check held IRQ sources survive SEI independently and acknowledge before CLI.
 * Clock domain: emulated 6502 instructions.
 */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <noftypes.h>
#include <nes6502.h>
#include <nes.h>
static uint8 memory[4096];
static nes6502_memread reads[] = {{(uint32)-1, (uint32)-1, NULL}};
static nes6502_memwrite writes[] = {{(uint32)-1, (uint32)-1, NULL}};
int main(void)
{
    nes6502_context cpu;
    memset(&cpu, 0, sizeof(cpu));
    for (unsigned i = 0; i < NES6502_NUMBANKS; ++i)
        cpu.mem_page[i] = memory;
    cpu.pc_reg = 0x200;
    cpu.p_reg = I_FLAG | R_FLAG;
    cpu.s_reg = 0xfd;
    cpu.read_handler = reads;
    cpu.write_handler = writes;
    memory[0x200] = 0x58; /* CLI */
    memory[0x201] = 0xea; /* NOP */
    memory[0xffe] = 0;
    memory[0xfff] = 3;
    nes6502_setcontext(&cpu);
    nes6502_setirq(NES6502_IRQ_FRAME, true);
    nes6502_setirq(NES6502_IRQ_MAPPER, true);
    nes_setfiq(0x40);
    nes6502_getcontext(&cpu);
    assert(cpu.irq_lines == NES6502_IRQ_MAPPER);
    nes6502_setirq(NES6502_IRQ_MAPPER, false);
    nes6502_execute(4);
    nes6502_getcontext(&cpu);
    assert(cpu.pc_reg == 0x202 && cpu.s_reg == 0xfd);
    /* An asserted source is level-sensitive and remains until its own ack. */
    cpu.pc_reg = 0x200;
    cpu.p_reg = I_FLAG | R_FLAG;
    nes6502_setcontext(&cpu);
    nes6502_setirq(NES6502_IRQ_FRAME, true);
    nes_setfiq(0x80); /* Five-step mode alone does not acknowledge the frame IRQ. */
    nes6502_execute(4);
    nes6502_getcontext(&cpu);
    assert(cpu.pc_reg == 0x300 && cpu.s_reg == 0xfa);
    assert(cpu.irq_lines == NES6502_IRQ_FRAME);
    puts("PASS held IRQ lines and independent APU/mapper acknowledgement");
    return 0;
}
