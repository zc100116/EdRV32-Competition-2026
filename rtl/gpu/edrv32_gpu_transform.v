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
    wire [7:0] unused_vertex_padding_w;
    assign unused_vertex_padding_w = vertex_data_i[79:72];

    reg phase_r;
    wire enable_w;
    wire accept_w;
    reg [47:0] vertex_r;
    wire [47:0] vertex_w;
    wire signed [47:0] matrix_product_w [0:5];
    wire signed [31:0] translation_w [0:1];
    wire signed [49:0] matrix_sum_w [0:1];
    reg [79:0] first_rows_r;
    wire [159:0] coordinates_w [2:5];
    wire signed [23:0] light_product_w [0:2];
    wire signed [25:0] unused_light_sum_w;
    reg [23:0] dot_r;
    wire [31:0] illumination_product_w [0:2];
    wire [32:0] illumination_w [0:2];
    wire [40:0] color_product_w [0:2];
    wire [71:0] rounded_color_w;
    reg [71:0] color_r;
    wire [31:0] uv_w [0:5];
    wire [23:0] base_color_w [0:3];
    reg [5:0] valid_r;
    reg [1:0] count_r;
    reg read_r;
    reg write_r;
    wire [39:0] coordinate_w [0:1];
    wire [23:0] light_color_w [0:2];
    wire push_w;
    wire pop_w;

    assign enable_w = count_r != 2 && !stop_i;
    assign vertex_ready_o = enable_w && !phase_r;
    assign accept_w = vertex_valid_i && vertex_ready_o;
    assign vertex_w = phase_r ? vertex_r : vertex_data_i[47:0];
    assign transformed_valid_o = count_r != 0;
    assign push_w = enable_w && valid_r[5];
    assign pop_w = transformed_valid_o && transformed_ready_i;
    assign idle_o = valid_r == 0 && count_r == 0 && !phase_r;
    assign unused_light_sum_w = $signed({{2{light_product_w[0][23]}}, light_product_w[0]})
        + $signed({{2{light_product_w[1][23]}}, light_product_w[1]})
        + $signed({{2{light_product_w[2][23]}}, light_product_w[2]});
    assign rounded_color_w = {light_color_w[2], light_color_w[1], light_color_w[0]};

    genvar row_g;
    genvar column_g;
    genvar channel_g;
    genvar stage_g;
    genvar field_g;
    generate
        for (row_g = 0; row_g < 2; row_g = row_g + 1) begin : g_sum
            // Issue stage: two rows of three 32x16 matrix multipliers and translation muxes.
            wire [31:0] translation_input_w;
            reg signed [31:0] translation_r;
            assign translation_w[row_g] = translation_r;
            assign translation_input_w = phase_r ? matrix_i[(row_g + 2) * 128 + 96 +: 32]
                : matrix_i[row_g * 128 + 96 +: 32];
            always @(posedge clk_i) begin
                if (enable_w) translation_r <= translation_input_w;
            end
            for (column_g = 0; column_g < 3; column_g = column_g + 1) begin : g_product
                wire signed [31:0] coefficient_w;
                reg signed [47:0] product_r;
                assign matrix_product_w[row_g * 3 + column_g] = product_r;
                assign coefficient_w = phase_r
                    ? matrix_i[(row_g + 2) * 128 + column_g * 32 +: 32]
                    : matrix_i[row_g * 128 + column_g * 32 +: 32];
                always @(posedge clk_i) begin
                    if (enable_w) product_r
                        <= coefficient_w * $signed(vertex_w[column_g * 16 +: 16]);
                end
            end
            // Sum stage: three s50 adders and two saturation comparators per row.
            assign coordinate_w[row_g] = matrix_sum_w[row_g] > 50'sd549755813887
                ? 40'h7fffffffff : (matrix_sum_w[row_g] < -50'sd549755813888
                ? 40'h8000000000 : matrix_sum_w[row_g][39:0]);
            assign matrix_sum_w[row_g] =
                $signed({{2{matrix_product_w[row_g * 3][47]}}, matrix_product_w[row_g * 3]})
                + $signed({{2{matrix_product_w[row_g * 3 + 1][47]}},
                    matrix_product_w[row_g * 3 + 1]})
                + $signed({{2{matrix_product_w[row_g * 3 + 2][47]}},
                    matrix_product_w[row_g * 3 + 2]})
                + $signed({{18{translation_w[row_g][31]}}, translation_w[row_g]});
        end
        // Three lighting channels: each has one 8x16 normal product at issue, then one
        // 24x8 product, one u33 add, one 33x8 product and one constant divide/round/saturate
        // at the original successive stage boundaries.
        for (channel_g = 0; channel_g < 3; channel_g = channel_g + 1) begin : g_light
            reg signed [23:0] light_product_r;
            reg [31:0] illumination_product_r;
            reg [32:0] illumination_r;
            reg [40:0] color_product_r;
            wire [41:0] rounded_w;
            assign light_product_w[channel_g] = light_product_r;
            assign illumination_product_w[channel_g] = illumination_product_r;
            assign illumination_w[channel_g] = illumination_r;
            assign color_product_w[channel_g] = color_product_r;
            assign rounded_w = ({1'b0, color_product_w[channel_g]} + 42'd267386880)
                / 42'd534773760;
            assign light_color_w[channel_g] = rounded_w > 255
                ? 24'hff0000 : {rounded_w[7:0], 16'd0};
            always @(posedge clk_i) begin
                if (enable_w) begin
                    light_product_r <= $signed(vertex_data_i[48 + channel_g * 8 +: 8])
                        * $signed(light_i[channel_g * 16 +: 16]);
                    illumination_product_r <= dot_r
                        * light_i[64 - channel_g * 8 +: 8];
                    illumination_r <= {1'b0, illumination_product_w[channel_g]}
                        + ({25'd0, light_i[88 - channel_g * 8 +: 8]} << 21);
                    color_product_r <= illumination_w[channel_g]
                        * base_color_w[3][channel_g * 8 +: 8];
                end
            end
        end
        for (stage_g = 2; stage_g < 6; stage_g = stage_g + 1) begin : g_coordinates
            reg [159:0] data_r;
            wire [159:0] next_w;
            if (stage_g == 2) begin : g_first
                assign next_w = {coordinate_w[1], coordinate_w[0], first_rows_r};
            end else begin : g_delay
                assign next_w = coordinates_w[stage_g - 1];
            end
            assign coordinates_w[stage_g] = data_r;
            always @(posedge clk_i) begin
                if (enable_w) data_r <= next_w;
            end
        end
        for (stage_g = 0; stage_g < 6; stage_g = stage_g + 1) begin : g_uv
            reg [31:0] data_r;
            wire [31:0] next_w;
            if (stage_g == 0) begin : g_first
                assign next_w = vertex_data_i[127:96];
            end else begin : g_delay
                assign next_w = uv_w[stage_g - 1];
            end
            assign uv_w[stage_g] = data_r;
            always @(posedge clk_i) begin
                if (enable_w) data_r <= next_w;
            end
        end
        for (stage_g = 0; stage_g < 4; stage_g = stage_g + 1) begin : g_base_color
            reg [23:0] data_r;
            wire [23:0] next_w;
            if (stage_g == 0) begin : g_first
                assign next_w = {vertex_data_i[84:80], vertex_data_i[84:82],
                    vertex_data_i[90:85], vertex_data_i[90:89],
                    vertex_data_i[95:91], vertex_data_i[95:93]};
            end else begin : g_delay
                assign next_w = base_color_w[stage_g - 1];
            end
            assign base_color_w[stage_g] = data_r;
            always @(posedge clk_i) begin
                if (enable_w) data_r <= next_w;
            end
        end
        // Output FIFO: nine independent fields, two slots each.
        for (field_g = 0; field_g < 9; field_g = field_g + 1) begin : g_output
            localparam WIDTH = field_g < 4 ? 40 : (field_g < 6 ? 16 : 24);
            localparam OFFSET = field_g < 4 ? field_g * 40
                : (field_g < 6 ? 160 + (field_g - 4) * 16 : 192 + (field_g - 6) * 24);
            reg [WIDTH-1:0] data_r [0:1];
            wire [WIDTH-1:0] next_w;
            if (field_g < 4) begin : g_position
                assign next_w = coordinates_w[5][field_g * 40 +: 40];
            end else if (field_g < 6) begin : g_uv
                assign next_w = uv_w[5][(field_g - 4) * 16 +: 16];
            end else begin : g_color
                assign next_w = color_r[(field_g - 6) * 24 +: 24];
            end
            assign transformed_data_o[OFFSET +: WIDTH] = data_r[read_r];
            always @(posedge clk_i) begin
                if (push_w) data_r[write_r] <= next_w;
            end
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
            if (accept_w) vertex_r <= vertex_data_i[47:0];
            first_rows_r <= {coordinate_w[1], coordinate_w[0]};
            dot_r <= unused_light_sum_w[25] ? 24'd0 : unused_light_sum_w[23:0];
            color_r <= rounded_color_w;
        end
    end
endmodule
