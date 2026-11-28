// File: edrv32_fpga_probe_gpu2_sfu_top.v
// Spec: gpu-v2-spec 2.4; G-P02 220 MHz arithmetic/storage probe.
// Description: Registered LFSR scalar requests/setup reads, registered ready and output folding.
// Clock domain: clk_gpu, directly supplied at clk_i.
module edrv32_fpga_probe_gpu2_sfu_top (
    input wire clk_i,
    input wire rst_n_i,
    output reg [31:0] fold_o
);
    reg [31:0] request_lfsr_r;
    reg [31:0] control_lfsr_r;
    wire unused_req_ready_w;
    wire valid0_w;
    wire valid1_w;
    wire [31:0] data0_w;
    wire [31:0] data1_w;
    wire [4:0] tag0_w;
    wire [4:0] tag1_w;
    wire [31:0] setup_seed_w;
    // LFSRs are stimulus control state; arithmetic/data registers are not reset.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            request_lfsr_r <= 32'h19841128;
            control_lfsr_r <= 32'h19761128;
        end else begin
            request_lfsr_r <= {request_lfsr_r[30:0], request_lfsr_r[31]
                ^ request_lfsr_r[21] ^ request_lfsr_r[1] ^ request_lfsr_r[0]};
            control_lfsr_r <= {control_lfsr_r[30:0], control_lfsr_r[31]
                ^ control_lfsr_r[21] ^ control_lfsr_r[1] ^ control_lfsr_r[0]};
        end
    end
    edrv32_gpu2_sfu u_sfu (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .req_valid_i(control_lfsr_r[0]),
        .req_ready_o(unused_req_ready_w),
        .req_op_i(control_lfsr_r[2:1]),
        .req_data_i(request_lfsr_r),
        .req_tag_i(control_lfsr_r[7:3]),
        .resp0_valid_o(valid0_w),
        .resp0_ready_i(control_lfsr_r[8]),
        .resp0_data_o(data0_w),
        .resp0_tag_o(tag0_w),
        .resp1_valid_o(valid1_w),
        .resp1_ready_i(control_lfsr_r[9]),
        .resp1_data_o(data1_w),
        .resp1_tag_o(tag1_w),
        .setup_en_i(control_lfsr_r[10]),
        .setup_index_i(control_lfsr_r[16:11]),
        .setup_seed_o(setup_seed_w)
    );
    always @(posedge clk_i) begin
        fold_o <= setup_seed_w ^ {22'b0, tag0_w, tag1_w}
            ^ (valid0_w && control_lfsr_r[8] ? data0_w : 32'b0)
            ^ (valid1_w && control_lfsr_r[9] ? data1_w : 32'b0);
    end
endmodule
