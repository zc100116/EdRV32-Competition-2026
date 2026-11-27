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
    // Fully registered native APM cascades absorb the preceding source registers.
    // All downstream result clocks and the nineteen-clock vertex pipeline are preserved.

    wire [49:0] matrix_extend0_0_w;

    wire [49:0] matrix_extend0_1_w;

    wire [49:0] matrix_extend0_2_w;
    wire [34:0] matrix_pair0_0_a0_w;
    wire [34:0] matrix_pair0_0_b0_w;
    reg [35:0] matrix_pair0_0_part0_r;
    wire [34:0] matrix_pair0_0_low0_w;
    wire [14:0] matrix_pair0_0_a1_w;
    wire [14:0] matrix_pair0_0_b1_w;
    reg [14:0] matrix_pair0_0_a1_w_d4_r;
    reg [14:0] matrix_pair0_0_b1_w_d4_r;
    reg [15:0] unused_matrix_pair0_0_part1_r;
    wire [14:0] matrix_pair0_0_low1_w;
    wire [49:0] matrix_pair0_0_w;
    reg [34:0] matrix_pair0_0_low0_w_d5_r;
    wire [34:0] matrix_pair0_1_a0_w;
    wire [34:0] matrix_pair0_1_b0_w;
    reg [35:0] matrix_pair0_1_part0_r;
    wire [34:0] matrix_pair0_1_low0_w;
    wire [14:0] matrix_pair0_1_a1_w;
    wire [14:0] matrix_pair0_1_b1_w;
    reg [14:0] matrix_pair0_1_a1_w_d4_r;
    reg [14:0] matrix_pair0_1_b1_w_d4_r;
    reg [15:0] unused_matrix_pair0_1_part1_r;
    wire [14:0] matrix_pair0_1_low1_w;
    wire [49:0] matrix_pair0_1_w;
    reg [34:0] matrix_pair0_1_low0_w_d5_r;
    wire [34:0] matrix_total0_a0_w;
    wire [34:0] matrix_total0_b0_w;
    reg [35:0] matrix_total0_part0_r;
    wire [34:0] matrix_total0_low0_w;
    wire [14:0] matrix_total0_a1_w;
    wire [14:0] matrix_total0_b1_w;
    reg [14:0] matrix_total0_a1_w_d6_r;
    reg [14:0] matrix_total0_b1_w_d6_r;
    reg [15:0] unused_matrix_total0_part1_r;
    wire [14:0] matrix_total0_low1_w;
    wire [49:0] matrix_total0_w;
    reg [34:0] matrix_total0_low0_w_d7_r;
    reg [39:0] matrix_clamp0_r;

    wire [49:0] matrix_extend1_0_w;

    wire [49:0] matrix_extend1_1_w;

    wire [49:0] matrix_extend1_2_w;
    wire [34:0] matrix_pair1_0_a0_w;
    wire [34:0] matrix_pair1_0_b0_w;
    reg [35:0] matrix_pair1_0_part0_r;
    wire [34:0] matrix_pair1_0_low0_w;
    wire [14:0] matrix_pair1_0_a1_w;
    wire [14:0] matrix_pair1_0_b1_w;
    reg [14:0] matrix_pair1_0_a1_w_d4_r;
    reg [14:0] matrix_pair1_0_b1_w_d4_r;
    reg [15:0] unused_matrix_pair1_0_part1_r;
    wire [14:0] matrix_pair1_0_low1_w;
    wire [49:0] matrix_pair1_0_w;
    reg [34:0] matrix_pair1_0_low0_w_d5_r;
    wire [34:0] matrix_pair1_1_a0_w;
    wire [34:0] matrix_pair1_1_b0_w;
    reg [35:0] matrix_pair1_1_part0_r;
    wire [34:0] matrix_pair1_1_low0_w;
    wire [14:0] matrix_pair1_1_a1_w;
    wire [14:0] matrix_pair1_1_b1_w;
    reg [14:0] matrix_pair1_1_a1_w_d4_r;
    reg [14:0] matrix_pair1_1_b1_w_d4_r;
    reg [15:0] unused_matrix_pair1_1_part1_r;
    wire [14:0] matrix_pair1_1_low1_w;
    wire [49:0] matrix_pair1_1_w;
    reg [34:0] matrix_pair1_1_low0_w_d5_r;
    wire [34:0] matrix_total1_a0_w;
    wire [34:0] matrix_total1_b0_w;
    reg [35:0] matrix_total1_part0_r;
    wire [34:0] matrix_total1_low0_w;
    wire [14:0] matrix_total1_a1_w;
    wire [14:0] matrix_total1_b1_w;
    reg [14:0] matrix_total1_a1_w_d6_r;
    reg [14:0] matrix_total1_b1_w_d6_r;
    reg [15:0] unused_matrix_total1_part1_r;
    wire [14:0] matrix_total1_low1_w;
    wire [49:0] matrix_total1_w;
    reg [34:0] matrix_total1_low0_w_d7_r;
    reg [39:0] matrix_clamp1_r;
    reg [79:0] first_rows_r;
    reg [159:0] coordinates_r;
    reg [7:0] normal0_r;
    reg [15:0] light0_r;
    reg [23:0] light_product0_r;
    reg [23:0] light_product0_p1_r;
    reg [23:0] light_product0_p2_r;
    wire [25:0] light_extend0_w;
    reg [7:0] normal1_r;
    reg [15:0] light1_r;
    reg [23:0] light_product1_r;
    reg [23:0] light_product1_p1_r;
    reg [23:0] light_product1_p2_r;
    wire [25:0] light_extend1_w;
    reg [7:0] normal2_r;
    reg [15:0] light2_r;
    reg [23:0] light_product2_r;
    reg [23:0] light_product2_p1_r;
    reg [23:0] light_product2_p2_r;
    wire [25:0] light_extend2_w;
    reg [25:0] light_pair_r;
    reg [25:0] light_extend2_w_d4_r;
    reg [25:0] unused_light_sum_r;
    reg [23:0] light_dot_r;
    // One local draw-light context; light_i is stable until idle_o (input contract).
    reg [7:0] direct0_r;
    reg [7:0] ambient0_r;

    wire [41:0] color_extend0_w;
    wire [41:0] color_bias0_w;
    wire [34:0] color_round0_a0_w;
    wire [34:0] color_round0_b0_w;
    reg [35:0] color_round0_part0_r;
    wire [34:0] color_round0_low0_w;
    wire [6:0] color_round0_a1_w;
    wire [6:0] color_round0_b1_w;
    reg [6:0] color_round0_a1_w_d14_r;
    reg [6:0] color_round0_b1_w_d14_r;
    reg [7:0] unused_color_round0_part1_r;
    wire [6:0] color_round0_low1_w;
    wire [41:0] unused_color_round0_w;
    reg [34:0] color_round0_low0_w_d15_r;
    reg [20:0] color_integer0_r;
    reg [16:0] unused_color_divide0_r;
    reg [20:0] color_integer0_d17_r;
    reg [23:0] color_clamp0_r;
    reg [7:0] direct1_r;
    reg [7:0] ambient1_r;

    wire [41:0] color_extend1_w;
    wire [41:0] color_bias1_w;
    wire [34:0] color_round1_a0_w;
    wire [34:0] color_round1_b0_w;
    reg [35:0] color_round1_part0_r;
    wire [34:0] color_round1_low0_w;
    wire [6:0] color_round1_a1_w;
    wire [6:0] color_round1_b1_w;
    reg [6:0] color_round1_a1_w_d14_r;
    reg [6:0] color_round1_b1_w_d14_r;
    reg [7:0] unused_color_round1_part1_r;
    wire [6:0] color_round1_low1_w;
    wire [41:0] unused_color_round1_w;
    reg [34:0] color_round1_low0_w_d15_r;
    reg [20:0] color_integer1_r;
    reg [16:0] unused_color_divide1_r;
    reg [20:0] color_integer1_d17_r;
    reg [23:0] color_clamp1_r;
    reg [7:0] direct2_r;
    reg [7:0] ambient2_r;

    wire [41:0] color_extend2_w;
    wire [41:0] color_bias2_w;
    wire [34:0] color_round2_a0_w;
    wire [34:0] color_round2_b0_w;
    reg [35:0] color_round2_part0_r;
    wire [34:0] color_round2_low0_w;
    wire [6:0] color_round2_a1_w;
    wire [6:0] color_round2_b1_w;
    reg [6:0] color_round2_a1_w_d14_r;
    reg [6:0] color_round2_b1_w_d14_r;
    reg [7:0] unused_color_round2_part1_r;
    wire [6:0] color_round2_low1_w;
    wire [41:0] unused_color_round2_w;
    reg [34:0] color_round2_low0_w_d15_r;
    reg [20:0] color_integer2_r;
    reg [16:0] unused_color_divide2_r;
    reg [20:0] color_integer2_d17_r;
    reg [23:0] color_clamp2_r;
    wire [39:0] coordinate0_w;
    wire [39:0] coordinate1_w;
    wire [39:0] coordinate2_w;
    wire [39:0] coordinate3_w;
    reg [39:0] output_0_r [0:1];
    reg [39:0] output_1_r [0:1];
    reg [39:0] output_2_r [0:1];
    reg [39:0] output_3_r [0:1];
    reg [15:0] output_4_r [0:1];
    reg [15:0] output_5_r [0:1];
    reg [23:0] output_6_r [0:1];
    reg [23:0] output_7_r [0:1];
    reg [23:0] output_8_r [0:1];
    reg phase_r;
    reg [47:0] vertex_r;
    wire [47:0] vertex_w;
    wire enable_w;
    wire accept_w;
    wire push_w;
    wire pop_w;
    reg [18:0] valid_r;
    reg [1:0] count_r;
    reg read_r;
    reg write_r;
    wire [7:0] unused_padding_w;
    assign unused_padding_w = vertex_data_i[79:72];
    assign enable_w = count_r != 2 && !stop_i;
    assign vertex_ready_o = enable_w && !phase_r;
    assign accept_w = vertex_valid_i && vertex_ready_o;
    assign vertex_w = phase_r ? vertex_r : vertex_data_i[47:0];
    assign transformed_valid_o = count_r != 0;
    assign push_w = enable_w && valid_r[18];
    assign pop_w = transformed_valid_o && transformed_ready_i;
    assign idle_o = valid_r == 0 && count_r == 0 && !phase_r;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            phase_r <= 0;
            valid_r <= 0;
            count_r <= 0;
            read_r <= 0;
            write_r <= 0;
        end else if (stop_i) begin
            phase_r <= 0;
            valid_r <= 0;
            count_r <= 0;
            read_r <= 0;
            write_r <= 0;
        end else begin
            if (enable_w) begin
                phase_r <= accept_w;
                valid_r <= {valid_r[17:0], accept_w};
            end
            if (push_w) write_r <= !write_r;
            if (pop_w) read_r <= !read_r;
            case ({push_w, pop_w})
                2'b10: count_r <= count_r + 1'b1;
                2'b01: count_r <= count_r - 1'b1;
                default: count_r <= count_r;
            endcase
        end
    end
    assign matrix_extend0_0_w = {{2{matrix_product0_0_p2_r[47]}}, matrix_product0_0_p2_r};
    assign matrix_extend0_1_w = {{2{matrix_product0_1_p2_r[47]}}, matrix_product0_1_p2_r};
    assign matrix_extend0_2_w = {{2{matrix_product0_2_p2_r[47]}}, matrix_product0_2_p2_r};
    assign matrix_pair0_0_a0_w = matrix_extend0_0_w[0 +: 35];
    assign matrix_pair0_0_b0_w = matrix_extend0_1_w[0 +: 35];
    assign matrix_pair0_0_low0_w = matrix_pair0_0_part0_r[34:0];
    assign matrix_pair0_0_a1_w = matrix_extend0_0_w[35 +: 15];
    assign matrix_pair0_0_b1_w = matrix_extend0_1_w[35 +: 15];
    assign matrix_pair0_0_low1_w = unused_matrix_pair0_0_part1_r[14:0];
    assign matrix_pair0_0_w = {matrix_pair0_0_low1_w, matrix_pair0_0_low0_w_d5_r};
    assign matrix_pair0_1_a0_w = matrix_extend0_2_w[0 +: 35];
    assign matrix_pair0_1_b0_w = translation0_context_w[0 +: 35];
    assign matrix_pair0_1_low0_w = matrix_pair0_1_part0_r[34:0];
    assign matrix_pair0_1_a1_w = matrix_extend0_2_w[35 +: 15];
    assign matrix_pair0_1_b1_w = translation0_context_w[35 +: 15];
    assign matrix_pair0_1_low1_w = unused_matrix_pair0_1_part1_r[14:0];
    assign matrix_pair0_1_w = {matrix_pair0_1_low1_w, matrix_pair0_1_low0_w_d5_r};
    assign matrix_total0_a0_w = matrix_pair0_0_w[0 +: 35];
    assign matrix_total0_b0_w = matrix_pair0_1_w[0 +: 35];
    assign matrix_total0_low0_w = matrix_total0_part0_r[34:0];
    assign matrix_total0_a1_w = matrix_pair0_0_w[35 +: 15];
    assign matrix_total0_b1_w = matrix_pair0_1_w[35 +: 15];
    assign matrix_total0_low1_w = unused_matrix_total0_part1_r[14:0];
    assign matrix_total0_w = {matrix_total0_low1_w, matrix_total0_low0_w_d7_r};
    assign matrix_extend1_0_w = {{2{matrix_product1_0_p2_r[47]}}, matrix_product1_0_p2_r};
    assign matrix_extend1_1_w = {{2{matrix_product1_1_p2_r[47]}}, matrix_product1_1_p2_r};
    assign matrix_extend1_2_w = {{2{matrix_product1_2_p2_r[47]}}, matrix_product1_2_p2_r};
    assign matrix_pair1_0_a0_w = matrix_extend1_0_w[0 +: 35];
    assign matrix_pair1_0_b0_w = matrix_extend1_1_w[0 +: 35];
    assign matrix_pair1_0_low0_w = matrix_pair1_0_part0_r[34:0];
    assign matrix_pair1_0_a1_w = matrix_extend1_0_w[35 +: 15];
    assign matrix_pair1_0_b1_w = matrix_extend1_1_w[35 +: 15];
    assign matrix_pair1_0_low1_w = unused_matrix_pair1_0_part1_r[14:0];
    assign matrix_pair1_0_w = {matrix_pair1_0_low1_w, matrix_pair1_0_low0_w_d5_r};
    assign matrix_pair1_1_a0_w = matrix_extend1_2_w[0 +: 35];
    assign matrix_pair1_1_b0_w = translation1_context_w[0 +: 35];
    assign matrix_pair1_1_low0_w = matrix_pair1_1_part0_r[34:0];
    assign matrix_pair1_1_a1_w = matrix_extend1_2_w[35 +: 15];
    assign matrix_pair1_1_b1_w = translation1_context_w[35 +: 15];
    assign matrix_pair1_1_low1_w = unused_matrix_pair1_1_part1_r[14:0];
    assign matrix_pair1_1_w = {matrix_pair1_1_low1_w, matrix_pair1_1_low0_w_d5_r};
    assign matrix_total1_a0_w = matrix_pair1_0_w[0 +: 35];
    assign matrix_total1_b0_w = matrix_pair1_1_w[0 +: 35];
    assign matrix_total1_low0_w = matrix_total1_part0_r[34:0];
    assign matrix_total1_a1_w = matrix_pair1_0_w[35 +: 15];
    assign matrix_total1_b1_w = matrix_pair1_1_w[35 +: 15];
    assign matrix_total1_low1_w = unused_matrix_total1_part1_r[14:0];
    assign matrix_total1_w = {matrix_total1_low1_w, matrix_total1_low0_w_d7_r};
    assign light_extend0_w = {{2{light_product0_p2_r[23]}}, light_product0_p2_r};
    assign light_extend1_w = {{2{light_product1_p2_r[23]}}, light_product1_p2_r};
    assign light_extend2_w = {{2{light_product2_p2_r[23]}}, light_product2_p2_r};
    assign color_extend0_w = {1'b0, color_product0_p2_r};
    assign color_bias0_w = 42'd267386880;
    assign color_round0_a0_w = color_extend0_w[0 +: 35];
    assign color_round0_b0_w = color_bias0_w[0 +: 35];
    assign color_round0_low0_w = color_round0_part0_r[34:0];
    assign color_round0_a1_w = color_extend0_w[35 +: 7];
    assign color_round0_b1_w = color_bias0_w[35 +: 7];
    assign color_round0_low1_w = unused_color_round0_part1_r[6:0];
    assign unused_color_round0_w = {color_round0_low1_w, color_round0_low0_w_d15_r};
    assign color_extend1_w = {1'b0, color_product1_p2_r};
    assign color_bias1_w = 42'd267386880;
    assign color_round1_a0_w = color_extend1_w[0 +: 35];
    assign color_round1_b0_w = color_bias1_w[0 +: 35];
    assign color_round1_low0_w = color_round1_part0_r[34:0];
    assign color_round1_a1_w = color_extend1_w[35 +: 7];
    assign color_round1_b1_w = color_bias1_w[35 +: 7];
    assign color_round1_low1_w = unused_color_round1_part1_r[6:0];
    assign unused_color_round1_w = {color_round1_low1_w, color_round1_low0_w_d15_r};
    assign color_extend2_w = {1'b0, color_product2_p2_r};
    assign color_bias2_w = 42'd267386880;
    assign color_round2_a0_w = color_extend2_w[0 +: 35];
    assign color_round2_b0_w = color_bias2_w[0 +: 35];
    assign color_round2_low0_w = color_round2_part0_r[34:0];
    assign color_round2_a1_w = color_extend2_w[35 +: 7];
    assign color_round2_b1_w = color_bias2_w[35 +: 7];
    assign color_round2_low1_w = unused_color_round2_part1_r[6:0];
    assign unused_color_round2_w = {color_round2_low1_w, color_round2_low0_w_d15_r};
    assign coordinate0_w = coordinates_r[0 +: 40];
    assign coordinate1_w = coordinates_r[40 +: 40];
    assign coordinate2_w = coordinates_r[80 +: 40];
    assign coordinate3_w = coordinates_r[120 +: 40];
    assign transformed_data_o[0 +: 40] = output_0_r[read_r];
    always @(posedge clk_i) begin
        if (push_w) output_0_r[write_r] <= coordinate_delay_w[0 +: 40];
    end
    assign transformed_data_o[40 +: 40] = output_1_r[read_r];
    always @(posedge clk_i) begin
        if (push_w) output_1_r[write_r] <= coordinate_delay_w[40 +: 40];
    end
    assign transformed_data_o[80 +: 40] = output_2_r[read_r];
    always @(posedge clk_i) begin
        if (push_w) output_2_r[write_r] <= coordinate_delay_w[80 +: 40];
    end
    assign transformed_data_o[120 +: 40] = output_3_r[read_r];
    always @(posedge clk_i) begin
        if (push_w) output_3_r[write_r] <= coordinate_delay_w[120 +: 40];
    end
    assign transformed_data_o[160 +: 16] = output_4_r[read_r];
    always @(posedge clk_i) begin
        if (push_w) output_4_r[write_r] <= vertex_uv_w[15:0];
    end
    assign transformed_data_o[176 +: 16] = output_5_r[read_r];
    always @(posedge clk_i) begin
        if (push_w) output_5_r[write_r] <= vertex_uv_w[31:16];
    end
    assign transformed_data_o[192 +: 24] = output_6_r[read_r];
    always @(posedge clk_i) begin
        if (push_w) output_6_r[write_r] <= color_clamp0_r;
    end
    assign transformed_data_o[216 +: 24] = output_7_r[read_r];
    always @(posedge clk_i) begin
        if (push_w) output_7_r[write_r] <= color_clamp1_r;
    end
    assign transformed_data_o[240 +: 24] = output_8_r[read_r];
    always @(posedge clk_i) begin
        if (push_w) output_8_r[write_r] <= color_clamp2_r;
    end
    // Each region owns the output-credit count used by its local clock enable.
    wire [5:0] pipeline_enable_w;
    // Eight enabled clocks of coordinate alignment, packed into three existing 72-bit DRMs.
    // The synchronous read supplies the eighth clock; seven addresses separate read/write.
    reg [5:0] coordinate_write_r;
    wire [5:0] coordinate_read_w;
    wire [215:0] coordinate_store_w;
    wire [215:0] coordinate_delay_w;
    wire [55:0] unused_coordinate_padding_w;
    assign coordinate_store_w = {56'b0, coordinate3_w, coordinate2_w,
        coordinate1_w, coordinate0_w};
    assign coordinate_read_w = coordinate_write_r - 6'd7;
    assign unused_coordinate_padding_w = coordinate_delay_w[215:160];
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) coordinate_write_r <= 6'd0;
        else if (stop_i) coordinate_write_r <= 6'd0;
        else if (pipeline_enable_w[4]) coordinate_write_r <= coordinate_write_r + 6'd1;
    end
    genvar coordinate_ram_g;
    generate
        for (coordinate_ram_g = 0; coordinate_ram_g < 3;
            coordinate_ram_g = coordinate_ram_g + 1) begin : g_coordinate_ram
            wire [71:0] u_delay_data_w;
            reg [71:0] u_delay_data_r;
            assign coordinate_delay_w[coordinate_ram_g*72 +: 72] = u_delay_data_r;
            always @(posedge clk_i) begin
                if (pipeline_enable_w[4]) u_delay_data_r <= u_delay_data_w;
            end
            edrv32_ram_gpu_table u_delay (
                .clk_i(clk_i),

                .wr_en_i(pipeline_enable_w[4]),
                .wr_addr_i(coordinate_write_r),
                .wr_data_i(coordinate_store_w[coordinate_ram_g*72 +: 72]),
                .rd_addr_i(coordinate_read_w),
                .rd_data_o(u_delay_data_w)
            );
        end
    endgenerate
    // Input draw configuration is stable through drain; translation needs only the row tag.
    reg [3:0] translation_phase_r;
    wire [49:0] translation0_context_w;
    wire [49:0] translation1_context_w;
    assign translation0_context_w = translation_phase_r[3] ?
        {{18{matrix_i[383]}}, matrix_i[352 +: 32]} :
        {{18{matrix_i[127]}}, matrix_i[96 +: 32]};
    assign translation1_context_w = translation_phase_r[3] ?
        {{18{matrix_i[511]}}, matrix_i[480 +: 32]} :
        {{18{matrix_i[255]}}, matrix_i[224 +: 32]};
    always @(posedge clk_i) begin
        if (pipeline_enable_w[0]) translation_phase_r <= {translation_phase_r[2:0], phase_r};
    end
    // At II=2, sixteen slots outlive the nineteen-clock vertex pipeline.
    // Store each field once; tags select RGB at clock 10 and UV at clock 18.
    reg [3:0] context_write_r;

    wire [75:0] context_tag_w;
    wire [3:0] color_tag_w;
    wire [3:0] uv_tag_w;
    wire [15:0] vertex_color_w;
    wire [31:0] vertex_uv_w;
    wire [7:0] base_color0_w;
    wire [7:0] base_color1_w;
    wire [7:0] base_color2_w;
    assign color_tag_w = context_tag_w[36 +: 4];
    assign uv_tag_w = context_tag_w[72 +: 4];
    assign vertex_color_w = unused_vertex_color_read0_w[0 +: 16];
    assign vertex_uv_w = unused_vertex_uv_read0_w[0 +: 32];
    assign base_color0_w = {vertex_color_w[15:11], vertex_color_w[15:13]};
    assign base_color1_w = {vertex_color_w[10:5], vertex_color_w[10:9]};
    assign base_color2_w = {vertex_color_w[4:0], vertex_color_w[4:2]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) context_write_r <= 4'd0;
        else if (stop_i) context_write_r <= 4'd0;
        else if (accept_w) context_write_r <= context_write_r + 4'd1;
    end
    genvar context_stage_g;
    generate
        for (context_stage_g = 0; context_stage_g < 19;
            context_stage_g = context_stage_g + 1) begin : g_context_tag
            reg [3:0] tag_r;
            wire [3:0] source_w;
            if (context_stage_g == 0) begin : g_input
                assign source_w = context_write_r;
            end else begin : g_previous
                assign source_w = context_tag_w[(context_stage_g-1)*4 +: 4];
            end
            always @(posedge clk_i) begin
                if (pipeline_enable_w[5]) tag_r <= source_w;
            end
            assign context_tag_w[context_stage_g*4 +: 4] = tag_r;
        end
    endgenerate
    genvar enable_region;
    generate
        for (enable_region = 0; enable_region < 6;
            enable_region = enable_region + 1) begin : g_enable_region
            (* keep = 1 *) reg [1:0] region_count_r /* synthesis syn_preserve=1 */;
            assign pipeline_enable_w[enable_region] = region_count_r != 2 && !stop_i;
            (* keep = 1 *) always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) region_count_r <= 0;
                else if (stop_i) region_count_r <= 0;
                else begin
                    case ({push_w, pop_w})
                        2'b10: region_count_r <= region_count_r + 1'b1;
                        2'b01: region_count_r <= region_count_r - 1'b1;
                        default: region_count_r <= region_count_r;
                    endcase
                end
            end
        end
    endgenerate
    always @(posedge clk_i) begin
        if (pipeline_enable_w[0]) begin

            matrix_pair0_0_part0_r <= {1'b0, matrix_pair0_0_a0_w} + {1'b0, matrix_pair0_0_b0_w};
            matrix_pair0_0_a1_w_d4_r <= matrix_pair0_0_a1_w;
            matrix_pair0_0_b1_w_d4_r <= matrix_pair0_0_b1_w;
            unused_matrix_pair0_0_part1_r <= {1'b0, matrix_pair0_0_a1_w_d4_r} + {1'b0,
                        matrix_pair0_0_b1_w_d4_r} + {15'b0, matrix_pair0_0_part0_r[35]};
            matrix_pair0_0_low0_w_d5_r <= matrix_pair0_0_low0_w;
            matrix_pair0_1_part0_r <= {1'b0, matrix_pair0_1_a0_w} + {1'b0, matrix_pair0_1_b0_w};
            matrix_pair0_1_a1_w_d4_r <= matrix_pair0_1_a1_w;
            matrix_pair0_1_b1_w_d4_r <= matrix_pair0_1_b1_w;
            unused_matrix_pair0_1_part1_r <= {1'b0, matrix_pair0_1_a1_w_d4_r} + {1'b0,
                        matrix_pair0_1_b1_w_d4_r} + {15'b0, matrix_pair0_1_part0_r[35]};
            matrix_pair0_1_low0_w_d5_r <= matrix_pair0_1_low0_w;
            matrix_total0_part0_r <= {1'b0, matrix_total0_a0_w} + {1'b0, matrix_total0_b0_w};
            matrix_total0_a1_w_d6_r <= matrix_total0_a1_w;
            matrix_total0_b1_w_d6_r <= matrix_total0_b1_w;
            unused_matrix_total0_part1_r <= {1'b0, matrix_total0_a1_w_d6_r} + {1'b0,
                        matrix_total0_b1_w_d6_r} + {15'b0, matrix_total0_part0_r[35]};
            matrix_total0_low0_w_d7_r <= matrix_total0_low0_w;
            matrix_clamp0_r <= matrix_total0_w[49] ?
                ((&matrix_total0_w[48:39]) ? matrix_total0_w[39:0] : 40'h8000000000) :
                ((|matrix_total0_w[48:39]) ? 40'h7fffffffff : matrix_total0_w[39:0]);

        end
    end
    always @(posedge clk_i) begin
        if (pipeline_enable_w[1]) begin

            matrix_pair1_0_part0_r <= {1'b0, matrix_pair1_0_a0_w} + {1'b0, matrix_pair1_0_b0_w};
            matrix_pair1_0_a1_w_d4_r <= matrix_pair1_0_a1_w;
            matrix_pair1_0_b1_w_d4_r <= matrix_pair1_0_b1_w;
            unused_matrix_pair1_0_part1_r <= {1'b0, matrix_pair1_0_a1_w_d4_r} + {1'b0,
                        matrix_pair1_0_b1_w_d4_r} + {15'b0, matrix_pair1_0_part0_r[35]};
            matrix_pair1_0_low0_w_d5_r <= matrix_pair1_0_low0_w;
            matrix_pair1_1_part0_r <= {1'b0, matrix_pair1_1_a0_w} + {1'b0, matrix_pair1_1_b0_w};
            matrix_pair1_1_a1_w_d4_r <= matrix_pair1_1_a1_w;
            matrix_pair1_1_b1_w_d4_r <= matrix_pair1_1_b1_w;
            unused_matrix_pair1_1_part1_r <= {1'b0, matrix_pair1_1_a1_w_d4_r} + {1'b0,
                        matrix_pair1_1_b1_w_d4_r} + {15'b0, matrix_pair1_1_part0_r[35]};
            matrix_pair1_1_low0_w_d5_r <= matrix_pair1_1_low0_w;
            matrix_total1_part0_r <= {1'b0, matrix_total1_a0_w} + {1'b0, matrix_total1_b0_w};
            matrix_total1_a1_w_d6_r <= matrix_total1_a1_w;
            matrix_total1_b1_w_d6_r <= matrix_total1_b1_w;
            unused_matrix_total1_part1_r <= {1'b0, matrix_total1_a1_w_d6_r} + {1'b0,
                        matrix_total1_b1_w_d6_r} + {15'b0, matrix_total1_part0_r[35]};
            matrix_total1_low0_w_d7_r <= matrix_total1_low0_w;
            matrix_clamp1_r <= matrix_total1_w[49] ?
                ((&matrix_total1_w[48:39]) ? matrix_total1_w[39:0] : 40'h8000000000) :
                ((|matrix_total1_w[48:39]) ? 40'h7fffffffff : matrix_total1_w[39:0]);
            first_rows_r <= {matrix_clamp1_r, matrix_clamp0_r};
        end
    end
    always @(posedge clk_i) begin
        if (pipeline_enable_w[2]) begin
            coordinates_r <= {matrix_clamp1_r, matrix_clamp0_r, first_rows_r};
            normal0_r <= vertex_data_i[48 +: 8];
            light0_r <= light_i[0 +: 16];
            light_product0_r <= $signed(normal0_r) * $signed(light0_r);
            light_product0_p1_r <= light_product0_r;
            light_product0_p2_r <= light_product0_p1_r;
            normal1_r <= vertex_data_i[56 +: 8];
            light1_r <= light_i[16 +: 16];
            light_product1_r <= $signed(normal1_r) * $signed(light1_r);
            light_product1_p1_r <= light_product1_r;
            light_product1_p2_r <= light_product1_p1_r;
            normal2_r <= vertex_data_i[64 +: 8];
            light2_r <= light_i[32 +: 16];
            light_product2_r <= $signed(normal2_r) * $signed(light2_r);
            light_product2_p1_r <= light_product2_r;
            light_product2_p2_r <= light_product2_p1_r;
            light_pair_r <= light_extend0_w + light_extend1_w;
            light_extend2_w_d4_r <= light_extend2_w;
            unused_light_sum_r <= light_pair_r + light_extend2_w_d4_r;
            light_dot_r <= unused_light_sum_r[25] ? 24'b0 : unused_light_sum_r[23:0];
            direct0_r <= light_i[64 +: 8];
            ambient0_r <= light_i[88 +: 8];

            color_round0_part0_r <= {1'b0, color_round0_a0_w} + {1'b0, color_round0_b0_w};
            color_round0_a1_w_d14_r <= color_round0_a1_w;
            color_round0_b1_w_d14_r <= color_round0_b1_w;
            unused_color_round0_part1_r <= {1'b0, color_round0_a1_w_d14_r} + {1'b0,
                        color_round0_b1_w_d14_r} + {7'b0, color_round0_part0_r[35]};
            color_round0_low0_w_d15_r <= color_round0_low0_w;
            color_integer0_r <= unused_color_round0_w[41:21];
            unused_color_divide0_r <= {1'b0, color_integer0_r[15:0]} + {9'b0,
                color_integer0_r[15:8]}
                        + 17'd1;
            color_integer0_d17_r <= color_integer0_r;
        end
    end
    always @(posedge clk_i) begin
        if (pipeline_enable_w[3]) begin
            color_clamp0_r <= color_integer0_d17_r >= 21'd65025 ? 24'hff0000 :
                        {unused_color_divide0_r[15:8], 16'b0};
            direct1_r <= light_i[56 +: 8];
            ambient1_r <= light_i[80 +: 8];

            color_round1_part0_r <= {1'b0, color_round1_a0_w} + {1'b0, color_round1_b0_w};
            color_round1_a1_w_d14_r <= color_round1_a1_w;
            color_round1_b1_w_d14_r <= color_round1_b1_w;
            unused_color_round1_part1_r <= {1'b0, color_round1_a1_w_d14_r} + {1'b0,
                        color_round1_b1_w_d14_r} + {7'b0, color_round1_part0_r[35]};
            color_round1_low0_w_d15_r <= color_round1_low0_w;
            color_integer1_r <= unused_color_round1_w[41:21];
            unused_color_divide1_r <= {1'b0, color_integer1_r[15:0]} + {9'b0,
                color_integer1_r[15:8]}
                        + 17'd1;
            color_integer1_d17_r <= color_integer1_r;
            color_clamp1_r <= color_integer1_d17_r >= 21'd65025 ? 24'hff0000 :
                        {unused_color_divide1_r[15:8], 16'b0};
            direct2_r <= light_i[48 +: 8];
            ambient2_r <= light_i[72 +: 8];

            color_round2_part0_r <= {1'b0, color_round2_a0_w} + {1'b0, color_round2_b0_w};
            color_round2_a1_w_d14_r <= color_round2_a1_w;
        end
    end
    always @(posedge clk_i) begin
        if (pipeline_enable_w[4]) begin
            color_round2_b1_w_d14_r <= color_round2_b1_w;
            unused_color_round2_part1_r <= {1'b0, color_round2_a1_w_d14_r} + {1'b0,
                        color_round2_b1_w_d14_r} + {7'b0, color_round2_part0_r[35]};
            color_round2_low0_w_d15_r <= color_round2_low0_w;
            color_integer2_r <= unused_color_round2_w[41:21];
            unused_color_divide2_r <= {1'b0, color_integer2_r[15:0]} + {9'b0,
                color_integer2_r[15:8]}
                        + 17'd1;
            color_integer2_d17_r <= color_integer2_r;
            color_clamp2_r <= color_integer2_d17_r >= 21'd65025 ? 24'hff0000 :
                        {unused_color_divide2_r[15:8], 16'b0};
        end
    end
    always @(posedge clk_i) begin
        if (pipeline_enable_w[5]) begin
            if (accept_w) vertex_r <= vertex_data_i[47:0];
        end
    end
    // Explicit LUTRAM vertex_color: 1 slice(s) per combinational read port.
    wire [71:0] vertex_color_input_w;
    assign vertex_color_input_w = {56'b0, vertex_data_i[95:80]};
    wire [71:0] unused_vertex_color_read0_w;
    edrv32_ram_gpu_table u_vertex_color_p0_b0 (
        .clk_i(clk_i),
        .wr_en_i(accept_w),
        .wr_addr_i({2'b0, context_write_r}),
        .wr_data_i(vertex_color_input_w[0 +: 72]),
        .rd_addr_i({2'b0, color_tag_w}),
        .rd_data_o(unused_vertex_color_read0_w[0 +: 72])
    );
    // Explicit LUTRAM vertex_uv: 1 slice(s) per combinational read port.
    wire [71:0] vertex_uv_input_w;
    assign vertex_uv_input_w = {40'b0, vertex_data_i[127:96]};
    wire [71:0] unused_vertex_uv_read0_w;
    edrv32_ram_gpu_table u_vertex_uv_p0_b0 (
        .clk_i(clk_i),
        .wr_en_i(accept_w),
        .wr_addr_i({2'b0, context_write_r}),
        .wr_data_i(vertex_uv_input_w[0 +: 72]),
        .rd_addr_i({2'b0, uv_tag_w}),
        .rd_data_o(unused_vertex_uv_read0_w[0 +: 72])
    );
    // Native input banks absorb the preceding source registers; output clocks stay unchanged.
    wire [47:0] matrix_product0_0_p2_r;
    wire [31:0] coefficient_0_0_apm_w;
    assign coefficient_0_0_apm_w =
        phase_r ? matrix_i[256 +: 32] : matrix_i[0 +: 32];
    edrv32_apm_gpu_s32xs16 u_matrix_product0_0 (
        .clk_i(clk_i),
        .enable_i(pipeline_enable_w[0]),
        .a_i(coefficient_0_0_apm_w),
        .b_i(vertex_w[0 +: 16]),
        .p_o(matrix_product0_0_p2_r)
    );
    wire [47:0] matrix_product0_1_p2_r;
    wire [31:0] coefficient_0_1_apm_w;
    assign coefficient_0_1_apm_w =
        phase_r ? matrix_i[288 +: 32] : matrix_i[32 +: 32];
    edrv32_apm_gpu_s32xs16 u_matrix_product0_1 (
        .clk_i(clk_i),
        .enable_i(pipeline_enable_w[0]),
        .a_i(coefficient_0_1_apm_w),
        .b_i(vertex_w[16 +: 16]),
        .p_o(matrix_product0_1_p2_r)
    );
    wire [47:0] matrix_product0_2_p2_r;
    wire [31:0] coefficient_0_2_apm_w;
    assign coefficient_0_2_apm_w =
        phase_r ? matrix_i[320 +: 32] : matrix_i[64 +: 32];
    edrv32_apm_gpu_s32xs16 u_matrix_product0_2 (
        .clk_i(clk_i),
        .enable_i(pipeline_enable_w[0]),
        .a_i(coefficient_0_2_apm_w),
        .b_i(vertex_w[32 +: 16]),
        .p_o(matrix_product0_2_p2_r)
    );
    wire [47:0] matrix_product1_0_p2_r;
    wire [31:0] coefficient_1_0_apm_w;
    assign coefficient_1_0_apm_w =
        phase_r ? matrix_i[384 +: 32] : matrix_i[128 +: 32];
    edrv32_apm_gpu_s32xs16 u_matrix_product1_0 (
        .clk_i(clk_i),
        .enable_i(pipeline_enable_w[1]),
        .a_i(coefficient_1_0_apm_w),
        .b_i(vertex_w[0 +: 16]),
        .p_o(matrix_product1_0_p2_r)
    );
    wire [47:0] matrix_product1_1_p2_r;
    wire [31:0] coefficient_1_1_apm_w;
    assign coefficient_1_1_apm_w =
        phase_r ? matrix_i[416 +: 32] : matrix_i[160 +: 32];
    edrv32_apm_gpu_s32xs16 u_matrix_product1_1 (
        .clk_i(clk_i),
        .enable_i(pipeline_enable_w[1]),
        .a_i(coefficient_1_1_apm_w),
        .b_i(vertex_w[16 +: 16]),
        .p_o(matrix_product1_1_p2_r)
    );
    wire [47:0] matrix_product1_2_p2_r;
    wire [31:0] coefficient_1_2_apm_w;
    assign coefficient_1_2_apm_w =
        phase_r ? matrix_i[448 +: 32] : matrix_i[192 +: 32];
    edrv32_apm_gpu_s32xs16 u_matrix_product1_2 (
        .clk_i(clk_i),
        .enable_i(pipeline_enable_w[1]),
        .a_i(coefficient_1_2_apm_w),
        .b_i(vertex_w[32 +: 16]),
        .p_o(matrix_product1_2_p2_r)
    );
    wire [31:0] illumination_product0_p2_r;
    edrv32_apm_gpu_u24xu8 u_illumination_product0 (
        .clk_i(clk_i),
        .enable_i(pipeline_enable_w[2]),
        .a_i(light_dot_r),
        .b_i(direct0_r),
        .p_o(illumination_product0_p2_r)
    );
    wire [40:0] color_product0_p2_r;
    wire [32:0] illumination0_apm_w;
    assign illumination0_apm_w =
        {1'b0, illumination_product0_p2_r} + {4'b0, ambient0_r, 21'b0};
    edrv32_apm_gpu_u33xu8 u_color_product0 (
        .clk_i(clk_i),
        .enable_i(pipeline_enable_w[2]),
        .a_i(illumination0_apm_w),
        .b_i(base_color0_w),
        .p_o(color_product0_p2_r)
    );
    wire [31:0] illumination_product1_p2_r;
    edrv32_apm_gpu_u24xu8 u_illumination_product1 (
        .clk_i(clk_i),
        .enable_i(pipeline_enable_w[3]),
        .a_i(light_dot_r),
        .b_i(direct1_r),
        .p_o(illumination_product1_p2_r)
    );
    wire [40:0] color_product1_p2_r;
    wire [32:0] illumination1_apm_w;
    assign illumination1_apm_w =
        {1'b0, illumination_product1_p2_r} + {4'b0, ambient1_r, 21'b0};
    edrv32_apm_gpu_u33xu8 u_color_product1 (
        .clk_i(clk_i),
        .enable_i(pipeline_enable_w[3]),
        .a_i(illumination1_apm_w),
        .b_i(base_color1_w),
        .p_o(color_product1_p2_r)
    );
    wire [31:0] illumination_product2_p2_r;
    edrv32_apm_gpu_u24xu8 u_illumination_product2 (
        .clk_i(clk_i),
        .enable_i(pipeline_enable_w[4]),
        .a_i(light_dot_r),
        .b_i(direct2_r),
        .p_o(illumination_product2_p2_r)
    );
    wire [40:0] color_product2_p2_r;
    wire [32:0] illumination2_apm_w;
    assign illumination2_apm_w =
        {1'b0, illumination_product2_p2_r} + {4'b0, ambient2_r, 21'b0};
    edrv32_apm_gpu_u33xu8 u_color_product2 (
        .clk_i(clk_i),
        .enable_i(pipeline_enable_w[4]),
        .a_i(illumination2_apm_w),
        .b_i(base_color2_w),
        .p_o(color_product2_p2_r)
    );
endmodule
