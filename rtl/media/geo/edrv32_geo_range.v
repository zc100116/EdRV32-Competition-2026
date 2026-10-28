// File: edrv32_geo_range.v
// Spec: geo-spec 2.4, 5.2, 6.
// Description: Four-stage range check: magnitudes, weighted spans, sums, comparison.
// Clock domain: clk_mem.
module edrv32_geo_range (
    // Clock; the result follows coefficients by four clocks.
    input wire clk_i,
    // Q16.16 matrix coefficients.
    input wire [31:0] a_i,
    input wire [31:0] b_i,
    input wire [31:0] c_i,
    input wire [31:0] d_i,
    // Exact unsigned comparison includes the most negative signed coefficient.
    output reg error_o
);
    reg [31:0] abs_a_r;
    reg [31:0] abs_b_r;
    reg [31:0] abs_c_r;
    reg [31:0] abs_d_r;
    reg [24:0] weighted_a_r;
    reg [24:0] weighted_b_r;
    reg [24:0] weighted_c_r;
    reg [24:0] weighted_d_r;
    reg [24:0] span_x_r;
    reg [24:0] span_y_r;
    reg [1:0] magnitude_error_r;
    always @(posedge clk_i) begin
        abs_a_r <= a_i[31] ? -a_i : a_i;
        abs_b_r <= b_i[31] ? -b_i : b_i;
        abs_c_r <= c_i[31] ? -c_i : c_i;
        abs_d_r <= d_i[31] ? -d_i : d_i;
        weighted_a_r <= {6'd0, abs_a_r[18:0]} * 25'd31;
        weighted_b_r <= {6'd0, abs_b_r[18:0]} * 25'd15;
        weighted_c_r <= {6'd0, abs_c_r[18:0]} * 25'd31;
        weighted_d_r <= {6'd0, abs_d_r[18:0]} * 25'd15;
        // Any magnitude >= 2^19 necessarily exceeds either weighted limit.
        magnitude_error_r <= {magnitude_error_r[0], |{abs_a_r[31:19],
            abs_b_r[31:19], abs_c_r[31:19], abs_d_r[31:19]}};
        span_x_r <= weighted_a_r + weighted_b_r;
        span_y_r <= weighted_c_r + weighted_d_r;
        error_o <= magnitude_error_r[1] ||
            span_x_r > 25'd5111808 || span_y_r > 25'd5111808;
    end
endmodule
