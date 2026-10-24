// ============================================================================
// File        : axi256_mem_model.sv
// Description : Compact single-outstanding 256-bit AXI memory model for the
//               System-AXI-to-DDR-Gateway directed tests.
// ============================================================================

`timescale 1ns/1ps

module axi256_mem_model #(
    parameter integer ID_W = 4,
    parameter integer WORDS = 4096
) (
    input  wire                 clk_i,
    input  wire                 rst_n_i,
    input  wire [ID_W-1:0]      awid_i,
    input  wire [31:0]          awaddr_i,
    input  wire [7:0]           awlen_i,
    input  wire [2:0]           awsize_i,
    input  wire [1:0]           awburst_i,
    input  wire                 awvalid_i,
    output wire                 awready_o,
    input  wire [255:0]         wdata_i,
    input  wire [31:0]          wstrb_i,
    input  wire                 wlast_i,
    input  wire                 wvalid_i,
    output wire                 wready_o,
    output wire [ID_W-1:0]      bid_o,
    output wire [1:0]           bresp_o,
    output wire                 bvalid_o,
    input  wire                 bready_i,
    input  wire [ID_W-1:0]      arid_i,
    input  wire [31:0]          araddr_i,
    input  wire [7:0]           arlen_i,
    input  wire [2:0]           arsize_i,
    input  wire [1:0]           arburst_i,
    input  wire                 arvalid_i,
    output wire                 arready_o,
    output wire [ID_W-1:0]      rid_o,
    output wire [255:0]         rdata_o,
    output wire [1:0]           rresp_o,
    output wire                 rlast_o,
    output wire                 rvalid_o,
    input  wire                 rready_i
);

    localparam integer ADDR_BITS = $clog2(WORDS);

    reg [255:0] store [0:WORDS-1];

    reg wr_active_r;
    reg [ID_W-1:0] wr_id_r;
    reg [31:0] wr_addr_r;
    reg [8:0] wr_left_r;
    reg bvalid_r;
    reg [1:0] bresp_r;

    reg rd_active_r;
    reg [ID_W-1:0] rd_id_r;
    reg [31:0] rd_addr_r;
    reg [8:0] rd_left_r;
    reg [1:0] rd_resp_r;

    integer byte_i;
    integer word_index_w;

    assign awready_o = !wr_active_r && !bvalid_r;
    assign wready_o = wr_active_r;
    assign bid_o = wr_id_r;
    assign bresp_o = bresp_r;
    assign bvalid_o = bvalid_r;

    assign arready_o = !rd_active_r;
    assign rid_o = rd_id_r;
    assign rdata_o = store[rd_addr_r[ADDR_BITS+4:5]];
    assign rresp_o = rd_resp_r;
    assign rlast_o = rd_left_r == 1;
    assign rvalid_o = rd_active_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            wr_active_r <= 1'b0;
            wr_id_r <= {ID_W{1'b0}};
            wr_addr_r <= 32'b0;
            wr_left_r <= 9'b0;
            bvalid_r <= 1'b0;
            bresp_r <= 2'b00;
            rd_active_r <= 1'b0;
            rd_id_r <= {ID_W{1'b0}};
            rd_addr_r <= 32'b0;
            rd_left_r <= 9'b0;
            rd_resp_r <= 2'b00;
        end else begin
            if (awvalid_i && awready_o) begin
                wr_active_r <= 1'b1;
                wr_id_r <= awid_i;
                wr_addr_r <= awaddr_i;
                wr_left_r <= {1'b0, awlen_i} + 1'b1;
                bresp_r <= ((awsize_i == 3'd5) &&
                            (awburst_i == 2'b01) &&
                            (awaddr_i[4:0] == 0)) ? 2'b00 : 2'b11;
            end

            if (wvalid_i && wready_o) begin
                word_index_w = wr_addr_r[ADDR_BITS+4:5];
                for (byte_i = 0; byte_i < 32; byte_i = byte_i + 1) begin
                    if (wstrb_i[byte_i])
                        store[word_index_w][byte_i*8 +: 8] <=
                            wdata_i[byte_i*8 +: 8];
                end
                if (wlast_i != (wr_left_r == 1))
                    bresp_r <= 2'b10;
                wr_addr_r <= wr_addr_r + 32;
                wr_left_r <= wr_left_r - 1'b1;
                if (wr_left_r == 1) begin
                    wr_active_r <= 1'b0;
                    bvalid_r <= 1'b1;
                end
            end

            if (bvalid_r && bready_i)
                bvalid_r <= 1'b0;

            if (arvalid_i && arready_o) begin
                rd_active_r <= 1'b1;
                rd_id_r <= arid_i;
                rd_addr_r <= araddr_i;
                rd_left_r <= {1'b0, arlen_i} + 1'b1;
                rd_resp_r <= ((arsize_i == 3'd5) &&
                              (arburst_i == 2'b01) &&
                              (araddr_i[4:0] == 0)) ? 2'b00 : 2'b11;
            end

            if (rvalid_o && rready_i) begin
                rd_addr_r <= rd_addr_r + 32;
                rd_left_r <= rd_left_r - 1'b1;
                if (rd_left_r == 1)
                    rd_active_r <= 1'b0;
            end
        end
    end

endmodule
