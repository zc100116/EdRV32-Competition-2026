// File: edrv32_gpu_setup.v
// Spec: gpu-spec 2.5, 2.12, 2.13.1-6; GPU microarchitecture 4.2-4.4.
// Description: Independent area reciprocal and seven overlapping attribute launches per triangle.
//              Sixteen ordered contexts and two output slots absorb downstream backpressure.
// Clock domain: clk_gpu.
module edrv32_gpu_setup (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Draw snapshot of SCISSOR/TGT, paired with the raster state snapshot.
    input wire render_state_valid_i,
    input wire [95:0] render_state_target_i,
    input wire render_state_wide_i,

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
    output wire [253:0] triangle_setup_start_o,
    output wire [367:0] triangle_setup_gradient_o,
    output wire [69:0] triangle_setup_h_o,

    // Command lifetime and performance event.
    input wire finish_i,
    input wire stop_i,
    output reg unit_done_o,
    output wire perf_triangle_o
);
    reg [3:0] pa_config_valid_r;
    reg signed [17:0] pa_target_x0_r;
    reg signed [17:0] pa_target_y0_r;
    reg signed [17:0] pa_target_x1_r;
    reg signed [17:0] pa_target_y1_r;
    reg signed [17:0] pa_scissor_x0_r;
    reg signed [17:0] pa_scissor_y0_r;
    reg signed [17:0] pa_scissor_x1_r;
    reg signed [17:0] pa_scissor_y1_r;
    reg signed [17:0] pa_left_r;
    reg signed [17:0] pa_top_r;
    reg signed [17:0] pa_right_r;
    reg signed [17:0] pa_bottom_r;
    reg signed [17:0] pa_width_r;
    reg signed [17:0] pa_height_r;
    reg signed [18:0] pa_span_r;
    reg signed [17:0] pa_origin_x_r;
    reg signed [17:0] pa_origin_y_r;
    reg pa_large_span_r;
    wire signed [17:0] pa_target_x0_w;
    wire signed [17:0] pa_target_y0_w;
    assign pa_target_x0_w = {{2{render_state_target_i[15]}}, render_state_target_i[0 +: 16]};
    assign pa_target_y0_w = {{2{render_state_target_i[31]}}, render_state_target_i[16 +: 16]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) pa_config_valid_r <= 0;
        else pa_config_valid_r <= {pa_config_valid_r[2:0], render_state_valid_i};
    end
    always @(posedge clk_i) begin
        if (render_state_valid_i) begin
            pa_target_x0_r <= pa_target_x0_w;
            pa_target_y0_r <= pa_target_y0_w;
            pa_target_x1_r <= pa_target_x0_w + (render_state_wide_i ? 18'sd1280 : 18'sd640);
            pa_target_y1_r <= pa_target_y0_w + (render_state_wide_i ? 18'sd90 : 18'sd180);
            pa_scissor_x0_r <= {{2{render_state_target_i[47]}}, render_state_target_i[32 +: 16]};
            pa_scissor_y0_r <= {{2{render_state_target_i[63]}}, render_state_target_i[48 +: 16]};
            pa_scissor_x1_r <= {{2{render_state_target_i[79]}}, render_state_target_i[64 +: 16]};
            pa_scissor_y1_r <= {{2{render_state_target_i[95]}}, render_state_target_i[80 +: 16]};
        end
        if (pa_config_valid_r[0]) begin
            pa_left_r <= pa_target_x0_r > pa_scissor_x0_r ? pa_target_x0_r : pa_scissor_x0_r;
            pa_top_r <= pa_target_y0_r > pa_scissor_y0_r ? pa_target_y0_r : pa_scissor_y0_r;
            pa_right_r <= pa_target_x1_r < pa_scissor_x1_r ? pa_target_x1_r : pa_scissor_x1_r;
            pa_bottom_r <= pa_target_y1_r < pa_scissor_y1_r ? pa_target_y1_r : pa_scissor_y1_r;
        end
        if (pa_config_valid_r[1]) begin
            pa_width_r <= pa_right_r - pa_left_r;
            pa_height_r <= pa_bottom_r - pa_top_r;
            pa_origin_x_r <= {pa_left_r[17:2], 2'b0};
            pa_origin_y_r <= {pa_top_r[17:1], 1'b0};
        end
        if (pa_config_valid_r[2])
            pa_span_r <= {pa_width_r[17], pa_width_r} + {pa_height_r[17], pa_height_r};
        // Legal TGT dimensions limit g to 10 or 11; bit_length(width+height+8)>10.
        if (pa_config_valid_r[3]) pa_large_span_r <= pa_span_r >= 19'sd1016;
    end

    // Two front clocks isolate bound selection from clipping and edge-offset subtraction.
    wire screen_accept_w;
    reg [1:0] front_valid_r;
    reg [2:0] front_interval_r;
    reg [107:0] front_vertex_r;
    reg [53:0] front_difference_x_r;
    reg [53:0] front_difference_y_r;
    reg signed [17:0] front_bound_x0_r;
    reg signed [17:0] front_bound_y0_r;
    reg signed [17:0] front_bound_x1_r;
    reg signed [17:0] front_bound_y1_r;
    reg signed [17:0] clipped_bound_x0_r;
    reg signed [17:0] clipped_bound_y0_r;
    reg signed [15:0] clipped_bound_x1_r;
    wire [17:0] unused_clipped_bound_x1_w;
    reg signed [15:0] clipped_bound_y1_r;
    wire [17:0] unused_clipped_bound_y1_w;
    assign unused_clipped_bound_x1_w = front_bound_x1_r < pa_right_r ?
        front_bound_x1_r : pa_right_r;
    assign unused_clipped_bound_y1_w = front_bound_y1_r < pa_bottom_r ?
        front_bound_y1_r : pa_bottom_r;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            front_valid_r <= 0;
            front_interval_r <= 0;
        end else if (stop_i) begin
            front_valid_r <= 0;
            front_interval_r <= 0;
        end else if (enable_w) begin
            front_valid_r <= {front_valid_r[0], screen_accept_w};
            if (front_interval_r != 0) front_interval_r <= front_interval_r - 3'd1;
            if (screen_accept_w) front_interval_r <= 3'd7;
        end
    end
    always @(posedge clk_i) begin
        if (screen_accept_w) begin
            front_vertex_r <= {y_w[2], x_w[2], y_w[1], x_w[1], y_w[0], x_w[0]};
            front_difference_x_r <= {difference_x_w[2], difference_x_w[1], difference_x_w[0]};
            front_difference_y_r <= {difference_y_w[2], difference_y_w[1], difference_y_w[0]};
            front_bound_x0_r <= bound_x0_w;
            front_bound_y0_r <= bound_y0_w;
            front_bound_x1_r <= unused_bound_x1_w;
            front_bound_y1_r <= unused_bound_y1_w;
        end
        if (enable_w && front_valid_r[0]) begin
            clipped_bound_x0_r <= front_bound_x0_r > pa_origin_x_r ?
                front_bound_x0_r : pa_origin_x_r;
            clipped_bound_y0_r <= front_bound_y0_r > pa_origin_y_r ?
                front_bound_y0_r : pa_origin_y_r;
            clipped_bound_x1_r <= unused_clipped_bound_x1_w[15:0];
            clipped_bound_y1_r <= unused_clipped_bound_y1_w[15:0];
        end
    end

    wire enable_w;
    // Independent occupancy replicas keep the common datapath CE local (microarch 4.14).
    wire [5:0] control_enable_w;
    genvar control_region;
    generate
        for (control_region = 0; control_region < 6;
            control_region = control_region + 1) begin : g_control_enable
            (* keep = "true", syn_preserve = 1 *) reg [1:0] occupancy_r;
            assign control_enable_w[control_region] = occupancy_r != 2 && !stop_i;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) occupancy_r <= 0;
                else if (stop_i) occupancy_r <= 0;
                else begin
                    case ({push_w, pop_w})
                        2'b10: occupancy_r <= occupancy_r + 2'd1;
                        2'b01: occupancy_r <= occupancy_r - 2'd1;
                        default: occupancy_r <= occupancy_r;
                    endcase
                end
            end
        end
    endgenerate

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
                if (control_enable_w[0]) tag_r <= previous_w;
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
    assign screen_triangle_ready_o = enable_w && front_interval_r == 0;
    assign screen_accept_w = screen_triangle_valid_i && screen_triangle_ready_o;
    assign accept_w = enable_w && front_valid_r[1];
    assign triangle_setup_valid_o = output_count_r != 0;
    assign pop_w = triangle_setup_valid_o && triangle_setup_ready_i;
    assign complete_w = enable_w && complete_r;
    assign push_w = complete_w && unused_pa_snapshot_w[459];
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
        edge_offset_x_w[0] = (clipped_bound_x0_r <<< 4) + 18'sd8
            - $signed(front_vertex_r[0 +: 18]);
        edge_offset_y_w[0] = (clipped_bound_y0_r <<< 4) + 18'sd8
            - $signed(front_vertex_r[18 +: 18]);
        edge_offset_x_w[1] = (clipped_bound_x0_r <<< 4) + 18'sd8
            - $signed(front_vertex_r[36 +: 18]);
        edge_offset_y_w[1] = (clipped_bound_y0_r <<< 4) + 18'sd8
            - $signed(front_vertex_r[54 +: 18]);
        edge_offset_x_w[2] = (clipped_bound_x0_r <<< 4) + 18'sd8
            - $signed(front_vertex_r[72 +: 18]);
        edge_offset_y_w[2] = (clipped_bound_y0_r <<< 4) + 18'sd8
            - $signed(front_vertex_r[90 +: 18]);
    end

    // Two front-end APMs issue area once and the three edge starts on the next clocks.
    always @(*) begin
        multiply_a_w[0] = $signed(front_difference_x_r[0 +: 18]);
        multiply_b_w[0] = -$signed(front_difference_y_r[36 +: 18]);
        multiply_a_w[1] = $signed(front_difference_y_r[0 +: 18]);
        multiply_b_w[1] = -$signed(front_difference_x_r[36 +: 18]);
        edge_index_w = 2'd0;
        if (!accept_w && interval_r >= 5) begin
            edge_index_w = 2'd3 - interval_r[1:0];
            case (interval_r[1:0])
                2'd3: begin
                    multiply_a_w[0] = $signed(front_difference_x_r[0 +: 18]);
                    multiply_b_w[0] = edge_offset_y_w[0];
                    multiply_a_w[1] = $signed(front_difference_y_r[0 +: 18]);
                    multiply_b_w[1] = edge_offset_x_w[0];
                end
                2'd2: begin
                    multiply_a_w[0] = $signed(front_difference_x_r[18 +: 18]);
                    multiply_b_w[0] = edge_offset_y_w[1];
                    multiply_a_w[1] = $signed(front_difference_y_r[18 +: 18]);
                    multiply_b_w[1] = edge_offset_x_w[1];
                end
                2'd1: begin
                    multiply_a_w[0] = $signed(front_difference_x_r[36 +: 18]);
                    multiply_b_w[0] = edge_offset_y_w[2];
                    multiply_a_w[1] = $signed(front_difference_y_r[36 +: 18]);
                    multiply_b_w[1] = edge_offset_x_w[2];
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
        if (control_enable_w[1]) begin
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
                else if (control_enable_w[2]) valid_r <= previous_w[7:6];
            end
            always @(posedge clk_i) begin
                if (control_enable_w[0]) metadata_r <= previous_w[5:0];
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
        else if (control_enable_w[1]) attribute_read_valid_r <= attribute_valid_r;
    end
    always @(posedge clk_i) begin
        if (control_enable_w[2]) begin
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
        .enable_i(control_enable_w[0]),
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
                case ({screen_accept_w, complete_w})
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
            if (control_enable_w[1]) begin
                if (interval_r != 0) interval_r <= interval_r - 3'd1;
                if (accept_w) begin
                    interval_r <= 3'd7;
                    allocate_r <= allocate_r + 4'd1;
                end
                complete_r <= pa_valid_r[PA_LATENCY-1] && pa_attribute_w == 6;
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
        if (control_enable_w[2]) begin
            if (area_valid_r) nonzero_r[area_tag_r] <= area_w != 0;

            if (accept_w) begin

                front_tag_r <= allocate_r;
            end
            if (reciprocal_valid_w) begin
                attribute_tag_r <= reciprocal_tag_w[(RECIP_LATENCY-1)*4 +: 4];
                attribute_reciprocal_r <= reciprocal_w;
                attribute_exponent_r <= reciprocal_exponent_w;
            end
        end
    end
    // P-A 2.13.6a: two shared 3-APM multipliers (five clocks), then CSA/carry.
    // All 27 clocks advance with the setup stall domain; metadata is only 14 bits.
    localparam PA_LATENCY = 27;
    reg [PA_LATENCY-1:0] pa_valid_r;
    reg [5:0] pa_clock_r;
    wire [PA_LATENCY*14-1:0] unused_pa_metadata_w;
    wire [71:0] unused_pa_context_w;
    wire [71:0] unused_pa_start_w;
    wire [143:0] unused_pa_gradient_w;
    wire [5:0] pa_start_read_w;
    wire [5:0] pa_gradient_read_w;
    wire [73:0] unused_pa_product_x_w;
    wire [73:0] unused_pa_product_y_w;
    wire [71:0] pa_relocated_w;
    wire [215:0] pa_absolute_w;
    wire [2:0] pa_sign_w;
    wire [71:0] pa_gradient_maximum_w;
    wire [71:0] pa_bound_w;
    wire [71:0] unused_pa_bound_w;
    wire [215:0] pa_payload_input_w;
    wire [215:0] unused_pa_payload_w;
    wire [5:0] pa_payload_read_w;
    wire [5:0] pa_bound_read_w;
    wire [8:0] pa_byte_valid_w;
    wire [26:0] pa_byte_position_w;
    reg [3:0] pa_byte_index_r;
    reg [2:0] pa_selected_position_w;
    wire [6:0] pa_length_w;
    wire pa_wide_w;
    wire [71:0] pa_allowance_w;
    reg [5:0] pa_kappa_base_r [0:4];
    reg [71:0] pa_threshold_0_r;
    reg [71:0] pa_threshold_1_r;
    reg [71:0] pa_threshold_2_r;
    reg pa_bound_high_greater_r;
    reg pa_bound_high_equal_r;
    reg pa_bound_low_greater_r;
    reg [5:0] pa_kappa_r [0:7];
    wire [362:0] pa_edges_w;
    wire [503:0] pa_snapshot_input_w;
    wire [503:0] unused_pa_snapshot_w;
    wire [5:0] pa_snapshot_read_w;
    assign pa_snapshot_input_w = {44'b0, nonzero_r[plane_tag_w[6:3]],
        pa_edges_w, unused_output_context_read0_w[0 +: 96]};
    assign pa_snapshot_read_w = pa_clock_r - 6'd28;
    wire [2:0] pa_attribute_w;
    wire [9:0] pa_h_w;
    wire [41:0] pa_start_w;
    wire [63:0] pa_gradient_w;
    assign pa_start_read_w = pa_clock_r - 6'd5;
    assign pa_gradient_read_w = pa_clock_r - 6'd8;
    assign pa_payload_read_w = pa_clock_r - 6'd10;
    assign pa_bound_read_w = pa_clock_r - 6'd6;
    assign pa_attribute_w = unused_pa_metadata_w[(PA_LATENCY-1)*14 +: 3];
    assign pa_h_w = unused_pa_metadata_w[(PA_LATENCY-1)*14+3 +: 10]
        + {4'b0, pa_kappa_r[7]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            pa_valid_r <= 0;
            pa_clock_r <= 0;
        end else if (stop_i) begin
            pa_valid_r <= 0;
        end else if (enable_w) begin
            pa_valid_r <= {pa_valid_r[PA_LATENCY-2:0], plane_valid_w};
            pa_clock_r <= pa_clock_r + 1'b1;
        end
    end
    genvar pa_stage;
    generate
        for (pa_stage = 0; pa_stage < PA_LATENCY; pa_stage = pa_stage + 1) begin : g_pa_meta
            reg [13:0] value_r;
            wire [13:0] previous_w;
            if (pa_stage == 0) begin : g_first
                assign previous_w = {unused_pa_context_w[36], plane_h_w, plane_tag_w[2:0]};
            end else begin : g_previous
                assign previous_w = unused_pa_metadata_w[(pa_stage-1)*14 +: 14];
            end
            assign unused_pa_metadata_w[pa_stage*14 +: 14] = value_r;
            always @(posedge clk_i) begin
                if (control_enable_w[4]) value_r <= previous_w;
            end
        end
    endgenerate
    edrv32_ram_gpu_table u_pa_context (
        .clk_i(clk_i),
        .wr_en_i(screen_accept_w),
        .wr_addr_i({2'b0, allocate_r}),
        .wr_data_i({35'b0, pa_large_span_r,
            pa_origin_y_r - origin_y_w, pa_origin_x_r - origin_x_w}),
        .rd_addr_i({2'b0, plane_tag_w[6:3]}),
        .rd_data_o(unused_pa_context_w)
    );
    edrv32_ram_gpu_table u_pa_start_delay (
        .clk_i(clk_i),
        .wr_en_i(enable_w && plane_valid_w),
        .wr_addr_i(pa_clock_r),
        .wr_data_i({6'b0, plane_start_w}),
        .rd_addr_i(pa_start_read_w),
        .rd_data_o(unused_pa_start_w)
    );
    edrv32_ram_gpu_table u_pa_gradient_delay_0 (
        .clk_i(clk_i),
        .wr_en_i(enable_w && plane_valid_w),
        .wr_addr_i(pa_clock_r),
        .wr_data_i(plane_gradient_w[0 +: 72]),
        .rd_addr_i(pa_gradient_read_w),
        .rd_data_o(unused_pa_gradient_w[0 +: 72])
    );
    edrv32_ram_gpu_table u_pa_gradient_delay_1 (
        .clk_i(clk_i),
        .wr_en_i(enable_w && plane_valid_w),
        .wr_addr_i(pa_clock_r),
        .wr_data_i({40'b0, plane_gradient_w[72 +: 32]}),
        .rd_addr_i(pa_gradient_read_w),
        .rd_data_o(unused_pa_gradient_w[72 +: 72])
    );
    edrv32_apm_gpu_s56xs18 u_pa_product_x (
        .clk_i(clk_i),
        .enable_i(control_enable_w[4]),
        .a_i({{4{plane_gradient_w[51]}}, plane_gradient_w[0 +: 52]}),
        .b_i(unused_pa_context_w[0 +: 18]),
        .p_o(unused_pa_product_x_w)
    );
    edrv32_apm_gpu_s56xs18 u_pa_product_y (
        .clk_i(clk_i),
        .enable_i(control_enable_w[5]),
        .a_i({{4{plane_gradient_w[103]}}, plane_gradient_w[52 +: 52]}),
        .b_i(unused_pa_context_w[18 +: 18]),
        .p_o(unused_pa_product_y_w)
    );
    edrv32_gpu_raster_prepare #(
        .WIDTH(72)
    ) u_pa_relocate (
        .clk_i(clk_i),
        .en_i(control_enable_w[3]),
        .a_i({{6{unused_pa_start_w[65]}}, unused_pa_start_w[0 +: 66]}),
        .b_i(unused_pa_product_x_w[71:0]),
        .c_i(unused_pa_product_y_w[71:0]),
        .sum_o(pa_relocated_w)
    );
    genvar pa_field;
    generate
        // Three signed-to-magnitude paths, each using two <=36-bit carry segments.
        for (pa_field = 0; pa_field < 3; pa_field = pa_field + 1) begin : g_pa_absolute
            localparam WIDTH = pa_field == 0 ? 72 : 52;
            localparam LOW = WIDTH / 2;
            wire [WIDTH-1:0] value_w;
            wire [LOW:0] low_w;
            wire [WIDTH-LOW-1:0] high_w;
            reg [LOW-1:0] low_r;
            reg carry_r;
            reg [WIDTH-LOW-1:0] high_r;
            reg sign_r;
            reg output_sign_r;
            reg [WIDTH-1:0] magnitude_r;
            if (pa_field == 0) begin : g_start
                assign value_w = pa_relocated_w;
            end else begin : g_gradient
                assign value_w = unused_pa_gradient_w[(pa_field-1)*52 +: 52];
            end
            assign low_w = {1'b0, value_w[LOW-1:0] ^ {LOW{value_w[WIDTH-1]}}}
                + {{LOW{1'b0}}, value_w[WIDTH-1]};
            assign high_w = high_r + {{(WIDTH-LOW-1){1'b0}}, carry_r};
            assign pa_absolute_w[pa_field*72 +: 72] =
                {{(72-WIDTH){1'b0}}, magnitude_r};
            assign pa_sign_w[pa_field] = output_sign_r;
            always @(posedge clk_i) begin
                if (control_enable_w[3+pa_field]) begin
                    low_r <= low_w[LOW-1:0];
                    carry_r <= low_w[LOW];
                    high_r <= value_w[WIDTH-1:LOW] ^ {(WIDTH-LOW){value_w[WIDTH-1]}};
                    sign_r <= value_w[WIDTH-1];
                    magnitude_r <= {high_w, low_r};
                    output_sign_r <= sign_r;
                end
            end
        end
    endgenerate
    // Decide which gradient has larger magnitude in parallel with the two abs stages.
    // Same signs use an unsigned two-half comparison; opposite signs use sign(gx+gy).
    // Only a selector then precedes the B adder, avoiding two serial carry chains.
    wire [51:0] unused_pa_gradient_sum_w;
    reg pa_gradient_high_greater_r;
    reg pa_gradient_high_equal_r;
    reg pa_gradient_low_greater_equal_r;
    reg pa_gradient_greater_equal_r;
    wire pa_gradient_x_larger_w;
    edrv32_gpu_raster_add #(
        .WIDTH(52)
    ) u_pa_gradient_sum (
        .clk_i(clk_i),
        .en_i(control_enable_w[4]),
        .a_i(unused_pa_gradient_w[0 +: 52]),
        .b_i(unused_pa_gradient_w[52 +: 52]),
        .sum_o(unused_pa_gradient_sum_w)
    );
    always @(posedge clk_i) begin
        if (control_enable_w[4]) begin
            pa_gradient_high_greater_r <=
                unused_pa_gradient_w[26 +: 26] > unused_pa_gradient_w[78 +: 26];
            pa_gradient_high_equal_r <=
                unused_pa_gradient_w[26 +: 26] == unused_pa_gradient_w[78 +: 26];
            pa_gradient_low_greater_equal_r <=
                unused_pa_gradient_w[0 +: 26] >= unused_pa_gradient_w[52 +: 26];
            pa_gradient_greater_equal_r <= pa_gradient_high_greater_r ||
                (pa_gradient_high_equal_r && pa_gradient_low_greater_equal_r);
        end
    end
    assign pa_gradient_x_larger_w = pa_sign_w[1] != pa_sign_w[2] ?
        unused_pa_gradient_sum_w[51] == pa_sign_w[1] :
        pa_gradient_greater_equal_r ^ pa_sign_w[1];
    assign pa_gradient_maximum_w = pa_gradient_x_larger_w ?
        pa_absolute_w[72 +: 72] : pa_absolute_w[144 +: 72];
    edrv32_gpu_raster_add #(
        .WIDTH(72)
    ) u_pa_bound (
        .clk_i(clk_i),
        .en_i(control_enable_w[3]),
        .a_i(pa_absolute_w[0 +: 72]),
        .b_i(unused_pa_metadata_w[9*14+13] ?
            pa_gradient_maximum_w << 11 : pa_gradient_maximum_w << 10),
        .sum_o(pa_bound_w)
    );
    assign pa_payload_input_w = {37'b0, pa_sign_w,
        pa_absolute_w[144 +: 52], pa_absolute_w[72 +: 52], pa_absolute_w[0 +: 72]};
    edrv32_ram_gpu_table u_pa_payload_0 (
        .clk_i(clk_i),
        .wr_en_i(enable_w && pa_valid_r[9]),
        .wr_addr_i(pa_clock_r),
        .wr_data_i(pa_payload_input_w[0 +: 72]),
        .rd_addr_i(pa_payload_read_w),
        .rd_data_o(unused_pa_payload_w[0 +: 72])
    );
    edrv32_ram_gpu_table u_pa_payload_1 (
        .clk_i(clk_i),
        .wr_en_i(enable_w && pa_valid_r[9]),
        .wr_addr_i(pa_clock_r),
        .wr_data_i(pa_payload_input_w[72 +: 72]),
        .rd_addr_i(pa_payload_read_w),
        .rd_data_o(unused_pa_payload_w[72 +: 72])
    );
    edrv32_ram_gpu_table u_pa_payload_2 (
        .clk_i(clk_i),
        .wr_en_i(enable_w && pa_valid_r[9]),
        .wr_addr_i(pa_clock_r),
        .wr_data_i(pa_payload_input_w[144 +: 72]),
        .rd_addr_i(pa_payload_read_w),
        .rd_data_o(unused_pa_payload_w[144 +: 72])
    );
    edrv32_ram_gpu_table u_pa_bound_delay (
        .clk_i(clk_i),
        .wr_en_i(enable_w && pa_valid_r[11]),
        .wr_addr_i(pa_clock_r),
        .wr_data_i(pa_bound_w),
        .rd_addr_i(pa_bound_read_w),
        .rd_data_o(unused_pa_bound_w)
    );
    genvar pa_byte;
    generate
        for (pa_byte = 0; pa_byte < 9; pa_byte = pa_byte + 1) begin : g_pa_byte
            wire [7:0] value_w;
            reg valid_r;
            reg [2:0] position_r;
            reg [2:0] position_w;
            assign value_w = pa_bound_w[pa_byte*8 +: 8];
            assign pa_byte_valid_w[pa_byte] = valid_r;
            assign pa_byte_position_w[pa_byte*3 +: 3] = position_r;
            always @(*) begin
                position_w = 0;
                casez (value_w)
                    8'b1???????: position_w = 3'd7;
                    8'b01??????: position_w = 3'd6;
                    8'b001?????: position_w = 3'd5;
                    8'b0001????: position_w = 3'd4;
                    8'b00001???: position_w = 3'd3;
                    8'b000001??: position_w = 3'd2;
                    8'b0000001?: position_w = 3'd1;
                    default: begin end
                endcase
            end
            always @(posedge clk_i) begin
                if (enable_w) begin
                    valid_r <= |value_w;
                    position_r <= position_w;
                end
            end
        end
    endgenerate
    reg [26:0] pa_byte_position_r;
    reg [3:0] pa_byte_index_w;
    always @(*) begin
        pa_byte_index_w = 0;
        casez (pa_byte_valid_w)
            9'b1????????: pa_byte_index_w = 4'd8;
            9'b01???????: pa_byte_index_w = 4'd7;
            9'b001??????: pa_byte_index_w = 4'd6;
            9'b0001?????: pa_byte_index_w = 4'd5;
            9'b00001????: pa_byte_index_w = 4'd4;
            9'b000001???: pa_byte_index_w = 4'd3;
            9'b0000001??: pa_byte_index_w = 4'd2;
            9'b00000001?: pa_byte_index_w = 4'd1;
            default: begin end
        endcase
        pa_selected_position_w = 0;
        case (pa_byte_index_r)
            4'd0: pa_selected_position_w = pa_byte_position_r[0 +: 3];
            4'd1: pa_selected_position_w = pa_byte_position_r[3 +: 3];
            4'd2: pa_selected_position_w = pa_byte_position_r[6 +: 3];
            4'd3: pa_selected_position_w = pa_byte_position_r[9 +: 3];
            4'd4: pa_selected_position_w = pa_byte_position_r[12 +: 3];
            4'd5: pa_selected_position_w = pa_byte_position_r[15 +: 3];
            4'd6: pa_selected_position_w = pa_byte_position_r[18 +: 3];
            4'd7: pa_selected_position_w = pa_byte_position_r[21 +: 3];
            4'd8: pa_selected_position_w = pa_byte_position_r[24 +: 3];
            default: begin end
        endcase
    end
    assign pa_length_w = {pa_byte_index_r, 3'b0} + {4'b0, pa_selected_position_w} + 7'd1;
    assign pa_wide_w = unused_pa_metadata_w[13*14 +: 3] != 0
        && unused_pa_metadata_w[13*14 +: 3] < 4;
    // bit_length(floor((B-1)/A)) is the least k with B <= A*2^k.
    // Start with max(0,bit_length(B)-(W-1)), then compare the exact threshold once.
    assign pa_allowance_w = (unused_pa_metadata_w[14*14 +: 3] != 0
        && unused_pa_metadata_w[14*14 +: 3] < 4 ? 72'h20000000000 : 72'h80000000)
        - (unused_pa_metadata_w[14*14+13] ? 72'd1026 : 72'd514);
    wire [6:0] unused_pa_kappa_initial_w;
    assign unused_pa_kappa_initial_w = pa_length_w - (pa_wide_w ? 7'd41 : 7'd31);
    integer pa_delay;
    always @(posedge clk_i) begin
        if (control_enable_w[5]) begin
            pa_byte_index_r <= pa_byte_index_w;
            pa_byte_position_r <= pa_byte_position_w;
            pa_kappa_base_r[0] <= pa_length_w > (pa_wide_w ? 7'd41 : 7'd31) ?
                unused_pa_kappa_initial_w[5:0] : 6'd0;
            for (pa_delay = 1; pa_delay < 5; pa_delay = pa_delay + 1)
                pa_kappa_base_r[pa_delay] <= pa_kappa_base_r[pa_delay-1];
            pa_threshold_0_r <= pa_allowance_w << pa_kappa_base_r[0][1:0];
            pa_threshold_1_r <= pa_threshold_0_r << {pa_kappa_base_r[1][3:2], 2'b0};
            pa_threshold_2_r <= pa_threshold_1_r << {pa_kappa_base_r[2][5:4], 4'b0};
            pa_bound_high_greater_r <= unused_pa_bound_w[71:36] > pa_threshold_2_r[71:36];
            pa_bound_high_equal_r <= unused_pa_bound_w[71:36] == pa_threshold_2_r[71:36];
            pa_bound_low_greater_r <= unused_pa_bound_w[35:0] > pa_threshold_2_r[35:0];
            pa_kappa_r[0] <= pa_kappa_base_r[4] + {5'b0, pa_bound_high_greater_r
                || (pa_bound_high_equal_r && pa_bound_low_greater_r)};
            for (pa_delay = 1; pa_delay < 8; pa_delay = pa_delay + 1)
                pa_kappa_r[pa_delay] <= pa_kappa_r[pa_delay-1];
        end
    end
    generate
        for (pa_field = 0; pa_field < 3; pa_field = pa_field + 1) begin : g_pa_round
            localparam WIDTH = pa_field == 0 ? 42 : 32;
            wire [71:0] magnitude_w;
            wire sign_w;
            reg [72:0] shifted_0_r;
            reg [72:0] shifted_1_r;
            reg [WIDTH:0] shifted_2_r;
            reg [4:0] sign_r;
            wire [72:0] unused_shifted_2_w;
            assign unused_shifted_2_w = shifted_1_r >> {pa_kappa_r[2][5:4], 4'b0};
            wire [WIDTH-1:0] rounded_w;
            wire [WIDTH-1:0] signed_w;
            if (pa_field == 0) begin : g_start
                assign magnitude_w = unused_pa_payload_w[0 +: 72];
                assign pa_start_w = signed_w;
            end else begin : g_gradient
                assign magnitude_w = {20'b0,
                    unused_pa_payload_w[72+(pa_field-1)*52 +: 52]};
                assign pa_gradient_w[(pa_field-1)*32 +: 32] = signed_w;
            end
            assign sign_w = unused_pa_payload_w[176+pa_field];
            always @(posedge clk_i) begin
                if (control_enable_w[3+pa_field]) begin
                    shifted_0_r <= {magnitude_w, 1'b0} >> pa_kappa_r[0][1:0];
                    shifted_1_r <= shifted_0_r >> {pa_kappa_r[1][3:2], 2'b0};
                    shifted_2_r <= unused_shifted_2_w[WIDTH:0];
                    sign_r <= {sign_r[3:0], sign_w};
                end
            end
            edrv32_gpu_raster_add #(
                .WIDTH(WIDTH)
            ) u_round (
                .clk_i(clk_i),
                .en_i(control_enable_w[3+pa_field]),
                .a_i(shifted_2_r[WIDTH:1]),
                .b_i({{(WIDTH-1){1'b0}}, shifted_2_r[0]}),
                .sum_o(rounded_w)
            );
            edrv32_gpu_raster_add #(
                .WIDTH(WIDTH)
            ) u_sign (
                .clk_i(clk_i),
                .en_i(control_enable_w[3+pa_field]),
                .a_i(rounded_w ^ {WIDTH{sign_r[4]}}),
                .b_i({{(WIDTH-1){1'b0}}, sign_r[4]}),
                .sum_o(signed_w)
            );
        end
    endgenerate
    edrv32_ram_gpu_table u_pa_snapshot_0 (
        .clk_i(clk_i),
        .wr_en_i(enable_w && plane_valid_w && plane_tag_w[2:0] == 6),
        .wr_addr_i(pa_clock_r),
        .wr_data_i(pa_snapshot_input_w[0 +: 72]),
        .rd_addr_i(pa_snapshot_read_w),
        .rd_data_o(unused_pa_snapshot_w[0 +: 72])
    );
    edrv32_ram_gpu_table u_pa_snapshot_1 (
        .clk_i(clk_i),
        .wr_en_i(enable_w && plane_valid_w && plane_tag_w[2:0] == 6),
        .wr_addr_i(pa_clock_r),
        .wr_data_i(pa_snapshot_input_w[72 +: 72]),
        .rd_addr_i(pa_snapshot_read_w),
        .rd_data_o(unused_pa_snapshot_w[72 +: 72])
    );
    edrv32_ram_gpu_table u_pa_snapshot_2 (
        .clk_i(clk_i),
        .wr_en_i(enable_w && plane_valid_w && plane_tag_w[2:0] == 6),
        .wr_addr_i(pa_clock_r),
        .wr_data_i(pa_snapshot_input_w[144 +: 72]),
        .rd_addr_i(pa_snapshot_read_w),
        .rd_data_o(unused_pa_snapshot_w[144 +: 72])
    );
    edrv32_ram_gpu_table u_pa_snapshot_3 (
        .clk_i(clk_i),
        .wr_en_i(enable_w && plane_valid_w && plane_tag_w[2:0] == 6),
        .wr_addr_i(pa_clock_r),
        .wr_data_i(pa_snapshot_input_w[216 +: 72]),
        .rd_addr_i(pa_snapshot_read_w),
        .rd_data_o(unused_pa_snapshot_w[216 +: 72])
    );
    edrv32_ram_gpu_table u_pa_snapshot_4 (
        .clk_i(clk_i),
        .wr_en_i(enable_w && plane_valid_w && plane_tag_w[2:0] == 6),
        .wr_addr_i(pa_clock_r),
        .wr_data_i(pa_snapshot_input_w[288 +: 72]),
        .rd_addr_i(pa_snapshot_read_w),
        .rd_data_o(unused_pa_snapshot_w[288 +: 72])
    );
    edrv32_ram_gpu_table u_pa_snapshot_5 (
        .clk_i(clk_i),
        .wr_en_i(enable_w && plane_valid_w && plane_tag_w[2:0] == 6),
        .wr_addr_i(pa_clock_r),
        .wr_data_i(pa_snapshot_input_w[360 +: 72]),
        .rd_addr_i(pa_snapshot_read_w),
        .rd_data_o(unused_pa_snapshot_w[360 +: 72])
    );
    edrv32_ram_gpu_table u_pa_snapshot_6 (
        .clk_i(clk_i),
        .wr_en_i(enable_w && plane_valid_w && plane_tag_w[2:0] == 6),
        .wr_addr_i(pa_clock_r),
        .wr_data_i(pa_snapshot_input_w[432 +: 72]),
        .rd_addr_i(pa_snapshot_read_w),
        .rd_data_o(unused_pa_snapshot_w[432 +: 72])
    );

    // Context and output queues are split by field; each bank has one whole-element write.
    reg [63:0] output_bounds_r [0:1];
    assign triangle_setup_bounds_o = output_bounds_r[output_read_r];
    always @(posedge clk_i) begin
        if (push_w)
            output_bounds_r[output_write_r] <= unused_pa_snapshot_w[32 +: 64];
    end
    reg [31:0] output_origin_r [0:1];
    assign triangle_setup_origin_o = output_origin_r[output_read_r];
    always @(posedge clk_i) begin
        if (push_w)
            output_origin_r[output_write_r] <= unused_pa_snapshot_w[0 +: 32];
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
            localparam WIDTH = attribute == 0 ? 32 : attribute < 4 ? 42 : 32;
            localparam GRAD_WIDTH = WIDTH - 10;
            localparam START_OFFSET = attribute == 0 ? 0 : attribute < 4 ?
                32 + (attribute-1)*42 : 158 + (attribute-4)*32;
            localparam GRAD_OFFSET = attribute == 0 ? 0 : attribute < 4 ?
                44 + (attribute-1)*64 : 236 + (attribute-4)*44;
            // Ordered attribute returns need one assembly register per field.
            // The next triangle's attribute 0 may arrive on the old triangle's push clock;
            // nonblocking writes retain the old coefficient for that output transfer.
            reg [WIDTH-1:0] start_r;
            reg [WIDTH-1:0] output_start_r [0:1];
            assign triangle_setup_start_o[START_OFFSET +: WIDTH] =
                output_start_r[output_read_r];
            always @(posedge clk_i) begin
                if (control_enable_w[0] && pa_valid_r[PA_LATENCY-1] && pa_attribute_w == attribute)
                    start_r <= pa_start_w[WIDTH-1:0];
                if (push_w)
                    output_start_r[output_write_r] <= start_r;
            end
            reg [2*GRAD_WIDTH-1:0] gradient_r;
            reg [2*GRAD_WIDTH-1:0] output_gradient_r [0:1];
            assign triangle_setup_gradient_o[GRAD_OFFSET +: 2*GRAD_WIDTH] =
                output_gradient_r[output_read_r];
            always @(posedge clk_i) begin
                if (control_enable_w[1] && pa_valid_r[PA_LATENCY-1] && pa_attribute_w == attribute)
                    gradient_r <= {pa_gradient_w[32 +: GRAD_WIDTH],
                        pa_gradient_w[0 +: GRAD_WIDTH]};
                if (push_w)
                    output_gradient_r[output_write_r] <= gradient_r;
            end
            reg [9:0] h_r;
            reg [9:0] output_h_r [0:1];
            assign triangle_setup_h_o[attribute*10 +: 10] =
                output_h_r[output_read_r];
            always @(posedge clk_i) begin
                if (control_enable_w[2] && pa_valid_r[PA_LATENCY-1] && pa_attribute_w == attribute)
                    h_r <= pa_h_w;
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
                    if (control_enable_w[0]) u_value_data_r <= u_value_data_w;
                end
                edrv32_ram_gpu_table u_value (
                    .clk_i(clk_i),
                    .wr_en_i(control_enable_w[1] && screen_accept_w),
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
            wire value_write_w;
            wire [3:0] value_tag_w;

            wire [39:0] dx_w;
            wire [39:0] dy_w;
            wire [39:0] bias_w;
            wire [39:0] value_w;


            reg [39:0] output_value_r [0:1];

            reg [39:0] output_dx_r [0:1];

            reg [39:0] output_dy_r [0:1];

            reg output_bias_r [0:1];
            // Explicit LUTRAM edge_value: 1 slice(s) per combinational read port.
            wire [71:0] edge_value_input_w;
            assign edge_value_input_w = {32'b0, value_w};
            wire [71:0] unused_edge_value_read0_w;
            edrv32_ram_gpu_table u_edge_value_p0_b0 (
                .clk_i(clk_i),
                .wr_en_i(control_enable_w[2] && value_write_w),
                .wr_addr_i({2'b0, value_tag_w}),
                .wr_data_i(edge_value_input_w[0 +: 72]),
                .rd_addr_i({2'b0, plane_tag_w[6:3]}),
                .rd_data_o(unused_edge_value_read0_w[0 +: 72])
            );
            // Explicit LUTRAM edge_coefficients: 2 slice(s) per combinational read port.
            wire [143:0] edge_coefficients_input_w;
            assign edge_coefficients_input_w = {24'b0, bias_w, dy_w, dx_w};
            wire [143:0] unused_edge_coefficients_read0_w;
            edrv32_ram_gpu_table u_edge_coefficients_p0_b0 (
                .clk_i(clk_i),
                .wr_en_i(control_enable_w[0] && accept_w),
                .wr_addr_i({2'b0, allocate_r}),
                .wr_data_i(edge_coefficients_input_w[0 +: 72]),
                .rd_addr_i({2'b0, plane_tag_w[6:3]}),
                .rd_data_o(unused_edge_coefficients_read0_w[0 +: 72])
            );
            edrv32_ram_gpu_table u_edge_coefficients_p0_b1 (
                .clk_i(clk_i),
                .wr_en_i(control_enable_w[1] && accept_w),
                .wr_addr_i({2'b0, allocate_r}),
                .wr_data_i(edge_coefficients_input_w[72 +: 72]),
                .rd_addr_i({2'b0, plane_tag_w[6:3]}),
                .rd_data_o(unused_edge_coefficients_read0_w[72 +: 72])
            );
            assign pa_edges_w[edge_bank*121 +: 40] = unused_edge_value_read0_w[0 +: 40];
            assign pa_edges_w[edge_bank*121+40 +: 80] =
                unused_edge_coefficients_read0_w[0 +: 80];
            assign pa_edges_w[edge_bank*121+120] = unused_edge_coefficients_read0_w[119];
            assign dx_w = -$signed({{22{front_difference_y_r[VERTEX*18+17]}},
                front_difference_y_r[VERTEX*18 +: 18]}) <<< 4;
            assign dy_w = $signed({{22{front_difference_x_r[VERTEX*18+17]}},
                front_difference_x_r[VERTEX*18 +: 18]}) <<< 4;
            assign bias_w = $signed(front_difference_y_r[VERTEX*18 +: 18]) < 0 ||
                (front_difference_y_r[VERTEX*18 +: 18] == 0
                && $signed(front_difference_x_r[VERTEX*18 +: 18]) > 0)
                ? 40'd0 : -40'd1;
            assign value_write_w = edge_valid_r && edge_index_r == VERTEX;
            assign value_tag_w = area_tag_r;
            assign value_w = {{3{edge_result_w[36]}}, edge_result_w};
            always @(posedge clk_i) begin

                if (push_w)

                    output_value_r[output_write_r] <=
                        unused_pa_snapshot_w[96+edge_bank*121 +: 40];
                if (push_w)
                    output_dx_r[output_write_r] <=
                        unused_pa_snapshot_w[96+edge_bank*121+40 +: 40];
                if (push_w)
                    output_dy_r[output_write_r] <=
                        unused_pa_snapshot_w[96+edge_bank*121+80 +: 40];
                if (push_w)
                    output_bias_r[output_write_r] <=
                        unused_pa_snapshot_w[96+edge_bank*121+120];
            end
            assign triangle_setup_edge_o[edge_bank*160+0 +: 40] =
                output_value_r[output_read_r];
            assign triangle_setup_edge_o[edge_bank*160+40 +: 40] =
                output_dx_r[output_read_r];
            assign triangle_setup_edge_o[edge_bank*160+80 +: 40] =
                output_dy_r[output_read_r];
            assign triangle_setup_edge_o[edge_bank*160+120 +: 40] =
                {40{output_bias_r[output_read_r]}};
        end
    endgenerate
    // Explicit LUTRAM attribute_context: 2 slice(s) per combinational read port.
    wire [143:0] attribute_context_input_w;
    assign attribute_context_input_w = {36'b0, offset_w, delta_w};
    wire [143:0] unused_attribute_context_read0_w;
    edrv32_ram_gpu_table u_attribute_context_p0_b0 (
        .clk_i(clk_i),
        .wr_en_i(control_enable_w[2] && screen_accept_w),
        .wr_addr_i({2'b0, allocate_r}),
        .wr_data_i(attribute_context_input_w[0 +: 72]),
        .rd_addr_i({2'b0, attribute_tag_r}),
        .rd_data_o(unused_attribute_context_read0_w[0 +: 72])
    );
    edrv32_ram_gpu_table u_attribute_context_p0_b1 (
        .clk_i(clk_i),
        .wr_en_i(control_enable_w[0] && screen_accept_w),
        .wr_addr_i({2'b0, allocate_r}),
        .wr_data_i(attribute_context_input_w[72 +: 72]),
        .rd_addr_i({2'b0, attribute_tag_r}),
        .rd_data_o(unused_attribute_context_read0_w[72 +: 72])
    );
    // Explicit LUTRAM output_context: 2 slice(s) per combinational read port.
    wire [143:0] output_context_input_w;
    assign output_context_input_w = {48'b0,
        {clipped_bound_y1_r[15:0], clipped_bound_x1_r[15:0],
        clipped_bound_y0_r[15:0], clipped_bound_x0_r[15:0]},
        {pa_origin_y_r[15:0], pa_origin_x_r[15:0]}};
    wire [143:0] unused_output_context_read0_w;
    edrv32_ram_gpu_table u_output_context_p0_b0 (
        .clk_i(clk_i),
        .wr_en_i(control_enable_w[1] && accept_w),
        .wr_addr_i({2'b0, allocate_r}),
        .wr_data_i(output_context_input_w[0 +: 72]),
        .rd_addr_i({2'b0, plane_tag_w[6:3]}),
        .rd_data_o(unused_output_context_read0_w[0 +: 72])
    );
    edrv32_ram_gpu_table u_output_context_p0_b1 (
        .clk_i(clk_i),
        .wr_en_i(control_enable_w[2] && accept_w),
        .wr_addr_i({2'b0, allocate_r}),
        .wr_data_i(output_context_input_w[72 +: 72]),
        .rd_addr_i({2'b0, plane_tag_w[6:3]}),
        .rd_data_o(unused_output_context_read0_w[72 +: 72])
    );
endmodule
