// File: edrv32_gpu_clip.v
// Spec: gpu-spec 2.4; GPU microarchitecture 4.3.
// Description: Five ordered Sutherland-Hodgman passes with two eight-vertex worksets.
//              Crossing edges use the symmetric exact quotient; all-inside triangles bypass
//              worksets.
// Clock domain: clk_gpu.
module edrv32_gpu_clip (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Three transformed vertices.
    input wire triangle_valid_i,
    output wire triangle_ready_o,
    input wire [791:0] triangle_data_i,

    // Clipped polygon in fan order, vertex zero in the low bits.
    output wire polygon_valid_o,
    input wire polygon_ready_i,
    output wire [2111:0] polygon_data_o,
    output wire [3:0] polygon_count_o,

    // Drain control.
    input wire stop_i,
    output wire idle_o
);
    wire [791:0] triangle_saved_w;
    wire source_accept_w;
    reg [4:0] wait_r;
    wire [85:0] distance_left_w;
    wire [85:0] distance_right_w;
    wire [1:0] distance_subtract_w;
    wire [83:0] numerator_magnitude_w;
    wire [43:0] denominator_magnitude_w;
    wire quotient_negative_w;
    localparam S_CHECK = 4'd11;
    localparam S_IDLE = 4'd0;
    localparam S_BEGIN = 4'd1;
    localparam S_EDGE = 4'd2;
    localparam S_MULTIPLY = 4'd3;
    localparam S_DIVIDE_LOAD = 4'd4;
    localparam S_DIVIDE = 4'd5;
    localparam S_ROUND = 4'd6;
    localparam S_APPEND_INTERSECTION = 4'd7;
    localparam S_APPEND_CURRENT = 4'd8;
    localparam S_ADVANCE = 4'd9;
    localparam S_OUTPUT = 4'd10;
    reg [3:0] state_r;
    reg bank_r;
    reg [2:0] plane_r;
    reg [3:0] input_count_r;
    reg [3:0] result_count_r;
    reg [2:0] vertex_index_r;
    reg [3:0] component_r;
    reg signed [42:0] previous_distance_r;
    wire signed [42:0] current_distance_w;
    wire signed [42:0] last_distance_w;
    reg [43:0] divisor_r;
    reg negative_r;
    reg [83:0] quotient_r;
    reg [44:0] remainder_r;
    reg [6:0] divide_count_r;
    wire [44:0] remainder_shift_w;
    wire [44:0] remainder_next_w;
    wire [83:0] quotient_next_w;
    wire [39:0] intersection_value_w;
    wire all_inside_w;
    wire [14:0] outside_w;
    wire signed [39:0] previous_component_w [0:8];
    wire signed [39:0] current_component_w [0:8];
    reg signed [39:0] previous_selected_w;
    reg signed [39:0] current_selected_w;
    wire [39:0] current_position_w [0:2];
    wire [39:0] last_position_w [0:2];
    wire signed [42:0] edge_distance_w [0:1];
    wire accept_w;
    wire push_w;
    wire pop_w;
    reg [1:0] count_r;
    reg read_r;
    reg write_r;
    reg [3:0] output_count_r [0:1];

    assign triangle_ready_o = state_r == S_IDLE && count_r != 2 && !stop_i;
    assign source_accept_w = triangle_valid_i && triangle_ready_o;
    assign accept_w = state_r == S_CHECK && wait_r == 0;
    assign push_w = !stop_i && ((accept_w && all_inside_w)
        || (state_r == S_OUTPUT && count_r != 2));
    assign polygon_valid_o = count_r != 0;
    assign polygon_count_o = output_count_r[read_r];
    assign pop_w = polygon_valid_o && polygon_ready_i;
    assign idle_o = state_r == S_IDLE && count_r == 0;
    assign remainder_shift_w = {remainder_r[43:0], quotient_r[83]};
    assign last_distance_w = edge_distance_w[0];
    assign current_distance_w = edge_distance_w[1];
    assign all_inside_w = ~|outside_w;

    // Acceptance stage: three copies of five s43 plane add/subtract units.
    // Edge stage: two paths, each one s43 adder and one s43 subtractor, selected by plane_r.
    wire [42:0] inside_0_x_w;
    wire [42:0] inside_0_y_w;
    wire [42:0] inside_0_w_w;
    wire [42:0] inside_w4_0_w;
    wire [42:0] inside_near0_w;
    wire [34:0] inside_0_near_a0_w;
    wire [34:0] inside_0_near_b0_w;
    reg [35:0] inside_0_near_part0_r;
    wire [34:0] inside_0_near_low0_w;
    wire [7:0] inside_0_near_a1_w;
    reg [7:0] inside_0_near_a1_w_d1_r;
    wire [7:0] inside_0_near_b1_w;
    reg [7:0] inside_0_near_b1_w_d1_r;
    reg [8:0] unused_inside_0_near_part1_r;
    wire [7:0] inside_0_near_low1_w;
    wire [42:0] unused_inside_0_near_w;
    reg [34:0] inside_0_near_low0_w_d2_r;
    wire [34:0] inside_0_xplus_a0_w;
    wire [34:0] inside_0_xplus_b0_w;
    reg [35:0] inside_0_xplus_part0_r;
    wire [34:0] inside_0_xplus_low0_w;
    wire [7:0] inside_0_xplus_a1_w;
    wire [7:0] inside_0_xplus_b1_w;
    reg [7:0] inside_0_xplus_a1_w_d1_r;
    reg [7:0] inside_0_xplus_b1_w_d1_r;
    reg [8:0] unused_inside_0_xplus_part1_r;
    wire [7:0] inside_0_xplus_low1_w;
    wire [42:0] unused_inside_0_xplus_w;
    reg [34:0] inside_0_xplus_low0_w_d2_r;
    wire [34:0] inside_0_xminus_a0_w;
    wire [34:0] inside_0_xminus_b0_w;
    reg [35:0] inside_0_xminus_part0_r;
    wire [34:0] inside_0_xminus_low0_w;
    wire [7:0] inside_0_xminus_a1_w;
    reg [7:0] inside_0_xminus_a1_w_d1_r;
    wire [7:0] inside_0_xminus_b1_w;
    reg [7:0] inside_0_xminus_b1_w_d1_r;
    reg [8:0] unused_inside_0_xminus_part1_r;
    wire [7:0] inside_0_xminus_low1_w;
    wire [42:0] unused_inside_0_xminus_w;
    reg [34:0] inside_0_xminus_low0_w_d2_r;
    wire [34:0] inside_0_yplus_a0_w;
    wire [34:0] inside_0_yplus_b0_w;
    reg [35:0] inside_0_yplus_part0_r;
    wire [34:0] inside_0_yplus_low0_w;
    wire [7:0] inside_0_yplus_a1_w;
    wire [7:0] inside_0_yplus_b1_w;
    reg [7:0] inside_0_yplus_a1_w_d1_r;
    reg [7:0] inside_0_yplus_b1_w_d1_r;
    reg [8:0] unused_inside_0_yplus_part1_r;
    wire [7:0] inside_0_yplus_low1_w;
    wire [42:0] unused_inside_0_yplus_w;
    reg [34:0] inside_0_yplus_low0_w_d2_r;
    wire [34:0] inside_0_yminus_a0_w;
    wire [34:0] inside_0_yminus_b0_w;
    reg [35:0] inside_0_yminus_part0_r;
    wire [34:0] inside_0_yminus_low0_w;
    wire [7:0] inside_0_yminus_a1_w;
    reg [7:0] inside_0_yminus_a1_w_d1_r;
    wire [7:0] inside_0_yminus_b1_w;
    reg [7:0] inside_0_yminus_b1_w_d1_r;
    reg [8:0] unused_inside_0_yminus_part1_r;
    wire [7:0] inside_0_yminus_low1_w;
    wire [42:0] unused_inside_0_yminus_w;
    reg [34:0] inside_0_yminus_low0_w_d2_r;
    wire [42:0] inside_1_x_w;
    wire [42:0] inside_1_y_w;
    wire [42:0] inside_1_w_w;
    wire [42:0] inside_w4_1_w;
    wire [42:0] inside_near1_w;
    wire [34:0] inside_1_near_a0_w;
    wire [34:0] inside_1_near_b0_w;
    reg [35:0] inside_1_near_part0_r;
    wire [34:0] inside_1_near_low0_w;
    wire [7:0] inside_1_near_a1_w;
    reg [7:0] inside_1_near_a1_w_d1_r;
    wire [7:0] inside_1_near_b1_w;
    reg [7:0] inside_1_near_b1_w_d1_r;
    reg [8:0] unused_inside_1_near_part1_r;
    wire [7:0] inside_1_near_low1_w;
    wire [42:0] unused_inside_1_near_w;
    reg [34:0] inside_1_near_low0_w_d2_r;
    wire [34:0] inside_1_xplus_a0_w;
    wire [34:0] inside_1_xplus_b0_w;
    reg [35:0] inside_1_xplus_part0_r;
    wire [34:0] inside_1_xplus_low0_w;
    wire [7:0] inside_1_xplus_a1_w;
    wire [7:0] inside_1_xplus_b1_w;
    reg [7:0] inside_1_xplus_a1_w_d1_r;
    reg [7:0] inside_1_xplus_b1_w_d1_r;
    reg [8:0] unused_inside_1_xplus_part1_r;
    wire [7:0] inside_1_xplus_low1_w;
    wire [42:0] unused_inside_1_xplus_w;
    reg [34:0] inside_1_xplus_low0_w_d2_r;
    wire [34:0] inside_1_xminus_a0_w;
    wire [34:0] inside_1_xminus_b0_w;
    reg [35:0] inside_1_xminus_part0_r;
    wire [34:0] inside_1_xminus_low0_w;
    wire [7:0] inside_1_xminus_a1_w;
    reg [7:0] inside_1_xminus_a1_w_d1_r;
    wire [7:0] inside_1_xminus_b1_w;
    reg [7:0] inside_1_xminus_b1_w_d1_r;
    reg [8:0] unused_inside_1_xminus_part1_r;
    wire [7:0] inside_1_xminus_low1_w;
    wire [42:0] unused_inside_1_xminus_w;
    reg [34:0] inside_1_xminus_low0_w_d2_r;
    wire [34:0] inside_1_yplus_a0_w;
    wire [34:0] inside_1_yplus_b0_w;
    reg [35:0] inside_1_yplus_part0_r;
    wire [34:0] inside_1_yplus_low0_w;
    wire [7:0] inside_1_yplus_a1_w;
    wire [7:0] inside_1_yplus_b1_w;
    reg [7:0] inside_1_yplus_a1_w_d1_r;
    reg [7:0] inside_1_yplus_b1_w_d1_r;
    reg [8:0] unused_inside_1_yplus_part1_r;
    wire [7:0] inside_1_yplus_low1_w;
    wire [42:0] unused_inside_1_yplus_w;
    reg [34:0] inside_1_yplus_low0_w_d2_r;
    wire [34:0] inside_1_yminus_a0_w;
    wire [34:0] inside_1_yminus_b0_w;
    reg [35:0] inside_1_yminus_part0_r;
    wire [34:0] inside_1_yminus_low0_w;
    wire [7:0] inside_1_yminus_a1_w;
    reg [7:0] inside_1_yminus_a1_w_d1_r;
    wire [7:0] inside_1_yminus_b1_w;
    reg [7:0] inside_1_yminus_b1_w_d1_r;
    reg [8:0] unused_inside_1_yminus_part1_r;
    wire [7:0] inside_1_yminus_low1_w;
    wire [42:0] unused_inside_1_yminus_w;
    reg [34:0] inside_1_yminus_low0_w_d2_r;
    wire [42:0] inside_2_x_w;
    wire [42:0] inside_2_y_w;
    wire [42:0] inside_2_w_w;
    wire [42:0] inside_w4_2_w;
    wire [42:0] inside_near2_w;
    wire [34:0] inside_2_near_a0_w;
    wire [34:0] inside_2_near_b0_w;
    reg [35:0] inside_2_near_part0_r;
    wire [34:0] inside_2_near_low0_w;
    wire [7:0] inside_2_near_a1_w;
    reg [7:0] inside_2_near_a1_w_d1_r;
    wire [7:0] inside_2_near_b1_w;
    reg [7:0] inside_2_near_b1_w_d1_r;
    reg [8:0] unused_inside_2_near_part1_r;
    wire [7:0] inside_2_near_low1_w;
    wire [42:0] unused_inside_2_near_w;
    reg [34:0] inside_2_near_low0_w_d2_r;
    wire [34:0] inside_2_xplus_a0_w;
    wire [34:0] inside_2_xplus_b0_w;
    reg [35:0] inside_2_xplus_part0_r;
    wire [34:0] inside_2_xplus_low0_w;
    wire [7:0] inside_2_xplus_a1_w;
    wire [7:0] inside_2_xplus_b1_w;
    reg [7:0] inside_2_xplus_a1_w_d1_r;
    reg [7:0] inside_2_xplus_b1_w_d1_r;
    reg [8:0] unused_inside_2_xplus_part1_r;
    wire [7:0] inside_2_xplus_low1_w;
    wire [42:0] unused_inside_2_xplus_w;
    reg [34:0] inside_2_xplus_low0_w_d2_r;
    wire [34:0] inside_2_xminus_a0_w;
    wire [34:0] inside_2_xminus_b0_w;
    reg [35:0] inside_2_xminus_part0_r;
    wire [34:0] inside_2_xminus_low0_w;
    wire [7:0] inside_2_xminus_a1_w;
    reg [7:0] inside_2_xminus_a1_w_d1_r;
    wire [7:0] inside_2_xminus_b1_w;
    reg [7:0] inside_2_xminus_b1_w_d1_r;
    reg [8:0] unused_inside_2_xminus_part1_r;
    wire [7:0] inside_2_xminus_low1_w;
    wire [42:0] unused_inside_2_xminus_w;
    reg [34:0] inside_2_xminus_low0_w_d2_r;
    wire [34:0] inside_2_yplus_a0_w;
    wire [34:0] inside_2_yplus_b0_w;
    reg [35:0] inside_2_yplus_part0_r;
    wire [34:0] inside_2_yplus_low0_w;
    wire [7:0] inside_2_yplus_a1_w;
    wire [7:0] inside_2_yplus_b1_w;
    reg [7:0] inside_2_yplus_a1_w_d1_r;
    reg [7:0] inside_2_yplus_b1_w_d1_r;
    reg [8:0] unused_inside_2_yplus_part1_r;
    wire [7:0] inside_2_yplus_low1_w;
    wire [42:0] unused_inside_2_yplus_w;
    reg [34:0] inside_2_yplus_low0_w_d2_r;
    wire [34:0] inside_2_yminus_a0_w;
    wire [34:0] inside_2_yminus_b0_w;
    reg [35:0] inside_2_yminus_part0_r;
    wire [34:0] inside_2_yminus_low0_w;
    wire [7:0] inside_2_yminus_a1_w;
    reg [7:0] inside_2_yminus_a1_w_d1_r;
    wire [7:0] inside_2_yminus_b1_w;
    reg [7:0] inside_2_yminus_b1_w_d1_r;
    reg [8:0] unused_inside_2_yminus_part1_r;
    wire [7:0] inside_2_yminus_low1_w;
    wire [42:0] unused_inside_2_yminus_w;
    reg [34:0] inside_2_yminus_low0_w_d2_r;
    reg [42:0] edge_left0_r;
    reg [42:0] edge_right0_r;
    reg [0:0] edge_subtract0_r;
    wire [34:0] edge_add0_a0_w;
    wire [34:0] edge_add0_b0_w;
    reg [35:0] edge_add0_part0_r;
    wire [34:0] edge_add0_low0_w;
    wire [7:0] edge_add0_a1_w;
    wire [7:0] edge_add0_b1_w;
    reg [7:0] edge_add0_a1_w_d1_r;
    reg [7:0] edge_add0_b1_w_d1_r;
    reg [8:0] unused_edge_add0_part1_r;
    wire [7:0] edge_add0_low1_w;
    wire [42:0] edge_add0_w;
    reg [34:0] edge_add0_low0_w_d2_r;
    wire [34:0] edge_sub0_a0_w;
    wire [34:0] edge_sub0_b0_w;
    reg [35:0] edge_sub0_part0_r;
    wire [34:0] edge_sub0_low0_w;
    wire [7:0] edge_sub0_a1_w;
    reg [7:0] edge_sub0_a1_w_d1_r;
    wire [7:0] edge_sub0_b1_w;
    reg [7:0] edge_sub0_b1_w_d1_r;
    reg [8:0] unused_edge_sub0_part1_r;
    wire [7:0] edge_sub0_low1_w;
    wire [42:0] edge_sub0_w;
    reg [34:0] edge_sub0_low0_w_d2_r;
    reg [0:0] edge_subtract0_r_d1_r;
    reg [0:0] edge_subtract0_r_d2_r;
    reg [42:0] edge_left1_r;
    reg [42:0] edge_right1_r;
    reg [0:0] edge_subtract1_r;
    wire [34:0] edge_add1_a0_w;
    wire [34:0] edge_add1_b0_w;
    reg [35:0] edge_add1_part0_r;
    wire [34:0] edge_add1_low0_w;
    wire [7:0] edge_add1_a1_w;
    wire [7:0] edge_add1_b1_w;
    reg [7:0] edge_add1_a1_w_d1_r;
    reg [7:0] edge_add1_b1_w_d1_r;
    reg [8:0] unused_edge_add1_part1_r;
    wire [7:0] edge_add1_low1_w;
    wire [42:0] edge_add1_w;
    reg [34:0] edge_add1_low0_w_d2_r;
    wire [34:0] edge_sub1_a0_w;
    wire [34:0] edge_sub1_b0_w;
    reg [35:0] edge_sub1_part0_r;
    wire [34:0] edge_sub1_low0_w;
    wire [7:0] edge_sub1_a1_w;
    reg [7:0] edge_sub1_a1_w_d1_r;
    wire [7:0] edge_sub1_b1_w;
    reg [7:0] edge_sub1_b1_w_d1_r;
    reg [8:0] unused_edge_sub1_part1_r;
    wire [7:0] edge_sub1_low1_w;
    wire [42:0] edge_sub1_w;
    reg [34:0] edge_sub1_low0_w_d2_r;
    reg [0:0] edge_subtract1_r_d1_r;
    reg [0:0] edge_subtract1_r_d2_r;
    reg [39:0] previous_component_r;
    reg [39:0] current_component_r;
    reg [42:0] current_distance_r;
    reg [42:0] previous_distance_input_r;
    // Two 40x43 signed products: nine registered native signed <=18x18 APMs each.
    // Four balanced tree levels settle within three clocks each; +10 per component.
    // S_MULTIPLY holds each component/distance constant throughout its 22-clock wait;
    // the result is sampled only after that wait. Finished low/middle fields remain
    // in their own registers instead of being delayed to align with the high field.
    // Every carry crosses a register: all paths remain single-clock paths, with no
    // multicycle timing exceptions. The thirteen-clock settling bound is unchanged.
    // Store only each node's live signed range: constant low zeros and sign copies
    // are reconstructed at its consumer, never shifted through data registers.
    wire [82:0] previous_product_w;
    wire [82:0] current_product_w;
    wire [165:0] product_result_w;
    assign previous_product_w = product_result_w[0 +: 83];
    assign current_product_w = product_result_w[83 +: 83];
    genvar product_g;
    generate
        for (product_g = 0; product_g < 2; product_g = product_g + 1) begin : g_product
            wire [39:0] component_w;
            wire [42:0] distance_w;
            assign component_w = product_g == 0 ? previous_component_r : current_component_r;
            assign distance_w = product_g == 0 ? current_distance_r : previous_distance_input_r;
            wire [35:0] node0_w;
            wire [35:0] node1_w;
            wire [26:0] node2_w;
            wire [35:0] node3_w;
            wire [35:0] node4_w;
            wire [26:0] node5_w;
            wire [23:0] node6_w;
            wire [23:0] node7_w;
            wire [14:0] node8_w;
            wire [53:0] node9_w;
            wire [44:0] node10_w;
            wire [44:0] node11_w;
            wire [41:0] node12_w;
            wire [14:0] node13_w;
            wire [62:0] node14_w;
            wire [45:0] node15_w;
            wire [14:0] node16_w;
            wire [80:0] node17_w;
            wire [14:0] node18_w;
            wire [82:0] node19_w;
            begin : g_node_0
                wire signed [17:0] a_w;
                wire signed [17:0] b_w;
                reg signed [35:0] partial_r;
                assign a_w = {1'b0, component_w[0 +: 17]};
                assign b_w = {1'b0, distance_w[0 +: 17]};
                always @(posedge clk_i) begin
                    partial_r <= a_w * b_w;
                end
                assign node0_w = partial_r;
            end
            begin : g_node_1
                wire signed [17:0] a_w;
                wire signed [17:0] b_w;
                reg signed [35:0] partial_r;
                assign a_w = {1'b0, component_w[0 +: 17]};
                assign b_w = {1'b0, distance_w[17 +: 17]};
                always @(posedge clk_i) begin
                    partial_r <= a_w * b_w;
                end
                assign node1_w = partial_r;
            end
            begin : g_node_2
                wire signed [17:0] a_w;
                wire signed [8:0] b_w;
                reg signed [26:0] partial_r;
                assign a_w = {1'b0, component_w[0 +: 17]};
                assign b_w = distance_w[42:34];
                always @(posedge clk_i) begin
                    partial_r <= a_w * b_w;
                end
                assign node2_w = partial_r;
            end
            begin : g_node_3
                wire signed [17:0] a_w;
                wire signed [17:0] b_w;
                reg signed [35:0] partial_r;
                assign a_w = {1'b0, component_w[17 +: 17]};
                assign b_w = {1'b0, distance_w[0 +: 17]};
                always @(posedge clk_i) begin
                    partial_r <= a_w * b_w;
                end
                assign node3_w = partial_r;
            end
            begin : g_node_4
                wire signed [17:0] a_w;
                wire signed [17:0] b_w;
                reg signed [35:0] partial_r;
                assign a_w = {1'b0, component_w[17 +: 17]};
                assign b_w = {1'b0, distance_w[17 +: 17]};
                always @(posedge clk_i) begin
                    partial_r <= a_w * b_w;
                end
                assign node4_w = partial_r;
            end
            begin : g_node_5
                wire signed [17:0] a_w;
                wire signed [8:0] b_w;
                reg signed [26:0] partial_r;
                assign a_w = {1'b0, component_w[17 +: 17]};
                assign b_w = distance_w[42:34];
                always @(posedge clk_i) begin
                    partial_r <= a_w * b_w;
                end
                assign node5_w = partial_r;
            end
            begin : g_node_6
                wire signed [5:0] a_w;
                wire signed [17:0] b_w;
                reg signed [23:0] partial_r;
                assign a_w = component_w[39:34];
                assign b_w = {1'b0, distance_w[0 +: 17]};
                always @(posedge clk_i) begin
                    partial_r <= a_w * b_w;
                end
                assign node6_w = partial_r;
            end
            begin : g_node_7
                wire signed [5:0] a_w;
                wire signed [17:0] b_w;
                reg signed [23:0] partial_r;
                assign a_w = component_w[39:34];
                assign b_w = {1'b0, distance_w[17 +: 17]};
                always @(posedge clk_i) begin
                    partial_r <= a_w * b_w;
                end
                assign node7_w = partial_r;
            end
            begin : g_node_8
                wire signed [5:0] a_w;
                wire signed [8:0] b_w;
                reg signed [14:0] partial_r;
                assign a_w = component_w[39:34];
                assign b_w = distance_w[42:34];
                always @(posedge clk_i) begin
                    partial_r <= a_w * b_w;
                end
                assign node8_w = partial_r;
            end
            begin : g_node_9
                wire [53:0] a_w;
                wire [53:0] b_w;
                assign a_w =
                    {{18{node0_w[35]}}, node0_w};
                assign b_w =
                    {{1{node1_w[35]}}, node1_w, 17'b0};
                reg [35:0] low_r;
                reg [18:0] high_r;
                always @(posedge clk_i) begin
                    low_r <= {1'b0, a_w[34:0]} + {1'b0, b_w[34:0]};
                    high_r <= a_w[53:35] + b_w[53:35] + {18'b0, low_r[35]};
                end
                assign node9_w = {high_r, low_r[34:0]};
            end
            begin : g_node_10
                wire [44:0] a_w;
                wire [44:0] b_w;
                assign a_w =
                    {{1{node2_w[26]}}, node2_w, 17'b0};
                assign b_w =
                    {{9{node3_w[35]}}, node3_w};
                reg [35:0] low_r;
                reg [9:0] high_r;
                always @(posedge clk_i) begin
                    low_r <= {1'b0, a_w[34:0]} + {1'b0, b_w[34:0]};
                    high_r <= a_w[44:35] + b_w[44:35] + {9'b0, low_r[35]};
                end
                assign node10_w = {high_r, low_r[34:0]};
            end
            begin : g_node_11
                wire [44:0] a_w;
                wire [44:0] b_w;
                assign a_w =
                    {{9{node4_w[35]}}, node4_w};
                assign b_w =
                    {{1{node5_w[26]}}, node5_w, 17'b0};
                reg [35:0] low_r;
                reg [9:0] high_r;
                always @(posedge clk_i) begin
                    low_r <= {1'b0, a_w[34:0]} + {1'b0, b_w[34:0]};
                    high_r <= a_w[44:35] + b_w[44:35] + {9'b0, low_r[35]};
                end
                assign node11_w = {high_r, low_r[34:0]};
            end
            begin : g_node_12
                wire [41:0] a_w;
                wire [41:0] b_w;
                assign a_w =
                    {{18{node6_w[23]}}, node6_w};
                assign b_w =
                    {{1{node7_w[23]}}, node7_w, 17'b0};
                reg [35:0] low_r;
                reg [6:0] high_r;
                always @(posedge clk_i) begin
                    low_r <= {1'b0, a_w[34:0]} + {1'b0, b_w[34:0]};
                    high_r <= a_w[41:35] + b_w[41:35] + {6'b0, low_r[35]};
                end
                assign node12_w = {high_r, low_r[34:0]};
            end
            begin : g_node_13
                assign node13_w = node8_w;
            end
            begin : g_node_14
                wire [62:0] a_w;
                wire [62:0] b_w;
                assign a_w =
                    {{9{node9_w[53]}}, node9_w};
                assign b_w =
                    {{1{node10_w[44]}}, node10_w, 17'b0};
                reg [35:0] low_r;
                reg [27:0] high_r;
                always @(posedge clk_i) begin
                    low_r <= {1'b0, a_w[34:0]} + {1'b0, b_w[34:0]};
                    high_r <= a_w[62:35] + b_w[62:35] + {27'b0, low_r[35]};
                end
                assign node14_w = {high_r, low_r[34:0]};
            end
            begin : g_node_15
                wire [45:0] a_w;
                wire [45:0] b_w;
                assign a_w =
                    {{1{node11_w[44]}}, node11_w};
                assign b_w =
                    {{4{node12_w[41]}}, node12_w};
                reg [35:0] low_r;
                reg [10:0] high_r;
                always @(posedge clk_i) begin
                    low_r <= {1'b0, a_w[34:0]} + {1'b0, b_w[34:0]};
                    high_r <= a_w[45:35] + b_w[45:35] + {10'b0, low_r[35]};
                end
                assign node15_w = {high_r, low_r[34:0]};
            end
            begin : g_node_16
                assign node16_w = node13_w;
            end
            begin : g_node_17
                wire [80:0] a_w;
                wire [80:0] b_w;
                assign a_w =
                    {{18{node14_w[62]}}, node14_w};
                assign b_w =
                    {{1{node15_w[45]}}, node15_w, 34'b0};
                reg [35:0] low_r;
                reg [35:0] middle_r;
                reg [10:0] top_r;
                always @(posedge clk_i) begin
                    low_r <= {1'b0, a_w[34:0]} + {1'b0, b_w[34:0]};
                    middle_r <= {1'b0, a_w[69:35]} +
                        {1'b0, b_w[69:35]} + {35'b0, low_r[35]};
                    top_r <= a_w[80:70] + b_w[80:70] +
                        {10'b0, middle_r[35]};
                end
                assign node17_w = {top_r, middle_r[34:0], low_r[34:0]};
            end
            begin : g_node_18
                assign node18_w = node16_w;
            end
            begin : g_node_19
                wire [82:0] a_w;
                wire [82:0] b_w;
                assign a_w =
                    {{2{node17_w[80]}}, node17_w};
                assign b_w =
                    {node18_w, 68'b0};
                reg [35:0] low_r;
                reg [35:0] middle_r;
                reg [12:0] top_r;
                always @(posedge clk_i) begin
                    low_r <= {1'b0, a_w[34:0]} + {1'b0, b_w[34:0]};
                    middle_r <= {1'b0, a_w[69:35]} +
                        {1'b0, b_w[69:35]} + {35'b0, low_r[35]};
                    top_r <= a_w[82:70] + b_w[82:70] +
                        {12'b0, middle_r[35]};
                end
                assign node19_w = {top_r, middle_r[34:0], low_r[34:0]};
            end
            assign product_result_w[product_g*83 +: 83] = node19_w;
        end
    endgenerate
    wire [83:0] previous_product_ext_w;
    wire [83:0] current_product_ext_w;
    wire [34:0] numerator_a0_w;
    wire [34:0] numerator_b0_w;
    reg [35:0] numerator_part0_r;
    wire [34:0] numerator_low0_w;
    wire [34:0] numerator_a1_w;
    reg [34:0] numerator_a1_w_d4_r;
    wire [34:0] numerator_b1_w;
    reg [34:0] numerator_b1_w_d4_r;
    reg [35:0] numerator_part1_r;
    wire [34:0] numerator_low1_w;
    wire [13:0] numerator_a2_w;
    reg [13:0] numerator_a2_w_d4_r;
    reg [13:0] numerator_a2_w_d5_r;
    wire [13:0] numerator_b2_w;
    reg [13:0] numerator_b2_w_d4_r;
    reg [13:0] numerator_b2_w_d5_r;
    reg [14:0] unused_numerator_part2_r;
    wire [13:0] numerator_low2_w;
    wire [83:0] numerator_w;
    reg [34:0] numerator_low1_w_d6_r;
    reg [34:0] numerator_low0_w_d5_r;
    reg [34:0] numerator_low0_w_d6_r;
    reg [0:0] numerator_abs_sign_r;
    reg [83:0] numerator_abs_invert_r;
    wire [83:0] numerator_abs_carry_w;
    wire [34:0] numerator_abs_a0_w;
    wire [34:0] numerator_abs_b0_w;
    reg [35:0] numerator_abs_part0_r;
    wire [34:0] numerator_abs_low0_w;
    wire [34:0] numerator_abs_a1_w;
    wire [34:0] numerator_abs_b1_w;
    reg [34:0] numerator_abs_a1_w_d8_r;
    reg [34:0] numerator_abs_b1_w_d8_r;
    reg [35:0] numerator_abs_part1_r;
    wire [34:0] numerator_abs_low1_w;
    wire [13:0] numerator_abs_a2_w;
    wire [13:0] numerator_abs_b2_w;
    reg [13:0] numerator_abs_a2_w_d8_r;
    reg [13:0] numerator_abs_a2_w_d9_r;
    reg [13:0] numerator_abs_b2_w_d8_r;
    reg [13:0] numerator_abs_b2_w_d9_r;
    reg [14:0] unused_numerator_abs_part2_r;
    wire [13:0] numerator_abs_low2_w;
    wire [83:0] numerator_abs_w;
    reg [34:0] numerator_abs_low1_w_d10_r;
    reg [34:0] numerator_abs_low0_w_d9_r;
    reg [34:0] numerator_abs_low0_w_d10_r;
    wire [43:0] current_distance_ext_w;
    wire [43:0] previous_distance_ext_w;
    wire [34:0] denominator_a0_w;
    wire [34:0] denominator_b0_w;
    reg [35:0] denominator_part0_r;
    wire [34:0] denominator_low0_w;
    wire [8:0] denominator_a1_w;
    reg [8:0] denominator_a1_w_d1_r;
    wire [8:0] denominator_b1_w;
    reg [8:0] denominator_b1_w_d1_r;
    reg [9:0] unused_denominator_part1_r;
    wire [8:0] denominator_low1_w;
    wire [43:0] denominator_w;
    reg [34:0] denominator_low0_w_d2_r;
    reg [0:0] denominator_abs_sign_r;
    reg [43:0] denominator_abs_invert_r;
    wire [43:0] denominator_abs_carry_w;
    wire [34:0] denominator_abs_a0_w;
    wire [34:0] denominator_abs_b0_w;
    reg [35:0] denominator_abs_part0_r;
    wire [34:0] denominator_abs_low0_w;
    wire [8:0] denominator_abs_a1_w;
    wire [8:0] denominator_abs_b1_w;
    reg [8:0] denominator_abs_a1_w_d4_r;
    reg [8:0] denominator_abs_b1_w_d4_r;
    reg [9:0] unused_denominator_abs_part1_r;
    wire [8:0] denominator_abs_low1_w;
    wire [43:0] denominator_abs_w;
    reg [34:0] denominator_abs_low0_w_d5_r;
    reg [0:0] numerator_abs_sign_d8_r;
    reg [0:0] numerator_abs_sign_d9_r;
    reg [0:0] numerator_abs_sign_d10_r;
    reg [0:0] denominator_abs_sign_d4_r;
    reg [0:0] denominator_abs_sign_d5_r;
    reg [0:0] denominator_abs_sign_d6_r;
    reg [0:0] denominator_abs_sign_d7_r;
    reg [0:0] denominator_abs_sign_d8_r;
    reg [0:0] denominator_abs_sign_d9_r;
    reg [0:0] denominator_abs_sign_d10_r;
    wire [45:0] division_shift_w;
    wire [45:0] division_divisor_w;
    wire [34:0] division_trial_a0_w;
    wire [34:0] division_trial_b0_w;
    reg [35:0] division_trial_part0_r;
    wire [34:0] division_trial_low0_w;
    wire [10:0] division_trial_a1_w;
    reg [10:0] division_trial_a1_w_d0_r;
    wire [10:0] division_trial_b1_w;
    reg [10:0] division_trial_b1_w_d0_r;
    reg [11:0] unused_division_trial_part1_r;
    wire [10:0] division_trial_low1_w;
    wire [45:0] division_trial_w;
    reg [34:0] division_trial_low0_w_d1_r;
    reg [45:0] round_remainder_r;
    reg [45:0] round_divisor_r;
    wire [46:0] round_rem47_w;
    wire [46:0] round_div47_w;
    wire [34:0] round_compare_a0_w;
    wire [34:0] round_compare_b0_w;
    reg [35:0] round_compare_part0_r;
    wire [34:0] round_compare_low0_w;
    wire [11:0] round_compare_a1_w;
    reg [11:0] round_compare_a1_w_d1_r;
    wire [11:0] round_compare_b1_w;
    reg [11:0] round_compare_b1_w_d1_r;
    reg [12:0] unused_round_compare_part1_r;
    wire [11:0] round_compare_low1_w;
    wire [46:0] unused_round_compare_w;
    reg [34:0] round_compare_low0_w_d2_r;
    wire [39:0] round_carry_w;
    wire [39:0] round_quotient_w;
    reg [39:0] round_quotient_w_d1_r;
    reg [39:0] round_quotient_w_d2_r;
    wire [34:0] intersection_round_a0_w;
    wire [34:0] intersection_round_b0_w;
    reg [35:0] intersection_round_part0_r;
    wire [34:0] intersection_round_low0_w;
    wire [4:0] intersection_round_a1_w;
    wire [4:0] intersection_round_b1_w;
    reg [4:0] intersection_round_a1_w_d3_r;
    reg [4:0] intersection_round_b1_w_d3_r;
    reg [5:0] unused_intersection_round_part1_r;
    wire [4:0] intersection_round_low1_w;
    wire [39:0] intersection_round_w;
    reg [34:0] intersection_round_low0_w_d4_r;
    wire [0:0] intersection_negative_w;
    reg [0:0] intersection_negative_w_d1_r;
    reg [0:0] intersection_negative_w_d2_r;
    reg [0:0] intersection_negative_w_d3_r;
    reg [0:0] intersection_negative_w_d4_r;
    reg [39:0] intersection_signed_invert_r;
    reg [0:0] intersection_negative_w_d5_r;
    wire [39:0] intersection_signed_carry_w;
    wire [34:0] intersection_signed_a0_w;
    wire [34:0] intersection_signed_b0_w;
    reg [35:0] intersection_signed_part0_r;
    wire [34:0] intersection_signed_low0_w;
    wire [4:0] intersection_signed_a1_w;
    wire [4:0] intersection_signed_b1_w;
    reg [4:0] intersection_signed_a1_w_d6_r;
    reg [4:0] intersection_signed_b1_w_d6_r;
    reg [5:0] unused_intersection_signed_part1_r;
    wire [4:0] intersection_signed_low1_w;
    wire [39:0] intersection_signed_w;
    reg [34:0] intersection_signed_low0_w_d7_r;

    assign inside_0_x_w = {{3{triangle_saved_w[39]}}, triangle_saved_w[0 +: 40]};
    assign inside_0_y_w = {{3{triangle_saved_w[79]}}, triangle_saved_w[40 +: 40]};
    assign inside_0_w_w = {{3{triangle_saved_w[159]}}, triangle_saved_w[120 +: 40]};
    assign inside_w4_0_w = inside_0_w_w << 2;
    assign inside_near0_w = 43'd4096;
    assign inside_0_near_a0_w = inside_0_w_w[0 +: 35];
    assign inside_0_near_b0_w = inside_near0_w[0 +: 35];
    assign inside_0_near_low0_w = inside_0_near_part0_r[34:0];
    assign inside_0_near_a1_w = inside_0_w_w[35 +: 8];
    assign inside_0_near_b1_w = inside_near0_w[35 +: 8];
    assign inside_0_near_low1_w = unused_inside_0_near_part1_r[7:0];
    assign unused_inside_0_near_w = {inside_0_near_low1_w, inside_0_near_low0_w_d2_r};
    assign inside_0_xplus_a0_w = inside_w4_0_w[0 +: 35];
    assign inside_0_xplus_b0_w = inside_0_x_w[0 +: 35];
    assign inside_0_xplus_low0_w = inside_0_xplus_part0_r[34:0];
    assign inside_0_xplus_a1_w = inside_w4_0_w[35 +: 8];
    assign inside_0_xplus_b1_w = inside_0_x_w[35 +: 8];
    assign inside_0_xplus_low1_w = unused_inside_0_xplus_part1_r[7:0];
    assign unused_inside_0_xplus_w = {inside_0_xplus_low1_w, inside_0_xplus_low0_w_d2_r};
    assign inside_0_xminus_a0_w = inside_w4_0_w[0 +: 35];
    assign inside_0_xminus_b0_w = inside_0_x_w[0 +: 35];
    assign inside_0_xminus_low0_w = inside_0_xminus_part0_r[34:0];
    assign inside_0_xminus_a1_w = inside_w4_0_w[35 +: 8];
    assign inside_0_xminus_b1_w = inside_0_x_w[35 +: 8];
    assign inside_0_xminus_low1_w = unused_inside_0_xminus_part1_r[7:0];
    assign unused_inside_0_xminus_w = {inside_0_xminus_low1_w, inside_0_xminus_low0_w_d2_r};
    assign inside_0_yplus_a0_w = inside_w4_0_w[0 +: 35];
    assign inside_0_yplus_b0_w = inside_0_y_w[0 +: 35];
    assign inside_0_yplus_low0_w = inside_0_yplus_part0_r[34:0];
    assign inside_0_yplus_a1_w = inside_w4_0_w[35 +: 8];
    assign inside_0_yplus_b1_w = inside_0_y_w[35 +: 8];
    assign inside_0_yplus_low1_w = unused_inside_0_yplus_part1_r[7:0];
    assign unused_inside_0_yplus_w = {inside_0_yplus_low1_w, inside_0_yplus_low0_w_d2_r};
    assign inside_0_yminus_a0_w = inside_w4_0_w[0 +: 35];
    assign inside_0_yminus_b0_w = inside_0_y_w[0 +: 35];
    assign inside_0_yminus_low0_w = inside_0_yminus_part0_r[34:0];
    assign inside_0_yminus_a1_w = inside_w4_0_w[35 +: 8];
    assign inside_0_yminus_b1_w = inside_0_y_w[35 +: 8];
    assign inside_0_yminus_low1_w = unused_inside_0_yminus_part1_r[7:0];
    assign unused_inside_0_yminus_w = {inside_0_yminus_low1_w, inside_0_yminus_low0_w_d2_r};
    assign outside_w[0] = unused_inside_0_near_w[42];
    assign outside_w[1] = unused_inside_0_xplus_w[42];
    assign outside_w[2] = unused_inside_0_xminus_w[42];
    assign outside_w[3] = unused_inside_0_yplus_w[42];
    assign outside_w[4] = unused_inside_0_yminus_w[42];
    assign inside_1_x_w = {{3{triangle_saved_w[303]}}, triangle_saved_w[264 +: 40]};
    assign inside_1_y_w = {{3{triangle_saved_w[343]}}, triangle_saved_w[304 +: 40]};
    assign inside_1_w_w = {{3{triangle_saved_w[423]}}, triangle_saved_w[384 +: 40]};
    assign inside_w4_1_w = inside_1_w_w << 2;
    assign inside_near1_w = 43'd4096;
    assign inside_1_near_a0_w = inside_1_w_w[0 +: 35];
    assign inside_1_near_b0_w = inside_near1_w[0 +: 35];
    assign inside_1_near_low0_w = inside_1_near_part0_r[34:0];
    assign inside_1_near_a1_w = inside_1_w_w[35 +: 8];
    assign inside_1_near_b1_w = inside_near1_w[35 +: 8];
    assign inside_1_near_low1_w = unused_inside_1_near_part1_r[7:0];
    assign unused_inside_1_near_w = {inside_1_near_low1_w, inside_1_near_low0_w_d2_r};
    assign inside_1_xplus_a0_w = inside_w4_1_w[0 +: 35];
    assign inside_1_xplus_b0_w = inside_1_x_w[0 +: 35];
    assign inside_1_xplus_low0_w = inside_1_xplus_part0_r[34:0];
    assign inside_1_xplus_a1_w = inside_w4_1_w[35 +: 8];
    assign inside_1_xplus_b1_w = inside_1_x_w[35 +: 8];
    assign inside_1_xplus_low1_w = unused_inside_1_xplus_part1_r[7:0];
    assign unused_inside_1_xplus_w = {inside_1_xplus_low1_w, inside_1_xplus_low0_w_d2_r};
    assign inside_1_xminus_a0_w = inside_w4_1_w[0 +: 35];
    assign inside_1_xminus_b0_w = inside_1_x_w[0 +: 35];
    assign inside_1_xminus_low0_w = inside_1_xminus_part0_r[34:0];
    assign inside_1_xminus_a1_w = inside_w4_1_w[35 +: 8];
    assign inside_1_xminus_b1_w = inside_1_x_w[35 +: 8];
    assign inside_1_xminus_low1_w = unused_inside_1_xminus_part1_r[7:0];
    assign unused_inside_1_xminus_w = {inside_1_xminus_low1_w, inside_1_xminus_low0_w_d2_r};
    assign inside_1_yplus_a0_w = inside_w4_1_w[0 +: 35];
    assign inside_1_yplus_b0_w = inside_1_y_w[0 +: 35];
    assign inside_1_yplus_low0_w = inside_1_yplus_part0_r[34:0];
    assign inside_1_yplus_a1_w = inside_w4_1_w[35 +: 8];
    assign inside_1_yplus_b1_w = inside_1_y_w[35 +: 8];
    assign inside_1_yplus_low1_w = unused_inside_1_yplus_part1_r[7:0];
    assign unused_inside_1_yplus_w = {inside_1_yplus_low1_w, inside_1_yplus_low0_w_d2_r};
    assign inside_1_yminus_a0_w = inside_w4_1_w[0 +: 35];
    assign inside_1_yminus_b0_w = inside_1_y_w[0 +: 35];
    assign inside_1_yminus_low0_w = inside_1_yminus_part0_r[34:0];
    assign inside_1_yminus_a1_w = inside_w4_1_w[35 +: 8];
    assign inside_1_yminus_b1_w = inside_1_y_w[35 +: 8];
    assign inside_1_yminus_low1_w = unused_inside_1_yminus_part1_r[7:0];
    assign unused_inside_1_yminus_w = {inside_1_yminus_low1_w, inside_1_yminus_low0_w_d2_r};
    assign outside_w[5] = unused_inside_1_near_w[42];
    assign outside_w[6] = unused_inside_1_xplus_w[42];
    assign outside_w[7] = unused_inside_1_xminus_w[42];
    assign outside_w[8] = unused_inside_1_yplus_w[42];
    assign outside_w[9] = unused_inside_1_yminus_w[42];
    assign inside_2_x_w = {{3{triangle_saved_w[567]}}, triangle_saved_w[528 +: 40]};
    assign inside_2_y_w = {{3{triangle_saved_w[607]}}, triangle_saved_w[568 +: 40]};
    assign inside_2_w_w = {{3{triangle_saved_w[687]}}, triangle_saved_w[648 +: 40]};
    assign inside_w4_2_w = inside_2_w_w << 2;
    assign inside_near2_w = 43'd4096;
    assign inside_2_near_a0_w = inside_2_w_w[0 +: 35];
    assign inside_2_near_b0_w = inside_near2_w[0 +: 35];
    assign inside_2_near_low0_w = inside_2_near_part0_r[34:0];
    assign inside_2_near_a1_w = inside_2_w_w[35 +: 8];
    assign inside_2_near_b1_w = inside_near2_w[35 +: 8];
    assign inside_2_near_low1_w = unused_inside_2_near_part1_r[7:0];
    assign unused_inside_2_near_w = {inside_2_near_low1_w, inside_2_near_low0_w_d2_r};
    assign inside_2_xplus_a0_w = inside_w4_2_w[0 +: 35];
    assign inside_2_xplus_b0_w = inside_2_x_w[0 +: 35];
    assign inside_2_xplus_low0_w = inside_2_xplus_part0_r[34:0];
    assign inside_2_xplus_a1_w = inside_w4_2_w[35 +: 8];
    assign inside_2_xplus_b1_w = inside_2_x_w[35 +: 8];
    assign inside_2_xplus_low1_w = unused_inside_2_xplus_part1_r[7:0];
    assign unused_inside_2_xplus_w = {inside_2_xplus_low1_w, inside_2_xplus_low0_w_d2_r};
    assign inside_2_xminus_a0_w = inside_w4_2_w[0 +: 35];
    assign inside_2_xminus_b0_w = inside_2_x_w[0 +: 35];
    assign inside_2_xminus_low0_w = inside_2_xminus_part0_r[34:0];
    assign inside_2_xminus_a1_w = inside_w4_2_w[35 +: 8];
    assign inside_2_xminus_b1_w = inside_2_x_w[35 +: 8];
    assign inside_2_xminus_low1_w = unused_inside_2_xminus_part1_r[7:0];
    assign unused_inside_2_xminus_w = {inside_2_xminus_low1_w, inside_2_xminus_low0_w_d2_r};
    assign inside_2_yplus_a0_w = inside_w4_2_w[0 +: 35];
    assign inside_2_yplus_b0_w = inside_2_y_w[0 +: 35];
    assign inside_2_yplus_low0_w = inside_2_yplus_part0_r[34:0];
    assign inside_2_yplus_a1_w = inside_w4_2_w[35 +: 8];
    assign inside_2_yplus_b1_w = inside_2_y_w[35 +: 8];
    assign inside_2_yplus_low1_w = unused_inside_2_yplus_part1_r[7:0];
    assign unused_inside_2_yplus_w = {inside_2_yplus_low1_w, inside_2_yplus_low0_w_d2_r};
    assign inside_2_yminus_a0_w = inside_w4_2_w[0 +: 35];
    assign inside_2_yminus_b0_w = inside_2_y_w[0 +: 35];
    assign inside_2_yminus_low0_w = inside_2_yminus_part0_r[34:0];
    assign inside_2_yminus_a1_w = inside_w4_2_w[35 +: 8];
    assign inside_2_yminus_b1_w = inside_2_y_w[35 +: 8];
    assign inside_2_yminus_low1_w = unused_inside_2_yminus_part1_r[7:0];
    assign unused_inside_2_yminus_w = {inside_2_yminus_low1_w, inside_2_yminus_low0_w_d2_r};
    assign outside_w[10] = unused_inside_2_near_w[42];
    assign outside_w[11] = unused_inside_2_xplus_w[42];
    assign outside_w[12] = unused_inside_2_xminus_w[42];
    assign outside_w[13] = unused_inside_2_yplus_w[42];
    assign outside_w[14] = unused_inside_2_yminus_w[42];
    assign edge_add0_a0_w = edge_left0_r[0 +: 35];
    assign edge_add0_b0_w = edge_right0_r[0 +: 35];
    assign edge_add0_low0_w = edge_add0_part0_r[34:0];
    assign edge_add0_a1_w = edge_left0_r[35 +: 8];
    assign edge_add0_b1_w = edge_right0_r[35 +: 8];
    assign edge_add0_low1_w = unused_edge_add0_part1_r[7:0];
    assign edge_add0_w = {edge_add0_low1_w, edge_add0_low0_w_d2_r};
    assign edge_sub0_a0_w = edge_left0_r[0 +: 35];
    assign edge_sub0_b0_w = edge_right0_r[0 +: 35];
    assign edge_sub0_low0_w = edge_sub0_part0_r[34:0];
    assign edge_sub0_a1_w = edge_left0_r[35 +: 8];
    assign edge_sub0_b1_w = edge_right0_r[35 +: 8];
    assign edge_sub0_low1_w = unused_edge_sub0_part1_r[7:0];
    assign edge_sub0_w = {edge_sub0_low1_w, edge_sub0_low0_w_d2_r};
    assign edge_distance_w[0] = edge_subtract0_r_d2_r ? edge_sub0_w : edge_add0_w;
    assign edge_add1_a0_w = edge_left1_r[0 +: 35];
    assign edge_add1_b0_w = edge_right1_r[0 +: 35];
    assign edge_add1_low0_w = edge_add1_part0_r[34:0];
    assign edge_add1_a1_w = edge_left1_r[35 +: 8];
    assign edge_add1_b1_w = edge_right1_r[35 +: 8];
    assign edge_add1_low1_w = unused_edge_add1_part1_r[7:0];
    assign edge_add1_w = {edge_add1_low1_w, edge_add1_low0_w_d2_r};
    assign edge_sub1_a0_w = edge_left1_r[0 +: 35];
    assign edge_sub1_b0_w = edge_right1_r[0 +: 35];
    assign edge_sub1_low0_w = edge_sub1_part0_r[34:0];
    assign edge_sub1_a1_w = edge_left1_r[35 +: 8];
    assign edge_sub1_b1_w = edge_right1_r[35 +: 8];
    assign edge_sub1_low1_w = unused_edge_sub1_part1_r[7:0];
    assign edge_sub1_w = {edge_sub1_low1_w, edge_sub1_low0_w_d2_r};
    assign edge_distance_w[1] = edge_subtract1_r_d2_r ? edge_sub1_w : edge_add1_w;
    assign previous_product_ext_w = {previous_product_w[82], previous_product_w};
    assign current_product_ext_w = {current_product_w[82], current_product_w};
    assign numerator_a0_w = previous_product_ext_w[0 +: 35];
    assign numerator_b0_w = current_product_ext_w[0 +: 35];
    assign numerator_low0_w = numerator_part0_r[34:0];
    assign numerator_a1_w = previous_product_ext_w[35 +: 35];
    assign numerator_b1_w = current_product_ext_w[35 +: 35];
    assign numerator_low1_w = numerator_part1_r[34:0];
    assign numerator_a2_w = previous_product_ext_w[70 +: 14];
    assign numerator_b2_w = current_product_ext_w[70 +: 14];
    assign numerator_low2_w = unused_numerator_part2_r[13:0];
    assign numerator_w = {numerator_low2_w, numerator_low1_w_d6_r, numerator_low0_w_d6_r};
    assign numerator_abs_carry_w = {83'b0, numerator_abs_sign_r};
    assign numerator_abs_a0_w = numerator_abs_invert_r[0 +: 35];
    assign numerator_abs_b0_w = numerator_abs_carry_w[0 +: 35];
    assign numerator_abs_low0_w = numerator_abs_part0_r[34:0];
    assign numerator_abs_a1_w = numerator_abs_invert_r[35 +: 35];
    assign numerator_abs_b1_w = numerator_abs_carry_w[35 +: 35];
    assign numerator_abs_low1_w = numerator_abs_part1_r[34:0];
    assign numerator_abs_a2_w = numerator_abs_invert_r[70 +: 14];
    assign numerator_abs_b2_w = numerator_abs_carry_w[70 +: 14];
    assign numerator_abs_low2_w = unused_numerator_abs_part2_r[13:0];
    assign numerator_abs_w = {numerator_abs_low2_w, numerator_abs_low1_w_d10_r,
            numerator_abs_low0_w_d10_r};
    assign current_distance_ext_w = {current_distance_r[42], current_distance_r};
    assign previous_distance_ext_w = {previous_distance_input_r[42], previous_distance_input_r};
    assign denominator_a0_w = current_distance_ext_w[0 +: 35];
    assign denominator_b0_w = previous_distance_ext_w[0 +: 35];
    assign denominator_low0_w = denominator_part0_r[34:0];
    assign denominator_a1_w = current_distance_ext_w[35 +: 9];
    assign denominator_b1_w = previous_distance_ext_w[35 +: 9];
    assign denominator_low1_w = unused_denominator_part1_r[8:0];
    assign denominator_w = {denominator_low1_w, denominator_low0_w_d2_r};
    assign denominator_abs_carry_w = {43'b0, denominator_abs_sign_r};
    assign denominator_abs_a0_w = denominator_abs_invert_r[0 +: 35];
    assign denominator_abs_b0_w = denominator_abs_carry_w[0 +: 35];
    assign denominator_abs_low0_w = denominator_abs_part0_r[34:0];
    assign denominator_abs_a1_w = denominator_abs_invert_r[35 +: 9];
    assign denominator_abs_b1_w = denominator_abs_carry_w[35 +: 9];
    assign denominator_abs_low1_w = unused_denominator_abs_part1_r[8:0];
    assign denominator_abs_w = {denominator_abs_low1_w, denominator_abs_low0_w_d5_r};
    assign numerator_magnitude_w = numerator_abs_w;
    assign denominator_magnitude_w = denominator_abs_w;
    assign quotient_negative_w = numerator_abs_sign_d10_r ^ denominator_abs_sign_d10_r;
    assign division_shift_w = {1'b0, remainder_shift_w};
    assign division_divisor_w = {2'b0, divisor_r};
    assign division_trial_a0_w = division_shift_w[0 +: 35];
    assign division_trial_b0_w = division_divisor_w[0 +: 35];
    assign division_trial_low0_w = division_trial_part0_r[34:0];
    assign division_trial_a1_w = division_shift_w[35 +: 11];
    assign division_trial_b1_w = division_divisor_w[35 +: 11];
    assign division_trial_low1_w = unused_division_trial_part1_r[10:0];
    assign division_trial_w = {division_trial_low1_w, division_trial_low0_w_d1_r};
    assign remainder_next_w = division_trial_w[45] ? remainder_shift_w : division_trial_w[44:0];
    assign quotient_next_w = {quotient_r[82:0], !division_trial_w[45]};
    assign round_rem47_w = {1'b0, round_remainder_r};
    assign round_div47_w = {1'b0, round_divisor_r};
    assign round_compare_a0_w = round_rem47_w[0 +: 35];
    assign round_compare_b0_w = round_div47_w[0 +: 35];
    assign round_compare_low0_w = round_compare_part0_r[34:0];
    assign round_compare_a1_w = round_rem47_w[35 +: 12];
    assign round_compare_b1_w = round_div47_w[35 +: 12];
    assign round_compare_low1_w = unused_round_compare_part1_r[11:0];
    assign unused_round_compare_w = {round_compare_low1_w, round_compare_low0_w_d2_r};
    assign round_carry_w = {39'b0, !unused_round_compare_w[46]};
    assign round_quotient_w = quotient_r[39:0];
    assign intersection_round_a0_w = round_quotient_w_d2_r[0 +: 35];
    assign intersection_round_b0_w = round_carry_w[0 +: 35];
    assign intersection_round_low0_w = intersection_round_part0_r[34:0];
    assign intersection_round_a1_w = round_quotient_w_d2_r[35 +: 5];
    assign intersection_round_b1_w = round_carry_w[35 +: 5];
    assign intersection_round_low1_w = unused_intersection_round_part1_r[4:0];
    assign intersection_round_w = {intersection_round_low1_w, intersection_round_low0_w_d4_r};
    assign intersection_negative_w = negative_r;
    assign intersection_signed_carry_w = {39'b0, intersection_negative_w_d5_r};
    assign intersection_signed_a0_w = intersection_signed_invert_r[0 +: 35];
    assign intersection_signed_b0_w = intersection_signed_carry_w[0 +: 35];
    assign intersection_signed_low0_w = intersection_signed_part0_r[34:0];
    assign intersection_signed_a1_w = intersection_signed_invert_r[35 +: 5];
    assign intersection_signed_b1_w = intersection_signed_carry_w[35 +: 5];
    assign intersection_signed_low1_w = unused_intersection_signed_part1_r[4:0];
    assign intersection_signed_w = {intersection_signed_low1_w, intersection_signed_low0_w_d7_r};
    assign intersection_value_w = intersection_signed_w;

    reg [3:0] state_next_w;
    always @(*) begin
        state_next_w = state_r;
        case (state_r)
            S_IDLE: if (source_accept_w) state_next_w = S_CHECK;
            S_CHECK: if (wait_r == 0)
                state_next_w = all_inside_w ? S_IDLE : S_BEGIN;
            S_BEGIN: if (wait_r == 0) state_next_w = S_EDGE;
            S_EDGE: if (wait_r == 0) begin
                if (previous_distance_r[42] != current_distance_w[42])
                    state_next_w = S_MULTIPLY;
                else state_next_w = current_distance_w[42] ? S_ADVANCE : S_APPEND_CURRENT;
            end
            S_MULTIPLY: if (wait_r == 0) state_next_w = S_DIVIDE_LOAD;
            S_DIVIDE_LOAD: state_next_w = S_DIVIDE;
            S_DIVIDE: if (wait_r == 0 && divide_count_r == 1) state_next_w = S_ROUND;
            S_ROUND: if (wait_r == 0)
                state_next_w = component_r == 8 ? S_APPEND_INTERSECTION : S_MULTIPLY;
            S_APPEND_INTERSECTION:
                state_next_w = current_distance_w[42] ? S_ADVANCE : S_APPEND_CURRENT;
            S_APPEND_CURRENT: state_next_w = S_ADVANCE;
            S_ADVANCE: begin
                if ({1'b0, vertex_index_r} + 4'd1 == input_count_r)
                    state_next_w = result_count_r < 3 ? S_IDLE :
                        plane_r == 4 ? S_OUTPUT : S_BEGIN;
                else state_next_w = S_EDGE;
            end
            S_OUTPUT: if (count_r != 2) state_next_w = S_IDLE;
            default: state_next_w = state_r;
        endcase
    end

    genvar vertex_g;
    genvar distance_g;
    genvar field_g;
    genvar slot_g;
    generate
        for (vertex_g = 0; vertex_g < 3; vertex_g = vertex_g + 1) begin : g_capture
            genvar capture_field;
            for (capture_field = 0; capture_field < 9; capture_field = capture_field + 1) begin
            : g_field
                localparam WIDTH = capture_field < 4 ? 40 : (capture_field < 6 ? 16 : 24);
                localparam OFFSET = capture_field < 4 ? capture_field*40 :
                    capture_field < 6 ? 160+(capture_field-4)*16 : 192+(capture_field-6)*24;
                reg [WIDTH-1:0] data_r;
                assign triangle_saved_w[vertex_g*264+OFFSET +: WIDTH] = data_r;
                always @(posedge clk_i) begin
                    if (source_accept_w)
                        data_r <= triangle_data_i[vertex_g*264+OFFSET +: WIDTH];
                end
            end
        end
        for (distance_g = 0; distance_g < 2; distance_g = distance_g + 1) begin : g_distance
            wire signed [42:0] x_w;
            wire signed [42:0] y_w;
            wire signed [42:0] w_w;
            reg signed [42:0] left_w;
            reg signed [42:0] right_w;
            reg subtract_w;
            assign x_w = distance_g == 0
                ? {{3{last_position_w[0][39]}}, last_position_w[0]}
                : {{3{current_position_w[0][39]}}, current_position_w[0]};
            assign y_w = distance_g == 0
                ? {{3{last_position_w[1][39]}}, last_position_w[1]}
                : {{3{current_position_w[1][39]}}, current_position_w[1]};
            assign w_w = distance_g == 0
                ? {{3{last_position_w[2][39]}}, last_position_w[2]}
                : {{3{current_position_w[2][39]}}, current_position_w[2]};
            always @(*) begin
                left_w = 43'sd0;
                right_w = 43'sd0;
                subtract_w = 1'b0;
                case (plane_r)
                    3'd0: begin left_w = w_w; right_w = 43'sd4096; subtract_w = 1'b1; end
                    3'd1: begin left_w = w_w <<< 2; right_w = x_w; end
                    3'd2: begin left_w = w_w <<< 2; right_w = x_w; subtract_w = 1'b1; end
                    3'd3: begin left_w = w_w <<< 2; right_w = y_w; end
                    3'd4: begin left_w = w_w <<< 2; right_w = y_w; subtract_w = 1'b1; end
                    default: begin end
                endcase
            end
            assign distance_left_w[distance_g*43 +: 43] = left_w;
            assign distance_right_w[distance_g*43 +: 43] = right_w;
            assign distance_subtract_w[distance_g] = subtract_w;
        end
        // Nine independent fields: 16 workset registers and two output slots each.
        // Each workset register has one full-field write point, including initial load.
        for (field_g = 0; field_g < 9; field_g = field_g + 1) begin : g_field
            (* keep = 1 *) reg [3:0] region_state_r /* synthesis syn_preserve=1 */;
            (* keep = 1 *) reg region_bank_r /* synthesis syn_preserve=1 */;
            (* keep = 1 *) reg [2:0] region_vertex_r /* synthesis syn_preserve=1 */;
            (* keep = 1 *) reg [3:0] region_input_count_r /* synthesis syn_preserve=1 */;
            wire [2:0] region_last_index_w;
            assign region_last_index_w = region_input_count_r[2:0] - 3'd1;
            wire region_push_w;
            assign region_push_w = !stop_i && ((region_state_r == S_CHECK && wait_r == 0 &&
            all_inside_w)
                || (region_state_r == S_OUTPUT && count_r != 2));
            (* keep = 1 *) always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    region_state_r <= S_IDLE;
                    region_bank_r <= 0;
                    region_vertex_r <= 0;
                    region_input_count_r <= 0;
                end else if (stop_i) region_state_r <= S_IDLE;
                else begin
                    region_state_r <= state_next_w;
                    if (accept_w && !all_inside_w) begin
                        region_bank_r <= 0;
                        region_input_count_r <= 3;
                    end
                    if (region_state_r == S_BEGIN && wait_r == 0) region_vertex_r <= 0;
                    if (region_state_r == S_ADVANCE) begin
                        if ({1'b0, region_vertex_r} + 4'd1 == region_input_count_r) begin
                            if (result_count_r >= 3) region_input_count_r <= result_count_r;
                        end else region_vertex_r <= region_vertex_r + 3'd1;
                    end
                    if (region_state_r == S_ADVANCE &&
                        {1'b0, vertex_index_r} + 4'd1 == input_count_r && result_count_r >= 3)
                        region_bank_r <= !region_bank_r;
                end
            end
            localparam WIDTH = field_g < 4 ? 40 : (field_g < 6 ? 16 : 24);
            localparam OFFSET = field_g < 4 ? field_g * 40
                : (field_g < 6 ? 160 + (field_g - 4) * 16 : 192 + (field_g - 6) * 24);
            wire [WIDTH*16-1:0] workset_w;
            reg [WIDTH-1:0] current_w;
            reg [WIDTH-1:0] last_w;
            reg [WIDTH-1:0] previous_r;
            reg [WIDTH-1:0] intersection_r;
            wire [3:0] current_select_w;
            wire [3:0] last_select_w;
            wire [WIDTH*4-1:0] current_quarter_w;
            wire [WIDTH*4-1:0] last_quarter_w;
            assign current_select_w = {region_bank_r, region_vertex_r};
            assign last_select_w = {region_bank_r, region_last_index_w};
            genvar quarter;
            for (quarter = 0; quarter < 4; quarter = quarter + 1) begin : g_select
                wire [WIDTH*4-1:0] values_w;
                assign values_w = workset_w[quarter*WIDTH*4 +: WIDTH*4];
                assign current_quarter_w[quarter*WIDTH +: WIDTH] = current_select_w[1] ?
                    (current_select_w[0] ? values_w[3*WIDTH +: WIDTH] :
                    values_w[2*WIDTH +: WIDTH]) :
                    (current_select_w[0] ? values_w[WIDTH +: WIDTH] : values_w[0 +: WIDTH]);
                assign last_quarter_w[quarter*WIDTH +: WIDTH] = last_select_w[1] ?
                    (last_select_w[0] ? values_w[3*WIDTH +: WIDTH] :
                    values_w[2*WIDTH +: WIDTH]) :
                    (last_select_w[0] ? values_w[WIDTH +: WIDTH] : values_w[0 +: WIDTH]);
            end
            always @(*) begin
                current_w = current_select_w[3] ?
                    (current_select_w[2] ? current_quarter_w[3*WIDTH +: WIDTH] :
                    current_quarter_w[2*WIDTH +: WIDTH]) :
                    (current_select_w[2] ? current_quarter_w[WIDTH +: WIDTH] :
                    current_quarter_w[0 +: WIDTH]);
                last_w = last_select_w[3] ?
                    (last_select_w[2] ? last_quarter_w[3*WIDTH +: WIDTH] :
                    last_quarter_w[2*WIDTH +: WIDTH]) :
                    (last_select_w[2] ? last_quarter_w[WIDTH +: WIDTH] :
                    last_quarter_w[0 +: WIDTH]);
            end
            if (field_g < 4) begin : g_signed
                assign previous_component_w[field_g] = previous_r;
                assign current_component_w[field_g] = current_w;
            end else begin : g_unsigned
                assign previous_component_w[field_g] = {{(40-WIDTH){1'b0}}, previous_r};
                assign current_component_w[field_g] = {{(40-WIDTH){1'b0}}, current_w};
            end
            if (field_g == 0 || field_g == 1 || field_g == 3) begin : g_position
                localparam AXIS = field_g == 3 ? 2 : field_g;
                assign current_position_w[AXIS] = current_w;
                assign last_position_w[AXIS] = last_w;
            end
            always @(posedge clk_i) begin
                if (region_state_r == S_BEGIN) previous_r <= last_w;
                if (region_state_r == S_ADVANCE) previous_r <= current_w;
                if (region_state_r == S_ROUND && wait_r == 0 && component_r == field_g)
                    intersection_r <= intersection_value_w[WIDTH-1:0];
            end
            for (slot_g = 0; slot_g < 16; slot_g = slot_g + 1) begin : g_workset
                localparam [2:0] INDEX = slot_g[2:0];
                reg [WIDTH-1:0] data_r;
                wire load_w;
                wire append_w;
                wire [WIDTH-1:0] load_data_w;
                wire [WIDTH-1:0] append_data_w;
                assign workset_w[WIDTH*slot_g +: WIDTH] = data_r;
                assign load_w = slot_g < 3 && accept_w && !all_inside_w;
                if (slot_g < 3) begin : g_input
                    assign load_data_w = triangle_saved_w[slot_g * 264 + OFFSET +: WIDTH];
                end else begin : g_no_input
                    assign load_data_w = {WIDTH{1'b0}};
                end
                assign append_w = region_bank_r == (slot_g < 8) && result_count_r[2:0] == INDEX
                    && (region_state_r == S_APPEND_INTERSECTION || region_state_r ==
            S_APPEND_CURRENT);
                assign append_data_w = region_state_r == S_APPEND_INTERSECTION
                    ? intersection_r : current_w;
                always @(posedge clk_i) begin
                    if (load_w || append_w) data_r <= load_w ? load_data_w : append_data_w;
                end
            end
            for (slot_g = 0; slot_g < 8; slot_g = slot_g + 1) begin : g_output
                reg [WIDTH-1:0] data_r [0:1];
                wire [WIDTH-1:0] bypass_w;
                wire [WIDTH-1:0] push_wide_w;
                if (slot_g < 3) begin : g_bypass
                    assign bypass_w = triangle_saved_w[slot_g * 264 + OFFSET +: WIDTH];
                end else begin : g_padding
                    assign bypass_w = {WIDTH{1'b0}};
                end
                assign push_wide_w = region_state_r == S_CHECK ? bypass_w
                    : (region_bank_r ? workset_w[WIDTH*(8 + slot_g) +: WIDTH]
                        : workset_w[WIDTH*slot_g +: WIDTH]);
                assign polygon_data_o[slot_g * 264 + OFFSET +: WIDTH] = data_r[read_r];
                always @(posedge clk_i) begin
                    if (region_push_w) data_r[write_r] <= push_wide_w;
                end
            end
        end
    endgenerate

    // Two 9:1 field selectors feed the two s40 x s43 multipliers in S_MULTIPLY.
    always @(*) begin
        previous_selected_w = 40'sd0;
        current_selected_w = 40'sd0;
        case (component_r)
            4'd0: begin
                previous_selected_w = previous_component_w[0];
                current_selected_w = current_component_w[0];
            end
            4'd1: begin
                previous_selected_w = previous_component_w[1];
                current_selected_w = current_component_w[1];
            end
            4'd2: begin
                previous_selected_w = previous_component_w[2];
                current_selected_w = current_component_w[2];
            end
            4'd3: begin
                previous_selected_w = previous_component_w[3];
                current_selected_w = current_component_w[3];
            end
            4'd4: begin
                previous_selected_w = previous_component_w[4];
                current_selected_w = current_component_w[4];
            end
            4'd5: begin
                previous_selected_w = previous_component_w[5];
                current_selected_w = current_component_w[5];
            end
            4'd6: begin
                previous_selected_w = previous_component_w[6];
                current_selected_w = current_component_w[6];
            end
            4'd7: begin
                previous_selected_w = previous_component_w[7];
                current_selected_w = current_component_w[7];
            end
            4'd8: begin
                previous_selected_w = previous_component_w[8];
                current_selected_w = current_component_w[8];
            end
            default: begin end
        endcase
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            wait_r <= 0;
            count_r <= 2'd0;
            read_r <= 1'b0;
            write_r <= 1'b0;
            bank_r <= 1'b0;
            plane_r <= 3'd0;
            input_count_r <= 4'd0;
            result_count_r <= 4'd0;
            vertex_index_r <= 3'd0;
            component_r <= 4'd0;
            divide_count_r <= 7'd0;
        end else if (stop_i) begin
            state_r <= S_IDLE;
            wait_r <= 0;
            count_r <= 2'd0;
            read_r <= 1'b0;
            write_r <= 1'b0;
        end else begin
            state_r <= state_next_w;
            if (push_w) write_r <= !write_r;
            if (pop_w) read_r <= !read_r;
            begin
                case ({push_w, pop_w})
                    2'b10: count_r <= count_r + 2'd1;
                    2'b01: count_r <= count_r - 2'd1;
                    default: count_r <= count_r;
                endcase
            end
            if (wait_r != 0) wait_r <= wait_r - 1'b1;
            case (state_r)
                S_IDLE: begin
                    if (source_accept_w) begin
                        begin end
                        wait_r <= 2;
                    end
                end
                S_CHECK: begin
                    if (wait_r == 0 && all_inside_w) begin end
                    if (accept_w && !all_inside_w) begin
                        wait_r <= 3;
                        bank_r <= 1'b0;
                        plane_r <= 3'd0;
                        input_count_r <= 4'd3;
                        begin end
                    end
                end
                S_BEGIN: if (wait_r == 0) begin
                    wait_r <= 3;
                    vertex_index_r <= 3'd0;
                    result_count_r <= 4'd0;
                    begin end
                end
                S_EDGE: if (wait_r == 0) begin
                    if (previous_distance_r[42] != current_distance_w[42]) begin
                        component_r <= 4'd0;
                        begin end
                        wait_r <= 22;
                    end else begin
                        begin end
                    end
                end
                S_MULTIPLY: if (wait_r == 0) begin end
                S_DIVIDE_LOAD: begin
                    divide_count_r <= 7'd84;
                    wait_r <= 2;
                    begin end
                end
                S_DIVIDE: if (wait_r == 0) begin
                    wait_r <= 2;
                    divide_count_r <= divide_count_r - 7'd1;
                    if (divide_count_r == 1) begin
                        begin end
                        wait_r <= 8;
                    end
                end
                S_ROUND: if (wait_r == 0) begin
                    if (component_r == 8) begin end
                    else begin
                        component_r <= component_r + 4'd1;
                        begin end
                        wait_r <= 22;
                    end
                end
                S_APPEND_INTERSECTION: begin
                    result_count_r <= result_count_r + 4'd1;
                    begin end
                end
                S_APPEND_CURRENT: begin
                    result_count_r <= result_count_r + 4'd1;
                    begin end
                end
                S_ADVANCE: begin
                    if ({1'b0, vertex_index_r} + 4'd1 == input_count_r) begin
                        if (result_count_r < 3) begin end
                        else begin
                            bank_r <= !bank_r;
                            input_count_r <= result_count_r;
                            plane_r <= plane_r + 3'd1;
                            begin end
                            wait_r <= 3;
                        end
                    end else begin
                        vertex_index_r <= vertex_index_r + 3'd1;
                        begin end
                        wait_r <= 3;
                    end
                end
                S_OUTPUT: if (count_r != 2) begin end
                default: begin end
            endcase
        end
    end

    always @(posedge clk_i) begin
        if (state_r == S_BEGIN) previous_distance_r <= last_distance_w;
        if (state_r == S_DIVIDE_LOAD) begin
            quotient_r <= numerator_magnitude_w;
            remainder_r <= 45'd0;
            divisor_r <= denominator_magnitude_w;
            negative_r <= quotient_negative_w;
        end
        if (state_r == S_DIVIDE && wait_r == 0) begin
            quotient_r <= quotient_next_w;
            remainder_r <= remainder_next_w;
        end
        if (state_r == S_ADVANCE) begin
            previous_distance_r <= current_distance_w;
        end
        if (push_w) begin
            output_count_r[write_r] <= state_r == S_CHECK ? 4'd3 : input_count_r;
        end
    end
    always @(posedge clk_i) begin
    inside_0_near_part0_r <= {1'b0, inside_0_near_a0_w} + {1'b0, ~inside_0_near_b0_w} + 36'd1;
    inside_0_near_a1_w_d1_r <= inside_0_near_a1_w;
    inside_0_near_b1_w_d1_r <= inside_0_near_b1_w;
    unused_inside_0_near_part1_r <= {1'b0, inside_0_near_a1_w_d1_r} + {1'b0,
            ~inside_0_near_b1_w_d1_r} + {8'b0, inside_0_near_part0_r[35]};
    inside_0_near_low0_w_d2_r <= inside_0_near_low0_w;
    inside_0_xplus_part0_r <= {1'b0, inside_0_xplus_a0_w} + {1'b0, inside_0_xplus_b0_w};
    inside_0_xplus_a1_w_d1_r <= inside_0_xplus_a1_w;
    inside_0_xplus_b1_w_d1_r <= inside_0_xplus_b1_w;
    unused_inside_0_xplus_part1_r <= {1'b0, inside_0_xplus_a1_w_d1_r} + {1'b0,
            inside_0_xplus_b1_w_d1_r} + {8'b0, inside_0_xplus_part0_r[35]};
    inside_0_xplus_low0_w_d2_r <= inside_0_xplus_low0_w;
    inside_0_xminus_part0_r <= {1'b0, inside_0_xminus_a0_w} + {1'b0, ~inside_0_xminus_b0_w} + 36'd1;
    inside_0_xminus_a1_w_d1_r <= inside_0_xminus_a1_w;
    inside_0_xminus_b1_w_d1_r <= inside_0_xminus_b1_w;
    unused_inside_0_xminus_part1_r <= {1'b0, inside_0_xminus_a1_w_d1_r} + {1'b0,
            ~inside_0_xminus_b1_w_d1_r} + {8'b0, inside_0_xminus_part0_r[35]};
    inside_0_xminus_low0_w_d2_r <= inside_0_xminus_low0_w;
    inside_0_yplus_part0_r <= {1'b0, inside_0_yplus_a0_w} + {1'b0, inside_0_yplus_b0_w};
    inside_0_yplus_a1_w_d1_r <= inside_0_yplus_a1_w;
    inside_0_yplus_b1_w_d1_r <= inside_0_yplus_b1_w;
    unused_inside_0_yplus_part1_r <= {1'b0, inside_0_yplus_a1_w_d1_r} + {1'b0,
            inside_0_yplus_b1_w_d1_r} + {8'b0, inside_0_yplus_part0_r[35]};
    inside_0_yplus_low0_w_d2_r <= inside_0_yplus_low0_w;
    inside_0_yminus_part0_r <= {1'b0, inside_0_yminus_a0_w} + {1'b0, ~inside_0_yminus_b0_w} + 36'd1;
    inside_0_yminus_a1_w_d1_r <= inside_0_yminus_a1_w;
    inside_0_yminus_b1_w_d1_r <= inside_0_yminus_b1_w;
    unused_inside_0_yminus_part1_r <= {1'b0, inside_0_yminus_a1_w_d1_r} + {1'b0,
            ~inside_0_yminus_b1_w_d1_r} + {8'b0, inside_0_yminus_part0_r[35]};
    inside_0_yminus_low0_w_d2_r <= inside_0_yminus_low0_w;
    inside_1_near_part0_r <= {1'b0, inside_1_near_a0_w} + {1'b0, ~inside_1_near_b0_w} + 36'd1;
    inside_1_near_a1_w_d1_r <= inside_1_near_a1_w;
    inside_1_near_b1_w_d1_r <= inside_1_near_b1_w;
    unused_inside_1_near_part1_r <= {1'b0, inside_1_near_a1_w_d1_r} + {1'b0,
            ~inside_1_near_b1_w_d1_r} + {8'b0, inside_1_near_part0_r[35]};
    inside_1_near_low0_w_d2_r <= inside_1_near_low0_w;
    inside_1_xplus_part0_r <= {1'b0, inside_1_xplus_a0_w} + {1'b0, inside_1_xplus_b0_w};
    inside_1_xplus_a1_w_d1_r <= inside_1_xplus_a1_w;
    inside_1_xplus_b1_w_d1_r <= inside_1_xplus_b1_w;
    unused_inside_1_xplus_part1_r <= {1'b0, inside_1_xplus_a1_w_d1_r} + {1'b0,
            inside_1_xplus_b1_w_d1_r} + {8'b0, inside_1_xplus_part0_r[35]};
    inside_1_xplus_low0_w_d2_r <= inside_1_xplus_low0_w;
    inside_1_xminus_part0_r <= {1'b0, inside_1_xminus_a0_w} + {1'b0, ~inside_1_xminus_b0_w} + 36'd1;
    inside_1_xminus_a1_w_d1_r <= inside_1_xminus_a1_w;
    inside_1_xminus_b1_w_d1_r <= inside_1_xminus_b1_w;
    unused_inside_1_xminus_part1_r <= {1'b0, inside_1_xminus_a1_w_d1_r} + {1'b0,
            ~inside_1_xminus_b1_w_d1_r} + {8'b0, inside_1_xminus_part0_r[35]};
    inside_1_xminus_low0_w_d2_r <= inside_1_xminus_low0_w;
    inside_1_yplus_part0_r <= {1'b0, inside_1_yplus_a0_w} + {1'b0, inside_1_yplus_b0_w};
    inside_1_yplus_a1_w_d1_r <= inside_1_yplus_a1_w;
    inside_1_yplus_b1_w_d1_r <= inside_1_yplus_b1_w;
    unused_inside_1_yplus_part1_r <= {1'b0, inside_1_yplus_a1_w_d1_r} + {1'b0,
            inside_1_yplus_b1_w_d1_r} + {8'b0, inside_1_yplus_part0_r[35]};
    inside_1_yplus_low0_w_d2_r <= inside_1_yplus_low0_w;
    inside_1_yminus_part0_r <= {1'b0, inside_1_yminus_a0_w} + {1'b0, ~inside_1_yminus_b0_w} + 36'd1;
    inside_1_yminus_a1_w_d1_r <= inside_1_yminus_a1_w;
    inside_1_yminus_b1_w_d1_r <= inside_1_yminus_b1_w;
    unused_inside_1_yminus_part1_r <= {1'b0, inside_1_yminus_a1_w_d1_r} + {1'b0,
            ~inside_1_yminus_b1_w_d1_r} + {8'b0, inside_1_yminus_part0_r[35]};
    inside_1_yminus_low0_w_d2_r <= inside_1_yminus_low0_w;
    inside_2_near_part0_r <= {1'b0, inside_2_near_a0_w} + {1'b0, ~inside_2_near_b0_w} + 36'd1;
    inside_2_near_a1_w_d1_r <= inside_2_near_a1_w;
    inside_2_near_b1_w_d1_r <= inside_2_near_b1_w;
    unused_inside_2_near_part1_r <= {1'b0, inside_2_near_a1_w_d1_r} + {1'b0,
            ~inside_2_near_b1_w_d1_r} + {8'b0, inside_2_near_part0_r[35]};
    inside_2_near_low0_w_d2_r <= inside_2_near_low0_w;
    inside_2_xplus_part0_r <= {1'b0, inside_2_xplus_a0_w} + {1'b0, inside_2_xplus_b0_w};
    inside_2_xplus_a1_w_d1_r <= inside_2_xplus_a1_w;
    inside_2_xplus_b1_w_d1_r <= inside_2_xplus_b1_w;
    unused_inside_2_xplus_part1_r <= {1'b0, inside_2_xplus_a1_w_d1_r} + {1'b0,
            inside_2_xplus_b1_w_d1_r} + {8'b0, inside_2_xplus_part0_r[35]};
    inside_2_xplus_low0_w_d2_r <= inside_2_xplus_low0_w;
    inside_2_xminus_part0_r <= {1'b0, inside_2_xminus_a0_w} + {1'b0, ~inside_2_xminus_b0_w} + 36'd1;
    inside_2_xminus_a1_w_d1_r <= inside_2_xminus_a1_w;
    inside_2_xminus_b1_w_d1_r <= inside_2_xminus_b1_w;
    unused_inside_2_xminus_part1_r <= {1'b0, inside_2_xminus_a1_w_d1_r} + {1'b0,
            ~inside_2_xminus_b1_w_d1_r} + {8'b0, inside_2_xminus_part0_r[35]};
    inside_2_xminus_low0_w_d2_r <= inside_2_xminus_low0_w;
    inside_2_yplus_part0_r <= {1'b0, inside_2_yplus_a0_w} + {1'b0, inside_2_yplus_b0_w};
    inside_2_yplus_a1_w_d1_r <= inside_2_yplus_a1_w;
    inside_2_yplus_b1_w_d1_r <= inside_2_yplus_b1_w;
    unused_inside_2_yplus_part1_r <= {1'b0, inside_2_yplus_a1_w_d1_r} + {1'b0,
            inside_2_yplus_b1_w_d1_r} + {8'b0, inside_2_yplus_part0_r[35]};
    inside_2_yplus_low0_w_d2_r <= inside_2_yplus_low0_w;
    inside_2_yminus_part0_r <= {1'b0, inside_2_yminus_a0_w} + {1'b0, ~inside_2_yminus_b0_w} + 36'd1;
    inside_2_yminus_a1_w_d1_r <= inside_2_yminus_a1_w;
    inside_2_yminus_b1_w_d1_r <= inside_2_yminus_b1_w;
    unused_inside_2_yminus_part1_r <= {1'b0, inside_2_yminus_a1_w_d1_r} + {1'b0,
            ~inside_2_yminus_b1_w_d1_r} + {8'b0, inside_2_yminus_part0_r[35]};
    inside_2_yminus_low0_w_d2_r <= inside_2_yminus_low0_w;
    edge_left0_r <= distance_left_w[0 +: 43];
    edge_right0_r <= distance_right_w[0 +: 43];
    edge_subtract0_r <= distance_subtract_w[0];
    edge_add0_part0_r <= {1'b0, edge_add0_a0_w} + {1'b0, edge_add0_b0_w};
    edge_add0_a1_w_d1_r <= edge_add0_a1_w;
    edge_add0_b1_w_d1_r <= edge_add0_b1_w;
    unused_edge_add0_part1_r <= {1'b0, edge_add0_a1_w_d1_r} + {1'b0, edge_add0_b1_w_d1_r} + {8'b0,
            edge_add0_part0_r[35]};
    edge_add0_low0_w_d2_r <= edge_add0_low0_w;
    edge_sub0_part0_r <= {1'b0, edge_sub0_a0_w} + {1'b0, ~edge_sub0_b0_w} + 36'd1;
    edge_sub0_a1_w_d1_r <= edge_sub0_a1_w;
    edge_sub0_b1_w_d1_r <= edge_sub0_b1_w;
    unused_edge_sub0_part1_r <= {1'b0, edge_sub0_a1_w_d1_r} + {1'b0, ~edge_sub0_b1_w_d1_r} + {8'b0,
            edge_sub0_part0_r[35]};
    edge_sub0_low0_w_d2_r <= edge_sub0_low0_w;
    edge_subtract0_r_d1_r <= edge_subtract0_r;
    edge_subtract0_r_d2_r <= edge_subtract0_r_d1_r;
    edge_left1_r <= distance_left_w[43 +: 43];
    edge_right1_r <= distance_right_w[43 +: 43];
    edge_subtract1_r <= distance_subtract_w[1];
    edge_add1_part0_r <= {1'b0, edge_add1_a0_w} + {1'b0, edge_add1_b0_w};
    edge_add1_a1_w_d1_r <= edge_add1_a1_w;
    edge_add1_b1_w_d1_r <= edge_add1_b1_w;
    unused_edge_add1_part1_r <= {1'b0, edge_add1_a1_w_d1_r} + {1'b0, edge_add1_b1_w_d1_r} + {8'b0,
            edge_add1_part0_r[35]};
    edge_add1_low0_w_d2_r <= edge_add1_low0_w;
    edge_sub1_part0_r <= {1'b0, edge_sub1_a0_w} + {1'b0, ~edge_sub1_b0_w} + 36'd1;
    edge_sub1_a1_w_d1_r <= edge_sub1_a1_w;
    edge_sub1_b1_w_d1_r <= edge_sub1_b1_w;
    unused_edge_sub1_part1_r <= {1'b0, edge_sub1_a1_w_d1_r} + {1'b0, ~edge_sub1_b1_w_d1_r} + {8'b0,
            edge_sub1_part0_r[35]};
    edge_sub1_low0_w_d2_r <= edge_sub1_low0_w;
    edge_subtract1_r_d1_r <= edge_subtract1_r;
    edge_subtract1_r_d2_r <= edge_subtract1_r_d1_r;
    previous_component_r <= previous_selected_w;
    current_component_r <= current_selected_w;
    current_distance_r <= current_distance_w;
    previous_distance_input_r <= previous_distance_r;
    numerator_part0_r <= {1'b0, numerator_a0_w} + {1'b0, ~numerator_b0_w} + 36'd1;
    numerator_a1_w_d4_r <= numerator_a1_w;
    numerator_b1_w_d4_r <= numerator_b1_w;
    numerator_part1_r <= {1'b0, numerator_a1_w_d4_r} + {1'b0, ~numerator_b1_w_d4_r} + {35'b0,
            numerator_part0_r[35]};
    numerator_a2_w_d4_r <= numerator_a2_w;
    numerator_a2_w_d5_r <= numerator_a2_w_d4_r;
    numerator_b2_w_d4_r <= numerator_b2_w;
    numerator_b2_w_d5_r <= numerator_b2_w_d4_r;
    unused_numerator_part2_r <= {1'b0, numerator_a2_w_d5_r} + {1'b0, ~numerator_b2_w_d5_r} + {14'b0,
            numerator_part1_r[35]};
    numerator_low1_w_d6_r <= numerator_low1_w;
    numerator_low0_w_d5_r <= numerator_low0_w;
    numerator_low0_w_d6_r <= numerator_low0_w_d5_r;
    numerator_abs_sign_r <= numerator_w[83];
    numerator_abs_invert_r <= numerator_w[83] ? ~numerator_w : numerator_w;
    numerator_abs_part0_r <= {1'b0, numerator_abs_a0_w} + {1'b0, numerator_abs_b0_w};
    numerator_abs_a1_w_d8_r <= numerator_abs_a1_w;
    numerator_abs_b1_w_d8_r <= numerator_abs_b1_w;
    numerator_abs_part1_r <= {1'b0, numerator_abs_a1_w_d8_r} + {1'b0, numerator_abs_b1_w_d8_r} +
            {35'b0, numerator_abs_part0_r[35]};
    numerator_abs_a2_w_d8_r <= numerator_abs_a2_w;
    numerator_abs_a2_w_d9_r <= numerator_abs_a2_w_d8_r;
    numerator_abs_b2_w_d8_r <= numerator_abs_b2_w;
    numerator_abs_b2_w_d9_r <= numerator_abs_b2_w_d8_r;
    unused_numerator_abs_part2_r <= {1'b0, numerator_abs_a2_w_d9_r} + {1'b0,
        numerator_abs_b2_w_d9_r}
            + {14'b0, numerator_abs_part1_r[35]};
    numerator_abs_low1_w_d10_r <= numerator_abs_low1_w;
    numerator_abs_low0_w_d9_r <= numerator_abs_low0_w;
    numerator_abs_low0_w_d10_r <= numerator_abs_low0_w_d9_r;
    denominator_part0_r <= {1'b0, denominator_a0_w} + {1'b0, ~denominator_b0_w} + 36'd1;
    denominator_a1_w_d1_r <= denominator_a1_w;
    denominator_b1_w_d1_r <= denominator_b1_w;
    unused_denominator_part1_r <= {1'b0, denominator_a1_w_d1_r} + {1'b0, ~denominator_b1_w_d1_r} +
            {9'b0, denominator_part0_r[35]};
    denominator_low0_w_d2_r <= denominator_low0_w;
    denominator_abs_sign_r <= denominator_w[43];
    denominator_abs_invert_r <= denominator_w[43] ? ~denominator_w : denominator_w;
    denominator_abs_part0_r <= {1'b0, denominator_abs_a0_w} + {1'b0, denominator_abs_b0_w};
    denominator_abs_a1_w_d4_r <= denominator_abs_a1_w;
    denominator_abs_b1_w_d4_r <= denominator_abs_b1_w;
    unused_denominator_abs_part1_r <= {1'b0, denominator_abs_a1_w_d4_r} + {1'b0,
            denominator_abs_b1_w_d4_r} + {9'b0, denominator_abs_part0_r[35]};
    denominator_abs_low0_w_d5_r <= denominator_abs_low0_w;
    numerator_abs_sign_d8_r <= numerator_abs_sign_r;
    numerator_abs_sign_d9_r <= numerator_abs_sign_d8_r;
    numerator_abs_sign_d10_r <= numerator_abs_sign_d9_r;
    denominator_abs_sign_d4_r <= denominator_abs_sign_r;
    denominator_abs_sign_d5_r <= denominator_abs_sign_d4_r;
    denominator_abs_sign_d6_r <= denominator_abs_sign_d5_r;
    denominator_abs_sign_d7_r <= denominator_abs_sign_d6_r;
    denominator_abs_sign_d8_r <= denominator_abs_sign_d7_r;
    denominator_abs_sign_d9_r <= denominator_abs_sign_d8_r;
    denominator_abs_sign_d10_r <= denominator_abs_sign_d9_r;
    division_trial_part0_r <= {1'b0, division_trial_a0_w} + {1'b0, ~division_trial_b0_w} + 36'd1;
    division_trial_a1_w_d0_r <= division_trial_a1_w;
    division_trial_b1_w_d0_r <= division_trial_b1_w;
    unused_division_trial_part1_r <= {1'b0, division_trial_a1_w_d0_r} + {1'b0,
            ~division_trial_b1_w_d0_r} + {11'b0, division_trial_part0_r[35]};
    division_trial_low0_w_d1_r <= division_trial_low0_w;
    round_remainder_r <= {remainder_r, 1'b0};
    round_divisor_r <= {2'b0, divisor_r};
    round_compare_part0_r <= {1'b0, round_compare_a0_w} + {1'b0, ~round_compare_b0_w} + 36'd1;
    round_compare_a1_w_d1_r <= round_compare_a1_w;
    round_compare_b1_w_d1_r <= round_compare_b1_w;
    unused_round_compare_part1_r <= {1'b0, round_compare_a1_w_d1_r} + {1'b0,
            ~round_compare_b1_w_d1_r} + {12'b0, round_compare_part0_r[35]};
    round_compare_low0_w_d2_r <= round_compare_low0_w;
    round_quotient_w_d1_r <= round_quotient_w;
    round_quotient_w_d2_r <= round_quotient_w_d1_r;
    intersection_round_part0_r <= {1'b0, intersection_round_a0_w} + {1'b0, intersection_round_b0_w};
    intersection_round_a1_w_d3_r <= intersection_round_a1_w;
    intersection_round_b1_w_d3_r <= intersection_round_b1_w;
    unused_intersection_round_part1_r <= {1'b0, intersection_round_a1_w_d3_r} + {1'b0,
            intersection_round_b1_w_d3_r} + {5'b0, intersection_round_part0_r[35]};
    intersection_round_low0_w_d4_r <= intersection_round_low0_w;
    intersection_negative_w_d1_r <= intersection_negative_w;
    intersection_negative_w_d2_r <= intersection_negative_w_d1_r;
    intersection_negative_w_d3_r <= intersection_negative_w_d2_r;
    intersection_negative_w_d4_r <= intersection_negative_w_d3_r;
    intersection_signed_invert_r <= intersection_negative_w_d4_r ? ~intersection_round_w :
            intersection_round_w;
    intersection_negative_w_d5_r <= intersection_negative_w_d4_r;
    intersection_signed_part0_r <= {1'b0, intersection_signed_a0_w} + {1'b0,
            intersection_signed_b0_w};
    intersection_signed_a1_w_d6_r <= intersection_signed_a1_w;
    intersection_signed_b1_w_d6_r <= intersection_signed_b1_w;
    unused_intersection_signed_part1_r <= {1'b0, intersection_signed_a1_w_d6_r} + {1'b0,
            intersection_signed_b1_w_d6_r} + {5'b0, intersection_signed_part0_r[35]};
    intersection_signed_low0_w_d7_r <= intersection_signed_low0_w;
    end
endmodule
