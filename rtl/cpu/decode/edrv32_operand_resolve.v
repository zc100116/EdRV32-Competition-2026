// ============================================================================
// File        : edrv32_operand_resolve.v
// Description : DECODE-local scalar integer operand selection from the register
//               file, the completed MDU slot, and registered pipeline bypass
//               records.
// Notes       : Priority is youngest older producer first. A matching producer
//               whose result is not ready blocks the operand; an older ready
//               producer must never be selected in its place.
// ============================================================================
`include "edrv32_isa.vh"
`include "edrv32_lsu.vh"
`include "edrv32_pair.vh"

module edrv32_operand_resolve #(
    parameter integer DUAL_ISSUE = 0
)(
    // Younger ALU in each registered parent packet.
    input  wire [`EDRV32_PAIR_RESULT_W-1:0] ex_second_i,
    input  wire [`EDRV32_PAIR_RESULT_W-1:0] mem1_second_i,
    input  wire [`EDRV32_PAIR_RESULT_W-1:0] mem2_second_i,
    input  wire [`EDRV32_PAIR_RESULT_W-1:0] commit_second_i,

    // Register-file value and resolved result for source operand 1.
    input  wire [4:0]  rs1_addr_i,
    input  wire        uses_rs1_i,
    input  wire [31:0] rs1_reg_data_i,
    output wire [31:0]                      rs1_value_o,
    output wire                             rs1_blocked_o,
    output wire                             rs1_mdu_o,
    output wire                             rs1_late_load_o,
    // Identity of the youngest matching unready load producer.  The PC
    // disambiguates two in-flight loads to the same rd: the EX-side capture
    // must only accept the value of this exact producer, never an older one.
    output wire [31:0]                      rs1_late_load_pc_o,
    output wire                             rs1_late_load_token_valid_o,
    output wire [`EDRV32_LSU_TOKEN_W-1:0]   rs1_late_load_token_o,

    // Register-file value and resolved result for source operand 2.
    input  wire [4:0]  rs2_addr_i,
    input  wire        uses_rs2_i,
    input  wire [31:0] rs2_reg_data_i,
    output wire [31:0]                      rs2_value_o,
    output wire                             rs2_blocked_o,
    output wire                             rs2_mdu_o,
    output wire                             rs2_late_load_o,
    output wire [31:0]                      rs2_late_load_pc_o,
    output wire                             rs2_late_load_token_valid_o,
    output wire [`EDRV32_LSU_TOKEN_W-1:0]   rs2_late_load_token_o,

    // Slot-owned age flags place the MDU among the ordinary pipeline records.
    // An unready younger writer must shadow a ready older MDU result as well.
    input  wire        mdu_valid_i,
    input  wire        mdu_ready_i,
    input  wire [4:0]  mdu_rd_i,
    input  wire [31:0] mdu_value_i,
    input  wire        mdu_passed_mem1_i,
    input  wire        mdu_passed_mem2_i,
    input  wire        mdu_authorized_i,

    // Producer records in youngest-to-oldest order.  A matching load that has
    // not produced its result yet is a late-load producer: the consumer is
    // released to EX and captures the value there, keyed by the producer PC.
    input  wire        ex_valid_i,
    input  wire        ex_write_i,
    input  wire        ex_ready_i,
    input  wire        ex_is_load_i,
    input  wire        ex_mdu_token_i,
    input  wire [31:0] ex_pc_i,
    input  wire [4:0]  ex_rd_i,
    input  wire [31:0] ex_value_i,
    input  wire        ex_lsu_token_valid_i,
    input  wire [`EDRV32_LSU_TOKEN_W-1:0] ex_lsu_token_i,

    input  wire        mem1_valid_i,
    input  wire        mem1_write_i,
    input  wire        mem1_ready_i,
    input  wire        mem1_is_load_i,
    input  wire [31:0] mem1_pc_i,
    input  wire [4:0]  mem1_rd_i,
    input  wire [31:0] mem1_value_i,
    input  wire        mem1_lsu_token_valid_i,
    input  wire [`EDRV32_LSU_TOKEN_W-1:0] mem1_lsu_token_i,

    input  wire        mem2_valid_i,
    input  wire        mem2_write_i,
    input  wire        mem2_ready_i,
    input  wire        mem2_is_load_i,
    input  wire [31:0] mem2_pc_i,
    input  wire [4:0]  mem2_rd_i,
    input  wire [31:0] mem2_value_i,
    input  wire        mem2_lsu_token_valid_i,
    input  wire [`EDRV32_LSU_TOKEN_W-1:0] mem2_lsu_token_i,

    input  wire        commit_valid_i,
    input  wire        commit_write_i,
    input  wire        commit_ready_i,
    input  wire [4:0]  commit_rd_i,
    input  wire [31:0] commit_value_i
);

    // Match every source against every older producer before choosing a value.
    // A match remains meaningful even when its value is not ready, because a
    // still older value for the same rd would be stale.
    wire  ex_second_valid_w;
    wire [31:0] ex_second_pc_w;
    wire [31:0] ex_second_instr_w;
    wire  ex_second_compressed_w;
    wire [`EDRV32_EPOCH_W-1:0] ex_second_epoch_w;
    wire [4:0] ex_second_rd_w;
    wire  ex_second_write_w;
    wire [31:0] ex_second_value_w;
    assign {ex_second_valid_w, ex_second_pc_w, ex_second_instr_w,
        ex_second_compressed_w, ex_second_epoch_w, ex_second_rd_w,
        ex_second_write_w, ex_second_value_w} = ex_second_i;
    wire  mem1_second_valid_w;
    wire [31:0] mem1_second_pc_w;
    wire [31:0] mem1_second_instr_w;
    wire  mem1_second_compressed_w;
    wire [`EDRV32_EPOCH_W-1:0] mem1_second_epoch_w;
    wire [4:0] mem1_second_rd_w;
    wire  mem1_second_write_w;
    wire [31:0] mem1_second_value_w;
    assign {mem1_second_valid_w, mem1_second_pc_w, mem1_second_instr_w,
        mem1_second_compressed_w, mem1_second_epoch_w, mem1_second_rd_w,
        mem1_second_write_w, mem1_second_value_w} = mem1_second_i;
    wire  mem2_second_valid_w;
    wire [31:0] mem2_second_pc_w;
    wire [31:0] mem2_second_instr_w;
    wire  mem2_second_compressed_w;
    wire [`EDRV32_EPOCH_W-1:0] mem2_second_epoch_w;
    wire [4:0] mem2_second_rd_w;
    wire  mem2_second_write_w;
    wire [31:0] mem2_second_value_w;
    assign {mem2_second_valid_w, mem2_second_pc_w, mem2_second_instr_w,
        mem2_second_compressed_w, mem2_second_epoch_w, mem2_second_rd_w,
        mem2_second_write_w, mem2_second_value_w} = mem2_second_i;
    wire  commit_second_valid_w;
    wire [31:0] commit_second_pc_w;
    wire [31:0] commit_second_instr_w;
    wire  commit_second_compressed_w;
    wire [`EDRV32_EPOCH_W-1:0] commit_second_epoch_w;
    wire [4:0] commit_second_rd_w;
    wire  commit_second_write_w;
    wire [31:0] commit_second_value_w;
    assign {commit_second_valid_w, commit_second_pc_w, commit_second_instr_w,
        commit_second_compressed_w, commit_second_epoch_w, commit_second_rd_w,
        commit_second_write_w, commit_second_value_w} = commit_second_i;

    wire mdu_rs1_address_match_w = uses_rs1_i && (rs1_addr_i != 5'd0) && mdu_valid_i &&
                           (mdu_rd_i != 5'd0) && (mdu_rd_i == rs1_addr_i);
    wire ex_rs1_primary_match_w = uses_rs1_i && (rs1_addr_i != 5'd0) && ex_valid_i &&
                          ex_write_i && (ex_rd_i != 5'd0) && (ex_rd_i == rs1_addr_i);
    wire ex_rs1_second_match_w = (DUAL_ISSUE != 0) &&
        ex_valid_i && ex_second_valid_w && ex_second_write_w &&
        uses_rs1_i && (rs1_addr_i != 5'd0) &&
        (ex_second_rd_w == rs1_addr_i);
    wire ex_rs1_match_w = ex_rs1_primary_match_w ||
        ex_rs1_second_match_w;
    wire mem1_rs1_primary_match_w = uses_rs1_i && (rs1_addr_i != 5'd0) &&
                            mem1_valid_i && mem1_write_i &&
                            (mem1_rd_i != 5'd0) && (mem1_rd_i == rs1_addr_i);
    wire mem1_rs1_second_match_w = (DUAL_ISSUE != 0) &&
        mem1_valid_i && mem1_second_valid_w && mem1_second_write_w &&
        uses_rs1_i && (rs1_addr_i != 5'd0) &&
        (mem1_second_rd_w == rs1_addr_i);
    wire mem1_rs1_match_w = mem1_rs1_primary_match_w ||
        mem1_rs1_second_match_w;
    wire mem2_rs1_primary_match_w = uses_rs1_i && (rs1_addr_i != 5'd0) &&
                            mem2_valid_i && mem2_write_i &&
                            (mem2_rd_i != 5'd0) && (mem2_rd_i == rs1_addr_i);
    wire mem2_rs1_second_match_w = (DUAL_ISSUE != 0) &&
        mem2_valid_i && mem2_second_valid_w && mem2_second_write_w &&
        uses_rs1_i && (rs1_addr_i != 5'd0) &&
        (mem2_second_rd_w == rs1_addr_i);
    wire mem2_rs1_match_w = mem2_rs1_primary_match_w ||
        mem2_rs1_second_match_w;
    wire commit_rs1_primary_match_w = uses_rs1_i && (rs1_addr_i != 5'd0) &&
                              commit_valid_i && commit_write_i &&
                              (commit_rd_i != 5'd0) && (commit_rd_i == rs1_addr_i);
    wire commit_rs1_second_match_w = (DUAL_ISSUE != 0) &&
        commit_valid_i && commit_second_valid_w && commit_second_write_w &&
        uses_rs1_i && (rs1_addr_i != 5'd0) &&
        (commit_second_rd_w == rs1_addr_i);
    wire commit_rs1_match_w = commit_rs1_primary_match_w ||
        commit_rs1_second_match_w;

    wire mdu_rs2_address_match_w = uses_rs2_i && (rs2_addr_i != 5'd0) && mdu_valid_i &&
                           (mdu_rd_i != 5'd0) && (mdu_rd_i == rs2_addr_i);
    wire ex_rs2_primary_match_w = uses_rs2_i && (rs2_addr_i != 5'd0) && ex_valid_i &&
                          ex_write_i && (ex_rd_i != 5'd0) && (ex_rd_i == rs2_addr_i);
    wire ex_rs2_second_match_w = (DUAL_ISSUE != 0) &&
        ex_valid_i && ex_second_valid_w && ex_second_write_w &&
        uses_rs2_i && (rs2_addr_i != 5'd0) &&
        (ex_second_rd_w == rs2_addr_i);
    wire ex_rs2_match_w = ex_rs2_primary_match_w ||
        ex_rs2_second_match_w;
    wire mem1_rs2_primary_match_w = uses_rs2_i && (rs2_addr_i != 5'd0) &&
                            mem1_valid_i && mem1_write_i &&
                            (mem1_rd_i != 5'd0) && (mem1_rd_i == rs2_addr_i);
    wire mem1_rs2_second_match_w = (DUAL_ISSUE != 0) &&
        mem1_valid_i && mem1_second_valid_w && mem1_second_write_w &&
        uses_rs2_i && (rs2_addr_i != 5'd0) &&
        (mem1_second_rd_w == rs2_addr_i);
    wire mem1_rs2_match_w = mem1_rs2_primary_match_w ||
        mem1_rs2_second_match_w;
    wire mem2_rs2_primary_match_w = uses_rs2_i && (rs2_addr_i != 5'd0) &&
                            mem2_valid_i && mem2_write_i &&
                            (mem2_rd_i != 5'd0) && (mem2_rd_i == rs2_addr_i);
    wire mem2_rs2_second_match_w = (DUAL_ISSUE != 0) &&
        mem2_valid_i && mem2_second_valid_w && mem2_second_write_w &&
        uses_rs2_i && (rs2_addr_i != 5'd0) &&
        (mem2_second_rd_w == rs2_addr_i);
    wire mem2_rs2_match_w = mem2_rs2_primary_match_w ||
        mem2_rs2_second_match_w;
    wire commit_rs2_primary_match_w = uses_rs2_i && (rs2_addr_i != 5'd0) &&
                              commit_valid_i && commit_write_i &&
                              (commit_rd_i != 5'd0) && (commit_rd_i == rs2_addr_i);
    wire commit_rs2_second_match_w = (DUAL_ISSUE != 0) &&
        commit_valid_i && commit_second_valid_w && commit_second_write_w &&
        uses_rs2_i && (rs2_addr_i != 5'd0) &&
        (commit_second_rd_w == rs2_addr_i);
    wire commit_rs2_match_w = commit_rs2_primary_match_w ||
        commit_rs2_second_match_w;

    // EX is replaced by the token on allocation, so every non-token EX record
    // seen while this MDU is pending is younger. MEM1/MEM2/COMMIT require their
    // registered stage-crossing flags before they may shadow the MDU.
    wire mdu_rs1_match_w = mdu_rs1_address_match_w &&
        !(ex_rs1_match_w && !ex_mdu_token_i) &&
        !(mem1_rs1_match_w && mdu_passed_mem1_i) &&
        !(mem2_rs1_match_w && mdu_passed_mem2_i) &&
        !(commit_rs1_match_w && mdu_authorized_i);
    wire mdu_rs2_match_w = mdu_rs2_address_match_w &&
        !(ex_rs2_match_w && !ex_mdu_token_i) &&
        !(mem1_rs2_match_w && mdu_passed_mem1_i) &&
        !(mem2_rs2_match_w && mdu_passed_mem2_i) &&
        !(commit_rs2_match_w && mdu_authorized_i);
    assign rs1_mdu_o = mdu_rs1_match_w;
    assign rs2_mdu_o = mdu_rs2_match_w;

    // The first matching producer wins.  Its ready bit decides whether DECODE
    // receives a bypass value or must hold the instruction.  An unready
    // matching load becomes a late-load producer: the consumer advances to EX
    // and captures the value there, keyed by the producer PC so an older
    // same-rd load can never satisfy the wait.
    reg [31:0]                      rs1_value_w;
    reg                             rs1_blocked_w;
    reg                             rs1_late_load_w;
    reg [31:0]                      rs1_late_load_pc_w;
    reg                             rs1_late_load_token_valid_w;
    reg [`EDRV32_LSU_TOKEN_W-1:0]   rs1_late_load_token_w;
    reg [31:0]                      rs2_value_w;
    reg                             rs2_blocked_w;
    reg                             rs2_late_load_w;
    reg [31:0]                      rs2_late_load_pc_w;
    reg                             rs2_late_load_token_valid_w;
    reg [`EDRV32_LSU_TOKEN_W-1:0]   rs2_late_load_token_w;

    assign rs1_value_o                  = rs1_value_w;
    assign rs1_blocked_o                = rs1_blocked_w;
    assign rs1_late_load_o              = rs1_late_load_w;
    assign rs1_late_load_pc_o           = rs1_late_load_pc_w;
    assign rs1_late_load_token_valid_o  = rs1_late_load_token_valid_w;
    assign rs1_late_load_token_o        = rs1_late_load_token_w;
    assign rs2_value_o                  = rs2_value_w;
    assign rs2_blocked_o                = rs2_blocked_w;
    assign rs2_late_load_o              = rs2_late_load_w;
    assign rs2_late_load_pc_o           = rs2_late_load_pc_w;
    assign rs2_late_load_token_valid_o  = rs2_late_load_token_valid_w;
    assign rs2_late_load_token_o        = rs2_late_load_token_w;

    always @* begin
        rs1_value_w   = (rs1_addr_i == 5'd0) ? 32'd0 : rs1_reg_data_i;
        rs1_blocked_w = 1'b0;
        rs1_late_load_w = 1'b0;
        rs1_late_load_pc_w = 32'd0;
        rs1_late_load_token_valid_w = 1'b0;
        rs1_late_load_token_w = {`EDRV32_LSU_TOKEN_W{1'b0}};
        if (mdu_rs1_match_w) begin
            rs1_value_w   = mdu_value_i;
            rs1_blocked_w = ~mdu_ready_i;
        end else if (ex_rs1_match_w) begin
            rs1_value_w = ex_rs1_second_match_w
                ? ex_second_value_w : ex_value_i;
            rs1_blocked_w = !ex_rs1_second_match_w && ~ex_ready_i;
            rs1_late_load_w = !ex_rs1_second_match_w &&
                ~ex_ready_i && ex_is_load_i;
            rs1_late_load_pc_w = ex_pc_i;
            rs1_late_load_token_valid_w = !ex_rs1_second_match_w &&
                ~ex_ready_i && ex_is_load_i &&
                                           ex_lsu_token_valid_i;
            rs1_late_load_token_w = ex_lsu_token_i;
        end else if (mem1_rs1_match_w) begin
            rs1_value_w = mem1_rs1_second_match_w
                ? mem1_second_value_w : mem1_value_i;
            rs1_blocked_w = !mem1_rs1_second_match_w && ~mem1_ready_i;
            rs1_late_load_w = !mem1_rs1_second_match_w &&
                ~mem1_ready_i && mem1_is_load_i;
            rs1_late_load_pc_w = mem1_pc_i;
            rs1_late_load_token_valid_w = !mem1_rs1_second_match_w &&
                ~mem1_ready_i && mem1_is_load_i &&
                                           mem1_lsu_token_valid_i;
            rs1_late_load_token_w = mem1_lsu_token_i;
        end else if (mem2_rs1_match_w) begin
            rs1_value_w = mem2_rs1_second_match_w
                ? mem2_second_value_w : mem2_value_i;
            rs1_blocked_w = !mem2_rs1_second_match_w && ~mem2_ready_i;
            rs1_late_load_w = !mem2_rs1_second_match_w &&
                ~mem2_ready_i && mem2_is_load_i;
            rs1_late_load_pc_w = mem2_pc_i;
            rs1_late_load_token_valid_w = !mem2_rs1_second_match_w &&
                ~mem2_ready_i && mem2_is_load_i &&
                                           mem2_lsu_token_valid_i;
            rs1_late_load_token_w = mem2_lsu_token_i;
        end else if (commit_rs1_match_w) begin
            rs1_value_w = commit_rs1_second_match_w
                ? commit_second_value_w : commit_value_i;
            rs1_blocked_w = !commit_rs1_second_match_w && ~commit_ready_i;
        end
    end

    always @* begin
        rs2_value_w   = (rs2_addr_i == 5'd0) ? 32'd0 : rs2_reg_data_i;
        rs2_blocked_w = 1'b0;
        rs2_late_load_w = 1'b0;
        rs2_late_load_pc_w = 32'd0;
        rs2_late_load_token_valid_w = 1'b0;
        rs2_late_load_token_w = {`EDRV32_LSU_TOKEN_W{1'b0}};
        if (mdu_rs2_match_w) begin
            rs2_value_w   = mdu_value_i;
            rs2_blocked_w = ~mdu_ready_i;
        end else if (ex_rs2_match_w) begin
            rs2_value_w = ex_rs2_second_match_w
                ? ex_second_value_w : ex_value_i;
            rs2_blocked_w = !ex_rs2_second_match_w && ~ex_ready_i;
            rs2_late_load_w = !ex_rs2_second_match_w &&
                ~ex_ready_i && ex_is_load_i;
            rs2_late_load_pc_w = ex_pc_i;
            rs2_late_load_token_valid_w = !ex_rs2_second_match_w &&
                ~ex_ready_i && ex_is_load_i &&
                                           ex_lsu_token_valid_i;
            rs2_late_load_token_w = ex_lsu_token_i;
        end else if (mem1_rs2_match_w) begin
            rs2_value_w = mem1_rs2_second_match_w
                ? mem1_second_value_w : mem1_value_i;
            rs2_blocked_w = !mem1_rs2_second_match_w && ~mem1_ready_i;
            rs2_late_load_w = !mem1_rs2_second_match_w &&
                ~mem1_ready_i && mem1_is_load_i;
            rs2_late_load_pc_w = mem1_pc_i;
            rs2_late_load_token_valid_w = !mem1_rs2_second_match_w &&
                ~mem1_ready_i && mem1_is_load_i &&
                                           mem1_lsu_token_valid_i;
            rs2_late_load_token_w = mem1_lsu_token_i;
        end else if (mem2_rs2_match_w) begin
            rs2_value_w = mem2_rs2_second_match_w
                ? mem2_second_value_w : mem2_value_i;
            rs2_blocked_w = !mem2_rs2_second_match_w && ~mem2_ready_i;
            rs2_late_load_w = !mem2_rs2_second_match_w &&
                ~mem2_ready_i && mem2_is_load_i;
            rs2_late_load_pc_w = mem2_pc_i;
            rs2_late_load_token_valid_w = !mem2_rs2_second_match_w &&
                ~mem2_ready_i && mem2_is_load_i &&
                                           mem2_lsu_token_valid_i;
            rs2_late_load_token_w = mem2_lsu_token_i;
        end else if (commit_rs2_match_w) begin
            rs2_value_w = commit_rs2_second_match_w
                ? commit_second_value_w : commit_value_i;
            rs2_blocked_w = !commit_rs2_second_match_w && ~commit_ready_i;
        end
    end

endmodule
