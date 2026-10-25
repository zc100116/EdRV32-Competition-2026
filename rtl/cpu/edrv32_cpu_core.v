// File: edrv32_cpu_core.v
// Spec: cpu-spec v0.4 2-7
// Description: Execute in-order dual-issue instructions through D/E/M/W.
//              Commit precise traps, memory transactions and architectural state.
// Clock: clk_sys.
module edrv32_cpu_core #(
    parameter RVC_EN = 1
) (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,
    // Instruction cache.
    output wire ic_req_valid_o,
    output wire [31:0] ic_req_addr_o,
    input wire ic_req_ready_i,
    input wire ic_resp_valid_i,
    input wire [63:0] ic_resp_data_i,
    input wire ic_resp_err_i,
    output wire ic_kill_o,
    output wire ic_inv_o,
    input wire ic_inv_done_i,
    // Data cache.
    output wire dc_req_valid_o,
    output wire [31:0] dc_req_addr_o,
    output wire dc_req_store_o,
    output wire [1:0] dc_req_size_o,
    input wire dc_req_ready_i,
    input wire dc_resp_valid_i,
    input wire [31:0] dc_resp_data_i,
    input wire dc_resp_err_i,
    input wire dc_resp_device_i,
    output wire dc_kill_o,
    output wire dc_commit_o,
    output wire [31:0] dc_store_data_o,
    output wire dc_fence_o,
    output wire dc_clean_all_o,
    input wire dc_fence_done_i,
    input wire dc_wb_event_i,
    // Interrupts, CLINT time and observation.
    input wire irq_meip_i,
    input wire irq_msip_i,
    input wire irq_mtip_i,
    input wire [63:0] mtime_i,
    output wire [63:0] debug_o
);
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
    wire [357:0] d_data_w;
    wire [1:0] d_count_w;
    wire [2:0] ib_count_w;
    reg [1:0] d_issue_w;
    wire [178:0] d_record_w [0:1];
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
    reg [31:0] d_operand_w [0:3];
    reg [3:0] d_hazard_w;
    reg [2:0] d_bypass_w [0:3];
    reg [2:0] d_wait_kind_w [0:3];
    wire d_raw_w;
    wire d_pair_type_w;
    wire d_serial_w;
    wire d_csr_wait_w;
    wire d_available_w;
    wire d_redirect_w;
    wire [31:0] d_target_w;
    reg [2:0] d_pair_reason_w;
    reg [1:0] e_valid_r;
    reg [1:0] m_valid_r;
    reg [1:0] w_valid_r;
    reg [178:0] e_record_r [0:1];
    reg [178:0] m_record_r [0:1];
    reg [178:0] w_record_r [0:1];
    reg [3:0] e_class_r [0:1];
    reg [3:0] m_class_r [0:1];
    reg [3:0] w_class_r [0:1];
    reg [3:0] e_operation_r [0:1];
    reg e_immediate_r [0:1];
    reg [31:0] e_imm_r [0:1];
    reg [31:0] e_operand_a_r [0:1];
    reg [31:0] e_operand_b_r [0:1];
    reg [4:0] e_rd_r [0:1];
    reg [4:0] m_rd_r [0:1];
    reg [4:0] w_rd_r [0:1];
    reg e_write_r [0:1];
    reg m_write_r [0:1];
    reg w_write_r [0:1];
    reg e_exception_r [0:1];
    reg m_exception_r [0:1];
    reg [31:0] e_cause_r [0:1];
    reg [31:0] m_cause_r [0:1];
    reg [31:0] e_value_r [0:1];
    reg [31:0] m_value_r [0:1];
    wire [31:0] e_alu_w [0:1];
    wire [31:0] e_alu_b_w [0:1];
    reg [31:0] e_result_w [0:1];
    reg [31:0] m_result_r [0:1];
    reg [31:0] w_result_r [0:1];
    reg [31:0] m_result_w [0:1];
    wire [31:0] w_result_w [0:1];
    reg [31:0] m_store_r;
    reg [31:0] m_csr_data_r;
    reg [31:0] m_instr_r;
    wire [31:0] e_instr_w;
    wire [31:0] e_next_pc_w;
    wire [31:0] e_address_w;
    wire [31:0] e_branch_target_w;
    wire [31:0] e_actual_pc_w;
    wire e_branch_taken_w;
    wire e_control_w;
    wire e_taken_w;
    wire e_call_w;
    wire e_return_w;
    wire [2:0] e_type_w;
    wire e_redirect_w;
    wire e_redirect0_w;
    wire e_redirect1_w;
    wire [31:0] e_second_next_pc_w;
    wire [31:0] e_redirect_pc_w;
    wire e_memory_w;
    wire e_misaligned_w;
    wire e_jump_misaligned_w;
    wire e_advance_w;
    wire m_advance_w;
    wire m_memory_w;
    wire m_wait_w;
    wire m_ready_w;
    wire [1:0] m_commit_w;
    wire m_commit0_w;
    wire m_fault0_w;
    wire m_fault1_w;
    wire m_interrupt_w;
    wire m_trap_w;
    wire [31:0] m_trap_pc_w;
    wire [31:0] m_trap_cause_w;
    wire [31:0] m_trap_value_w;
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
    wire csr_illegal_w;
    wire csr_m_access_w;
    wire csr_d_access_w;
    wire csr_write_w;
    wire [11:0] csr_addr_w;
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
    wire div_wait_w;
    reg div_started_r;
    reg div_done_r;
    reg [127:0] committed_ras_data_r;
    reg [1:0] committed_ras_ptr_r;
    reg [2:0] committed_ras_count_r;
    reg [127:0] committed_ras_data_w;
    reg [1:0] committed_ras_ptr_w;
    reg [2:0] committed_ras_count_w;
    wire [36:0] committed_ras_w;
    wire [1:0] committed_top_w;
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
    integer operand_idx;
    integer producer_idx;
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
    assign unused_mul_valid_w = mul_valid_w;
    assign unused_lane1_predicted_target_w = d_record_w[1][132:101];
    assign e_instr_w = e_record_r[0][63:32];
    assign d_record_w[0] = d_data_w[178:0];
    assign d_record_w[1] = d_data_w[357:179];
    assign d_source_w[0] = d_rs1_w[0];
    assign d_source_w[1] = d_rs2_w[0];
    assign d_source_w[2] = d_rs1_w[1];
    assign d_source_w[3] = d_rs2_w[1];
    genvar lane;
    generate
        for (lane = 0; lane < 2; lane = lane + 1) begin : g_lane
            assign d_instr_w[lane] = d_record_w[lane][63:32];
            edrv32_cpu_decode u_decode (
                .instr_i(d_instr_w[lane]),
                .rs1_o(d_rs1_w[lane]),
                .rs2_o(d_rs2_w[lane]),
                .rd_o(d_rd_w[lane]),
                .rs1_used_o(d_use1_w[lane]),
                .rs2_used_o(d_use2_w[lane]),
                .rd_write_o(d_write_w[lane]),
                .imm_o(d_imm_w[lane]),
                .class_o(d_class_w[lane]),
                .alu_operation_o(d_operation_w[lane]),
                .operand_imm_o(d_immediate_w[lane]),
                .illegal_o(d_illegal_w[lane])
            );
            assign e_alu_b_w[lane] = e_immediate_r[lane] ?
                e_imm_r[lane] : e_operand_b_r[lane];
            edrv32_cpu_alu u_alu (
                .operand_a_i(e_operand_a_r[lane]),
                .operand_b_i(e_alu_b_w[lane]),
                .operation_i(e_operation_r[lane]),
                .result_o(e_alu_w[lane])
            );
            assign w_result_w[lane] = lane == 0 && w_class_r[lane] == C_MUL ?
                mul_result_w : w_result_r[lane];
        end
    endgenerate
    edrv32_cpu_frontend #(.RVC_EN(RVC_EN)) u_frontend (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .redirect_valid_i(backend_redirect_w),
        .redirect_pc_i(backend_redirect_pc_w),
        .redirect_ras_i(backend_redirect_ras_w),
        .redirect_push_i(!m_redirect_w && e_redirect0_w && e_call_w),
        .redirect_pop_i(!m_redirect_w && e_redirect0_w && e_return_w),
        .redirect_return_pc_i(e_next_pc_w),
        .d_redirect_valid_i(d_redirect_w),
        .d_redirect_pc_i(d_target_w),
        .d_redirect_ras_i(d_record_w[0][178:142]),
        .d_redirect_push_i(d_rd_w[0] == 1 || d_rd_w[0] == 5),
        .d_redirect_pop_i(1'b0),
        .d_redirect_return_pc_i(d_record_w[0][31:0] + (d_record_w[0][96] ? 32'd2 : 32'd4)),
        .halt_i(sleep_r || div_wait_w || m_wait_w),
        .update_valid_i(e_advance_w && e_valid_r[0] && e_control_w &&
            !e_exception_r[0] && !e_jump_misaligned_w),
        .update_clear_i(e_redirect1_w || (e_redirect0_w && !e_control_w)),
        .update_clear_index_i(e_redirect1_w ? e_record_r[1][7:3] : e_record_r[0][7:3]),
        .update_pc_i(e_record_r[0][31:0]),
        .update_target_i(e_branch_target_w),
        .update_type_i(e_type_w),
        .update_taken_i(e_class_r[0] != C_BRANCH || e_branch_taken_w),
        .update_compressed_i(e_record_r[0][96]),
        .update_index_i(e_record_r[0][141:133]),
        .decode_pop_count_i(d_issue_w),
        .decode_data_o(d_data_w),
        .decode_valid_count_o(d_count_w),
        .ib_count_o(ib_count_w),
        .ic_req_valid_o(ic_req_valid_o),
        .ic_req_addr_o(ic_req_addr_o),
        .ic_req_ready_i(ic_req_ready_i),
        .ic_resp_valid_i(ic_resp_valid_i),
        .ic_resp_data_i(ic_resp_data_i),
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
        .read_addr0_i(d_source_w[0]),
        .read_data0_o(d_register_w[0]),
        .read_addr1_i(d_source_w[1]),
        .read_data1_o(d_register_w[1]),
        .read_addr2_i(d_source_w[2]),
        .read_data2_o(d_register_w[2]),
        .read_addr3_i(d_source_w[3]),
        .read_data3_o(d_register_w[3]),
        .write_valid0_i(w_valid_r[0] && w_write_r[0]),
        .write_addr0_i(w_rd_r[0]),
        .write_data0_i(w_result_w[0]),
        .write_valid1_i(w_valid_r[1] && w_write_r[1]),
        .write_addr1_i(w_rd_r[1]),
        .write_data1_i(w_result_w[1])
    );
    edrv32_cpu_csr #(.RVC_EN(RVC_EN)) u_csr (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .access_valid_i(csr_m_access_w || csr_d_access_w),
        .addr_i(csr_addr_w),
        .write_i(csr_write_w),
        .commit_i(m_commit_w[0] && csr_m_access_w),
        .command_i(csr_command_w),
        .write_data_i(csr_operand_w),
        .read_data_o(csr_read_w),
        .illegal_o(csr_illegal_w),
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
    edrv32_cpu_branch u_branch (
        .operand_a_i(e_operand_a_r[0]),
        .operand_b_i(e_operand_b_r[0]),
        .condition_i(e_instr_w[14:12]),
        .taken_o(e_branch_taken_w)
    );
    edrv32_cpu_mul u_mul (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .enable_i(!m_wait_w),
        .valid_i(e_advance_w && e_valid_r[0] && e_class_r[0] == C_MUL),
        .operand_a_i(e_operand_a_r[0]),
        .operand_b_i(e_operand_b_r[0]),
        .operation_i(e_instr_w[13:12]),
        .valid_o(mul_valid_w),
        .result_o(mul_result_w)
    );
    edrv32_cpu_div u_div (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .start_i(div_start_w),
        .operand_a_i(e_operand_a_r[0]),
        .operand_b_i(e_operand_b_r[0]),
        .operation_i(e_instr_w[13:12]),
        .busy_o(div_busy_w),
        .valid_o(div_valid_w),
        .result_o(div_result_w)
    );
    // Closest producer wins, including the younger lane on same-group WAW.
    always @(*) begin
        d_hazard_w = 0;
        for (operand_idx = 0; operand_idx < 4; operand_idx = operand_idx + 1) begin
            d_operand_w[operand_idx] = d_register_w[operand_idx];
            d_bypass_w[operand_idx] = 0;
            d_wait_kind_w[operand_idx] = 0;
            for (producer_idx = 0; producer_idx < 2; producer_idx = producer_idx + 1) begin
                if (w_valid_r[producer_idx] && w_write_r[producer_idx] &&
                    w_rd_r[producer_idx] != 0 &&
                    w_rd_r[producer_idx] == d_source_w[operand_idx]) begin
                    d_operand_w[operand_idx] = w_result_w[producer_idx];
                    d_bypass_w[operand_idx] = 3'd5 + producer_idx[2:0];
                end
            end
            for (producer_idx = 0; producer_idx < 2; producer_idx = producer_idx + 1) begin
                if (m_valid_r[producer_idx] && m_write_r[producer_idx] &&
                    m_rd_r[producer_idx] != 0 &&
                    m_rd_r[producer_idx] == d_source_w[operand_idx]) begin
                    d_operand_w[operand_idx] = m_result_w[producer_idx];
                    d_bypass_w[operand_idx] = 3'd3 + producer_idx[2:0];
                    d_wait_kind_w[operand_idx] = m_class_r[producer_idx] == C_MUL ? 3'd2 : 3'd0;
                end
            end
            for (producer_idx = 0; producer_idx < 2; producer_idx = producer_idx + 1) begin
                if (e_valid_r[producer_idx] && e_write_r[producer_idx] &&
                    e_rd_r[producer_idx] != 0 &&
                    e_rd_r[producer_idx] == d_source_w[operand_idx]) begin
                    d_operand_w[operand_idx] = e_result_w[producer_idx];
                    d_bypass_w[operand_idx] = 3'd1 + producer_idx[2:0];
                    d_wait_kind_w[operand_idx] = e_class_r[producer_idx] == C_LOAD ? 3'd1 :
                        e_class_r[producer_idx] == C_MUL ? 3'd2 :
                        e_class_r[producer_idx] == C_CSR ? 3'd3 : 3'd0;
                end
            end
            d_hazard_w[operand_idx] = d_wait_kind_w[operand_idx] != 0;
        end
    end
    assign d_raw_w = d_write_w[0] && d_rd_w[0] != 0 &&
        ((d_use1_w[1] && d_rs1_w[1] == d_rd_w[0]) ||
        (d_use2_w[1] && d_rs2_w[1] == d_rd_w[0]));
    assign d_pair_type_w = d_class_w[1] <= C_AUIPC &&
        !d_illegal_w[1] && !d_record_w[1][98] && !d_record_w[1][97];
    assign d_serial_w = d_class_w[0] >= C_CSR;
    assign d_csr_wait_w = d_class_w[0] == C_CSR && (e_valid_r != 0 || m_valid_r != 0);
    assign d_available_w = (!e_valid_r[0] || e_advance_w) && !m_wait_w &&
        !backend_redirect_w && !sleep_r;
    always @(*) begin
        d_issue_w = 0;
        d_pair_reason_w = 0;
        if (d_count_w != 0 && d_available_w && !d_csr_wait_w &&
            !(d_use1_w[0] && d_hazard_w[0]) && !(d_use2_w[0] && d_hazard_w[1])) begin
            d_issue_w = 1;
            if (d_count_w >= 2) begin
                if (d_raw_w)
                    d_pair_reason_w = 1;
                else if (d_serial_w || (d_use1_w[1] && d_hazard_w[2]) ||
                    (d_use2_w[1] && d_hazard_w[3]))
                    d_pair_reason_w = 2;
                else if (!d_pair_type_w)
                    d_pair_reason_w = 3;
                else
                    d_issue_w = 2;
            end else
                d_pair_reason_w = 4;
        end
        if (d_redirect_w && d_issue_w == 2)
            d_issue_w = 1;
    end
    assign d_target_w = d_record_w[0][31:0] + d_imm_w[0];
    assign d_redirect_w = d_count_w != 0 && d_available_w && !d_csr_wait_w &&
        !(d_use1_w[0] && d_hazard_w[0]) && !(d_use2_w[0] && d_hazard_w[1]) &&
        d_class_w[0] == C_JAL && !d_record_w[0][99] && !d_record_w[0][98] &&
        !d_record_w[0][97] && !d_illegal_w[0];
    assign e_next_pc_w = e_record_r[0][31:0] + (e_record_r[0][96] ? 32'd2 : 32'd4);
    assign e_address_w = e_operand_a_r[0] + e_imm_r[0];
    assign e_branch_target_w = e_class_r[0] == C_JALR ?
        {e_address_w[31:1], 1'b0} : e_record_r[0][31:0] + e_imm_r[0];
    assign e_control_w = e_class_r[0] == C_BRANCH || e_class_r[0] == C_JAL ||
        e_class_r[0] == C_JALR;
    assign e_taken_w = e_class_r[0] == C_BRANCH ? e_branch_taken_w :
        e_class_r[0] == C_JAL || e_class_r[0] == C_JALR;
    assign e_actual_pc_w = e_class_r[0] == C_BRANCH ?
        (e_branch_taken_w ? e_branch_target_w : e_next_pc_w) :
        (e_class_r[0] == C_JAL || e_class_r[0] == C_JALR ? e_branch_target_w : e_next_pc_w);
    assign e_call_w = (e_class_r[0] == C_JAL || e_class_r[0] == C_JALR) &&
        (e_instr_w[11:7] == 1 || e_instr_w[11:7] == 5);
    assign e_return_w = e_class_r[0] == C_JALR &&
        (e_instr_w[19:15] == 1 || e_instr_w[19:15] == 5) &&
        !e_call_w;
    assign e_type_w = e_call_w ? 3'd3 : e_return_w ? 3'd4 :
        e_class_r[0] == C_JAL ? 3'd1 : e_class_r[0] == C_JALR ? 3'd2 : 3'd0;
    assign e_jump_misaligned_w = !RVC_EN && e_control_w && e_actual_pc_w[1];
    assign e_redirect0_w = e_advance_w && e_valid_r[0] && !e_exception_r[0] &&
        !e_jump_misaligned_w && ((e_control_w &&
        ((e_taken_w != e_record_r[0][100]) || (e_taken_w && e_record_r[0][100] &&
        e_branch_target_w != e_record_r[0][132:101]))) ||
        (!e_control_w && e_record_r[0][100]));
    assign e_second_next_pc_w = e_record_r[1][31:0] +
        (e_record_r[1][96] ? 32'd2 : 32'd4);
    assign e_redirect1_w = e_advance_w && e_valid_r[1] && !e_redirect0_w &&
        !e_exception_r[1] && e_record_r[1][100];
    assign e_redirect_w = e_redirect0_w || e_redirect1_w;
    assign e_redirect_pc_w = e_redirect0_w ? e_actual_pc_w : e_second_next_pc_w;
    assign e_memory_w = e_class_r[0] == C_LOAD || e_class_r[0] == C_STORE;
    assign e_misaligned_w = (e_instr_w[13:12] == 1 && e_address_w[0]) ||
        (e_instr_w[13:12] == 2 && e_address_w[1:0] != 0);
    assign div_start_w = e_valid_r[0] && e_class_r[0] == C_DIV && !div_started_r &&
        m_valid_r == 0 && w_valid_r == 0 && !m_redirect_w;
    assign div_wait_w = e_valid_r[0] && e_class_r[0] == C_DIV && !(div_done_r || div_valid_w);
    assign e_advance_w = e_valid_r[0] && !m_wait_w && !m_redirect_w && !div_wait_w &&
        (!e_memory_w || e_exception_r[0] || e_misaligned_w || dc_req_ready_i);
    // spec 3.3: valid is independent of ready; acceptance advances E into M.
    assign dc_req_valid_o = e_valid_r[0] && !m_wait_w && !m_redirect_w && !div_wait_w &&
        e_memory_w && !e_exception_r[0] && !e_misaligned_w;
    assign dc_req_addr_o = e_address_w;
    assign dc_req_store_o = e_class_r[0] == C_STORE;
    assign dc_req_size_o = e_instr_w[13:12];
    assign dc_store_data_o = m_store_r;
    assign m_memory_w = m_class_r[0] == C_LOAD || m_class_r[0] == C_STORE;
    assign m_fault0_w = m_exception_r[0] ||
        (m_memory_w && dc_resp_valid_i && dc_resp_err_i);
    assign m_ready_w = !m_valid_r[0] || m_fault0_w ||
        (m_memory_w ? dc_resp_valid_i : m_class_r[0] == C_FENCE ? dc_fence_done_i :
        m_class_r[0] == C_FENCE_I ? m_fence_phase_r && ic_inv_done_i : 1'b1);
    assign m_wait_w = m_valid_r[0] && !m_ready_w;
    assign m_advance_w = m_valid_r[0] && m_ready_w;
    assign m_fault1_w = m_valid_r[1] && m_exception_r[1] && m_ready_w;
    assign irq_pending_w = (csr_meie_w && irq_meip_i) ||
        (csr_msie_w && irq_msip_i) || (csr_mtie_w && irq_mtip_i);
    assign irq_cause_w = csr_meie_w && irq_meip_i ? 32'h8000000b :
        csr_msie_w && irq_msip_i ? 32'h80000003 : 32'h80000007;
    assign m_interrupt_w = m_valid_r[0] && csr_global_mie_w && irq_pending_w &&
        !m_fault0_w && !(m_memory_w && (dc_resp_device_i || m_device_started_r)) &&
        m_class_r[0] != C_DIV && !(div_started_r && !div_done_r);
    assign m_trap_w = m_valid_r[0] && (m_fault0_w || m_fault1_w || m_interrupt_w);
    assign m_trap_pc_w = !m_fault0_w && !m_interrupt_w && m_fault1_w ?
        m_record_r[1][31:0] : m_record_r[0][31:0];
    assign m_trap_cause_w = m_fault0_w ? (m_exception_r[0] ? m_cause_r[0] :
        m_class_r[0] == C_STORE ? 32'd7 : 32'd5) : m_interrupt_w ? irq_cause_w : m_cause_r[1];
    assign m_trap_value_w = m_fault0_w ? (m_exception_r[0] ? m_value_r[0] : m_result_r[0]) :
        m_interrupt_w ? 32'd0 : m_value_r[1];
    assign m_commit0_w = m_advance_w && !m_fault0_w && !m_interrupt_w;
    assign m_commit_w = {m_commit0_w && m_valid_r[1] && !m_fault1_w, m_commit0_w};
    assign dc_commit_o = m_valid_r[0] && m_memory_w && !m_fault0_w && !m_interrupt_w &&
        !m_device_started_r && (dc_resp_device_i || dc_resp_valid_i);
    assign dc_kill_o = m_trap_w && m_memory_w && !m_exception_r[0] && !m_device_started_r;
    assign dc_fence_o = m_valid_r[0] && m_class_r[0] == C_FENCE && !m_trap_w;
    assign dc_clean_all_o = m_valid_r[0] && m_class_r[0] == C_FENCE_I &&
        !m_fence_phase_r && !m_trap_w;
    assign m_mret_w = m_commit_w[0] && m_class_r[0] == C_SYSTEM && m_instr_r == 32'h30200073;
    assign m_wfi_w = m_commit_w[0] && m_class_r[0] == C_SYSTEM && m_instr_r == 32'h10500073;
    assign m_fence_i_done_w = m_commit_w[0] && m_class_r[0] == C_FENCE_I;
    assign m_redirect_w = m_trap_w || m_mret_w || m_fence_i_done_w || m_wfi_w;
    assign m_redirect_pc_w = m_trap_w ?
        ({csr_mtvec_w[31:2], 2'b0} +
        (m_interrupt_w && csr_mtvec_w[1:0] == 1 ? {m_trap_cause_w[29:0], 2'b0} : 32'd0)) :
        m_mret_w ? csr_mepc_w :
        m_record_r[0][31:0] + (m_record_r[0][96] ? 32'd2 : 32'd4);
    assign backend_redirect_w = m_redirect_w || e_redirect_w;
    assign backend_redirect_pc_w = m_redirect_w ? m_redirect_pc_w : e_redirect_pc_w;
    assign backend_redirect_ras_w = m_redirect_w ? committed_ras_w :
        e_redirect0_w ? e_record_r[0][178:142] : e_record_r[1][178:142];
    assign csr_m_access_w = m_valid_r[0] && m_class_r[0] == C_CSR;
    assign csr_d_access_w = d_count_w != 0 && d_class_w[0] == C_CSR && !csr_m_access_w;
    assign csr_addr_w = csr_m_access_w ? m_instr_r[31:20] : d_instr_w[0][31:20];
    assign csr_command_w = csr_m_access_w ? m_instr_r[13:12] : d_instr_w[0][13:12];
    assign csr_write_w = csr_m_access_w ? (m_instr_r[13:12] == 1 || m_instr_r[19:15] != 0) :
        (d_instr_w[0][13:12] == 1 || d_instr_w[0][19:15] != 0);
    assign csr_operand_w = csr_m_access_w ? m_csr_data_r :
        (d_instr_w[0][14] ? {27'b0, d_instr_w[0][19:15]} : d_operand_w[0]);
    always @(*) begin
        for (result_idx = 0; result_idx < 2; result_idx = result_idx + 1) begin
            e_result_w[result_idx] = e_alu_w[result_idx];
            case (e_class_r[result_idx])
                C_LUI: e_result_w[result_idx] = e_imm_r[result_idx];
                C_AUIPC: e_result_w[result_idx] =
                    e_record_r[result_idx][31:0] + e_imm_r[result_idx];
                C_JAL, C_JALR: e_result_w[result_idx] = e_record_r[result_idx][31:0] +
                    (e_record_r[result_idx][96] ? 32'd2 : 32'd4);
                C_LOAD, C_STORE: e_result_w[result_idx] =
                    e_operand_a_r[result_idx] + e_imm_r[result_idx];
                C_DIV: e_result_w[result_idx] = div_result_w;
                default: e_result_w[result_idx] = e_alu_w[result_idx];
            endcase
            m_result_w[result_idx] = m_result_r[result_idx];
            if (result_idx == 0) begin
                if (m_class_r[result_idx] == C_CSR)
                    m_result_w[result_idx] = csr_read_w;
                if (m_class_r[result_idx] == C_LOAD) begin
                    case (m_instr_r[14:12])
                        0: m_result_w[result_idx] =
                            {{24{dc_resp_data_i[7]}}, dc_resp_data_i[7:0]};
                        1: m_result_w[result_idx] =
                            {{16{dc_resp_data_i[15]}}, dc_resp_data_i[15:0]};
                        4: m_result_w[result_idx] = {24'b0, dc_resp_data_i[7:0]};
                        5: m_result_w[result_idx] = {16'b0, dc_resp_data_i[15:0]};
                        default: m_result_w[result_idx] = dc_resp_data_i;
                    endcase
                end
            end
        end
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            e_valid_r <= 0;
            m_valid_r <= 0;
            w_valid_r <= 0;
            div_started_r <= 0;
            div_done_r <= 0;
            m_device_started_r <= 0;
            m_fence_phase_r <= 0;
            sleep_r <= 0;
            ic_expect_r <= 0;
            dc_expect_r <= 0;
            ic_miss_r <= 0;
            dc_miss_r <= 0;
        end else begin
            w_valid_r <= m_commit_w;
            if (!m_wait_w)
                m_valid_r <= e_advance_w ? {e_valid_r[1] && !e_redirect0_w, e_valid_r[0]} : 2'b0;
            if (e_advance_w)
                e_valid_r <= 0;
            if (d_issue_w != 0)
                e_valid_r <= d_issue_w == 2 ? 2'b11 : 2'b01;
            if (backend_redirect_w)
                e_valid_r <= 0;
            if (m_redirect_w)
                m_valid_r <= 0;
            if (div_start_w)
                div_started_r <= 1;
            if (div_valid_w)
                div_done_r <= 1;
            if (e_advance_w || backend_redirect_w || d_issue_w != 0) begin
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
            if (m_commit_w[stage_idx]) begin
                w_record_r[stage_idx] <= m_record_r[stage_idx];
                w_result_r[stage_idx] <= m_result_w[stage_idx];
                w_rd_r[stage_idx] <= m_rd_r[stage_idx];
                w_write_r[stage_idx] <= m_write_r[stage_idx];
                w_class_r[stage_idx] <= m_class_r[stage_idx];
            end
            if (e_advance_w) begin
                m_record_r[stage_idx] <= e_record_r[stage_idx];
                m_result_r[stage_idx] <= e_result_w[stage_idx];
                m_rd_r[stage_idx] <= e_rd_r[stage_idx];
                m_write_r[stage_idx] <= e_write_r[stage_idx];
                m_class_r[stage_idx] <= e_class_r[stage_idx];
                m_exception_r[stage_idx] <= e_exception_r[stage_idx];
                m_cause_r[stage_idx] <= e_cause_r[stage_idx];
                m_value_r[stage_idx] <= e_value_r[stage_idx];
                if (stage_idx == 0 && !e_exception_r[stage_idx]) begin
                    if (e_memory_w && e_misaligned_w) begin
                        m_exception_r[stage_idx] <= 1;
                        m_cause_r[stage_idx] <= e_class_r[stage_idx] == C_STORE ? 32'd6 : 32'd4;
                        m_value_r[stage_idx] <= e_address_w;
                    end else if (e_jump_misaligned_w) begin
                        m_exception_r[stage_idx] <= 1;
                        m_cause_r[stage_idx] <= 0;
                        m_value_r[stage_idx] <= e_actual_pc_w;
                    end
                end
            end
            if (d_issue_w != 0) begin
                e_record_r[stage_idx] <= d_record_w[stage_idx];
                if (stage_idx == 0 && d_redirect_w) begin
                    e_record_r[stage_idx][100] <= 1;
                    e_record_r[stage_idx][132:101] <= d_target_w;
                end
                e_class_r[stage_idx] <= d_class_w[stage_idx];
                e_operation_r[stage_idx] <= d_operation_w[stage_idx];
                e_immediate_r[stage_idx] <= d_immediate_w[stage_idx];
                e_imm_r[stage_idx] <= d_imm_w[stage_idx];
                e_operand_a_r[stage_idx] <= d_operand_w[stage_idx * 2];
                e_operand_b_r[stage_idx] <= d_operand_w[stage_idx * 2 + 1];
                e_rd_r[stage_idx] <= d_rd_w[stage_idx];
                e_write_r[stage_idx] <= d_write_w[stage_idx];
                e_exception_r[stage_idx] <= d_record_w[stage_idx][98] ||
                    d_record_w[stage_idx][97] || d_illegal_w[stage_idx] ||
                    (stage_idx == 0 && csr_d_access_w && csr_illegal_w) ||
                    d_instr_w[stage_idx] == 32'h00000073 || d_instr_w[stage_idx] == 32'h00100073;
                e_cause_r[stage_idx] <= d_record_w[stage_idx][98] ? 32'd1 :
                    d_instr_w[stage_idx] == 32'h00000073 ? 32'd11 :
                    d_instr_w[stage_idx] == 32'h00100073 ? 32'd3 : 32'd2;
                e_value_r[stage_idx] <= d_record_w[stage_idx][98] ? d_record_w[stage_idx][31:0] :
                    d_instr_w[stage_idx] == 32'h00000073 || d_instr_w[stage_idx] == 32'h00100073 ?
                    32'd0 : d_record_w[stage_idx][95:64];
            end
        end
        if (e_advance_w) begin
            m_store_r <= e_operand_b_r[0];
            m_instr_r <= e_instr_w;
            m_csr_data_r <= e_instr_w[14] ? {27'b0, e_instr_w[19:15]} : e_operand_a_r[0];
        end
    end
    assign m_call_w = (m_class_r[0] == C_JAL || m_class_r[0] == C_JALR) &&
        (m_instr_r[11:7] == 1 || m_instr_r[11:7] == 5);
    assign m_return_w = m_class_r[0] == C_JALR &&
        (m_instr_r[19:15] == 1 || m_instr_r[19:15] == 5) &&
        !m_call_w;
    assign m_link_w = m_record_r[0][31:0] + (m_record_r[0][96] ? 32'd2 : 32'd4);
    always @(*) begin
        committed_ras_data_w = committed_ras_data_r;
        committed_ras_ptr_w = committed_ras_ptr_r;
        committed_ras_count_w = committed_ras_count_r;
        if (m_commit_w[0]) begin
            if (m_return_w && committed_ras_count_w != 0) begin
                committed_ras_ptr_w = committed_ras_ptr_w - 1'b1;
                committed_ras_count_w = committed_ras_count_w - 1'b1;
            end
            if (m_call_w) begin
                committed_ras_data_w[committed_ras_ptr_w * 32 +: 32] = m_link_w;
                committed_ras_ptr_w = committed_ras_ptr_w + 1'b1;
                if (committed_ras_count_w < 4)
                    committed_ras_count_w = committed_ras_count_w + 1'b1;
            end
        end
    end
    assign committed_top_w = committed_ras_ptr_w - 1'b1;
    assign committed_ras_w = {committed_ras_count_w, committed_ras_ptr_w,
        committed_ras_data_w[committed_top_w * 32 +: 32]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            committed_ras_ptr_r <= 0;
            committed_ras_count_r <= 0;
        end else begin
            committed_ras_ptr_r <= committed_ras_ptr_w;
            committed_ras_count_r <= committed_ras_count_w;
        end
    end
    always @(posedge clk_i) begin
        if (m_commit_w[0] && (m_call_w || m_return_w))
            committed_ras_data_r <= committed_ras_data_w;
    end
    assign retire_count_w = {1'b0, w_valid_r[0]} + {1'b0, w_valid_r[1]};
    // spec 5: a minstret write replaces the count including its own retirement.
    // The write commits in M, one cycle before its instruction retires in W.
    assign w_instret_write_w = w_valid_r[0] && w_class_r[0] == C_CSR &&
        (w_record_r[0][95:84] == 12'hb02 || w_record_r[0][95:84] == 12'hb82) &&
        (w_record_r[0][77:76] == 2'b01 || w_record_r[0][83:79] != 0);
    assign csr_retire_count_w = w_instret_write_w ? 2'b0 : retire_count_w;
    assign ic_miss_start_w = ic_expect_r && !ic_resp_valid_i && !ic_kill_o;
    assign dc_miss_start_w = dc_expect_r && !dc_resp_valid_i && !dc_resp_device_i && !dc_kill_o;
    always @(*) begin
        event_count_w = 0;
        event_count_w[1:0] = {1'b0, retire_count_w == 2};
        event_count_w[3:2] = {1'b0, retire_count_w == 1};
        event_count_w[5:4] = {1'b0, retire_count_w == 0};
        event_count_w[7:6] = {1'b0, w_valid_r[0] &&
            (w_class_r[0] == C_BRANCH || w_class_r[0] == C_JAL || w_class_r[0] == C_JALR)};
        event_count_w[9:8] = {1'b0, d_issue_w == 1 && d_pair_reason_w == 1};
        event_count_w[11:10] = {1'b0, d_issue_w == 1 && d_pair_reason_w == 2};
        event_count_w[13:12] = {1'b0, d_issue_w == 1 && d_pair_reason_w == 3};
        event_count_w[15:14] = {1'b0, d_issue_w == 1 && d_pair_reason_w == 4};
        event_count_w[17:16] = {1'b0, d_count_w != 0 && e_valid_r[0] &&
            e_class_r[0] == C_LOAD && ((d_use1_w[0] && d_rs1_w[0] == e_rd_r[0]) ||
            (d_use2_w[0] && d_rs2_w[0] == e_rd_r[0])) && e_rd_r[0] != 0};
        event_count_w[19:18] = {1'b0, div_wait_w};
        event_count_w[21:20] = {1'b0, m_wait_w && dc_resp_device_i};
        event_count_w[23:22] = {1'b0, d_count_w == 0 && d_available_w};
        event_count_w[25:24] = {1'b0, ic_miss_start_w};
        event_count_w[27:26] = {1'b0, dc_miss_start_w};
        event_count_w[29:28] = {1'b0, dc_wb_event_i};
        event_count_w[31:30] = {1'b0, e_redirect_w || d_redirect_w};
    end
    assign trace_bypass_w = {
        d_issue_w == 2 && d_use2_w[1] ? d_bypass_w[3] : 3'b0,
        d_issue_w == 2 && d_use1_w[1] ? d_bypass_w[2] : 3'b0,
        d_issue_w != 0 && d_use2_w[0] ? d_bypass_w[1] : 3'b0,
        d_issue_w != 0 && d_use1_w[0] ? d_bypass_w[0] : 3'b0};
    always @(*) begin
        trace_redirect_cause_w = 0;
        if (e_redirect_w) begin
            if (e_redirect1_w || !e_control_w)
                trace_redirect_cause_w = 3;
            else if (e_class_r[0] == C_BRANCH && e_record_r[0][100] != e_branch_taken_w)
                trace_redirect_cause_w = 1;
            else
                trace_redirect_cause_w = 2;
        end
        trace_stall_cause_w = div_wait_w ? 3'd5 : 3'd0;
        if (d_count_w != 0 && d_issue_w == 0) begin
            if (d_csr_wait_w)
                trace_stall_cause_w = 4;
            if (d_use1_w[0] && d_wait_kind_w[0] != 0 &&
                (trace_stall_cause_w == 0 || d_wait_kind_w[0] < trace_stall_cause_w))
                trace_stall_cause_w = d_wait_kind_w[0];
            if (d_use2_w[0] && d_wait_kind_w[1] != 0 &&
                (trace_stall_cause_w == 0 || d_wait_kind_w[1] < trace_stall_cause_w))
                trace_stall_cause_w = d_wait_kind_w[1];
        end
    end
    assign trace_valid_w = w_valid_r;
    assign trace_pc_w = {w_record_r[1][31:0], w_record_r[0][31:0]};
    assign trace_instr_w = {w_record_r[1][95:64], w_record_r[0][95:64]};
    assign trace_rd_w = {w_write_r[1] ? w_rd_r[1] : 5'b0,
        w_write_r[0] ? w_rd_r[0] : 5'b0};
    assign trace_rd_data_w = {w_result_w[1], w_result_w[0]};
    assign trace_trap_w = m_trap_w;
    assign trace_cause_w = m_trap_cause_w;
    assign debug_o = {trace_valid_w[0] ? trace_pc_w[31:0] :
        trace_valid_w[1] ? trace_pc_w[63:32] : 32'b0,
        2'b0, sleep_r, dc_miss_r, ic_miss_r, m_wait_w && dc_resp_device_i,
        div_busy_w, event_count_w[16], d_pair_reason_w, retire_count_w,
        trace_trap_w, d_redirect_w, e_redirect_w, fetch_wait_w, m_wait_w,
        m_wait_w || div_wait_w || (d_count_w != 0 && d_issue_w == 0),
        w_valid_r, m_valid_r, e_valid_r,
        d_count_w >= 2, d_count_w != 0, ib_count_w, f2_valid_w, f1_valid_w};
endmodule
