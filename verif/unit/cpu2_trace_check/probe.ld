/* File: probe.ld
 * Spec: cpu-v2-testplan 4, V01 converter fixture.
 * Description: Link the Spike probe in executable DDR.
 * Clock: none.
 */
OUTPUT_ARCH(riscv)
ENTRY(_start)
SECTIONS { . = 0x80000000; .text : { *(.text*) } }
