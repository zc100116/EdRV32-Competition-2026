// File: edrv32_rnd_geometry.v
// Spec: rnd-spec v0.4 2.3 and 2.6 TRIANGLE/LINE/ARC, 5.2.
// Description: One lane, four subcolumns and four streamed subrows; exact signed
//              edge/circle differences feed registered predicates and coverage counts.
// Clock domain: clk_mem (clk_i).
module edrv32_rnd_geometry (
    // Clock and synchronous stream cancellation.
    input wire clk_i,
    input wire rst_n_i,
    input wire clear_i,
    input wire start_i,

    // Command/parameters are captured at command start.
    input wire [511:0] command_i,
    input wire [1023:0] parameters_i,
    input wire [11:0] left_i,
    input wire [11:0] top_i,

    // Consecutive drawing groups; row_end restarts at the clipped left edge.
    input wire request_i,
    output wire ready_o,
    input wire row_end_i,
    output wire valid_o,
    input wire out_ready_i,
    output wire [7:0] coverage_o
);
    localparam [2:0] S_IDLE = 3'd0;
    localparam [2:0] S_X = 3'd1;
    localparam [2:0] S_Y = 3'd2;
    localparam [2:0] S_SEED = 3'd3;
    localparam [2:0] S_READY = 3'd4;
    localparam [2:0] S_CENTER = 3'd5;
    localparam [2:0] S_SETUP = 3'd6;
    reg [2:0] state_r;
    reg [2:0] state_w;
    reg [16:0] skip_x_r;
    reg [16:0] skip_y_r;
    reg [1:0] phase_r;
    reg sample_valid_r;
    reg q_valid_r;
    reg inside_valid_r;
    reg count_valid_r;
    reg output_valid_r;
    reg [1:0] sample_phase_r;
    reg [1:0] q_phase_r;
    reg [1:0] inside_phase_r;
    reg [1:0] count_phase_r;
    reg aa_r;
    reg triangle_r;
    reg line_r;
    reg [34:0] length_r;
    reg signed [35:0] half_width_r;
    reg [7:0] output_r [0:7];
    reg [2:0] read_r;
    reg [2:0] write_r;
    reg [3:0] queued_r;
    reg [3:0] reserved_r;
    wire consume_w;
    wire enqueue_w;
    wire [7:0] result_w;
    wire aa_w;
    wire triangle_w;
    wire line_w;
    wire accept_w;
    wire sample_w;
    wire [1:0] sample_phase_w;
    wire signed [17:0] offset_x_w;
    wire signed [17:0] offset_y_w;
    wire [34:0] length_w;
    wire signed [35:0] half_width_w;
    reg signed [35:0] circle_r [0:3];
    reg signed [35:0] center_offset_r [0:3];
    reg signed [35:0] circle_row_r [0:3];
    reg signed [23:0] circle_dx_r [0:3];
    reg signed [23:0] circle_row_dx_r [0:3];
    reg signed [23:0] circle_dy_r [0:3];
    reg signed [23:0] circle_row_dy_r [0:3];
    reg signed [35:0] circle_sample_r [0:3];
    reg signed [23:0] circle_sample_dy_r [0:3];
    reg signed [23:0] circle_sample_dx_r [0:3];
    wire signed [23:0] circle_sample_dx_w [0:3];
    reg signed [35:0] edge_r [0:2];
    reg signed [35:0] edge_row_r [0:2];
    reg signed [35:0] edge_sample_r [0:2];
    reg signed [35:0] edge_dx_r [0:2];
    reg signed [35:0] edge_dy_r [0:2];
    wire signed [35:0] circle_base_w [0:3];
    wire signed [23:0] circle_delta_w [0:3];
    wire signed [35:0] edge_base_w [0:2];
    reg signed [35:0] circle_base_r [0:3];
    reg signed [23:0] circle_delta_r [0:3];
    reg signed [35:0] edge_base_r [0:2];
    reg signed [31:0] edge_dx_sample_r [0:2];
    reg signed [35:0] q_r [0:0][0:3][0:3];
    reg signed [35:0] e_r [0:0][0:3][0:2];
    reg [3:0] inside_r [0:0];
    reg [2:0] count_r [0:0];
    reg [4:0] total_r [0:0];
    reg [4:0] result_r [0:0];
    wire unused_parameters_w;
    assign aa_w = aa_r;
    assign triangle_w = triangle_r;
    assign line_w = line_r;
    assign ready_o = state_r == S_READY && phase_r == 0 && reserved_r < 8;
    assign accept_w = ready_o && request_i;
    assign sample_w = accept_w || phase_r != 0;
    assign sample_phase_w = accept_w ? 2'd0 : phase_r;
    assign offset_x_w = $signed({6'd0, left_i}) -
        $signed({{2{command_i[175]}}, command_i[175:160]});
    assign offset_y_w = $signed({6'd0, top_i}) -
        $signed({{2{command_i[191]}}, command_i[191:176]});
    assign length_w = length_r;
    assign half_width_w = half_width_r;
    assign valid_o = queued_r != 0 || output_valid_r;
    assign coverage_o = queued_r != 0 ? output_r[read_r] : result_w;
    assign consume_w = valid_o && out_ready_i;
    assign enqueue_w = output_valid_r && (queued_r != 0 || !out_ready_i);
    always @(posedge clk_i) begin
        if (start_i) begin
            aa_r <= command_i[16];
            triangle_r <= command_i[7:0] == 8'h09;
            line_r <= command_i[7:0] == 8'h0a;
            length_r <= {parameters_i[223:192], 3'd0};
            half_width_r <= $signed({1'b0, parameters_i[255:224], 3'd0});
        end
        if (enqueue_w)
            output_r[write_r] <= result_w;
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            read_r <= 3'd0;
            write_r <= 3'd0;
            queued_r <= 4'd0;
            reserved_r <= 4'd0;
        end else if (clear_i || start_i) begin
            read_r <= 3'd0;
            write_r <= 3'd0;
            queued_r <= 4'd0;
            reserved_r <= 4'd0;
        end else begin
            reserved_r <= reserved_r + {3'd0, accept_w} - {3'd0, consume_w};
            queued_r <= queued_r + {3'd0, enqueue_w} -
                {3'd0, consume_w && queued_r != 0};
            if (enqueue_w)
                write_r <= write_r + 3'd1;
            if (consume_w && queued_r != 0)
                read_r <= read_r + 3'd1;
        end
    end
    assign unused_parameters_w = ^{parameters_i[1023:704], parameters_i[495:480],
        parameters_i[367:352], parameters_i[239:224], parameters_i[111:96],
        offset_x_w[17], offset_y_w[17], command_i[511:192], command_i[159:22],
        command_i[15:8], command_i[21:17]};

    always @(*) begin
        state_w = state_r;
        case (state_r)
            S_CENTER: state_w = S_SETUP;
            S_SETUP: state_w = S_X;
            S_X: if (skip_x_r == 0)
                state_w = S_Y;
            S_Y: if (skip_y_r == 0)
                state_w = S_SEED;
            S_SEED: state_w = S_READY;
            default: state_w = state_r;
        endcase
    end
    // Every circle/edge has the same state, phase and AA D as the central control.
    // Request stays combinational, so backpressure and the sampling edge are unchanged.
    genvar control;
    generate for (control = 0; control < 7; control = control + 1) begin : g_sample_ctrl
        reg [2:0] control_state_r /* synthesis syn_preserve=1 */;
        reg [1:0] phase_copy_r /* synthesis syn_preserve=1 */;
        reg aa_copy_r /* synthesis syn_preserve=1 */;
        wire group_start_copy_w /* synthesis syn_keep=1 */;
        wire sample_copy_w /* synthesis syn_keep=1 */;
        assign group_start_copy_w = control_state_r == S_READY && phase_copy_r == 0;
        assign sample_copy_w = (group_start_copy_w && reserved_r < 8 && request_i) ||
            phase_copy_r != 0;
        always @(posedge clk_i) begin
            if (start_i)
                aa_copy_r <= command_i[16];
        end
        always @(posedge clk_i or negedge rst_n_i) begin
            if (!rst_n_i) begin
                control_state_r <= S_IDLE;
                phase_copy_r <= 2'd0;
            end else if (clear_i || start_i) begin
                control_state_r <= clear_i ? S_IDLE : S_CENTER;
                phase_copy_r <= 2'd0;
            end else begin
                control_state_r <= state_w;
                if (sample_w)
                    phase_copy_r <= aa_w ? phase_r + 2'd1 : 2'd0;
            end
        end
    end endgenerate

    genvar item;
    generate for (item = 0; item < 4; item = item + 1) begin : g_circle
        wire [2:0] state_local_w;
        assign state_local_w = g_sample_ctrl[item].control_state_r;
        wire aa_local_w;
        assign aa_local_w = g_sample_ctrl[item].aa_copy_r;
        wire group_start_local_w;
        assign group_start_local_w = g_sample_ctrl[item].group_start_copy_w;
        wire sample_local_w;
        assign sample_local_w = g_sample_ctrl[item].sample_copy_w;
        wire [127:0] block_w;
        wire signed [35:0] initial_w;
        wire signed [23:0] dx_w;
        wire signed [23:0] dy_w;
        wire signed [35:0] center_x_w;
        wire signed [35:0] center_y_w;
        wire signed [35:0] center_offset_w;
        wire signed [35:0] subrow_delta_w;
        assign block_w = command_i[7:0] == 8'h0a ? parameters_i[256+item*128 +: 128] :
            parameters_i[item*128 +: 128];
        assign initial_w = $signed(block_w[35:0]);
        assign dx_w = $signed(block_w[87:64]);
        assign dy_w = $signed(block_w[119:96]);
        assign center_x_w =
            ($signed({{12{circle_dx_r[item][23]}}, circle_dx_r[item]}) - 36'sd112) >>> 3;
        assign center_y_w =
            ($signed({{12{circle_dy_r[item][23]}}, circle_dy_r[item]}) - 36'sd112) >>> 3;
        assign subrow_delta_w =
            ($signed({{12{circle_dy_r[item][23]}}, circle_dy_r[item]}) - 36'sd48) >>> 2;
        assign center_offset_w = center_x_w + (center_x_w <<< 1) +
            center_y_w + (center_y_w <<< 1) + 36'sd18;
        assign circle_base_w[item] = group_start_local_w ?
            circle_r[item] : circle_sample_r[item];
        assign circle_sample_dx_w[item] = group_start_local_w ?
            circle_dx_r[item] : circle_sample_dx_r[item];
        wire signed [24:0] subcolumn_delta_w;
        assign subcolumn_delta_w =
            $signed({circle_sample_dx_w[item][23], circle_sample_dx_w[item]}) - 25'sd48;
        assign circle_delta_w[item] = {subcolumn_delta_w[24], subcolumn_delta_w[24:2]};
        wire unused_delta_w;
        assign unused_delta_w = ^subcolumn_delta_w[1:0];
        wire unused_block_w;
        assign unused_block_w = ^{block_w[63:36], block_w[95:88], block_w[127:120]};
        wire signed [35:0] step_base_w;
        wire signed [35:0] step_delta_w;
        wire signed [23:0] step_dx_w;
        wire signed [23:0] step_dy_w;
        wire signed [35:0] step_result_w;
        wire signed [35:0] sample_delta_w;
        // Request qualifies the register enable, not the arithmetic operand mux.
        assign step_base_w = state_local_w == S_READY && row_end_i ?
            circle_row_r[item] : circle_r[item];
        assign step_delta_w = state_local_w == S_Y ?
            {{12{circle_dy_r[item][23]}}, circle_dy_r[item]} :
            state_local_w == S_READY && row_end_i ?
                {{12{circle_row_dy_r[item][23]}}, circle_row_dy_r[item]} :
                    {{12{circle_dx_r[item][23]}}, circle_dx_r[item]};
        assign step_result_w = step_base_w + step_delta_w;
        assign step_dx_w = circle_dx_r[item] + 24'sd128;
        assign step_dy_w = (state_local_w == S_READY ?
            circle_row_dy_r[item] : circle_dy_r[item]) + 24'sd128;
        assign sample_delta_w = group_start_local_w ?
            (aa_local_w ? subrow_delta_w : 36'sd0) :
            {{12{circle_sample_dy_r[item][23]}}, circle_sample_dy_r[item]};
        always @(posedge clk_i) begin
            if (start_i) begin
                circle_r[item] <= initial_w;
                circle_dx_r[item] <= dx_w + (command_i[16] ? 24'sd0 : 24'sd48);
                circle_dy_r[item] <= dy_w + (command_i[16] ? 24'sd0 : 24'sd48);
            end else begin
                // Decode, center adjustment and seeding occupy separate setup cycles.
                if (state_local_w == S_CENTER)
                    center_offset_r[item] <= center_offset_w;
                if (state_local_w == S_SETUP)
                    circle_r[item] <= circle_r[item] + (aa_local_w ?
                        36'sd0 : center_offset_r[item]);
                if ((state_local_w == S_X && skip_x_r != 0) ||
                    (state_local_w == S_Y && skip_y_r != 0) || accept_w)
                    circle_r[item] <= step_result_w;
                if ((state_local_w == S_X && skip_x_r != 0) ||
                    (accept_w && !row_end_i))
                    circle_dx_r[item] <= step_dx_w;
                else if (accept_w && row_end_i)
                    circle_dx_r[item] <= circle_row_dx_r[item];
                if ((state_local_w == S_Y && skip_y_r != 0) ||
                    (accept_w && row_end_i))
                    circle_dy_r[item] <= step_dy_w;
                if (state_local_w == S_SEED) begin
                    circle_row_r[item] <= circle_r[item];
                    circle_row_dx_r[item] <= circle_dx_r[item];
                    circle_row_dy_r[item] <= circle_dy_r[item];
                end else if (accept_w && row_end_i) begin
                    circle_row_r[item] <= step_result_w;
                    circle_row_dy_r[item] <= step_dy_w;
                end
                if (sample_local_w)
                    circle_sample_r[item] <= (group_start_local_w ? circle_r[item] :
                        circle_sample_r[item]) + sample_delta_w;
                if (accept_w) begin
                    circle_sample_dx_r[item] <= circle_dx_r[item];
                    circle_sample_dy_r[item] <= aa_local_w ?
                        subrow_delta_w[23:0] + 24'sd8 : 24'sd0;
                end else if (phase_r != 0)
                    circle_sample_dy_r[item] <= circle_sample_dy_r[item] +
                        (aa_local_w ? 24'sd8 : 24'sd0);
            end
        end
        always @(posedge clk_i) begin
            if (sample_local_w) begin
                circle_base_r[item] <= circle_base_w[item];
                circle_delta_r[item] <= circle_delta_w[item];
            end
        end
    end endgenerate

    generate for (item = 0; item < 3; item = item + 1) begin : g_edge
        wire [2:0] state_local_w;
        assign state_local_w = g_sample_ctrl[item+4].control_state_r;
        wire aa_local_w;
        assign aa_local_w = g_sample_ctrl[item+4].aa_copy_r;
        wire group_start_local_w;
        assign group_start_local_w = g_sample_ctrl[item+4].group_start_copy_w;
        wire sample_local_w;
        assign sample_local_w = g_sample_ctrl[item+4].sample_copy_w;
        wire [95:0] block_w;
        wire signed [35:0] initial_w;
        assign block_w = command_i[7:0] != 8'h09 && command_i[7:0] != 8'h0a ?
            parameters_i[512+item*96 +: 96] : parameters_i[item*96 +: 96];
        wire signed [35:0] dx_w;
        wire signed [35:0] dy_w;
        assign dx_w = {{4{block_w[63]}}, block_w[63:32]};
        assign dy_w = {{4{block_w[95]}}, block_w[95:64]};
        assign initial_w = $signed({{4{block_w[31]}}, block_w[31:0]}) <<< 3;
        assign edge_base_w[item] = group_start_local_w ? edge_r[item] :
            edge_sample_r[item];
        wire signed [35:0] step_base_w;
        wire signed [35:0] step_delta_w;
        wire signed [35:0] step_result_w;
        assign step_base_w = state_local_w == S_READY && row_end_i ?
            edge_row_r[item] : edge_r[item];
        assign step_delta_w = state_local_w == S_Y ||
            (state_local_w == S_READY && row_end_i) ?
            edge_dy_r[item] <<< 3 : edge_dx_r[item] <<< 3;
        assign step_result_w = step_base_w + step_delta_w;
        always @(posedge clk_i) begin
            if (start_i) begin
                edge_dx_r[item] <= dx_w;
                edge_dy_r[item] <= dy_w;
                edge_r[item] <= initial_w + (command_i[16] ? dx_w : dx_w <<< 2) +
                    (command_i[16] ? dy_w : dy_w <<< 2);
            end else begin
                if ((state_local_w == S_X && skip_x_r != 0) ||
                    (state_local_w == S_Y && skip_y_r != 0) || accept_w)
                    edge_r[item] <= step_result_w;
                if (state_local_w == S_SEED)
                    edge_row_r[item] <= edge_r[item];
                else if (accept_w && row_end_i)
                    edge_row_r[item] <= step_result_w;
                if (sample_local_w)
                    edge_sample_r[item] <= (group_start_local_w ?
                        edge_r[item] : edge_sample_r[item]) +
                        (aa_local_w ? edge_dy_r[item] <<< 1 : 36'sd0);
            end
        end
        always @(posedge clk_i) begin
            if (sample_local_w) begin
                edge_base_r[item] <= edge_base_w[item];
                edge_dx_sample_r[item] <= edge_dx_r[item][31:0];
            end
        end
    end endgenerate

    genvar pixel;
    genvar subcolumn;
    genvar element;
    generate for (pixel = 0; pixel < 1; pixel = pixel + 1) begin : g_lane
        wire [12:0] coverage_scaled_w;
        assign coverage_scaled_w = {result_r[pixel], 8'd0} -
            {8'd0, result_r[pixel]} + 13'd8;
        assign result_w[pixel*8 +: 8] = coverage_scaled_w[11:4];
        wire unused_coverage_w;
        assign unused_coverage_w = ^{coverage_scaled_w[12], coverage_scaled_w[3:0]};
        for (subcolumn = 0; subcolumn < 4; subcolumn = subcolumn + 1) begin : g_column
            (* keep = "true", syn_preserve = 1 *) reg [5:0] column_mode_r;
            // Distinct setup enables retain physical copies through register merging.
            localparam integer COLUMN = pixel * 4 + subcolumn;
            wire mode_load_w;
            assign mode_load_w = COLUMN == 0 ? start_i :
                COLUMN == 1 ? state_r == S_CENTER : COLUMN == 2 ? state_r == S_SETUP :
                    state_r == S_X;
            always @(posedge clk_i) begin
                if (mode_load_w)
                    column_mode_r <= command_i[21:16];
            end
            localparam integer STEP = pixel * 4 + subcolumn;
            localparam integer OFFSET = 4 * STEP * (STEP - 1);
            localparam signed [23:0] BIAS = OFFSET[23:0];
            wire [3:0] circle_inside_w;
            wire [2:0] edge_inside_w;
            wire line_inside_w;
            wire ring_inside_w;
            wire angle_inside_w;
            wire sample_inside_w;
            for (element = 0; element < 4; element = element + 1) begin : g_q
                wire signed [23:0] delta_w;
                wire signed [23:0] offset_w;
                assign delta_w = circle_delta_r[element];
                assign offset_w = column_mode_r[0] ?
                    ((STEP & 1) != 0 ? delta_w : 24'sd0) +
                    ((STEP & 2) != 0 ? delta_w <<< 1 : 24'sd0) +
                    BIAS : 24'sd0;
                assign circle_inside_w[element] = q_r[pixel][subcolumn][element] <= 0;
                always @(posedge clk_i) begin
                    q_r[pixel][subcolumn][element] <= circle_base_r[element] +
                        {{12{offset_w[23]}}, offset_w};
                end
            end
            for (element = 0; element < 3; element = element + 1) begin : g_e
                wire signed [35:0] offset_w;
                wire signed [35:0] dx_w;
                assign dx_w = {{4{edge_dx_sample_r[element][31]}}, edge_dx_sample_r[element]};
                assign offset_w = column_mode_r[0] ?
                    ((subcolumn & 1) != 0 ? dx_w <<< 1 : 36'sd0) +
                    ((subcolumn & 2) != 0 ? dx_w <<< 2 : 36'sd0) : 36'sd0;
                assign edge_inside_w[element] = triangle_w && !column_mode_r[1+element] ?
                    e_r[pixel][subcolumn][element] > 0 :
                    e_r[pixel][subcolumn][element] >= 0;
                always @(posedge clk_i) begin
                    e_r[pixel][subcolumn][element] <= edge_base_r[element] +
                        offset_w;
                end
            end
            // L/h occupy 35 bits; the signed36 geometry retains the comparison sign.
            assign line_inside_w = !e_r[pixel][subcolumn][0][35] &&
                e_r[pixel][subcolumn][0][34:0] <= length_w &&
                e_r[pixel][subcolumn][1] >= -half_width_w &&
                e_r[pixel][subcolumn][1] <= half_width_w;
            assign ring_inside_w = circle_inside_w[0] &&
                (column_mode_r[5] || !circle_inside_w[1]);
            assign angle_inside_w = column_mode_r[4] || (column_mode_r[3] ?
                (edge_inside_w[0] || edge_inside_w[1]) :
                (edge_inside_w[0] && edge_inside_w[1]));
            assign sample_inside_w = triangle_w ? &edge_inside_w : line_w ?
                line_inside_w || (column_mode_r[1] && circle_inside_w[0]) ||
                (column_mode_r[2] && circle_inside_w[1]) :
                (ring_inside_w && angle_inside_w) || (!column_mode_r[4] &&
                ((column_mode_r[1] && circle_inside_w[2]) ||
                    (column_mode_r[2] && circle_inside_w[3])));
            always @(posedge clk_i) begin
                if (q_valid_r)
                    inside_r[pixel][subcolumn] <= sample_inside_w;
            end
        end
        always @(posedge clk_i) begin
            if (inside_valid_r)
                count_r[pixel] <= {2'd0, inside_r[pixel][0]} +
                    {2'd0, inside_r[pixel][1]} + {2'd0, inside_r[pixel][2]} +
                    {2'd0, inside_r[pixel][3]};
            if (count_valid_r) begin
                total_r[pixel] <= count_phase_r == 0 ? {2'd0, count_r[pixel]} :
                    total_r[pixel] + {2'd0, count_r[pixel]};
                if (!aa_w || count_phase_r == 3)
                    result_r[pixel] <= aa_w ? total_r[pixel] + {2'd0, count_r[pixel]} :
                        {count_r[pixel], 2'd0};
            end
        end
    end endgenerate

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            skip_x_r <= 17'd0;
            skip_y_r <= 17'd0;
            phase_r <= 2'd0;
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
            sample_valid_r <= 1'b0;
            q_valid_r <= 1'b0;
            inside_valid_r <= 1'b0;
            count_valid_r <= 1'b0;
            output_valid_r <= 1'b0;
        end else begin
            if (sample_w)
                phase_r <= aa_w ? phase_r + 2'd1 : 2'd0;
            state_r <= state_w;
            if (state_r == S_X && skip_x_r != 0)
                skip_x_r <= skip_x_r - 17'd1;
            if (state_r == S_Y && skip_y_r != 0)
                skip_y_r <= skip_y_r - 17'd1;
            sample_valid_r <= sample_w;
            q_valid_r <= sample_valid_r;
            inside_valid_r <= q_valid_r;
            count_valid_r <= inside_valid_r;
            output_valid_r <= count_valid_r && (!aa_w || count_phase_r == 3);
        end
    end
    always @(posedge clk_i) begin
        sample_phase_r <= sample_phase_w;
        q_phase_r <= sample_phase_r;
        inside_phase_r <= q_phase_r;
        count_phase_r <= inside_phase_r;
    end
endmodule
