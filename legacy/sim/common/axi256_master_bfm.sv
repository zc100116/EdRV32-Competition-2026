// ============================================================================
// File        : axi256_master_bfm.sv
// Description : Small task-driven 256-bit AXI master used by DDR integration
//               cases.  It deliberately generates only aligned INCR bursts.
// ============================================================================

`timescale 1ns/1ps

module axi256_master_bfm #(
    parameter integer ID_W = 4,
    parameter integer TAG = 0
) (
    input  wire                 clk_i,
    input  wire                 rst_n_i,

    output reg  [ID_W-1:0]      awid_o,
    output reg  [31:0]          awaddr_o,
    output reg  [7:0]           awlen_o,
    output reg  [2:0]           awsize_o,
    output reg  [1:0]           awburst_o,
    output reg  [3:0]           awqos_o,
    output reg                  awvalid_o,
    input  wire                 awready_i,
    output reg  [255:0]         wdata_o,
    output reg  [31:0]          wstrb_o,
    output reg                  wlast_o,
    output reg                  wvalid_o,
    input  wire                 wready_i,
    input  wire [ID_W-1:0]      bid_i,
    input  wire [1:0]           bresp_i,
    input  wire                 bvalid_i,
    output reg                  bready_o,

    output reg  [ID_W-1:0]      arid_o,
    output reg  [31:0]          araddr_o,
    output reg  [7:0]           arlen_o,
    output reg  [2:0]           arsize_o,
    output reg  [1:0]           arburst_o,
    output reg  [3:0]           arqos_o,
    output reg                  arvalid_o,
    input  wire                 arready_i,
    input  wire [ID_W-1:0]      rid_i,
    input  wire [255:0]         rdata_i,
    input  wire [1:0]           rresp_i,
    input  wire                 rlast_i,
    input  wire                 rvalid_i,
    output reg                  rready_o
);

    integer cycle_r;

    function [255:0] make_pattern;
        input [31:0] seed;
        input integer index;
        integer lane;
        begin
            for (lane = 0; lane < 8; lane = lane + 1)
                make_pattern[lane*32 +: 32] =
                    seed ^ index ^ TAG ^ (lane * 32'h1020_4081);
        end
    endfunction

    task write_burst;
        input [31:0] addr;
        input [ID_W-1:0] id;
        input integer beats;
        input [31:0] seed;
        integer index;
        integer begin_cycle;
        begin
            @(posedge clk_i);
            awid_o <= id;
            awaddr_o <= addr;
            awlen_o <= beats - 1;
            awsize_o <= 3'd5;
            awburst_o <= 2'b01;
            awvalid_o <= 1'b1;
            do @(posedge clk_i); while (!awready_i);
            awvalid_o <= 1'b0;

            begin_cycle = cycle_r;
            index = 0;
            wdata_o <= make_pattern(seed, 0);
            wstrb_o <= 32'hffff_ffff;
            wlast_o <= (beats == 1);
            wvalid_o <= 1'b1;
            while (index < beats) begin
                @(posedge clk_i);
                if (wready_i) begin
                    index = index + 1;
                    if (index < beats) begin
                        wdata_o <= make_pattern(seed, index);
                        wlast_o <= (index == beats - 1);
                    end
                end
            end
            wvalid_o <= 1'b0;
            wlast_o <= 1'b0;

            while (!bvalid_i)
                @(posedge clk_i);
            if ((bid_i !== id) || (bresp_i !== 2'b00))
                $fatal(1, "AXI_BFM%0d write response id=%h resp=%h", TAG,
                       bid_i, bresp_i);
            @(posedge clk_i);
            $display("AXI256_BFM_WRITE tag=%0d beats=%0d elapsed_cycles=%0d",
                     TAG, beats, cycle_r - begin_cycle);
        end
    endtask

    task read_check;
        input [31:0] addr;
        input [ID_W-1:0] id;
        input integer beats;
        input [31:0] seed;
        integer index;
        integer begin_cycle;
        begin
            @(posedge clk_i);
            arid_o <= id;
            araddr_o <= addr;
            arlen_o <= beats - 1;
            arsize_o <= 3'd5;
            arburst_o <= 2'b01;
            arvalid_o <= 1'b1;
            do @(posedge clk_i); while (!arready_i);
            arvalid_o <= 1'b0;

            begin_cycle = cycle_r;
            index = 0;
            while (index < beats) begin
                @(posedge clk_i);
                if (rvalid_i) begin
                    if (rid_i !== id)
                        $fatal(1, "AXI_BFM%0d read ID beat=%0d got=%h exp=%h",
                               TAG, index, rid_i, id);
                    if (rresp_i !== 2'b00)
                        $fatal(1, "AXI_BFM%0d read response beat=%0d resp=%h",
                               TAG, index, rresp_i);
                    if (rdata_i !== make_pattern(seed, index))
                        $fatal(1, "AXI_BFM%0d read data beat=%0d", TAG, index);
                    if (rlast_i !== (index == beats - 1))
                        $fatal(1, "AXI_BFM%0d read last beat=%0d last=%0d",
                               TAG, index, rlast_i);
                    index = index + 1;
                end
            end
            $display("AXI256_BFM_READ tag=%0d beats=%0d elapsed_cycles=%0d",
                     TAG, beats, cycle_r - begin_cycle);
        end
    endtask

    initial begin
        awid_o = 0;
        awaddr_o = 0;
        awlen_o = 0;
        awsize_o = 3'd5;
        awburst_o = 2'b01;
        awqos_o = 0;
        awvalid_o = 0;
        wdata_o = 0;
        wstrb_o = 0;
        wlast_o = 0;
        wvalid_o = 0;
        bready_o = 1;
        arid_o = 0;
        araddr_o = 0;
        arlen_o = 0;
        arsize_o = 3'd5;
        arburst_o = 2'b01;
        arqos_o = 0;
        arvalid_o = 0;
        rready_o = 1;
        cycle_r = 0;
    end

    always @(posedge clk_i) begin
        if (!rst_n_i)
            cycle_r <= 0;
        else
            cycle_r <= cycle_r + 1;
    end

endmodule
