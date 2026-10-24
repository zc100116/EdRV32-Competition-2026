// ============================================================================
// File        : edrv32_csr.vh
// Description : Fixed RV32IMC machine-mode CSR and interrupt encodings.
// ============================================================================
`ifndef EDRV32_CSR_VH
`define EDRV32_CSR_VH

`define EDRV32_CSR_MSTATUS    12'h300
`define EDRV32_CSR_MISA       12'h301
`define EDRV32_CSR_MIE        12'h304
`define EDRV32_CSR_MTVEC      12'h305
`define EDRV32_CSR_MCOUNTINHIBIT 12'h320
`define EDRV32_CSR_MSCRATCH   12'h340
`define EDRV32_CSR_MEPC       12'h341
`define EDRV32_CSR_MCAUSE     12'h342
`define EDRV32_CSR_MTVAL      12'h343
`define EDRV32_CSR_MIP        12'h344

`define EDRV32_CSR_MCYCLE     12'hB00
`define EDRV32_CSR_MINSTRET   12'hB02
`define EDRV32_CSR_MHPMCOUNTER_FIRST  12'hB03
`define EDRV32_CSR_MHPMCOUNTER_LAST   12'hB1F
`define EDRV32_CSR_MCYCLEH    12'hB80
`define EDRV32_CSR_MINSTRETH  12'hB82
`define EDRV32_CSR_MHPMCOUNTERH_FIRST 12'hB83
`define EDRV32_CSR_MHPMCOUNTERH_LAST  12'hB9F
`define EDRV32_CSR_MHPMEVENT_FIRST     12'h323
`define EDRV32_CSR_MHPMEVENT_LAST      12'h33F
// EdRV32 custom-machine aliases extend the 29 standard HPM counters with
// eleven counters so all forty platform events can be observed at once.
`define EDRV32_CSR_MHPMEXTRA_FIRST     12'h7C0
`define EDRV32_CSR_MHPMEXTRA_LAST      12'h7CA
`define EDRV32_CSR_MHPMEXTRAH_FIRST    12'h7D0
`define EDRV32_CSR_MHPMEXTRAH_LAST     12'h7DA
`define EDRV32_CSR_MHPMEXTRAEVENT_FIRST 12'h7E0
`define EDRV32_CSR_MHPMEXTRAEVENT_LAST  12'h7EA
`define EDRV32_CSR_MHPMEXTRAINHIBIT    12'h7F0
`define EDRV32_CSR_CYCLE      12'hC00
`define EDRV32_CSR_TIME       12'hC01
`define EDRV32_CSR_INSTRET    12'hC02
`define EDRV32_CSR_CYCLEH     12'hC80
`define EDRV32_CSR_TIMEH      12'hC81
`define EDRV32_CSR_INSTRETH   12'hC82

`define EDRV32_CSR_MVENDORID  12'hF11
`define EDRV32_CSR_MARCHID    12'hF12
`define EDRV32_CSR_MIMPID     12'hF13
`define EDRV32_CSR_MHARTID    12'hF14

`define EDRV32_MSTATUS_MIE_BIT   3
`define EDRV32_MSTATUS_MPIE_BIT  7
`define EDRV32_IRQ_M_SOFT_BIT    3
`define EDRV32_IRQ_M_TIMER_BIT   7
`define EDRV32_IRQ_M_EXT_BIT     11

`define EDRV32_CAUSE_INT_M_SOFT  (32'h8000_0000 | 32'd3)
`define EDRV32_CAUSE_INT_M_TIMER (32'h8000_0000 | 32'd7)
`define EDRV32_CAUSE_INT_M_EXT   (32'h8000_0000 | 32'd11)

`endif
