// ============================================================================
// File        : edrv32_ex_stage.v
// Description : Scalar EX stage for integer execution and branch resolution.
// Notes       : EX computes results and side-effect requests, but the following
//               pipeline state is owned by edrv32_pipe_ex_to_mem1.
// ============================================================================
`include "edrv32_isa.vh"
`include "edrv32_uop.vh"
`include "edrv32_pair.vh"
`include "edrv32_bus.vh"
`include "edrv32_exception.vh"

// The stage directly owns its execution logic and outgoing registered boundary.
module edrv32_ex_stage #(
    parameter integer DUAL_ISSUE = 0,
    parameter integer MUL_CAPTURE_LIVE_LOAD = 0
)(
    input  wire                         clk_i,
    input  wire                         rst_n_i,

    input  wire [`EDRV32_PAIR_DECODE_W-1:0] second_i,
    output wire [`EDRV32_PAIR_RESULT_W-1:0] result_second_o,

    input wire resident_second_rs1_i,
    input wire resident_second_rs2_i,

    // Registered decoded uop from DECODE.
    input  wire                         valid_i,
    output wire                         ready_o,
    input  wire [31:0]                  pc_i,
    input  wire [31:0]                  instr_i,
    input  wire                         is_compressed_i,
    input  wire [`EDRV32_EPOCH_W-1:0]   epoch_i,
    input  wire                         predicted_taken_i,
    input  wire [31:0]                  predicted_target_i,
    input  wire [4:0]                   rd_i,
    input  wire                         rd_write_i,
    input  wire [`EDRV32_OP_CLASS_W-1:0] op_class_i,
    input  wire [`EDRV32_ALU_OP_W-1:0]  alu_op_i,
    input  wire [`EDRV32_BRANCH_OP_W-1:0] branch_op_i,
    input  wire [`BUS_SZ_W-1:0]         mem_size_i,
    input  wire                         mem_unsigned_i,
    input  wire [`EDRV32_MDU_OP_W-1:0]  mdu_op_i,
    input  wire [`EDRV32_CSR_OP_W-1:0]  csr_op_i,
    input  wire [11:0]                  csr_addr_i,
    input  wire [31:0]                  csr_src_i,
    input  wire [31:0]                  lhs_i,
    input  wire [31:0]                  rhs_i,
    input  wire [31:0]                  rs2_value_i,
    input  wire                         resident_bypass_rs1_i,
    input  wire                         resident_bypass_rs2_i,
    input  wire [31:0]                  resident_bypass_pc_i,
    input  wire                         late_mdu_rs1_i,
    input  wire                         late_mdu_rs2_i,
    input  wire                         late_load_rs1_i,
    input  wire                         late_load_rs2_i,
    input  wire [31:0]                  late_load_rs1_pc_i,
    input  wire [31:0]                  late_load_rs2_pc_i,
    input  wire                         late_load_rs1_token_valid_i,
    input  wire                         late_load_rs2_token_valid_i,
    input  wire [31:0]                  imm_i,
    input  wire                         fence_i,
    input  wire                         fencei_i,
    input  wire                         mret_i,
    input  wire                         wfi_i,
    input  wire                         exception_valid_i,
    input  wire [`EDRV32_EXC_CAUSE_W-1:0] exception_cause_i,
    input  wire [31:0]                  exception_tval_i,

    // Registered MEM2 load completion used by an early-issued dependent uop.
    input  wire                         load_bypass_valid_i,
    input  wire [31:0]                  load_bypass_pc_i,
    input  wire [31:0]                  load_bypass_value_i,
    input  wire                         load_queue_rs1_ready_i,
    input  wire [31:0]                  load_queue_rs1_value_i,
    input  wire                         load_queue_rs1_stored_ready_i,
    input  wire [31:0]                  load_queue_rs1_stored_value_i,
    input  wire                         load_queue_rs2_ready_i,
    input  wire [31:0]                  load_queue_rs2_value_i,
    input  wire                         load_queue_rs2_stored_ready_i,
    input  wire [31:0]                  load_queue_rs2_stored_value_i,
    input  wire                         result_bypass_valid_i,
    input  wire                         result_bypass_ready_i,
    input  wire [31:0]                  result_bypass_pc_i,
    input  wire [31:0]                  result_bypass_value_i,
    output wire                         late_load_stall_o,
    input  wire                         mdu_bypass_valid_i,
    input  wire [31:0]                  mdu_bypass_value_i,
    output wire                         late_mdu_stall_o,

    // Control-flow recovery and predictor training.
    output wire                         redirect_valid_o,
    input  wire                         redirect_ready_i,
    output wire [31:0]                  redirect_target_o,
    output wire                         younger_kill_o,
    output wire                         direction_mispredict_o,
    output wire                         target_mispredict_o,
    output wire                         predictor_update_valid_o,
    output wire [31:0]                  predictor_update_pc_o,
    output wire                         predictor_update_is_conditional_o,
    output wire                         predictor_update_is_unconditional_o,
    output wire                         predictor_update_taken_o,
    output wire [31:0]                  predictor_update_target_o,
    output wire                         predictor_update_ras_push_o,
    output wire                         predictor_update_ras_pop_o,
    output wire [31:0]                  predictor_update_link_addr_o,

    // Decoupled multiply/divide request.
    output wire                         mdu_req_valid_o,
    input  wire                         mdu_req_ready_i,
    output wire [`EDRV32_MDU_OP_W-1:0]  mdu_req_op_o,
    output wire [31:0]                  mdu_req_lhs_o,
    output wire [31:0]                  mdu_req_rhs_o,
    output wire [31:0]                  mdu_req_mul_lhs_o,
    output wire [31:0]                  mdu_req_mul_rhs_o,
    output wire [31:0]                  mdu_req_div_lhs_o,
    output wire [31:0]                  mdu_req_div_rhs_o,
    output wire [4:0]                   mdu_req_rd_o,
    output wire                         mdu_req_fire_o,

    // Registered executed uop presented to MEM1.
    output wire                         result_valid_o,
    input  wire                         result_ready_i,
    output wire [31:0]                  result_pc_o,
    output wire [31:0]                  result_instr_o,
    output wire                         result_is_compressed_o,
    output wire [`EDRV32_EPOCH_W-1:0]   result_epoch_o,
    output wire [4:0]                   result_rd_o,
    output wire                         result_rd_write_o,
    output wire [`EDRV32_OP_CLASS_W-1:0] result_op_class_o,
    output wire [31:0]                  result_value_o,
    output wire                         result_value_ready_o,
    output wire [31:0]                  result_mem_addr_o,
    output wire [`BUS_SZ_W-1:0]         result_mem_size_o,
    output wire                         result_mem_unsigned_o,
    output wire [31:0]                  result_store_data_o,
    output wire                         result_mdu_token_o,
    output wire [`EDRV32_CSR_OP_W-1:0]  result_csr_op_o,
    output wire [11:0]                  result_csr_addr_o,
    output wire [31:0]                  result_csr_src_o,
    output wire                         result_fence_o,
    output wire                         result_fencei_o,
    output wire                         result_mret_o,
    output wire                         result_wfi_o,
    output wire                         result_exception_valid_o,
    output wire [`EDRV32_EXC_CAUSE_W-1:0] result_exception_cause_o,
    output wire [31:0]                  result_exception_tval_o,

    input  wire                         kill_i
);

    wire                         candidate_valid_w;
    wire                         candidate_ready_w;
    wire [31:0]                  candidate_pc_w;
    wire [31:0]                  candidate_instr_w;
    wire                         candidate_is_compressed_w;
    wire [`EDRV32_EPOCH_W-1:0]   candidate_epoch_w;
    wire [4:0]                   candidate_rd_w;
    wire                         candidate_rd_write_w;
    wire [`EDRV32_OP_CLASS_W-1:0] candidate_op_class_w;
    wire [31:0]                  candidate_result_w;
    wire                         candidate_result_ready_w;
    wire [31:0]                  candidate_mem_addr_w;
    wire [`BUS_SZ_W-1:0]         candidate_mem_size_w;
    wire                         candidate_mem_unsigned_w;
    wire [31:0]                  candidate_store_data_w;
    wire                         candidate_mdu_token_w;
    wire [`EDRV32_CSR_OP_W-1:0]  candidate_csr_op_w;
    wire [11:0]                  candidate_csr_addr_w;
    wire [31:0]                  candidate_csr_src_w;
    wire                         candidate_fence_w;
    wire                         candidate_fencei_w;
    wire                         candidate_mret_w;
    wire                         candidate_wfi_w;
    wire                         candidate_exception_valid_w;
    wire [`EDRV32_EXC_CAUSE_W-1:0] candidate_exception_cause_w;
    wire [31:0]                  candidate_exception_tval_w;
    wire                         pipe_transfer_w;
    wire                         pipe_valid_we_w;
    wire                         pipe_valid_d_w;


    // Stage-local execution logic is written directly in this module.


    // Instruction class flags make the datapath and side-effect conditions
    // below read in architectural terms.
    wire [31:0] alu_result_w;
    wire branch_taken_w;
    wire is_branch_w = (op_class_i == `EDRV32_OP_BRANCH);
    wire is_jump_w   = (op_class_i == `EDRV32_OP_JUMP);
    wire is_load_w   = (op_class_i == `EDRV32_OP_LOAD);
    wire is_store_w  = (op_class_i == `EDRV32_OP_STORE);
    wire is_mdu_w    = (op_class_i == `EDRV32_OP_MDU);
    wire is_divrem_w = is_mdu_w && mdu_op_i[2];

    wire second_valid_w;
    wire [31:0] second_pc_w;
    wire [31:0] second_instr_w;
    wire second_compressed_w;
    wire [`EDRV32_EPOCH_W-1:0] second_epoch_w;
    wire [4:0] second_rd_w;
    wire second_write_w;
    wire [`EDRV32_ALU_OP_W-1:0] second_alu_w;
    wire [31:0] second_lhs_w;
    wire [31:0] second_rhs_w;
    wire [1:0] second_lhs_source_w;
    wire [1:0] second_rhs_source_w;
    wire [31:0] second_result_w;
    assign {second_valid_w, second_pc_w, second_instr_w, second_compressed_w,
        second_epoch_w, second_rd_w, second_write_w, second_alu_w,
        second_lhs_w, second_rhs_w, second_lhs_source_w, second_rhs_source_w} = second_i;

    // A dependent uop may enter EX one cycle before a resident MEM2 load
    // completes. The cache response is already registered at the D-cache
    // boundary; this mux therefore never creates a RAM/tag-to-EX path.
    reg late_load_rs1_captured_r;
    reg late_load_rs2_captured_r;
    reg [31:0] late_load_rs1_value_r;
    reg [31:0] late_load_rs2_value_r;
    reg resident_bypass_rs1_captured_r;
    reg resident_bypass_rs2_captured_r;
    reg [31:0] resident_bypass_rs1_value_r;
    reg [31:0] resident_bypass_rs2_value_r;
    reg late_mdu_captured_r;
    reg [31:0] late_mdu_value_r;
    // The consumer's late-load producer is identified by its PC, not its rd:
    // two in-flight loads may target the same rd, and only the youngest
    // matching producer recorded by DECODE may release the wait.
    wire late_load_rs1_legacy_match_w = !late_load_rs1_token_valid_i &&
        load_bypass_valid_i &&
        (load_bypass_pc_i == late_load_rs1_pc_i);
    wire late_load_rs2_legacy_match_w = !late_load_rs2_token_valid_i &&
        load_bypass_valid_i &&
        (load_bypass_pc_i == late_load_rs2_pc_i);
    wire late_load_rs1_queue_match_w = late_load_rs1_token_valid_i &&
                                        load_queue_rs1_ready_i;
    wire late_load_rs2_queue_match_w = late_load_rs2_token_valid_i &&
                                        load_queue_rs2_ready_i;
    wire late_load_rs1_match_w = late_load_rs1_queue_match_w ||
                                 late_load_rs1_legacy_match_w;
    wire late_load_rs2_match_w = late_load_rs2_queue_match_w ||
                                 late_load_rs2_legacy_match_w;
    wire registered_second_valid_w;
    wire [31:0] registered_second_pc_w;
    wire [31:0] registered_second_instr_w;
    wire registered_second_compressed_w;
    wire [`EDRV32_EPOCH_W-1:0] registered_second_epoch_w;
    wire [4:0] registered_second_rd_w;
    wire registered_second_write_w;
    wire [31:0] registered_second_value_w;
    assign {registered_second_valid_w, registered_second_pc_w, registered_second_instr_w,
        registered_second_compressed_w, registered_second_epoch_w, registered_second_rd_w,
        registered_second_write_w, registered_second_value_w} = result_second_o;
    wire registered_second_ready_w = (DUAL_ISSUE != 0) && registered_second_valid_w &&
        registered_second_write_w && (registered_second_rd_w != 5'd0);
    wire resident_second_rs1_w = (DUAL_ISSUE != 0) && resident_second_rs1_i;
    wire resident_bypass_rs1_match_w = result_bypass_valid_i &&
        (resident_second_rs1_w ? registered_second_ready_w : result_bypass_ready_i) &&
        (result_bypass_pc_i == resident_bypass_pc_i);
    wire [31:0] resident_source_rs1_w = resident_second_rs1_w
        ? registered_second_value_w : result_bypass_value_i;
    wire resident_second_rs2_w = (DUAL_ISSUE != 0) && resident_second_rs2_i;
    wire resident_bypass_rs2_match_w = result_bypass_valid_i &&
        (resident_second_rs2_w ? registered_second_ready_w : result_bypass_ready_i) &&
        (result_bypass_pc_i == resident_bypass_pc_i);
    wire [31:0] resident_source_rs2_w = resident_second_rs2_w
        ? registered_second_value_w : result_bypass_value_i;
    // B binds the same older packet as A, using registered results only. Hold
    // a selected value locally if A waits or the output is backpressured;
    // the producer is allowed to leave EX before the whole consumer executes.
    reg second_lhs_captured_r;
    reg second_rhs_captured_r;
    reg [31:0] second_lhs_value_r;
    reg [31:0] second_rhs_value_r;
    wire second_parent_match_w = result_bypass_valid_i &&
        (result_bypass_pc_i == resident_bypass_pc_i);
    wire second_lhs_match_w = second_parent_match_w &&
        ((second_lhs_source_w == 2'd1 && result_bypass_ready_i) ||
         (second_lhs_source_w == 2'd2 && registered_second_ready_w));
    wire second_rhs_match_w = second_parent_match_w &&
        ((second_rhs_source_w == 2'd1 && result_bypass_ready_i) ||
         (second_rhs_source_w == 2'd2 && registered_second_ready_w));
    wire [31:0] second_lhs_live_w = second_lhs_source_w == 2'd2
        ? registered_second_value_w : result_bypass_value_i;
    wire [31:0] second_rhs_live_w = second_rhs_source_w == 2'd2
        ? registered_second_value_w : result_bypass_value_i;
    wire second_lhs_ready_w = second_lhs_source_w == 2'd0 ||
        second_lhs_captured_r || second_lhs_match_w;
    wire second_rhs_ready_w = second_rhs_source_w == 2'd0 ||
        second_rhs_captured_r || second_rhs_match_w;
    wire second_operands_ready_w = (DUAL_ISSUE == 0) || !second_valid_w ||
        (second_lhs_ready_w && second_rhs_ready_w);
    wire [31:0] second_lhs_resolved_w = second_lhs_captured_r
        ? second_lhs_value_r : second_lhs_live_w;
    wire [31:0] second_rhs_resolved_w = second_rhs_captured_r
        ? second_rhs_value_r : second_rhs_live_w;
    wire [31:0] second_effective_lhs_w =
        (second_lhs_w & {32{second_lhs_source_w == 2'd0}}) |
        (second_lhs_resolved_w & {32{second_lhs_source_w != 2'd0}});
    wire [31:0] second_effective_rhs_w =
        (second_rhs_w & {32{second_rhs_source_w == 2'd0}}) |
        (second_rhs_resolved_w & {32{second_rhs_source_w != 2'd0}});
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            second_lhs_captured_r <= 1'b0;
            second_rhs_captured_r <= 1'b0;
        end else if (kill_i || !valid_i || ready_o) begin
            second_lhs_captured_r <= 1'b0;
            second_rhs_captured_r <= 1'b0;
        end else if ((DUAL_ISSUE != 0) && second_valid_w) begin
            if (second_lhs_match_w && !second_lhs_captured_r) begin
                second_lhs_captured_r <= 1'b1;
                second_lhs_value_r <= second_lhs_live_w;
            end
            if (second_rhs_match_w && !second_rhs_captured_r) begin
                second_rhs_captured_r <= 1'b1;
                second_rhs_value_r <= second_rhs_live_w;
            end
        end
    end
    // DIV/REM has a long request-time negate/control cone.  Capture a newly
    // arriving Load value beside EX before allowing that operation to issue;
    // all shorter consumers may use the exact queue/COMMIT completion live.
    wire registered_mul_input_w = (MUL_CAPTURE_LIVE_LOAD != 0) &&
        is_mdu_w && (mdu_op_i == `EDRV32_MDU_MUL);
    wire late_load_rs1_issue_ready_w = registered_mul_input_w
        ? (late_load_rs1_token_valid_i && load_queue_rs1_stored_ready_i)
        : (late_load_rs1_match_w && !is_divrem_w);
    wire late_load_rs2_issue_ready_w = registered_mul_input_w
        ? (late_load_rs2_token_valid_i && load_queue_rs2_stored_ready_i)
        : (late_load_rs2_match_w && !is_divrem_w);
    wire late_load_rs1_ready_w = !late_load_rs1_i ||
        late_load_rs1_captured_r || late_load_rs1_issue_ready_w;
    wire late_load_rs2_ready_w = !late_load_rs2_i ||
        late_load_rs2_captured_r || late_load_rs2_issue_ready_w;
    wire late_load_ready_w = late_load_rs1_ready_w &&
                             late_load_rs2_ready_w;
    wire control_flow_w = is_branch_w || is_jump_w;
    // A branch comparing a queued Load against x0 needs only a zero test.
    // Keep its live value off the general branch comparator and JALR adder.
    wire zero_branch_eligible_w = is_branch_w &&
        ((branch_op_i == `EDRV32_BRANCH_EQ) ||
         (branch_op_i == `EDRV32_BRANCH_NE)) &&
        (instr_i[24:20] == 5'd0) && late_load_rs1_i &&
        late_load_rs1_token_valid_i && !late_load_rs1_captured_r;
    wire zero_branch_live_w = zero_branch_eligible_w &&
        load_queue_rs1_ready_i && !load_queue_rs1_stored_ready_i;
    // Equality branches can consume the registered cache response on arrival.
    // Compare each live source in parallel with the stored general comparator;
    // the response never enters the ordered comparator or the JALR adder.
    wire equality_branch_w = is_branch_w &&
        ((branch_op_i == `EDRV32_BRANCH_EQ) ||
         (branch_op_i == `EDRV32_BRANCH_NE));
    wire equality_rs1_live_w = equality_branch_w && late_load_rs1_i &&
        late_load_rs1_token_valid_i && !late_load_rs1_captured_r &&
        !resident_bypass_rs1_i && load_queue_rs1_ready_i &&
        !load_queue_rs1_stored_ready_i;
    wire equality_rs2_live_w = equality_branch_w && late_load_rs2_i &&
        late_load_rs2_token_valid_i && !late_load_rs2_captured_r &&
        !resident_bypass_rs2_i && load_queue_rs2_ready_i &&
        !load_queue_rs2_stored_ready_i;
    wire control_rs1_live_ready_w = late_load_rs1_token_valid_i
        ? (load_queue_rs1_stored_ready_i || equality_rs1_live_w)
        : late_load_rs1_legacy_match_w;
    wire control_rs2_live_ready_w = late_load_rs2_token_valid_i
        ? (load_queue_rs2_stored_ready_i || equality_rs2_live_w)
        : late_load_rs2_legacy_match_w;
    wire control_rs1_ready_w = !late_load_rs1_i ||
        late_load_rs1_captured_r || control_rs1_live_ready_w;
    wire control_rs2_ready_w = !late_load_rs2_i ||
        late_load_rs2_captured_r || control_rs2_live_ready_w;
    wire control_operands_ready_w = !control_flow_w ||
        (control_rs1_ready_w && control_rs2_ready_w);
    wire resident_bypass_rs1_ready_w = !resident_bypass_rs1_i ||
        resident_bypass_rs1_captured_r || resident_bypass_rs1_match_w;
    wire resident_bypass_rs2_ready_w = !resident_bypass_rs2_i ||
        resident_bypass_rs2_captured_r || resident_bypass_rs2_match_w;
    wire resident_bypass_ready_w = resident_bypass_rs1_ready_w &&
                                   resident_bypass_rs2_ready_w;
    // Both MDU source tags name the same protected one-entry producer. A
    // single replay value therefore suffices even when both operands match.
    // Keep live MDU data off the long control-flow and DIV/REM input cones.
    wire late_mdu_live_allowed_w = (op_class_i == `EDRV32_OP_ALU) ||
        is_load_w || is_store_w;
    wire late_mdu_ready_w = !(late_mdu_rs1_i || late_mdu_rs2_i) ||
        late_mdu_captured_r || (mdu_bypass_valid_i && late_mdu_live_allowed_w);
    wire load_operands_ready_w = late_load_ready_w && resident_bypass_ready_w &&
        control_operands_ready_w;
    wire operands_ready_w = load_operands_ready_w && late_mdu_ready_w &&
                            second_operands_ready_w;
    wire [31:0] late_mdu_value_w = late_mdu_captured_r
        ? late_mdu_value_r : mdu_bypass_value_i;
    wire [31:0] late_load_rs1_live_value_w = late_load_rs1_queue_match_w
        ? load_queue_rs1_value_i : load_bypass_value_i;
    wire [31:0] late_load_rs2_live_value_w = late_load_rs2_queue_match_w
        ? load_queue_rs2_value_i : load_bypass_value_i;
    wire [31:0] late_load_rs1_value_w = late_load_rs1_captured_r
        ? late_load_rs1_value_r : late_load_rs1_live_value_w;
    wire [31:0] late_load_rs2_value_w = late_load_rs2_captured_r
        ? late_load_rs2_value_r : late_load_rs2_live_value_w;
    wire [31:0] control_rs1_live_value_w = late_load_rs1_token_valid_i
        ? load_queue_rs1_stored_value_i : load_bypass_value_i;
    wire [31:0] control_rs2_live_value_w = late_load_rs2_token_valid_i
        ? load_queue_rs2_stored_value_i : load_bypass_value_i;
    wire [31:0] control_late_rs1_value_w = late_load_rs1_captured_r
        ? late_load_rs1_value_r : control_rs1_live_value_w;
    wire [31:0] control_late_rs2_value_w = late_load_rs2_captured_r
        ? late_load_rs2_value_r : control_rs2_live_value_w;
    wire [31:0] resident_bypass_rs1_value_w =
        resident_bypass_rs1_captured_r ? resident_bypass_rs1_value_r
                                        : resident_source_rs1_w;
    wire [31:0] resident_bypass_rs2_value_w =
        resident_bypass_rs2_captured_r ? resident_bypass_rs2_value_r
                                        : resident_source_rs2_w;
    // The resident and late-load tags are mutually exclusive for one source.
    // Express producer priority as a one-hot data merge before the ALU.
    wire resident_rs1_select_w = resident_bypass_rs1_i;
    wire late_load_rs1_select_w = late_load_rs1_i &&
                                  !resident_bypass_rs1_i;
    wire late_mdu_rs1_select_w = late_mdu_rs1_i &&
        !resident_bypass_rs1_i && !late_load_rs1_i;
    wire base_rs1_select_w = !resident_bypass_rs1_i && !late_load_rs1_i &&
        !late_mdu_rs1_i;
    wire resident_rs2_select_w = resident_bypass_rs2_i;
    wire late_load_rs2_select_w = late_load_rs2_i &&
                                  !resident_bypass_rs2_i;
    wire late_mdu_rs2_select_w = late_mdu_rs2_i &&
        !resident_bypass_rs2_i && !late_load_rs2_i;
    wire base_rs2_select_w = !resident_bypass_rs2_i && !late_load_rs2_i &&
        !late_mdu_rs2_i;
    wire [31:0] effective_rs1_w =
        (resident_bypass_rs1_value_w & {32{resident_rs1_select_w}}) |
        (late_load_rs1_value_w & {32{late_load_rs1_select_w}}) |
        (late_mdu_value_w & {32{late_mdu_rs1_select_w}}) |
        (lhs_i & {32{base_rs1_select_w}});
    wire [31:0] effective_rs2_w =
        (resident_bypass_rs2_value_w & {32{resident_rs2_select_w}}) |
        (late_load_rs2_value_w & {32{late_load_rs2_select_w}}) |
        (late_mdu_value_w & {32{late_mdu_rs2_select_w}}) |
        (rs2_value_i & {32{base_rs2_select_w}});
    wire [31:0] effective_lhs_w = effective_rs1_w;
    // This separate operand view contains only registered data sources.
    // A one-stage multiplier must never inherit the live Cache response path
    // through effective_rs*_w, even when its request is functionally blocked.
    wire [31:0] stored_load_rs1_value_w = late_load_rs1_captured_r
        ? late_load_rs1_value_r : load_queue_rs1_stored_value_i;
    wire [31:0] stored_load_rs2_value_w = late_load_rs2_captured_r
        ? late_load_rs2_value_r : load_queue_rs2_stored_value_i;
    wire [31:0] registered_mul_lhs_w =
        (resident_bypass_rs1_value_w & {32{resident_rs1_select_w}}) |
        (stored_load_rs1_value_w & {32{late_load_rs1_select_w}}) |
        (late_mdu_value_r & {32{late_mdu_rs1_select_w}}) |
        (lhs_i & {32{base_rs1_select_w}});
    wire [31:0] registered_mul_rhs_w =
        (resident_bypass_rs2_value_w & {32{resident_rs2_select_w}}) |
        (stored_load_rs2_value_w & {32{late_load_rs2_select_w}}) |
        (late_mdu_value_r & {32{late_mdu_rs2_select_w}}) |
        (rs2_value_i & {32{base_rs2_select_w}});
    wire [31:0] effective_rhs_w = (resident_bypass_rs2_i ||
                                   late_load_rs2_i || late_mdu_rs2_i) && !is_store_w
        ? effective_rs2_w : rhs_i;
    wire [31:0] effective_csr_src_w = (late_load_rs1_i ||
        resident_bypass_rs1_i) &&
        (op_class_i == `EDRV32_OP_CSR)
            ? effective_rs1_w : csr_src_i;
    wire [31:0] control_effective_rs1_w = late_mdu_rs1_i ? late_mdu_value_r :
        resident_bypass_rs1_i
        ? resident_bypass_rs1_value_w :
        late_load_rs1_i ? control_late_rs1_value_w : lhs_i;
    wire [31:0] control_effective_rs2_w = late_mdu_rs2_i ? late_mdu_value_r :
        resident_bypass_rs2_i
        ? resident_bypass_rs2_value_w :
        late_load_rs2_i ? control_late_rs2_value_w : rs2_value_i;
    assign late_load_stall_o = valid_i &&
        (late_load_rs1_i || late_load_rs2_i || resident_bypass_rs1_i ||
         resident_bypass_rs2_i) && !load_operands_ready_w;
    assign late_mdu_stall_o = valid_i && !kill_i &&
        (late_mdu_rs1_i || late_mdu_rs2_i) && !late_mdu_ready_w;

    // A blocked EX consumer must retain the one-cycle completion, including
    // the edge on which COMMIT releases the MDU slot. In-order EX issue keeps
    // a new MDU allocation behind this consumer until it advances or is killed.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            late_mdu_captured_r <= 1'b0;
        else if (kill_i || !valid_i || (valid_i && ready_o))
            late_mdu_captured_r <= 1'b0;
        else if ((late_mdu_rs1_i || late_mdu_rs2_i) && mdu_bypass_valid_i)
            late_mdu_captured_r <= 1'b1;
    end

    always @(posedge clk_i) begin
        if (valid_i && (late_mdu_rs1_i || late_mdu_rs2_i) && mdu_bypass_valid_i)
            late_mdu_value_r <= mdu_bypass_value_i;
    end

    // If the downstream EX/MEM1 boundary is full when the one-cycle MEM2
    // bypass appears, retain the value next to the resident EX uop. This is a
    // stage-local replay buffer: it is cleared when that uop leaves or is
    // killed and never becomes architectural state.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            late_load_rs1_captured_r <= 1'b0;
            late_load_rs2_captured_r <= 1'b0;
            resident_bypass_rs1_captured_r <= 1'b0;
            resident_bypass_rs2_captured_r <= 1'b0;
        end else if (kill_i || !valid_i || (valid_i && ready_o)) begin
            late_load_rs1_captured_r <= 1'b0;
            late_load_rs2_captured_r <= 1'b0;
            resident_bypass_rs1_captured_r <= 1'b0;
            resident_bypass_rs2_captured_r <= 1'b0;
        end else begin
            if (late_load_rs1_i && late_load_rs1_match_w) begin
                late_load_rs1_captured_r <= 1'b1;
                late_load_rs1_value_r <= late_load_rs1_live_value_w;
            end
            if (late_load_rs2_i && late_load_rs2_match_w) begin
                late_load_rs2_captured_r <= 1'b1;
                late_load_rs2_value_r <= late_load_rs2_live_value_w;
            end
            if (resident_bypass_rs1_i && resident_bypass_rs1_match_w) begin
                resident_bypass_rs1_captured_r <= 1'b1;
                resident_bypass_rs1_value_r <= resident_source_rs1_w;
            end
            if (resident_bypass_rs2_i && resident_bypass_rs2_match_w) begin
                resident_bypass_rs2_captured_r <= 1'b1;
                resident_bypass_rs2_value_r <= resident_source_rs2_w;
            end
        end
    end

    // Sequential PCs only add the constants 2 or 4, so ordinary RTL is clear
    // enough here.  The variable PC+immediate path uses the structural adder.
    wire [31:0] fallthrough_w = pc_i + (is_compressed_i ? 32'd2 : 32'd4);
    wire [31:0] pc_relative_target_w;
    wire unused_pc_target_carry_w;
    edrv32_adder32 u_pc_relative_target (
        .lhs_i(pc_i),
        .rhs_i(imm_i),
        .carry_i(1'b0),
        .sum_o(pc_relative_target_w),
        .carry_o(unused_pc_target_carry_w)
    );
    wire [31:0] jalr_base_w = control_effective_rs1_w;
    wire [31:0] jalr_sum_w;
    wire unused_jalr_carry_w;
    edrv32_adder32 u_jalr_target (
        .lhs_i(jalr_base_w),
        .rhs_i(imm_i),
        .carry_i(1'b0),
        .sum_o(jalr_sum_w),
        .carry_o(unused_jalr_carry_w)
    );
    wire [31:0] jalr_target_w = {jalr_sum_w[31:1], 1'b0};
    wire control_taken_w = is_jump_w || (is_branch_w && branch_taken_w);
    wire [31:0] control_target_w = (is_jump_w && (instr_i[6:0] == `EDRV32_OPCODE_JALR))
                                   ? jalr_target_w : pc_relative_target_w;
    wire [31:0] actual_next_w = control_taken_w ? control_target_w : fallthrough_w;

    // Compare direction first and compare targets only when both sides agree
    // that control flow is taken.  Besides being exactly equivalent for stale
    // BTB metadata on non-control uops, this keeps branch_taken_w out of a
    // 32-bit actual-next mux followed by another 32-bit equality tree.
    wire direction_miss_w = control_taken_w ^ predicted_taken_i;
    wire target_miss_w = control_taken_w && predicted_taken_i &&
                         (control_target_w != predicted_target_i);
    wire mispredict_w = !exception_valid_i &&
                        (direction_miss_w || target_miss_w);

    // Legal loads and stores use ADD for effective-address generation. Check
    // only the low address bits here so alignment does not depend on the
    // general ALU's compare/shift/result selection path.
    wire [1:0] memory_addr_lsb_w = effective_lhs_w[1:0] + rhs_i[1:0];
    wire address_misaligned_w =
        ((mem_size_i == `BUS_SZ_HALF) && memory_addr_lsb_w[0]) ||
        ((mem_size_i == `BUS_SZ_WORD) && (|memory_addr_lsb_w));
    wire memory_misaligned_w = (is_load_w || is_store_w) && address_misaligned_w &&
                               !exception_valid_i;

    reg exception_valid_w;
    reg [`EDRV32_EXC_CAUSE_W-1:0] exception_cause_w;
    reg [31:0] exception_tval_w;

    // Reserve redirect capacity for every uop that can still require a repair.
    // This deliberately depends only on registered decode/prediction metadata,
    // not on branch_taken_w/mispredict_w, so the branch compare cone cannot
    // feed back through ready_o into the frontend.
    wire redirect_slot_needed_w = valid_i && !exception_valid_i &&
                                  (is_branch_w || is_jump_w || predicted_taken_i);

    // A uop may leave EX only when every resource it may need can be accepted
    // on the same cycle.  The actual redirect remains conditional on
    // mispredict_w; reserving the slot only makes readiness conservative when
    // that slot is unavailable.
    wire redirect_needed_w = valid_i && candidate_ready_w &&
                             operands_ready_w && mispredict_w;
    wire mdu_request_needed_w = valid_i && candidate_ready_w &&
                                operands_ready_w && is_mdu_w &&
                                rd_write_i && (rd_i != 5'd0) &&
                                !exception_valid_i;
    wire side_effects_ready_w = operands_ready_w &&
                                (!redirect_slot_needed_w || redirect_ready_i) &&
                                (!mdu_request_needed_w || mdu_req_ready_i);

    // The scalar ALU and branch comparator operate in parallel.
    edrv32_alu u_alu (
        .op_i(alu_op_i),
        .lhs_i(effective_lhs_w),
        .rhs_i(effective_rhs_w),
        .result_o(alu_result_w)
    );

    wire [31:0] branch_lhs_w = control_effective_rs1_w;
    wire [31:0] branch_rhs_w = control_effective_rs2_w;
    wire branch_taken_general_w;
    edrv32_branch_unit u_branch_unit (
        .branch_op_i(branch_op_i),
        .lhs_i(branch_lhs_w),
        .rhs_i(branch_rhs_w),
        .taken_o(branch_taken_general_w)
    );
    wire load_nonzero_w = |load_queue_rs1_value_i;
    wire equality_rs1_match_w =
        (load_queue_rs1_value_i == control_effective_rs2_w);
    wire equality_rs2_match_w =
        (control_effective_rs1_w == load_queue_rs2_value_i);
    wire equality_both_match_w =
        (load_queue_rs1_value_i == load_queue_rs2_value_i);
    wire equality_live_match_w = equality_rs1_live_w
        ? (equality_rs2_live_w ? equality_both_match_w : equality_rs1_match_w)
        : equality_rs2_match_w;
    wire equality_live_taken_w = (branch_op_i == `EDRV32_BRANCH_EQ)
        ? equality_live_match_w : !equality_live_match_w;
    wire equality_live_w = equality_rs1_live_w || equality_rs2_live_w;
    assign branch_taken_w = zero_branch_live_w
        ? ((branch_op_i == `EDRV32_BRANCH_EQ)
            ? !load_nonzero_w : load_nonzero_w)
        : equality_live_w ? equality_live_taken_w : branch_taken_general_w;

    // Preserve an earlier exception unless the current memory operation adds
    // a more immediate address-alignment fault.
    always @* begin
        exception_valid_w = exception_valid_i;
        exception_cause_w = exception_cause_i;
        exception_tval_w  = exception_tval_i;
        if (memory_misaligned_w) begin
            exception_valid_w = 1'b1;
            exception_cause_w = is_load_w ? `EDRV32_EXC_LOAD_MISALIGNED
                                           : `EDRV32_EXC_STORE_MISALIGNED;
            // MEM1 reconstructs this precise tval from the separately
            // registered effective address. Avoid duplicating the long
            // Load-bypass/ALU path into a second EX payload register bank.
        end
    end

    // EX owns the elastic-boundary policy.  The pipe module only captures the
    // validity and payload values selected here.
    assign candidate_ready_w = ~kill_i && (~result_valid_o || result_ready_i);
    assign ready_o = ~kill_i && candidate_ready_w && side_effects_ready_w;

    assign redirect_valid_o  = ~kill_i && redirect_needed_w;
    assign redirect_target_o = actual_next_w;
    assign younger_kill_o     = redirect_valid_o && redirect_ready_i && ready_o;
    assign direction_mispredict_o = younger_kill_o && direction_miss_w;
    assign target_mispredict_o = younger_kill_o && target_miss_w;

    assign mdu_req_valid_o = ~kill_i && mdu_request_needed_w;
    assign mdu_req_op_o    = mdu_op_i;
    // Keep the divider data pins on the same registered/captured operand
    // contract as its request valid. Static timing cannot infer that live
    // D-cache data is irrelevant while req_valid is low, so leaving the raw
    // mux connected would recreate a false functional shortcut in hardware.
    assign mdu_req_lhs_o   = effective_lhs_w;
    assign mdu_req_rhs_o   = effective_rs2_w;
    assign mdu_req_mul_lhs_o = registered_mul_lhs_w;
    assign mdu_req_mul_rhs_o = registered_mul_rhs_w;
    assign mdu_req_div_lhs_o = control_effective_rs1_w;
    assign mdu_req_div_rhs_o = control_effective_rs2_w;
    assign mdu_req_rd_o    = rd_i;
    assign mdu_req_fire_o  = mdu_req_valid_o && mdu_req_ready_i && ready_o;

    // Predictor training is emitted only for a uop that actually leaves EX.
    wire capture_w = valid_i && ready_o;

    wire is_jalr_w = is_jump_w &&
                     (instr_i[6:0] == `EDRV32_OPCODE_JALR);
    wire rd_is_link_w = (rd_i == 5'd1) || (rd_i == 5'd5);
    wire rs1_is_link_w = (instr_i[19:15] == 5'd1) ||
                         (instr_i[19:15] == 5'd5);

    // Branch/jump and load/store op classes are mutually exclusive.  Qualify
    // predictor training with the incoming exception only, so the load/store
    // alignment cone cannot become part of every predictor write enable.
    assign predictor_update_valid_o = capture_w &&
        (is_branch_w || is_jump_w) && !exception_valid_i;
    assign predictor_update_pc_o = pc_i;
    assign predictor_update_is_conditional_o = is_branch_w;
    assign predictor_update_is_unconditional_o = is_jump_w;
    assign predictor_update_taken_o = control_taken_w;
    assign predictor_update_target_o = control_target_w;
    assign predictor_update_ras_push_o = is_jump_w && rd_is_link_w;
    assign predictor_update_ras_pop_o = is_jalr_w && rs1_is_link_w &&
        (!rd_is_link_w || (rd_i != instr_i[19:15]));
    assign predictor_update_link_addr_o = fallthrough_w;

    // Form the complete EX result packet consumed by the next boundary.
    assign candidate_valid_w           = ~kill_i && valid_i &&
                                         side_effects_ready_w;
    assign candidate_pc_w              = pc_i;
    assign candidate_instr_w           = instr_i;
    assign candidate_is_compressed_w   = is_compressed_i;
    assign candidate_epoch_w           = epoch_i;
    assign candidate_rd_w              = rd_i;
    assign candidate_rd_write_w        = rd_write_i && !exception_valid_w;
    assign candidate_op_class_w        = op_class_i;
    assign candidate_result_w          = is_jump_w ? fallthrough_w : alu_result_w;
    assign candidate_result_ready_w    = rd_write_i && !exception_valid_w &&
                                         ((op_class_i == `EDRV32_OP_ALU) ||
                                          is_jump_w);
    assign candidate_mem_addr_w        = alu_result_w;
    assign candidate_mem_size_w        = mem_size_i;
    assign candidate_mem_unsigned_w    = mem_unsigned_i;
    assign candidate_store_data_w      = effective_rs2_w;
    assign candidate_mdu_token_w       = mdu_req_fire_o;
    assign candidate_csr_op_w          = csr_op_i;
    assign candidate_csr_addr_w        = csr_addr_i;
    assign candidate_csr_src_w         = effective_csr_src_w;
    // These flags belong to non-memory op classes. A new EX alignment fault
    // therefore cannot coexist with them; DECODE already clears the flags
    // for an inherited exception. Keep the D-cache/alignment cone off these
    // otherwise independent pipe payload enables.
    assign candidate_fence_w           = fence_i && !exception_valid_i;
    assign candidate_fencei_w          = fencei_i && !exception_valid_i;
    assign candidate_mret_w            = mret_i && !exception_valid_i;
    assign candidate_wfi_w             = wfi_i && !exception_valid_i;
    assign candidate_exception_valid_w = exception_valid_w;
    assign candidate_exception_cause_w = exception_cause_w;
    assign candidate_exception_tval_w  = exception_tval_w;

    assign pipe_transfer_w = result_valid_o && result_ready_i;
    assign pipe_valid_we_w = kill_i || capture_w || pipe_transfer_w;
    assign pipe_valid_d_w  = ~kill_i && capture_w;


    // B has no control side effects. Its result uses the parent's controls.
    edrv32_alu u_second_alu (
        .op_i(second_alu_w),
        .lhs_i(second_effective_lhs_w),
        .rhs_i(second_effective_rhs_w),
        .result_o(second_result_w)
    );
    wire second_parent_eligible_w = (op_class_i == `EDRV32_OP_ALU) ||
        (op_class_i == `EDRV32_OP_LOAD) || (op_class_i == `EDRV32_OP_STORE);
    wire second_live_w = (DUAL_ISSUE != 0) && second_valid_w &&
        second_parent_eligible_w && !exception_valid_w;
    wire [`EDRV32_PAIR_RESULT_W-1:0] candidate_second_w =
        {second_live_w, second_pc_w, second_instr_w, second_compressed_w,
         second_epoch_w, second_rd_w, second_write_w, second_result_w};

    edrv32_pipe_ex_to_mem1 #(.SECOND_ENABLE(DUAL_ISSUE)) u_pipe (
        .second_i(candidate_second_w),
        .second_o(result_second_o),
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .valid_we_i(pipe_valid_we_w),
        .valid_d_i(pipe_valid_d_w),
        .payload_we_i(capture_w),
        .pc_i(candidate_pc_w),
        .instr_i(candidate_instr_w),
        .is_compressed_i(candidate_is_compressed_w),
        .epoch_i(candidate_epoch_w),
        .rd_i(candidate_rd_w),
        .rd_write_i(candidate_rd_write_w),
        .op_class_i(candidate_op_class_w),
        .result_i(candidate_result_w),
        .result_ready_i(candidate_result_ready_w),
        .mem_addr_i(candidate_mem_addr_w),
        .mem_size_i(candidate_mem_size_w),
        .mem_unsigned_i(candidate_mem_unsigned_w),
        .store_data_i(candidate_store_data_w),
        .mdu_token_i(candidate_mdu_token_w),
        .csr_op_i(candidate_csr_op_w),
        .csr_addr_i(candidate_csr_addr_w),
        .csr_src_i(candidate_csr_src_w),
        .fence_i(candidate_fence_w),
        .fencei_i(candidate_fencei_w),
        .mret_i(candidate_mret_w),
        .wfi_i(candidate_wfi_w),
        .exception_valid_i(candidate_exception_valid_w),
        .exception_cause_i(candidate_exception_cause_w),
        .exception_tval_i(candidate_exception_tval_w),
        .valid_o(result_valid_o),
        .pc_o(result_pc_o),
        .instr_o(result_instr_o),
        .is_compressed_o(result_is_compressed_o),
        .epoch_o(result_epoch_o),
        .rd_o(result_rd_o),
        .rd_write_o(result_rd_write_o),
        .op_class_o(result_op_class_o),
        .result_o(result_value_o),
        .result_ready_o(result_value_ready_o),
        .mem_addr_o(result_mem_addr_o),
        .mem_size_o(result_mem_size_o),
        .mem_unsigned_o(result_mem_unsigned_o),
        .store_data_o(result_store_data_o),
        .mdu_token_o(result_mdu_token_o),
        .csr_op_o(result_csr_op_o),
        .csr_addr_o(result_csr_addr_o),
        .csr_src_o(result_csr_src_o),
        .fence_o(result_fence_o),
        .fencei_o(result_fencei_o),
        .mret_o(result_mret_o),
        .wfi_o(result_wfi_o),
        .exception_valid_o(result_exception_valid_o),
        .exception_cause_o(result_exception_cause_o),
        .exception_tval_o(result_exception_tval_o)
    );

endmodule
