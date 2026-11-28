// File: edrv32_cpu2_fpu_divsqrt.v
// Spec: fpu-spec 2.2, 3.1, 5.2-5.4; interface freeze C05.
// Description: Single-entry S/D radix-four divide/square-root owner.
//              Independent S and optional D datapaths hold completion under backpressure.
// Clock domain: clk_sys.
module edrv32_cpu2_fpu_divsqrt #(
    parameter [31:0] FPU_FORMAT = "F"
) (
    // Clock and reset: only ownership and schedule registers reset.
    input wire clk_i,
    input wire rst_n_i,

    // Resolved, legal DIV/SQRT request; boxing is performed by fpu_top.
    input wire unit_req_valid_i,
    output wire unit_req_ready_o,
    input wire [31:0] unit_req_instr_i,
    input wire [(FPU_FORMAT == "FD" ? 4 : 3)-1:0] unit_req_tag_i,
    input wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] unit_req_src1_i,
    input wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] unit_req_src2_i,
    input wire [2:0] unit_req_rm_i,

    // Local held result. Narrow result extension belongs to fpu_top.
    output wire unit_resp_valid_o,
    input wire unit_resp_ready_i,
    output wire [(FPU_FORMAT == "FD" ? 4 : 3)-1:0] unit_resp_tag_o,
    output wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] unit_resp_data_o,
    output wire [4:0] unit_resp_flags_o,
    output wire unit_resp_int_dest_o,

    // Inclusive cancellation by queue-head-relative age, including acceptance.
    input wire [(FPU_FORMAT == "FD" ? 4 : 3)-1:0] age_head_i,
    input wire cancel_valid_i,
    input wire [(FPU_FORMAT == "FD" ? 4 : 3)-1:0] cancel_tag_i
);
    localparam TAG_WIDTH = FPU_FORMAT == "FD" ? 4 : 3;
    reg busy_r;
    reg done_r;
    reg [5:0] phase_r;
    reg double_r;
    reg sqrt_r;
    reg [TAG_WIDTH-1:0] tag_r;
    wire [TAG_WIDTH-1:0] current_age_w;
    wire [TAG_WIDTH-1:0] request_age_w;
    wire [TAG_WIDTH-1:0] cancel_age_w;
    wire cancel_current_w;
    wire cancel_request_w;
    wire accept_w;
    wire start_w;
    wire last_w;
    assign current_age_w = tag_r - age_head_i;
    assign request_age_w = unit_req_tag_i - age_head_i;
    assign cancel_age_w = cancel_tag_i - age_head_i;
    assign cancel_current_w = cancel_valid_i && current_age_w >= cancel_age_w;
    assign cancel_request_w = cancel_valid_i && request_age_w >= cancel_age_w;
    assign unit_req_ready_o = !busy_r;
    assign accept_w = unit_req_valid_i && unit_req_ready_o;
    assign start_w = accept_w && !cancel_request_w;
    assign last_w = phase_r == (double_r ? (sqrt_r ? 6'd36 : 6'd35)
        : (sqrt_r ? 6'd22 : 6'd21));
    assign unit_resp_valid_o = done_r;
    assign unit_resp_tag_o = tag_r;
    assign unit_resp_int_dest_o = 1'b0;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            busy_r <= 1'b0;
            done_r <= 1'b0;
            phase_r <= 6'd0;
        end else begin
            if (busy_r && cancel_current_w) begin
                busy_r <= 1'b0;
                done_r <= 1'b0;
            end else if (done_r && unit_resp_ready_i) begin
                busy_r <= 1'b0;
                done_r <= 1'b0;
            end else if (busy_r && !done_r) begin
                if (last_w) done_r <= 1'b1;
                else phase_r <= phase_r + 6'd1;
            end
            if (start_w) begin
                busy_r <= 1'b1;
                done_r <= 1'b0;
                phase_r <= 6'd1;
            end
        end
    end
    always @(posedge clk_i) begin
        if (start_w) begin
            double_r <= FPU_FORMAT == "FD" && unit_req_instr_i[25];
            tag_r <= unit_req_tag_i;
            sqrt_r <= unit_req_instr_i[30];
        end
    end
    wire active_w;
    assign active_w = busy_r && !done_r;
    wire [31:0] single_result_w;
    wire [4:0] single_flags_w;
    edrv32_cpu2_fpu_divsqrt32 u_single (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .capture_next_i(start_w && !(FPU_FORMAT == "FD" && unit_req_instr_i[25])),
        .prepare_next_i(active_w && !double_r && phase_r == 6'd1),
        .iterate_next_i(active_w && !double_r && phase_r >= 6'd2
            && phase_r <= (sqrt_r ? 6'd15 : 6'd14)),
        .shift_next_i(active_w && !double_r && phase_r == (sqrt_r ? 6'd16 : 6'd15)),
        .align_next_i(active_w && !double_r && phase_r == (sqrt_r ? 6'd17 : 6'd16)),
        .round_next_i(active_w && !double_r && phase_r == (sqrt_r ? 6'd18 : 6'd17)),
        .encode_next_i(active_w && !double_r && phase_r == (sqrt_r ? 6'd20 : 6'd19)),
        .pack_next_i(active_w && !double_r && phase_r == (sqrt_r ? 6'd21 : 6'd20)),
        .unit_req_src1_i(unit_req_src1_i[31:0]),
        .unit_req_src2_i(unit_req_src2_i[31:0]),
        .sqrt_i(unit_req_instr_i[30]),
        .unit_req_rm_i(unit_req_rm_i),
        .result_o(single_result_w),
        .flags_o(single_flags_w)
    );
    generate
        if (FPU_FORMAT == "FD") begin : g_double
            wire [63:0] double_result_w;
            wire [4:0] double_flags_w;
            edrv32_cpu2_fpu_divsqrt64 u_double (
                .clk_i(clk_i),
                .rst_n_i(rst_n_i),
                .capture_next_i(start_w && unit_req_instr_i[25]),
                .prepare_next_i(active_w && double_r && phase_r == 6'd1),
                .iterate_next_i(active_w && double_r && phase_r >= 6'd2
            && phase_r <= (sqrt_r ? 6'd29 : 6'd28)),
                .shift_next_i(active_w && double_r && phase_r == (sqrt_r ? 6'd30 : 6'd29)),
                .align_next_i(active_w && double_r && phase_r == (sqrt_r ? 6'd31 : 6'd30)),
                .round_next_i(active_w && double_r && phase_r == (sqrt_r ? 6'd32 : 6'd31)),
                .normalize_next_i(active_w && double_r && phase_r == (sqrt_r ? 6'd33 : 6'd32)),
                .encode_next_i(active_w && double_r && phase_r == (sqrt_r ? 6'd34 : 6'd33)),
                .pack_next_i(active_w && double_r && phase_r == (sqrt_r ? 6'd35 : 6'd34)),
                .unit_req_src1_i(unit_req_src1_i),
                .unit_req_src2_i(unit_req_src2_i),
                .sqrt_i(unit_req_instr_i[30]),
                .unit_req_rm_i(unit_req_rm_i),
                .result_o(double_result_w),
                .flags_o(double_flags_w)
            );
            assign unit_resp_data_o = double_r ? double_result_w : {32'b0, single_result_w};
            assign unit_resp_flags_o = done_r ? (double_r ? double_flags_w : single_flags_w)
                : 5'b0;
        end else begin : g_single
            assign unit_resp_data_o = single_result_w;
            assign unit_resp_flags_o = done_r ? single_flags_w : 5'b0;
        end
    endgenerate
    /* verilator lint_off UNUSEDSIGNAL */
    wire unused_w;
    assign unused_w = &{1'b0, unit_req_instr_i[31], unit_req_instr_i[29:26],
        unit_req_instr_i[24:0]};
    /* verilator lint_on UNUSEDSIGNAL */
endmodule
