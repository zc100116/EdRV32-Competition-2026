// ============================================================================
// File        : edrv32_decode_stage.v
// Description : Decodes one canonical instruction, resolves its register
//               operands from the youngest available producer, and issues a
//               complete scalar uop after dependency and capacity checks pass.
// ============================================================================
`include "edrv32_isa.vh"
`include "edrv32_uop.vh"
`include "edrv32_pair.vh"
`include "edrv32_bus.vh"
`include "edrv32_exception.vh"
`include "edrv32_lsu.vh"

// The stage directly owns its execution logic and outgoing registered boundary.
module edrv32_decode_stage #(
    parameter integer DUAL_ISSUE = 0
)(
    input  wire                         clk_i,
    input  wire                         rst_n_i,

    output wire resident_second_rs1_o,
    output wire resident_second_rs2_o,

    // Optional younger candidate and architectural second write port.
    input  wire                             second_valid_i,
    input  wire [31:0]                      second_pc_i,
    input  wire [31:0]                      second_instr_i,
    input  wire [31:0]                      second_raw_instr_i,
    input  wire                             second_is_compressed_i,
    input  wire                             second_fetch_fault_i,
    input  wire                             second_compressed_illegal_i,
    input  wire [`EDRV32_EPOCH_W-1:0]       second_epoch_i,
    input  wire                             second_predicted_taken_i,
    input  wire [31:0]                      second_predicted_target_i,
    input  wire [1:0]                       second_predictor_meta_i,
    output wire                             second_ready_o,
    output wire [`EDRV32_PAIR_DECODE_W-1:0] second_o,
    input  wire                             commit_second_write_i,
    input  wire [4:0]                       commit_second_rd_i,
    input  wire [31:0]                      commit_second_value_i,
    input  wire [`EDRV32_PAIR_RESULT_W-1:0] ex_second_i,
    input  wire [`EDRV32_PAIR_RESULT_W-1:0] mem1_second_i,
    input  wire [`EDRV32_PAIR_RESULT_W-1:0] mem2_second_i,
    input  wire [`EDRV32_PAIR_RESULT_W-1:0] commit_second_i,

    // Registered canonical instruction from ALIGN.
    input  wire                         valid_i,
    output wire                         ready_o,
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

    // Architectural GPR writeback.
    input  wire                         commit_rd_write_i,
    input  wire [4:0]                   commit_rd_i,
    input  wire [31:0]                  commit_rd_value_i,

    // Registered bypass records, youngest to oldest.
    input  wire                         ex_bypass_valid_i,
    input  wire                         ex_bypass_write_i,
    input  wire                         ex_bypass_ready_i,
    input  wire                         ex_bypass_is_load_i,
    input  wire                         ex_bypass_mdu_token_i,
    input  wire [31:0]                  ex_bypass_pc_i,
    input  wire [4:0]                   ex_bypass_rd_i,
    input  wire [31:0]                  ex_bypass_value_i,
    input  wire                         ex_bypass_lsu_token_valid_i,
    input  wire [`EDRV32_LSU_TOKEN_W-1:0] ex_bypass_lsu_token_i,
    input  wire                         mem1_bypass_valid_i,
    input  wire                         mem1_bypass_write_i,
    input  wire                         mem1_bypass_ready_i,
    input  wire                         mem1_bypass_is_load_i,
    input  wire [31:0]                  mem1_bypass_pc_i,
    input  wire [4:0]                   mem1_bypass_rd_i,
    input  wire [31:0]                  mem1_bypass_value_i,
    input  wire                         mem1_bypass_lsu_token_valid_i,
    input  wire [`EDRV32_LSU_TOKEN_W-1:0] mem1_bypass_lsu_token_i,
    input  wire                         mem2_bypass_valid_i,
    input  wire                         mem2_bypass_write_i,
    input  wire                         mem2_bypass_ready_i,
    input  wire                         mem2_bypass_is_load_i,
    input  wire [31:0]                  mem2_bypass_pc_i,
    input  wire [4:0]                   mem2_bypass_rd_i,
    input  wire [31:0]                  mem2_bypass_value_i,
    input  wire                         mem2_bypass_lsu_token_valid_i,
    input  wire [`EDRV32_LSU_TOKEN_W-1:0] mem2_bypass_lsu_token_i,
    input  wire                         commit_bypass_valid_i,
    input  wire                         commit_bypass_write_i,
    input  wire                         commit_bypass_ready_i,
    input  wire [4:0]                   commit_bypass_rd_i,
    input  wire [31:0]                  commit_bypass_value_i,

    // Completed long-latency producer and issue-capacity hazards.
    input  wire                         mdu_bypass_valid_i,
    input  wire                         mdu_bypass_ready_i,
    input  wire [4:0]                   mdu_bypass_rd_i,
    input  wire [31:0]                  mdu_bypass_value_i,
    input  wire                         mdu_passed_mem1_i,
    input  wire                         mdu_passed_mem2_i,
    input  wire                         mdu_authorized_i,
    input  wire                         mdu_waw_hazard_i,
    input  wire                         mdu_issue_ready_i,
    input  wire                         issue_block_i,
    output wire [4:0]                   hazard_rs1_addr_o,
    output wire                         hazard_uses_rs1_o,
    output wire [4:0]                   hazard_rs2_addr_o,
    output wire                         hazard_uses_rs2_o,
    output wire [4:0]                   hazard_rd_addr_o,
    output wire                         hazard_rd_write_o,
    output wire                         dependency_stall_o,
    output wire                         structural_stall_o,
    // Mutual-exclusion HPM attribution: one-hot dependency-stall causes and
    // the consumer class of the candidate currently waiting at this boundary.
    output wire                         hpm_stall_resident_o,
    output wire                         hpm_stall_load_o,
    output wire                         hpm_stall_mdu_o,
    output wire                         hpm_stall_waw_o,
    output wire                         hazard_mdu_rs1_o,
    output wire                         hazard_mdu_rs2_o,
    output wire [1:0]                   hpm_candidate_class_o,

    // Registered decoded uop presented to EX.
    output wire                         valid_o,
    input  wire                         ready_i,
    output wire [31:0]                  pc_o,
    output wire [31:0]                  instr_o,
    output wire                         is_compressed_o,
    output wire [`EDRV32_EPOCH_W-1:0]   epoch_o,
    output wire                         predicted_taken_o,
    output wire [31:0]                  predicted_target_o,
    output wire [1:0]                   predictor_meta_o,
    output wire [4:0]                   rd_o,
    output wire                         rd_write_o,
    output wire [`EDRV32_OP_CLASS_W-1:0] op_class_o,
    output wire [`EDRV32_ALU_OP_W-1:0]  alu_op_o,
    output wire [`EDRV32_BRANCH_OP_W-1:0] branch_op_o,
    output wire [`BUS_SZ_W-1:0]         mem_size_o,
    output wire                         mem_unsigned_o,
    output wire [`EDRV32_MDU_OP_W-1:0]  mdu_op_o,
    output wire [`EDRV32_CSR_OP_W-1:0]  csr_op_o,
    output wire [11:0]                  csr_addr_o,
    output wire [31:0]                  csr_src_o,
    output wire [31:0]                  lhs_o,
    output wire [31:0]                  rhs_o,
    output wire [31:0]                  rs2_value_o,
    output wire                         resident_bypass_rs1_o,
    output wire                         resident_bypass_rs2_o,
    output wire [31:0]                  resident_bypass_pc_o,
    output wire                         late_mdu_rs1_o,
    output wire                         late_mdu_rs2_o,
    output wire                         late_load_rs1_o,
    output wire                         late_load_rs2_o,
    output wire [31:0]                  late_load_rs1_pc_o,
    output wire [31:0]                  late_load_rs2_pc_o,
    output wire                         late_load_rs1_token_valid_o,
    output wire [`EDRV32_LSU_TOKEN_W-1:0] late_load_rs1_token_o,
    output wire                         late_load_rs2_token_valid_o,
    output wire [`EDRV32_LSU_TOKEN_W-1:0] late_load_rs2_token_o,
    output wire [31:0]                  imm_o,
    output wire                         fence_o,
    output wire                         fencei_o,
    output wire                         mret_o,
    output wire                         wfi_o,
    output wire                         exception_valid_o,
    output wire [`EDRV32_EXC_CAUSE_W-1:0] exception_cause_o,
    output wire [31:0]                  exception_tval_o,

    input  wire                         frontend_kill_i,
    input  wire                         boundary_kill_i
);

    wire                         candidate_valid_w;
    wire                         candidate_ready_w;
    wire [31:0]                  candidate_pc_w;
    wire [31:0]                  candidate_instr_w;
    wire                         candidate_is_compressed_w;
    wire [`EDRV32_EPOCH_W-1:0]   candidate_epoch_w;
    wire                         candidate_predicted_taken_w;
    wire [31:0]                  candidate_predicted_target_w;
    wire [1:0]                   candidate_predictor_meta_w;
    wire [4:0]                   candidate_rd_w;
    wire                         candidate_rd_write_w;
    wire [`EDRV32_OP_CLASS_W-1:0] candidate_op_class_w;
    wire [`EDRV32_ALU_OP_W-1:0]  candidate_alu_op_w;
    wire [`EDRV32_BRANCH_OP_W-1:0] candidate_branch_op_w;
    wire [`BUS_SZ_W-1:0]         candidate_mem_size_w;
    wire                         candidate_mem_unsigned_w;
    wire [`EDRV32_MDU_OP_W-1:0]  candidate_mdu_op_w;
    wire [`EDRV32_CSR_OP_W-1:0]  candidate_csr_op_w;
    wire [11:0]                  candidate_csr_addr_w;
    wire [31:0]                  candidate_csr_src_w;
    wire [31:0]                  candidate_lhs_w;
    wire [31:0]                  candidate_rhs_w;
    wire [31:0]                  candidate_rs2_value_w;
    wire                         candidate_resident_bypass_rs1_w;
    wire                         candidate_resident_bypass_rs2_w;
    wire [31:0]                  candidate_resident_bypass_pc_w;
    wire [31:0]                  candidate_imm_w;
    wire                         candidate_fence_w;
    wire                         candidate_fencei_w;
    wire                         candidate_mret_w;
    wire                         candidate_wfi_w;
    wire                         candidate_exception_valid_w;
    wire [`EDRV32_EXC_CAUSE_W-1:0] candidate_exception_cause_w;
    wire [31:0]                  candidate_exception_tval_w;
    wire                         pipe_capture_w;
    wire                         pipe_transfer_w;
    wire                         pipe_valid_we_w;
    wire                         pipe_valid_d_w;


    // Stage-local execution logic is written directly in this module.


    wire [4:0] dec_rs1_w;
    wire [4:0] dec_rs2_w;
    wire [4:0] dec_rd_w;
    wire dec_uses_rs1_w;
    wire dec_uses_rs2_w;
    wire dec_rd_write_w;
    wire [`EDRV32_OP_CLASS_W-1:0] dec_op_class_w;
    wire [`EDRV32_ALU_OP_W-1:0] dec_alu_op_w;
    wire [`EDRV32_OP_A_SEL_W-1:0] dec_op_a_sel_w;
    wire dec_op_b_imm_w;
    wire [`EDRV32_IMM_SEL_W-1:0] dec_imm_sel_w;
    wire [`EDRV32_BRANCH_OP_W-1:0] dec_branch_op_w;
    wire [`BUS_SZ_W-1:0] dec_mem_size_w;
    wire dec_mem_unsigned_w;
    wire [`EDRV32_MDU_OP_W-1:0] dec_mdu_op_w;
    wire [`EDRV32_CSR_OP_W-1:0] dec_csr_op_w;
    wire dec_csr_imm_w;
    wire dec_fence_w;
    wire dec_fencei_w;
    wire dec_ecall_w;
    wire dec_ebreak_w;
    wire dec_mret_w;
    wire dec_wfi_w;
    wire dec_illegal_w;

    wire [31:0] immediate_w;
    wire [31:0] rs1_reg_data_w;
    wire [31:0] rs2_reg_data_w;
    wire [31:0] rs1_value_w;
    wire [31:0] rs2_value_w;
    wire rs1_blocked_w;
    wire rs2_blocked_w;
    wire rs1_late_load_w;
    wire rs2_late_load_w;
    wire [31:0] rs1_late_load_pc_w;
    wire [31:0] rs2_late_load_pc_w;
    wire rs1_late_load_token_valid_w;
    wire [`EDRV32_LSU_TOKEN_W-1:0] rs1_late_load_token_w;
    wire rs2_late_load_token_valid_w;
    wire [`EDRV32_LSU_TOKEN_W-1:0] rs2_late_load_token_w;
    wire rs1_mdu_w;
    wire rs2_mdu_w;
    wire selected_mdu_rs1_w = rs1_mdu_w && !resident_rs1_hazard_w &&
        !resident_second_rs1_hazard_w;
    wire selected_mdu_rs2_w = rs2_mdu_w && !resident_rs2_hazard_w &&
        !resident_second_rs2_hazard_w;

    reg [31:0] selected_lhs_w;
    wire [31:0] selected_rhs_w = dec_op_b_imm_w ? immediate_w : rs2_value_w;
    wire [31:0] csr_src_w = dec_csr_imm_w ? immediate_w : rs1_value_w;

    reg exception_valid_w;
    reg [`EDRV32_EXC_CAUSE_W-1:0] exception_cause_w;
    reg [31:0] exception_tval_w;

    // The DECODE-to-EX resident is younger than every external bypass source.
    // During a same-cycle transfer/refill it has not yet appeared at the EX
    // bypass record, so a dependent replacement instruction waits one cycle.
    wire resident_rs1_hazard_w = valid_o && rd_write_o &&
                                 (rd_o != 5'd0) && dec_uses_rs1_w &&
                                 (dec_rs1_w == rd_o);
    wire resident_rs2_hazard_w = valid_o && rd_write_o &&
                                 (rd_o != 5'd0) && dec_uses_rs2_w &&
                                 (dec_rs2_w == rd_o);
    wire resident_raw_hazard_w = resident_rs1_hazard_w ||
                                 resident_rs2_hazard_w;
    wire resident_forwardable_w = valid_o && rd_write_o &&
        !exception_valid_o &&
        ((op_class_o == `EDRV32_OP_ALU) ||
         (op_class_o == `EDRV32_OP_JUMP));
    wire resident_bypass_rs1_w = (resident_rs1_hazard_w &&
        resident_forwardable_w) || resident_second_rs1_hazard_w;
    wire resident_bypass_rs2_w = (resident_rs2_hazard_w &&
        resident_forwardable_w) || resident_second_rs2_hazard_w;
    // A resident MDU allocates its protected slot on the same edge that a
    // short consumer refills DECODE. No consumer can capture while that MDU
    // is held: candidate_ready_w still requires the resident transfer.
    wire resident_mdu_w = valid_o && rd_write_o && !exception_valid_o &&
                          (op_class_o == `EDRV32_OP_MDU);
    wire resident_mdu_eligible_w = resident_mdu_w && late_mdu_eligible_w;
    wire resident_mdu_rs1_w = resident_rs1_hazard_w && resident_mdu_eligible_w;
    wire resident_mdu_rs2_w = resident_rs2_hazard_w && resident_mdu_eligible_w;
    wire resident_blocked_w = resident_raw_hazard_w &&
                              !resident_forwardable_w && !resident_mdu_eligible_w;

    edrv32_decoder u_decoder (
        // Canonical 32-bit instruction being decoded.
        .instr_i(instr_i),

        // Register identities and access intent.
        .rs1_addr_o(dec_rs1_w),
        .rs2_addr_o(dec_rs2_w),
        .rd_addr_o(dec_rd_w),
        .uses_rs1_o(dec_uses_rs1_w),
        .uses_rs2_o(dec_uses_rs2_w),
        .rd_write_o(dec_rd_write_w),

        // Integer execution controls.
        .op_class_o(dec_op_class_w),
        .alu_op_o(dec_alu_op_w),
        .op_a_sel_o(dec_op_a_sel_w),
        .op_b_imm_o(dec_op_b_imm_w),
        .imm_sel_o(dec_imm_sel_w),
        .branch_op_o(dec_branch_op_w),

        // Memory, MDU and CSR controls.
        .mem_size_o(dec_mem_size_w),
        .mem_unsigned_o(dec_mem_unsigned_w),
        .mdu_op_o(dec_mdu_op_w),
        .csr_op_o(dec_csr_op_w),
        .csr_imm_o(dec_csr_imm_w),

        // Ordering and privileged instruction flags.
        .fence_o(dec_fence_w),
        .fencei_o(dec_fencei_w),
        .ecall_o(dec_ecall_w),
        .ebreak_o(dec_ebreak_w),
        .mret_o(dec_mret_w),
        .wfi_o(dec_wfi_w),
        .illegal_o(dec_illegal_w)
    );

    edrv32_immgen u_immgen (
        .instr_i(instr_i),
        .imm_sel_i(dec_imm_sel_w),
        .imm_o(immediate_w)
    );

    edrv32_regfile #(.SECOND_ENABLE(DUAL_ISSUE)) u_regfile (
        .clk_i(clk_i),
        .second_rs1_addr_i(second_rs1_w),
        .second_rs2_addr_i(second_rs2_w),
        .second_rs1_data_o(second_rs1_reg_w),
        .second_rs2_data_o(second_rs2_reg_w),
        .second_rd_write_i(commit_second_write_i),
        .second_rd_addr_i(commit_second_rd_i),
        .second_rd_data_i(commit_second_value_i),

        // Two combinational read ports.
        .rs1_addr_i(dec_rs1_w),
        .rs1_data_o(rs1_reg_data_w),
        .rs2_addr_i(dec_rs2_w),
        .rs2_data_o(rs2_reg_data_w),

        // Single architectural write port from COMMIT.
        .rd_write_i(commit_rd_write_i),
        .rd_addr_i(commit_rd_i),
        .rd_data_i(commit_rd_value_i)
    );

    edrv32_operand_resolve #(.DUAL_ISSUE(DUAL_ISSUE)) u_operand_resolve (
        .ex_second_i(ex_second_i),
        .mem1_second_i(mem1_second_i),
        .mem2_second_i(mem2_second_i),
        .commit_second_i(commit_second_i),
        // First source operand and its resolution result.
        .rs1_addr_i(dec_rs1_w),
        .uses_rs1_i(dec_uses_rs1_w),
        .rs1_reg_data_i(rs1_reg_data_w),
        .rs1_value_o(rs1_value_w),
        .rs1_blocked_o(rs1_blocked_w),
        .rs1_mdu_o(rs1_mdu_w),
        .rs1_late_load_o(rs1_late_load_w),
        .rs1_late_load_pc_o(rs1_late_load_pc_w),
        .rs1_late_load_token_valid_o(rs1_late_load_token_valid_w),
        .rs1_late_load_token_o(rs1_late_load_token_w),

        // Second source operand and its resolution result.
        .rs2_addr_i(dec_rs2_w),
        .uses_rs2_i(dec_uses_rs2_w),
        .rs2_reg_data_i(rs2_reg_data_w),
        .rs2_value_o(rs2_value_w),
        .rs2_blocked_o(rs2_blocked_w),
        .rs2_mdu_o(rs2_mdu_w),
        .rs2_late_load_o(rs2_late_load_w),
        .rs2_late_load_pc_o(rs2_late_load_pc_w),
        .rs2_late_load_token_valid_o(rs2_late_load_token_valid_w),
        .rs2_late_load_token_o(rs2_late_load_token_w),

        // Completed MDU data is registered locally by the MDU.  Keeping its
        // pending record valid until architectural writeback preserves WAW
        // protection while allowing a matching consumer to use the value.
        .mdu_valid_i(mdu_bypass_valid_i),
        .mdu_ready_i(mdu_bypass_ready_i),
        .mdu_rd_i(mdu_bypass_rd_i),
        .mdu_value_i(mdu_bypass_value_i),
        .mdu_passed_mem1_i(mdu_passed_mem1_i),
        .mdu_passed_mem2_i(mdu_passed_mem2_i),
        .mdu_authorized_i(mdu_authorized_i),

        // Youngest-to-oldest producer records.
        .ex_valid_i(ex_bypass_valid_i),
        .ex_write_i(ex_bypass_write_i),
        .ex_ready_i(ex_bypass_ready_i),
        .ex_is_load_i(ex_bypass_is_load_i),
        .ex_mdu_token_i(ex_bypass_mdu_token_i),
        .ex_pc_i(ex_bypass_pc_i),
        .ex_rd_i(ex_bypass_rd_i),
        .ex_value_i(ex_bypass_value_i),
        .ex_lsu_token_valid_i(ex_bypass_lsu_token_valid_i),
        .ex_lsu_token_i(ex_bypass_lsu_token_i),

        .mem1_valid_i(mem1_bypass_valid_i),
        .mem1_write_i(mem1_bypass_write_i),
        .mem1_ready_i(mem1_bypass_ready_i),
        .mem1_is_load_i(mem1_bypass_is_load_i),
        .mem1_pc_i(mem1_bypass_pc_i),
        .mem1_rd_i(mem1_bypass_rd_i),
        .mem1_value_i(mem1_bypass_value_i),
        .mem1_lsu_token_valid_i(mem1_bypass_lsu_token_valid_i),
        .mem1_lsu_token_i(mem1_bypass_lsu_token_i),

        .mem2_valid_i(mem2_bypass_valid_i),
        .mem2_write_i(mem2_bypass_write_i),
        .mem2_ready_i(mem2_bypass_ready_i),
        .mem2_is_load_i(mem2_bypass_is_load_i),
        .mem2_pc_i(mem2_bypass_pc_i),
        .mem2_rd_i(mem2_bypass_rd_i),
        .mem2_value_i(mem2_bypass_value_i),
        .mem2_lsu_token_valid_i(mem2_bypass_lsu_token_valid_i),
        .mem2_lsu_token_i(mem2_bypass_lsu_token_i),

        .commit_valid_i(commit_bypass_valid_i),
        .commit_write_i(commit_bypass_write_i),
        .commit_ready_i(commit_bypass_ready_i),
        .commit_rd_i(commit_bypass_rd_i),
        .commit_value_i(commit_bypass_value_i)
    );

    always @* begin
        case (dec_op_a_sel_w)
            `EDRV32_OP_A_PC:   selected_lhs_w = pc_i;
            `EDRV32_OP_A_ZERO: selected_lhs_w = 32'd0;
            default:           selected_lhs_w = rs1_value_w;
        endcase
    end

    always @* begin
        exception_valid_w = 1'b0;
        exception_cause_w = `EDRV32_EXC_ILLEGAL_INSTR;
        exception_tval_w  = 32'd0;
        if (fetch_fault_i) begin
            exception_valid_w = 1'b1;
            exception_cause_w = `EDRV32_EXC_INSTR_ACCESS;
            exception_tval_w  = pc_i;
        end else if (compressed_illegal_i || dec_illegal_w) begin
            exception_valid_w = 1'b1;
            exception_cause_w = `EDRV32_EXC_ILLEGAL_INSTR;
            exception_tval_w  = raw_instr_i;
        end else if (dec_ebreak_w) begin
            exception_valid_w = 1'b1;
            exception_cause_w = `EDRV32_EXC_BREAKPOINT;
            exception_tval_w  = 32'd0;
        end else if (dec_ecall_w) begin
            exception_valid_w = 1'b1;
            exception_cause_w = `EDRV32_EXC_ECALL_M;
            exception_tval_w  = 32'd0;
        end
    end

    assign hazard_rs1_addr_o = dec_rs1_w;
    assign hazard_uses_rs1_o = dec_uses_rs1_w;
    assign hazard_rs2_addr_o = dec_rs2_w;
    assign hazard_uses_rs2_o = dec_uses_rs2_w;
    assign hazard_rd_addr_o  = dec_rd_w;
    assign hazard_rd_write_o = dec_rd_write_w;

    // Fetch/compressed faults are already registered by the frontend and may
    // bypass an unrelated backend capacity block.  Synchronous exceptions
    // discovered by this decoder use side-effect-free decode defaults and can
    // wait in program order when the backend is full.  Keeping dec_illegal,
    // ECALL and EBREAK out of the ready cone prevents the full decoder from
    // feeding back through ALIGN into the IF2 buffer write enables.
    wire frontend_exception_w = fetch_fault_i || compressed_illegal_i;

    // Short consumers may reserve EX while the sole MDU producer is pending.
    // Ordinary same-rd writers may issue in order; the age-aware resolver
    // selects them ahead of the MDU. A new MDU still waits for the sole slot.
    wire late_mdu_eligible_w = (dec_op_class_w == `EDRV32_OP_ALU) ||
        (dec_op_class_w == `EDRV32_OP_LOAD) ||
        (dec_op_class_w == `EDRV32_OP_STORE);
    wire late_mdu_rs1_w = resident_mdu_rs1_w ||
        (late_mdu_eligible_w && selected_mdu_rs1_w && !mdu_bypass_ready_i);
    wire late_mdu_rs2_w = resident_mdu_rs2_w ||
        (late_mdu_eligible_w && selected_mdu_rs2_w && !mdu_bypass_ready_i);
    wire mdu_raw_blocked_w = (selected_mdu_rs1_w || selected_mdu_rs2_w) &&
        !mdu_bypass_ready_i &&
        !(late_mdu_rs1_w || late_mdu_rs2_w);
    wire mdu_waw_blocked_w = mdu_waw_hazard_i &&
        (dec_op_class_w == `EDRV32_OP_MDU);
    wire rs1_hard_blocked_w = rs1_blocked_w && !rs1_late_load_w &&
        !late_mdu_rs1_w && !resident_bypass_rs1_w;
    wire rs2_hard_blocked_w = rs2_blocked_w && !rs2_late_load_w &&
        !late_mdu_rs2_w && !resident_bypass_rs2_w;

    assign dependency_stall_o = valid_i && !frontend_exception_w &&
                                (rs1_hard_blocked_w || rs2_hard_blocked_w ||
                                 primary_resident_second_raw_w ||
                                 resident_blocked_w ||
                                 mdu_raw_blocked_w ||
                                 mdu_waw_blocked_w);
    assign structural_stall_o = valid_i && !frontend_exception_w &&
                                (issue_block_i ||
                                 ((dec_op_class_w == `EDRV32_OP_MDU) &&
                                  !mdu_issue_ready_i));

    // One-hot dependency-stall cause split for the empty-retire attribution.
    // The MDU term wins whenever the scoreboard participates, because an MDU
    // pending match also appears as a hard-blocked operand in operand_resolve.
    assign hpm_stall_resident_o = valid_i && !frontend_exception_w &&
                                  (resident_blocked_w || primary_resident_second_raw_w);
    assign hpm_stall_load_o = valid_i && !frontend_exception_w &&
                              (rs1_hard_blocked_w || rs2_hard_blocked_w) &&
                              !(mdu_raw_blocked_w ||
                                mdu_waw_blocked_w);
    assign hpm_stall_mdu_o = valid_i && !frontend_exception_w &&
                             (mdu_raw_blocked_w ||
                              mdu_waw_blocked_w);
    assign hpm_stall_waw_o = valid_i && !frontend_exception_w && mdu_waw_blocked_w;
    assign hazard_mdu_rs1_o = selected_mdu_rs1_w;
    assign hazard_mdu_rs2_o = selected_mdu_rs2_w;

    // B may name an older resident ALU whose result will be registered in EX
    // on this transfer. Same-group RAW still cannot form an ALU cascade.
    wire [4:0] second_rs1_w;
    wire [4:0] second_rs2_w;
    wire [4:0] second_rd_w;
    wire second_uses_rs1_w;
    wire second_uses_rs2_w;
    wire second_write_w;
    wire [`EDRV32_OP_CLASS_W-1:0] second_class_w;
    wire [`EDRV32_ALU_OP_W-1:0] second_alu_w;
    wire [`EDRV32_OP_A_SEL_W-1:0] second_a_sel_w;
    wire second_b_imm_w;
    wire [`EDRV32_IMM_SEL_W-1:0] second_imm_sel_w;
    wire second_illegal_w;
    wire [31:0] second_immediate_w;
    wire [31:0] second_rs1_reg_w;
    wire [31:0] second_rs2_reg_w;
    wire [31:0] second_rs1_value_w;
    wire [31:0] second_rs2_value_w;
    wire second_rs1_blocked_w;
    wire second_rs2_blocked_w;
    wire resident_second_valid_w;
    wire [31:0] resident_second_pc_w;
    wire [31:0] resident_second_instr_w;
    wire resident_second_compressed_w;
    wire [`EDRV32_EPOCH_W-1:0] resident_second_epoch_w;
    wire [4:0] resident_second_rd_w;
    wire resident_second_write_w;
    wire [`EDRV32_ALU_OP_W-1:0] resident_second_alu_w;
    wire [31:0] resident_second_lhs_w;
    wire [31:0] resident_second_rhs_w;
    wire [1:0] resident_second_lhs_source_w;
    wire [1:0] resident_second_rhs_source_w;
    assign {resident_second_valid_w, resident_second_pc_w, resident_second_instr_w,
        resident_second_compressed_w, resident_second_epoch_w, resident_second_rd_w,
        resident_second_write_w, resident_second_alu_w,
        resident_second_lhs_w, resident_second_rhs_w,
        resident_second_lhs_source_w, resident_second_rhs_source_w} = second_o;

    edrv32_decoder u_second_decoder (
        .instr_i(second_instr_i),
        .rs1_addr_o(second_rs1_w),
        .rs2_addr_o(second_rs2_w),
        .rd_addr_o(second_rd_w),
        .uses_rs1_o(second_uses_rs1_w),
        .uses_rs2_o(second_uses_rs2_w),
        .rd_write_o(second_write_w),
        .op_class_o(second_class_w),
        .alu_op_o(second_alu_w),
        .op_a_sel_o(second_a_sel_w),
        .op_b_imm_o(second_b_imm_w),
        .imm_sel_o(second_imm_sel_w),
        .illegal_o(second_illegal_w)
    );
    edrv32_immgen u_second_immgen (
        .instr_i(second_instr_i),
        .imm_sel_i(second_imm_sel_w),
        .imm_o(second_immediate_w)
    );
    edrv32_operand_resolve #(.DUAL_ISSUE(DUAL_ISSUE)) u_second_operand_resolve (
        .ex_second_i(ex_second_i),
        .mem1_second_i(mem1_second_i),
        .mem2_second_i(mem2_second_i),
        .commit_second_i(commit_second_i),
        // First source operand and its resolution result.
        .rs1_addr_i(second_rs1_w),
        .uses_rs1_i(second_uses_rs1_w),
        .rs1_reg_data_i(second_rs1_reg_w),
        .rs1_value_o(second_rs1_value_w),
        .rs1_blocked_o(second_rs1_blocked_w),
        .rs1_mdu_o(),
        .rs1_late_load_o(),
        .rs1_late_load_pc_o(),
        .rs1_late_load_token_valid_o(),
        .rs1_late_load_token_o(),

        // Second source operand and its resolution result.
        .rs2_addr_i(second_rs2_w),
        .uses_rs2_i(second_uses_rs2_w),
        .rs2_reg_data_i(second_rs2_reg_w),
        .rs2_value_o(second_rs2_value_w),
        .rs2_blocked_o(second_rs2_blocked_w),
        .rs2_mdu_o(),
        .rs2_late_load_o(),
        .rs2_late_load_pc_o(),
        .rs2_late_load_token_valid_o(),
        .rs2_late_load_token_o(),

        // Completed MDU data is registered locally by the MDU.  Keeping its
        // pending record valid until architectural writeback preserves WAW
        // protection while allowing a matching consumer to use the value.
        .mdu_valid_i(mdu_bypass_valid_i),
        .mdu_ready_i(mdu_bypass_ready_i),
        .mdu_rd_i(mdu_bypass_rd_i),
        .mdu_value_i(mdu_bypass_value_i),
        .mdu_passed_mem1_i(mdu_passed_mem1_i),
        .mdu_passed_mem2_i(mdu_passed_mem2_i),
        .mdu_authorized_i(mdu_authorized_i),

        // Youngest-to-oldest producer records.
        .ex_valid_i(ex_bypass_valid_i),
        .ex_write_i(ex_bypass_write_i),
        .ex_ready_i(ex_bypass_ready_i),
        .ex_is_load_i(ex_bypass_is_load_i),
        .ex_mdu_token_i(ex_bypass_mdu_token_i),
        .ex_pc_i(ex_bypass_pc_i),
        .ex_rd_i(ex_bypass_rd_i),
        .ex_value_i(ex_bypass_value_i),
        .ex_lsu_token_valid_i(ex_bypass_lsu_token_valid_i),
        .ex_lsu_token_i(ex_bypass_lsu_token_i),

        .mem1_valid_i(mem1_bypass_valid_i),
        .mem1_write_i(mem1_bypass_write_i),
        .mem1_ready_i(mem1_bypass_ready_i),
        .mem1_is_load_i(mem1_bypass_is_load_i),
        .mem1_pc_i(mem1_bypass_pc_i),
        .mem1_rd_i(mem1_bypass_rd_i),
        .mem1_value_i(mem1_bypass_value_i),
        .mem1_lsu_token_valid_i(mem1_bypass_lsu_token_valid_i),
        .mem1_lsu_token_i(mem1_bypass_lsu_token_i),

        .mem2_valid_i(mem2_bypass_valid_i),
        .mem2_write_i(mem2_bypass_write_i),
        .mem2_ready_i(mem2_bypass_ready_i),
        .mem2_is_load_i(mem2_bypass_is_load_i),
        .mem2_pc_i(mem2_bypass_pc_i),
        .mem2_rd_i(mem2_bypass_rd_i),
        .mem2_value_i(mem2_bypass_value_i),
        .mem2_lsu_token_valid_i(mem2_bypass_lsu_token_valid_i),
        .mem2_lsu_token_i(mem2_bypass_lsu_token_i),

        .commit_valid_i(commit_bypass_valid_i),
        .commit_write_i(commit_bypass_write_i),
        .commit_ready_i(commit_bypass_ready_i),
        .commit_rd_i(commit_bypass_rd_i),
        .commit_value_i(commit_bypass_value_i)
    );
    wire resident_second_live_w = (DUAL_ISSUE != 0) && valid_o &&
        resident_second_valid_w && resident_second_write_w && (resident_second_rd_w != 5'd0);
    // The replacement A records which result in the older registered packet
    // it needs. EX consumes that exact parent PC after the execution boundary.
    wire resident_second_rs1_hazard_w = resident_second_live_w &&
        dec_uses_rs1_w && (dec_rs1_w == resident_second_rd_w);
    wire resident_second_rs2_hazard_w = resident_second_live_w &&
        dec_uses_rs2_w && (dec_rs2_w == resident_second_rd_w);
    wire primary_resident_second_raw_w = 1'b0;
    wire second_rs1_resident_a_w = valid_o && rd_write_o && rd_o != 5'd0 &&
        second_uses_rs1_w && second_rs1_w == rd_o;
    wire second_rs2_resident_a_w = valid_o && rd_write_o && rd_o != 5'd0 &&
        second_uses_rs2_w && second_rs2_w == rd_o;
    wire second_rs1_resident_b_w = resident_second_live_w &&
        second_uses_rs1_w && second_rs1_w == resident_second_rd_w;
    wire second_rs2_resident_b_w = resident_second_live_w &&
        second_uses_rs2_w && second_rs2_w == resident_second_rd_w;
    wire [1:0] second_lhs_source_w = second_rs1_resident_b_w ? 2'd2 :
        (second_rs1_resident_a_w && resident_forwardable_w) ? 2'd1 : 2'd0;
    wire [1:0] second_rhs_source_w = second_rs2_resident_b_w ? 2'd2 :
        (second_rs2_resident_a_w && resident_forwardable_w) ? 2'd1 : 2'd0;
    wire second_resident_raw_w = !resident_forwardable_w &&
        ((second_rs1_resident_a_w && !second_rs1_resident_b_w) ||
         (second_rs2_resident_a_w && !second_rs2_resident_b_w));
    // A younger resident source shadows all external Load/MDU records.
    wire second_operand_blocked_w =
        (second_rs1_blocked_w && second_lhs_source_w == 2'd0) ||
        (second_rs2_blocked_w && second_rhs_source_w == 2'd0);
    wire pair_raw_w = dec_rd_write_w && dec_rd_w != 5'd0 &&
        ((second_uses_rs1_w && second_rs1_w == dec_rd_w) ||
         (second_uses_rs2_w && second_rs2_w == dec_rd_w));
    wire pair_waw_w = dec_rd_write_w && second_write_w && dec_rd_w != 5'd0 &&
        dec_rd_w == second_rd_w;
    wire pair_sequential_w = second_pc_i ==
        (pc_i + (is_compressed_i ? 32'd2 : 32'd4));
    // A keeps exclusive ownership of the LSU. B only computes an independent
    // ALU result; a load's destination is unavailable to B in this group.
    wire pair_primary_eligible_w = (dec_op_class_w == `EDRV32_OP_ALU) ||
        (dec_op_class_w == `EDRV32_OP_LOAD) || (dec_op_class_w == `EDRV32_OP_STORE);
    wire pair_accept_w = (DUAL_ISSUE != 0) && valid_i && ready_o && second_valid_i &&
        pair_primary_eligible_w && second_class_w == `EDRV32_OP_ALU &&
        !exception_valid_w && !second_fetch_fault_i && !second_compressed_illegal_i &&
        !second_illegal_w && !predicted_taken_i && !second_predicted_taken_i &&
        epoch_i == second_epoch_i && pair_sequential_w && !pair_raw_w && !pair_waw_w &&
        !second_operand_blocked_w && !second_resident_raw_w;
    reg [31:0] second_lhs_w;
    always @(*) begin
        second_lhs_w = second_rs1_value_w;
        case (second_a_sel_w)
            `EDRV32_OP_A_PC: second_lhs_w = second_pc_i;
            `EDRV32_OP_A_ZERO: second_lhs_w = 32'd0;
            default: begin end
        endcase
    end
    wire [31:0] second_rhs_w = second_b_imm_w ? second_immediate_w : second_rs2_value_w;
    wire [`EDRV32_PAIR_DECODE_W-1:0] candidate_second_w =
        {pair_accept_w, second_pc_i, second_instr_i, second_is_compressed_i,
         second_epoch_i, second_rd_w, second_write_w, second_alu_w, second_lhs_w,
         second_rhs_w, second_lhs_source_w, second_rhs_source_w};
    assign second_ready_o = pair_accept_w;

    // Consumer class for the RAW matrix: {ALU/JUMP, CONTROL, MEMORY, OTHER}.
    reg [1:0] candidate_class_w;
    always @* begin
        case (dec_op_class_w)
            `EDRV32_OP_BRANCH:       candidate_class_w = 2'd1;
            `EDRV32_OP_LOAD,
            `EDRV32_OP_STORE:        candidate_class_w = 2'd2;
            `EDRV32_OP_ALU,
            `EDRV32_OP_JUMP:         candidate_class_w = 2'd0;
            default:                 candidate_class_w = 2'd3;
        endcase
    end
    assign hpm_candidate_class_o = candidate_class_w;

    assign ready_o = ~frontend_kill_i && candidate_ready_w &&
                        ~dependency_stall_o && ~structural_stall_o;

    // Candidate valid is independent of ready.  ALIGN->DECODE owns and holds
    // the input payload until this stage and DECODE->EX complete a transfer.
    assign candidate_valid_w           = ~frontend_kill_i && valid_i &&
                                         ~dependency_stall_o &&
                                         ~structural_stall_o;
    assign candidate_pc_w              = pc_i;
    assign candidate_instr_w           = instr_i;
    assign candidate_is_compressed_w   = is_compressed_i;
    assign candidate_epoch_w           = epoch_i;
    assign candidate_predicted_taken_w  = predicted_taken_i;
    assign candidate_predicted_target_w = predicted_target_i;
    assign candidate_predictor_meta_w   = predictor_meta_i;
    assign candidate_rd_w              = dec_rd_w;
    assign candidate_rd_write_w        = dec_rd_write_w && !exception_valid_w;
    assign candidate_op_class_w        = dec_op_class_w;
    assign candidate_alu_op_w          = dec_alu_op_w;
    assign candidate_branch_op_w       = dec_branch_op_w;
    assign candidate_mem_size_w        = dec_mem_size_w;
    assign candidate_mem_unsigned_w    = dec_mem_unsigned_w;
    assign candidate_mdu_op_w          = dec_mdu_op_w;
    assign candidate_csr_op_w          = dec_csr_op_w;
    assign candidate_csr_addr_w        = instr_i[31:20];
    assign candidate_csr_src_w         = csr_src_w;
    assign candidate_lhs_w             = selected_lhs_w;
    assign candidate_rhs_w             = selected_rhs_w;
    assign candidate_rs2_value_w       = rs2_value_w;
    assign candidate_resident_bypass_rs1_w = resident_bypass_rs1_w;
    assign candidate_resident_bypass_rs2_w = resident_bypass_rs2_w;
    assign candidate_resident_bypass_pc_w  = pc_o;
    assign candidate_imm_w             = immediate_w;
    assign candidate_fence_w           = dec_fence_w && !exception_valid_w;
    assign candidate_fencei_w         = dec_fencei_w && !exception_valid_w;
    assign candidate_mret_w            = dec_mret_w && !exception_valid_w;
    assign candidate_wfi_w             = dec_wfi_w && !exception_valid_w;
    assign candidate_exception_valid_w = exception_valid_w;
    assign candidate_exception_cause_w = exception_cause_w;
    assign candidate_exception_tval_w  = exception_tval_w;

    // DECODE owns the elastic slot and squash policy.  Payload sampling keeps
    // the previous timing optimization: the wide register bank is enabled by
    // local capacity, while valid_i only drives the narrow validity register.
    assign candidate_ready_w = ~valid_o || ready_i;
    assign pipe_capture_w     = candidate_valid_w && candidate_ready_w;
    assign pipe_transfer_w    = valid_o && ready_i;
    assign pipe_valid_we_w    = boundary_kill_i || pipe_capture_w ||
                                pipe_transfer_w;
    assign pipe_valid_d_w     = ~boundary_kill_i && pipe_capture_w;


    edrv32_pipe_decode_to_ex #(.SECOND_ENABLE(DUAL_ISSUE)) u_pipe (
        .resident_second_rs1_i(resident_second_rs1_hazard_w),
        .resident_second_rs2_i(resident_second_rs2_hazard_w),
        .resident_second_rs1_o(resident_second_rs1_o),
        .resident_second_rs2_o(resident_second_rs2_o),
        .second_i(candidate_second_w),
        .second_o(second_o),
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .valid_we_i(pipe_valid_we_w),
        .valid_d_i(pipe_valid_d_w),
        .payload_we_i(candidate_ready_w),
        .pc_i(candidate_pc_w),
        .instr_i(candidate_instr_w),
        .is_compressed_i(candidate_is_compressed_w),
        .epoch_i(candidate_epoch_w),
        .predicted_taken_i(candidate_predicted_taken_w),
        .predicted_target_i(candidate_predicted_target_w),
        .predictor_meta_i(candidate_predictor_meta_w),
        .rd_i(candidate_rd_w),
        .rd_write_i(candidate_rd_write_w),
        .op_class_i(candidate_op_class_w),
        .alu_op_i(candidate_alu_op_w),
        .branch_op_i(candidate_branch_op_w),
        .mem_size_i(candidate_mem_size_w),
        .mem_unsigned_i(candidate_mem_unsigned_w),
        .mdu_op_i(candidate_mdu_op_w),
        .csr_op_i(candidate_csr_op_w),
        .csr_addr_i(candidate_csr_addr_w),
        .csr_src_i(candidate_csr_src_w),
        .lhs_i(candidate_lhs_w),
        .rhs_i(candidate_rhs_w),
        .rs2_value_i(candidate_rs2_value_w),
        .resident_bypass_rs1_i(candidate_resident_bypass_rs1_w),
        .resident_bypass_rs2_i(candidate_resident_bypass_rs2_w),
        .resident_bypass_pc_i(candidate_resident_bypass_pc_w),
        .late_mdu_rs1_i(late_mdu_rs1_w),
        .late_mdu_rs2_i(late_mdu_rs2_w),
        .late_load_rs1_i(rs1_late_load_w && !resident_second_rs1_hazard_w),
        .late_load_rs2_i(rs2_late_load_w && !resident_second_rs2_hazard_w),
        .late_load_rs1_pc_i(rs1_late_load_pc_w),
        .late_load_rs2_pc_i(rs2_late_load_pc_w),
        .late_load_rs1_token_valid_i(rs1_late_load_token_valid_w),
        .late_load_rs1_token_i(rs1_late_load_token_w),
        .late_load_rs2_token_valid_i(rs2_late_load_token_valid_w),
        .late_load_rs2_token_i(rs2_late_load_token_w),
        .imm_i(candidate_imm_w),
        .fence_i(candidate_fence_w),
        .fencei_i(candidate_fencei_w),
        .mret_i(candidate_mret_w),
        .wfi_i(candidate_wfi_w),
        .exception_valid_i(candidate_exception_valid_w),
        .exception_cause_i(candidate_exception_cause_w),
        .exception_tval_i(candidate_exception_tval_w),
        .valid_o(valid_o),
        .pc_o(pc_o),
        .instr_o(instr_o),
        .is_compressed_o(is_compressed_o),
        .epoch_o(epoch_o),
        .predicted_taken_o(predicted_taken_o),
        .predicted_target_o(predicted_target_o),
        .predictor_meta_o(predictor_meta_o),
        .rd_o(rd_o),
        .rd_write_o(rd_write_o),
        .op_class_o(op_class_o),
        .alu_op_o(alu_op_o),
        .branch_op_o(branch_op_o),
        .mem_size_o(mem_size_o),
        .mem_unsigned_o(mem_unsigned_o),
        .mdu_op_o(mdu_op_o),
        .csr_op_o(csr_op_o),
        .csr_addr_o(csr_addr_o),
        .csr_src_o(csr_src_o),
        .lhs_o(lhs_o),
        .rhs_o(rhs_o),
        .rs2_value_o(rs2_value_o),
        .resident_bypass_rs1_o(resident_bypass_rs1_o),
        .resident_bypass_rs2_o(resident_bypass_rs2_o),
        .resident_bypass_pc_o(resident_bypass_pc_o),
        .late_mdu_rs1_o(late_mdu_rs1_o),
        .late_mdu_rs2_o(late_mdu_rs2_o),
        .late_load_rs1_o(late_load_rs1_o),
        .late_load_rs2_o(late_load_rs2_o),
        .late_load_rs1_pc_o(late_load_rs1_pc_o),
        .late_load_rs2_pc_o(late_load_rs2_pc_o),
        .late_load_rs1_token_valid_o(late_load_rs1_token_valid_o),
        .late_load_rs1_token_o(late_load_rs1_token_o),
        .late_load_rs2_token_valid_o(late_load_rs2_token_valid_o),
        .late_load_rs2_token_o(late_load_rs2_token_o),
        .imm_o(imm_o),
        .fence_o(fence_o),
        .fencei_o(fencei_o),
        .mret_o(mret_o),
        .wfi_o(wfi_o),
        .exception_valid_o(exception_valid_o),
        .exception_cause_o(exception_cause_o),
        .exception_tval_o(exception_tval_o)
    );

endmodule
