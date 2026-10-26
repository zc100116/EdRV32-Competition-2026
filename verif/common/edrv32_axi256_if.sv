// File: edrv32_axi256_if.sv
// Spec: SoC 4.2; mem-subsys-testplan 2.2.
// Description: Shared verification wires for local and DDR interfaces.
// Clock domain: clk_mem.
`timescale 1ns/1ps
interface edrv32_axi256_if #(parameter int ID_WIDTH = 1);
    logic [ID_WIDTH-1:0] awid;
    logic [31:0] awaddr;
    logic [3:0] awlen;
    logic awvalid;
    logic awready;
    logic [255:0] wdata;
    logic [31:0] wstrb;
    logic wlast;
    logic wvalid;
    logic wready;
    logic [ID_WIDTH-1:0] bid;
    logic [1:0] bresp;
    logic bvalid;
    logic bready;
    logic [ID_WIDTH-1:0] arid;
    logic [31:0] araddr;
    logic [3:0] arlen;
    logic arvalid;
    logic arready;
    logic [ID_WIDTH-1:0] rid;
    logic [255:0] rdata;
    logic [1:0] rresp;
    logic rlast;
    logic rvalid;
    logic rready;
endinterface
