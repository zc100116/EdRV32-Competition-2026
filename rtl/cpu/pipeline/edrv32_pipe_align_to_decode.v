// ============================================================================
// File        : edrv32_pipe_align_to_decode.v
// Description : Register bank for the ALIGN-to-DECODE boundary.
// Notes       : Handshake, flush, and occupancy decisions belong to ALIGN.
//               Every output below is driven only by a register in this file.
// ============================================================================
`include "edrv32_uop.vh"

module edrv32_pipe_align_to_decode (
    input  wire                         clk_i,
    input  wire                         rst_n_i,

    // Register controls computed by edrv32_align_stage.
    input  wire                         valid_we_i,
    input  wire                         valid_d_i,
    input  wire                         payload_we_i,

    // Canonical instruction data presented at the register inputs.
    input  wire [31:0]                  pc_i,
    input  wire [31:0]                  instr_i,
    input  wire [31:0]                  raw_instr_i,
    input  wire                         is_compressed_i,
    input  wire                         fetch_fault_i,
    input  wire                         compressed_illegal_i,
    input  wire [`EDRV32_EPOCH_W-1:0]   epoch_i,
    input  wire                         predicted_taken_i,
    input  wire [31:0]                  predicted_target_i,
    input  wire [1:0]                   predictor_meta_i,

    // Registered boundary state.
    output wire                         valid_o,
    output wire [31:0]                  pc_o,
    output wire [31:0]                  instr_o,
    output wire [31:0]                  raw_instr_o,
    output wire                         is_compressed_o,
    output wire                         fetch_fault_o,
    output wire                         compressed_illegal_o,
    output wire [`EDRV32_EPOCH_W-1:0]   epoch_o,
    output wire                         predicted_taken_o,
    output wire [31:0]                  predicted_target_o,
    output wire [1:0]                   predictor_meta_o
);

    reg                       valid_r;
    reg [31:0]                pc_r;
    reg [31:0]                instr_r;
    reg [31:0]                raw_instr_r;
    reg                       is_compressed_r;
    reg                       fetch_fault_r;
    reg                       compressed_illegal_r;
    reg [`EDRV32_EPOCH_W-1:0] epoch_r;
    reg                       predicted_taken_r;
    reg [31:0]                predicted_target_r;
    reg [1:0]                 predictor_meta_r;

    assign valid_o              = valid_r;
    assign pc_o                 = pc_r;
    assign instr_o              = instr_r;
    assign raw_instr_o          = raw_instr_r;
    assign is_compressed_o      = is_compressed_r;
    assign fetch_fault_o        = fetch_fault_r;
    assign compressed_illegal_o = compressed_illegal_r;
    assign epoch_o              = epoch_r;
    assign predicted_taken_o    = predicted_taken_r;
    assign predicted_target_o   = predicted_target_r;
    assign predictor_meta_o     = predictor_meta_r;

    // Only validity requires reset.  Invalid payload bits are unobservable.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            valid_r <= 1'b0;
        else if (valid_we_i)
            valid_r <= valid_d_i;
    end

    // The complete payload is one register bank with one write enable.
    always @(posedge clk_i) begin
        if (payload_we_i) begin
            pc_r                 <= pc_i;
            instr_r              <= instr_i;
            raw_instr_r          <= raw_instr_i;
            is_compressed_r      <= is_compressed_i;
            fetch_fault_r        <= fetch_fault_i;
            compressed_illegal_r <= compressed_illegal_i;
            epoch_r              <= epoch_i;
            predicted_taken_r    <= predicted_taken_i;
            predicted_target_r   <= predicted_target_i;
            predictor_meta_r     <= predictor_meta_i;
        end
    end

endmodule
