/* freertos_risc_v_chip_specific_extensions.h — RV32IM, no extra registers. */
#ifndef SHOWCASE_FREERTOS_CHIP_H
#define SHOWCASE_FREERTOS_CHIP_H
#define portasmHAS_MTIME 1
#define portasmHAS_SIFIVE_CLINT 0
#define portasmADDITIONAL_CONTEXT_SIZE 0
.macro portasmSAVE_ADDITIONAL_REGISTERS
.endm
.macro portasmRESTORE_ADDITIONAL_REGISTERS
.endm
#endif
