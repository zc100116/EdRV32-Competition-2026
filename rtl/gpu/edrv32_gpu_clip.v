// File: edrv32_gpu_clip.v
// Spec: gpu-spec 2.4; GPU microarchitecture 4.3.
// Description: Five ordered Sutherland-Hodgman passes with two eight-vertex worksets.
//              Crossing edges use the symmetric exact quotient; all-inside triangles bypass worksets.
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
    reg [263:0] workset_r [0:1][0:7];
    reg bank_r;
    reg [2:0] plane_r;
    reg [3:0] input_count_r;
    reg [3:0] result_count_r;
    reg [2:0] vertex_index_r;
    reg [3:0] component_r;
    reg [263:0] previous_r;
    wire [263:0] current_w;
    reg [263:0] intersection_r;
    reg signed [42:0] previous_distance_r;
    wire signed [42:0] current_distance_w;
    wire signed [42:0] last_distance_w;
    wire signed [43:0] denominator_w;
    reg signed [82:0] product_r [0:1];
    wire signed [83:0] numerator_w;
    reg [43:0] divisor_r;
    reg negative_r;
    reg [83:0] quotient_r;
    reg [44:0] remainder_r;
    reg [6:0] divide_count_r;
    wire [44:0] remainder_shift_w;
    wire [44:0] remainder_next_w;
    wire [83:0] quotient_next_w;
    wire [84:0] unused_rounded_w;
    wire [39:0] intersection_value_w;
    reg all_inside_w;
    integer test_plane_w;
    integer test_vertex_w;
    wire accept_w;
    wire push_w;
    wire pop_w;
    reg [1:0] count_r;
    reg read_r;
    reg write_r;
    reg [2111:0] output_r [0:1];
    reg [3:0] output_count_r [0:1];
    integer copy_r;

    function signed [42:0] distance;
        input [263:0] unused_vertex_i;
        input [2:0] plane_i;
        reg signed [42:0] x;
        reg signed [42:0] y;
        reg signed [42:0] w;
        begin
            x = {{3{unused_vertex_i[39]}}, unused_vertex_i[39:0]};
            y = {{3{unused_vertex_i[79]}}, unused_vertex_i[79:40]};
            w = {{3{unused_vertex_i[159]}}, unused_vertex_i[159:120]};
            case (plane_i)
                3'd0: distance = w - 43'sd4096;
                3'd1: distance = (w <<< 2) + x;
                3'd2: distance = (w <<< 2) - x;
                3'd3: distance = (w <<< 2) + y;
                3'd4: distance = (w <<< 2) - y;
                default: distance = 43'sd0;
            endcase
        end
    endfunction

    function signed [39:0] component;
        input [263:0] vertex_i;
        input [3:0] component_i;
        begin
            component = 40'sd0;
            case (component_i)
                0, 1, 2, 3: component = vertex_i[component_i * 40 +: 40];
                4, 5: component = {24'd0, vertex_i[160 + ({28'd0, component_i} - 4) * 16 +: 16]};
                6, 7, 8: component = {16'd0, vertex_i[192 + ({28'd0, component_i} - 6) * 24 +: 24]};
                default: component = 40'sd0;
            endcase
        end
    endfunction

    assign triangle_ready_o = state_r == S_IDLE && count_r != 2 && !stop_i;
    assign accept_w = triangle_valid_i && triangle_ready_o;
    assign push_w = !stop_i && ((accept_w && all_inside_w)
        || (state_r == S_OUTPUT && count_r != 2));
    assign polygon_valid_o = count_r != 0;
    assign polygon_data_o = output_r[read_r];
    assign polygon_count_o = output_count_r[read_r];
    assign pop_w = polygon_valid_o && polygon_ready_i;
    assign idle_o = state_r == S_IDLE && count_r == 0;
    assign current_w = workset_r[bank_r][vertex_index_r];
    assign last_distance_w = distance(
        workset_r[bank_r][input_count_r[2:0] - 3'd1], plane_r);
    assign current_distance_w = distance(current_w, plane_r);
    assign denominator_w = $signed({current_distance_w[42], current_distance_w})
        - $signed({previous_distance_r[42], previous_distance_r});
    assign numerator_w = $signed({product_r[0][82], product_r[0]})
        - $signed({product_r[1][82], product_r[1]});
    assign remainder_shift_w = {remainder_r[43:0], quotient_r[83]};
    assign remainder_next_w = remainder_shift_w >= {1'b0, divisor_r}
        ? remainder_shift_w - {1'b0, divisor_r} : remainder_shift_w;
    assign quotient_next_w = {quotient_r[82:0], remainder_shift_w >= {1'b0, divisor_r}};
    assign unused_rounded_w = {1'b0, quotient_r}
        + {84'd0, ({remainder_r, 1'b0} >= {2'd0, divisor_r})};
    assign intersection_value_w = negative_r
        ? -unused_rounded_w[39:0] : unused_rounded_w[39:0];

    always @(*) begin
        all_inside_w = 1'b1;
        for (test_plane_w = 0; test_plane_w < 5; test_plane_w = test_plane_w + 1) begin
            for (test_vertex_w = 0; test_vertex_w < 3; test_vertex_w = test_vertex_w + 1) begin
                if (distance(triangle_data_i[test_vertex_w * 264 +: 264],
                    test_plane_w[2:0]) < 0) all_inside_w = 1'b0;
            end
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
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
            count_r <= 2'd0;
            read_r <= 1'b0;
            write_r <= 1'b0;
        end else begin
            if (push_w) write_r <= !write_r;
            if (pop_w) read_r <= !read_r;
            begin
                case ({push_w, pop_w})
                    2'b10: count_r <= count_r + 2'd1;
                    2'b01: count_r <= count_r - 2'd1;
                    default: count_r <= count_r;
                endcase
            end
            case (state_r)
                S_IDLE: begin
                    if (accept_w && !all_inside_w) begin
                        bank_r <= 1'b0;
                        plane_r <= 3'd0;
                        input_count_r <= 4'd3;
                        state_r <= S_BEGIN;
                    end
                end
                S_BEGIN: begin
                    vertex_index_r <= 3'd0;
                    result_count_r <= 4'd0;
                    state_r <= S_EDGE;
                end
                S_EDGE: begin
                    if (previous_distance_r[42] != current_distance_w[42]) begin
                        component_r <= 4'd0;
                        state_r <= S_MULTIPLY;
                    end else begin
                        state_r <= current_distance_w[42] ? S_ADVANCE : S_APPEND_CURRENT;
                    end
                end
                S_MULTIPLY: state_r <= S_DIVIDE_LOAD;
                S_DIVIDE_LOAD: begin
                    divide_count_r <= 7'd84;
                    state_r <= S_DIVIDE;
                end
                S_DIVIDE: begin
                    divide_count_r <= divide_count_r - 7'd1;
                    if (divide_count_r == 1) state_r <= S_ROUND;
                end
                S_ROUND: begin
                    if (component_r == 8) state_r <= S_APPEND_INTERSECTION;
                    else begin
                        component_r <= component_r + 4'd1;
                        state_r <= S_MULTIPLY;
                    end
                end
                S_APPEND_INTERSECTION: begin
                    result_count_r <= result_count_r + 4'd1;
                    state_r <= current_distance_w[42] ? S_ADVANCE : S_APPEND_CURRENT;
                end
                S_APPEND_CURRENT: begin
                    result_count_r <= result_count_r + 4'd1;
                    state_r <= S_ADVANCE;
                end
                S_ADVANCE: begin
                    if ({1'b0, vertex_index_r} + 4'd1 == input_count_r) begin
                        if (result_count_r < 3) state_r <= S_IDLE;
                        else begin
                            bank_r <= !bank_r;
                            input_count_r <= result_count_r;
                            plane_r <= plane_r + 3'd1;
                            state_r <= plane_r == 4 ? S_OUTPUT : S_BEGIN;
                        end
                    end else begin
                        vertex_index_r <= vertex_index_r + 3'd1;
                        state_r <= S_EDGE;
                    end
                end
                S_OUTPUT: if (count_r != 2) state_r <= S_IDLE;
                default: state_r <= state_r;
            endcase
        end
    end

    always @(posedge clk_i) begin
        if (accept_w && !all_inside_w) begin
            for (copy_r = 0; copy_r < 3; copy_r = copy_r + 1) begin
                workset_r[0][copy_r] <= triangle_data_i[copy_r * 264 +: 264];
            end
        end
        if (state_r == S_BEGIN) begin
            previous_r <= workset_r[bank_r][input_count_r[2:0] - 3'd1];
            previous_distance_r <= last_distance_w;
        end
        if (state_r == S_MULTIPLY) begin
            product_r[0] <= component(previous_r, component_r) * current_distance_w;
            product_r[1] <= component(current_w, component_r) * previous_distance_r;
        end
        if (state_r == S_DIVIDE_LOAD) begin
            quotient_r <= numerator_w[83] ? -numerator_w : numerator_w;
            remainder_r <= 45'd0;
            divisor_r <= denominator_w[43] ? -denominator_w : denominator_w;
            negative_r <= numerator_w[83] ^ denominator_w[43];
        end
        if (state_r == S_DIVIDE) begin
            quotient_r <= quotient_next_w;
            remainder_r <= remainder_next_w;
        end
        if (state_r == S_ROUND) begin
            case (component_r)
                0, 1, 2, 3: intersection_r[component_r * 40 +: 40] <= intersection_value_w;
                4, 5: intersection_r[160 + ({28'd0, component_r} - 4) * 16 +: 16]
                    <= intersection_value_w[15:0];
                6, 7, 8: intersection_r[192 + ({28'd0, component_r} - 6) * 24 +: 24]
                    <= intersection_value_w[23:0];
                default: begin end
            endcase
        end
        if (state_r == S_APPEND_INTERSECTION)
            workset_r[!bank_r][result_count_r[2:0]] <= intersection_r;
        if (state_r == S_APPEND_CURRENT)
            workset_r[!bank_r][result_count_r[2:0]] <= current_w;
        if (state_r == S_ADVANCE) begin
            previous_r <= current_w;
            previous_distance_r <= current_distance_w;
        end
        if (push_w) begin
            output_count_r[write_r] <= state_r == S_IDLE ? 4'd3 : input_count_r;
            if (state_r == S_IDLE) output_r[write_r] <= {1320'd0, triangle_data_i};
            else begin
                for (copy_r = 0; copy_r < 8; copy_r = copy_r + 1) begin
                    output_r[write_r][copy_r * 264 +: 264] <= workset_r[bank_r][copy_r];
                end
            end
        end
    end
endmodule
