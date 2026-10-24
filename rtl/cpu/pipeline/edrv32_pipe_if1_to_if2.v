// ============================================================================
// File        : edrv32_pipe_if1_to_if2.v
// Description : Two-entry register bank for accepted IF1 request metadata.
// Notes       : IF1 owns protocol, ordering and occupancy. This module only
//               shifts/writes payload registers selected by IF1, and every
//               externally visible field comes directly from the head _r.
// ============================================================================
`include "edrv32_uop.vh"

module edrv32_pipe_if1_to_if2 (
    input wire [71:0] wide_meta_i,
    output wire [71:0] wide_meta_o,
    input  wire                         clk_i,
    input  wire                         rst_n_i,
    input  wire                         shift_i,
    input  wire                         write_i,
    input  wire [1:0]                   write_index_i,
    input  wire                         preview_valid_we_i,
    input  wire                         preview_valid_d_i,
    input  wire                         preview_payload_we_i,
    input  wire [31:0]                  preview_addr_i,
    input  wire [`EDRV32_EPOCH_W-1:0]   preview_epoch_i,
    input  wire [31:0]                  preview_target0_i,
    input  wire [31:0]                  preview_target1_i,

    input  wire [31:0]                  addr_i,
    input  wire [`EDRV32_EPOCH_W-1:0]   epoch_i,
    input  wire                         predicted_taken0_i,
    input  wire [31:0]                  predicted_target0_i,
    input  wire [1:0]                   predictor_meta0_i,
    input  wire                         predicted_taken1_i,
    input  wire [31:0]                  predicted_target1_i,
    input  wire [1:0]                   predictor_meta1_i,

    output wire [31:0]                  addr_o,
    output wire [`EDRV32_EPOCH_W-1:0]   epoch_o,
    output wire                         predicted_taken0_o,
    output wire [31:0]                  predicted_target0_o,
    output wire [1:0]                   predictor_meta0_o,
    output wire                         predicted_taken1_o,
    output wire [31:0]                  predicted_target1_o,
    output wire [1:0]                   predictor_meta1_o,
    output wire                         preview_valid_o,
    output wire [31:0]                  preview_addr_o,
    output wire [`EDRV32_EPOCH_W-1:0]   preview_epoch_o,
    output wire [31:0]                  preview_target0_o,
    output wire [31:0]                  preview_target1_o
);

    reg [71:0] head_wide_meta_r;
    reg [71:0] tail_wide_meta_r;
    assign wide_meta_o = head_wide_meta_r;

    reg [31:0] head_addr_r;
    reg [`EDRV32_EPOCH_W-1:0] head_epoch_r;
    reg head_predicted_taken0_r;
    reg [31:0] head_predicted_target0_r;
    reg [1:0] head_predictor_meta0_r;
    reg head_predicted_taken1_r;
    reg [31:0] head_predicted_target1_r;
    reg [1:0] head_predictor_meta1_r;

    reg [31:0] tail_addr_r;
    reg [`EDRV32_EPOCH_W-1:0] tail_epoch_r;
    reg tail_predicted_taken0_r;
    reg [31:0] tail_predicted_target0_r;
    reg [1:0] tail_predictor_meta0_r;
    reg tail_predicted_taken1_r;
    reg [31:0] tail_predicted_target1_r;
    reg [1:0] tail_predictor_meta1_r;
    reg preview_valid_r;
    reg [31:0] preview_addr_r;
    reg [`EDRV32_EPOCH_W-1:0] preview_epoch_r;
    reg [31:0] preview_target0_r;
    reg [31:0] preview_target1_r;

    assign addr_o = head_addr_r;
    assign epoch_o = head_epoch_r;
    assign predicted_taken0_o = head_predicted_taken0_r;
    assign predicted_target0_o = head_predicted_target0_r;
    assign predictor_meta0_o = head_predictor_meta0_r;
    assign predicted_taken1_o = head_predicted_taken1_r;
    assign predicted_target1_o = head_predicted_target1_r;
    assign predictor_meta1_o = head_predictor_meta1_r;
    assign preview_valid_o = preview_valid_r;
    assign preview_addr_o = preview_addr_r;
    assign preview_epoch_o = preview_epoch_r;
    assign preview_target0_o = preview_target0_r;
    assign preview_target1_o = preview_target1_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            preview_valid_r <= 1'b0;
        else if (preview_valid_we_i)
            preview_valid_r <= preview_valid_d_i;
    end

    always @(posedge clk_i) begin
        if (preview_payload_we_i) begin
            preview_addr_r <= preview_addr_i;
            preview_epoch_r <= preview_epoch_i;
            preview_target0_r <= preview_target0_i;
            preview_target1_r <= preview_target1_i;
        end
    end

    // A simultaneous full-queue pop+push moves the old tail to the head and
    // writes the new request into the tail. For a one-entry queue the indexed
    // head write intentionally overrides the preceding invalid tail shift.
    always @(posedge clk_i) begin
        if (shift_i) begin
            head_wide_meta_r <= tail_wide_meta_r;
            head_addr_r <= tail_addr_r;
            head_epoch_r <= tail_epoch_r;
            head_predicted_taken0_r <= tail_predicted_taken0_r;
            head_predicted_target0_r <= tail_predicted_target0_r;
            head_predictor_meta0_r <= tail_predictor_meta0_r;
            head_predicted_taken1_r <= tail_predicted_taken1_r;
            head_predicted_target1_r <= tail_predicted_target1_r;
            head_predictor_meta1_r <= tail_predictor_meta1_r;
        end

        if (write_i) begin
            if (write_index_i == 2'd0) begin
                head_wide_meta_r <= wide_meta_i;
                head_addr_r <= addr_i;
                head_epoch_r <= epoch_i;
                head_predicted_taken0_r <= predicted_taken0_i;
                head_predicted_target0_r <= predicted_target0_i;
                head_predictor_meta0_r <= predictor_meta0_i;
                head_predicted_taken1_r <= predicted_taken1_i;
                head_predicted_target1_r <= predicted_target1_i;
                head_predictor_meta1_r <= predictor_meta1_i;
            end else begin
                tail_wide_meta_r <= wide_meta_i;
                tail_addr_r <= addr_i;
                tail_epoch_r <= epoch_i;
                tail_predicted_taken0_r <= predicted_taken0_i;
                tail_predicted_target0_r <= predicted_target0_i;
                tail_predictor_meta0_r <= predictor_meta0_i;
                tail_predicted_taken1_r <= predicted_taken1_i;
                tail_predicted_target1_r <= predicted_target1_i;
                tail_predictor_meta1_r <= predictor_meta1_i;
            end
        end
    end

endmodule
