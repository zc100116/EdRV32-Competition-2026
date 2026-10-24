// ============================================================================
// File        : edrv32_geometry_coord_walker.v
// Description : Backpressure-safe affine coordinate walker for Geometry DMA.
// Notes       : Configuration uses signed Q16.16 inverse-map coordinates.
//               A hardware setup engine computes the origin and per-pixel/row
//               increments before launch. The walker therefore needs adders,
//               not dividers or per-pixel multipliers. Fractional outputs feed
//               the bilinear sampler.
// ============================================================================

module edrv32_geometry_coord_walker (
    input  wire                     clk_i,
    input  wire                     rst_n_i,

    input  wire                     cfg_start_i,
    input  wire [15:0]              cfg_dst_width_i,
    input  wire [15:0]              cfg_dst_height_i,
    input  wire [15:0]              cfg_src_width_i,
    input  wire [15:0]              cfg_src_height_i,
    input  wire signed [31:0]        cfg_origin_x_i,
    input  wire signed [31:0]        cfg_origin_y_i,
    input  wire signed [31:0]        cfg_pixel_step_x_i,
    input  wire signed [31:0]        cfg_pixel_step_y_i,
    input  wire signed [31:0]        cfg_row_step_x_i,
    input  wire signed [31:0]        cfg_row_step_y_i,

    output wire                     coord_valid_o,
    input  wire                     coord_ready_i,
    output wire [15:0]              dst_x_o,
    output wire [15:0]              dst_y_o,
    output wire signed [15:0]        src_x_o,
    output wire signed [15:0]        src_y_o,
    output wire [15:0]              src_x_frac_o,
    output wire [15:0]              src_y_frac_o,
    output wire                     src_in_bounds_o,
    output wire                     sof_o,
    output wire                     eol_o,
    output wire                     eof_o,

    output wire                     busy_o,
    output wire                     done_o,
    output wire                     error_o
);

    reg active_r;
    reg done_r;
    reg error_r;
    reg [15:0] dst_width_r;
    reg [15:0] dst_height_r;
    reg [15:0] src_width_r;
    reg [15:0] src_height_r;
    reg [15:0] dst_x_r;
    reg [15:0] dst_y_r;
    reg signed [31:0] row_x_r;
    reg signed [31:0] row_y_r;
    reg signed [31:0] sample_x_r;
    reg signed [31:0] sample_y_r;
    reg signed [31:0] pixel_step_x_r;
    reg signed [31:0] pixel_step_y_r;
    reg signed [31:0] row_step_x_r;
    reg signed [31:0] row_step_y_r;

    wire coord_fire_w = active_r && coord_ready_i;
    wire line_last_w = dst_x_r == dst_width_r - 1'b1;
    wire frame_last_w = line_last_w &&
        (dst_y_r == dst_height_r - 1'b1);
    wire signed [15:0] sample_x_integer_w = sample_x_r[31:16];
    wire signed [15:0] sample_y_integer_w = sample_y_r[31:16];
    wire sample_x_nonnegative_w = !sample_x_integer_w[15];
    wire sample_y_nonnegative_w = !sample_y_integer_w[15];
    wire sample_x_in_range_w = sample_x_nonnegative_w &&
        ($unsigned(sample_x_integer_w) < src_width_r);
    wire sample_y_in_range_w = sample_y_nonnegative_w &&
        ($unsigned(sample_y_integer_w) < src_height_r);

    assign coord_valid_o = active_r;
    assign dst_x_o = dst_x_r;
    assign dst_y_o = dst_y_r;
    assign src_x_o = sample_x_integer_w;
    assign src_y_o = sample_y_integer_w;
    assign src_x_frac_o = sample_x_r[15:0];
    assign src_y_frac_o = sample_y_r[15:0];
    assign src_in_bounds_o = sample_x_in_range_w && sample_y_in_range_w;
    assign sof_o = active_r && (dst_x_r == 0) && (dst_y_r == 0);
    assign eol_o = active_r && line_last_w;
    assign eof_o = active_r && frame_last_w;
    assign busy_o = active_r;
    assign done_o = done_r;
    assign error_o = error_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            active_r <= 1'b0;
            done_r <= 1'b0;
            error_r <= 1'b0;
            dst_width_r <= 16'b0;
            dst_height_r <= 16'b0;
            src_width_r <= 16'b0;
            src_height_r <= 16'b0;
            dst_x_r <= 16'b0;
            dst_y_r <= 16'b0;
            row_x_r <= 32'sb0;
            row_y_r <= 32'sb0;
            sample_x_r <= 32'sb0;
            sample_y_r <= 32'sb0;
            pixel_step_x_r <= 32'sb0;
            pixel_step_y_r <= 32'sb0;
            row_step_x_r <= 32'sb0;
            row_step_y_r <= 32'sb0;
        end else begin
            done_r <= 1'b0;

            if (cfg_start_i) begin
                if (active_r) begin
                    error_r <= 1'b1;
                end else if ((cfg_dst_width_i == 0) ||
                             (cfg_dst_height_i == 0) ||
                             (cfg_src_width_i == 0) ||
                             (cfg_src_height_i == 0)) begin
                    error_r <= 1'b1;
                    done_r <= 1'b1;
                end else begin
                    active_r <= 1'b1;
                    error_r <= 1'b0;
                    dst_width_r <= cfg_dst_width_i;
                    dst_height_r <= cfg_dst_height_i;
                    src_width_r <= cfg_src_width_i;
                    src_height_r <= cfg_src_height_i;
                    dst_x_r <= 16'b0;
                    dst_y_r <= 16'b0;
                    row_x_r <= cfg_origin_x_i;
                    row_y_r <= cfg_origin_y_i;
                    sample_x_r <= cfg_origin_x_i;
                    sample_y_r <= cfg_origin_y_i;
                    pixel_step_x_r <= cfg_pixel_step_x_i;
                    pixel_step_y_r <= cfg_pixel_step_y_i;
                    row_step_x_r <= cfg_row_step_x_i;
                    row_step_y_r <= cfg_row_step_y_i;
                end
            end

            if (coord_fire_w) begin
                if (frame_last_w) begin
                    active_r <= 1'b0;
                    done_r <= 1'b1;
                    dst_x_r <= 16'b0;
                    dst_y_r <= 16'b0;
                end else if (line_last_w) begin
                    dst_x_r <= 16'b0;
                    dst_y_r <= dst_y_r + 1'b1;
                    row_x_r <= row_x_r + row_step_x_r;
                    row_y_r <= row_y_r + row_step_y_r;
                    sample_x_r <= row_x_r + row_step_x_r;
                    sample_y_r <= row_y_r + row_step_y_r;
                end else begin
                    dst_x_r <= dst_x_r + 1'b1;
                    sample_x_r <= sample_x_r + pixel_step_x_r;
                    sample_y_r <= sample_y_r + pixel_step_y_r;
                end
            end
        end
    end

endmodule
