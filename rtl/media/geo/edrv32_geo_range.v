// File: edrv32_geo_range.v
// Spec: geo-spec 2.4, 5.2, 6.
// Description: Check the fixed 32x16 block against the logical 80x80 source capacity.
// Clock domain: clk_mem.
module edrv32_geo_range (
    // Q16.16 matrix coefficients.
    input wire [31:0] a_i,
    input wire [31:0] b_i,
    input wire [31:0] c_i,
    input wire [31:0] d_i,
    // Exact unsigned comparison includes the most negative signed coefficient.
    output wire error_o
);
    wire [31:0] abs_a_w;
    wire [31:0] abs_b_w;
    wire [31:0] abs_c_w;
    wire [31:0] abs_d_w;
    wire [24:0] span_x_w;
    wire [24:0] span_y_w;
    assign abs_a_w = a_i[31] ? -a_i : a_i;
    assign abs_b_w = b_i[31] ? -b_i : b_i;
    assign abs_c_w = c_i[31] ? -c_i : c_i;
    assign abs_d_w = d_i[31] ? -d_i : d_i;
    assign span_x_w = {6'd0, abs_a_w[18:0]} * 25'd31 + {6'd0, abs_b_w[18:0]} * 25'd15;
    assign span_y_w = {6'd0, abs_c_w[18:0]} * 25'd31 + {6'd0, abs_d_w[18:0]} * 25'd15;
    // Any magnitude >= 2^19 necessarily exceeds either weighted limit.
    assign error_o = |{abs_a_w[31:19], abs_b_w[31:19],
        abs_c_w[31:19], abs_d_w[31:19]} ||
        span_x_w > 25'd5111808 || span_y_w > 25'd5111808;
endmodule
