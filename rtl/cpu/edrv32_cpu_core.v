// File: edrv32_cpu_core.v
// Spec: cpu-spec v0.15 2-7
// Description: Execute in-order dual-issue instructions through D/E/M/W.
//              Commit precise traps, memory transactions and architectural state.
// Clock: clk_sys.
module edrv32_cpu_core (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,
    input wire rst_sys_csr_n_i,
    input wire [9:0] rst_sys_counter_n_i,

    // Instruction cache.
    output wire ic_req_valid_o,
    output wire [31:0] ic_req_addr_o,
    input wire ic_req_ready_i,
    input wire ic_resp_valid_i,
    input wire [7:0] ic_resp_valid_copy_i,
    input wire [63:0] ic_resp_data_i,
    input wire [43:0] ic_resp_predecode_i,
    input wire ic_resp_err_i,
    output wire ic_kill_o,
    output wire ic_inv_o,
    input wire ic_inv_done_i,
    // Data cache.
    output wire dc_req_valid_o,
    output wire dc_req_early_o,
    output wire [31:0] dc_req_addr_o,
    output wire dc_req_store_o,
    output wire [1:0] dc_req_size_o,
    input wire dc_req_ready_i,
    input wire dc_resp_valid_i,
    input wire [63:0] dc_resp_way_data_i,
    input wire [1:0] dc_resp_way_hit_i,
    input wire dc_resp_err_i,
    input wire dc_resp_device_i,
    output wire dc_kill_o,
    output wire dc_commit_o,
    output wire [31:0] dc_store_data_o,
    output wire dc_fence_o,
    output wire dc_clean_all_o,
    input wire dc_fence_done_i,
    input wire dc_wb_event_i,
    // Read-only D-stage cache query (cpu-spec 3.3, 4.10).
    output wire dc_early_valid_o,
    output wire [31:0] dc_early_addr_o,
    input wire [1:0] dc_early_way_hit_i,
    input wire [63:0] dc_early_way_data_i,
    // Interrupts, CLINT time and observation.
    input wire irq_meip_i,
    input wire irq_msip_i,
    input wire irq_mtip_i,
    input wire [63:0] mtime_i,
    output wire [63:0] debug_o
);
    // Shared frontend/backend instruction-record layout (cpu-spec 4.1).
    localparam REC_BITS = 179;
    localparam REC_PC_LSB = 0;
    localparam REC_INSTR_LSB = 32;
    localparam REC_RAW_LSB = 64;
    localparam REC_ILLEGAL = 97;
    localparam REC_FETCH_ERR = 98;
    localparam REC_PRED_HIT = 99;
    localparam REC_PRED_TAKEN = 100;
    localparam REC_PRED_TARGET_LSB = 101;
    localparam REC_GHR_LSB = 133;
    localparam REC_RAS_LSB = 142;
    localparam C_ALU = 4'd0;
    localparam C_LUI = 4'd1;
    localparam C_AUIPC = 4'd2;
    localparam C_JAL = 4'd3;
    localparam C_JALR = 4'd4;
    localparam C_BRANCH = 4'd5;
    localparam C_LOAD = 4'd6;
    localparam C_STORE = 4'd7;
    localparam C_MUL = 4'd8;
    localparam C_DIV = 4'd9;
    localparam C_CSR = 4'd10;
    localparam C_SYSTEM = 4'd11;
    localparam C_FENCE = 4'd12;
    localparam C_FENCE_I = 4'd13;
    wire [1:0] d_pipe1_w;
    wire [1:0] d_control_w;
    wire d_pair_w;
    wire d_swap_w;
    wire d_jal_redirect0_w;
    wire d_redirect_slot_w;
    wire [31:0] d_slot_target_w [0:1];
    // Registered frontend events; payload never depends on the emit-cycle handshake.
    reg e_redirect_r;
    reg e_redirect_advanced_r;
    reg e_redirect_old_r;
    wire [1:0] m_squash_w;
    wire [36:0] e_redirect_ras_w;
    wire e_redirect_push_w;
    wire e_redirect_pop_w;
    wire [31:0] e_redirect_link_w;
    wire [1:0] e_redirect_cause_w;
    reg [31:0] e_redirect_target_lane_r [0:1];
    reg [31:0] e_redirect_next_lane_r [0:1];
    reg [36:0] e_redirect_ras_lane_r [0:1];
    reg [31:0] e_redirect_origin_lane_r [0:1];
    reg [1:0] e_redirect_action_lane_r [0:1];
    reg [1:0] e_redirect_cause_lane_r [0:1];
    (* keep = "true", syn_preserve = 1 *) reg [9:0] e_redirect_lane_copy1_r;
    (* keep = "true", syn_preserve = 1 *) reg [3:0] e_redirect_taken_copy1_r;
    reg m_redirect_r;
    reg m_redirect_trap_r;
    wire m_front_capture_w;
    reg [31:0] m_redirect_origin_r;
    wire [31:0] e_redirect_origin_w;
    reg [31:0] d_redirect_origin_r;
    reg [31:0] m_redirect_pc_r;
    reg d_redirect_r;
    reg d_redirect_issued_r;
    reg d_redirect_slot_r;
    reg [31:0] d_redirect_pc_r;
    reg [36:0] d_redirect_ras_r;
    reg d_redirect_push_r;
    reg [31:0] d_redirect_link_r;
    reg update_valid_r;
    reg update_clear_r;
    wire [6:0] update_clear_index_w;
    reg [31:0] update_pc_r;
    reg [31:0] update_target_r;
    reg [2:0] update_type_r;
    reg update_taken_r;
    reg [11:0] update_index_r;
    reg [11:0] update_tournament_r;
    wire e_flush_w;
    wire frontend_redirect_w;
    wire [16:0] frontend_redirect_copy_w;
    wire [31:0] frontend_redirect_pc_w;
    wire [36:0] frontend_redirect_ras_w;
    wire frontend_d_redirect_w;
    wire d_capture_w;
    wire e_capture_w;
    wire m_kill_all_w;
    wire d_early_eligible_w;
    wire d_early_slot_w;
    wire [4:0] d_early_select_w;
    wire [31:0] d_early_base_w;
    reg e_early_r;
    reg e_repair_pending_r;
    reg [3:0] e_repair_mask_r;
    wire e_repair_w;
    wire [31:0] e_early_result_w [0:1];
    wire [31:0] m_load_result_w [0:1];
    reg e_swap_r;
    reg m_swap_r;
    reg w_swap_r;
    wire e_old_w;
    wire e_young_w;
    wire m_old_w;
    wire m_young_w;
    wire e_branch_lane_w;
    wire m_branch_lane_w;
    wire e_older_fault_w;
    wire [1:0] e_lane_fault_w;
    wire e_old_redirect_w;
    wire e_kill_young_w;
    wire [1:0] e_survive_w;
    wire [1:0] e_lane_control_w;
    wire [1:0] e_lane_taken_w;
    wire [1:0] e_lane_branch_taken_w;
    wire [1:0] e_lane_call_w;
    wire [1:0] e_lane_return_w;
    wire [1:0] e_lane_jump_fault_w;
    reg [1:0] e_jump_fault_r;
    wire e_old_control_unresolved_w;
    wire [1:0] e_lane_redirect_needed_w;
    wire [31:0] e_lane_target_w [0:1];
    wire [31:0] e_lane_next_pc_w [0:1];
    wire [2:0] e_lane_type_w [0:1];
    wire [1:0] e_lane_exception_w;
    wire [1:0] m_lane_fault_w;
    wire m_fault1_w;
    wire m_fault_old_w;
    wire m_block_early_w;
    wire m_trap_lane_w;
    reg e_exception1_r;
    reg m_exception1_r;
    reg [31:0] e_cause1_r;
    reg [31:0] e_value1_r;
    reg [31:0] m_cause1_r;
    reg [31:0] m_value1_r;
    reg [31:0] e_pc_target1_r;
    reg e_pc_target_match1_r;
    wire [31:0] e_lane_pc_target_w [0:1];
    wire [1:0] e_lane_target_match_w;
    wire [1:0] d_map_w;
    // v0.20: choose a load using queue contents and pipeline capabilities only.
    assign d_early_slot_w = !d_load_w[0] && d_load_w[1] &&
        d_count_w >= 2 && d_pipe1_w[0];
    // Only registered/architectural producers may feed the D address adder.
    // The exclusion list is independent of cache hit and current issue handshakes.
    assign d_early_eligible_w = d_load_w[d_early_slot_w] &&
        !(d_early_slot_w && d_dest_w[0] && d_rd_w[0] == d_rs1_w[1]) &&
        !(e_valid_r[0] && e_dest_r[0] &&
            e_rd_r[0] == d_rs1_w[d_early_slot_w]) &&
        !(e_valid_r[1] && e_dest_r[1] &&
            e_rd_r[1] == d_rs1_w[d_early_slot_w]) &&
        !(m_valid_r[0] && m_dest_r[0] &&
            m_rd_r[0] == d_rs1_w[d_early_slot_w] &&
            m_slow_r) &&
        !(w_valid_r[0] && w_dest_r &&
            w_rd_r[0] == d_rs1_w[d_early_slot_w] && w_mul_r[0]);
    // Qualifying queries exclude E and unregistered M/W producers. Select
    // registered data directly so those excluded results never feed this adder.
    assign d_early_select_w = {d_bypass_select_w[d_early_slot_w*2][6:3],
        d_bypass_select_w[d_early_slot_w*2][0]};
    assign d_early_base_w =
        ({32{d_early_select_w[0]}} & d_register_w[d_early_slot_w*2]) |
        ({32{d_early_select_w[1]}} & m_result_r[0]) |
        ({32{d_early_select_w[2]}} & m_result_r[1]) |
        ({32{d_early_select_w[3]}} & w_result_r[0]) |
        ({32{d_early_select_w[4]}} & w_result_r[1]);
    assign dc_early_addr_o = d_early_base_w + d_imm_w[d_early_slot_w];
    assign dc_early_valid_o = d_count_w != 0 && d_early_eligible_w;
    // Format each way before its late hit selects an operand (cpu-spec 4.9).
    function [31:0] load_value;
        input [31:0] data_i;
        input [3:0] format_i;
        integer bit_index;
        begin
            load_value[7:0] = data_i[7:0];
            for (bit_index = 8; bit_index < 16; bit_index = bit_index + 1)
                load_value[bit_index] = (data_i[bit_index] && format_i[2]) |
                    (data_i[7] && format_i[0]);
            for (bit_index = 16; bit_index < 32; bit_index = bit_index + 1)
                load_value[bit_index] = (data_i[bit_index] && format_i[3]) |
                    (data_i[15] && format_i[1]) | (data_i[7] && format_i[0]);
        end
    endfunction
    // Decode size/sign before the RAM edge, in parallel with address generation.
    reg [3:0] e_load_format_r;
    reg [3:0] m_load_format_r;
    wire [2:0] d_load_format_w;
    assign d_load_format_w = d_instr_w[d_map_w[0]][14:12];
    always @(posedge clk_i) begin
        if (e_operand_load_copy_w[0]) begin
            e_load_format_r <= {d_load_format_w[1],
                d_load_format_w[1] || d_load_format_w[0],
                d_load_format_w == 1, d_load_format_w == 0};
        end
        if (e_advance_copy_w[0])
            m_load_format_r <= e_load_format_r;
    end
    genvar load_way;
    generate
        for (load_way = 0; load_way < 2; load_way = load_way + 1) begin : g_load_way
            assign e_early_result_w[load_way] =
                load_value(dc_early_way_data_i[load_way*32 +: 32], e_load_format_r);
            assign m_load_result_w[load_way] =
                load_value(dc_resp_way_data_i[load_way*32 +: 32], m_load_format_r);
        end
    endgenerate
    assign e_repair_w = e_repair_pending_r && !m_wait_w && !m_block_early_w;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            e_early_r <= 0;
            e_repair_pending_r <= 0;
        end else begin
            // A query is usable only in the immediately following E cycle.
            e_early_r <= dc_early_valid_o && d_issue_valid_w &&
                d_early_slot_w == d_map_w[0];
            if (d_issue_valid_w)
                e_repair_pending_r <= e_early_r && e_advance_w && !(|dc_early_way_hit_i) &&
                    (|e_repair_mask_next_w);
            if (e_repair_w || m_redirect_w || e_flush_w)
                e_repair_pending_r <= 0;
        end
    end
    wire [3:0] e_repair_mask_next_w;
    genvar repair_operand;
    generate
        for (repair_operand = 0; repair_operand < 4;
            repair_operand = repair_operand + 1) begin : g_repair_mask
            assign e_repair_mask_next_w[repair_operand] =
                d_bypass_select_w[d_map_w[repair_operand/2]*2 + repair_operand%2][1] &&
                (repair_operand%2 == 0 ? d_use1_w[d_map_w[repair_operand/2]] :
                d_use2_w[d_map_w[repair_operand/2]]) &&
                (repair_operand/2 == 0 || d_issue_w[1]);
        end
    endgenerate
    always @(posedge clk_i) begin
        if (d_issue_valid_w)
            e_repair_mask_r <= e_repair_mask_next_w;
    end
    assign e_old_w = e_swap_r;
    assign e_young_w = !e_swap_r;
    assign m_old_w = m_swap_r;
    assign m_young_w = !m_swap_r;
    assign d_map_w = {1'b1 ^ d_swap_w, d_swap_w};
    assign e_lane_pc_target_w[0] = e_pc_target_r;
    assign e_lane_pc_target_w[1] = e_pc_target1_r;
    assign e_lane_target_match_w = {e_pc_target_match1_r, e_target_match_w};
    assign e_lane_exception_w = {e_exception1_r, e_exception_r};
    assign e_branch_lane_w = e_valid_r[1] && e_lane_control_w[1];
    assign m_branch_lane_w = m_valid_r[1] && m_control_r;
    // Each survivor tests only its older lane. A younger pipe-0 address must
    // not enter the pipe-0 ownership/operand-enable loop through the old-lane mux.
    assign e_lane_fault_w[0] = e_valid_r[0] &&
        (e_exception_r || e_jump_fault_r[0] || (e_memory_r && e_misaligned_w));
    assign e_lane_fault_w[1] = e_valid_r[1] && (e_exception1_r || e_jump_fault_r[1]);
    assign e_old_redirect_w = e_redirect_r && !e_redirect_advanced_r && e_redirect_old_r;
    assign e_older_fault_w = e_swap_r ? e_lane_fault_w[1] : e_lane_fault_w[0];
    assign e_kill_young_w = e_older_fault_w || e_old_redirect_w;
    assign m_squash_w[0] = m_kill_all_w ||
        (e_redirect_r && e_redirect_advanced_r && e_redirect_old_r && m_swap_r);
    assign m_squash_w[1] = m_kill_all_w ||
        (e_redirect_r && e_redirect_advanced_r && e_redirect_old_r && !m_swap_r);
    assign e_survive_w[0] = e_valid_r[0] &&
        !(e_swap_r && (e_lane_fault_w[1] || e_old_redirect_w));
    assign e_survive_w[1] = e_valid_r[1] &&
        !(!e_swap_r && (e_lane_fault_w[0] || e_old_redirect_w));
    wire [357:0] d_data_w;
    wire [139:0] d_predecode_w;
    wire [1:0] d_load_w;
    wire [1:0] d_mul_w;
    wire [1:0] d_csr_w;
    wire [1:0] d_memory_w;
    wire [1:0] d_serial_slot_w;
    wire [1:0] d_dest_w;
    wire [1:0] d_slow_w;
    wire [1:0] d_jal_w;
    reg [1:0] e_load_r;
    reg [1:0] e_mul_r;
    reg [1:0] e_csr_r;
    reg e_memory_r;
    reg [1:0] e_control_r;
    reg [1:0] e_dest_r;
    reg e_slow_r;
    reg m_load_r;
    reg [1:0] m_mul_r;
    reg m_csr_r;
    reg m_memory_r;
    reg m_control_r;
    reg [1:0] m_dest_r;
    reg m_slow_r;
    reg [1:0] w_mul_r;
    reg w_dest_r;
    wire [5:0] d_index_hi_w;
    wire [23:0] d_tournament_w;
    wire [1:0] d_count_w;
    wire [2:0] ib_count_w;
    wire [1:0] d_issue_w;
    wire d_issue_valid_w;
    wire d_head_single_w;
    wire d_single_w;
    reg [2:0] d_pair_reason_pre_w;
    wire [REC_BITS-1:0] d_record_w [0:1];
    wire [31:0] d_instr_w [0:1];
    wire [4:0] d_rs1_w [0:1];
    wire [4:0] d_rs2_w [0:1];
    wire [4:0] d_rd_w [0:1];
    wire d_use1_w [0:1];
    wire d_use2_w [0:1];
    wire d_write_w [0:1];
    wire [31:0] d_imm_w [0:1];
    wire [3:0] d_class_w [0:1];
    wire [3:0] d_operation_w [0:1];
    wire d_immediate_w [0:1];
    wire d_illegal_w [0:1];
    wire [31:0] d_register_w [0:3];
    wire [4:0] d_source_w [0:3];
    wire [79:0] d_operand_addr_w;
    wire [31:0] e_forward_w [0:3];
    wire [31:0] e_alu_input_w [0:1];
    wire [31:0] e_branch_forward_w [0:3];
    wire [3:0] d_hazard_w;
    wire [2:0] d_bypass_w [0:3];
    wire [6:0] d_bypass_select_w [0:3];
    wire [2:0] d_wait_kind_w [0:3];
    wire d_raw_w;
    wire d_pair_type_w;
    wire d_serial_w;
    wire d_csr_wait_w;
    wire d_available_w;
    wire d_redirect_w;
    reg d_redirected_r;
    wire [31:0] d_target_w;
    wire [31:0] d_jalr_expected_even_w;
    wire [31:0] d_jalr_expected_odd_w;
    reg [2:0] d_pair_reason_w;
    reg [1:0] e_valid_r;
    reg [1:0] m_valid_r;
    reg [1:0] w_valid_r;
    reg [1:0] w2_valid_r;
    reg w2_swap_r;
    reg [REC_BITS-1:0] w2_record_r [0:1];
    reg [31:0] w2_result_r [0:1];
    wire [31:0] w2_result_w [0:1];
    reg [4:0] w2_rd_r [0:1];
    reg w2_write_r [0:1];
    reg [3:0] w2_class_r [0:1];
    reg [REC_BITS-1:0] e_record_r [0:1];
    wire [11:0] e_predict_index_w;
    reg [11:0] e_predict_index_r;
    reg [11:0] e_tournament_r;
    assign e_predict_index_w = e_predict_index_r;
    always @(posedge clk_i) begin
        if (e_operand_load_copy_w[4])
            e_tournament_r <= d_control_w[1] && d_pair_w ?
                d_tournament_w[23:12] : d_tournament_w[11:0];
        if (e_operand_load_copy_w[4])
            e_predict_index_r <= d_control_w[1] && d_pair_w ?
                {d_index_hi_w[5:3], d_record_w[1][REC_GHR_LSB +: 9]} :
                {d_index_hi_w[2:0], d_record_w[0][REC_GHR_LSB +: 9]};
    end
    reg [REC_BITS-1:0] m_record_r [0:1];
    reg [REC_BITS-1:0] w_record_r [0:1];
    reg [3:0] e_class_r [0:1];
    reg [3:0] m_class_r [0:1];
    reg [3:0] w_class_r [0:1];
    reg [9:0] e_operation_select_r [0:1];
    reg e_immediate_r [0:1];
    reg [31:0] e_imm_r [0:1];
    reg [31:0] e_operand_a_r [0:1];
    wire [31:0] e_operand_a_w [0:1];
    reg [31:0] e_operand_b_r [0:1];
    wire [31:0] e_operand_b_w [0:1];
    reg [31:0] e_branch_a_r [0:1] /* synthesis syn_preserve=1 */;
    reg [31:0] e_branch_b_r [0:1] /* synthesis syn_preserve=1 */;
    wire [31:0] e_branch_a_w [0:1];
    wire [31:0] e_branch_b_w [0:1];
    wire [15:0] e_alu_forward_w [0:3];
    reg [31:0] e_forward_result_r [0:1];
    (* keep = "true", syn_preserve = 1 *) reg [31:0] e_branch_result_copy_r [0:1];
    reg [31:0] e_nonalu_result_r [0:1];
    reg e_div_result_r [0:1];
    wire [31:0] e_alu_operand_b_w [0:1];
    reg [31:0] e_pc_target_r;
    reg e_pc_target_match_r;
    reg [31:0] e_jalr_expected_even_r;
    reg [31:0] e_jalr_expected_odd_r;
    reg [4:0] e_rd_r [0:1];
    reg [4:0] m_rd_r [0:1];
    reg [4:0] w_rd_r [0:1];
    reg e_write_r [0:1];
    reg m_write_r [0:1];
    reg w_write_r [0:1];
    reg e_exception_r;
    reg m_exception_r;
    reg [31:0] e_cause_r;
    reg [31:0] m_cause_r;
    reg [31:0] e_value_r;
    reg [31:0] m_value_r;
    wire [31:0] e_alu_w [0:1];
    (* keep = "true", syn_preserve = 1 *) reg [31:0] e_alu_operand_b_copy1_r [0:1];
    reg [31:0] e_result_w [0:1];
    reg [31:0] m_result_r [0:1];
    reg [31:0] w_result_r [0:1];
    reg [31:0] m_result_w [0:1];
    wire [31:0] w_result_w [0:1];
    reg [31:0] m_store_r;
    reg [31:0] m_csr_data_r;
    reg m_wait_dc_r;
    reg [31:0] m_instr_r;
    wire [31:0] e_instr_w;
    wire [31:0] e_next_pc_w;
    wire [31:0] e_address_w;
    wire e_control_w;
    wire e_redirect_w;
    wire e_redirect0_w;
    wire e_redirect1_w;
    wire [31:0] e_redirect_pc_w;
    wire e_memory_w;
    wire e_misaligned_w;
    wire e_jump_misaligned_w;
    wire e_target_match_w;
    wire e_advance_w;
    wire e_operand_load_w;
    wire [4:0] e_operand_load_copy_w;
    wire [1:0] e_data_load_copy_w;
    wire e_data_payload_block_w;
    wire [1:0] e_advance_copy_w;
    wire e_payload_block_w;
    genvar enable_group;
    // Replicate the existing E-valid state, not the late combinational handshakes.
    // Each local enable still sees this cycle's D-cache response and redirects.
    generate
        for (enable_group = 0; enable_group < 7;
            enable_group = enable_group + 1) begin : g_e_enable
            reg e_valid_r_copy /* synthesis syn_preserve=1 */;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i)
                    e_valid_r_copy <= 0;
                else begin
                    if (e_advance_w)
                        e_valid_r_copy <= 0;
                    if (d_issue_valid_w)
                        e_valid_r_copy <= 1;
                    if (m_redirect_w || e_flush_w)
                        e_valid_r_copy <= 0;
                end
            end
            if (enable_group < 2) begin : g_data_load
                assign e_data_load_copy_w[enable_group] =
                    !(e_valid_r_copy && e_data_payload_block_w) &&
                    (!(e_valid_r_copy && m_valid_r[0] && m_wait_dc_r) || dc_resp_valid_i);
            end
            if (enable_group < 5) begin : g_load
                assign e_operand_load_copy_w[enable_group] =
                    !(e_valid_r_copy && e_payload_block_w) &&
                    (!(e_valid_r_copy && m_valid_r[0] && m_wait_dc_r) || dc_resp_valid_i);
            end else begin : g_advance
                assign e_advance_copy_w[enable_group-5] = e_valid_r_copy &&
                    !m_wait_w && !m_block_early_w && !e_flush_w &&
                    !e_repair_pending_r && !div_wait_w &&
                    (!e_memory_w || e_exception_r || e_misaligned_w || dc_req_ready_i);
            end
        end
    endgenerate
    wire e_payload_hold_w;
    wire e_payload_wait_dc_w;
    wire m_wait_other_w;
    wire e_resolve_w;
    reg e_resolved_r;
    wire e_resolve_ready_w;
    wire e_capture_reason_w;
    wire [3:0] e_capture_copy_w;
    wire m_advance_w;
    wire m_memory_w;
    wire m_wait_w;
    reg m_wait_r;
    reg div_wait_front_r;
    wire m_ready_w;
    wire [1:0] m_commit_w;
    wire m_commit0_w;
    wire m_fault0_w;
    wire m_interrupt_w;
    wire m_trap_w;
    wire [31:0] m_trap_pc_w;
    wire [31:0] m_trap_cause_w;
    wire [31:0] m_trap_value_w;
    wire m_system_commit_w;
    wire m_mret_w;
    wire m_wfi_w;
    wire m_fence_i_done_w;
    wire m_redirect_w;
    wire [31:0] m_redirect_pc_w;
    wire backend_redirect_w;
    wire [31:0] backend_redirect_pc_w;
    wire [36:0] backend_redirect_ras_w;
    reg m_device_started_r;
    reg m_fence_phase_r;
    reg sleep_r;
    wire irq_pending_w;
    wire [31:0] irq_cause_w;
    wire csr_global_mie_w;
    wire csr_meie_w;
    wire csr_mtie_w;
    wire csr_msie_w;
    wire [27:0] unused_status_high_w;
    wire [2:0] unused_status_low_w;
    wire [19:0] unused_mie_high_w;
    wire [2:0] unused_mie_middle0_w;
    wire [2:0] unused_mie_middle1_w;
    wire [2:0] unused_mie_low_w;
    wire unused_invalidate_done_w;
    wire [31:0] csr_mtvec_w;
    wire [31:0] csr_mepc_w;
    wire [31:0] csr_read_w;
    wire csr_decode_illegal_w;
    wire unused_csr_illegal_w;
    wire csr_m_access_w;
    wire csr_d_access_w;
    wire csr_write_w;
    wire [41:0] d_csr_select_w;
    reg [41:0] e_csr_select_r;
    reg [41:0] m_csr_select_r;
    wire [1:0] csr_command_w;
    wire [31:0] csr_operand_w;
    wire [1:0] retire_count_w;
    wire [1:0] csr_retire_count_w;
    wire w_instret_write_w;
    reg [31:0] event_count_w;
    wire mul_valid_w;
    wire [31:0] mul_result_w;
    wire div_busy_w;
    wire div_valid_w;
    wire [31:0] div_result_w;
    wire div_start_w;
    wire [7:0] div_start_copy_w;
    wire e_div_cancel_w;
    wire div_wait_w;
    reg div_started_r;
    reg div_done_r;
    reg [127:0] committed_ras_data_r;
    reg [1:0] committed_ras_ptr_r;
    reg [2:0] committed_ras_count_r;
    reg [1:0] committed_ras_ptr_w;
    reg [2:0] committed_ras_count_w;
    wire [36:0] committed_ras_w;
    reg w_ras_call_r;
    reg w_ras_return_r;
    reg [31:0] w_ras_link_r;
    (* keep = "true", syn_preserve = 1 *) reg [10:0] w_ras_commit_copy1_r;
    (* keep = "true", syn_preserve = 1 *) reg [15:0] committed_ras_ptr_copy1_r;
    (* keep = "true", syn_preserve = 1 *) reg [3:0] committed_ras_top_copy1_r;
    (* keep = "true", syn_preserve = 1 *) reg [3:0] committed_ras_second_copy1_r;
    wire [31:0] committed_ras_top_w;
    wire m_call_w;
    wire m_return_w;
    wire [31:0] m_link_w;
    wire f1_valid_w;
    wire f2_valid_w;
    wire fetch_wait_w;
    reg ic_expect_r;
    reg dc_expect_r;
    reg ic_miss_r;
    reg dc_miss_r;
    wire ic_miss_start_w;
    wire dc_miss_start_w;
    wire unused_mul_valid_w;
    wire [31:0] unused_lane1_predicted_target_w;
    integer result_idx;
    integer stage_idx;
    wire [11:0] trace_bypass_w /* verilator public_flat_rd */;
    reg [1:0] trace_redirect_cause_w /* verilator public_flat_rd */;
    reg [2:0] trace_stall_cause_w /* verilator public_flat_rd */;
    wire [1:0] trace_valid_w /* verilator public_flat_rd */;
    wire [63:0] trace_pc_w /* verilator public_flat_rd */;
    wire [63:0] trace_instr_w /* verilator public_flat_rd */;
    wire [9:0] trace_rd_w /* verilator public_flat_rd */;
    wire [63:0] trace_rd_data_w /* verilator public_flat_rd */;
    wire trace_trap_w /* verilator public_flat_rd */;
    wire [31:0] trace_cause_w /* verilator public_flat_rd */;
    wire [1:0] trace_redirect_stage_w /* verilator public_flat_rd */;
    wire [31:0] trace_redirect_pc_w /* verilator public_flat_rd */;
    assign trace_redirect_stage_w = m_redirect_r ?
        (m_redirect_trap_r ? 2'd0 : 2'd3) :
        e_redirect_w ? 2'd2 : d_redirect_w ? 2'd1 : 2'd0;
    assign trace_redirect_pc_w = m_redirect_r ? m_redirect_origin_r :
        e_redirect_r ? e_redirect_origin_w : d_redirect_origin_r;
    reg trace_trap_r;
    reg trace_trap_pending_r;
    reg [31:0] trace_cause_pending_r;
    reg [31:0] trace_cause_r;
    // A younger M fault is traced after its surviving older slot reaches W.
    // These registers drive trace only; architectural trap handling remains in M.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            trace_trap_r <= 0;
            trace_trap_pending_r <= 0;
        end else begin
            trace_trap_pending_r <= m_trap_w && (|m_commit_w);
            trace_trap_r <= (m_trap_w && m_commit_w == 0) || trace_trap_pending_r;
        end
    end
    always @(posedge clk_i) begin
        if (m_trap_w)
            trace_cause_pending_r <= m_trap_cause_w;
        trace_cause_r <= trace_trap_pending_r ? trace_cause_pending_r : m_trap_cause_w;
    end
    assign unused_mul_valid_w = mul_valid_w;
    assign unused_lane1_predicted_target_w = d_record_w[1][REC_PRED_TARGET_LSB +: 32];
    assign e_instr_w = e_record_r[0][REC_INSTR_LSB +: 32];
    assign d_record_w[0] = d_data_w[REC_BITS-1:0];
    assign d_record_w[1] = d_data_w[2*REC_BITS-1:REC_BITS];
    assign d_source_w[0] = d_operand_addr_w[4:0];
    assign d_source_w[1] = d_operand_addr_w[9:5];
    assign d_source_w[2] = d_operand_addr_w[14:10];
    assign d_source_w[3] = d_operand_addr_w[19:15];
    wire [119:0] e_shift_slot_w [0:1];
    wire [19:0] e_shift_result_w [0:1];
    genvar shift_result_group;
    generate
        for (shift_result_group = 0; shift_result_group < 4;
            shift_result_group = shift_result_group + 1) begin : g_shift_result
            // Each result FF bit feeds six banks in each of two instruction slots.
            (* keep = "true", syn_preserve = 1 *) reg [4:0] result0_copy_r;
            (* keep = "true", syn_preserve = 1 *) reg [4:0] result1_copy_r;
            assign e_shift_result_w[0][shift_result_group*5 +: 5] = result0_copy_r;
            assign e_shift_result_w[1][shift_result_group*5 +: 5] = result1_copy_r;
            always @(posedge clk_i) begin
                result0_copy_r <= e_alu_w[0][4:0];
                result1_copy_r <= e_alu_w[1][4:0];
            end
        end
    endgenerate
    genvar lane;
    genvar shift_bank;
    generate
        for (lane = 0; lane < 2; lane = lane + 1) begin : g_lane
            assign d_instr_w[lane] = d_record_w[lane][REC_INSTR_LSB +: 32];
            assign {d_jal_w[lane], d_slow_w[lane], d_dest_w[lane],
                d_serial_slot_w[lane], d_memory_w[lane], d_control_w[lane],
                d_csr_w[lane], d_mul_w[lane], d_load_w[lane], d_imm_w[lane],
                d_operation_w[lane], d_class_w[lane], d_pipe1_w[lane],
                d_illegal_w[lane], d_immediate_w[lane], d_write_w[lane],
                d_use2_w[lane], d_use1_w[lane], d_rd_w[lane], d_rs2_w[lane],
                d_rs1_w[lane]} = d_predecode_w[lane*70 +: 70];
            wire repair_lane_w;
            assign repair_lane_w = lane == 0 ? e_swap_r : !e_swap_r;
            wire [119:0] shift_amount_w;
            wire [119:0] shift_payload_w;
            assign e_shift_slot_w[lane] = shift_payload_w;
            for (shift_bank = 0; shift_bank < 24;
                shift_bank = shift_bank + 1) begin : g_shift_bank
                (* keep = "true", syn_preserve = 1 *) reg [4:0] amount_copy1_r;
                (* keep = "true", syn_preserve = 1 *) reg [1:0] select_copy_r;
                (* keep = "true", syn_preserve = 1 *) reg map_copy_r;
                always @(posedge clk_i or negedge rst_n_i) begin
                    if (!rst_n_i)
                        map_copy_r <= 0;
                    else if (d_issue_valid_w)
                        map_copy_r <= d_swap_w;
                end
                assign shift_amount_w[shift_bank*5 +: 5] = map_copy_r ?
                    e_shift_slot_w[1-lane][shift_bank*5 +: 5] :
                    e_shift_slot_w[lane][shift_bank*5 +: 5];
                assign shift_payload_w[shift_bank*5 +: 5] =
                    ({5{select_copy_r[0]}} & e_shift_result_w[0][(shift_bank/6)*5 +: 5]) |
                    ({5{select_copy_r[1]}} & e_shift_result_w[1][(shift_bank/6)*5 +: 5]) |
                    ({5{!(|select_copy_r)}} & amount_copy1_r);
                always @(posedge clk_i) begin
                    if (e_data_load_copy_w[lane]) begin
                        select_copy_r <= d_immediate_w[lane] ? 2'b0 :
                            {d_bypass_select_w[lane*2+1][2],
                            d_bypass_select_w[lane*2+1][1] &&
                            !(e_early_r && e_load_r[0])};
                    end else begin
                        select_copy_r <= 0;
                    end
                    amount_copy1_r <= e_alu_input_w[lane][4:0];
                    if (e_repair_w && e_repair_mask_r[repair_lane_w*2+1] &&
                        !e_immediate_r[repair_lane_w]) begin
                        select_copy_r <= 0;
                    end
                end
            end
            edrv32_cpu_alu u_alu (
                .operand_a_i(e_operand_a_w[lane]),
                .operand_b_i(e_alu_operand_b_w[lane]),
                .shift_amount_i(shift_amount_w),
                .operation_select_i(e_operation_select_r[lane]),
                .other_result_i(e_nonalu_result_r[lane] |
                    ({32{e_div_result_r[lane]}} & div_result_w)),
                .result_o(e_alu_w[lane])
            );
            assign w_result_w[lane] = w_result_r[lane];
            assign w2_result_w[lane] = lane == 0 && w2_class_r[lane] == C_MUL ?
                mul_result_w : w2_result_r[lane];
        end
    endgenerate
    // cpu-spec 4.9: choose the forwarding source before the data path.
    // Mapping and same-group WAW priority affect only these one-hot enables.
    genvar forward_operand;
    genvar forward_copy;
    generate
        for (forward_operand = 0; forward_operand < 4;
            forward_operand = forward_operand + 1) begin : g_forward
            wire [6:0] select_w;
            assign select_w = d_bypass_select_w[forward_operand];
            wire physical_lane_w;
            assign physical_lane_w = forward_operand/2 != 0 ? !e_swap_r : e_swap_r;
            wire [1:0] alu_select_w;
            assign alu_select_w = {select_w[2], select_w[1] && !early_w};
            for (forward_copy = 0; forward_copy < 8;
                forward_copy = forward_copy + 1) begin : g_select_copy
                (* keep = "true", syn_preserve = 1 *) reg [1:0] select_copy_r;
                assign e_alu_forward_w[forward_operand][forward_copy*2 +: 2] = select_copy_r;
                always @(posedge clk_i) begin
                    if (e_data_load_copy_w[forward_operand/2])
                        select_copy_r <= alu_select_w;
                    else
                        select_copy_r <= 0;
                    if (e_repair_w &&
                        e_repair_mask_r[physical_lane_w*2 + forward_operand%2])
                        select_copy_r <= 0;
                end
            end
            wire early_w;
            wire memory_w;
            wire capture_w;
            wire hold_w;
            wire repair_w;
            wire [1:0] repair_select_w;
            assign repair_w = e_repair_w &&
                e_repair_mask_r[physical_lane_w*2 + forward_operand%2];
            assign capture_w = e_data_load_copy_w[forward_operand/2] && !repair_w;
            assign hold_w = !e_data_load_copy_w[forward_operand/2] && !repair_w;
            assign repair_select_w = dc_resp_way_hit_i & {2{repair_w}};
            wire [9:0] data_select_w;
            wire [31:0] data_w [1:9];
            assign early_w = e_early_r && e_load_r[0];
            assign memory_w = m_load_r;
            // Capture program slots independently; the registered E map chooses their lanes.
            assign data_select_w = {10{capture_w}} & {
                select_w[3] && memory_w && dc_resp_way_hit_i[1],
                select_w[3] && memory_w && dc_resp_way_hit_i[0],
                select_w[1] && early_w && dc_early_way_hit_i[1],
                select_w[1] && early_w && dc_early_way_hit_i[0],
                select_w[3] && m_csr_r,
                select_w[6], select_w[5], select_w[4],
                select_w[3] && !memory_w && !m_csr_r, select_w[0]};
            assign data_w[1] = m_result_r[0];
            assign data_w[2] = m_result_w[1];
            assign data_w[3] = w_result_w[0];
            assign data_w[4] = w_result_w[1];
            assign data_w[5] = csr_read_w;
            assign data_w[6] = e_early_result_w[0];
            assign data_w[7] = e_early_result_w[1];
            assign data_w[8] = m_load_result_w[0];
            assign data_w[9] = m_load_result_w[1];
            wire [31:0] selected_data_w;
            wire [31:0] held_data_w;
            wire [31:0] held_branch_w;
            assign held_data_w = forward_operand%2 == 0 ?
                e_operand_a_w[physical_lane_w] : e_operand_b_w[physical_lane_w];
            assign held_branch_w = forward_operand%2 == 0 ?
                e_branch_a_w[physical_lane_w] : e_branch_b_w[physical_lane_w];
            assign selected_data_w =
                ({32{data_select_w[0]}} & d_register_w[forward_operand]) |
                ({32{data_select_w[1]}} & data_w[1]) |
                ({32{data_select_w[2]}} & data_w[2]) |
                ({32{data_select_w[3]}} & data_w[3]) |
                ({32{data_select_w[4]}} & data_w[4]) |
                ({32{data_select_w[5]}} & data_w[5]) |
                ({32{data_select_w[6]}} & data_w[6]) |
                ({32{data_select_w[7]}} & data_w[7]) |
                ({32{data_select_w[8] || repair_select_w[0]}} & data_w[8]) |
                ({32{data_select_w[9] || repair_select_w[1]}} & data_w[9]);
            assign e_forward_w[forward_operand] = selected_data_w |
                ({32{hold_w}} & held_data_w);
            assign e_branch_forward_w[forward_operand] = selected_data_w |
                ({32{hold_w}} & held_branch_w);
            if (forward_operand%2 == 1) begin : g_alu_input
                wire [9:0] select_alu_w;
                assign select_alu_w[7:0] = data_select_w[7:0] &
                    {8{!d_immediate_w[forward_operand/2]}};
                assign select_alu_w[9:8] = (data_select_w[9:8] &
                    {2{!d_immediate_w[forward_operand/2]}}) | repair_select_w;
                assign e_alu_input_w[forward_operand/2] =
                    ({32{select_alu_w[0]}} & d_register_w[forward_operand]) |
                    ({32{select_alu_w[1]}} & data_w[1]) |
                    ({32{select_alu_w[2]}} & data_w[2]) |
                    ({32{select_alu_w[3]}} & data_w[3]) |
                    ({32{select_alu_w[4]}} & data_w[4]) |
                    ({32{select_alu_w[5]}} & data_w[5]) |
                    ({32{select_alu_w[6]}} & data_w[6]) |
                    ({32{select_alu_w[7]}} & data_w[7]) |
                    ({32{select_alu_w[8]}} & data_w[8]) |
                    ({32{select_alu_w[9]}} & data_w[9]) |
                    ({32{capture_w && d_immediate_w[forward_operand/2]}} &
                        d_imm_w[forward_operand/2]) |
                    ({32{hold_w}} & e_alu_operand_b_w[physical_lane_w]);
            end
        end
    endgenerate
    genvar operand_lane;
    genvar operand_slice;
    generate
        for (operand_lane = 0; operand_lane < 2;
            operand_lane = operand_lane + 1) begin : g_registered_forward
            always @(posedge clk_i) begin
                // A stalled consumer snapshots its selected value before these
                // producer copies are overwritten by the held E computation.
                e_forward_result_r[operand_lane] <= e_alu_w[operand_lane];
                e_branch_result_copy_r[operand_lane] <= e_alu_w[operand_lane];
            end
            for (operand_slice = 0; operand_slice < 4;
                operand_slice = operand_slice + 1) begin : g_slice
                (* keep = "true", syn_preserve = 1 *) reg [4:0] map_copy_r;
                wire slot_a_w;
                wire slot_b_w;
                wire branch_slot_a_w;
                wire branch_slot_b_w;
                wire alu_slot_b_w;
                wire [1:0] select_a_w;
                wire [1:0] select_b_w;
                wire [1:0] branch_select_a_w;
                wire [1:0] branch_select_b_w;
                wire [7:0] result_a_w;
                wire [7:0] result_b_w;
                wire [7:0] branch_result_a_w;
                wire [7:0] branch_result_b_w;
                always @(posedge clk_i or negedge rst_n_i) begin
                    if (!rst_n_i)
                        map_copy_r <= 0;
                    else if (d_issue_valid_w)
                        map_copy_r <= {5{d_swap_w}};
                end
                assign slot_a_w = operand_lane[0] ^ map_copy_r[0];
                assign slot_b_w = operand_lane[0] ^ map_copy_r[1];
                assign branch_slot_a_w = operand_lane[0] ^ map_copy_r[2];
                assign branch_slot_b_w = operand_lane[0] ^ map_copy_r[3];
                assign alu_slot_b_w = operand_lane[0] ^ map_copy_r[4];
                assign select_a_w = e_alu_forward_w[slot_a_w*2][operand_slice*2 +: 2];
                assign select_b_w = e_alu_forward_w[slot_b_w*2+1][operand_slice*2 +: 2];
                assign branch_select_a_w =
                    e_alu_forward_w[branch_slot_a_w*2][8+operand_slice*2 +: 2];
                assign branch_select_b_w =
                    e_alu_forward_w[branch_slot_b_w*2+1][8+operand_slice*2 +: 2];
                assign result_a_w =
                    ({8{select_a_w[0]}} & e_forward_result_r[0][operand_slice*8 +: 8]) |
                    ({8{select_a_w[1]}} & e_forward_result_r[1][operand_slice*8 +: 8]);
                assign result_b_w =
                    ({8{select_b_w[0]}} & e_forward_result_r[0][operand_slice*8 +: 8]) |
                    ({8{select_b_w[1]}} & e_forward_result_r[1][operand_slice*8 +: 8]);
                assign branch_result_a_w =
                    ({8{branch_select_a_w[0]}} &
                        e_branch_result_copy_r[0][operand_slice*8 +: 8]) |
                    ({8{branch_select_a_w[1]}} &
                        e_branch_result_copy_r[1][operand_slice*8 +: 8]);
                assign branch_result_b_w =
                    ({8{branch_select_b_w[0]}} &
                        e_branch_result_copy_r[0][operand_slice*8 +: 8]) |
                    ({8{branch_select_b_w[1]}} &
                        e_branch_result_copy_r[1][operand_slice*8 +: 8]);
                assign e_operand_a_w[operand_lane][operand_slice*8 +: 8] = result_a_w |
                    ({8{!(|select_a_w)}} & e_operand_a_r[slot_a_w][operand_slice*8 +: 8]);
                assign e_operand_b_w[operand_lane][operand_slice*8 +: 8] = result_b_w |
                    ({8{!(|select_b_w)}} & e_operand_b_r[slot_b_w][operand_slice*8 +: 8]);
                assign e_branch_a_w[operand_lane][operand_slice*8 +: 8] = branch_result_a_w |
                    ({8{!(|branch_select_a_w)}} &
                        e_branch_a_r[branch_slot_a_w][operand_slice*8 +: 8]);
                assign e_branch_b_w[operand_lane][operand_slice*8 +: 8] = branch_result_b_w |
                    ({8{!(|branch_select_b_w)}} &
                        e_branch_b_r[branch_slot_b_w][operand_slice*8 +: 8]);
                assign e_alu_operand_b_w[operand_lane][operand_slice*8 +: 8] =
                    ({8{!e_immediate_r[operand_lane]}} & result_b_w) |
                    ({8{e_immediate_r[operand_lane] || !(|select_b_w)}} &
                        e_alu_operand_b_copy1_r[alu_slot_b_w][operand_slice*8 +: 8]);
            end
        end
    endgenerate
    edrv32_cpu_frontend u_frontend (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .redirect_valid_i(frontend_redirect_w),
        .redirect_valid_copy_i(frontend_redirect_copy_w),
        .redirect_pc_i(frontend_redirect_pc_w),
        .redirect_ras_i(frontend_redirect_ras_w),
        .redirect_push_i(!m_redirect_r && (e_redirect_r ?
            e_redirect_push_w : d_redirect_push_r)),
        .redirect_pop_i(!m_redirect_r &&
            e_redirect_r && e_redirect_pop_w),
        .redirect_return_pc_i(e_redirect_r ? e_redirect_link_w : d_redirect_link_r),
        .d_redirect_valid_i(frontend_d_redirect_w),
        .d_redirect_pc_i(d_redirect_pc_r),
        .d_redirect_slot_i(d_redirect_slot_r),
        .d_redirect_ras_i(d_redirect_ras_r),
        .d_redirect_push_i(d_redirect_push_r),
        .d_redirect_pop_i(1'b0),
        .d_redirect_return_pc_i(d_redirect_link_r),
        .halt_i(sleep_r || div_wait_front_r || m_wait_r),
        .update_valid_i(update_valid_r),
        .update_clear_i(update_clear_r),
        .update_clear_index_i(update_clear_index_w),
        .update_pc_i(update_pc_r),
        .update_target_i(update_target_r),
        .update_type_i(update_type_r),
        .update_taken_i(update_taken_r),
        .update_index_i(update_index_r),
        .update_tournament_i(update_tournament_r),
        .decode_pop_count_i(d_issue_w),
        .decode_data_o(d_data_w),
        .decode_predecode_o(d_predecode_w),
        .decode_index_hi_o(d_index_hi_w),
        .decode_tournament_o(d_tournament_w),
        .decode_operand_addr_o(d_operand_addr_w),
        .decode_valid_count_o(d_count_w),
        .ib_count_o(ib_count_w),
        .ic_req_valid_o(ic_req_valid_o),
        .ic_req_addr_o(ic_req_addr_o),
        .ic_req_ready_i(ic_req_ready_i),
        .ic_resp_valid_i(ic_resp_valid_i),
        .ic_resp_valid_copy_i(ic_resp_valid_copy_i),
        .ic_resp_data_i(ic_resp_data_i),
        .ic_resp_predecode_i(ic_resp_predecode_i),
        .ic_resp_err_i(ic_resp_err_i),
        .ic_kill_o(ic_kill_o),
        .invalidate_i(m_valid_r[0] && m_class_r[0] == C_FENCE_I && m_fence_phase_r),
        .invalidate_done_o(unused_invalidate_done_w),
        .ic_inv_o(ic_inv_o),
        .ic_inv_done_i(ic_inv_done_i),
        .f1_valid_o(f1_valid_w),
        .f2_valid_o(f2_valid_w),
        .fetch_wait_o(fetch_wait_w)
    );
    edrv32_cpu_regfile u_regfile (
        .clk_i(clk_i),
        .read_addr0_i({d_operand_addr_w[60 +: 5], d_operand_addr_w[40 +: 5],
            d_operand_addr_w[20 +: 5], d_operand_addr_w[0 +: 5]}),
        .read_data0_o(d_register_w[0]),
        .read_addr1_i({d_operand_addr_w[65 +: 5], d_operand_addr_w[45 +: 5],
            d_operand_addr_w[25 +: 5], d_operand_addr_w[5 +: 5]}),
        .read_data1_o(d_register_w[1]),
        .read_addr2_i({d_operand_addr_w[70 +: 5], d_operand_addr_w[50 +: 5],
            d_operand_addr_w[30 +: 5], d_operand_addr_w[10 +: 5]}),
        .read_data2_o(d_register_w[2]),
        .read_addr3_i({d_operand_addr_w[75 +: 5], d_operand_addr_w[55 +: 5],
            d_operand_addr_w[35 +: 5], d_operand_addr_w[15 +: 5]}),
        .read_data3_o(d_register_w[3]),
        .write_valid0_i(w2_valid_r[0] && w2_write_r[0]),
        .write_addr0_i(w2_rd_r[0]),
        .write_data0_i(w2_result_w[0]),
        .write_valid1_i(w2_valid_r[1] && w2_write_r[1] &&
            !(w2_swap_r && w2_valid_r[0] && w2_write_r[0] && w2_rd_r[0] == w2_rd_r[1])),
        .write_addr1_i(w2_rd_r[1]),
        .write_data1_i(w2_result_w[1])
    );
    edrv32_cpu_csr u_csr (
        .clk_i(clk_i),
        .rst_n_i(rst_sys_csr_n_i),
        .rst_sys_counter_n_i(rst_sys_counter_n_i),
        .access_valid_i(csr_m_access_w),
        .select_i(m_csr_select_r),
        .write_i(csr_write_w),
        // CSR is ready immediately in M, with the same exception/interrupt priority.
        .commit_i(m_system_commit_w && csr_m_access_w),
        // A CSR is alone in M; its cancellation never needs a cache response.
        .write_cancel_i(!m_system_commit_w),
        .command_i(csr_command_w),
        .write_data_i(csr_operand_w),
        .read_data_o(csr_read_w),
        .illegal_o(unused_csr_illegal_w),
        .decode_valid_i(csr_d_access_w),
        .decode_addr_i(d_instr_w[0][31:20]),
        .decode_write_i(d_instr_w[0][13:12] == 1 || d_instr_w[0][19:15] != 0),
        .decode_illegal_o(csr_decode_illegal_w),
        .decode_select_o(d_csr_select_w),
        .retire_count_i(csr_retire_count_w),
        .event_count_i(event_count_w),
        .trap_i(m_trap_w),
        .trap_pc_i(m_trap_pc_w),
        .trap_cause_i(m_trap_cause_w),
        .trap_value_i(m_trap_value_w),
        .mret_i(m_mret_w),
        .mstatus_o({unused_status_high_w, csr_global_mie_w, unused_status_low_w}),
        .mie_o({unused_mie_high_w, csr_meie_w, unused_mie_middle0_w,
            csr_mtie_w, unused_mie_middle1_w, csr_msie_w, unused_mie_low_w}),
        .mtvec_o(csr_mtvec_w),
        .mepc_o(csr_mepc_w),
        .irq_meip_i(irq_meip_i),
        .irq_msip_i(irq_msip_i),
        .irq_mtip_i(irq_mtip_i),
        .mtime_i(mtime_i)
    );
    edrv32_cpu_mul u_mul (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .enable_i(1'b1),
        .valid_i(e_advance_w && e_survive_w[0] && e_class_r[0] == C_MUL),
        .operand_a_i(e_operand_a_w[0]),
        .operand_b_i(e_operand_b_w[0]),
        .operation_i(e_instr_w[13:12]),
        .valid_o(mul_valid_w),
        .result_o(mul_result_w)
    );
    edrv32_cpu_div u_div (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .start_i(div_start_w),
        .start_payload_i(div_start_copy_w),
        .operand_a_i(e_operand_a_w[0]),
        .operand_b_i(e_operand_b_w[0]),
        .operation_i(e_instr_w[13:12]),
        .busy_o(div_busy_w),
        .valid_o(div_valid_w),
        .result_o(div_result_w)
    );
    // Closest producer wins, including the younger lane on same-group WAW.
    // Match physical lanes in parallel, then apply age and stage priority once.
    // The data mux consumes this one-hot result without an encode/decode round trip.
    genvar bypass_operand;
    generate
        for (bypass_operand = 0; bypass_operand < 4;
            bypass_operand = bypass_operand + 1) begin : g_bypass
            wire [1:0] e_match_w;
            wire [1:0] m_match_w;
            wire [1:0] w_match_w;
            wire [1:0] e_select_w;
            wire [1:0] m_select_w;
            wire [1:0] w_select_w;
            wire e_any_w;
            wire m_any_w;
            wire w_any_w;
            wire load_wait_w;
            wire mul_wait_w;
            wire csr_wait_w;
            // Prepare W's destination validity and WAW winner with its payload.
            // Each operand owns a local copy, keeping W-valid out of the mux chain.
            (* keep = "true", syn_preserve = 1 *) reg [1:0] w_forward_valid_copy1_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i)
                    w_forward_valid_copy1_r <= 0;
                else begin
                    w_forward_valid_copy1_r[0] <= m_commit_w[0] && m_dest_r[0] &&
                        (!(m_commit_w[1] && m_dest_r[1]) ||
                        m_rd_r[0] != m_rd_r[1] || m_swap_r);
                    w_forward_valid_copy1_r[1] <= m_commit_w[1] && m_dest_r[1] &&
                        (!(m_commit_w[0] && m_dest_r[0]) ||
                        m_rd_r[0] != m_rd_r[1] || !m_swap_r);
                end
            end
            assign e_match_w[0] = e_valid_r[0] && e_dest_r[0] &&
                e_rd_r[0] == d_source_w[bypass_operand];
            assign e_match_w[1] = e_valid_r[1] && e_dest_r[1] &&
                e_rd_r[1] == d_source_w[bypass_operand];
            assign m_match_w[0] = m_valid_r[0] && m_dest_r[0] &&
                m_rd_r[0] == d_source_w[bypass_operand];
            assign m_match_w[1] = m_valid_r[1] && m_dest_r[1] &&
                m_rd_r[1] == d_source_w[bypass_operand];
            assign w_match_w[0] = w_forward_valid_copy1_r[0] &&
                w_rd_r[0] == d_source_w[bypass_operand];
            assign w_match_w[1] = w_forward_valid_copy1_r[1] &&
                w_rd_r[1] == d_source_w[bypass_operand];
            assign e_any_w = |e_match_w;
            assign m_any_w = |m_match_w;
            assign w_any_w = |w_match_w;
            assign e_select_w[0] = e_match_w[0] && (!e_match_w[1] || e_swap_r);
            assign e_select_w[1] = e_match_w[1] && (!e_match_w[0] || !e_swap_r);
            assign m_select_w[0] = !e_any_w && m_match_w[0] &&
                (!m_match_w[1] || m_swap_r);
            assign m_select_w[1] = !e_any_w && m_match_w[1] &&
                (!m_match_w[0] || !m_swap_r);
            assign w_select_w[0] = !e_any_w && !m_any_w && w_match_w[0];
            assign w_select_w[1] = !e_any_w && !m_any_w && w_match_w[1];
            assign d_bypass_select_w[bypass_operand] =
                {w_select_w, m_select_w, e_select_w, !e_any_w && !m_any_w && !w_any_w};
            // Binary codes remain only at the documented trace interface.
            assign d_bypass_w[bypass_operand] =
                ({3{e_select_w[0]}} & 3'd1) | ({3{e_select_w[1]}} & 3'd2) |
                ({3{m_select_w[0]}} & 3'd3) | ({3{m_select_w[1]}} & 3'd4) |
                ({3{w_select_w[0]}} & 3'd5) | ({3{w_select_w[1]}} & 3'd6);
            assign load_wait_w = !e_early_r &&
                ((e_select_w[0] && e_load_r[0]) || (e_select_w[1] && e_load_r[1]));
            assign mul_wait_w = (e_select_w[0] && e_mul_r[0]) ||
                (e_select_w[1] && e_mul_r[1]) || (m_select_w[0] && m_mul_r[0]) ||
                (m_select_w[1] && m_mul_r[1]) || (w_select_w[0] && w_mul_r[0]) ||
                (w_select_w[1] && w_mul_r[1]);
            assign csr_wait_w = (e_select_w[0] && e_csr_r[0]) ||
                (e_select_w[1] && e_csr_r[1]);
            assign d_hazard_w[bypass_operand] = load_wait_w || mul_wait_w || csr_wait_w;
            assign d_wait_kind_w[bypass_operand] = load_wait_w ? 3'd1 :
                mul_wait_w ? 3'd2 : csr_wait_w ? 3'd3 : 3'd0;
        end
    endgenerate
    assign d_raw_w = d_dest_w[0] &&
        ((d_use1_w[1] && d_rs1_w[1] == d_rd_w[0]) ||
        (d_use2_w[1] && d_rs2_w[1] == d_rd_w[0]));
    assign d_pair_type_w = (|d_pipe1_w) && !(d_control_w[0] && d_control_w[1]);
    assign d_serial_w = d_serial_slot_w[0] || d_serial_slot_w[1];
    assign d_pair_w = d_count_w >= 2 && !d_raw_w && !d_serial_w && d_pair_type_w &&
        !d_illegal_w[1] && !d_record_w[1][REC_FETCH_ERR] && !d_record_w[1][REC_ILLEGAL] &&
        !(d_use1_w[1] && d_hazard_w[2]) && !(d_use2_w[1] && d_hazard_w[3]);
    // Mapping is prepared before the late M/D-cache issue handshake.
    // Only a fresh slot-0 redirect suppresses pairing; its retained head may later pair
    // with an instruction fetched from the corrected target while E is blocked.
    assign d_jal_redirect0_w = !d_redirected_r && d_jal_w[0] &&
        !d_record_w[0][REC_PRED_HIT] && !d_record_w[0][REC_FETCH_ERR] &&
        !d_record_w[0][REC_ILLEGAL] && !d_illegal_w[0];
    // The registered redirect also forces a retained slot-0 JAL to issue alone.
    // Keep its mapping in slot 0 on that cycle, even if the younger IB entry pairs.
    assign d_swap_w = d_pair_w && !d_pipe1_w[1] && !d_jal_redirect0_w &&
        !(d_redirect_r && !d_redirect_issued_r && !d_redirect_slot_w);
    assign d_csr_wait_w = d_csr_w[0] &&
        (e_valid_r != 0 || m_valid_r != 0);
    // C-F1 path 3: test E ownership before applying the shared M backpressure.
    assign d_available_w = !m_wait_w && !m_block_early_w &&
        !m_redirect_r && !e_redirect_r && !sleep_r &&
        !(d_redirect_r && d_redirect_issued_r) && !e_repair_pending_r &&
        (e_valid_r == 0 || (!div_wait_w &&
        (!e_memory_w || e_exception_r || e_misaligned_w || dc_req_ready_i)));
    assign d_head_single_w = d_jal_redirect0_w ||
        (d_redirect_r && !d_redirect_issued_r && !d_redirect_slot_w);
    assign d_single_w = !d_pair_w || d_head_single_w;
    assign d_issue_valid_w = d_count_w != 0 && d_available_w && !d_csr_wait_w &&
        !(d_use1_w[0] && d_hazard_w[0]) && !(d_use2_w[0] && d_hazard_w[1]);
    assign d_issue_w = {d_issue_valid_w && !d_single_w, d_issue_valid_w && d_single_w};
    // Classify before the late availability handshake; it only gates the final event.
    always @(*) begin
        d_pair_reason_pre_w = 0;
        if (d_count_w < 2)
            d_pair_reason_pre_w = 4;
        else if (d_raw_w)
            d_pair_reason_pre_w = 1;
        else if (d_serial_w || d_illegal_w[1] ||
            d_record_w[1][REC_FETCH_ERR] || d_record_w[1][REC_ILLEGAL] ||
            (d_use1_w[1] && d_hazard_w[2]) || (d_use2_w[1] && d_hazard_w[3]))
            d_pair_reason_pre_w = 2;
        else if (!d_pair_type_w)
            d_pair_reason_pre_w = 3;
        if (d_head_single_w)
            d_pair_reason_pre_w = 0;
    end
    always @(*) begin
        d_pair_reason_w = 0;
        if (d_issue_valid_w)
            d_pair_reason_w = d_pair_reason_pre_w;
    end
    assign d_slot_target_w[0] = d_record_w[0][REC_PC_LSB +: 32] + d_imm_w[0];
    assign d_slot_target_w[1] = d_record_w[1][REC_PC_LSB +: 32] + d_imm_w[1];
    assign d_target_w = d_slot_target_w[d_redirect_slot_w];
    assign d_redirect_slot_w = !d_jal_w[0];
    // JALR clears sum bit 0: either preimage of the aligned prediction is a match.
    // These D computations use prediction/immediate only, before operand forwarding.
    assign d_jalr_expected_even_w =
        {d_record_w[d_map_w[0]][REC_PRED_TARGET_LSB + 1 +: 31], 1'b0} -
        d_imm_w[d_map_w[0]];
    assign d_jalr_expected_odd_w =
        {d_record_w[d_map_w[0]][REC_PRED_TARGET_LSB + 1 +: 31], 1'b1} -
        d_imm_w[d_map_w[0]];
    // cpu-spec 4.4: a stalled JAL redirects once, then remains at the IB head.
    assign d_capture_w = d_count_w != 0 && !d_redirected_r &&
        !m_block_early_w && !m_redirect_r && !e_redirect_r &&
        !d_redirect_r && !sleep_r &&
        (!d_redirect_slot_w || (d_pair_w &&
        !(d_use1_w[0] && d_hazard_w[0]) && !(d_use2_w[0] && d_hazard_w[1]))) &&
        d_jal_w[d_redirect_slot_w] &&
        !d_record_w[d_redirect_slot_w][REC_PRED_HIT] &&
        !d_record_w[d_redirect_slot_w][REC_FETCH_ERR] &&
        !d_record_w[d_redirect_slot_w][REC_ILLEGAL] && !d_illegal_w[d_redirect_slot_w];
    genvar branch_lane;
    generate
        for (branch_lane = 0; branch_lane < 2;
            branch_lane = branch_lane + 1) begin : g_branch
            wire [31:0] instr_w;
            wire [31:0] address_w;
            wire [19:0] unused_instr_w;
            assign unused_instr_w = {instr_w[31:20], instr_w[6:0], address_w[0]};
            assign instr_w = e_record_r[branch_lane][REC_INSTR_LSB +: 32];
            assign address_w = e_operand_a_w[branch_lane] + e_imm_r[branch_lane];
            edrv32_cpu_branch u_branch (
                .operand_a_i(e_branch_a_w[branch_lane]),
                .operand_b_i(e_branch_b_w[branch_lane]),
                .condition_i(instr_w[14:12]),
                .taken_o(e_lane_branch_taken_w[branch_lane])
            );
            assign e_lane_next_pc_w[branch_lane] =
                e_record_r[branch_lane][REC_PC_LSB +: 32] + 32'd4;
            assign e_lane_target_w[branch_lane] = e_class_r[branch_lane] == C_JALR ?
                {address_w[31:1], 1'b0} : e_lane_pc_target_w[branch_lane];
            assign e_lane_control_w[branch_lane] = e_control_r[branch_lane];
            assign e_lane_taken_w[branch_lane] = e_class_r[branch_lane] == C_BRANCH ?
                e_lane_branch_taken_w[branch_lane] :
                e_class_r[branch_lane] == C_JAL || e_class_r[branch_lane] == C_JALR;
            assign e_lane_call_w[branch_lane] =
                (e_class_r[branch_lane] == C_JAL || e_class_r[branch_lane] == C_JALR) &&
                (instr_w[11:7] == 1 || instr_w[11:7] == 5);
            assign e_lane_return_w[branch_lane] = e_class_r[branch_lane] == C_JALR &&
                (instr_w[19:15] == 1 || instr_w[19:15] == 5) && !e_lane_call_w[branch_lane];
            assign e_lane_type_w[branch_lane] = e_lane_call_w[branch_lane] ? 3'd3 :
                e_lane_return_w[branch_lane] ? 3'd4 : e_class_r[branch_lane] == C_JAL ?
                3'd1 : e_class_r[branch_lane] == C_JALR ? 3'd2 : 3'd0;
            assign e_lane_jump_fault_w[branch_lane] = e_lane_taken_w[branch_lane] &&
                e_lane_target_w[branch_lane][1];
            assign e_lane_redirect_needed_w[branch_lane] =
                !e_lane_exception_w[branch_lane] &&
                !e_lane_jump_fault_w[branch_lane] &&
                ((e_lane_taken_w[branch_lane] !=
                e_record_r[branch_lane][REC_PRED_TAKEN]) ||
                (e_lane_taken_w[branch_lane] &&
                e_record_r[branch_lane][REC_PRED_TAKEN] && !e_lane_target_match_w[branch_lane]));
        end
    endgenerate
    assign e_next_pc_w = e_lane_next_pc_w[0];
    wire [31:0] unused_next_pc_w;
    assign unused_next_pc_w = e_next_pc_w;
    assign e_address_w = e_operand_a_w[0] + e_imm_r[0];
    assign e_control_w = e_lane_control_w[0];
    assign e_jump_misaligned_w = e_lane_jump_fault_w[0];
    assign e_target_match_w = e_class_r[0] == C_JALR ?
        (!e_record_r[0][REC_PRED_TARGET_LSB] &&
        (e_operand_a_w[0] == e_jalr_expected_even_r ||
        e_operand_a_w[0] == e_jalr_expected_odd_r)) : e_pc_target_match_r;
    // A younger M fault can wait for its older load; E is already on the discarded path.
    assign e_resolve_ready_w = (|e_valid_r) && !m_block_early_w &&
        !m_mret_w && !m_fence_i_done_w && !m_wfi_w && !e_flush_w && !e_repair_pending_r &&
        (!div_wait_w || e_old_control_unresolved_w);
    assign e_resolve_w = e_resolve_ready_w && !e_resolved_r;
    assign e_redirect0_w = e_resolve_w && e_valid_r[0] && e_lane_redirect_needed_w[0] &&
        !(e_swap_r && (e_older_fault_w ||
        (e_valid_r[1] && e_lane_redirect_needed_w[1])));
    assign e_redirect1_w = e_resolve_w && e_valid_r[1] && e_lane_redirect_needed_w[1] &&
        !(!e_swap_r && (e_older_fault_w ||
        (e_valid_r[0] && e_lane_redirect_needed_w[0])));
    assign e_capture_w = e_redirect0_w || e_redirect1_w;
    assign e_capture_reason_w =
        (e_valid_r[0] && e_lane_redirect_needed_w[0] &&
        !(e_swap_r && (e_older_fault_w || (e_valid_r[1] && e_lane_redirect_needed_w[1])))) ||
        (e_valid_r[1] && e_lane_redirect_needed_w[1] &&
        !(!e_swap_r && (e_older_fault_w || (e_valid_r[0] && e_lane_redirect_needed_w[0]))));
    assign e_redirect_w = e_redirect_r;
    assign d_redirect_w = d_redirect_r;
    assign e_flush_w = (e_redirect_r && e_redirect_advanced_r) || m_redirect_r;
    assign m_kill_all_w = m_redirect_r && !m_redirect_trap_r;
    assign e_memory_w = e_survive_w[0] && e_memory_r;
    assign e_misaligned_w = (e_instr_w[13:12] == 1 && e_address_w[0]) ||
        (e_instr_w[13:12] == 2 && e_address_w[1:0] != 0);
    // Resolve an older control instruction before starting its younger divide.
    // cpu-spec 4.4/4.9: this cycle's comparison only enters result registers.
    assign e_old_control_unresolved_w = e_swap_r && e_valid_r[1] &&
        e_control_r[1] && !e_resolved_r;
    // A swapped divide can only be canceled by its older pipe-1 slot.
    // Specialize that fault instead of routing pipe-0 load alignment through start.
    assign e_div_cancel_w = e_swap_r && e_valid_r[1] &&
        (e_exception1_r || e_jump_fault_r[1] ||
        (e_redirect_r && !e_redirect_advanced_r && e_redirect_old_r));
    // Each divider payload slice owns its E-class copy and local start gate.
    genvar div_start_group;
    generate
        for (div_start_group = 0; div_start_group < 8;
            div_start_group = div_start_group + 1) begin : g_div_start
            (* keep = "true", syn_preserve = 1 *) reg e_div_copy1_r;
            always @(posedge clk_i) begin
                if (e_operand_load_w)
                    e_div_copy1_r <= d_class_w[d_map_w[0]] == C_DIV;
            end
            assign div_start_copy_w[div_start_group] = e_valid_r[0] && !e_div_cancel_w &&
                e_div_copy1_r && !div_started_r && !e_old_control_unresolved_w &&
                m_valid_r == 0 && w_valid_r == 0 && !e_repair_pending_r;
        end
    endgenerate
    (* keep = "true", syn_preserve = 1 *) reg e_div_valid_r;
    always @(posedge clk_i) begin
        if (e_operand_load_w)
            e_div_valid_r <= d_class_w[d_map_w[0]] == C_DIV;
    end
    assign div_start_w = e_valid_r[0] && !e_div_cancel_w && e_div_valid_r &&
        !div_started_r && !e_old_control_unresolved_w &&
        m_valid_r == 0 && w_valid_r == 0 && !e_repair_pending_r;
    assign div_wait_w = e_valid_r[0] && !e_div_cancel_w &&
        e_class_r[0] == C_DIV && !(div_done_r || div_valid_w);
    assign e_advance_w = (|e_valid_r) && !m_wait_w && !m_block_early_w && !e_flush_w &&
                    !e_repair_pending_r && !div_wait_w &&
        (!e_memory_w || e_exception_r || e_misaligned_w || dc_req_ready_i);
    // C-F1 path 3: M's memory-wait class is prepared in E. Apply the two
    // late D-cache handshakes directly to the operand load, before valid issue.
    // Redirects may replace invalid payload, while any live stalled E holds it.
    assign m_wait_other_w = m_valid_r[0] && !m_exception_r &&
        ((m_class_r[0] == C_FENCE && !dc_fence_done_i) ||
        (m_class_r[0] == C_FENCE_I && !(m_fence_phase_r && ic_inv_done_i)));
    // Prepare early hold reasons in parallel; the late hit only releases one mux.
    assign e_payload_block_w = e_repair_pending_r || div_wait_w || m_wait_other_w ||
        (e_memory_w && !e_exception_r && !e_misaligned_w && !dc_req_ready_i);
    // Operand data may conservatively hold when an E memory exception bypasses
    // request-ready: M will discard every younger incoming instruction. Metadata
    // retains the exact advance rule, while alignment never enters the data ring.
    assign e_data_payload_block_w = e_repair_pending_r || div_wait_w || m_wait_other_w ||
        (e_valid_r[0] && e_memory_r && !dc_req_ready_i);
    assign e_payload_hold_w = (|e_valid_r) && e_payload_block_w;
    assign e_payload_wait_dc_w = (|e_valid_r) && m_valid_r[0] && m_wait_dc_r;
    assign e_operand_load_w = !e_payload_hold_w && (!e_payload_wait_dc_w || dc_resp_valid_i);
    // spec 3.3: valid is independent of ready; acceptance advances E into M.
    assign dc_req_valid_o = (|e_valid_r) && !m_wait_w && !m_block_early_w &&
        !e_flush_w && !e_repair_pending_r && !div_wait_w &&
        e_memory_w && !e_exception_r && !e_misaligned_w;
    assign dc_req_early_o = e_early_r;
    assign dc_req_addr_o = e_address_w;
    assign dc_req_store_o = e_class_r[0] == C_STORE;
    assign dc_req_size_o = e_instr_w[13:12];
    assign dc_store_data_o = m_store_r;
    assign m_memory_w = m_valid_r[0] && !m_squash_w[0] && m_memory_r;
    assign m_fault0_w = m_valid_r[0] && !m_squash_w[0] &&
        (m_exception_r || (m_memory_w && dc_resp_err_i));
    assign m_fault1_w = m_valid_r[1] && !m_squash_w[1] &&
        m_exception1_r;
    assign m_lane_fault_w = {m_fault1_w, m_fault0_w};
    assign m_fault_old_w = m_lane_fault_w[m_old_w];
    assign m_ready_w = m_kill_all_w || m_valid_r == 0 || m_fault_old_w ||
        (m_memory_w ? (m_fault0_w || dc_resp_valid_i) : m_valid_r[0] && m_class_r[0] == C_FENCE ?
        dc_fence_done_i : m_valid_r[0] && m_class_r[0] == C_FENCE_I ?
        m_fence_phase_r && ic_inv_done_i : 1'b1);
    assign m_wait_w = (|m_valid_r) && !m_ready_w;
    assign m_advance_w = (|m_valid_r) && m_ready_w;
    assign irq_pending_w = (csr_meie_w && irq_meip_i) ||
        (csr_msie_w && irq_msip_i) || (csr_mtie_w && irq_mtip_i);
    assign irq_cause_w = csr_meie_w && irq_meip_i ? 32'h8000000b :
        csr_msie_w && irq_msip_i ? 32'h80000003 : 32'h80000007;
    assign m_interrupt_w = m_valid_r[m_old_w] && !m_kill_all_w &&
        csr_global_mie_w && irq_pending_w &&
        !m_fault_old_w && !m_device_started_r &&
        !(m_memory_w && !m_old_w && dc_resp_device_i) &&
        m_class_r[m_old_w] != C_DIV && m_class_r[m_old_w] != C_FENCE_I &&
        !(div_started_r && !div_done_r);
    // With M ready, any known M fault traps; with M waiting, issue is blocked anyway.
    // This equivalent early predicate keeps cache-hit -> trap priority out of issue.
    assign m_block_early_w = (|m_lane_fault_w) || m_interrupt_w;
    assign m_trap_w = (|m_valid_r) && (m_fault_old_w || m_interrupt_w ||
        (m_lane_fault_w[m_young_w] &&
        (!m_memory_w || m_fault0_w || dc_resp_valid_i)));
    assign m_trap_lane_w = m_interrupt_w || m_fault_old_w ? m_old_w : m_young_w;
    assign m_trap_pc_w = m_record_r[m_trap_lane_w][REC_PC_LSB +: 32];
    assign m_trap_cause_w = m_interrupt_w ? irq_cause_w : m_trap_lane_w ? m_cause1_r :
        m_exception_r ? m_cause_r : m_class_r[0] == C_STORE ? 32'd7 : 32'd5;
    assign m_trap_value_w = m_interrupt_w ? 32'd0 : m_trap_lane_w ? m_value1_r :
        m_exception_r ? m_value_r : m_result_r[0];
    assign m_commit0_w = m_advance_w && m_valid_r[0] && !m_squash_w[0] &&
        !m_fault0_w && !m_interrupt_w && !(m_swap_r && m_fault1_w);
    assign m_commit_w[0] = m_commit0_w;
    assign m_commit_w[1] = m_advance_w && m_valid_r[1] && !m_squash_w[1] &&
        !m_fault1_w && !m_interrupt_w &&
        !(!m_swap_r && m_fault0_w);
    assign dc_commit_o = m_valid_r[0] && m_memory_w && !m_fault0_w && !m_interrupt_w &&
        !(m_swap_r && m_fault1_w) &&
        !m_device_started_r && (dc_resp_device_i || dc_resp_valid_i);
    assign dc_kill_o = m_valid_r[0] &&
        (m_class_r[0] == C_LOAD || m_class_r[0] == C_STORE) && !m_exception_r &&
        !m_device_started_r &&
        (m_squash_w[0] || m_interrupt_w || m_fault0_w || (m_swap_r && m_fault1_w));
    // Each kill reason already implies a trap; do not feed trap acceptance back
    // through cache controls. Serial fences have no younger M lane to await.
    assign dc_fence_o = m_valid_r[0] && !m_squash_w[0] &&
        m_class_r[0] == C_FENCE && !m_block_early_w;
    assign dc_clean_all_o = m_valid_r[0] && !m_squash_w[0] && m_class_r[0] == C_FENCE_I &&
        !m_fence_phase_r && !m_block_early_w;
    // cpu-spec 4.5: system instructions are ready in M without a D-cache response.
    // Specialize their commit predicate so D-cache hit/ready cannot feed MRET or WFI.
    assign m_system_commit_w = m_valid_r[0] && !m_squash_w[0] && !m_exception_r &&
        !(csr_global_mie_w && irq_pending_w && !(div_started_r && !div_done_r));
    assign m_mret_w = m_class_r[0] == C_SYSTEM && m_instr_r == 32'h30200073 &&
        m_system_commit_w;
    assign m_wfi_w = m_class_r[0] == C_SYSTEM && m_instr_r == 32'h10500073 &&
        m_system_commit_w;
    // FENCE.I accepts no interrupt and completes solely on the invalidate handshake.
    assign m_fence_i_done_w = m_valid_r[0] && !m_squash_w[0] && m_class_r[0] == C_FENCE_I &&
        !m_exception_r && m_fence_phase_r && ic_inv_done_i;
    assign m_redirect_w = m_trap_w;
    assign m_front_capture_w = m_trap_w || m_mret_w || m_fence_i_done_w || m_wfi_w;
    assign m_redirect_pc_w = m_trap_w ?
        ({csr_mtvec_w[31:2], 2'b0} +
        (m_interrupt_w && csr_mtvec_w[1:0] == 1 ? {m_trap_cause_w[29:0], 2'b0} : 32'd0)) :
        m_mret_w ? csr_mepc_w :
        m_record_r[0][REC_PC_LSB +: 32] + 32'd4;
    assign backend_redirect_w = m_redirect_w || m_redirect_r || e_redirect_r;
    assign backend_redirect_pc_w = m_redirect_r ? m_redirect_pc_r :
        e_redirect_pc_w;
    assign backend_redirect_ras_w = m_redirect_r ? committed_ras_w :
        e_redirect_ras_w;
    assign frontend_redirect_w = m_redirect_r || e_redirect_r ||
        (d_redirect_r && d_redirect_issued_r);
    assign frontend_redirect_pc_w = m_redirect_r || e_redirect_r ?
        backend_redirect_pc_w : d_redirect_pc_r;
    assign frontend_redirect_ras_w = m_redirect_r || e_redirect_r ?
        backend_redirect_ras_w : d_redirect_ras_r;
    assign frontend_d_redirect_w = d_redirect_r && !d_redirect_issued_r &&
        !m_redirect_r && !e_redirect_r;
    // RAS restoration occurs for every registered M/E/D redirect. The ordinary
    // frontend PC/payload ports retain their existing M-before-E-before-D priority.
    genvar redirect_bank;
    genvar capture_bank;
    generate
        for (capture_bank = 0; capture_bank < 4;
            capture_bank = capture_bank + 1) begin : g_capture_bank
            // Four groups limit each final decision to at most five replica FFs.
            (* keep = "true", syn_preserve = 1 *) reg e_resolved_copy1_r;
            assign e_capture_copy_w[capture_bank] = e_resolve_ready_w &&
                !e_resolved_copy1_r && e_capture_reason_w;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i)
                    e_resolved_copy1_r <= 0;
                else begin
                    if (e_resolve_w)
                        e_resolved_copy1_r <= 1;
                    if (e_advance_w || m_redirect_w || d_issue_valid_w)
                        e_resolved_copy1_r <= 0;
                end
            end
        end
        for (redirect_bank = 0; redirect_bank < 17;
            redirect_bank = redirect_bank + 1) begin : g_redirect_bank
            localparam CAPTURE_BANK = redirect_bank < 12 ? redirect_bank/4 : 3;
            (* keep = "true", syn_preserve = 1 *) reg e_redirect_copy1_r;
            (* keep = "true", syn_preserve = 1 *) reg m_redirect_copy1_r;
            (* keep = "true", syn_preserve = 1 *) reg d_redirect_copy1_r;
            assign frontend_redirect_copy_w[redirect_bank] =
                m_redirect_copy1_r ? 1'b1 : e_redirect_copy1_r ? 1'b1 : d_redirect_copy1_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    e_redirect_copy1_r <= 0;
                    m_redirect_copy1_r <= 0;
                    d_redirect_copy1_r <= 0;
                end else begin
                    e_redirect_copy1_r <= e_capture_copy_w[CAPTURE_BANK];
                    m_redirect_copy1_r <= m_front_capture_w;
                    d_redirect_copy1_r <= d_capture_w;
                end
            end
        end
    endgenerate
    // Each comparison drives result FFs, then local FF copies select <=16 payload bits.
    genvar redirect_slice;
    generate
        for (redirect_slice = 0; redirect_slice < 2;
            redirect_slice = redirect_slice + 1) begin : g_redirect_slice
            wire [15:0] pc0_w;
            wire [15:0] pc1_w;
            assign pc0_w = e_redirect_taken_copy1_r[redirect_slice] ?
                e_redirect_target_lane_r[0][redirect_slice*16 +: 16] :
                e_redirect_next_lane_r[0][redirect_slice*16 +: 16];
            assign pc1_w = e_redirect_taken_copy1_r[redirect_slice+2] ?
                e_redirect_target_lane_r[1][redirect_slice*16 +: 16] :
                e_redirect_next_lane_r[1][redirect_slice*16 +: 16];
            assign e_redirect_pc_w[redirect_slice*16 +: 16] =
                e_redirect_lane_copy1_r[redirect_slice] ? pc1_w : pc0_w;
            assign e_redirect_ras_w[redirect_slice*16 +: 16] =
                e_redirect_lane_copy1_r[redirect_slice+2] ?
                e_redirect_ras_lane_r[1][redirect_slice*16 +: 16] :
                e_redirect_ras_lane_r[0][redirect_slice*16 +: 16];
            assign e_redirect_link_w[redirect_slice*16 +: 16] =
                e_redirect_lane_copy1_r[redirect_slice+5] ?
                e_redirect_next_lane_r[1][redirect_slice*16 +: 16] :
                e_redirect_next_lane_r[0][redirect_slice*16 +: 16];
            assign e_redirect_origin_w[redirect_slice*16 +: 16] =
                e_redirect_lane_copy1_r[redirect_slice+7] ?
                e_redirect_origin_lane_r[1][redirect_slice*16 +: 16] :
                e_redirect_origin_lane_r[0][redirect_slice*16 +: 16];
        end
    endgenerate
    assign e_redirect_ras_w[36:32] = e_redirect_lane_copy1_r[4] ?
        e_redirect_ras_lane_r[1][36:32] : e_redirect_ras_lane_r[0][36:32];
    assign {e_redirect_push_w, e_redirect_pop_w} = e_redirect_lane_copy1_r[9] ?
        e_redirect_action_lane_r[1] : e_redirect_action_lane_r[0];
    assign e_redirect_cause_w = e_redirect_lane_copy1_r[9] ?
        e_redirect_cause_lane_r[1] : e_redirect_cause_lane_r[0];
    assign update_clear_index_w = e_redirect_lane_copy1_r[9] ?
        e_redirect_origin_lane_r[1][9:3] : e_redirect_origin_lane_r[0][9:3];
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            e_redirect_r <= 0;
            m_redirect_r <= 0;
            d_redirect_r <= 0;
            update_valid_r <= 0;
            update_clear_r <= 0;
        end else begin
            e_redirect_r <= e_capture_w;
            m_redirect_r <= m_front_capture_w;
            d_redirect_r <= d_capture_w;
            update_valid_r <= e_resolve_w && e_survive_w[e_branch_lane_w] &&
                e_lane_control_w[e_branch_lane_w] &&
                !e_lane_exception_w[e_branch_lane_w] &&
                !e_lane_jump_fault_w[e_branch_lane_w];
            update_clear_r <= (e_redirect0_w && !e_control_w) ||
                (e_redirect1_w && !e_lane_control_w[1]);
        end
    end
    always @(posedge clk_i) begin
        e_redirect_advanced_r <= e_advance_w;
        e_redirect_old_r <= e_redirect1_w == e_old_w;
        e_redirect_lane_copy1_r <= {10{e_redirect1_w}};
        e_redirect_taken_copy1_r <= {{2{e_lane_taken_w[1]}}, {2{e_lane_taken_w[0]}}};
        m_redirect_pc_r <= m_redirect_pc_w;
        m_redirect_trap_r <= m_trap_w;
        m_redirect_origin_r <= m_record_r[0][REC_PC_LSB +: 32];
        d_redirect_origin_r <= d_record_w[d_redirect_slot_w][REC_PC_LSB +: 32];
        d_redirect_issued_r <= d_issue_valid_w;
        d_redirect_slot_r <= d_redirect_slot_w;
        d_redirect_pc_r <= d_target_w;
        d_redirect_ras_r <= d_record_w[d_redirect_slot_w][REC_RAS_LSB +: 37];
        d_redirect_push_r <= d_rd_w[d_redirect_slot_w] == 1 ||
            d_rd_w[d_redirect_slot_w] == 5;
        d_redirect_link_r <= d_record_w[d_redirect_slot_w][REC_PC_LSB +: 32] + 32'd4;
        update_pc_r <= e_record_r[e_branch_lane_w][REC_PC_LSB +: 32];
        update_target_r <= e_lane_target_w[e_branch_lane_w];
        update_type_r <= e_lane_type_w[e_branch_lane_w];
        update_taken_r <= e_lane_taken_w[e_branch_lane_w];
        update_index_r <= e_predict_index_w;
        update_tournament_r <= e_tournament_r;
    end
    assign csr_m_access_w = m_valid_r[0] && m_csr_r;
    assign csr_d_access_w = d_count_w != 0 && d_csr_w[0] && !csr_m_access_w;
    // C-F1 path 1: M owns the CSR data port; D has a separate permission decoder.
    assign csr_command_w = m_instr_r[13:12];
    assign csr_write_w = m_instr_r[13:12] == 1 || m_instr_r[19:15] != 0;
    // D only checks address/permission; only M can commit a CSR write (cpu-spec 4.6).
    assign csr_operand_w = m_csr_data_r;
    always @(*) begin
        for (result_idx = 0; result_idx < 2; result_idx = result_idx + 1) begin
            e_result_w[result_idx] = e_alu_w[result_idx];
            case (e_class_r[result_idx])
                C_LUI: e_result_w[result_idx] = e_imm_r[result_idx];
                C_AUIPC: e_result_w[result_idx] =
                    e_record_r[result_idx][REC_PC_LSB +: 32] + e_imm_r[result_idx];
                C_JAL, C_JALR: e_result_w[result_idx] = e_record_r[result_idx][REC_PC_LSB +: 32] +
                    32'd4;
                C_LOAD: e_result_w[result_idx] =
                    e_operand_a_w[result_idx] + e_imm_r[result_idx];
                C_STORE: e_result_w[result_idx] =
                    e_operand_a_w[result_idx] + e_imm_r[result_idx];
                C_DIV: e_result_w[result_idx] = div_result_w;
                default: e_result_w[result_idx] = e_alu_w[result_idx];
            endcase
            m_result_w[result_idx] = m_result_r[result_idx];
            if (result_idx == 0) begin
                if (m_csr_r)
                    m_result_w[result_idx] = csr_read_w;
                if (m_load_r)
                    m_result_w[result_idx] =
                        ({32{dc_resp_way_hit_i[0]}} & m_load_result_w[0]) |
                        ({32{dc_resp_way_hit_i[1]}} & m_load_result_w[1]);
            end
        end
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            e_valid_r <= 0;
            e_swap_r <= 0;
            m_swap_r <= 0;
            w_swap_r <= 0;
            m_valid_r <= 0;
            w_valid_r <= 0;
            w2_valid_r <= 0;
            w2_swap_r <= 0;
            div_started_r <= 0;
            div_done_r <= 0;
            m_device_started_r <= 0;
            m_fence_phase_r <= 0;
            sleep_r <= 0;
            ic_expect_r <= 0;
            dc_expect_r <= 0;
            ic_miss_r <= 0;
            dc_miss_r <= 0;
            m_wait_r <= 0;
            div_wait_front_r <= 0;
            e_resolved_r <= 0;
            e_jump_fault_r <= 0;
            d_redirected_r <= 0;
        end else begin
            // The frontend observes M backpressure one cycle after D-cache lookup.
            m_wait_r <= m_wait_w;
            div_wait_front_r <= div_wait_w;
            if (d_capture_w)
                d_redirected_r <= 1;
            if (backend_redirect_w || d_issue_valid_w)
                d_redirected_r <= 0;
            w_valid_r <= m_commit_w;
            w2_valid_r <= w_valid_r;
            w2_swap_r <= w_swap_r;
            w_swap_r <= m_swap_r;
            if (e_advance_w)
                m_swap_r <= e_swap_r;
            if (d_issue_valid_w)
                e_swap_r <= d_swap_w;
            if (!m_wait_w)
                m_valid_r <= e_advance_w ? e_survive_w : 2'b0;
            if (e_advance_w)
                e_valid_r <= 0;
            if (d_issue_valid_w)
                e_valid_r <= d_issue_w[1] ? 2'b11 : 2'b01;
            if (e_kill_young_w && !e_advance_w)
                e_valid_r[e_young_w] <= 0;
            if (m_redirect_w || e_flush_w)
                e_valid_r <= 0;
            if (e_resolve_w)
                e_resolved_r <= 1;
            if (e_resolve_w)
                e_jump_fault_r <= e_lane_jump_fault_w;
            if (e_advance_w || m_redirect_w || d_issue_valid_w)
                e_resolved_r <= 0;
            if (e_advance_w || m_redirect_w || e_flush_w || d_issue_valid_w)
                e_jump_fault_r <= 0;
            if (m_redirect_w || m_kill_all_w)
                m_valid_r <= 0;
            if (div_start_w)
                div_started_r <= 1;
            if (div_valid_w)
                div_done_r <= 1;
            if (e_advance_w || m_redirect_w || d_issue_valid_w) begin
                div_started_r <= 0;
                div_done_r <= 0;
            end
            if (dc_commit_o && dc_resp_device_i)
                m_device_started_r <= 1;
            if (m_advance_w || m_redirect_w) begin
                m_device_started_r <= 0;
                m_fence_phase_r <= 0;
            end else if (dc_clean_all_o && dc_fence_done_i)
                m_fence_phase_r <= 1;
            if (m_wfi_w)
                sleep_r <= !irq_pending_w;
            else if (irq_pending_w || m_trap_w)
                sleep_r <= 0;
            ic_expect_r <= ic_req_valid_o && ic_req_ready_i;
            dc_expect_r <= dc_req_valid_o && dc_req_ready_i;
            if (ic_miss_start_w)
                ic_miss_r <= 1;
            if (ic_resp_valid_i || ic_kill_o)
                ic_miss_r <= 0;
            if (dc_miss_start_w)
                dc_miss_r <= 1;
            if (dc_resp_valid_i || dc_kill_o)
                dc_miss_r <= 0;
        end
    end
    always @(posedge clk_i) begin
        for (stage_idx = 0; stage_idx < 2; stage_idx = stage_idx + 1) begin
            e_redirect_target_lane_r[stage_idx] <= e_lane_target_w[stage_idx];
            e_redirect_next_lane_r[stage_idx] <= e_lane_next_pc_w[stage_idx];
            e_redirect_ras_lane_r[stage_idx] <= e_record_r[stage_idx][REC_RAS_LSB +: 37];
            e_redirect_origin_lane_r[stage_idx] <= e_record_r[stage_idx][REC_PC_LSB +: 32];
            e_redirect_action_lane_r[stage_idx] <=
                {e_lane_call_w[stage_idx], e_lane_return_w[stage_idx]};
            e_redirect_cause_lane_r[stage_idx] <= !e_lane_control_w[stage_idx] ? 2'd3 :
                e_class_r[stage_idx] == C_BRANCH &&
                e_record_r[stage_idx][REC_PRED_TAKEN] != e_lane_branch_taken_w[stage_idx] ?
                2'd1 : 2'd2;
            w2_record_r[stage_idx] <= w_record_r[stage_idx];
            w2_result_r[stage_idx] <= w_result_w[stage_idx];
            w2_rd_r[stage_idx] <= w_rd_r[stage_idx];
            w2_write_r[stage_idx] <= w_write_r[stage_idx];
            w2_class_r[stage_idx] <= w_class_r[stage_idx];
            // C-F1 path 4: W validity is replaced every cycle, so its payload
            // can follow M unconditionally without the D-cache-hit CE cone.
            begin
                w_record_r[stage_idx] <= m_record_r[stage_idx];
                w_result_r[stage_idx] <= m_result_w[stage_idx];
                w_rd_r[stage_idx] <= m_rd_r[stage_idx];
                w_write_r[stage_idx] <= m_write_r[stage_idx];
                w_class_r[stage_idx] <= m_class_r[stage_idx];
                w_mul_r[stage_idx] <= m_mul_r[stage_idx];
                if (stage_idx == 0)
                    w_dest_r <= m_dest_r[0];
            end
            if (!m_wait_w)
                m_result_r[stage_idx] <= stage_idx == 0 &&
                    (e_class_r[stage_idx] == C_LOAD || e_class_r[stage_idx] == C_STORE) ?
                    e_address_w : e_result_w[stage_idx];
            if (e_advance_copy_w[stage_idx]) begin
                m_record_r[stage_idx] <= e_record_r[stage_idx];
                m_rd_r[stage_idx] <= e_rd_r[stage_idx];
                m_write_r[stage_idx] <= e_write_r[stage_idx];
                m_class_r[stage_idx] <= e_class_r[stage_idx];
                m_mul_r[stage_idx] <= e_mul_r[stage_idx];
                m_dest_r[stage_idx] <= e_dest_r[stage_idx];
                if (stage_idx == 0) begin
                    m_load_r <= e_load_r[0];
                    m_csr_r <= e_csr_r[0];
                    m_memory_r <= e_memory_r;
                    m_slow_r <= e_slow_r;
                    m_exception_r <= e_exception_r;
                    m_cause_r <= e_cause_r;
                    m_value_r <= e_value_r;
                    if (!e_exception_r) begin
                        if (e_memory_w && e_misaligned_w) begin
                            m_exception_r <= 1;
                            m_cause_r <= e_class_r[stage_idx] == C_STORE ? 32'd6 : 32'd4;
                            m_value_r <= e_address_w;
                        end else if (e_control_w) begin
                            m_exception_r <= e_jump_misaligned_w;
                            m_cause_r <= 0;
                            m_value_r <= e_lane_target_w[0];
                        end
                    end
                end
                if (stage_idx == 1) begin
                    m_control_r <= e_control_r[1];
                    m_exception1_r <= e_exception1_r || e_lane_jump_fault_w[1];
                    m_cause1_r <= e_exception1_r ? e_cause1_r : 32'd0;
                    m_value1_r <= e_exception1_r ? e_value1_r : e_lane_target_w[1];
                end
            end
            // Per-source enables include capture, hold and failed-early repair.
            // No data mux follows the final one-hot merge.
            e_operand_a_r[stage_idx] <= e_forward_w[stage_idx*2];
            e_operand_b_r[stage_idx] <= e_forward_w[stage_idx*2+1];
            e_alu_operand_b_copy1_r[stage_idx] <= e_alu_input_w[stage_idx];
            e_branch_a_r[stage_idx] <= e_branch_forward_w[stage_idx*2];
            e_branch_b_r[stage_idx] <= e_branch_forward_w[stage_idx*2+1];
            // A live stalled E holds all payload; otherwise validity owns its use.
            // Keep the late D$ handshake out of issue/hazard/redirect selection.
            if (e_operand_load_copy_w[stage_idx+2]) begin
                e_record_r[stage_idx] <= d_record_w[d_map_w[stage_idx]];
                if (d_class_w[d_map_w[stage_idx]] == C_JAL &&
                    !d_record_w[d_map_w[stage_idx]][REC_PRED_HIT]) begin
                    e_record_r[stage_idx][REC_PRED_TAKEN] <= 1;
                    e_record_r[stage_idx][REC_PRED_TARGET_LSB +: 32] <=
                        d_slot_target_w[d_map_w[stage_idx]];
                end
                e_class_r[stage_idx] <= d_class_w[d_map_w[stage_idx]];
                e_load_r[stage_idx] <= d_load_w[d_map_w[stage_idx]];
                e_mul_r[stage_idx] <= d_mul_w[d_map_w[stage_idx]];
                e_csr_r[stage_idx] <= d_csr_w[d_map_w[stage_idx]];
                e_control_r[stage_idx] <= d_control_w[d_map_w[stage_idx]];
                e_dest_r[stage_idx] <= d_dest_w[d_map_w[stage_idx]];
                e_operation_select_r[stage_idx] <=
                    {10{d_class_w[d_map_w[stage_idx]] == C_ALU}} & {
                    d_operation_w[d_map_w[stage_idx]] == 4'h7,
                    d_operation_w[d_map_w[stage_idx]] == 4'h6,
                    d_operation_w[d_map_w[stage_idx]] == 4'hd,
                    d_operation_w[d_map_w[stage_idx]] == 4'h5,
                    d_operation_w[d_map_w[stage_idx]] == 4'h4,
                    d_operation_w[d_map_w[stage_idx]] == 4'h3,
                    d_operation_w[d_map_w[stage_idx]] == 4'h2,
                    d_operation_w[d_map_w[stage_idx]] == 4'h1,
                    d_operation_w[d_map_w[stage_idx]] == 4'h8,
                    d_operation_w[d_map_w[stage_idx]] == 4'h0};
                e_div_result_r[stage_idx] <= d_class_w[d_map_w[stage_idx]] == C_DIV;
                e_nonalu_result_r[stage_idx] <=
                    ({32{d_class_w[d_map_w[stage_idx]] == C_LUI}} &
                        d_imm_w[d_map_w[stage_idx]]) |
                    ({32{d_class_w[d_map_w[stage_idx]] == C_AUIPC}} &
                        d_slot_target_w[d_map_w[stage_idx]]) |
                    ({32{d_class_w[d_map_w[stage_idx]] == C_JAL ||
                        d_class_w[d_map_w[stage_idx]] == C_JALR}} &
                        (d_record_w[d_map_w[stage_idx]][REC_PC_LSB +: 32] + 32'd4));
                e_immediate_r[stage_idx] <= d_immediate_w[d_map_w[stage_idx]];
                e_imm_r[stage_idx] <= d_imm_w[d_map_w[stage_idx]];
                e_rd_r[stage_idx] <= d_rd_w[d_map_w[stage_idx]];
                e_write_r[stage_idx] <= d_write_w[d_map_w[stage_idx]];
                if (stage_idx == 0) begin
                    e_memory_r <= d_memory_w[d_map_w[0]];
                    e_slow_r <= d_slow_w[d_map_w[0]];
                    e_exception_r <= d_record_w[d_map_w[stage_idx]][REC_FETCH_ERR] ||
                        d_record_w[d_map_w[stage_idx]][REC_ILLEGAL] ||
                        d_illegal_w[d_map_w[stage_idx]] ||
                        (csr_d_access_w && csr_decode_illegal_w) ||
                        d_instr_w[d_map_w[stage_idx]] == 32'h00000073 ||
                        d_instr_w[d_map_w[stage_idx]] == 32'h00100073;
                    e_cause_r <= d_record_w[d_map_w[stage_idx]][REC_FETCH_ERR] ? 32'd1 :
                        d_instr_w[d_map_w[stage_idx]] == 32'h00000073 ? 32'd11 :
                        d_instr_w[d_map_w[stage_idx]] == 32'h00100073 ? 32'd3 : 32'd2;
                    e_value_r <= d_record_w[d_map_w[stage_idx]][REC_FETCH_ERR] ||
                        d_instr_w[d_map_w[stage_idx]] == 32'h00100073 ?
                        d_record_w[d_map_w[stage_idx]][REC_PC_LSB +: 32] :
                        d_instr_w[d_map_w[stage_idx]] == 32'h00000073 ? 32'd0 :
                        d_record_w[d_map_w[stage_idx]][REC_RAW_LSB +: 2] != 2'b11 ?
                        {16'b0, d_record_w[d_map_w[stage_idx]][REC_RAW_LSB +: 16]} :
                        d_record_w[d_map_w[stage_idx]][REC_RAW_LSB +: 32];
                end
                if (stage_idx == 1) begin
                    // CSR/system instructions never enter pipe 1 (spec 4.2).
                    e_exception1_r <= d_record_w[d_map_w[stage_idx]][REC_FETCH_ERR] ||
                        d_record_w[d_map_w[stage_idx]][REC_ILLEGAL] ||
                        d_illegal_w[d_map_w[stage_idx]];
                    e_cause1_r <= d_record_w[d_map_w[stage_idx]][REC_FETCH_ERR] ? 32'd1 : 32'd2;
                    e_value1_r <= d_record_w[d_map_w[stage_idx]][REC_FETCH_ERR] ?
                        d_record_w[d_map_w[stage_idx]][REC_PC_LSB +: 32] :
                        d_record_w[d_map_w[stage_idx]][REC_RAW_LSB +: 2] != 2'b11 ?
                        {16'b0, d_record_w[d_map_w[stage_idx]][REC_RAW_LSB +: 16]} :
                        d_record_w[d_map_w[stage_idx]][REC_RAW_LSB +: 32];
                end
            end
        end
        if (e_advance_w) begin
            m_wait_dc_r <= e_memory_w && !e_exception_r && !e_misaligned_w;
            m_store_r <= e_operand_b_w[0];
            m_instr_r <= e_instr_w;
            m_csr_select_r <= e_csr_select_r;
            m_csr_data_r <= e_instr_w[14] ? {27'b0, e_instr_w[19:15]} : e_operand_a_w[0];
        end
        // Speculative D payload uses the same free-E enable as operands; no extra cycle.
        if (e_operand_load_w) begin
            e_csr_select_r <= d_csr_select_w;
            e_pc_target_r <= d_slot_target_w[d_map_w[0]];
            e_pc_target1_r <= d_slot_target_w[d_map_w[1]];
            e_pc_target_match_r <=
                (d_class_w[d_map_w[0]] == C_JAL &&
                !d_record_w[d_map_w[0]][REC_PRED_HIT]) ||
                d_slot_target_w[d_map_w[0]] ==
                d_record_w[d_map_w[0]][REC_PRED_TARGET_LSB +: 32];
            e_pc_target_match1_r <=
                (d_class_w[d_map_w[1]] == C_JAL &&
                !d_record_w[d_map_w[1]][REC_PRED_HIT]) ||
                d_slot_target_w[d_map_w[1]] ==
                d_record_w[d_map_w[1]][REC_PRED_TARGET_LSB +: 32];
            e_jalr_expected_even_r <= d_jalr_expected_even_w;
            e_jalr_expected_odd_r <= d_jalr_expected_odd_w;
        end
    end
    assign m_call_w = (m_class_r[m_branch_lane_w] == C_JAL ||
        m_class_r[m_branch_lane_w] == C_JALR) &&
        (m_record_r[m_branch_lane_w][REC_INSTR_LSB + 7 +: 5] == 1 ||
        m_record_r[m_branch_lane_w][REC_INSTR_LSB + 7 +: 5] == 5);
    assign m_return_w = m_class_r[m_branch_lane_w] == C_JALR &&
        (m_record_r[m_branch_lane_w][REC_INSTR_LSB + 15 +: 5] == 1 ||
        m_record_r[m_branch_lane_w][REC_INSTR_LSB + 15 +: 5] == 5) && !m_call_w;
    assign m_link_w = m_result_r[m_branch_lane_w];
    // Delay the physical committed-RAS update to W. During an M redirect's emit
    // cycle, W is exactly that M group's commit: this lookahead is its checkpoint.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            w_ras_commit_copy1_r <= 0;
        else
            w_ras_commit_copy1_r <= {11{m_commit_w[m_branch_lane_w]}};
    end
    always @(posedge clk_i) begin
        w_ras_call_r <= m_call_w;
        w_ras_return_r <= m_return_w;
        w_ras_link_r <= m_link_w;
    end
    always @(*) begin
        committed_ras_ptr_w = committed_ras_ptr_r;
        committed_ras_count_w = committed_ras_count_r;
        if (w_ras_commit_copy1_r[8]) begin
            if (w_ras_return_r && committed_ras_count_r != 0) begin
                committed_ras_ptr_w = committed_ras_ptr_r - 1'b1;
                committed_ras_count_w = committed_ras_count_r - 1'b1;
            end
            if (w_ras_call_r) begin
                committed_ras_ptr_w = committed_ras_ptr_r + 1'b1;
                if (committed_ras_count_r < 4)
                    committed_ras_count_w = committed_ras_count_r + 1'b1;
            end
        end
    end
    assign committed_ras_w =
        {committed_ras_count_w, committed_ras_ptr_w, committed_ras_top_w};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            committed_ras_ptr_r <= 0;
            committed_ras_count_r <= 0;
            committed_ras_ptr_copy1_r <= 0;
            committed_ras_top_copy1_r <= {2{2'd3}};
            committed_ras_second_copy1_r <= {2{2'd2}};
        end else begin
            committed_ras_ptr_r <= committed_ras_ptr_w;
            committed_ras_count_r <= committed_ras_count_w;
            committed_ras_ptr_copy1_r <= {8{committed_ras_ptr_w}};
            committed_ras_top_copy1_r <= {2{committed_ras_ptr_w - 2'd1}};
            committed_ras_second_copy1_r <= {2{committed_ras_ptr_w - 2'd2}};
        end
    end
    genvar ras_bank;
    genvar ras_half;
    generate
        for (ras_bank = 0; ras_bank < 8; ras_bank = ras_bank + 1) begin : g_committed_ras
            localparam WORD = ras_bank / 2;
            // Each late write enable owns one 16-bit bank.
            always @(posedge clk_i) begin
                if (w_ras_commit_copy1_r[ras_bank] && w_ras_call_r &&
                    committed_ras_ptr_copy1_r[ras_bank*2 +: 2] == WORD[1:0])
                    committed_ras_data_r[ras_bank*16 +: 16] <=
                        w_ras_link_r[(ras_bank%2)*16 +: 16];
            end
        end
        for (ras_half = 0; ras_half < 2; ras_half = ras_half + 1) begin : g_committed_top
            wire [15:0] top_w;
            wire [15:0] second_w;
            wire push_w;
            wire pop_w;
            assign top_w = committed_ras_data_r[
                committed_ras_top_copy1_r[ras_half*2 +: 2]*32 + ras_half*16 +: 16];
            assign second_w = committed_ras_data_r[
                committed_ras_second_copy1_r[ras_half*2 +: 2]*32 + ras_half*16 +: 16];
            assign push_w = w_ras_commit_copy1_r[ras_half+9] && w_ras_call_r;
            assign pop_w = w_ras_commit_copy1_r[ras_half+9] && w_ras_return_r &&
                committed_ras_count_r != 0;
            assign committed_ras_top_w[ras_half*16 +: 16] = push_w ?
                w_ras_link_r[ras_half*16 +: 16] : pop_w ? second_w : top_w;
        end
    endgenerate
    assign retire_count_w = {1'b0, w2_valid_r[0]} + {1'b0, w2_valid_r[1]};
    // spec 5: a minstret write replaces the count including its own retirement.
    // The write commits in M, one cycle before its instruction retires in W.
    assign w_instret_write_w = w2_valid_r[0] && w2_class_r[0] == C_CSR &&
        (w2_record_r[0][REC_RAW_LSB+20 +: 12] == 12'hb02
        || w2_record_r[0][REC_RAW_LSB+20 +: 12] == 12'hb82) &&
        (w2_record_r[0][REC_RAW_LSB+12 +: 2] == 2'b01 || w2_record_r[0][REC_RAW_LSB+15 +: 5] != 0);
    assign csr_retire_count_w = w_instret_write_w ? 2'b0 : retire_count_w;
    assign ic_miss_start_w = ic_expect_r && !ic_resp_valid_i && !ic_kill_o;
    assign dc_miss_start_w = dc_expect_r && !dc_resp_valid_i && !dc_resp_device_i && !dc_kill_o;
    always @(*) begin
        event_count_w = 0;
        event_count_w[1:0] = {1'b0, retire_count_w == 2};
        event_count_w[3:2] = {1'b0, retire_count_w == 1};
        event_count_w[5:4] = {1'b0, retire_count_w == 0};
        event_count_w[7:6] = {1'b0,
            (w2_valid_r[0] && w2_class_r[0] >= C_JAL && w2_class_r[0] <= C_BRANCH) ||
            (w2_valid_r[1] && w2_class_r[1] >= C_JAL && w2_class_r[1] <= C_BRANCH)};
        event_count_w[9:8] = {1'b0, d_issue_valid_w && d_pair_reason_pre_w == 1};
        event_count_w[11:10] = {1'b0, d_issue_valid_w && d_pair_reason_pre_w == 2};
        event_count_w[13:12] = {1'b0, d_issue_valid_w && d_pair_reason_pre_w == 3};
        event_count_w[15:14] = {1'b0, d_issue_valid_w && d_pair_reason_pre_w == 4};
        event_count_w[17:16] = {1'b0, e_repair_pending_r ||
            (d_count_w != 0 && !d_issue_valid_w && e_valid_r[0] &&
            e_class_r[0] == C_LOAD && !e_early_r && ((d_use1_w[0] && d_rs1_w[0] == e_rd_r[0]) ||
            (d_use2_w[0] && d_rs2_w[0] == e_rd_r[0])) && e_rd_r[0] != 0)};
        event_count_w[19:18] = {1'b0, div_wait_w};
        event_count_w[21:20] = {1'b0, m_wait_w && dc_resp_device_i};
        event_count_w[23:22] = {1'b0, d_count_w == 0 && d_available_w};
        event_count_w[25:24] = {1'b0, ic_miss_start_w};
        event_count_w[27:26] = {1'b0, dc_miss_start_w};
        event_count_w[29:28] = {1'b0, dc_wb_event_i};
        event_count_w[31:30] = {1'b0,
            trace_redirect_stage_w == 1 || trace_redirect_stage_w == 2};
    end
    assign trace_bypass_w = {
        d_issue_w[1] && d_use2_w[1] ? d_bypass_w[3] : 3'b0,
        d_issue_w[1] && d_use1_w[1] ? d_bypass_w[2] : 3'b0,
        d_issue_valid_w && d_use2_w[0] ? d_bypass_w[1] : 3'b0,
        d_issue_valid_w && d_use1_w[0] ? d_bypass_w[0] : 3'b0};
    always @(*) begin
        trace_redirect_cause_w = m_redirect_r ? 2'd0 :
            e_redirect_r ? e_redirect_cause_w : 2'd0;
        trace_stall_cause_w = e_repair_pending_r ? 3'd1 : div_wait_w ? 3'd5 : 3'd0;
        if (d_count_w != 0 && !d_issue_valid_w) begin
            if (d_csr_wait_w && !e_repair_pending_r)
                trace_stall_cause_w = 4;
            if (d_use1_w[0] && d_wait_kind_w[0] != 0 &&
                (trace_stall_cause_w == 0 || d_wait_kind_w[0] < trace_stall_cause_w))
                trace_stall_cause_w = d_wait_kind_w[0];
            if (d_use2_w[0] && d_wait_kind_w[1] != 0 &&
                (trace_stall_cause_w == 0 || d_wait_kind_w[1] < trace_stall_cause_w))
                trace_stall_cause_w = d_wait_kind_w[1];
        end
    end
    assign trace_valid_w = w2_swap_r ? {w2_valid_r[0], w2_valid_r[1]} : w2_valid_r;
    assign trace_pc_w = {w2_record_r[!w2_swap_r][REC_PC_LSB +: 32],
        w2_record_r[w2_swap_r][REC_PC_LSB +: 32]};
    assign trace_instr_w = {w2_record_r[!w2_swap_r][REC_RAW_LSB +: 32],
        w2_record_r[w2_swap_r][REC_RAW_LSB +: 32]};
    assign trace_rd_w = {w2_write_r[!w2_swap_r] ? w2_rd_r[!w2_swap_r] : 5'b0,
        w2_write_r[w2_swap_r] ? w2_rd_r[w2_swap_r] : 5'b0};
    assign trace_rd_data_w = {w2_result_w[!w2_swap_r], w2_result_w[w2_swap_r]};
    assign trace_trap_w = trace_trap_r;
    assign trace_cause_w = trace_cause_r;
    assign debug_o = {trace_valid_w[0] ? trace_pc_w[31:0] :
        trace_valid_w[1] ? trace_pc_w[63:32] : 32'b0,
        2'b0, sleep_r, dc_miss_r, ic_miss_r, m_wait_w && dc_resp_device_i,
        div_busy_w, event_count_w[16], d_pair_reason_w, retire_count_w,
        m_trap_w, trace_redirect_stage_w == 1, trace_redirect_stage_w == 2,
        fetch_wait_w, m_wait_w,
        m_wait_w || div_wait_w || (d_count_w != 0 && !d_issue_valid_w),
        w2_valid_r, m_valid_r, e_valid_r,
        d_count_w >= 2, d_count_w != 0, ib_count_w, f2_valid_w, f1_valid_w};
endmodule
