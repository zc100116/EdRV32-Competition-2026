// File: edrv32_gpu_transform.v
// Spec: gpu-spec 2.4, 2.12; GPU microarchitecture 4.3.
// Description: Six shared matrix multipliers issue two rows per clock, one vertex per two clocks.
//              Full sums saturate once; lighting rounds once before Q16 color expansion.
// Clock domain: clk_gpu.
module edrv32_gpu_transform (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Vertex input with stable draw configuration.
    input wire vertex_valid_i,
    output wire vertex_ready_o,
    input wire [127:0] vertex_data_i,
    input wire [511:0] matrix_i,
    input wire [95:0] light_i,

    // Transformed vertex, coordinates/UV/RGB from low to high.
    output wire transformed_valid_o,
    input wire transformed_ready_i,
    output wire [263:0] transformed_data_o,

    // Drain control.
    input wire stop_i,
    output wire idle_o
);
    reg phase_r;
    wire enable_w;
    wire accept_w;
    reg [127:0] vertex_r;
    wire [127:0] vertex_w;
    reg signed [47:0] matrix_product_r [0:5];
    reg signed [31:0] translation_r [0:1];
    wire signed [49:0] matrix_sum_w [0:1];
    reg [79:0] first_rows_r;
    reg [159:0] coordinates_r [2:5];
    reg signed [23:0] light_product_r [0:2];
    wire signed [25:0] unused_light_sum_w;
    reg [23:0] dot_r;
    reg [31:0] illumination_product_r [0:2];
    reg [32:0] illumination_r [0:2];
    reg [40:0] color_product_r [0:2];
    wire [71:0] rounded_color_w;
    reg [71:0] color_r;
    reg [31:0] uv_r [0:5];
    reg [23:0] base_color_r [0:3];
    reg [5:0] valid_r;
    reg [1:0] count_r;
    reg read_r;
    reg write_r;
    reg [263:0] output_r [0:1];
    wire push_w;
    wire pop_w;
    integer row_r;
    integer column_r;
    integer channel_r;
    integer stage_r;

    function [39:0] coordinate;
        input signed [49:0] value_i;
        begin
            if (value_i > 50'sd549755813887) coordinate = 40'h7fffffffff;
            else if (value_i < -50'sd549755813888) coordinate = 40'h8000000000;
            else coordinate = value_i[39:0];
        end
    endfunction

    function [23:0] light_color;
        input [40:0] value_i;
        reg [41:0] unused_rounded;
        begin
            unused_rounded = ({1'b0, value_i} + 42'd267386880) / 42'd534773760;
            light_color = unused_rounded > 255 ? 24'hff0000
                : {unused_rounded[7:0], 16'd0};
        end
    endfunction

    assign enable_w = count_r != 2 && !stop_i;
    assign vertex_ready_o = enable_w && !phase_r;
    assign accept_w = vertex_valid_i && vertex_ready_o;
    assign vertex_w = phase_r ? vertex_r : vertex_data_i;
    assign transformed_valid_o = count_r != 0;
    assign transformed_data_o = output_r[read_r];
    assign push_w = enable_w && valid_r[5];
    assign pop_w = transformed_valid_o && transformed_ready_i;
    assign idle_o = valid_r == 0 && count_r == 0 && !phase_r;
    assign unused_light_sum_w = $signed({{2{light_product_r[0][23]}}, light_product_r[0]})
        + $signed({{2{light_product_r[1][23]}}, light_product_r[1]})
        + $signed({{2{light_product_r[2][23]}}, light_product_r[2]});
    assign rounded_color_w = {light_color(color_product_r[2]),
        light_color(color_product_r[1]), light_color(color_product_r[0])};

    genvar row_g;
    generate
        for (row_g = 0; row_g < 2; row_g = row_g + 1) begin : g_sum
            assign matrix_sum_w[row_g] =
                $signed({{2{matrix_product_r[row_g * 3][47]}}, matrix_product_r[row_g * 3]})
                + $signed({{2{matrix_product_r[row_g * 3 + 1][47]}},
                    matrix_product_r[row_g * 3 + 1]})
                + $signed({{2{matrix_product_r[row_g * 3 + 2][47]}},
                    matrix_product_r[row_g * 3 + 2]})
                + $signed({{18{translation_r[row_g][31]}}, translation_r[row_g]});
        end
    endgenerate

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            phase_r <= 1'b0;
            valid_r <= 6'd0;
            count_r <= 2'd0;
            read_r <= 1'b0;
            write_r <= 1'b0;
        end else if (stop_i) begin
            phase_r <= 1'b0;
            valid_r <= 6'd0;
            count_r <= 2'd0;
            read_r <= 1'b0;
            write_r <= 1'b0;
        end else begin
            if (enable_w) begin
                phase_r <= accept_w;
                valid_r <= {valid_r[4:0], accept_w};
            end
            if (push_w) write_r <= !write_r;
            if (pop_w) read_r <= !read_r;
            begin
                case ({push_w, pop_w})
                    2'b10: count_r <= count_r + 2'd1;
                    2'b01: count_r <= count_r - 2'd1;
                    default: count_r <= count_r;
                endcase
            end
        end
    end

    always @(posedge clk_i) begin
        if (enable_w) begin
            if (accept_w) vertex_r <= vertex_data_i;
            for (row_r = 0; row_r < 2; row_r = row_r + 1) begin
                for (column_r = 0; column_r < 3; column_r = column_r + 1) begin
                    matrix_product_r[row_r * 3 + column_r] <=
                        $signed(matrix_i[((phase_r ? 2 : 0) + row_r) * 128
                            + column_r * 32 +: 32])
                        * $signed(vertex_w[column_r * 16 +: 16]);
                end
                translation_r[row_r] <=
                    matrix_i[((phase_r ? 2 : 0) + row_r) * 128 + 96 +: 32];
            end
            first_rows_r <= {coordinate(matrix_sum_w[1]), coordinate(matrix_sum_w[0])};
            coordinates_r[2] <= {coordinate(matrix_sum_w[1]),
                coordinate(matrix_sum_w[0]), first_rows_r};
            for (stage_r = 3; stage_r < 6; stage_r = stage_r + 1) begin
                coordinates_r[stage_r] <= coordinates_r[stage_r - 1];
            end
            light_product_r[0] <= $signed(vertex_data_i[55:48]) * $signed(light_i[15:0]);
            light_product_r[1] <= $signed(vertex_data_i[63:56]) * $signed(light_i[31:16]);
            light_product_r[2] <= $signed(vertex_data_i[71:64]) * $signed(light_i[47:32]);
            dot_r <= unused_light_sum_w[25] ? 24'd0 : unused_light_sum_w[23:0];
            base_color_r[0] <= {vertex_data_i[84:80], vertex_data_i[84:82],
                vertex_data_i[90:85], vertex_data_i[90:89],
                vertex_data_i[95:91], vertex_data_i[95:93]};
            for (stage_r = 1; stage_r < 4; stage_r = stage_r + 1) begin
                base_color_r[stage_r] <= base_color_r[stage_r - 1];
            end
            for (channel_r = 0; channel_r < 3; channel_r = channel_r + 1) begin
                illumination_product_r[channel_r] <= dot_r
                    * light_i[64 - channel_r * 8 +: 8];
                illumination_r[channel_r] <= {1'b0, illumination_product_r[channel_r]}
                    + ({25'd0, light_i[88 - channel_r * 8 +: 8]} << 21);
                color_product_r[channel_r] <= illumination_r[channel_r]
                    * base_color_r[3][channel_r * 8 +: 8];
            end
            color_r <= rounded_color_w;
            uv_r[0] <= vertex_data_i[127:96];
            for (stage_r = 1; stage_r < 6; stage_r = stage_r + 1) begin
                uv_r[stage_r] <= uv_r[stage_r - 1];
            end
        end
        if (push_w) begin
            output_r[write_r] <= {color_r, uv_r[5], coordinates_r[5]};
        end
    end
endmodule
