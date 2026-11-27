// File: edrv32_fpga_probe_cpu2_fma_top.v
// Spec: fpu-spec 5.2, 5.3, 7.1; CPU v2 probe P09.
// Description: Register-driven standalone FMA timing probe with serial seed input.
//              Full input and result registers preserve both timing boundaries.
// Clock domain: clk_sys (clk_i, constrained to 150 MHz).
module edrv32_fpga_probe_cpu2_fma_top (
    // Single probe clock and externally injectable LFSR seed bits.
    input wire clk_i,
    input wire [3:0] seed_i,

    // Registered folded observation of every result/flags bit.
    output reg [3:0] observe_o
);
    reg [100:0] stimulus_r;
    reg [31:0] a_r;
    reg [31:0] b_r;
    reg [31:0] c_r;
    reg [1:0] op_r;
    reg [2:0] rm_r;
    wire [31:0] result_w;
    wire [4:0] flags_w;
    reg [31:0] result_r;
    reg [4:0] flags_r;
    always @(posedge clk_i) begin
        stimulus_r <= {stimulus_r[96:0], stimulus_r[100:97]
            ^ {4{stimulus_r[100] ^ stimulus_r[95] ^ stimulus_r[94] ^ stimulus_r[93]}}
            ^ seed_i};
        a_r <= stimulus_r[31:0];
        b_r <= stimulus_r[63:32];
        c_r <= stimulus_r[95:64];
        op_r <= stimulus_r[97:96];
        rm_r <= stimulus_r[100] ? 3'b100 : {1'b0, stimulus_r[99:98]};
        result_r <= result_w;
        flags_r <= flags_w;
        observe_o <= result_r[3:0] ^ result_r[7:4] ^ result_r[11:8]
            ^ result_r[15:12] ^ result_r[19:16] ^ result_r[23:20]
            ^ result_r[27:24] ^ result_r[31:28] ^ flags_r[3:0] ^ {3'b0, flags_r[4]};
    end
    edrv32_cpu2_fpu_fma32 u_fma (
        .clk_i(clk_i),
        .a_i(a_r),
        .b_i(b_r),
        .c_i(c_r),
        .op_i(op_r),
        .rm_i(rm_r),
        .result_o(result_w),
        .flags_o(flags_w)
    );
endmodule
