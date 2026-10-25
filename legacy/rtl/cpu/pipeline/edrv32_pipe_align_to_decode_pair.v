// ============================================================================
// File        : edrv32_pipe_align_to_decode_pair.v
// Description : Four registered instruction payloads for the paired ALIGN
//               boundary. ALIGN owns occupancy, movement and squash policy.
// ============================================================================
`include "edrv32_uop.vh"

module edrv32_pipe_align_to_decode_pair #(
    parameter integer PAYLOAD_W = 134 + `EDRV32_EPOCH_W
)(
    input  wire                 clk_i,
    input  wire                 rst_n_i,
    input  wire                 valid_we_i,
    input  wire [3:0]           valid_i,
    input  wire [3:0]           payload_we_i,
    input  wire [PAYLOAD_W-1:0] payload0_i,
    input  wire [PAYLOAD_W-1:0] payload1_i,
    input  wire [PAYLOAD_W-1:0] payload2_i,
    input  wire [PAYLOAD_W-1:0] payload3_i,
    output wire [3:0]           valid_o,
    output wire [PAYLOAD_W-1:0] payload0_o,
    output wire [PAYLOAD_W-1:0] payload1_o,
    output wire [PAYLOAD_W-1:0] payload2_o,
    output wire [PAYLOAD_W-1:0] payload3_o
);

    reg [3:0]           valid_r;
    reg [PAYLOAD_W-1:0] payload0_r;
    reg [PAYLOAD_W-1:0] payload1_r;
    reg [PAYLOAD_W-1:0] payload2_r;
    reg [PAYLOAD_W-1:0] payload3_r;

    assign valid_o    = valid_r;
    assign payload0_o = payload0_r;
    assign payload1_o = payload1_r;
    assign payload2_o = payload2_r;
    assign payload3_o = payload3_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            valid_r <= 4'b0000;
        else if (valid_we_i)
            valid_r <= valid_i;
    end

    always @(posedge clk_i) begin
        if (payload_we_i[0])
            payload0_r <= payload0_i;
        if (payload_we_i[1])
            payload1_r <= payload1_i;
        if (payload_we_i[2])
            payload2_r <= payload2_i;
        if (payload_we_i[3])
            payload3_r <= payload3_i;
    end

endmodule
