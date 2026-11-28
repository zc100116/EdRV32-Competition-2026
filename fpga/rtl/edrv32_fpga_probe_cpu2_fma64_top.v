// File: edrv32_fpga_probe_cpu2_fma64_top.v
// Spec: fpu-spec 5.2, 5.3, 7.1; CPU v2 probe P09.
// Description: Register-driven standalone FMA timing probe with serial seed input.
//              Full input and result registers preserve both timing boundaries.
// Clock domain: clk_sys (clk_i, constrained to 165 MHz).
module edrv32_fpga_probe_cpu2_fma64_top (
    // Single probe clock and externally injectable LFSR seed bits.
    input wire clk_i,
    input wire rst_n_i,
    input wire [3:0] seed_i,

    // Registered folded observation of every result/flags bit.
    output reg [3:0] observe_o
);
    reg [196:0] stimulus_r;
    reg [63:0] a_r;
    reg [63:0] b_r;
    reg [63:0] c_r;
    reg [1:0] op_r;
    reg [1:0] kind_r;
    wire [31:0] instr_w;
    reg [2:0] rm_r;
    wire [63:0] result_w;
    wire [4:0] flags_w;
    reg [63:0] result_r;
    reg [4:0] flags_r;
    always @(posedge clk_i) begin
        stimulus_r <= {stimulus_r[192:0], stimulus_r[196:193]
            ^ {4{stimulus_r[196] ^ stimulus_r[191] ^ stimulus_r[190] ^ stimulus_r[189]}}
            ^ seed_i};
        if (unit_req_ready_w) begin
            a_r <= stimulus_r[63:0];
            b_r <= stimulus_r[127:64];
            c_r <= stimulus_r[191:128];
            op_r <= stimulus_r[193:192];
            kind_r <= stimulus_r[195:194];
            rm_r <= stimulus_r[196] ? 3'b100 : {1'b0, stimulus_r[195:194]};
        end
        result_r <= result_w;
        flags_r <= flags_w;
        observe_o <= result_r[3:0] ^ result_r[7:4] ^ result_r[11:8]
            ^ result_r[15:12] ^ result_r[19:16] ^ result_r[23:20]
            ^ result_r[27:24] ^ result_r[31:28] ^ result_r[35:32] ^ result_r[39:36] ^
        result_r[43:40]

            ^ result_r[47:44] ^ result_r[51:48] ^ result_r[55:52]
            ^ result_r[59:56] ^ result_r[63:60] ^ flags_r[3:0] ^ {3'b0, flags_r[4]};
    end
    // Keep ADD, SUB, MUL and every fused variant live in the timing netlist.
    assign instr_w = kind_r == 2'd0 ? 32'h02000053
        : kind_r == 2'd1 ? 32'h0a000053
        : kind_r == 2'd2 ? 32'h12000053 : {5'b0,2'b01,18'b0,3'b100,op_r,2'b11};
    wire unit_req_ready_w;
    wire unused_resp_valid_w;
    wire [3:0] unused_resp_tag_w;
    wire unused_int_dest_w;
    reg resp_ready_r;
    always @(posedge clk_i) begin
        resp_ready_r <= stimulus_r[0];
    end
    edrv32_cpu2_fpu_fma64 u_fma (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .unit_req_valid_i(1'b1),
        .unit_req_ready_o(unit_req_ready_w),
        .unit_req_instr_i(instr_w),
        .unit_req_tag_i(4'b0),
        .unit_req_src1_i(a_r),
        .unit_req_src2_i(b_r),
        .unit_req_src3_i(c_r),
        .unit_req_rm_i(rm_r),
        .unit_resp_valid_o(unused_resp_valid_w),
        .unit_resp_ready_i(resp_ready_r),
        .unit_resp_tag_o(unused_resp_tag_w),
        .unit_resp_data_o(result_w),
        .unit_resp_flags_o(flags_w),
        .unit_resp_int_dest_o(unused_int_dest_w),
        .age_head_i(4'b0),
        .cancel_valid_i(1'b0),
        .cancel_tag_i(4'b0)
    );
endmodule
