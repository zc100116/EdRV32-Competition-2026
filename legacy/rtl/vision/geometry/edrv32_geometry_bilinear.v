// ============================================================================
// File        : edrv32_geometry_bilinear.v
// Description : Fixed RGB565 bilinear interpolation pipeline.
// Notes       : A credit counter covers the arithmetic pipeline plus a small
//               output queue, so downstream backpressure never overwrites an
//               in-flight sample and ready does not ripple through stages.
// ============================================================================

module edrv32_geometry_bilinear #(
    parameter integer OUTPUT_DEPTH = 8,
    parameter integer OUTPUT_PTR_W = 3
) (
    input  wire         clk_i,
    input  wire         rst_n_i,

    input  wire         sample_valid_i,
    output wire         sample_ready_o,
    input  wire [15:0]  sample_p00_i,
    input  wire [15:0]  sample_p10_i,
    input  wire [15:0]  sample_p01_i,
    input  wire [15:0]  sample_p11_i,
    input  wire [15:0]  sample_frac_x_i,
    input  wire [15:0]  sample_frac_y_i,
    input  wire         sample_in_bounds_i,
    input  wire [15:0]  sample_fill_pixel_i,
    input  wire [15:0]  sample_dst_x_i,
    input  wire [15:0]  sample_dst_y_i,
    input  wire         sample_sof_i,
    input  wire         sample_eol_i,
    input  wire         sample_eof_i,

    output wire         pixel_valid_o,
    input  wire         pixel_ready_i,
    output wire [15:0]  pixel_data_o,
    output wire [15:0]  pixel_dst_x_o,
    output wire [15:0]  pixel_dst_y_o,
    output wire         pixel_sof_o,
    output wire         pixel_eol_o,
    output wire         pixel_eof_o
);

    localparam integer OUTSTANDING_W = $clog2(OUTPUT_DEPTH + 1);

    function [7:0] expand_r5;
        input [4:0] value_i;
        begin
            expand_r5 = {value_i, value_i[4:2]};
        end
    endfunction

    function [7:0] expand_g6;
        input [5:0] value_i;
        begin
            expand_g6 = {value_i, value_i[5:4]};
        end
    endfunction

    function [23:0] lerp_u8_q16;
        input [7:0] lhs_i;
        input [7:0] rhs_i;
        input [15:0] fraction_i;
        reg signed [8:0] delta_v;
        reg signed [25:0] product_v;
        reg signed [25:0] result_v;
        begin
            delta_v = $signed({1'b0, rhs_i}) - $signed({1'b0, lhs_i});
            product_v = delta_v * $signed({1'b0, fraction_i});
            result_v = $signed({1'b0, lhs_i, 16'b0}) + product_v;
            lerp_u8_q16 = result_v[23:0];
        end
    endfunction

    function [7:0] lerp_q16_u8;
        input [23:0] lhs_i;
        input [23:0] rhs_i;
        input [15:0] fraction_i;
        reg signed [24:0] delta_v;
        reg signed [41:0] product_v;
        reg signed [41:0] result_v;
        begin
            delta_v = $signed({1'b0, rhs_i}) - $signed({1'b0, lhs_i});
            product_v = delta_v * $signed({1'b0, fraction_i});
            result_v = $signed({1'b0, lhs_i, 16'b0}) + product_v +
                42'sd2147483648;
            lerp_q16_u8 = result_v[39:32];
        end
    endfunction

    reg s0_valid_r;
    reg [7:0] s0_r00_r;
    reg [7:0] s0_g00_r;
    reg [7:0] s0_b00_r;
    reg [7:0] s0_r10_r;
    reg [7:0] s0_g10_r;
    reg [7:0] s0_b10_r;
    reg [7:0] s0_r01_r;
    reg [7:0] s0_g01_r;
    reg [7:0] s0_b01_r;
    reg [7:0] s0_r11_r;
    reg [7:0] s0_g11_r;
    reg [7:0] s0_b11_r;
    reg [15:0] s0_frac_x_r;
    reg [15:0] s0_frac_y_r;
    reg s0_in_bounds_r;
    reg [15:0] s0_fill_pixel_r;
    reg [15:0] s0_dst_x_r;
    reg [15:0] s0_dst_y_r;
    reg s0_sof_r;
    reg s0_eol_r;
    reg s0_eof_r;

    reg s1_valid_r;
    reg [23:0] s1_top_r_r;
    reg [23:0] s1_top_g_r;
    reg [23:0] s1_top_b_r;
    reg [23:0] s1_bottom_r_r;
    reg [23:0] s1_bottom_g_r;
    reg [23:0] s1_bottom_b_r;
    reg [15:0] s1_frac_y_r;
    reg s1_in_bounds_r;
    reg [15:0] s1_fill_pixel_r;
    reg [15:0] s1_dst_x_r;
    reg [15:0] s1_dst_y_r;
    reg s1_sof_r;
    reg s1_eol_r;
    reg s1_eof_r;

    reg s2_valid_r;
    reg [15:0] s2_pixel_r;
    reg [15:0] s2_dst_x_r;
    reg [15:0] s2_dst_y_r;
    reg s2_sof_r;
    reg s2_eol_r;
    reg s2_eof_r;

    wire [7:0] s1_result_r_w = lerp_q16_u8(
        s1_top_r_r, s1_bottom_r_r, s1_frac_y_r);
    wire [7:0] s1_result_g_w = lerp_q16_u8(
        s1_top_g_r, s1_bottom_g_r, s1_frac_y_r);
    wire [7:0] s1_result_b_w = lerp_q16_u8(
        s1_top_b_r, s1_bottom_b_r, s1_frac_y_r);
    wire [15:0] s1_bilinear_pixel_w = {
        s1_result_r_w[7:3], s1_result_g_w[7:2], s1_result_b_w[7:3]};

    reg [15:0] fifo_pixel_r [0:OUTPUT_DEPTH-1];
    reg [15:0] fifo_dst_x_r [0:OUTPUT_DEPTH-1];
    reg [15:0] fifo_dst_y_r [0:OUTPUT_DEPTH-1];
    reg fifo_sof_r [0:OUTPUT_DEPTH-1];
    reg fifo_eol_r [0:OUTPUT_DEPTH-1];
    reg fifo_eof_r [0:OUTPUT_DEPTH-1];
    reg [OUTPUT_PTR_W-1:0] fifo_write_ptr_r;
    reg [OUTPUT_PTR_W-1:0] fifo_read_ptr_r;
    reg [OUTSTANDING_W-1:0] fifo_count_r;
    reg [OUTSTANDING_W-1:0] outstanding_r;

    wire sample_fire_w = sample_valid_i && sample_ready_o;
    wire pixel_fire_w = pixel_valid_o && pixel_ready_i;
    wire fifo_push_w = s2_valid_r;

    assign sample_ready_o = outstanding_r < OUTPUT_DEPTH;
    assign pixel_valid_o = fifo_count_r != 0;
    assign pixel_data_o = fifo_pixel_r[fifo_read_ptr_r];
    assign pixel_dst_x_o = fifo_dst_x_r[fifo_read_ptr_r];
    assign pixel_dst_y_o = fifo_dst_y_r[fifo_read_ptr_r];
    assign pixel_sof_o = fifo_sof_r[fifo_read_ptr_r];
    assign pixel_eol_o = fifo_eol_r[fifo_read_ptr_r];
    assign pixel_eof_o = fifo_eof_r[fifo_read_ptr_r];

    generate
        if ((OUTPUT_DEPTH != (1 << OUTPUT_PTR_W)) || (OUTPUT_DEPTH < 4)) begin
            edrv32_geometry_bilinear_output_depth_must_be_power_of_two_at_least_four
                u_static_assert ();
        end
    endgenerate

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            s0_valid_r <= 1'b0;
            s1_valid_r <= 1'b0;
            s2_valid_r <= 1'b0;
            fifo_write_ptr_r <= {OUTPUT_PTR_W{1'b0}};
            fifo_read_ptr_r <= {OUTPUT_PTR_W{1'b0}};
            fifo_count_r <= {OUTSTANDING_W{1'b0}};
            outstanding_r <= {OUTSTANDING_W{1'b0}};
        end else begin
            s0_valid_r <= sample_fire_w;
            s1_valid_r <= s0_valid_r;
            s2_valid_r <= s1_valid_r;

            if (sample_fire_w) begin
                s0_r00_r <= expand_r5(sample_p00_i[15:11]);
                s0_g00_r <= expand_g6(sample_p00_i[10:5]);
                s0_b00_r <= expand_r5(sample_p00_i[4:0]);
                s0_r10_r <= expand_r5(sample_p10_i[15:11]);
                s0_g10_r <= expand_g6(sample_p10_i[10:5]);
                s0_b10_r <= expand_r5(sample_p10_i[4:0]);
                s0_r01_r <= expand_r5(sample_p01_i[15:11]);
                s0_g01_r <= expand_g6(sample_p01_i[10:5]);
                s0_b01_r <= expand_r5(sample_p01_i[4:0]);
                s0_r11_r <= expand_r5(sample_p11_i[15:11]);
                s0_g11_r <= expand_g6(sample_p11_i[10:5]);
                s0_b11_r <= expand_r5(sample_p11_i[4:0]);
                s0_frac_x_r <= sample_frac_x_i;
                s0_frac_y_r <= sample_frac_y_i;
                s0_in_bounds_r <= sample_in_bounds_i;
                s0_fill_pixel_r <= sample_fill_pixel_i;
                s0_dst_x_r <= sample_dst_x_i;
                s0_dst_y_r <= sample_dst_y_i;
                s0_sof_r <= sample_sof_i;
                s0_eol_r <= sample_eol_i;
                s0_eof_r <= sample_eof_i;
            end

            if (s0_valid_r) begin
                s1_top_r_r <= lerp_u8_q16(
                    s0_r00_r, s0_r10_r, s0_frac_x_r);
                s1_top_g_r <= lerp_u8_q16(
                    s0_g00_r, s0_g10_r, s0_frac_x_r);
                s1_top_b_r <= lerp_u8_q16(
                    s0_b00_r, s0_b10_r, s0_frac_x_r);
                s1_bottom_r_r <= lerp_u8_q16(
                    s0_r01_r, s0_r11_r, s0_frac_x_r);
                s1_bottom_g_r <= lerp_u8_q16(
                    s0_g01_r, s0_g11_r, s0_frac_x_r);
                s1_bottom_b_r <= lerp_u8_q16(
                    s0_b01_r, s0_b11_r, s0_frac_x_r);
                s1_frac_y_r <= s0_frac_y_r;
                s1_in_bounds_r <= s0_in_bounds_r;
                s1_fill_pixel_r <= s0_fill_pixel_r;
                s1_dst_x_r <= s0_dst_x_r;
                s1_dst_y_r <= s0_dst_y_r;
                s1_sof_r <= s0_sof_r;
                s1_eol_r <= s0_eol_r;
                s1_eof_r <= s0_eof_r;
            end

            if (s1_valid_r) begin
                s2_pixel_r <= s1_in_bounds_r ?
                    s1_bilinear_pixel_w : s1_fill_pixel_r;
                s2_dst_x_r <= s1_dst_x_r;
                s2_dst_y_r <= s1_dst_y_r;
                s2_sof_r <= s1_sof_r;
                s2_eol_r <= s1_eol_r;
                s2_eof_r <= s1_eof_r;
            end

            if (fifo_push_w) begin
                fifo_pixel_r[fifo_write_ptr_r] <= s2_pixel_r;
                fifo_dst_x_r[fifo_write_ptr_r] <= s2_dst_x_r;
                fifo_dst_y_r[fifo_write_ptr_r] <= s2_dst_y_r;
                fifo_sof_r[fifo_write_ptr_r] <= s2_sof_r;
                fifo_eol_r[fifo_write_ptr_r] <= s2_eol_r;
                fifo_eof_r[fifo_write_ptr_r] <= s2_eof_r;
                fifo_write_ptr_r <= fifo_write_ptr_r + 1'b1;
            end

            if (pixel_fire_w)
                fifo_read_ptr_r <= fifo_read_ptr_r + 1'b1;

            case ({fifo_push_w, pixel_fire_w})
                2'b10: fifo_count_r <= fifo_count_r + 1'b1;
                2'b01: fifo_count_r <= fifo_count_r - 1'b1;
                default: fifo_count_r <= fifo_count_r;
            endcase

            case ({sample_fire_w, pixel_fire_w})
                2'b10: outstanding_r <= outstanding_r + 1'b1;
                2'b01: outstanding_r <= outstanding_r - 1'b1;
                default: outstanding_r <= outstanding_r;
            endcase
        end
    end

endmodule
