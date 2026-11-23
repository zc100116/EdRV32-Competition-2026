// File: edrv32_gpu_setup.v
// Spec: gpu-spec 2.5, 2.12, 2.13.1-6; GPU microarchitecture 4.2-4.4.
// Description: Independent area reciprocal and seven overlapping attribute launches per triangle.
//              Sixteen ordered contexts and two output slots absorb downstream backpressure.
// Clock domain: clk_gpu.
module edrv32_gpu_setup (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Screen triangle stream.
    input wire screen_triangle_valid_i,
    output wire screen_triangle_ready_o,
    input wire [50:0] screen_triangle_x_i,
    input wire [50:0] screen_triangle_y_i,
    input wire [47:0] screen_triangle_depth_i,
    input wire [104:0] screen_triangle_q_i,
    input wire [152:0] screen_triangle_uq_i,
    input wire [152:0] screen_triangle_vq_i,
    input wire [215:0] screen_triangle_color_i,

    // Established triangle stream.
    output wire triangle_setup_valid_o,
    input wire triangle_setup_ready_i,
    output wire [63:0] triangle_setup_bounds_o,
    output wire [479:0] triangle_setup_edge_o,
    output wire [31:0] triangle_setup_origin_o,
    output wire [489:0] triangle_setup_start_o,
    output wire [783:0] triangle_setup_gradient_o,
    output wire [69:0] triangle_setup_h_o,
    output wire [173:0] triangle_setup_normal_gradient_o,

    // Command lifetime and performance event.
    input wire finish_i,
    input wire stop_i,
    output reg unit_done_o,
    output wire perf_triangle_o
);
    wire enable_w;
    wire accept_w;
    wire pop_w;
    wire complete_w;
    wire push_w;
    reg [2:0] interval_r;
    reg [3:0] allocate_r;
    reg [4:0] pending_r;
    reg [1:0] output_count_r;
    reg output_read_r;
    reg output_write_r;
    reg [2093:0] output_r [0:1];
    reg [152:0] attribute_r [0:15][0:6];
    reg [71:0] delta_r [0:15];
    reg [35:0] offset_r [0:15];
    reg [31:0] origin_r [0:15];
    reg [63:0] bounds_r [0:15];
    reg [479:0] edge_r [0:15];
    reg [489:0] start_r [0:15];
    reg [783:0] gradient_r [0:15];
    reg [69:0] h_r [0:15];
    reg [173:0] normal_r [0:15];
    reg nonzero_r [0:15];
    reg area_valid_r;
    reg signed [17:0] front_delta_x_r [0:2];
    reg signed [17:0] front_delta_y_r [0:2];
    reg signed [17:0] front_offset_x_r [0:2];
    reg signed [17:0] front_offset_y_r [0:2];
    reg signed [17:0] multiply_a_w [0:1];
    reg signed [17:0] multiply_b_w [0:1];
    reg signed [35:0] multiply_r [0:1];
    reg edge_valid_r;
    reg [1:0] edge_index_r;
    reg [1:0] edge_index_w;
    reg [3:0] front_tag_r;
    reg signed [36:0] edge_result_w;
    reg [3:0] area_tag_r;
    reg [3:0] reciprocal_tag_r [0:9];
    wire reciprocal_valid_w;
    wire [30:0] reciprocal_w;
    wire [5:0] reciprocal_exponent_w;
    reg attribute_valid_r;
    reg [2:0] attribute_index_r;
    reg [3:0] attribute_tag_r;
    reg [30:0] attribute_reciprocal_r;
    reg [5:0] attribute_exponent_r;
    wire plane_valid_w;
    wire [6:0] plane_tag_w;
    wire [69:0] plane_start_w;
    wire [111:0] plane_gradient_w;
    wire [9:0] plane_h_w;
    wire [57:0] plane_normal_w;
    reg complete_r;
    reg [3:0] complete_tag_r;
    reg signed [17:0] x_w [0:2];
    reg signed [17:0] y_w [0:2];
    reg signed [17:0] minimum_x_w;
    reg signed [17:0] minimum_y_w;
    reg signed [17:0] maximum_x_w;
    reg signed [17:0] maximum_y_w;
    reg signed [17:0] origin_x_w;
    reg signed [17:0] origin_y_w;
    reg signed [17:0] bound_x0_w;
    reg signed [17:0] bound_y0_w;
    reg signed [17:0] unused_bound_x1_w;
    reg signed [17:0] unused_bound_y1_w;
    reg signed [17:0] difference_x_w [0:2];
    reg signed [17:0] difference_y_w [0:2];

    reg signed [35:0] area_w;
    reg [71:0] delta_w;
    reg [35:0] offset_w;
    reg [479:0] edge_w;
    reg signed [17:0] edge_offset_x_w [0:2];
    reg signed [17:0] edge_offset_y_w [0:2];
    reg signed [39:0] edge_value_w;
    reg signed [39:0] edge_dx_w;
    reg signed [39:0] edge_dy_w;
    reg signed [39:0] edge_bias_w;
    integer vertex_w;
    integer next_w;
    integer index_r;

    assign enable_w = output_count_r != 2 && !stop_i;
    assign screen_triangle_ready_o = enable_w && interval_r == 0;
    assign accept_w = screen_triangle_valid_i && screen_triangle_ready_o;
    assign triangle_setup_valid_o = output_count_r != 0;
    assign pop_w = triangle_setup_valid_o && triangle_setup_ready_i;
    assign complete_w = enable_w && complete_r;
    assign push_w = complete_w && nonzero_r[complete_tag_r];
    assign perf_triangle_o = push_w;
    assign triangle_setup_bounds_o = output_r[output_read_r][0 +: 64];
    assign triangle_setup_edge_o = output_r[output_read_r][64 +: 480];
    assign triangle_setup_origin_o = output_r[output_read_r][544 +: 32];
    assign triangle_setup_start_o = output_r[output_read_r][576 +: 490];
    assign triangle_setup_gradient_o = output_r[output_read_r][1066 +: 784];
    assign triangle_setup_h_o = output_r[output_read_r][1850 +: 70];
    assign triangle_setup_normal_gradient_o = output_r[output_read_r][1920 +: 174];

    always @(*) begin
        for (vertex_w = 0; vertex_w < 3; vertex_w = vertex_w + 1) begin
            x_w[vertex_w] = {screen_triangle_x_i[vertex_w * 17 + 16],
                screen_triangle_x_i[vertex_w * 17 +: 17]};
            y_w[vertex_w] = {screen_triangle_y_i[vertex_w * 17 + 16],
                screen_triangle_y_i[vertex_w * 17 +: 17]};
        end
        minimum_x_w = x_w[0];
        minimum_y_w = y_w[0];
        maximum_x_w = x_w[0];
        maximum_y_w = y_w[0];
        for (vertex_w = 1; vertex_w < 3; vertex_w = vertex_w + 1) begin
            if (x_w[vertex_w] < minimum_x_w) minimum_x_w = x_w[vertex_w];
            if (y_w[vertex_w] < minimum_y_w) minimum_y_w = y_w[vertex_w];
            if (x_w[vertex_w] > maximum_x_w) maximum_x_w = x_w[vertex_w];
            if (y_w[vertex_w] > maximum_y_w) maximum_y_w = y_w[vertex_w];
        end
        origin_x_w = minimum_x_w >>> 4;
        origin_y_w = minimum_y_w >>> 4;
        bound_x0_w = ((minimum_x_w + 18'sd7) >>> 6) <<< 2;
        bound_y0_w = (minimum_y_w + 18'sd7) >>> 4;
        unused_bound_x1_w = ((maximum_x_w - 18'sd8) >>> 4) + 18'sd1;
        unused_bound_y1_w = ((maximum_y_w - 18'sd8) >>> 4) + 18'sd1;
        delta_w = 72'd0;
        offset_w = 36'd0;
        edge_w = 480'd0;
        edge_value_w = 40'sd0;
        edge_dx_w = 40'sd0;
        edge_dy_w = 40'sd0;
        edge_bias_w = 40'sd0;
        next_w = 0;
        for (vertex_w = 0; vertex_w < 3; vertex_w = vertex_w + 1) begin
            next_w = vertex_w == 2 ? 0 : vertex_w + 1;
            difference_x_w[vertex_w] = x_w[next_w] - x_w[vertex_w];
            difference_y_w[vertex_w] = y_w[next_w] - y_w[vertex_w];
        end
        area_w = multiply_r[0] - multiply_r[1];
        delta_w = {difference_x_w[0], difference_x_w[2],
            -difference_y_w[0], -difference_y_w[2]};
        offset_w[0 +: 18] = (origin_x_w <<< 4) + 18'sd8 - x_w[0];
        offset_w[18 +: 18] = (origin_y_w <<< 4) + 18'sd8 - y_w[0];
        for (vertex_w = 0; vertex_w < 3; vertex_w = vertex_w + 1) begin
            next_w = vertex_w == 2 ? 0 : vertex_w + 1;
            edge_offset_x_w[vertex_w] = (bound_x0_w <<< 4) + 18'sd8 - x_w[vertex_w];
            edge_offset_y_w[vertex_w] = (bound_y0_w <<< 4) + 18'sd8 - y_w[vertex_w];
            edge_dx_w = -$signed({{22{difference_y_w[vertex_w][17]}},
                difference_y_w[vertex_w]}) <<< 4;
            edge_dy_w = $signed(difference_x_w[vertex_w]) * 40'sd16;
            edge_value_w = 40'sd0;
            edge_bias_w = difference_y_w[vertex_w] < 0
                || (difference_y_w[vertex_w] == 0 && difference_x_w[vertex_w] > 0)
                ? 40'sd0 : -40'sd1;
            // Raster edge order is (b,c), (c,a), (a,b), as for the attribute weights.
            next_w = vertex_w == 0 ? 2 : vertex_w - 1;
            edge_w[next_w * 160 +: 160] =
                {edge_bias_w, edge_dy_w, edge_dx_w, edge_value_w};
        end
    end

    // Two front-end APMs issue area once and the three edge starts on the next clocks.
    always @(*) begin
        multiply_a_w[0] = difference_x_w[0];
        multiply_b_w[0] = -difference_y_w[2];
        multiply_a_w[1] = difference_y_w[0];
        multiply_b_w[1] = -difference_x_w[2];
        edge_index_w = 2'd0;
        edge_result_w = $signed({multiply_r[0][35], multiply_r[0]})
            - $signed({multiply_r[1][35], multiply_r[1]});
        if (!accept_w && interval_r >= 5) begin
            edge_index_w = 2'd3 - interval_r[1:0];
            multiply_a_w[0] = front_delta_x_r[edge_index_w];
            multiply_b_w[0] = front_offset_y_r[edge_index_w];
            multiply_a_w[1] = front_delta_y_r[edge_index_w];
            multiply_b_w[1] = front_offset_x_r[edge_index_w];
        end
    end

    edrv32_gpu_project_recip u_area_reciprocal (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .enable_i(enable_w),
        .stop_i(stop_i),
        .value_valid_i(area_valid_r),
        .value_i({4'd0, area_w}),
        .value_valid_o(reciprocal_valid_w),
        .reciprocal_o(reciprocal_w),
        .exponent_o(reciprocal_exponent_w)
    );

    edrv32_gpu_setup_plane u_plane (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .enable_i(enable_w),
        .stop_i(stop_i),
        .plane_valid_i(attribute_valid_r),
        .plane_tag_i({attribute_tag_r, attribute_index_r}),
        .plane_value_i(attribute_r[attribute_tag_r][attribute_index_r]),
        .plane_delta_i(delta_r[attribute_tag_r]),
        .plane_offset_i(offset_r[attribute_tag_r]),
        .plane_reciprocal_i(attribute_reciprocal_r),
        .plane_exponent_i(attribute_exponent_r),
        .plane_valid_o(plane_valid_w),
        .plane_tag_o(plane_tag_w),
        .plane_start_o(plane_start_w),
        .plane_gradient_o(plane_gradient_w),
        .plane_h_o(plane_h_w),
        .plane_normal_o(plane_normal_w)
    );

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            interval_r <= 3'd0;
            allocate_r <= 4'd0;
            pending_r <= 5'd0;
            output_count_r <= 2'd0;
            output_read_r <= 1'b0;
            output_write_r <= 1'b0;
            area_valid_r <= 1'b0;
            edge_valid_r <= 1'b0;
            attribute_valid_r <= 1'b0;
            attribute_index_r <= 3'd0;
            complete_r <= 1'b0;
            unit_done_o <= 1'b0;
        end else if (stop_i) begin
            interval_r <= 3'd0;
            pending_r <= 5'd0;
            output_count_r <= 2'd0;
            output_read_r <= 1'b0;
            output_write_r <= 1'b0;
            area_valid_r <= 1'b0;
            edge_valid_r <= 1'b0;
            attribute_valid_r <= 1'b0;
            complete_r <= 1'b0;
            unit_done_o <= finish_i;
        end else begin
            if (!finish_i) unit_done_o <= 1'b0;
            else if (pending_r == 0 && output_count_r == 0) unit_done_o <= 1'b1;
            begin
                case ({accept_w, complete_w})
                    2'b10: pending_r <= pending_r + 5'd1;
                    2'b01: pending_r <= pending_r - 5'd1;
                    default: pending_r <= pending_r;
                endcase
            end
            begin
                case ({push_w, pop_w})
                    2'b10: output_count_r <= output_count_r + 2'd1;
                    2'b01: output_count_r <= output_count_r - 2'd1;
                    default: output_count_r <= output_count_r;
                endcase
            end
            if (pop_w) output_read_r <= !output_read_r;
            if (push_w) output_write_r <= !output_write_r;
            if (enable_w) begin
                if (interval_r != 0) interval_r <= interval_r - 3'd1;
                if (accept_w) begin
                    interval_r <= 3'd7;
                    allocate_r <= allocate_r + 4'd1;
                end
                area_valid_r <= accept_w;
                edge_valid_r <= interval_r >= 5;
                complete_r <= plane_valid_w && plane_tag_w[2:0] == 6;
                if (attribute_valid_r) begin
                    attribute_index_r <= attribute_index_r + 3'd1;
                    if (attribute_index_r == 6) attribute_valid_r <= 1'b0;
                end
                if (reciprocal_valid_w) begin
                    attribute_valid_r <= 1'b1;
                    attribute_index_r <= 3'd0;
                end
            end
        end
    end

    always @(posedge clk_i) begin
        if (enable_w) begin
            multiply_r[0] <= multiply_a_w[0] * multiply_b_w[0];
            multiply_r[1] <= multiply_a_w[1] * multiply_b_w[1];
            edge_index_r <= edge_index_w;
            if (area_valid_r) nonzero_r[area_tag_r] <= area_w != 0;
            if (edge_valid_r) begin
                edge_r[front_tag_r][
                    (edge_index_r == 0 ? 32'd2 : {30'd0, edge_index_r} - 32'd1) * 160 +: 40]
                    <= {{3{edge_result_w[36]}}, edge_result_w};
            end
            area_tag_r <= allocate_r;
            reciprocal_tag_r[0] <= area_tag_r;
            for (index_r = 1; index_r < 10; index_r = index_r + 1) begin
                reciprocal_tag_r[index_r] <= reciprocal_tag_r[index_r - 1];
            end
            if (accept_w) begin
                delta_r[allocate_r] <= delta_w;
                offset_r[allocate_r] <= offset_w;
                origin_r[allocate_r] <= {origin_y_w[15:0], origin_x_w[15:0]};
                bounds_r[allocate_r] <= {unused_bound_y1_w[15:0], unused_bound_x1_w[15:0],
                    bound_y0_w[15:0], bound_x0_w[15:0]};
                edge_r[allocate_r] <= edge_w;
                front_tag_r <= allocate_r;
                for (index_r = 0; index_r < 3; index_r = index_r + 1) begin
                    front_delta_x_r[index_r] <= difference_x_w[index_r];
                    front_delta_y_r[index_r] <= difference_y_w[index_r];
                    front_offset_x_r[index_r] <= edge_offset_x_w[index_r];
                    front_offset_y_r[index_r] <= edge_offset_y_w[index_r];
                end
                attribute_r[allocate_r][0] <= {
                    35'd0, screen_triangle_depth_i[32 +: 16],
                    35'd0, screen_triangle_depth_i[16 +: 16],
                    35'd0, screen_triangle_depth_i[0 +: 16]};
                attribute_r[allocate_r][1] <= {
                    16'd0, screen_triangle_q_i[70 +: 35],
                    16'd0, screen_triangle_q_i[35 +: 35],
                    16'd0, screen_triangle_q_i[0 +: 35]};
                attribute_r[allocate_r][2] <= {
                    screen_triangle_uq_i[102 +: 51],
                    screen_triangle_uq_i[51 +: 51],
                    screen_triangle_uq_i[0 +: 51]};
                attribute_r[allocate_r][3] <= {
                    screen_triangle_vq_i[102 +: 51],
                    screen_triangle_vq_i[51 +: 51],
                    screen_triangle_vq_i[0 +: 51]};
                attribute_r[allocate_r][4] <= {
                    27'd0, screen_triangle_color_i[144 +: 24],
                    27'd0, screen_triangle_color_i[72 +: 24],
                    27'd0, screen_triangle_color_i[0 +: 24]};
                attribute_r[allocate_r][5] <= {
                    27'd0, screen_triangle_color_i[168 +: 24],
                    27'd0, screen_triangle_color_i[96 +: 24],
                    27'd0, screen_triangle_color_i[24 +: 24]};
                attribute_r[allocate_r][6] <= {
                    27'd0, screen_triangle_color_i[192 +: 24],
                    27'd0, screen_triangle_color_i[120 +: 24],
                    27'd0, screen_triangle_color_i[48 +: 24]};
            end
            if (reciprocal_valid_w) begin
                attribute_tag_r <= reciprocal_tag_r[9];
                attribute_reciprocal_r <= reciprocal_w;
                attribute_exponent_r <= reciprocal_exponent_w;
            end
            if (plane_valid_w) begin
                start_r[plane_tag_w[6:3]][plane_tag_w[2:0] * 70 +: 70] <= plane_start_w;
                gradient_r[plane_tag_w[6:3]][plane_tag_w[2:0] * 112 +: 112]
                    <= plane_gradient_w;
                h_r[plane_tag_w[6:3]][plane_tag_w[2:0] * 10 +: 10] <= plane_h_w;
                if (plane_tag_w[2:0] >= 1 && plane_tag_w[2:0] <= 3) begin
                    normal_r[plane_tag_w[6:3]][({29'd0, plane_tag_w[2:0]} - 1) * 29 +: 29]
                        <= plane_normal_w[28:0];
                    normal_r[plane_tag_w[6:3]][({29'd0, plane_tag_w[2:0]} + 2) * 29 +: 29]
                        <= plane_normal_w[57:29];
                end
                complete_tag_r <= plane_tag_w[6:3];
            end
        end
        if (push_w) begin
            output_r[output_write_r] <= {normal_r[complete_tag_r], h_r[complete_tag_r],
                gradient_r[complete_tag_r], start_r[complete_tag_r], origin_r[complete_tag_r],
                edge_r[complete_tag_r], bounds_r[complete_tag_r]};
        end
    end
endmodule
