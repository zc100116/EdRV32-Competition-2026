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
    reg [71:0] delta_r [0:15];
    reg [35:0] offset_r [0:15];
    reg [31:0] origin_r [0:15];
    reg [63:0] bounds_r [0:15];
    reg nonzero_r [0:15];
    reg area_valid_r;
    reg signed [17:0] front_delta_x_0_r;
    reg signed [17:0] front_delta_x_1_r;
    reg signed [17:0] front_delta_x_2_r;
    reg signed [17:0] front_delta_y_0_r;
    reg signed [17:0] front_delta_y_1_r;
    reg signed [17:0] front_delta_y_2_r;
    reg signed [17:0] front_offset_x_0_r;
    reg signed [17:0] front_offset_x_1_r;
    reg signed [17:0] front_offset_x_2_r;
    reg signed [17:0] front_offset_y_0_r;
    reg signed [17:0] front_offset_y_1_r;
    reg signed [17:0] front_offset_y_2_r;
    reg signed [17:0] multiply_a_w [0:1];
    reg signed [17:0] multiply_b_w [0:1];
    reg signed [35:0] multiply_0_r;
    reg signed [35:0] multiply_1_r;
    reg edge_valid_r;
    reg [1:0] edge_index_r;
    reg [1:0] edge_index_w;
    reg [3:0] front_tag_r;
    reg signed [36:0] edge_result_w;
    reg [3:0] area_tag_r;
    reg [3:0] reciprocal_tag_0_r;
    reg [3:0] reciprocal_tag_1_r;
    reg [3:0] reciprocal_tag_2_r;
    reg [3:0] reciprocal_tag_3_r;
    reg [3:0] reciprocal_tag_4_r;
    reg [3:0] reciprocal_tag_5_r;
    reg [3:0] reciprocal_tag_6_r;
    reg [3:0] reciprocal_tag_7_r;
    reg [3:0] reciprocal_tag_8_r;
    reg [3:0] reciprocal_tag_9_r;
    wire reciprocal_valid_w;
    wire [30:0] reciprocal_w;
    wire [5:0] reciprocal_exponent_w;
    wire [5:0] reciprocal_exponent_wr_w;
    wire [5:0] reciprocal_exponent_delay_w;
    reg [5:0] reciprocal_exponent_first_r;
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
    reg signed [17:0] edge_offset_x_w [0:2];
    reg signed [17:0] edge_offset_y_w [0:2];

    assign enable_w = output_count_r != 2 && !stop_i;
    assign screen_triangle_ready_o = enable_w && interval_r == 0;
    assign accept_w = screen_triangle_valid_i && screen_triangle_ready_o;
    assign triangle_setup_valid_o = output_count_r != 0;
    assign pop_w = triangle_setup_valid_o && triangle_setup_ready_i;
    assign complete_w = enable_w && complete_r;
    assign push_w = complete_w && nonzero_r[complete_tag_r];
    assign perf_triangle_o = push_w;
    // Front combinational stage: eight 18-bit bound comparators and six edge subtractors.
    always @(*) begin
        x_w[0] = {screen_triangle_x_i[16],
            screen_triangle_x_i[0 +: 17]};
        y_w[0] = {screen_triangle_y_i[16],
            screen_triangle_y_i[0 +: 17]};
        x_w[1] = {screen_triangle_x_i[33],
            screen_triangle_x_i[17 +: 17]};
        y_w[1] = {screen_triangle_y_i[33],
            screen_triangle_y_i[17 +: 17]};
        x_w[2] = {screen_triangle_x_i[50],
            screen_triangle_x_i[34 +: 17]};
        y_w[2] = {screen_triangle_y_i[50],
            screen_triangle_y_i[34 +: 17]};
        minimum_x_w = x_w[1] < x_w[0] ? x_w[1] : x_w[0];
        minimum_x_w = x_w[2] < minimum_x_w ? x_w[2] : minimum_x_w;
        minimum_y_w = y_w[1] < y_w[0] ? y_w[1] : y_w[0];
        minimum_y_w = y_w[2] < minimum_y_w ? y_w[2] : minimum_y_w;
        maximum_x_w = x_w[1] > x_w[0] ? x_w[1] : x_w[0];
        maximum_x_w = x_w[2] > maximum_x_w ? x_w[2] : maximum_x_w;
        maximum_y_w = y_w[1] > y_w[0] ? y_w[1] : y_w[0];
        maximum_y_w = y_w[2] > maximum_y_w ? y_w[2] : maximum_y_w;
        origin_x_w = minimum_x_w >>> 4;
        origin_y_w = minimum_y_w >>> 4;
        bound_x0_w = ((minimum_x_w + 18'sd7) >>> 6) <<< 2;
        bound_y0_w = (minimum_y_w + 18'sd7) >>> 4;
        unused_bound_x1_w = ((maximum_x_w - 18'sd8) >>> 4) + 18'sd1;
        unused_bound_y1_w = ((maximum_y_w - 18'sd8) >>> 4) + 18'sd1;
        difference_x_w[0] = x_w[1] - x_w[0];
        difference_y_w[0] = y_w[1] - y_w[0];
        difference_x_w[1] = x_w[2] - x_w[1];
        difference_y_w[1] = y_w[2] - y_w[1];
        difference_x_w[2] = x_w[0] - x_w[2];
        difference_y_w[2] = y_w[0] - y_w[2];
        area_w = multiply_0_r - multiply_1_r;
        delta_w = {difference_x_w[0], difference_x_w[2],
            -difference_y_w[0], -difference_y_w[2]};
        offset_w = {(origin_y_w <<< 4) + 18'sd8 - y_w[0],
            (origin_x_w <<< 4) + 18'sd8 - x_w[0]};
        edge_offset_x_w[0] = (bound_x0_w <<< 4) + 18'sd8 - x_w[0];
        edge_offset_y_w[0] = (bound_y0_w <<< 4) + 18'sd8 - y_w[0];
        edge_offset_x_w[1] = (bound_x0_w <<< 4) + 18'sd8 - x_w[1];
        edge_offset_y_w[1] = (bound_y0_w <<< 4) + 18'sd8 - y_w[1];
        edge_offset_x_w[2] = (bound_x0_w <<< 4) + 18'sd8 - x_w[2];
        edge_offset_y_w[2] = (bound_y0_w <<< 4) + 18'sd8 - y_w[2];
    end

    // Two front-end APMs issue area once and the three edge starts on the next clocks.
    always @(*) begin
        multiply_a_w[0] = difference_x_w[0];
        multiply_b_w[0] = -difference_y_w[2];
        multiply_a_w[1] = difference_y_w[0];
        multiply_b_w[1] = -difference_x_w[2];
        edge_index_w = 2'd0;
        edge_result_w = $signed({multiply_0_r[35], multiply_0_r})
            - $signed({multiply_1_r[35], multiply_1_r});
        if (!accept_w && interval_r >= 5) begin
            edge_index_w = 2'd3 - interval_r[1:0];
            case (interval_r[1:0])
                2'd3: begin
                    multiply_a_w[0] = front_delta_x_0_r;
                    multiply_b_w[0] = front_offset_y_0_r;
                    multiply_a_w[1] = front_delta_y_0_r;
                    multiply_b_w[1] = front_offset_x_0_r;
                end
                2'd2: begin
                    multiply_a_w[0] = front_delta_x_1_r;
                    multiply_b_w[0] = front_offset_y_1_r;
                    multiply_a_w[1] = front_delta_y_1_r;
                    multiply_b_w[1] = front_offset_x_1_r;
                end
                2'd1: begin
                    multiply_a_w[0] = front_delta_x_2_r;
                    multiply_b_w[0] = front_offset_y_2_r;
                    multiply_a_w[1] = front_delta_y_2_r;
                    multiply_b_w[1] = front_offset_x_2_r;
                end
                default: begin
                    multiply_a_w[0] = 18'sd0;
                    multiply_b_w[0] = 18'sd0;
                    multiply_a_w[1] = 18'sd0;
                    multiply_b_w[1] = 18'sd0;
                end
            endcase
        end
    end

    edrv32_gpu_project_recip u_area_reciprocal (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .enable_i(enable_w),
        .delay_exponent_wr_data_o(reciprocal_exponent_wr_w),
        .delay_exponent_rd_data_i(reciprocal_exponent_delay_w),
        .stop_i(stop_i),
        .value_valid_i(area_valid_r),
        .value_i({4'd0, area_w}),
        .value_valid_o(reciprocal_valid_w),
        .reciprocal_o(reciprocal_w),
        .exponent_o(reciprocal_exponent_w)
    );

    always @(posedge clk_i) begin
        if (enable_w) reciprocal_exponent_first_r <= reciprocal_exponent_wr_w;
    end
    edrv32_gpu_setup_plane u_plane (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .enable_i(enable_w),
        .stop_i(stop_i),
        .recip_delay_wr_data_i(reciprocal_exponent_first_r),
        .recip_delay_rd_data_o(reciprocal_exponent_delay_w),
        .plane_valid_i(attribute_valid_r),
        .plane_tag_i({attribute_tag_r, attribute_index_r}),
        .plane_value_i(attribute_value_w),
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
            multiply_0_r <= multiply_a_w[0] * multiply_b_w[0];
            multiply_1_r <= multiply_a_w[1] * multiply_b_w[1];
            edge_index_r <= edge_index_w;
            if (area_valid_r) nonzero_r[area_tag_r] <= area_w != 0;
            area_tag_r <= allocate_r;
            reciprocal_tag_0_r <= area_tag_r;
            reciprocal_tag_1_r <= reciprocal_tag_0_r;
            reciprocal_tag_2_r <= reciprocal_tag_1_r;
            reciprocal_tag_3_r <= reciprocal_tag_2_r;
            reciprocal_tag_4_r <= reciprocal_tag_3_r;
            reciprocal_tag_5_r <= reciprocal_tag_4_r;
            reciprocal_tag_6_r <= reciprocal_tag_5_r;
            reciprocal_tag_7_r <= reciprocal_tag_6_r;
            reciprocal_tag_8_r <= reciprocal_tag_7_r;
            reciprocal_tag_9_r <= reciprocal_tag_8_r;
            if (accept_w) begin
                delta_r[allocate_r] <= delta_w;
                offset_r[allocate_r] <= offset_w;
                origin_r[allocate_r] <= {origin_y_w[15:0], origin_x_w[15:0]};
                bounds_r[allocate_r] <= {unused_bound_y1_w[15:0], unused_bound_x1_w[15:0],
                    bound_y0_w[15:0], bound_x0_w[15:0]};
                front_tag_r <= allocate_r;
                front_delta_x_0_r <= difference_x_w[0];
                front_delta_y_0_r <= difference_y_w[0];
                front_offset_x_0_r <= edge_offset_x_w[0];
                front_offset_y_0_r <= edge_offset_y_w[0];
                front_delta_x_1_r <= difference_x_w[1];
                front_delta_y_1_r <= difference_y_w[1];
                front_offset_x_1_r <= edge_offset_x_w[1];
                front_offset_y_1_r <= edge_offset_y_w[1];
                front_delta_x_2_r <= difference_x_w[2];
                front_delta_y_2_r <= difference_y_w[2];
                front_offset_x_2_r <= edge_offset_x_w[2];
                front_offset_y_2_r <= edge_offset_y_w[2];
            end
            if (reciprocal_valid_w) begin
                attribute_tag_r <= reciprocal_tag_9_r;
                attribute_reciprocal_r <= reciprocal_w;
                attribute_exponent_r <= reciprocal_exponent_w;
            end
            if (plane_valid_w) complete_tag_r <= plane_tag_w[6:3];
        end
    end
    // Context and output queues are split by field; each bank has one whole-element write.
    reg [63:0] output_bounds_r [0:1];
    assign triangle_setup_bounds_o = output_bounds_r[output_read_r];
    always @(posedge clk_i) begin
        if (push_w) output_bounds_r[output_write_r] <= bounds_r[complete_tag_r];
    end
    reg [31:0] output_origin_r [0:1];
    assign triangle_setup_origin_o = output_origin_r[output_read_r];
    always @(posedge clk_i) begin
        if (push_w) output_origin_r[output_write_r] <= origin_r[complete_tag_r];
    end
    wire [152:0] attribute_value_w;
    wire [152:0] attribute_value_wires [0:6];
    reg [152:0] selected_attribute_w;
    assign attribute_value_w = selected_attribute_w;
    always @(*) begin
        selected_attribute_w = 153'd0;
        case (attribute_index_r)
            3'd0: selected_attribute_w = attribute_value_wires[0];
            3'd1: selected_attribute_w = attribute_value_wires[1];
            3'd2: selected_attribute_w = attribute_value_wires[2];
            3'd3: selected_attribute_w = attribute_value_wires[3];
            3'd4: selected_attribute_w = attribute_value_wires[4];
            3'd5: selected_attribute_w = attribute_value_wires[5];
            3'd6: selected_attribute_w = attribute_value_wires[6];
            default: selected_attribute_w = 153'd0;
        endcase
    end
    genvar attribute;
    generate
        for (attribute = 0; attribute < 7; attribute = attribute + 1) begin : g_attribute
            reg [152:0] value_r [0:15];
            wire [152:0] value_w;
            assign attribute_value_wires[attribute] = value_r[attribute_tag_r];
            if (attribute == 0) begin : g_input_0
                assign value_w = {
                    35'd0,
                    screen_triangle_depth_i[32 +: 16], 35'd0,
                    screen_triangle_depth_i[16 +: 16], 35'd0,
                    screen_triangle_depth_i[0 +: 16]};
            end
            if (attribute == 1) begin : g_input_1
                assign value_w = {
                    16'd0,
                    screen_triangle_q_i[70 +: 35], 16'd0,
                    screen_triangle_q_i[35 +: 35], 16'd0,
                    screen_triangle_q_i[0 +: 35]};
            end
            if (attribute == 2) begin : g_input_2
                assign value_w = {
                    screen_triangle_uq_i[102 +: 51],
                    screen_triangle_uq_i[51 +: 51],
                    screen_triangle_uq_i[0 +: 51]};
            end
            if (attribute == 3) begin : g_input_3
                assign value_w = {
                    screen_triangle_vq_i[102 +: 51],
                    screen_triangle_vq_i[51 +: 51],
                    screen_triangle_vq_i[0 +: 51]};
            end
            if (attribute == 4) begin : g_input_4
                assign value_w = {
                    27'd0,
                    screen_triangle_color_i[144 +: 24], 27'd0,
                    screen_triangle_color_i[72 +: 24], 27'd0,
                    screen_triangle_color_i[0 +: 24]};
            end
            if (attribute == 5) begin : g_input_5
                assign value_w = {
                    27'd0,
                    screen_triangle_color_i[168 +: 24], 27'd0,
                    screen_triangle_color_i[96 +: 24], 27'd0,
                    screen_triangle_color_i[24 +: 24]};
            end
            if (attribute == 6) begin : g_input_6
                assign value_w = {
                    27'd0,
                    screen_triangle_color_i[192 +: 24], 27'd0,
                    screen_triangle_color_i[120 +: 24], 27'd0,
                    screen_triangle_color_i[48 +: 24]};
            end
            reg [69:0] start_r [0:15];
            reg [69:0] output_start_r [0:1];
            assign triangle_setup_start_o[attribute*70 +: 70] =
                output_start_r[output_read_r];
            always @(posedge clk_i) begin
                if (enable_w && plane_valid_w && plane_tag_w[2:0] == attribute)
                    start_r[plane_tag_w[6:3]] <= plane_start_w;
                if (push_w) output_start_r[output_write_r] <= start_r[complete_tag_r];
            end
            reg [111:0] gradient_r [0:15];
            reg [111:0] output_gradient_r [0:1];
            assign triangle_setup_gradient_o[attribute*112 +: 112] =
                output_gradient_r[output_read_r];
            always @(posedge clk_i) begin
                if (enable_w && plane_valid_w && plane_tag_w[2:0] == attribute)
                    gradient_r[plane_tag_w[6:3]] <= plane_gradient_w;
                if (push_w) output_gradient_r[output_write_r] <= gradient_r[complete_tag_r];
            end
            reg [9:0] h_r [0:15];
            reg [9:0] output_h_r [0:1];
            assign triangle_setup_h_o[attribute*10 +: 10] =
                output_h_r[output_read_r];
            always @(posedge clk_i) begin
                if (enable_w && plane_valid_w && plane_tag_w[2:0] == attribute)
                    h_r[plane_tag_w[6:3]] <= plane_h_w;
                if (push_w) output_h_r[output_write_r] <= h_r[complete_tag_r];
            end
            always @(posedge clk_i) begin
                if (enable_w && accept_w) value_r[allocate_r] <= value_w;
            end
        end
    endgenerate
    genvar edge_bank;
    generate
        // Three edge coefficient banks; two shared front multipliers retain their issue schedule.
        for (edge_bank = 0; edge_bank < 3; edge_bank = edge_bank + 1) begin : g_edge
            localparam VERTEX = (edge_bank + 1) % 3;
            reg [39:0] value_r [0:15];
            reg [39:0] output_value_r [0:1];
            reg [39:0] dx_r [0:15];
            reg [39:0] output_dx_r [0:1];
            reg [39:0] dy_r [0:15];
            reg [39:0] output_dy_r [0:1];
            reg [39:0] bias_r [0:15];
            reg [39:0] output_bias_r [0:1];
            wire [39:0] dx_w;
            wire [39:0] dy_w;
            wire [39:0] bias_w;
            assign dx_w = -$signed({{22{difference_y_w[VERTEX][17]}},
                difference_y_w[VERTEX]}) <<< 4;
            assign dy_w = $signed({{22{difference_x_w[VERTEX][17]}},
                difference_x_w[VERTEX]}) <<< 4;
            assign bias_w = difference_y_w[VERTEX] < 0 ||
                (difference_y_w[VERTEX] == 0 && difference_x_w[VERTEX] > 0)
                ? 40'd0 : -40'd1;
            wire value_write_w;
            wire [3:0] value_tag_w;
            wire [39:0] value_w;
            assign value_write_w = accept_w || (edge_valid_r && edge_index_r == VERTEX);
            assign value_tag_w = accept_w ? allocate_r : front_tag_r;
            assign value_w = accept_w ? 40'd0 : {{3{edge_result_w[36]}}, edge_result_w};
            always @(posedge clk_i) begin
                if (enable_w && value_write_w) value_r[value_tag_w] <= value_w;
                if (enable_w && accept_w) begin
                    dx_r[allocate_r] <= dx_w;
                    dy_r[allocate_r] <= dy_w;
                    bias_r[allocate_r] <= bias_w;
                end
                if (push_w) output_value_r[output_write_r] <= value_r[complete_tag_r];
                if (push_w) output_dx_r[output_write_r] <= dx_r[complete_tag_r];
                if (push_w) output_dy_r[output_write_r] <= dy_r[complete_tag_r];
                if (push_w) output_bias_r[output_write_r] <= bias_r[complete_tag_r];
            end
            assign triangle_setup_edge_o[edge_bank*160+0 +: 40] =
                output_value_r[output_read_r];
            assign triangle_setup_edge_o[edge_bank*160+40 +: 40] =
                output_dx_r[output_read_r];
            assign triangle_setup_edge_o[edge_bank*160+80 +: 40] =
                output_dy_r[output_read_r];
            assign triangle_setup_edge_o[edge_bank*160+120 +: 40] =
                output_bias_r[output_read_r];
        end
    endgenerate
    genvar normal;
    generate
        for (normal = 0; normal < 6; normal = normal + 1) begin : g_normal
            reg [28:0] value_r [0:15];
            reg [28:0] output_r [0:1];
            always @(posedge clk_i) begin
                if (enable_w && plane_valid_w && plane_tag_w[2:0] == (normal % 3) + 1)
                    value_r[plane_tag_w[6:3]] <= plane_normal_w[(normal / 3)*29 +: 29];
                if (push_w) output_r[output_write_r] <= value_r[complete_tag_r];
            end
            assign triangle_setup_normal_gradient_o[normal*29 +: 29] = output_r[output_read_r];
        end
    endgenerate
endmodule
