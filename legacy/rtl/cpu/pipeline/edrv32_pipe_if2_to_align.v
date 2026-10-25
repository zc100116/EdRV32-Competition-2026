// ============================================================================
// File        : edrv32_pipe_if2_to_align.v
// Description : Two-entry register bank for IF2 alignment windows.
// Notes       : IF2 owns formability, instruction length, occupancy, ready,
//               accept, flush, and queue movement.  Head outputs are registers.
// ============================================================================
`include "edrv32_uop.vh"

module edrv32_pipe_if2_to_align (
    input  wire                         clk_i,

    // Register write controls computed by edrv32_if2_stage.
    input  wire                         head_we_i,
    input  wire                         head_from_tail_i,
    input  wire                         tail_we_i,

    // Alignment-window data at the register inputs.
    input  wire [15:0]                  halfword0_i,
    input  wire [15:0]                  halfword1_i,
    input  wire                         halfword1_valid_i,
    input  wire [31:0]                  pc_i,
    input  wire                         halfword0_error_i,
    input  wire                         halfword1_error_i,
    input  wire [`EDRV32_EPOCH_W-1:0]   epoch_i,
    input  wire                         predicted_taken_i,
    input  wire [31:0]                  predicted_target_i,
    input  wire [1:0]                   predictor_meta_i,

    // Oldest registered alignment window.
    output wire [15:0]                  halfword0_o,
    output wire [15:0]                  halfword1_o,
    output wire                         halfword1_valid_o,
    output wire [31:0]                  pc_o,
    output wire                         halfword0_error_o,
    output wire                         halfword1_error_o,
    output wire [`EDRV32_EPOCH_W-1:0]   epoch_o,
    output wire                         predicted_taken_o,
    output wire [31:0]                  predicted_target_o,
    output wire [1:0]                   predictor_meta_o
);

    reg [15:0]                head_halfword0_r;
    reg [15:0]                head_halfword1_r;
    reg                       head_halfword1_valid_r;
    reg [31:0]                head_pc_r;
    reg                       head_halfword0_error_r;
    reg                       head_halfword1_error_r;
    reg [`EDRV32_EPOCH_W-1:0] head_epoch_r;
    reg                       head_predicted_taken_r;
    reg [31:0]                head_predicted_target_r;
    reg [1:0]                 head_predictor_meta_r;

    reg [15:0]                tail_halfword0_r;
    reg [15:0]                tail_halfword1_r;
    reg                       tail_halfword1_valid_r;
    reg [31:0]                tail_pc_r;
    reg                       tail_halfword0_error_r;
    reg                       tail_halfword1_error_r;
    reg [`EDRV32_EPOCH_W-1:0] tail_epoch_r;
    reg                       tail_predicted_taken_r;
    reg [31:0]                tail_predicted_target_r;
    reg [1:0]                 tail_predictor_meta_r;

    assign halfword0_o        = head_halfword0_r;
    assign halfword1_o        = head_halfword1_r;
    assign halfword1_valid_o  = head_halfword1_valid_r;
    assign pc_o               = head_pc_r;
    assign halfword0_error_o  = head_halfword0_error_r;
    assign halfword1_error_o  = head_halfword1_error_r;
    assign epoch_o            = head_epoch_r;
    assign predicted_taken_o  = head_predicted_taken_r;
    assign predicted_target_o = head_predicted_target_r;
    assign predictor_meta_o   = head_predictor_meta_r;

    always @(posedge clk_i) begin
        if (head_we_i) begin
            if (head_from_tail_i) begin
                head_halfword0_r        <= tail_halfword0_r;
                head_halfword1_r        <= tail_halfword1_r;
                head_halfword1_valid_r  <= tail_halfword1_valid_r;
                head_pc_r               <= tail_pc_r;
                head_halfword0_error_r  <= tail_halfword0_error_r;
                head_halfword1_error_r  <= tail_halfword1_error_r;
                head_epoch_r            <= tail_epoch_r;
                head_predicted_taken_r  <= tail_predicted_taken_r;
                head_predicted_target_r <= tail_predicted_target_r;
                head_predictor_meta_r   <= tail_predictor_meta_r;
            end else begin
                head_halfword0_r        <= halfword0_i;
                head_halfword1_r        <= halfword1_i;
                head_halfword1_valid_r  <= halfword1_valid_i;
                head_pc_r               <= pc_i;
                head_halfword0_error_r  <= halfword0_error_i;
                head_halfword1_error_r  <= halfword1_error_i;
                head_epoch_r            <= epoch_i;
                head_predicted_taken_r  <= predicted_taken_i;
                head_predicted_target_r <= predicted_target_i;
                head_predictor_meta_r   <= predictor_meta_i;
            end
        end
    end

    always @(posedge clk_i) begin
        if (tail_we_i) begin
            tail_halfword0_r        <= halfword0_i;
            tail_halfword1_r        <= halfword1_i;
            tail_halfword1_valid_r  <= halfword1_valid_i;
            tail_pc_r               <= pc_i;
            tail_halfword0_error_r  <= halfword0_error_i;
            tail_halfword1_error_r  <= halfword1_error_i;
            tail_epoch_r            <= epoch_i;
            tail_predicted_taken_r  <= predicted_taken_i;
            tail_predicted_target_r <= predicted_target_i;
            tail_predictor_meta_r   <= predictor_meta_i;
        end
    end

endmodule
