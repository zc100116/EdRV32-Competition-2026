// File: edrv32_apb_if.sv
// Spec: SoC 4.3; sys-subsys 3.2.
// Description: Sixteen APB slots sharing address and write payload.
// Clock domain: selected by the connected bridge.
interface edrv32_apb_if;
    logic [11:0] paddr;
    logic [15:0] psel;
    logic penable;
    logic pwrite;
    logic [31:0] pwdata;
    logic [3:0] pstrb;
    logic [511:0] prdata;
    logic [15:0] pready;
    logic [15:0] pslverr;
endinterface
