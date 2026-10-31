// File: edrv32_rnd_geometry.v
// Spec: rnd-spec v0.3 2.3 and 2.6 TRIANGLE/LINE/ARC, 5.2.
// Description: Two lanes, four subcolumns and four streamed subrows; exact signed
//              edge/circle differences feed registered predicates and coverage counts.
// Clock domain: clk_mem (clk_i).
module edrv32_rnd_geometry (
    // Clock and synchronous stream cancellation.
    input wire clk_i,
    input wire rst_n_i,
    input wire clear_i,
    input wire start_i,
    input wire advance_i,

    // Command/parameters remain stable through the complete draw.
    input wire [511:0] command_i,
    input wire [1023:0] parameters_i,
    input wire [11:0] left_i,
    input wire [11:0] top_i,

    // Consecutive drawing groups; row_end restarts at the clipped left edge.
    input wire request_i,
    output wire ready_o,
    input wire pair_i,
    input wire row_end_i,
    output wire valid_o,
    output wire [15:0] coverage_o
);
    localparam [2:0] S_IDLE = 3'd0;
    localparam [2:0] S_X = 3'd1;
    localparam [2:0] S_Y = 3'd2;
    localparam [2:0] S_SEED = 3'd3;
    localparam [2:0] S_READY = 3'd4;
    localparam [2:0] S_CENTER = 3'd5;
    localparam [2:0] S_SETUP = 3'd6;
    reg [2:0] state_r;
    reg [16:0] skip_x_r;
    reg [16:0] skip_y_r;
    reg [1:0] phase_r;
    reg sample_valid_r;
    reg pending_r;
    reg pair_r;
    reg row_end_r;
    reg q_valid_r;
    reg inside_valid_r;
    reg count_valid_r;
    reg output_valid_r;
    reg [1:0] sample_phase_r;
    reg [1:0] q_phase_r;
    reg [1:0] inside_phase_r;
    reg [1:0] count_phase_r;
    wire aa_w;
    wire triangle_w;
    wire line_w;
    wire accept_w;
    wire group_start_w;
    wire sample_w;
    wire [1:0] sample_phase_w;
    wire signed [17:0] offset_x_w;
    wire signed [17:0] offset_y_w;
    wire [34:0] length_w;
    wire signed [35:0] half_width_w;
    reg signed [47:0] circle_r [0:3];
    reg signed [47:0] center_offset_r [0:3];
    reg signed [47:0] circle_row_r [0:3];
    reg signed [31:0] circle_dx_r [0:3];
    reg signed [31:0] circle_row_dx_r [0:3];
    reg signed [31:0] circle_dy_r [0:3];
    reg signed [31:0] circle_row_dy_r [0:3];
    reg signed [47:0] circle_sample_r [0:3];
    reg signed [31:0] circle_sample_dy_r [0:3];
    reg signed [31:0] circle_sample_dx_r [0:3];
    wire signed [31:0] circle_sample_dx_w [0:3];
    reg signed [50:0] edge_r [0:2];
    reg signed [50:0] edge_row_r [0:2];
    reg signed [50:0] edge_sample_r [0:2];
    wire signed [50:0] edge_dx_w [0:2];
    wire signed [50:0] edge_dy_w [0:2];
    wire signed [47:0] circle_base_w [0:3];
    wire signed [31:0] circle_delta_w [0:3];
    wire signed [50:0] edge_base_w [0:2];
    reg signed [47:0] circle_base_r [0:3];
    reg signed [31:0] circle_delta_r [0:3];
    reg signed [31:0] circle_dx_sample_r [0:3];
    reg signed [50:0] edge_base_r [0:2];
    reg signed [31:0] edge_dx_sample_r [0:2];
    reg signed [47:0] q_r [0:1][0:3][0:3];
    reg signed [50:0] e_r [0:1][0:3][0:2];
    reg [3:0] inside_r [0:1];
    reg [2:0] count_r [0:1];
    reg [4:0] total_r [0:1];
    reg [4:0] result_r [0:1];
    wire unused_parameters_w;
    assign aa_w = command_i[16];
    assign triangle_w = command_i[7:0] == 8'h09;
    assign line_w = command_i[7:0] == 8'h0a;
    assign ready_o = state_r == S_READY && phase_r == 0;
    assign group_start_w = state_r == S_READY && phase_r == 0;
    assign accept_w = ready_o && request_i;
    assign sample_w = accept_w || phase_r != 0;
    assign sample_phase_w = accept_w ? 2'd0 : phase_r;
    assign offset_x_w = $signed({6'd0, left_i}) -
        $signed({{2{command_i[175]}}, command_i[175:160]});
    assign offset_y_w = $signed({6'd0, top_i}) -
        $signed({{2{command_i[191]}}, command_i[191:176]});
    assign length_w = {parameters_i[223:192], 3'd0};
    assign half_width_w = $signed({1'b0, parameters_i[255:224], 3'd0});
    assign valid_o = output_valid_r;
    assign unused_parameters_w = ^{parameters_i[1023:704], parameters_i[495:480],
        parameters_i[367:352], parameters_i[239:224], parameters_i[111:96],
        offset_x_w[17], offset_y_w[17], command_i[511:192], command_i[159:22],
        command_i[15:8]};

    genvar item;
    generate for (item = 0; item < 4; item = item + 1) begin : g_circle
        wire [127:0] block_w;
        wire signed [47:0] initial_w;
        wire signed [31:0] dx_w;
        wire signed [31:0] dy_w;
        wire signed [47:0] center_x_w;
        wire signed [47:0] center_y_w;
        wire signed [47:0] center_offset_w;
        wire signed [47:0] subrow_delta_w;
        assign block_w = line_w ? parameters_i[256+item*128 +: 128] :
            parameters_i[item*128 +: 128];
        assign initial_w = $signed(block_w[47:0]);
        assign dx_w = $signed(block_w[95:64]);
        assign dy_w = $signed(block_w[127:96]);
        assign center_x_w =
            ($signed({{16{circle_dx_r[item][31]}}, circle_dx_r[item]}) - 48'sd112) >>> 3;
        assign center_y_w =
            ($signed({{16{circle_dy_r[item][31]}}, circle_dy_r[item]}) - 48'sd112) >>> 3;
        assign subrow_delta_w =
            ($signed({{16{circle_dy_r[item][31]}}, circle_dy_r[item]}) - 48'sd48) >>> 2;
        assign center_offset_w = center_x_w + (center_x_w <<< 1) +
            center_y_w + (center_y_w <<< 1) + 48'sd18;
        assign circle_base_w[item] = group_start_w ? circle_r[item] : circle_sample_r[item];
        assign circle_sample_dx_w[item] = group_start_w ?
            circle_dx_r[item] : circle_sample_dx_r[item];
        assign circle_delta_w[item] = (circle_sample_dx_w[item] - 32'sd48) >>> 2;
        wire unused_block_w;
        assign unused_block_w = ^block_w[63:48];
        wire signed [47:0] step_base_w;
        wire signed [47:0] step_delta_w;
        wire signed [31:0] step_dx_w;
        wire signed [31:0] step_dy_w;
        wire signed [47:0] step_result_w;
        wire signed [47:0] sample_delta_w;
        assign step_base_w = pending_r && row_end_r ? circle_row_r[item] : circle_r[item];
        assign step_delta_w = state_r == S_Y ?
            {{16{circle_dy_r[item][31]}}, circle_dy_r[item]} :
            pending_r && row_end_r ?
                {{16{circle_row_dy_r[item][31]}}, circle_row_dy_r[item]} :
                pending_r && pair_r ?
                    ({{16{circle_dx_r[item][31]}}, circle_dx_r[item]} <<< 1) + 48'sd128 :
                    {{16{circle_dx_r[item][31]}}, circle_dx_r[item]};
        assign step_result_w = step_base_w + step_delta_w;
        assign step_dx_w = circle_dx_r[item] + (pending_r && pair_r ? 32'sd256 : 32'sd128);
        assign step_dy_w = (pending_r ? circle_row_dy_r[item] : circle_dy_r[item]) + 32'sd128;
        assign sample_delta_w = group_start_w ? (aa_w ? subrow_delta_w : 48'sd0) :
            {{16{circle_sample_dy_r[item][31]}}, circle_sample_dy_r[item]};
        always @(posedge clk_i) begin
            if (start_i) begin
                circle_r[item] <= initial_w;
                circle_dx_r[item] <= dx_w + (aa_w ? 32'sd0 : 32'sd48);
                circle_dy_r[item] <= dy_w + (aa_w ? 32'sd0 : 32'sd48);
            end else if (advance_i) begin
                // Decode, center adjustment and seeding occupy separate setup cycles.
                if (state_r == S_CENTER)
                    center_offset_r[item] <= center_offset_w;
                if (state_r == S_SETUP)
                    circle_r[item] <= circle_r[item] + (aa_w ? 48'sd0 : center_offset_r[item]);
                if ((state_r == S_X && skip_x_r != 0) ||
                    (state_r == S_Y && skip_y_r != 0) || pending_r)
                    circle_r[item] <= step_result_w;
                if ((state_r == S_X && skip_x_r != 0) || (pending_r && !row_end_r))
                    circle_dx_r[item] <= step_dx_w;
                else if (pending_r && row_end_r)
                    circle_dx_r[item] <= circle_row_dx_r[item];
                if ((state_r == S_Y && skip_y_r != 0) || (pending_r && row_end_r))
                    circle_dy_r[item] <= step_dy_w;
                if (state_r == S_SEED) begin
                    circle_row_r[item] <= circle_r[item];
                    circle_row_dx_r[item] <= circle_dx_r[item];
                    circle_row_dy_r[item] <= circle_dy_r[item];
                end else if (pending_r && row_end_r) begin
                    circle_row_r[item] <= step_result_w;
                    circle_row_dy_r[item] <= step_dy_w;
                end
                if (sample_w)
                    circle_sample_r[item] <= (group_start_w ? circle_r[item] :
                        circle_sample_r[item]) + sample_delta_w;
                if (accept_w) begin
                    circle_sample_dx_r[item] <= circle_dx_r[item];
                    circle_sample_dy_r[item] <= aa_w ?
                        ((circle_dy_r[item] - 32'sd48) >>> 2) + 32'sd8 : 32'sd0;
                end else if (phase_r != 0)
                    circle_sample_dy_r[item] <= circle_sample_dy_r[item] +
                        (aa_w ? 32'sd8 : 32'sd0);
            end
        end
    end endgenerate

    generate for (item = 0; item < 3; item = item + 1) begin : g_edge
        wire [95:0] block_w;
        wire signed [50:0] initial_w;
        assign block_w = !triangle_w && !line_w ?
            parameters_i[512+item*96 +: 96] : parameters_i[item*96 +: 96];
        assign edge_dx_w[item] = {{19{block_w[63]}}, block_w[63:32]};
        assign edge_dy_w[item] = {{19{block_w[95]}}, block_w[95:64]};
        assign initial_w = $signed({{19{block_w[31]}}, block_w[31:0]}) <<< 3;
        assign edge_base_w[item] = group_start_w ? edge_r[item] : edge_sample_r[item];
        wire signed [50:0] step_base_w;
        wire signed [50:0] step_delta_w;
        wire signed [50:0] step_result_w;
        assign step_base_w = pending_r && row_end_r ? edge_row_r[item] : edge_r[item];
        assign step_delta_w = state_r == S_Y || (pending_r && row_end_r) ?
            edge_dy_w[item] <<< 3 : pending_r && pair_r ?
                edge_dx_w[item] <<< 4 : edge_dx_w[item] <<< 3;
        assign step_result_w = step_base_w + step_delta_w;
        always @(posedge clk_i) begin
            if (start_i)
                edge_r[item] <= initial_w + (aa_w ? edge_dx_w[item] :
                    edge_dx_w[item] <<< 2) + (aa_w ? edge_dy_w[item] : edge_dy_w[item] <<< 2);
            else if (advance_i) begin
                if ((state_r == S_X && skip_x_r != 0) ||
                    (state_r == S_Y && skip_y_r != 0) || pending_r)
                    edge_r[item] <= step_result_w;
                if (state_r == S_SEED)
                    edge_row_r[item] <= edge_r[item];
                else if (pending_r && row_end_r)
                    edge_row_r[item] <= step_result_w;
                if (sample_w)
                    edge_sample_r[item] <= (group_start_w ? edge_r[item] : edge_sample_r[item]) +
                        (aa_w ? edge_dy_w[item] <<< 1 : 51'sd0);
            end
        end
    end endgenerate

    // Commit the next group position after registering row-end/pair selection.
    always @(posedge clk_i) begin
        if (advance_i && accept_w) begin
            pair_r <= pair_i;
            row_end_r <= row_end_i;
        end
    end
    // Select operands before the parallel constant offsets and full-width sums.
    integer sample_element;
    always @(posedge clk_i) begin
        if (advance_i && sample_w) begin
            for (sample_element = 0; sample_element < 4; sample_element = sample_element + 1) begin
                circle_base_r[sample_element] <= circle_base_w[sample_element];
                circle_delta_r[sample_element] <= circle_delta_w[sample_element];
                circle_dx_sample_r[sample_element] <= circle_sample_dx_w[sample_element];
            end
            for (sample_element = 0; sample_element < 3; sample_element = sample_element + 1) begin
                edge_base_r[sample_element] <= edge_base_w[sample_element];
                edge_dx_sample_r[sample_element] <= edge_dx_w[sample_element][31:0];
            end
        end
    end
    genvar pixel;
    genvar subcolumn;
    genvar element;
    generate for (pixel = 0; pixel < 2; pixel = pixel + 1) begin : g_lane
        wire [12:0] coverage_scaled_w;
        assign coverage_scaled_w = {result_r[pixel], 8'd0} -
            {8'd0, result_r[pixel]} + 13'd8;
        assign coverage_o[pixel*8 +: 8] = coverage_scaled_w[11:4];
        wire unused_coverage_w;
        assign unused_coverage_w = ^{coverage_scaled_w[12], coverage_scaled_w[3:0]};
        for (subcolumn = 0; subcolumn < 4; subcolumn = subcolumn + 1) begin : g_column
            localparam integer STEP = pixel * 4 + subcolumn;
            localparam integer OFFSET = 4 * STEP * (STEP - 1);
            localparam signed [34:0] BIAS = {{3{OFFSET[31]}}, OFFSET};
            wire [3:0] circle_inside_w;
            wire [2:0] edge_inside_w;
            wire line_inside_w;
            wire ring_inside_w;
            wire angle_inside_w;
            wire sample_inside_w;
            for (element = 0; element < 4; element = element + 1) begin : g_q
                wire signed [34:0] delta_w;
                wire signed [34:0] offset_w;
                assign delta_w = {{3{circle_delta_r[element][31]}}, circle_delta_r[element]};
                assign offset_w = aa_w ? delta_w * STEP + BIAS : pixel == 0 ? 35'sd0 :
                    {{3{circle_dx_sample_r[element][31]}}, circle_dx_sample_r[element]};
                assign circle_inside_w[element] = q_r[pixel][subcolumn][element] <= 0;
                always @(posedge clk_i) begin
                    if (advance_i && sample_valid_r)
                        q_r[pixel][subcolumn][element] <= circle_base_r[element] +
                            {{13{offset_w[34]}}, offset_w};
                end
            end
            for (element = 0; element < 3; element = element + 1) begin : g_e
                wire signed [35:0] offset_w;
                wire signed [35:0] dx_w;
                assign dx_w = {{4{edge_dx_sample_r[element][31]}}, edge_dx_sample_r[element]};
                assign offset_w = aa_w ? dx_w * (8*pixel+2*subcolumn) : dx_w * (8*pixel);
                assign edge_inside_w[element] = triangle_w && !command_i[17+element] ?
                    e_r[pixel][subcolumn][element] > 0 :
                    e_r[pixel][subcolumn][element] >= 0;
                always @(posedge clk_i) begin
                    if (advance_i && sample_valid_r)
                        e_r[pixel][subcolumn][element] <= edge_base_r[element] +
                            {{15{offset_w[35]}}, offset_w};
                end
            end
            // L/h occupy 35 bits; factor extension bits before the bounded compares.
            assign line_inside_w = e_r[pixel][subcolumn][0][50:35] == 0 &&
                e_r[pixel][subcolumn][0][34:0] <= length_w &&
                e_r[pixel][subcolumn][1][50:36] == {15{e_r[pixel][subcolumn][1][35]}} &&
                $signed(e_r[pixel][subcolumn][1][35:0]) >= -half_width_w &&
                $signed(e_r[pixel][subcolumn][1][35:0]) <= half_width_w;
            assign ring_inside_w = circle_inside_w[0] &&
                (command_i[21] || !circle_inside_w[1]);
            assign angle_inside_w = command_i[20] || (command_i[19] ?
                (edge_inside_w[0] || edge_inside_w[1]) :
                (edge_inside_w[0] && edge_inside_w[1]));
            assign sample_inside_w = triangle_w ? &edge_inside_w : line_w ?
                line_inside_w || (command_i[17] && circle_inside_w[0]) ||
                (command_i[18] && circle_inside_w[1]) :
                (ring_inside_w && angle_inside_w) || (!command_i[20] &&
                ((command_i[17] && circle_inside_w[2]) ||
                    (command_i[18] && circle_inside_w[3])));
            always @(posedge clk_i) begin
                if (advance_i && q_valid_r)
                    inside_r[pixel][subcolumn] <= sample_inside_w;
            end
        end
        always @(posedge clk_i) begin
            if (advance_i) begin
                if (inside_valid_r)
                    count_r[pixel] <= {2'd0, inside_r[pixel][0]} +
                        {2'd0, inside_r[pixel][1]} + {2'd0, inside_r[pixel][2]} +
                        {2'd0, inside_r[pixel][3]};
                if (count_valid_r) begin
                    total_r[pixel] <= count_phase_r == 0 ? {2'd0, count_r[pixel]} :
                        total_r[pixel] + {2'd0, count_r[pixel]};
                    if (count_phase_r == 3)
                        result_r[pixel] <= total_r[pixel] + {2'd0, count_r[pixel]};
                end
            end
        end
    end endgenerate

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            skip_x_r <= 17'd0;
            skip_y_r <= 17'd0;
            phase_r <= 2'd0;
            pending_r <= 1'b0;
            sample_valid_r <= 1'b0;
            q_valid_r <= 1'b0;
            inside_valid_r <= 1'b0;
            count_valid_r <= 1'b0;
            output_valid_r <= 1'b0;
        end else if (clear_i || start_i) begin
            state_r <= clear_i ? S_IDLE : S_CENTER;
            skip_x_r <= offset_x_w[16:0];
            skip_y_r <= offset_y_w[16:0];
            phase_r <= 2'd0;
            pending_r <= 1'b0;
            sample_valid_r <= 1'b0;
            q_valid_r <= 1'b0;
            inside_valid_r <= 1'b0;
            count_valid_r <= 1'b0;
            output_valid_r <= 1'b0;
        end else if (advance_i) begin
            if (sample_w)
                phase_r <= phase_r + 2'd1;
            case (state_r)
                S_CENTER: state_r <= S_SETUP;
                S_SETUP: state_r <= S_X;
                S_X: if (skip_x_r == 0)
                    state_r <= S_Y;
                else
                    skip_x_r <= skip_x_r - 17'd1;
                S_Y: if (skip_y_r == 0)
                    state_r <= S_SEED;
                else
                    skip_y_r <= skip_y_r - 17'd1;
                S_SEED: state_r <= S_READY;
                default: state_r <= state_r;
            endcase
            pending_r <= accept_w;
            sample_valid_r <= sample_w;
            q_valid_r <= sample_valid_r;
            inside_valid_r <= q_valid_r;
            count_valid_r <= inside_valid_r;
            output_valid_r <= count_valid_r && count_phase_r == 3;
        end
    end
    always @(posedge clk_i) begin
        if (advance_i) begin
            sample_phase_r <= sample_phase_w;
            q_phase_r <= sample_phase_r;
            inside_phase_r <= q_phase_r;
            count_phase_r <= inside_phase_r;
        end
    end
endmodule
