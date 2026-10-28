// File: edrv32_pix_stub_tb.sv
// Spec: PIX testplan PX-01; V-T3 environment-only compile/run.
// Description: Explicit straight-through stub top; excluded from formal test.yaml.
// Clock domain: clk_mem.
`timescale 1ns/1ps
module edrv32_pix_stub_tb;
    `include "environment.svh"
    edrv32_pix_passthrough_stub u_dut (
        `include "dut_connections.svh"
    );
endmodule
