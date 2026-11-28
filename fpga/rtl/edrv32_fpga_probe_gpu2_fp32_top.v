// File: edrv32_fpga_probe_gpu2_fp32_top.v
// Spec: gpu-v2-spec 2.4; G-P01 220 MHz timing probe.
// Description: Registered LFSR stimulus, registered downstream readiness and output folding.
// Clock domain: clk_gpu, directly supplied at clk_i.
module edrv32_fpga_probe_gpu2_fp32_top (
    // Probe clock and control reset.
    input wire clk_i,
    input wire rst_n_i,

    // Registered observable arithmetic fold.
    output reg [31:0] fold_o
);
    reg [127:0] a_lfsr_r;
    reg [127:0] b_lfsr_r;
    reg [127:0] c_lfsr_r;
    reg [31:0] ready_lfsr_r;
    wire unused_req_ready_w;
    wire vec_valid_w;
    wire dp_valid_w;
    wire [127:0] vec_data_w;
    wire [31:0] dp_data_w;
    // LFSRs are free-running stimulus control state; accepted edges sample their current words.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            a_lfsr_r <= 128'hf1e2d3c4b5a69788776655443322110f;
            b_lfsr_r <= 128'h3456789abcdef1236789abcdef123457;
            c_lfsr_r <= 128'h123456789abcdef0123456789abcdef1;
            ready_lfsr_r <= 32'h8912abcd;
        end else begin
            a_lfsr_r <= {a_lfsr_r[126:0], a_lfsr_r[127] ^ a_lfsr_r[125]
                ^ a_lfsr_r[100] ^ a_lfsr_r[98]};
            b_lfsr_r <= {b_lfsr_r[126:0], b_lfsr_r[127] ^ b_lfsr_r[125]
                ^ b_lfsr_r[100] ^ b_lfsr_r[98]};
            c_lfsr_r <= {c_lfsr_r[126:0], c_lfsr_r[127] ^ c_lfsr_r[125]
                ^ c_lfsr_r[100] ^ c_lfsr_r[98]};
            ready_lfsr_r <= {ready_lfsr_r[30:0], ready_lfsr_r[31] ^ ready_lfsr_r[21]
                ^ ready_lfsr_r[1] ^ ready_lfsr_r[0]};
        end
    end
    edrv32_gpu2_fp32 u_fp32 (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .req_valid_i(a_lfsr_r[5]),
        .req_ready_o(unused_req_ready_w),
        .req_op_i(c_lfsr_r[1:0]),
        .req_a_i(a_lfsr_r),
        .req_b_i(b_lfsr_r),
        .req_c_i(c_lfsr_r),
        .vec_valid_o(vec_valid_w),
        .vec_ready_i(ready_lfsr_r[0]),
        .vec_data_o(vec_data_w),
        .dp_valid_o(dp_valid_w),
        .dp_ready_i(ready_lfsr_r[1]),
        .dp_data_o(dp_data_w)
    );
    always @(posedge clk_i) begin
        fold_o <= (vec_valid_w && ready_lfsr_r[0]
            ? vec_data_w[31:0] ^ vec_data_w[63:32] ^ vec_data_w[95:64]
                ^ vec_data_w[127:96] : 32'b0)
            ^ (dp_valid_w && ready_lfsr_r[1] ? dp_data_w : 32'b0);
    end
endmodule
