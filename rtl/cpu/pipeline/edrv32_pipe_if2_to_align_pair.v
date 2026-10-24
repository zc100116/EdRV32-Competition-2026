// ============================================================================
// File        : edrv32_pipe_if2_to_align_pair.v
// Description : Four payload registers for the paired IF2 window boundary.
//               IF2 owns occupancy, queue movement, prediction and squash.
// ============================================================================
`include "edrv32_uop.vh"

module edrv32_pipe_if2_to_align_pair #(
    parameter integer PAYLOAD_W = 102 + `EDRV32_EPOCH_W
)(
    input  wire                 clk_i,
    input  wire                 payload_we_i,
    input  wire [PAYLOAD_W-1:0] payload0_i,
    input  wire [PAYLOAD_W-1:0] payload1_i,
    input  wire [PAYLOAD_W-1:0] payload2_i,
    input  wire [PAYLOAD_W-1:0] payload3_i,
    output wire [PAYLOAD_W-1:0] payload0_o,
    output wire [PAYLOAD_W-1:0] payload1_o,
    output wire [PAYLOAD_W-1:0] payload2_o,
    output wire [PAYLOAD_W-1:0] payload3_o
);
    reg [PAYLOAD_W-1:0] payload0_r;
    reg [PAYLOAD_W-1:0] payload1_r;
    reg [PAYLOAD_W-1:0] payload2_r;
    reg [PAYLOAD_W-1:0] payload3_r;

    assign payload0_o = payload0_r;
    assign payload1_o = payload1_r;
    assign payload2_o = payload2_r;
    assign payload3_o = payload3_r;

    always @(posedge clk_i) begin
        if (payload_we_i) begin
            payload0_r <= payload0_i;
            payload1_r <= payload1_i;
            payload2_r <= payload2_i;
            payload3_r <= payload3_i;
        end
    end
endmodule
