// File: edrv32_cpu2_fpu_fma64_lz53.v
// Spec: fpu-spec 5.2.
// Description: Parallel classification leading-zero count for a 53-bit significand.
// Clock domain: clk_sys (combinational).
module edrv32_cpu2_fpu_fma64_lz53 (
    input wire [52:0] data_i,
    output wire [5:0] count_o
);
    wire high_hit_w;
    wire low_hit_w;
    wire [4:0] high_count_w;
    wire [4:0] low_count_w;
    edrv32_cpu2_fpu_lza32 u_high (
        .data_i(data_i[52:21]),
        .hit_o(high_hit_w),
        .count_o(high_count_w)
    );
    edrv32_cpu2_fpu_lza32 u_low (
        .data_i({data_i[20:0],11'b0}),
        .hit_o(low_hit_w),
        .count_o(low_count_w)
    );
    assign count_o = high_hit_w ? {1'b0,high_count_w}
        : low_hit_w ? {1'b1,low_count_w} : 6'd53;
endmodule
