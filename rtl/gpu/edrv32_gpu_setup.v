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
    output wire [433:0] triangle_setup_start_o,
    output wire [671:0] triangle_setup_gradient_o,
    output wire [69:0] triangle_setup_h_o,

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

    reg nonzero_r [0:15];
    wire area_valid_r;
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
    wire edge_valid_r;
    wire [1:0] edge_index_r;
    reg [1:0] edge_index_w;
    reg [3:0] front_tag_r;
    wire signed [36:0] edge_result_w;
    wire [3:0] area_tag_r;

    // Must equal the total enabled-clock latency of edrv32_gpu_project_recip.
    localparam RECIP_LATENCY = 24;
    wire [RECIP_LATENCY*4-1:0] reciprocal_tag_w;
    genvar reciprocal_stage;
    generate
        for (reciprocal_stage = 0; reciprocal_stage < RECIP_LATENCY;
            reciprocal_stage = reciprocal_stage + 1) begin : g_reciprocal_tag
            reg [3:0] tag_r;
            wire [3:0] previous_w;
            if (reciprocal_stage == 0) begin : g_first
                assign previous_w = area_tag_r;
            end else begin : g_previous
                assign previous_w = reciprocal_tag_w[(reciprocal_stage-1)*4 +: 4];
            end
            assign reciprocal_tag_w[reciprocal_stage*4 +: 4] = tag_r;
            always @(posedge clk_i) begin
                if (enable_w) tag_r <= previous_w;
            end
        end
    endgenerate
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
    wire [65:0] plane_start_w;
    wire [103:0] plane_gradient_w;
    wire [9:0] plane_h_w;
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

    wire signed [35:0] area_w;
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
        minimum_x_w = x_w[0] <= x_w[1] && x_w[0] <= x_w[2] ? x_w[0] :
            x_w[1] <= x_w[2] ? x_w[1] : x_w[2];
        minimum_y_w = y_w[0] <= y_w[1] && y_w[0] <= y_w[2] ? y_w[0] :
            y_w[1] <= y_w[2] ? y_w[1] : y_w[2];
        maximum_x_w = x_w[0] >= x_w[1] && x_w[0] >= x_w[2] ? x_w[0] :
            x_w[1] >= x_w[2] ? x_w[1] : x_w[2];
        maximum_y_w = y_w[0] >= y_w[1] && y_w[0] >= y_w[2] ? y_w[0] :
            y_w[1] >= y_w[2] ? y_w[1] : y_w[2];
        origin_x_w = minimum_x_w >>> 4;
        origin_y_w = minimum_y_w >>> 4;
        bound_x0_w = ((minimum_x_w + 18'sd7) >>> 6) <<< 2;
        bound_y0_w = ((minimum_y_w + 18'sd7) >>> 5) <<< 1;
        unused_bound_x1_w = ((maximum_x_w - 18'sd8) >>> 4) + 18'sd1;
        unused_bound_y1_w = ((maximum_y_w - 18'sd8) >>> 4) + 18'sd1;
        difference_x_w[0] = x_w[1] - x_w[0];
        difference_y_w[0] = y_w[1] - y_w[0];
        difference_x_w[1] = x_w[2] - x_w[1];
        difference_y_w[1] = y_w[2] - y_w[1];
        difference_x_w[2] = x_w[0] - x_w[2];
        difference_y_w[2] = y_w[0] - y_w[2];
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

    // Two shared APMs: registered operands, three product registers and two carry slices.
    reg signed [17:0] multiply_a_0_r;
    reg signed [17:0] multiply_a_1_r;
    reg signed [17:0] multiply_b_0_r;
    reg signed [17:0] multiply_b_1_r;
    reg signed [35:0] product_0_0_r;
    reg signed [35:0] product_1_0_r;
    reg signed [35:0] product_0_1_r;
    reg signed [35:0] product_1_1_r;
    reg [34:0] difference_low_r;
    reg difference_carry_r;
    reg [1:0] difference_high_a_r;
    reg [1:0] difference_high_b_r;
    reg [36:0] difference_r;
    wire [35:0] difference_low_w;
    wire [1:0] difference_high_w;
    wire [47:0] front_metadata_w;
    assign difference_low_w = {1'b0, multiply_0_r[34:0]}
        + {1'b0, ~multiply_1_r[34:0]} + 36'd1;
    assign difference_high_w = difference_high_a_r + ~difference_high_b_r
        + {1'b0, difference_carry_r};
    assign edge_result_w = difference_r;
    assign area_w = difference_r[35:0];
    assign area_valid_r = front_metadata_w[47];
    assign edge_valid_r = front_metadata_w[46];
    assign edge_index_r = front_metadata_w[44 +: 2];
    assign area_tag_r = front_metadata_w[40 +: 4];
    always @(posedge clk_i) begin
        if (enable_w) begin
            multiply_a_0_r <= multiply_a_w[0];
            multiply_a_1_r <= multiply_a_w[1];
            multiply_b_0_r <= multiply_b_w[0];
            multiply_b_1_r <= multiply_b_w[1];
            product_0_0_r <= multiply_a_0_r * multiply_b_0_r;
            product_1_0_r <= multiply_a_1_r * multiply_b_1_r;
            product_0_1_r <= product_0_0_r;
            product_1_1_r <= product_1_0_r;
            multiply_0_r <= product_0_1_r;
            multiply_1_r <= product_1_1_r;
            difference_low_r <= difference_low_w[34:0];
            difference_carry_r <= difference_low_w[35];
            difference_high_a_r <= {multiply_0_r[35], multiply_0_r[35]};
            difference_high_b_r <= {multiply_1_r[35], multiply_1_r[35]};
            difference_r <= {difference_high_w, difference_low_r};
        end
    end
    genvar front_stage;
    generate
        for (front_stage = 0; front_stage < 6; front_stage = front_stage + 1) begin : g_front
            reg [1:0] valid_r;
            reg [5:0] metadata_r;
            wire [7:0] previous_w;
            if (front_stage == 0) begin : g_input
                assign previous_w = {accept_w, !accept_w && interval_r >= 5,
                    edge_index_w, accept_w ? allocate_r : front_tag_r};
            end else begin : g_delay
                assign previous_w = front_metadata_w[(front_stage-1)*8 +: 8];
            end
            assign front_metadata_w[front_stage*8 +: 8] = {valid_r, metadata_r};
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) valid_r <= 0;
                else if (stop_i) valid_r <= 0;
                else if (enable_w) valid_r <= previous_w[7:6];
            end
            always @(posedge clk_i) begin
                if (enable_w) metadata_r <= previous_w[5:0];
            end
        end
    endgenerate

    (* keep = 1 *) reg [1:0] area_count_r /* synthesis syn_preserve=1 */;
    wire area_enable_w;
    assign area_enable_w = area_count_r != 2 && !stop_i;
    (* keep = 1 *) always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) area_count_r <= 0;
        else if (stop_i) area_count_r <= 0;
        else begin
            case ({push_w, pop_w})
                2'b10: area_count_r <= area_count_r + 1'b1;
                2'b01: area_count_r <= area_count_r - 1'b1;
                default: area_count_r <= area_count_r;
            endcase
        end
    end

    edrv32_gpu_project_recip u_area_reciprocal (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .enable_i(area_enable_w),
        .stop_i(stop_i),
        .value_valid_i(area_valid_r),
        .value_i({4'd0, area_w}),
        .value_valid_o(reciprocal_valid_w),
        .reciprocal_o(reciprocal_w),
        .exponent_o(reciprocal_exponent_w)
    );

    // Read each attribute bank into a register before the seven-way attribute selector.
    reg attribute_read_valid_r;
    reg [6:0] attribute_read_tag_r;
    reg [71:0] attribute_read_delta_r;
    reg [35:0] attribute_read_offset_r;
    reg [30:0] attribute_read_reciprocal_r;
    reg [5:0] attribute_read_exponent_r;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) attribute_read_valid_r <= 0;
        else if (stop_i) attribute_read_valid_r <= 0;
        else if (enable_w) attribute_read_valid_r <= attribute_valid_r;
    end
    always @(posedge clk_i) begin
        if (enable_w) begin
            attribute_read_tag_r <= {attribute_tag_r, attribute_index_r};
            attribute_read_delta_r <= unused_attribute_context_read0_w[0 +: 72];
            attribute_read_offset_r <= unused_attribute_context_read0_w[72 +: 36];
            attribute_read_reciprocal_r <= attribute_reciprocal_r;
            attribute_read_exponent_r <= attribute_exponent_r;
        end
    end

    edrv32_gpu_setup_plane u_plane (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .enable_i(enable_w),
        .stop_i(stop_i),
        .credit_push_i(push_w),
        .credit_pop_i(pop_w),
        .plane_valid_i(attribute_read_valid_r),
        .plane_tag_i(attribute_read_tag_r),
        .plane_value_i(attribute_value_w),
        .plane_delta_i(attribute_read_delta_r),
        .plane_offset_i(attribute_read_offset_r),
        .plane_reciprocal_i(attribute_read_reciprocal_r),
        .plane_exponent_i(attribute_read_exponent_r),
        .plane_valid_o(plane_valid_w),
        .plane_tag_o(plane_tag_w),
        .plane_start_o(plane_start_w),
        .plane_gradient_o(plane_gradient_w),
        .plane_h_o(plane_h_w)
    );

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            interval_r <= 3'd0;
            allocate_r <= 4'd0;
            pending_r <= 5'd0;
            output_count_r <= 2'd0;
            output_read_r <= 1'b0;
            output_write_r <= 1'b0;
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
            if (area_valid_r) nonzero_r[area_tag_r] <= area_w != 0;

            if (accept_w) begin

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
                attribute_tag_r <= reciprocal_tag_w[(RECIP_LATENCY-1)*4 +: 4];
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
        if (push_w)
            output_bounds_r[output_write_r] <= unused_output_context_read0_w[32 +: 64];
    end
    reg [31:0] output_origin_r [0:1];
    assign triangle_setup_origin_o = output_origin_r[output_read_r];
    always @(posedge clk_i) begin
        if (push_w)
            output_origin_r[output_write_r] <= unused_output_context_read0_w[0 +: 32];
    end
    wire [152:0] attribute_value_w;
    wire [152:0] attribute_value_wires_w [0:6];
    reg [152:0] selected_attribute_w;
    assign attribute_value_w = selected_attribute_w;
    always @(*) begin
        selected_attribute_w = 153'd0;
        case (attribute_read_tag_r[2:0])
            3'd0: selected_attribute_w = attribute_value_wires_w[0];
            3'd1: selected_attribute_w = attribute_value_wires_w[1];
            3'd2: selected_attribute_w = attribute_value_wires_w[2];
            3'd3: selected_attribute_w = attribute_value_wires_w[3];
            3'd4: selected_attribute_w = attribute_value_wires_w[4];
            3'd5: selected_attribute_w = attribute_value_wires_w[5];
            3'd6: selected_attribute_w = attribute_value_wires_w[6];
            default: selected_attribute_w = 153'd0;
        endcase
    end
    genvar attribute;
    generate
        for (attribute = 0; attribute < 7; attribute = attribute + 1) begin : g_attribute
            // Input values live through the reciprocal and seven attribute reads (<64 clocks).
            wire [152:0] unused_value_w;
            wire [152:0] value_read_r;
            assign attribute_value_wires_w[attribute] = value_read_r;
            if (attribute == 0) begin : g_input_0
                assign unused_value_w = {
                    35'd0,
                    screen_triangle_depth_i[32 +: 16], 35'd0,
                    screen_triangle_depth_i[16 +: 16], 35'd0,
                    screen_triangle_depth_i[0 +: 16]};
            end
            if (attribute == 1) begin : g_input_1
                assign unused_value_w = {
                    16'd0,
                    screen_triangle_q_i[70 +: 35], 16'd0,
                    screen_triangle_q_i[35 +: 35], 16'd0,
                    screen_triangle_q_i[0 +: 35]};
            end
            if (attribute == 2) begin : g_input_2
                assign unused_value_w = {
                    screen_triangle_uq_i[102 +: 51],
                    screen_triangle_uq_i[51 +: 51],
                    screen_triangle_uq_i[0 +: 51]};
            end
            if (attribute == 3) begin : g_input_3
                assign unused_value_w = {
                    screen_triangle_vq_i[102 +: 51],
                    screen_triangle_vq_i[51 +: 51],
                    screen_triangle_vq_i[0 +: 51]};
            end
            if (attribute == 4) begin : g_input_4
                assign unused_value_w = {
                    27'd0,
                    screen_triangle_color_i[144 +: 24], 27'd0,
                    screen_triangle_color_i[72 +: 24], 27'd0,
                    screen_triangle_color_i[0 +: 24]};
            end
            if (attribute == 5) begin : g_input_5
                assign unused_value_w = {
                    27'd0,
                    screen_triangle_color_i[168 +: 24], 27'd0,
                    screen_triangle_color_i[96 +: 24], 27'd0,
                    screen_triangle_color_i[24 +: 24]};
            end
            if (attribute == 6) begin : g_input_6
                assign unused_value_w = {
                    27'd0,
                    screen_triangle_color_i[192 +: 24], 27'd0,
                    screen_triangle_color_i[120 +: 24], 27'd0,
                    screen_triangle_color_i[48 +: 24]};
            end
            localparam WIDTH = attribute == 0 ? 62 : attribute < 4 ? 66 : 58;
            localparam GRAD_WIDTH = WIDTH - 14;
            localparam START_OFFSET = attribute == 0 ? 0 : attribute < 4 ?
                62 + (attribute-1)*66 : 260 + (attribute-4)*58;
            localparam GRAD_OFFSET = attribute == 0 ? 0 : attribute < 4 ?
                96 + (attribute-1)*104 : 408 + (attribute-4)*88;
            // Ordered attribute returns need one assembly register per field.
            // The next triangle's attribute 0 may arrive on the old triangle's push clock;
            // nonblocking writes retain the old coefficient for that output transfer.
            reg [WIDTH-1:0] start_r;
            reg [WIDTH-1:0] output_start_r [0:1];
            assign triangle_setup_start_o[START_OFFSET +: WIDTH] =
                output_start_r[output_read_r];
            always @(posedge clk_i) begin
                if (enable_w && plane_valid_w && plane_tag_w[2:0] == attribute)
                    start_r <= plane_start_w[WIDTH-1:0];
                if (push_w)
                    output_start_r[output_write_r] <= start_r;
            end
            reg [2*GRAD_WIDTH-1:0] gradient_r;
            reg [2*GRAD_WIDTH-1:0] output_gradient_r [0:1];
            assign triangle_setup_gradient_o[GRAD_OFFSET +: 2*GRAD_WIDTH] =
                output_gradient_r[output_read_r];
            always @(posedge clk_i) begin
                if (enable_w && plane_valid_w && plane_tag_w[2:0] == attribute)
                    gradient_r <= {plane_gradient_w[52 +: GRAD_WIDTH],
                        plane_gradient_w[0 +: GRAD_WIDTH]};
                if (push_w)
                    output_gradient_r[output_write_r] <= gradient_r;
            end
            reg [9:0] h_r;
            reg [9:0] output_h_r [0:1];
            assign triangle_setup_h_o[attribute*10 +: 10] =
                output_h_r[output_read_r];
            always @(posedge clk_i) begin
                if (enable_w && plane_valid_w && plane_tag_w[2:0] == attribute)
                    h_r <= plane_h_w;
                if (push_w)
                    output_h_r[output_write_r] <= h_r;
            end
            // Store only significant vertex bits; reconstruct the original 51-bit fields.
            localparam FIELD_WIDTH = attribute == 0 ? 16 : attribute == 1 ? 35
                : attribute < 4 ? 51 : 24;
            localparam BANKS = (3*FIELD_WIDTH+71)/72;
            wire [BANKS*72-1:0] value_input_w;
            wire [BANKS*72-1:0] unused_value_data_w;
            assign value_input_w = {{(BANKS*72-3*FIELD_WIDTH){1'b0}},
                unused_value_w[102 +: FIELD_WIDTH], unused_value_w[51 +: FIELD_WIDTH],
                unused_value_w[0 +: FIELD_WIDTH]};
            assign value_read_r = {{(51-FIELD_WIDTH){1'b0}},
                unused_value_data_w[2*FIELD_WIDTH +: FIELD_WIDTH],
                {(51-FIELD_WIDTH){1'b0}},
                unused_value_data_w[FIELD_WIDTH +: FIELD_WIDTH],
                {(51-FIELD_WIDTH){1'b0}}, unused_value_data_w[0 +: FIELD_WIDTH]};
            genvar value_bank;
            for (value_bank = 0; value_bank < BANKS; value_bank = value_bank + 1) begin : g_value
                wire [71:0] u_value_data_w;
                reg [71:0] u_value_data_r;
                assign unused_value_data_w[value_bank*72 +: 72] = u_value_data_r;
                always @(posedge clk_i) begin
                    if (enable_w) u_value_data_r <= u_value_data_w;
                end
                edrv32_ram_gpu_table u_value (
                    .clk_i(clk_i),
                    .wr_en_i(enable_w && accept_w),
                    .wr_addr_i({3'b0, allocate_r[2:0]}),
                    .wr_data_i(value_input_w[value_bank*72 +: 72]),
                    .rd_addr_i({3'b0, attribute_tag_r[2:0]}),
                    .rd_data_o(u_value_data_w)
                );
            end
        end
    endgenerate
    genvar edge_bank;
    generate
        // Three edge coefficient banks; two shared front multipliers retain their issue schedule.
        for (edge_bank = 0; edge_bank < 3; edge_bank = edge_bank + 1) begin : g_edge
            localparam VERTEX = (edge_bank + 1) % 3;

            reg [39:0] output_value_r [0:1];

            reg [39:0] output_dx_r [0:1];

            reg [39:0] output_dy_r [0:1];

            reg [39:0] output_bias_r [0:1];
            // Explicit LUTRAM edge_value: 1 slice(s) per combinational read port.
            wire [71:0] edge_value_input_w;
            assign edge_value_input_w = {32'b0, value_w};
            wire [71:0] unused_edge_value_read0_w;
            edrv32_ram_gpu_table u_edge_value_p0_b0 (
                .clk_i(clk_i),
                .wr_en_i(enable_w && value_write_w),
                .wr_addr_i({2'b0, value_tag_w}),
                .wr_data_i(edge_value_input_w[0 +: 72]),
                .rd_addr_i({2'b0, complete_tag_r}),
                .rd_data_o(unused_edge_value_read0_w[0 +: 72])
            );
            // Explicit LUTRAM edge_coefficients: 2 slice(s) per combinational read port.
            wire [143:0] edge_coefficients_input_w;
            assign edge_coefficients_input_w = {24'b0, bias_w, dy_w, dx_w};
            wire [143:0] unused_edge_coefficients_read0_w;
            edrv32_ram_gpu_table u_edge_coefficients_p0_b0 (
                .clk_i(clk_i),
                .wr_en_i(enable_w && accept_w),
                .wr_addr_i({2'b0, allocate_r}),
                .wr_data_i(edge_coefficients_input_w[0 +: 72]),
                .rd_addr_i({2'b0, complete_tag_r}),
                .rd_data_o(unused_edge_coefficients_read0_w[0 +: 72])
            );
            edrv32_ram_gpu_table u_edge_coefficients_p0_b1 (
                .clk_i(clk_i),
                .wr_en_i(enable_w && accept_w),
                .wr_addr_i({2'b0, allocate_r}),
                .wr_data_i(edge_coefficients_input_w[72 +: 72]),
                .rd_addr_i({2'b0, complete_tag_r}),
                .rd_data_o(unused_edge_coefficients_read0_w[72 +: 72])
            );
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
            assign value_write_w = edge_valid_r && edge_index_r == VERTEX;
            assign value_tag_w = area_tag_r;
            assign value_w = {{3{edge_result_w[36]}}, edge_result_w};
            always @(posedge clk_i) begin

                if (push_w)

                    output_value_r[output_write_r] <= unused_edge_value_read0_w[0 +: 40];
                if (push_w)
                    output_dx_r[output_write_r] <= unused_edge_coefficients_read0_w[0 +: 40];
                if (push_w)
                    output_dy_r[output_write_r] <= unused_edge_coefficients_read0_w[40 +: 40];
                if (push_w)
                    output_bias_r[output_write_r] <= unused_edge_coefficients_read0_w[80 +: 40];
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
    // Explicit LUTRAM attribute_context: 2 slice(s) per combinational read port.
    wire [143:0] attribute_context_input_w;
    assign attribute_context_input_w = {36'b0, offset_w, delta_w};
    wire [143:0] unused_attribute_context_read0_w;
    edrv32_ram_gpu_table u_attribute_context_p0_b0 (
        .clk_i(clk_i),
        .wr_en_i(enable_w && accept_w),
        .wr_addr_i({2'b0, allocate_r}),
        .wr_data_i(attribute_context_input_w[0 +: 72]),
        .rd_addr_i({2'b0, attribute_tag_r}),
        .rd_data_o(unused_attribute_context_read0_w[0 +: 72])
    );
    edrv32_ram_gpu_table u_attribute_context_p0_b1 (
        .clk_i(clk_i),
        .wr_en_i(enable_w && accept_w),
        .wr_addr_i({2'b0, allocate_r}),
        .wr_data_i(attribute_context_input_w[72 +: 72]),
        .rd_addr_i({2'b0, attribute_tag_r}),
        .rd_data_o(unused_attribute_context_read0_w[72 +: 72])
    );
    // Explicit LUTRAM output_context: 2 slice(s) per combinational read port.
    wire [143:0] output_context_input_w;
    assign output_context_input_w = {48'b0, {unused_bound_y1_w[15:0], unused_bound_x1_w[15:0],
        bound_y0_w[15:0], bound_x0_w[15:0]}, {origin_y_w[15:0], origin_x_w[15:0]}};
    wire [143:0] unused_output_context_read0_w;
    edrv32_ram_gpu_table u_output_context_p0_b0 (
        .clk_i(clk_i),
        .wr_en_i(enable_w && accept_w),
        .wr_addr_i({2'b0, allocate_r}),
        .wr_data_i(output_context_input_w[0 +: 72]),
        .rd_addr_i({2'b0, complete_tag_r}),
        .rd_data_o(unused_output_context_read0_w[0 +: 72])
    );
    edrv32_ram_gpu_table u_output_context_p0_b1 (
        .clk_i(clk_i),
        .wr_en_i(enable_w && accept_w),
        .wr_addr_i({2'b0, allocate_r}),
        .wr_data_i(output_context_input_w[72 +: 72]),
        .rd_addr_i({2'b0, complete_tag_r}),
        .rd_data_o(unused_output_context_read0_w[72 +: 72])
    );
endmodule
