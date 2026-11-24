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
    reg bank_r;
    reg [2:0] plane_r;
    reg [3:0] input_count_r;
    reg [3:0] result_count_r;
    reg [2:0] vertex_index_r;
    reg [3:0] component_r;
    reg signed [42:0] previous_distance_r;
    wire signed [42:0] current_distance_w;
    wire signed [42:0] last_distance_w;
    wire signed [43:0] denominator_w;
    reg signed [82:0] previous_product_r;
    reg signed [82:0] current_product_r;
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
    wire all_inside_w;
    wire [14:0] outside_w;
    wire [2:0] last_index_w;
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
    assign accept_w = triangle_valid_i && triangle_ready_o;
    assign push_w = !stop_i && ((accept_w && all_inside_w)
        || (state_r == S_OUTPUT && count_r != 2));
    assign polygon_valid_o = count_r != 0;
    assign polygon_count_o = output_count_r[read_r];
    assign pop_w = polygon_valid_o && polygon_ready_i;
    assign idle_o = state_r == S_IDLE && count_r == 0;
    assign last_index_w = input_count_r[2:0] - 3'd1;
    assign last_distance_w = edge_distance_w[0];
    assign current_distance_w = edge_distance_w[1];
    assign all_inside_w = ~|outside_w;
    assign denominator_w = $signed({current_distance_w[42], current_distance_w})
        - $signed({previous_distance_r[42], previous_distance_r});
    assign numerator_w = $signed({previous_product_r[82], previous_product_r})
        - $signed({current_product_r[82], current_product_r});
    assign remainder_shift_w = {remainder_r[43:0], quotient_r[83]};
    assign remainder_next_w = remainder_shift_w >= {1'b0, divisor_r}
        ? remainder_shift_w - {1'b0, divisor_r} : remainder_shift_w;
    assign quotient_next_w = {quotient_r[82:0], remainder_shift_w >= {1'b0, divisor_r}};
    assign unused_rounded_w = {1'b0, quotient_r}
        + {84'd0, ({remainder_r, 1'b0} >= {2'd0, divisor_r})};
    assign intersection_value_w = negative_r
        ? -unused_rounded_w[39:0] : unused_rounded_w[39:0];

    // Acceptance stage: three copies of five s43 plane add/subtract units.
    // Edge stage: two paths, each one s43 adder and one s43 subtractor, selected by plane_r.
    genvar vertex_g;
    genvar distance_g;
    genvar field_g;
    genvar slot_g;
    generate
        for (vertex_g = 0; vertex_g < 3; vertex_g = vertex_g + 1) begin : g_inside
            wire signed [42:0] x_w;
            wire signed [42:0] y_w;
            wire signed [42:0] w_w;
            wire [43*5-1:0] unused_distance_w;
            assign x_w = {{3{triangle_data_i[vertex_g * 264 + 39]}},
                triangle_data_i[vertex_g * 264 +: 40]};
            assign y_w = {{3{triangle_data_i[vertex_g * 264 + 79]}},
                triangle_data_i[vertex_g * 264 + 40 +: 40]};
            assign w_w = {{3{triangle_data_i[vertex_g * 264 + 159]}},
                triangle_data_i[vertex_g * 264 + 120 +: 40]};
            assign unused_distance_w[0 +: 43] = w_w - 43'sd4096;
            assign unused_distance_w[43 +: 43] = (w_w <<< 2) + x_w;
            assign unused_distance_w[86 +: 43] = (w_w <<< 2) - x_w;
            assign unused_distance_w[129 +: 43] = (w_w <<< 2) + y_w;
            assign unused_distance_w[172 +: 43] = (w_w <<< 2) - y_w;
            for (distance_g = 0; distance_g < 5; distance_g = distance_g + 1) begin : g_sign
                assign outside_w[vertex_g * 5 + distance_g] = unused_distance_w[43*distance_g+42];
            end
        end
        for (distance_g = 0; distance_g < 2; distance_g = distance_g + 1) begin : g_distance
            wire signed [42:0] x_w;
            wire signed [42:0] y_w;
            wire signed [42:0] w_w;
            reg signed [42:0] left_w;
            reg signed [42:0] right_w;
            reg subtract_w;
            wire signed [42:0] sum_w;
            wire signed [42:0] difference_w;
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
            assign sum_w = left_w + right_w;
            assign difference_w = left_w - right_w;
            assign edge_distance_w[distance_g] = subtract_w ? difference_w : sum_w;
        end
        // Nine independent fields: 16 workset registers and two output slots each.
        // Each workset register has one full-field write point, including initial load.
        for (field_g = 0; field_g < 9; field_g = field_g + 1) begin : g_field
            localparam WIDTH = field_g < 4 ? 40 : (field_g < 6 ? 16 : 24);
            localparam OFFSET = field_g < 4 ? field_g * 40
                : (field_g < 6 ? 160 + (field_g - 4) * 16 : 192 + (field_g - 6) * 24);
            wire [WIDTH*16-1:0] workset_w;
            reg [WIDTH-1:0] current_w;
            reg [WIDTH-1:0] last_w;
            reg [WIDTH-1:0] previous_r;
            reg [WIDTH-1:0] intersection_r;
            always @(*) begin
                current_w = 0;
                case ({bank_r, vertex_index_r})
                    4'd0: current_w = workset_w[WIDTH*0 +: WIDTH];
                    4'd1: current_w = workset_w[WIDTH*1 +: WIDTH];
                    4'd2: current_w = workset_w[WIDTH*2 +: WIDTH];
                    4'd3: current_w = workset_w[WIDTH*3 +: WIDTH];
                    4'd4: current_w = workset_w[WIDTH*4 +: WIDTH];
                    4'd5: current_w = workset_w[WIDTH*5 +: WIDTH];
                    4'd6: current_w = workset_w[WIDTH*6 +: WIDTH];
                    4'd7: current_w = workset_w[WIDTH*7 +: WIDTH];
                    4'd8: current_w = workset_w[WIDTH*8 +: WIDTH];
                    4'd9: current_w = workset_w[WIDTH*9 +: WIDTH];
                    4'd10: current_w = workset_w[WIDTH*10 +: WIDTH];
                    4'd11: current_w = workset_w[WIDTH*11 +: WIDTH];
                    4'd12: current_w = workset_w[WIDTH*12 +: WIDTH];
                    4'd13: current_w = workset_w[WIDTH*13 +: WIDTH];
                    4'd14: current_w = workset_w[WIDTH*14 +: WIDTH];
                    4'd15: current_w = workset_w[WIDTH*15 +: WIDTH];
                    default: current_w = 0;
                endcase
            end
            always @(*) begin
                last_w = 0;
                case ({bank_r, last_index_w})
                    4'd0: last_w = workset_w[WIDTH*0 +: WIDTH];
                    4'd1: last_w = workset_w[WIDTH*1 +: WIDTH];
                    4'd2: last_w = workset_w[WIDTH*2 +: WIDTH];
                    4'd3: last_w = workset_w[WIDTH*3 +: WIDTH];
                    4'd4: last_w = workset_w[WIDTH*4 +: WIDTH];
                    4'd5: last_w = workset_w[WIDTH*5 +: WIDTH];
                    4'd6: last_w = workset_w[WIDTH*6 +: WIDTH];
                    4'd7: last_w = workset_w[WIDTH*7 +: WIDTH];
                    4'd8: last_w = workset_w[WIDTH*8 +: WIDTH];
                    4'd9: last_w = workset_w[WIDTH*9 +: WIDTH];
                    4'd10: last_w = workset_w[WIDTH*10 +: WIDTH];
                    4'd11: last_w = workset_w[WIDTH*11 +: WIDTH];
                    4'd12: last_w = workset_w[WIDTH*12 +: WIDTH];
                    4'd13: last_w = workset_w[WIDTH*13 +: WIDTH];
                    4'd14: last_w = workset_w[WIDTH*14 +: WIDTH];
                    4'd15: last_w = workset_w[WIDTH*15 +: WIDTH];
                    default: last_w = 0;
                endcase
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
                if (state_r == S_BEGIN) previous_r <= last_w;
                if (state_r == S_ADVANCE) previous_r <= current_w;
                if (state_r == S_ROUND && component_r == field_g)
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
                    assign load_data_w = triangle_data_i[slot_g * 264 + OFFSET +: WIDTH];
                end else begin : g_no_input
                    assign load_data_w = {WIDTH{1'b0}};
                end
                assign append_w = bank_r == (slot_g < 8) && result_count_r[2:0] == INDEX
                    && (state_r == S_APPEND_INTERSECTION || state_r == S_APPEND_CURRENT);
                assign append_data_w = state_r == S_APPEND_INTERSECTION
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
                    assign bypass_w = triangle_data_i[slot_g * 264 + OFFSET +: WIDTH];
                end else begin : g_padding
                    assign bypass_w = {WIDTH{1'b0}};
                end
                assign push_wide_w = state_r == S_IDLE ? bypass_w
                    : (bank_r ? workset_w[WIDTH*(8 + slot_g) +: WIDTH]
                        : workset_w[WIDTH*slot_g +: WIDTH]);
                assign polygon_data_o[slot_g * 264 + OFFSET +: WIDTH] = data_r[read_r];
                always @(posedge clk_i) begin
                    if (push_w) data_r[write_r] <= push_wide_w;
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
        if (state_r == S_BEGIN) previous_distance_r <= last_distance_w;
        if (state_r == S_MULTIPLY) begin
            previous_product_r <= previous_selected_w * current_distance_w;
            current_product_r <= current_selected_w * previous_distance_r;
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
        if (state_r == S_ADVANCE) begin
            previous_distance_r <= current_distance_w;
        end
        if (push_w) begin
            output_count_r[write_r] <= state_r == S_IDLE ? 4'd3 : input_count_r;
        end
    end
endmodule
