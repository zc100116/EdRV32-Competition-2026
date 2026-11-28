// File: edrv32_cpu2_commit.v
// Spec: cpu-v2-spec 3.5, 5.1, 5.6, 6; fpu-spec 4, 5.5.
// Description: Retire an ordered prefix, authorize memory side effects and
// serialize traps, interrupt boundaries, fences, MRET and WFI.
// Clock domain: clk_sys.
module edrv32_cpu2_commit #(
    parameter ISSUE_WIDTH = 2,
    parameter [31:0] FPU_FORMAT = "NONE"
) (
    input wire clk_i,
    input wire rst_n_i,
    input wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] head0_tag_i,
    input wire [31:0] head0_pc_i,
    input wire [31:0] head0_next_pc_i,
    input wire [3:0] head0_kind_i,
    input wire [31:0] head0_trace_instr_i,
    input wire [4:0] head0_rd_i,
    input wire [1:0] head0_dest_i,
    input wire head0_store_i,
    input wire head0_divide_i,
    input wire head0_double_beat_i,
    input wire head0_valid_i,
    input wire head0_done_i,
    input wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] head0_data_i,
    input wire [4:0] head0_flags_i,
    input wire head0_exception_i,
    input wire [3:0] head0_cause_i,
    input wire [31:0] head0_tval_i,
    input wire head0_device_i,
    input wire [31:0] head0_mem_addr_i,
    input wire [63:0] head0_mem_data_i,
    input wire [7:0] head0_mem_mask_i,
    output wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] wb0_tag_o,
    output wire wb0_valid_copy_o,
    output wire [4:0] wb0_rd_copy_o,
    output wire wb0_valid_o,
    output wire [4:0] wb0_rd_o,
    output wire [31:0] wb0_data_o,
    input wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] head1_tag_i,
    input wire [31:0] head1_pc_i,
    input wire [31:0] head1_next_pc_i,
    input wire [3:0] head1_kind_i,
    input wire [31:0] head1_trace_instr_i,
    input wire [4:0] head1_rd_i,
    input wire [1:0] head1_dest_i,
    input wire head1_store_i,
    input wire head1_divide_i,
    input wire head1_double_beat_i,
    input wire head1_valid_i,
    input wire head1_done_i,
    input wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] head1_data_i,
    input wire [4:0] head1_flags_i,
    input wire head1_exception_i,
    input wire [3:0] head1_cause_i,
    input wire [31:0] head1_tval_i,
    input wire head1_device_i,
    input wire [31:0] head1_mem_addr_i,
    input wire [63:0] head1_mem_data_i,
    input wire [7:0] head1_mem_mask_i,
    output wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] wb1_tag_o,
    output wire wb1_valid_copy_o,
    output wire [4:0] wb1_rd_copy_o,
    output wire wb1_valid_o,
    output wire [4:0] wb1_rd_o,
    output wire [31:0] wb1_data_o,
    input wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] age_head_i,
    input wire cancel_valid_i,
    input wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] cancel_tag_i,
    input wire branch_redirect_valid_i,
    input wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] branch_redirect_tag_i,
    input wire [31:0] branch_redirect_pc_i,
    output wire [1:0] retire_count_o,
    output wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] fp_wb_tag_o,
    output wire fp_wb_valid_o,
    output wire [4:0] fp_wb_rd_o,
    output wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] fp_wb_data_o,
    output wire commit_lsu_valid_o,
    input wire commit_lsu_ready_i,
    output wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] commit_lsu_tag_o,
    input wire commit_lsu_done_valid_i,
    output wire commit_lsu_done_ready_o,
    input wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] commit_lsu_done_tag_i,
    input wire commit_lsu_done_error_i,
    input wire [31:0] commit_lsu_done_fault_addr_i,
    input wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] commit_lsu_done_data_i,
    output wire csr_commit_valid_o,
    output wire fp_commit_flags_valid_o,
    output wire [4:0] fp_commit_flags_o,
    output wire fp_commit_write_o,
    input wire irq_pending_i,
    input wire [31:0] irq_cause_i,
    input wire irq_wake_i,
    input wire [31:0] trap_target_i,
    input wire [31:0] csr_mepc_i,
    output wire mret_valid_o,
    output wire trap_valid_o,
    output wire [31:0] trap_pc_o,
    output wire [31:0] trap_cause_o,
    output wire [31:0] trap_tval_o,
    output wire commit_cancel_valid_o,
    output wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] commit_cancel_tag_o,
    output wire commit_redirect_valid_o,
    output wire [31:0] commit_redirect_pc_o,
    output wire fetch_stop_o,
    output wire dc_fence_valid_o,
    input wire dc_fence_ready_i,
    output wire dc_fence_clean_all_o,
    input wire dc_fence_done_i,
    output wire ic_inv_valid_o,
    input wire ic_inv_ready_i,
    input wire ic_inv_done_i,
    output wire [1:0] counter_retire_count_o,
    output wire [1:0] hpm_branch_count_o
);
    // Commit-only classification: four bits cover the nine mutually exclusive kinds.
    localparam [3:0] C_FENCE = 4'd1;
    localparam [3:0] C_FENCE_I = 4'd2;
    localparam [3:0] C_MRET = 4'd4;
    localparam [3:0] C_WFI = 4'd5;
    localparam [3:0] C_CSR = 4'd6;
    localparam [3:0] C_CONTROL = 4'd7;
    localparam [3:0] C_FP = 4'd8;
    localparam T = FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2;
    localparam B = FPU_FORMAT == "FD" ? 64 : 32;
    localparam S_IDLE = 3'd0;
    localparam S_LSU = 3'd1;
    localparam S_DC = 3'd2;
    localparam S_IC_REQ = 3'd3;
    localparam S_IC = 3'd4;
    localparam S_FENCE_DONE = 3'd5;
    wire wb0_valid_w;
    wire [4:0] wb0_rd_w;
    wire [31:0] wb0_data_w;
    wire wb1_valid_w;
    wire [4:0] wb1_rd_w;
    wire [31:0] wb1_data_w;
    wire fp_wb_valid_w;
    wire [4:0] fp_wb_rd_w;
    wire [B-1:0] fp_wb_data_w;
    reg [2:0] state_r;
    reg [31:0] next_pc_r;
    reg stop_r;
    reg redirect_r;
    reg [31:0] redirect_pc_r;
    wire [T-1:0] cancel_distance_w;
    wire [T-1:0] head0_distance_w;
    wire [T-1:0] head1_distance_w;
    wire head0_cancel_w;
    wire head1_cancel_w;
    wire memory0_w;
    wire memory1_w;
    wire fence0_w;
    wire fence_i0_w;
    wire system0_w;
    wire system1_w;
    wire mret0_w;
    wire wfi0_w;
    wire indivisible_w;
    wire lsu_done_w;
    wire lsu_error_w;
    wire irq_take_w;
    wire fault0_w;
    wire fault1_w;
    wire retire0_w;
    wire retire1_w;
    wire fp_int1_w;
    wire fp_int1_retire_w;
    wire [B-1:0] retire_data0_w;
    wire [B-1:0] retire_data1_w;
    wire redirect_request_w;
    wire control0_w;
    wire control1_w;
    wire [31:0] redirect_target_w;
    assign cancel_distance_w = cancel_tag_i - age_head_i;
    assign head0_distance_w = head0_tag_i - age_head_i;
    assign head1_distance_w = head1_tag_i - age_head_i;
    // Commit cancellation is produced here; only branch cancellation can suppress heads.
    // Using cancel_valid here would feed the trap decision back into itself.
    assign head0_cancel_w = branch_redirect_valid_i &&
        head0_distance_w > (branch_redirect_tag_i - age_head_i);
    assign head1_cancel_w = branch_redirect_valid_i &&
        head1_distance_w > (branch_redirect_tag_i - age_head_i);
    assign memory0_w = head0_store_i || head0_device_i || head0_double_beat_i;
    assign memory1_w = head1_store_i || head1_device_i || head1_double_beat_i;
    assign fence0_w = head0_kind_i == C_FENCE || head0_kind_i == C_FENCE_I;
    assign fence_i0_w = head0_kind_i == C_FENCE_I;
    assign system0_w = head0_kind_i >= C_FENCE && head0_kind_i <= C_CSR;
    assign system1_w = head1_kind_i >= C_FENCE && head1_kind_i <= C_CSR;
    assign mret0_w = head0_kind_i == C_MRET;
    assign wfi0_w = head0_kind_i == C_WFI;
    assign indivisible_w =
        (head0_valid_i && (head0_divide_i || head0_double_beat_i)) ||
        state_r == S_LSU || (state_r != S_IDLE && fence_i0_w);
    assign lsu_done_w = state_r == S_LSU && commit_lsu_done_valid_i;
    assign lsu_error_w = lsu_done_w && commit_lsu_done_error_i;
    assign fault0_w = head0_valid_i && !head0_cancel_w &&
        ((head0_done_i && head0_exception_i) || lsu_error_w);
    assign irq_take_w = irq_pending_i && !fault0_w && !indivisible_w;
    assign retire0_w = head0_valid_i && head0_done_i && !head0_cancel_w &&
        !fault0_w && !irq_take_w && !stop_r &&
        (memory0_w ? lsu_done_w : fence0_w ? state_r == S_FENCE_DONE : 1'b1);
    assign fault1_w = ISSUE_WIDTH == 2 && retire0_w && !system0_w && head1_valid_i &&
        head1_done_i && !head1_cancel_w && head1_exception_i;
    assign fp_int1_w = head1_dest_i == 2'd1 && head1_kind_i == C_FP;
    assign fp_int1_retire_w = retire1_w && fp_int1_w;
    assign retire1_w = ISSUE_WIDTH == 2 && retire0_w && !system0_w &&
        head1_valid_i && head1_done_i && !head1_cancel_w && !head1_exception_i &&
        !memory1_w && !system1_w &&
        !(head0_dest_i == 2'd2 && head1_dest_i == 2'd2) &&
        !(fp_int1_w && head0_dest_i == 2'd1 && head0_rd_i != 0);
    assign retire_count_o = {1'b0, retire0_w} + {1'b0, retire1_w};
    assign counter_retire_count_o = retire_count_o;
    assign retire_data0_w = head0_device_i ? commit_lsu_done_data_i : head0_data_i;
    assign retire_data1_w = head1_data_i;
    // FP-to-integer results always occupy integer port zero, preserving port one.
    assign wb0_valid_w = (retire0_w && head0_dest_i == 2'd1 && head0_rd_i != 0) ||
        (fp_int1_retire_w && head1_rd_i != 0);
    assign wb0_rd_w = fp_int1_retire_w ? head1_rd_i : head0_rd_i;
    assign wb0_data_w = fp_int1_retire_w ? retire_data1_w[31:0] : retire_data0_w[31:0];
    assign wb1_valid_w = retire1_w && !fp_int1_w && head1_dest_i == 2'd1 && head1_rd_i != 0;
    assign wb1_rd_w = ISSUE_WIDTH == 2 ? head1_rd_i : 5'b0;
    assign wb1_data_w = ISSUE_WIDTH == 2 ? retire_data1_w[31:0] : 32'b0;
    assign fp_wb_valid_w = FPU_FORMAT != "NONE" &&
        ((retire0_w && head0_dest_i == 2'd2) || (retire1_w && head1_dest_i == 2'd2));
    assign fp_wb_rd_w = FPU_FORMAT == "NONE" ? 5'b0 :
        (retire1_w && head1_dest_i == 2'd2 ? head1_rd_i : head0_rd_i);
    assign fp_wb_data_w = FPU_FORMAT == "NONE" ? {B{1'b0}} :
        (retire1_w && head1_dest_i == 2'd2 ? retire_data1_w : retire_data0_w);
    assign fp_commit_flags_valid_o = FPU_FORMAT != "NONE" && (retire0_w || retire1_w);
    assign fp_commit_flags_o = FPU_FORMAT == "NONE" ? 5'b0 :
        ({5{retire0_w}} & head0_flags_i) | ({5{retire1_w}} & head1_flags_i);
    assign fp_commit_write_o = fp_wb_valid_w;
    assign csr_commit_valid_o = retire0_w && head0_kind_i == C_CSR;
    assign mret_valid_o = retire0_w && mret0_w;
    assign commit_lsu_valid_o = state_r == S_IDLE && head0_valid_i && head0_done_i &&
        memory0_w && !fault0_w && !irq_take_w && !head0_cancel_w;
    assign commit_lsu_tag_o = head0_tag_i;
    assign commit_lsu_done_ready_o = state_r == S_LSU;
    assign dc_fence_valid_o = state_r == S_IDLE && head0_valid_i && head0_done_i &&
        fence0_w && !fault0_w && !irq_take_w && !head0_cancel_w;
    assign dc_fence_clean_all_o = fence_i0_w;
    assign ic_inv_valid_o = state_r == S_IC_REQ;
    assign trap_valid_o = fault0_w || irq_take_w || fault1_w;
    assign trap_pc_o = fault1_w ? head1_pc_i : head0_valid_i ? head0_pc_i : next_pc_r;
    assign trap_cause_o = fault0_w ? (lsu_error_w ?
        (head0_store_i ? 32'd7 : 32'd5) : {28'b0, head0_cause_i}) :
        irq_take_w ? irq_cause_i : {28'b0, head1_cause_i};
    assign trap_tval_o = fault0_w ?
        (lsu_error_w ? commit_lsu_done_fault_addr_i : head0_tval_i) :
        irq_take_w ? 32'b0 : head1_tval_i;
    assign commit_cancel_valid_o = redirect_request_w;
    assign commit_cancel_tag_o = trap_valid_o ?
        (fault1_w ? head1_tag_i : age_head_i) : head0_tag_i + 1'b1;
    assign redirect_request_w = trap_valid_o || mret_valid_o ||
        (retire0_w && (fence_i0_w || wfi0_w));
    assign redirect_target_w = trap_valid_o ? trap_target_i :
        mret_valid_o ? csr_mepc_i : head0_pc_i + 32'd4;
    assign commit_redirect_valid_o = redirect_r;
    assign commit_redirect_pc_o = redirect_pc_r;
    assign fetch_stop_o = stop_r;
    assign control0_w = head0_kind_i == C_CONTROL;
    assign control1_w = head1_kind_i == C_CONTROL;
    assign hpm_branch_count_o = {1'b0, retire0_w && control0_w} +
        {1'b0, retire1_w && control1_w};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            stop_r <= 1'b0;
            redirect_r <= 1'b0;
            next_pc_r <= 32'b0;
        end else begin
            redirect_r <= redirect_request_w;
            if (irq_wake_i)
                stop_r <= 1'b0;
            if (retire0_w && wfi0_w)
                stop_r <= !irq_wake_i;
            if (retire0_w)
                next_pc_r <= control0_w ? head0_next_pc_i : head0_pc_i + 32'd4;
            if (retire1_w)
                next_pc_r <= control1_w ? head1_next_pc_i : head1_pc_i + 32'd4;
            if (branch_redirect_valid_i)
                next_pc_r <= branch_redirect_pc_i;
            if (redirect_request_w)
                next_pc_r <= redirect_target_w;
            case (state_r)
                S_IDLE: begin
                    if (commit_lsu_valid_o && commit_lsu_ready_i)
                        state_r <= S_LSU;
                    if (dc_fence_valid_o && dc_fence_ready_i)
                        state_r <= S_DC;
                end
                S_LSU: if (lsu_done_w) state_r <= S_IDLE;
                S_DC: if (dc_fence_done_i)
                    state_r <= fence_i0_w ? S_IC_REQ : S_FENCE_DONE;
                S_IC_REQ: if (ic_inv_ready_i) state_r <= S_IC;
                S_IC: if (ic_inv_done_i) state_r <= S_FENCE_DONE;
                S_FENCE_DONE: if (retire0_w) state_r <= S_IDLE;
                default: begin end
            endcase
            begin
                if (trap_valid_o)
                    state_r <= S_IDLE;
            end
        end
    end
    always @(posedge clk_i) begin
        if (redirect_request_w)
            redirect_pc_r <= redirect_target_w;
    end
    wire [1:0] wb_valid_w;
    wire [4:0] wb_rd_w [0:1];
    wire [31:0] wb_data_w [0:1];
    wire [T-1:0] wb_tag_w [0:1];
    wire [1:0] wb_valid_copy_w;
    wire [4:0] wb_rd_copy_w [0:1];
    assign wb0_valid_o = wb_valid_w[0];
    assign wb0_rd_o = wb_rd_w[0];
    assign wb0_data_o = wb_data_w[0];
    assign wb0_tag_o = wb_tag_w[0];
    assign wb0_valid_copy_o = wb_valid_copy_w[0];
    assign wb0_rd_copy_o = wb_rd_copy_w[0];
    assign wb1_valid_o = wb_valid_w[1];
    assign wb1_rd_o = wb_rd_w[1];
    assign wb1_data_o = wb_data_w[1];
    assign wb1_tag_o = wb_tag_w[1];
    assign wb1_valid_copy_o = wb_valid_copy_w[1];
    assign wb1_rd_copy_o = wb_rd_copy_w[1];
    // Frozen WB boundary: retirement captures here; RF/LVT and operand waits
    // consume these registered ports on the following edge, before tag reuse can complete.
    genvar wb_slot;
    generate
        localparam WB_SLOTS = 2;
        for (wb_slot = 0; wb_slot < WB_SLOTS; wb_slot = wb_slot + 1) begin : g_wb
            localparam PRESENT = wb_slot < ISSUE_WIDTH;
            if (PRESENT) begin : g_present
                (* keep = "true", syn_preserve = 1 *) reg valid_r;
                (* keep = "true", syn_preserve = 1 *) reg [4:0] rd_r;
                reg [31:0] data_r;
                reg [T-1:0] tag_r;
                wire valid_w;
                wire [4:0] rd_w;
                wire [31:0] data_w;
                wire [T-1:0] tag_w;
                assign valid_w = wb_slot == 0 ? wb0_valid_w : wb1_valid_w;
                assign rd_w = wb_slot == 0 ? wb0_rd_w : wb1_rd_w;
                assign data_w = wb_slot == 0 ? wb0_data_w : wb1_data_w;
                assign tag_w = wb_slot == 0 ?
                    (fp_int1_retire_w ? head1_tag_i : head0_tag_i) : head1_tag_i;
                assign wb_valid_w[wb_slot] = valid_r;
                assign wb_rd_w[wb_slot] = rd_r;
                assign wb_data_w[wb_slot] = data_r;
                assign wb_tag_w[wb_slot] = tag_r;
                always @(posedge clk_i or negedge rst_n_i) begin
                    if (!rst_n_i)
                        valid_r <= 1'b0;
                    else
                        valid_r <= valid_w;
                end
                always @(posedge clk_i) begin
                    if (valid_w) begin
                        rd_r <= rd_w;
                        data_r <= data_w;
                        tag_r <= tag_w;
                    end
                end
                if (ISSUE_WIDTH == 2) begin : g_copy
                    (* keep = "true", syn_preserve = 1 *) reg valid_copy_r;
                    (* keep = "true", syn_preserve = 1 *) reg [4:0] rd_copy_r;
                    assign wb_valid_copy_w[wb_slot] = valid_copy_r;
                    assign wb_rd_copy_w[wb_slot] = rd_copy_r;
                    always @(posedge clk_i or negedge rst_n_i) begin
                        if (!rst_n_i)
                            valid_copy_r <= 1'b0;
                        else
                            valid_copy_r <= valid_w;
                    end
                    always @(posedge clk_i) begin
                        if (valid_w)
                            rd_copy_r <= rd_w;
                    end
                end else begin : g_no_copy
                    assign wb_valid_copy_w[wb_slot] = 1'b0;
                    assign wb_rd_copy_w[wb_slot] = 5'b0;
                end
            end else begin : g_absent
                assign wb_valid_w[wb_slot] = 1'b0;
                assign wb_rd_w[wb_slot] = 5'b0;
                assign wb_data_w[wb_slot] = 32'b0;
                assign wb_tag_w[wb_slot] = {T{1'b0}};
                assign wb_valid_copy_w[wb_slot] = 1'b0;
                assign wb_rd_copy_w[wb_slot] = 5'b0;
            end
        end
        if (FPU_FORMAT != "NONE") begin : g_fp_wb
            reg valid_r;
            reg [4:0] rd_r;
            reg [B-1:0] data_r;
            reg [T-1:0] tag_r;
            assign fp_wb_valid_o = valid_r;
            assign fp_wb_rd_o = rd_r;
            assign fp_wb_data_o = data_r;
            assign fp_wb_tag_o = tag_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i)
                    valid_r <= 1'b0;
                else
                    valid_r <= fp_wb_valid_w;
            end
            always @(posedge clk_i) begin
                if (fp_wb_valid_w) begin
                    rd_r <= fp_wb_rd_w;
                    data_r <= fp_wb_data_w;
                    tag_r <= retire1_w && head1_dest_i == 2'd2 ? head1_tag_i : head0_tag_i;
                end
            end
        end else begin : g_no_fp_wb
            assign fp_wb_valid_o = 1'b0;
            assign fp_wb_rd_o = 5'b0;
            assign fp_wb_data_o = {B{1'b0}};
            assign fp_wb_tag_o = {T{1'b0}};
        end
    endgenerate
    wire [63:0] device_trace_data_w;
    wire [63:0] device_done_data_w;
    assign device_done_data_w = {{(64-B){1'b0}}, commit_lsu_done_data_i};
    genvar trace_byte;
    generate
        for (trace_byte = 0; trace_byte < 8; trace_byte = trace_byte + 1) begin : g_trace_byte
            assign device_trace_data_w[trace_byte*8 +: 8] =
                {8{head0_mem_mask_i[trace_byte]}} & device_done_data_w[trace_byte*8 +: 8];
        end
    endgenerate
    wire [ISSUE_WIDTH-1:0] trace_valid_w;
    wire [32*ISSUE_WIDTH-1:0] trace_pc_w;
    wire [32*ISSUE_WIDTH-1:0] trace_instr_w;
    wire [5*ISSUE_WIDTH-1:0] trace_rd_w;
    wire [2*ISSUE_WIDTH-1:0] trace_rd_domain_w;
    wire [64*ISSUE_WIDTH-1:0] trace_rd_data_w;
    wire [5*ISSUE_WIDTH-1:0] trace_flags_w;
    wire [ISSUE_WIDTH-1:0] trace_mem_valid_w;
    wire [ISSUE_WIDTH-1:0] trace_mem_store_w;
    wire [32*ISSUE_WIDTH-1:0] trace_mem_addr_w;
    wire [64*ISSUE_WIDTH-1:0] trace_mem_data_w;
    wire [8*ISSUE_WIDTH-1:0] trace_mem_mask_w;
    wire trace_trap_w;
    wire [31:0] trace_cause_w;
    wire [31:0] trace_trap_pc_w;
    wire [31:0] trace_tval_w;
    assign trace_valid_w[0] = retire0_w;
    assign trace_pc_w[31:0] = head0_pc_i;
    assign trace_instr_w[31:0] = head0_trace_instr_i;
    assign trace_rd_w[4:0] = head0_rd_i;
    // x0 integer writes report domain 0 (no write); FP f0 stays 2.
    assign trace_rd_domain_w[1:0] =
        (head0_dest_i == 2'd1 && head0_rd_i == 5'd0) ? 2'd0 : head0_dest_i;
    assign trace_rd_data_w[63:0] = {{(64-B){1'b0}}, retire_data0_w};
    assign trace_flags_w[4:0] = head0_flags_i;
    assign trace_mem_valid_w[0] = retire0_w && (head0_trace_instr_i[6:0] == 7'h03 ||
        head0_trace_instr_i[6:0] == 7'h07 || head0_trace_instr_i[6:0] == 7'h23 ||
        head0_trace_instr_i[6:0] == 7'h27);
    assign trace_mem_store_w[0] = head0_store_i;
    assign trace_mem_addr_w[31:0] = head0_mem_addr_i;
    assign trace_mem_data_w[63:0] = head0_device_i && !head0_store_i ?
        device_trace_data_w : head0_mem_data_i;
    assign trace_mem_mask_w[7:0] = head0_mem_mask_i;
    generate
        if (ISSUE_WIDTH == 2) begin : g_trace1
            assign trace_valid_w[1] = retire1_w;
            assign trace_pc_w[63:32] = head1_pc_i;
            assign trace_instr_w[63:32] = head1_trace_instr_i;
            assign trace_rd_w[9:5] = head1_rd_i;
            // x0 integer writes report domain 0 (no write); FP f0 stays 2.
            assign trace_rd_domain_w[3:2] =
                (head1_dest_i == 2'd1 && head1_rd_i == 5'd0) ? 2'd0 : head1_dest_i;
            assign trace_rd_data_w[127:64] = {{(64-B){1'b0}}, retire_data1_w};
            assign trace_flags_w[9:5] = head1_flags_i;
            assign trace_mem_valid_w[1] = retire1_w && (head1_trace_instr_i[6:0] == 7'h03 ||
                head1_trace_instr_i[6:0] == 7'h07 || head1_trace_instr_i[6:0] == 7'h23 ||
                head1_trace_instr_i[6:0] == 7'h27);
            assign trace_mem_store_w[1] = head1_store_i;
            assign trace_mem_addr_w[63:32] = head1_mem_addr_i;
            assign trace_mem_data_w[127:64] = head1_mem_data_i;
            assign trace_mem_mask_w[15:8] = head1_mem_mask_i;
        end
    endgenerate
    assign trace_trap_w = trap_valid_o;
    assign trace_cause_w = trap_cause_o;
    assign trace_trap_pc_w = trap_pc_o;
    assign trace_tval_w = trap_tval_o;
    // Unused configuration fields and internal architectural observation wires.
    /* verilator lint_off UNUSEDSIGNAL */
    wire unused_w = ^{
        head1_trace_instr_i, head1_mem_addr_i, head1_mem_data_i, head1_mem_mask_i,
        fp_wb_rd_w, fp_wb_data_w,
        head1_divide_i,
        cancel_valid_i,
        commit_lsu_done_tag_i,
        cancel_distance_w,
        trace_valid_w,
        trace_pc_w,
        trace_instr_w,
        trace_rd_w,
        trace_rd_domain_w,
        trace_rd_data_w,
        trace_flags_w,
        trace_mem_valid_w,
        trace_mem_store_w,
        trace_mem_addr_w,
        trace_mem_data_w,
        trace_mem_mask_w,
        trace_trap_w,
        trace_cause_w,
        trace_trap_pc_w,
        trace_tval_w
    };
    /* verilator lint_on UNUSEDSIGNAL */
endmodule
