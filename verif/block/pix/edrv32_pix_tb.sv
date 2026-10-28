// File: edrv32_pix_tb.sv
// Spec: PIX 2-5; PIX testplan PX-01 through PX-14.
// Description: Independent public-port verification top for the real PIX module.
// Clock domain: clk_mem.
`timescale 1ns/1ps
module edrv32_pix_tb;
    `include "environment.svh"
    edrv32_pix u_dut (
        `include "dut_connections.svh"
    );
endmodule
