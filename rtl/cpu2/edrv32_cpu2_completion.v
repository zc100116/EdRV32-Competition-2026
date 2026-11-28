// File: edrv32_cpu2_completion.v
// Spec: cpu-v2-spec 3.2, 3.4, 3.5, 5.1, 5.6; fpu-spec 5.4.
// Description: Shared in-order allocation records and age-arbitrated result banks.
// Replicated asynchronous LUTRAM data and PC banks for every configuration.
// Clock domain: clk_sys.
module edrv32_cpu2_completion #(
    parameter ISSUE_WIDTH = 2,
    parameter [31:0] FPU_FORMAT = "NONE"
) (
    input wire clk_i,
    input wire rst_n_i,
    input wire allocate_valid_i,
    input wire [1:0] allocate_count_i,
    output wire allocate_ready_o,
    output wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?5:4)-1:0] allocate_credit_o,
    input wire [1:0] retire_count_i,
    input wire commit_cancel_valid_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] commit_cancel_tag_i,
    input wire branch_redirect_valid_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] branch_redirect_tag_i,
    input wire [31:0] branch_redirect_pc_i,
    output wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] age_head_o,
    output wire cancel_valid_o,
    output wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] cancel_tag_o,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] allocate0_tag_i,
    input wire [31:0] allocate0_pc_i,
    input wire [31:0] allocate0_instr_i,
    input wire [4:0] allocate0_rd_i,
    input wire [1:0] allocate0_dest_i,
    input wire [31:0] allocate0_csr_src_i,
    input wire allocate0_store_i,
    input wire allocate0_divide_i,
    input wire allocate0_double_beat_i,
    output wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] head0_tag_o,
    output wire [31:0] head0_pc_o,
    output wire [31:0] head0_next_pc_o,
    output wire [3:0] head0_kind_o,
    output wire [31:0] head0_trace_instr_o,
    output wire [4:0] head0_rd_o,
    output wire [1:0] head0_dest_o,
    output wire head0_store_o,
    output wire head0_divide_o,
    output wire head0_double_beat_o,
    output wire head0_valid_o,
    output wire head0_done_o,
    output wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] head0_data_o,
    output wire [4:0] head0_flags_o,
    output wire head0_exception_o,
    output wire [3:0] head0_cause_o,
    output wire [31:0] head0_tval_o,
    output wire head0_device_o,
    output wire [31:0] head0_mem_addr_o,
    output wire [63:0] head0_mem_data_o,
    output wire [7:0] head0_mem_mask_o,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] allocate1_tag_i,
    input wire [31:0] allocate1_pc_i,
    input wire [31:0] allocate1_instr_i,
    input wire [4:0] allocate1_rd_i,
    input wire [1:0] allocate1_dest_i,
    input wire [31:0] allocate1_csr_src_i,
    input wire allocate1_store_i,
    input wire allocate1_divide_i,
    input wire allocate1_double_beat_i,
    output wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] head1_tag_o,
    output wire [31:0] head1_pc_o,
    output wire [31:0] head1_next_pc_o,
    output wire [3:0] head1_kind_o,
    output wire [31:0] head1_trace_instr_o,
    output wire [4:0] head1_rd_o,
    output wire [1:0] head1_dest_o,
    output wire head1_store_o,
    output wire head1_divide_o,
    output wire head1_double_beat_o,
    output wire head1_valid_o,
    output wire head1_done_o,
    output wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] head1_data_o,
    output wire [4:0] head1_flags_o,
    output wire head1_exception_o,
    output wire [3:0] head1_cause_o,
    output wire [31:0] head1_tval_o,
    output wire head1_device_o,
    output wire [31:0] head1_mem_addr_o,
    output wire [63:0] head1_mem_data_o,
    output wire [7:0] head1_mem_mask_o,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] source0_tag_i,
    input wire source0_valid_i,
    input wire source0_domain_i,
    output wire source0_ready_o,
    output wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] source0_data_o,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] source1_tag_i,
    input wire source1_valid_i,
    input wire source1_domain_i,
    output wire source1_ready_o,
    output wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] source1_data_o,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] source2_tag_i,
    input wire source2_valid_i,
    input wire source2_domain_i,
    output wire source2_ready_o,
    output wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] source2_data_o,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] source3_tag_i,
    input wire source3_valid_i,
    input wire source3_domain_i,
    output wire source3_ready_o,
    output wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] source3_data_o,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] source4_tag_i,
    input wire source4_valid_i,
    input wire source4_domain_i,
    output wire source4_ready_o,
    output wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] source4_data_o,
    input wire alu0_complete_valid_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] alu0_complete_tag_i,
    input wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] alu0_complete_data_i,
    input wire [4:0] alu0_complete_flags_i,
    input wire alu0_complete_exception_i,
    input wire [3:0] alu0_complete_cause_i,
    input wire [31:0] alu0_complete_tval_i,
    output wire alu0_complete_ready_o,
    input wire alu1_complete_valid_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] alu1_complete_tag_i,
    input wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] alu1_complete_data_i,
    input wire [4:0] alu1_complete_flags_i,
    input wire alu1_complete_exception_i,
    input wire [3:0] alu1_complete_cause_i,
    input wire [31:0] alu1_complete_tval_i,
    output wire alu1_complete_ready_o,
    input wire [31:0] branch_complete_next_pc_i,
    input wire branch_complete_valid_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] branch_complete_tag_i,
    input wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] branch_complete_data_i,
    input wire [4:0] branch_complete_flags_i,
    input wire branch_complete_exception_i,
    input wire [3:0] branch_complete_cause_i,
    input wire [31:0] branch_complete_tval_i,
    output wire branch_complete_ready_o,
    input wire mul_complete_valid_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] mul_complete_tag_i,
    input wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] mul_complete_data_i,
    input wire [4:0] mul_complete_flags_i,
    input wire mul_complete_exception_i,
    input wire [3:0] mul_complete_cause_i,
    input wire [31:0] mul_complete_tval_i,
    output wire mul_complete_ready_o,
    input wire div_complete_valid_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] div_complete_tag_i,
    input wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] div_complete_data_i,
    input wire [4:0] div_complete_flags_i,
    input wire div_complete_exception_i,
    input wire [3:0] div_complete_cause_i,
    input wire [31:0] div_complete_tval_i,
    output wire div_complete_ready_o,
    input wire lsu_complete_valid_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] lsu_complete_tag_i,
    input wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] lsu_complete_data_i,
    input wire [4:0] lsu_complete_flags_i,
    input wire lsu_complete_exception_i,
    input wire [3:0] lsu_complete_cause_i,
    input wire [31:0] lsu_complete_tval_i,
    output wire lsu_complete_ready_o,
    input wire csr_complete_valid_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] csr_complete_tag_i,
    input wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] csr_complete_data_i,
    input wire [4:0] csr_complete_flags_i,
    input wire csr_complete_exception_i,
    input wire [3:0] csr_complete_cause_i,
    input wire [31:0] csr_complete_tval_i,
    output wire csr_complete_ready_o,
    input wire fp_resp_valid_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] fp_resp_tag_i,
    input wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] fp_resp_data_i,
    input wire [4:0] fp_resp_flags_i,
    output wire fp_resp_ready_o,
    input wire decode_complete_valid_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] decode_complete_tag_i,
    input wire decode_complete_exception_i,
    input wire [3:0] decode_complete_cause_i,
    input wire [31:0] decode_complete_tval_i,
    output wire decode_complete_ready_o,
    input wire fp_resp_int_dest_i,
    input wire lsu_complete_device_i,
    input wire [31:0] lsu_complete_mem_addr_i,
    input wire [63:0] lsu_complete_mem_data_i,
    input wire [7:0] lsu_complete_mem_mask_i
);
    // Commit-only classification: four bits cover the nine mutually exclusive kinds.
    localparam [3:0] C_REGULAR = 4'd0;
    localparam [3:0] C_FENCE = 4'd1;
    localparam [3:0] C_FENCE_I = 4'd2;
    localparam [3:0] C_SYSTEM = 4'd3;
    localparam [3:0] C_MRET = 4'd4;
    localparam [3:0] C_WFI = 4'd5;
    localparam [3:0] C_CSR = 4'd6;
    localparam [3:0] C_CONTROL = 4'd7;
    localparam [3:0] C_FP = 4'd8;
    localparam N = ISSUE_WIDTH == 2 || FPU_FORMAT == "FD" ? 16 : 8;
    localparam T = ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3;
    localparam B = FPU_FORMAT == "FD" ? 64 : 32;
    localparam S = FPU_FORMAT == "F" ? (ISSUE_WIDTH == 1 ? 3 : 5) : 2*ISSUE_WIDTH;
    localparam [T:0] DEPTH = {1'b1, {T{1'b0}}};
    reg [T-1:0] head_r;
    reg [T-1:0] tail_r;
    reg [T:0] count_r;
    wire [T-1:0] head_tag_w [0:1];
    wire [T-1:0] source_tag_w [0:4];
    wire [4:0] source_valid_w;
    wire [4:0] source_domain_w;
    wire [N-1:0] valid_w;
    wire [N-1:0] done_w;
    wire [N-1:0] device_w;
    wire [1:0] dest_w [0:N-1];
    wire [3:0] kind_w [0:N-1];
    wire [31:0] trace_instr_w [0:N-1];
    wire [3:0] allocate_kind_w [0:1];
    wire [4:0] rd_w [0:N-1];
    wire [N-1:0] store_w;
    wire [N-1:0] divide_w;
    wire [N-1:0] double_beat_w;
    wire [N-1:0] exception_w;
    wire [3:0] cause_w [0:N-1];
    wire [4:0] flags_w [0:N-1];
    wire [31:0] mem_addr_w [0:N-1];
    wire [63:0] mem_data_w [0:N-1];
    wire [7:0] mem_mask_w [0:N-1];
    wire [8:0] result_valid_w;
    wire [8:0] result_grant_w;
    wire [8:0] result_fp_w;
    wire [T-1:0] result_tag_w [0:8];
    wire [T-1:0] result_distance_w [0:8];
    wire [B-1:0] result_data_w [0:8];
    wire [B-1:0] result_payload_w [0:8];
    wire [4:0] result_flags_w [0:8];
    wire [8:0] result_exception_w;
    wire [3:0] result_cause_w [0:8];
    wire [31:0] result_tval_w [0:8];
    wire [T-1:0] cancel_distance_w;
    wire [T-1:0] branch_distance_w;
    wire branch_cancel_w;
    wire allocate_w;
    wire [1:0] add_count_w;
    wire [T-1:0] retire_delta_w;
    wire [T-1:0] allocate_delta_w;
    assign age_head_o = head_r;
    assign head_tag_w[0] = head_r;
    assign head_tag_w[1] = head_r + 1'b1;
    assign allocate_credit_o = DEPTH - count_r;
    assign allocate_ready_o = { {(T-1){1'b0}}, allocate_count_i } <=
        allocate_credit_o;
    assign allocate_w = allocate_valid_i && allocate_ready_o;
    assign add_count_w = allocate_w ? allocate_count_i : 2'b0;
    assign retire_delta_w = {{(T-2){1'b0}}, retire_count_i};
    assign allocate_delta_w = {{(T-2){1'b0}}, add_count_w};
    assign branch_distance_w = branch_redirect_tag_i - head_r;
    assign branch_cancel_w = branch_redirect_valid_i &&
        ({1'b0, branch_distance_w} + 1'b1 < count_r);
    assign cancel_valid_o = commit_cancel_valid_i || branch_cancel_w;
    assign cancel_tag_o = commit_cancel_valid_i ? commit_cancel_tag_i :
        branch_redirect_tag_i + 1'b1;
    assign cancel_distance_w = cancel_tag_o - head_r;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            head_r <= {T{1'b0}};
            tail_r <= {T{1'b0}};
            count_r <= {(T+1){1'b0}};
        end else begin
            head_r <= head_r + retire_delta_w;
            if (cancel_valid_o) begin
                tail_r <= cancel_tag_o;
                count_r <= {1'b0, cancel_distance_w} - {1'b0, retire_delta_w};
            end else begin
                tail_r <= tail_r + allocate_delta_w;
                count_r <= count_r + {1'b0, allocate_delta_w} - {1'b0, retire_delta_w};
            end
        end
    end
    assign result_valid_w[0] = alu0_complete_valid_i;
    assign result_tag_w[0] = alu0_complete_tag_i;
    assign result_data_w[0] = alu0_complete_data_i;
    assign result_flags_w[0] = alu0_complete_flags_i;
    assign result_exception_w[0] = alu0_complete_exception_i;
    assign result_cause_w[0] = alu0_complete_cause_i;
    assign result_tval_w[0] = alu0_complete_tval_i;
    assign alu0_complete_ready_o = result_grant_w[0];
    assign result_valid_w[1] = (ISSUE_WIDTH == 2 && alu1_complete_valid_i);
    assign result_tag_w[1] = alu1_complete_tag_i;
    assign result_data_w[1] = alu1_complete_data_i;
    assign result_flags_w[1] = alu1_complete_flags_i;
    assign result_exception_w[1] = alu1_complete_exception_i;
    assign result_cause_w[1] = alu1_complete_cause_i;
    assign result_tval_w[1] = alu1_complete_tval_i;
    assign alu1_complete_ready_o = ISSUE_WIDTH == 2 && result_grant_w[1];
    assign result_valid_w[2] = branch_complete_valid_i;
    assign result_tag_w[2] = branch_complete_tag_i;
    assign result_data_w[2] = branch_complete_data_i;
    assign result_flags_w[2] = branch_complete_flags_i;
    assign result_exception_w[2] = branch_complete_exception_i;
    assign result_cause_w[2] = branch_complete_cause_i;
    assign result_tval_w[2] = branch_complete_tval_i;
    assign branch_complete_ready_o = result_grant_w[2];
    assign result_valid_w[3] = mul_complete_valid_i;
    assign result_tag_w[3] = mul_complete_tag_i;
    assign result_data_w[3] = mul_complete_data_i;
    assign result_flags_w[3] = mul_complete_flags_i;
    assign result_exception_w[3] = mul_complete_exception_i;
    assign result_cause_w[3] = mul_complete_cause_i;
    assign result_tval_w[3] = mul_complete_tval_i;
    assign mul_complete_ready_o = result_grant_w[3];
    assign result_valid_w[4] = div_complete_valid_i;
    assign result_tag_w[4] = div_complete_tag_i;
    assign result_data_w[4] = div_complete_data_i;
    assign result_flags_w[4] = div_complete_flags_i;
    assign result_exception_w[4] = div_complete_exception_i;
    assign result_cause_w[4] = div_complete_cause_i;
    assign result_tval_w[4] = div_complete_tval_i;
    assign div_complete_ready_o = result_grant_w[4];
    assign result_valid_w[5] = lsu_complete_valid_i;
    assign result_tag_w[5] = lsu_complete_tag_i;
    assign result_data_w[5] = lsu_complete_data_i;
    assign result_flags_w[5] = lsu_complete_flags_i;
    assign result_exception_w[5] = lsu_complete_exception_i;
    assign result_cause_w[5] = lsu_complete_cause_i;
    assign result_tval_w[5] = lsu_complete_tval_i;
    assign lsu_complete_ready_o = result_grant_w[5];
    assign result_valid_w[6] = csr_complete_valid_i;
    assign result_tag_w[6] = csr_complete_tag_i;
    assign result_data_w[6] = csr_complete_data_i;
    assign result_flags_w[6] = csr_complete_flags_i;
    assign result_exception_w[6] = csr_complete_exception_i;
    assign result_cause_w[6] = csr_complete_cause_i;
    assign result_tval_w[6] = csr_complete_tval_i;
    assign csr_complete_ready_o = result_grant_w[6];
    assign result_valid_w[7] = (FPU_FORMAT != "NONE" && fp_resp_valid_i);
    assign result_tag_w[7] = fp_resp_tag_i;
    assign result_data_w[7] = fp_resp_data_i;
    assign result_flags_w[7] = fp_resp_flags_i;
    assign result_exception_w[7] = 'b0;
    assign result_cause_w[7] = 'b0;
    assign result_tval_w[7] = 'b0;
    assign fp_resp_ready_o = FPU_FORMAT != "NONE" && result_grant_w[7];
    assign result_valid_w[8] = decode_complete_valid_i;
    assign result_tag_w[8] = decode_complete_tag_i;
    assign result_data_w[8] = 'b0;
    assign result_flags_w[8] = 'b0;
    assign result_exception_w[8] = decode_complete_exception_i;
    assign result_cause_w[8] = decode_complete_cause_i;
    assign result_tval_w[8] = decode_complete_tval_i;
    assign decode_complete_ready_o = result_grant_w[8];
    assign source_tag_w[0] = source0_tag_i;
    assign source_valid_w[0] = source0_valid_i;
    assign source_domain_w[0] = source0_domain_i;
    assign source_tag_w[1] = source1_tag_i;
    assign source_valid_w[1] = source1_valid_i;
    assign source_domain_w[1] = source1_domain_i;
    assign source_tag_w[2] = source2_tag_i;
    assign source_valid_w[2] = source2_valid_i;
    assign source_domain_w[2] = source2_domain_i;
    assign source_tag_w[3] = source3_tag_i;
    assign source_valid_w[3] = source3_valid_i;
    assign source_domain_w[3] = source3_domain_i;
    assign source_tag_w[4] = source4_tag_i;
    assign source_valid_w[4] = source4_valid_i;
    assign source_domain_w[4] = source4_domain_i;
    genvar slot;
    generate
        for (slot = 0; slot < 2; slot = slot + 1) begin : g_allocate_kind
            wire [31:0] instr_w;
            reg [3:0] decoded_kind_w;
            assign instr_w = slot == 0 ? allocate0_instr_i : allocate1_instr_i;
            assign allocate_kind_w[slot] = decoded_kind_w;
            always @(*) begin
                decoded_kind_w = C_REGULAR;
                case (instr_w[6:0])
                    7'h0f: decoded_kind_w = instr_w[14:12] == 3'b001 ? C_FENCE_I : C_FENCE;
                    7'h73: begin
                        if (instr_w == 32'h30200073)
                            decoded_kind_w = C_MRET;
                        else if (instr_w == 32'h10500073)
                            decoded_kind_w = C_WFI;
                        else if (instr_w[14:12] != 3'b0)
                            decoded_kind_w = C_CSR;
                        else
                            decoded_kind_w = C_SYSTEM;
                    end
                    7'h63, 7'h6f, 7'h67: decoded_kind_w = C_CONTROL;
                    7'h53: decoded_kind_w = C_FP;
                    default: decoded_kind_w = C_REGULAR;
                endcase
            end
        end
    endgenerate
    // Pairwise comparisons form independent age winners, without a serial scan.
    genvar r;
    genvar other;
    generate
        for (r = 0; r < 9; r = r + 1) begin : g_arbitrate
            wire [8:0] older_w;
            // Exceptions have no result: the same data write stores their mtval.
            assign result_payload_w[r] = result_exception_w[r] ?
                {{(B-32){1'b0}}, result_tval_w[r]} : result_data_w[r];
            assign result_distance_w[r] = result_tag_w[r] - head_r;
            assign result_fp_w[r] = dest_w[result_tag_w[r]] == 2'd2;
            for (other = 0; other < 9; other = other + 1) begin : g_compare
                assign older_w[other] = result_valid_w[other] &&
                    result_distance_w[other] < result_distance_w[r] &&
                    (result_tag_w[other][0] == result_tag_w[r][0] ||
                    (result_fp_w[other] && result_fp_w[r]));
            end
            assign result_grant_w[r] = !(|older_w);
        end
    endgenerate
    // One independent control record per slot avoids PDS array multiple writers.
    genvar q;
    generate
        for (q = 0; q < N; q = q + 1) begin : g_record
            localparam [T-1:0] TAG = q;
            reg valid_r;
            reg done_r;
            reg device_r;
            reg [3:0] kind_r;
            // Trace is the only consumer of the original instruction word.
            reg [31:0] trace_instr_r;
            reg [4:0] rd_r;
            reg [1:0] dest_r;
            reg store_r;
            reg divide_r;
            reg double_beat_r;
            reg exception_r;
            reg [3:0] cause_r;
            reg [4:0] flags_r;
            reg [31:0] mem_addr_r;
            reg [63:0] mem_data_r;
            reg [7:0] mem_mask_r;
            wire [T-1:0] distance_w;
            wire cancel_w;
            wire release_w;
            wire allocate0_w;
            wire allocate1_w;
            wire [8:0] accept_w;
            reg [4:0] selected_flags_w;
            reg selected_exception_w;
            reg [3:0] selected_cause_w;
            integer k;
            assign distance_w = TAG - head_r;
            assign cancel_w = cancel_valid_o && distance_w >= cancel_distance_w;
            assign release_w = {1'b0, distance_w} < { {(T-1){1'b0}}, retire_count_i };
            assign allocate0_w = allocate_w && allocate_count_i != 0 && allocate0_tag_i == TAG;
            assign allocate1_w = ISSUE_WIDTH == 2 && allocate_w && allocate_count_i == 2 &&
                allocate1_tag_i == TAG;
            for (r = 0; r < 9; r = r + 1) begin : g_accept
                assign accept_w[r] = result_valid_w[r] && result_grant_w[r] &&
                    result_tag_w[r] == TAG && !cancel_w;
            end
            always @(*) begin
                selected_flags_w = 5'b0;
                selected_exception_w = 1'b0;
                selected_cause_w = 4'b0;
                for (k = 0; k < 9; k = k + 1) begin
                    selected_flags_w = selected_flags_w | ({5{accept_w[k]}} & result_flags_w[k]);
                    selected_exception_w = selected_exception_w |
                        (accept_w[k] && result_exception_w[k]);
                    selected_cause_w = selected_cause_w | ({4{accept_w[k]}} & result_cause_w[k]);
                end
            end
            assign valid_w[q] = valid_r;
            assign done_w[q] = done_r;
            assign device_w[q] = device_r;
            assign kind_w[q] = kind_r;
            assign trace_instr_w[q] = trace_instr_r;
            assign rd_w[q] = rd_r;
            assign dest_w[q] = dest_r;
            assign store_w[q] = store_r;
            assign divide_w[q] = divide_r;
            assign double_beat_w[q] = double_beat_r;
            assign exception_w[q] = exception_r;
            assign cause_w[q] = cause_r;
            assign flags_w[q] = flags_r;
            assign mem_addr_w[q] = mem_addr_r;
            assign mem_data_w[q] = mem_data_r;
            assign mem_mask_w[q] = mem_mask_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    valid_r <= 1'b0;
                    done_r <= 1'b0;
                    device_r <= 1'b0;
                    exception_r <= 1'b0;
                end else begin
                    if (release_w || cancel_w)
                        valid_r <= 1'b0;
                    if ((allocate0_w || allocate1_w) && !cancel_w) begin
                        valid_r <= 1'b1;
                        done_r <= 1'b0;
                        device_r <= 1'b0;
                        exception_r <= 1'b0;
                    end
                    if (|accept_w) begin
                        done_r <= 1'b1;
                        device_r <= accept_w[5] && lsu_complete_device_i;
                        exception_r <= selected_exception_w;
                    end
                end
            end
            always @(posedge clk_i) begin
                if (allocate0_w || allocate1_w) begin
                    kind_r <= allocate1_w ? allocate_kind_w[1] : allocate_kind_w[0];
                    trace_instr_r <= allocate1_w ? allocate1_instr_i : allocate0_instr_i;
                    rd_r <= allocate1_w ? allocate1_rd_i : allocate0_rd_i;
                    dest_r <= allocate1_w ? allocate1_dest_i : allocate0_dest_i;
                    store_r <= allocate1_w ? allocate1_store_i : allocate0_store_i;
                    divide_r <= allocate1_w ? allocate1_divide_i : allocate0_divide_i;
                    double_beat_r <= allocate1_w ?
                        allocate1_double_beat_i : allocate0_double_beat_i;
                end
                if (|accept_w) begin
                    flags_r <= selected_flags_w;
                    cause_r <= selected_cause_w;
                end
                if (accept_w[5]) begin
                    mem_addr_r <= lsu_complete_mem_addr_i;
                    mem_data_r <= lsu_complete_mem_data_i;
                    mem_mask_r <= lsu_complete_mem_mask_i;
                end
            end
        end
    endgenerate
    wire [31:0] bank_low_w [0:2*(S+1)-1];
    wire [31:0] bank_high_w [0:5];
    wire [31:0] bank_pc_w [0:1];
    wire [31:0] bank_next_pc_w [0:1];
    wire [B-1:0] bank_head_data_w [0:1];
    genvar bank;
    genvar copy;
    generate
            for (bank = 0; bank < 2; bank = bank + 1) begin : g_bank
                wire write_w;
                wire [T-1:0] write_tag_w;
                wire [B-1:0] write_data_w;
                wire [8:0] bank_accept_w;
                wire [T-1:0] tag_term_w [0:8];
                wire [B-1:0] data_term_w [0:8];
                wire allocate_bank_w;
                wire allocate_second_w;
                wire [T-1:0] allocate_tag_w;
                wire [31:0] allocate_pc_w;
                wire [T-1:0] read_head_w;
                wire [T-1:0] read_data_head_w;
                wire [T-1:0] next_head_w;
                wire [2:0] pc_head_addr_w;
                reg [B-1:0] head_data_r;
                wire [B-1:0] head_read_w;
                wire [2:0] write_addr_w;
                wire [2:0] pc_write_addr_w;
                wire [2:0] head_addr_w;
                /* verilator lint_off UNUSEDSIGNAL */
                wire unused_bank_w = ^{write_tag_w[0], allocate_tag_w[0], read_head_w[0]};
                /* verilator lint_on UNUSEDSIGNAL */
                assign allocate_second_w = ISSUE_WIDTH == 2 && allocate_count_i == 2 &&
                    allocate1_tag_i[0] == (bank == 1);
                assign allocate_bank_w = allocate_w && allocate_count_i != 0 &&
                    (allocate0_tag_i[0] == (bank == 1) || allocate_second_w);
                assign allocate_tag_w = allocate_second_w ? allocate1_tag_i : allocate0_tag_i;
                assign allocate_pc_w = allocate_second_w ? allocate1_pc_i : allocate0_pc_i;
                assign read_head_w = head_r[0] == (bank == 1) ? head_tag_w[0] : head_tag_w[1];
                assign next_head_w = head_r + retire_delta_w;
                assign read_data_head_w = next_head_w[0] == (bank == 1) ?
                    next_head_w : next_head_w + 1'b1;
                assign pc_head_addr_w = {{(4-T){1'b0}}, read_head_w[T-1:1]};
                assign bank_head_data_w[bank] = head_data_r;
                if (FPU_FORMAT == "FD") begin : g_head_fd
                    assign head_read_w = {bank_high_w[bank*3+2], bank_low_w[bank*(S+1)+S]};
                end else begin : g_head_f
                    assign head_read_w = bank_low_w[bank*(S+1)+S];
                end
                // Read the post-retirement head and capture locally. A result written on
                // this edge bypasses the asynchronous RAM read into the same capture.
                always @(posedge clk_i) begin
                    head_data_r <= write_w && write_tag_w == read_data_head_w ?
                        write_data_w : head_read_w;
                end
                assign write_addr_w = {{(4-T){1'b0}}, write_tag_w[T-1:1]};
                assign pc_write_addr_w = {{(4-T){1'b0}}, allocate_tag_w[T-1:1]};
                assign head_addr_w = {{(4-T){1'b0}}, read_data_head_w[T-1:1]};
                for (r = 0; r < 9; r = r + 1) begin : g_write_term
                    assign bank_accept_w[r] = result_valid_w[r] && result_grant_w[r] &&
                        result_tag_w[r][0] == (bank == 1) &&
                        !(cancel_valid_o && result_distance_w[r] >= cancel_distance_w);
                    assign tag_term_w[r] = {T{bank_accept_w[r]}} & result_tag_w[r];
                    assign data_term_w[r] = {B{bank_accept_w[r]}} & result_payload_w[r];
                end
                assign write_w = |bank_accept_w;
                assign write_tag_w =
                    (tag_term_w[0] | tag_term_w[1] | tag_term_w[2]) |
                    (tag_term_w[3] | tag_term_w[4] | tag_term_w[5]) |
                    (tag_term_w[6] | tag_term_w[7] | tag_term_w[8]);
                assign write_data_w =
                    (data_term_w[0] | data_term_w[1] | data_term_w[2]) |
                    (data_term_w[3] | data_term_w[4] | data_term_w[5]) |
                    (data_term_w[6] | data_term_w[7] | data_term_w[8]);
                edrv32_ram_cpu2_completion u_next_pc (
                    .clk_i(clk_i),
                    .wr_en_i(bank_accept_w[2]),
                    .wr_addr_i(write_addr_w),
                    .wr_data_i(branch_complete_next_pc_i),
                    .rd_addr_i(pc_head_addr_w),
                    .rd_data_o(bank_next_pc_w[bank])
                );
                edrv32_ram_cpu2_completion u_pc (
                    .clk_i(clk_i),
                    .wr_en_i(allocate_bank_w),
                    .wr_addr_i(pc_write_addr_w),
                    .wr_data_i(allocate_pc_w),
                    .rd_addr_i(pc_head_addr_w),
                    .rd_data_o(bank_pc_w[bank])
                );
                for (copy = 0; copy < S+1; copy = copy + 1) begin : g_low
                    wire [2:0] read_addr_w;
                    if (copy == S) begin : g_head
                        assign read_addr_w = head_addr_w;
                    end else begin : g_source
                        assign read_addr_w = {{(4-T){1'b0}}, source_tag_w[copy][T-1:1]};
                    end
                    edrv32_ram_cpu2_completion u_data (
                        .clk_i(clk_i),
                        .wr_en_i(write_w),
                        .wr_addr_i(write_addr_w),
                        .wr_data_i(write_data_w[31:0]),
                        .rd_addr_i(read_addr_w),
                        .rd_data_o(bank_low_w[bank*(S+1)+copy])
                    );
                end
                if (FPU_FORMAT == "FD") begin : g_fd
                    localparam HIGH_COPIES = 3;
                    for (copy = 0; copy < HIGH_COPIES; copy = copy + 1) begin : g_high
                        wire [2:0] read_addr_w;
                        if (copy == 2) begin : g_head
                            assign read_addr_w = head_addr_w;
                        end else begin : g_source
                            assign read_addr_w = source_tag_w[copy][T-1:1];
                        end
                        edrv32_ram_cpu2_completion u_data (
                            .clk_i(clk_i),
                            .wr_en_i(write_w),
                            .wr_addr_i(write_addr_w),
                            .wr_data_i(write_data_w[63:32]),
                            .rd_addr_i(read_addr_w),
                            .rd_data_o(bank_high_w[bank*3+copy])
                        );
                    end
                end else begin : g_f
                    assign bank_high_w[bank*3] = 32'b0;
                    assign bank_high_w[bank*3+1] = 32'b0;
                    assign bank_high_w[bank*3+2] = 32'b0;
                end
            end
    endgenerate
    generate
        if (0 < ISSUE_WIDTH) begin : g_head0
            assign head0_tag_o = head_tag_w[0];
            assign head0_next_pc_o = (head_tag_w[0][0] ?
                bank_next_pc_w[1] : bank_next_pc_w[0]);
            assign head0_pc_o = (head_tag_w[0][0] ? bank_pc_w[1] : bank_pc_w[0]);
            assign head0_kind_o = kind_w[head_tag_w[0]];
            assign head0_trace_instr_o = trace_instr_w[head_tag_w[0]];
            assign head0_rd_o = rd_w[head_tag_w[0]];
            assign head0_dest_o = dest_w[head_tag_w[0]];
            assign head0_store_o = store_w[head_tag_w[0]];
            assign head0_divide_o = divide_w[head_tag_w[0]];
            assign head0_double_beat_o = double_beat_w[head_tag_w[0]];
            assign head0_valid_o = valid_w[head_tag_w[0]];
            assign head0_done_o = done_w[head_tag_w[0]];
            assign head0_data_o = (head_tag_w[0][0] ?
                bank_head_data_w[1] : bank_head_data_w[0]);
            assign head0_flags_o = flags_w[head_tag_w[0]];
            assign head0_exception_o = exception_w[head_tag_w[0]];
            assign head0_cause_o = cause_w[head_tag_w[0]];
            assign head0_tval_o = head0_data_o[31:0];
            assign head0_device_o = device_w[head_tag_w[0]];
            assign head0_mem_addr_o = mem_addr_w[head_tag_w[0]];
            assign head0_mem_data_o = mem_data_w[head_tag_w[0]];
            assign head0_mem_mask_o = mem_mask_w[head_tag_w[0]];
        end else begin : g_absent_head0
            assign head0_tag_o = 'b0;
            assign head0_pc_o = 'b0;
            assign head0_next_pc_o = 'b0;
            assign head0_kind_o = 'b0;
            assign head0_trace_instr_o = 'b0;
            assign head0_rd_o = 'b0;
            assign head0_dest_o = 'b0;
            assign head0_store_o = 'b0;
            assign head0_divide_o = 'b0;
            assign head0_double_beat_o = 'b0;
            assign head0_valid_o = 'b0;
            assign head0_done_o = 'b0;
            assign head0_data_o = 'b0;
            assign head0_flags_o = 'b0;
            assign head0_exception_o = 'b0;
            assign head0_cause_o = 'b0;
            assign head0_tval_o = 'b0;
            assign head0_device_o = 'b0;
            assign head0_mem_addr_o = 'b0;
            assign head0_mem_data_o = 'b0;
            assign head0_mem_mask_o = 'b0;
        end
    endgenerate
    generate
        if (1 < ISSUE_WIDTH) begin : g_head1
            assign head1_tag_o = head_tag_w[1];
            assign head1_next_pc_o = (head_tag_w[1][0] ?
                bank_next_pc_w[1] : bank_next_pc_w[0]);
            assign head1_pc_o = (head_tag_w[1][0] ? bank_pc_w[1] : bank_pc_w[0]);
            assign head1_kind_o = kind_w[head_tag_w[1]];
            assign head1_trace_instr_o = trace_instr_w[head_tag_w[1]];
            assign head1_rd_o = rd_w[head_tag_w[1]];
            assign head1_dest_o = dest_w[head_tag_w[1]];
            assign head1_store_o = store_w[head_tag_w[1]];
            assign head1_divide_o = divide_w[head_tag_w[1]];
            assign head1_double_beat_o = double_beat_w[head_tag_w[1]];
            assign head1_valid_o = valid_w[head_tag_w[1]];
            assign head1_done_o = done_w[head_tag_w[1]];
            assign head1_data_o = (head_tag_w[1][0] ?
                bank_head_data_w[1] : bank_head_data_w[0]);
            assign head1_flags_o = flags_w[head_tag_w[1]];
            assign head1_exception_o = exception_w[head_tag_w[1]];
            assign head1_cause_o = cause_w[head_tag_w[1]];
            assign head1_tval_o = head1_data_o[31:0];
            assign head1_device_o = device_w[head_tag_w[1]];
            assign head1_mem_addr_o = mem_addr_w[head_tag_w[1]];
            assign head1_mem_data_o = mem_data_w[head_tag_w[1]];
            assign head1_mem_mask_o = mem_mask_w[head_tag_w[1]];
        end else begin : g_absent_head1
            assign head1_tag_o = 'b0;
            assign head1_pc_o = 'b0;
            assign head1_next_pc_o = 'b0;
            assign head1_kind_o = 'b0;
            assign head1_trace_instr_o = 'b0;
            assign head1_rd_o = 'b0;
            assign head1_dest_o = 'b0;
            assign head1_store_o = 'b0;
            assign head1_divide_o = 'b0;
            assign head1_double_beat_o = 'b0;
            assign head1_valid_o = 'b0;
            assign head1_done_o = 'b0;
            assign head1_data_o = 'b0;
            assign head1_flags_o = 'b0;
            assign head1_exception_o = 'b0;
            assign head1_cause_o = 'b0;
            assign head1_tval_o = 'b0;
            assign head1_device_o = 'b0;
            assign head1_mem_addr_o = 'b0;
            assign head1_mem_data_o = 'b0;
            assign head1_mem_mask_o = 'b0;
        end
    endgenerate
    generate
        if (0 < S) begin : g_source0
            assign source0_ready_o = source0_valid_i && valid_w[source0_tag_i] &&
                done_w[source0_tag_i] && !device_w[source0_tag_i];
            if (FPU_FORMAT == "FD") begin : g_fd
                assign source0_data_o = {(source0_tag_i[0] ?
                    bank_high_w[3+0] : bank_high_w[0]), (source0_tag_i[0] ?
                    bank_low_w[S+1+0] : bank_low_w[0])};
            end else begin : g_word
                assign source0_data_o = {{(B-32){1'b0}},
                    (source0_tag_i[0] ? bank_low_w[S+1+0] : bank_low_w[0])};
            end
        end else begin : g_absent_source0
            assign source0_ready_o = 1'b0;
            assign source0_data_o = {B{1'b0}};
        end
    endgenerate
    generate
        if (1 < S) begin : g_source1
            assign source1_ready_o = source1_valid_i && valid_w[source1_tag_i] &&
                done_w[source1_tag_i] && !device_w[source1_tag_i];
            if (FPU_FORMAT == "FD") begin : g_fd
                assign source1_data_o = {(source1_tag_i[0] ?
                    bank_high_w[3+1] : bank_high_w[1]), (source1_tag_i[0] ?
                    bank_low_w[S+1+1] : bank_low_w[1])};
            end else begin : g_word
                assign source1_data_o = {{(B-32){1'b0}},
                    (source1_tag_i[0] ? bank_low_w[S+1+1] : bank_low_w[1])};
            end
        end else begin : g_absent_source1
            assign source1_ready_o = 1'b0;
            assign source1_data_o = {B{1'b0}};
        end
    endgenerate
    generate
        if (2 < S) begin : g_source2
            assign source2_ready_o = source2_valid_i && valid_w[source2_tag_i] &&
                done_w[source2_tag_i] && !device_w[source2_tag_i];
                assign source2_data_o = {{(B-32){1'b0}},
                    (source2_tag_i[0] ? bank_low_w[S+1+2] : bank_low_w[2])};
        end else begin : g_absent_source2
            assign source2_ready_o = 1'b0;
            assign source2_data_o = {B{1'b0}};
        end
    endgenerate
    generate
        if (3 < S) begin : g_source3
            assign source3_ready_o = source3_valid_i && valid_w[source3_tag_i] &&
                done_w[source3_tag_i] && !device_w[source3_tag_i];
                assign source3_data_o = {{(B-32){1'b0}},
                    (source3_tag_i[0] ? bank_low_w[S+1+3] : bank_low_w[3])};
        end else begin : g_absent_source3
            assign source3_ready_o = 1'b0;
            assign source3_data_o = {B{1'b0}};
        end
    endgenerate
    generate
        if (4 < S) begin : g_source4
            assign source4_ready_o = source4_valid_i && valid_w[source4_tag_i] &&
                done_w[source4_tag_i] && !device_w[source4_tag_i];
                assign source4_data_o = {{(B-32){1'b0}},
                    (source4_tag_i[0] ? bank_low_w[S+1+4] : bank_low_w[4])};
        end else begin : g_absent_source4
            assign source4_ready_o = 1'b0;
            assign source4_data_o = {B{1'b0}};
        end
    endgenerate
    // Unused configuration fields and internal architectural observation wires.
    /* verilator lint_off UNUSEDSIGNAL */
    wire unused_w = ^{
        allocate0_csr_src_i, allocate1_csr_src_i,
        branch_redirect_pc_i,
        fp_resp_int_dest_i,
        source_valid_w,
        source_domain_w,
        source_tag_w[0],
        source_tag_w[1],
        source_tag_w[2],
        source_tag_w[3],
        source_tag_w[4],
        bank_high_w[0],
        bank_high_w[1],
        bank_high_w[2],
        bank_high_w[3],
        bank_high_w[4],
        bank_high_w[5]
    };
    /* verilator lint_on UNUSEDSIGNAL */
endmodule
