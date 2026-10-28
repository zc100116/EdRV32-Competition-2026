// File: edrv32_geo_bounds.v
// Spec: geo-spec 2.1, 2.2, 5.2.
// Description: Evaluate affine corner extrema, include the bilinear halo, and clip source reads.
// Clock domain: clk_mem.
module edrv32_geo_bounds (
    // Clock and setup. The caller holds block inputs through done.
    input wire clk_i,
    input wire rst_n_i,
    input wire start_i,
    input wire clear_i,
    output reg done_o,
    // Block origin, extent, and matrix.
    input wire [31:0] x_i,
    input wire [31:0] y_i,
    input wire [5:0] width_i,
    input wire [4:0] height_i,
    input wire [31:0] a_i,
    input wire [31:0] b_i,
    input wire [31:0] c_i,
    input wire [31:0] d_i,
    input wire [11:0] src_w_i,
    input wire [11:0] src_h_i,
    // Clipped source rectangle, with x aligned down for DMA.
    output wire empty_o,
    output wire [11:0] origin_x_o,
    output wire [11:0] origin_y_o,
    output wire [15:0] width_bytes_o,
    output wire [11:0] height_o
);
    reg [2:0] remaining_r;
    reg [4:0] columns_r;
    reg [3:0] rows_r;
    reg signed [23:0] a_r;
    reg signed [23:0] b_r;
    reg signed [23:0] c_r;
    reg signed [23:0] d_r;
    reg signed [23:0] dx_r;
    reg signed [23:0] bx_r;
    reg signed [23:0] dy_r;
    reg signed [23:0] by_r;
    wire [5:0] columns_w;
    wire [4:0] rows_w;
    wire signed [31:0] min_x_w;
    wire signed [31:0] min_y_w;
    wire signed [31:0] max_x_w;
    wire signed [31:0] max_y_w;
    wire signed [16:0] left_w;
    wire signed [16:0] top_w;
    wire signed [16:0] right_w;
    wire signed [16:0] bottom_w;
    wire [11:0] clip_left_w;
    wire [11:0] clip_top_w;
    wire [11:0] clip_right_w;
    wire [11:0] clip_bottom_w;
    wire [11:0] covered_columns_w;
    wire unused_w;
    assign unused_w = &{a_i[31:20], b_i[31:20], c_i[31:20], d_i[31:20],
        columns_w[5], rows_w[4], min_x_w[15:0], min_y_w[15:0], max_x_w[15:0],
        max_y_w[15:0], clip_left_w[3:0]};
    // Spec 2.4 was accepted before setup: products fit signed 24 bits.
    assign columns_w = width_i - 6'd1;
    assign rows_w = height_i - 5'd1;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            remaining_r <= 3'd0;
            done_o <= 1'b0;
        end else if (clear_i) begin
            remaining_r <= 3'd0;
            done_o <= 1'b0;
        end else begin
            done_o <= remaining_r == 3'd1;
            if (start_i)
                remaining_r <= 3'd5;
            else if (remaining_r != 0)
                remaining_r <= remaining_r - 3'd1;
        end
    end
    always @(posedge clk_i) begin
        if (start_i) begin
            columns_r <= columns_w[4:0];
            rows_r <= rows_w[3:0];
            a_r <= {{4{a_i[19]}}, a_i[19:0]};
            b_r <= {{4{b_i[19]}}, b_i[19:0]};
            c_r <= {{4{c_i[19]}}, c_i[19:0]};
            d_r <= {{4{d_i[19]}}, d_i[19:0]};
            dx_r <= 24'sd0;
            bx_r <= 24'sd0;
            dy_r <= 24'sd0;
            by_r <= 24'sd0;
        end else if (remaining_r != 0) begin
            if (columns_r[0]) begin
                dx_r <= dx_r + a_r;
                dy_r <= dy_r + c_r;
            end
            if (rows_r[0]) begin
                bx_r <= bx_r + b_r;
                by_r <= by_r + d_r;
            end
            columns_r <= {1'b0, columns_r[4:1]};
            rows_r <= {1'b0, rows_r[3:1]};
            a_r <= a_r << 1;
            b_r <= b_r << 1;
            c_r <= c_r << 1;
            d_r <= d_r << 1;
        end
    end
    assign min_x_w = $signed(x_i) + (dx_r < 0 ? {{8{dx_r[23]}}, dx_r} : 32'sd0) +
        (bx_r < 0 ? {{8{bx_r[23]}}, bx_r} : 32'sd0);
    assign max_x_w = $signed(x_i) + (dx_r > 0 ? {{8{dx_r[23]}}, dx_r} : 32'sd0) +
        (bx_r > 0 ? {{8{bx_r[23]}}, bx_r} : 32'sd0);
    assign min_y_w = $signed(y_i) + (dy_r < 0 ? {{8{dy_r[23]}}, dy_r} : 32'sd0) +
        (by_r < 0 ? {{8{by_r[23]}}, by_r} : 32'sd0);
    assign max_y_w = $signed(y_i) + (dy_r > 0 ? {{8{dy_r[23]}}, dy_r} : 32'sd0) +
        (by_r > 0 ? {{8{by_r[23]}}, by_r} : 32'sd0);
    assign left_w = {min_x_w[31], min_x_w[31:16]};
    assign top_w = {min_y_w[31], min_y_w[31:16]};
    assign right_w = $signed({max_x_w[31], max_x_w[31:16]}) + 17'sd1;
    assign bottom_w = $signed({max_y_w[31], max_y_w[31:16]}) + 17'sd1;
    assign empty_o = src_w_i == 0 || src_h_i == 0 || right_w < 0 || bottom_w < 0 ||
        left_w >= $signed({5'd0, src_w_i}) || top_w >= $signed({5'd0, src_h_i});
    assign clip_left_w = left_w < 0 ? 12'd0 : left_w[11:0];
    assign clip_top_w = top_w < 0 ? 12'd0 : top_w[11:0];
    assign clip_right_w = right_w >= $signed({5'd0, src_w_i}) ?
        src_w_i - 12'd1 : right_w[11:0];
    assign clip_bottom_w = bottom_w >= $signed({5'd0, src_h_i}) ?
        src_h_i - 12'd1 : bottom_w[11:0];
    assign origin_x_o = {clip_left_w[11:4], 4'd0};
    assign origin_y_o = clip_top_w;
    assign covered_columns_w = clip_right_w - origin_x_o + 12'd1;
    assign width_bytes_o = {3'd0, covered_columns_w, 1'b0};
    assign height_o = clip_bottom_w - clip_top_w + 12'd1;
endmodule
