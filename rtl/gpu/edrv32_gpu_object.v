// File: edrv32_gpu_object.v
// Spec: gpu-spec.md 2.9, 4, 5; GPU microarchitecture 4.2, 4.5, 4.6.
// Description: Ordered object motion, lifetime, eight-way collision and quad generation.
//              Twelve-stage II=1 core with two ingress slots and independent output retirement.
// Clock: clk_i (GPU).
module edrv32_gpu_object (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Command and immutable configuration snapshots.
    input wire object_cfg_valid_i,
    output wire object_cfg_ready_o,
    input wire [63:0] object_cfg_live_i,
    input wire [511:0] object_cfg_targets_i,
    input wire [31:0] object_cfg_hit_base_i,
    input wire [23:0] object_cfg_hit_max_i,
    input wire [31:0] object_cfg_free_base_i,
    input wire [23:0] object_cfg_free_max_i,
    input wire draw_valid_i,
    output wire draw_ready_o,
    input wire [255:0] draw_command_i,
    input wire object_record_valid_i,
    output wire object_record_ready_o,
    input wire [255:0] object_record_data_i,
    input wire [23:0] object_record_idx_i,

    // Independently backpressured ordered output streams.
    output wire object_update_valid_o,
    input wire object_update_ready_i,
    output wire [23:0] object_update_idx_o,
    output wire [255:0] object_update_data_o,
    output wire object_event_valid_o,
    input wire object_event_ready_i,
    output wire [23:0] object_event_idx_o,
    output wire [7:0] object_event_hit_o,
    output wire object_event_free_o,
    output wire object_quad_valid_o,
    input wire object_quad_ready_i,
    output wire [127:0] object_quad_data_o,
    output wire [16:0] object_quad_x_o,
    output wire [16:0] object_quad_y_o,

    // Drain and deferred atomic result publication.
    input wire finish_i,
    input wire stop_i,
    output reg unit_done_o,
    input wire object_publish_i,
    output reg object_result_valid_o,
    input wire object_result_ready_i,
    output wire [23:0] object_result_hit_count_o,
    output wire [23:0] object_result_free_count_o,
    output wire [23:0] object_result_alive_count_o,
    output wire [1:0] object_result_overflow_o,
    output wire perf_object_busy_o
);
    localparam STAGES = 12;

    reg active_r;
    reg finish_r;
    reg started_r;
    reg step_r;
    reg draw_r;
    reg published_r;
    reg [63:0] live_r;
    reg [511:0] targets_r;
    reg [23:0] hit_max_r;
    reg [23:0] free_max_r;
    reg [26:0] hit_count_r;
    reg [23:0] free_count_r;
    reg [23:0] alive_count_r;

    // The registered occupancy breaks the ready path at the unit boundary.
    reg [255:0] ingress_data_r [0:1];
    reg [23:0] ingress_idx_r [0:1];
    reg ingress_read_r;
    reg ingress_write_r;
    reg [1:0] ingress_count_r;
    wire ingress_push_w;
    wire ingress_pop_w;
    wire advance_w;
    wire outputs_retired_w;
    reg [STAGES-1:0] valid_r;
    reg update_pending_r;
    reg event_pending_r;
    reg quad_pending_r;

    reg [255:0] record_r [0:STAGES-1];
    reg [23:0] idx_r [0:STAGES-1];
    reg [STAGES-1:0] original_alive_r;
    reg [15:0] acceleration_x_r;
    reg [15:0] acceleration_y_r;
    reg [12:0] position_low_x_r;
    reg [12:0] position_low_y_r;
    reg signed [17:0] collision_x0_r;
    reg signed [17:0] collision_x1_r;
    reg signed [17:0] collision_y0_r;
    reg signed [17:0] collision_y1_r;
    reg [7:0] hit_r [6:STAGES-1];
    reg [2:0] hit_low_r;
    reg [2:0] hit_high_r;
    reg [3:0] hit_sum_r [8:STAGES-1];
    reg [127:0] quad_data_r [9:STAGES-1];
    reg [16:0] quad_x_r [9:STAGES-1];
    reg [16:0] quad_y_r [9:STAGES-1];
    wire [11:0] velocity_upper_x_w;
    wire [11:0] velocity_upper_y_w;
    wire signed [17:0] position_x_w;
    wire signed [17:0] position_y_w;
    wire [7:0] collision_hit_w;
    wire [15:0] rounded_x_w;
    wire [15:0] rounded_y_w;
    wire [2:0] count_low_w;
    wire [2:0] count_high_w;
    integer stage_r;
    genvar target;

    // DMA adapters own list bases; only capacities participate in this core.
    wire unused_snapshot_w;
    assign unused_snapshot_w = ^{object_cfg_hit_base_i, object_cfg_free_base_i,
                                    draw_command_i[255:34], draw_command_i[31:0]};

    // spec 2.12: signed nearest rounding, ties away from zero.
    function [15:0] rounded_acceleration;
        input [15:0] acceleration_i;
        reg [16:0] magnitude;
        reg [16:0] unused_rounded;
        begin
            magnitude = acceleration_i[15] ? -{1'b1, acceleration_i} : {1'b0, acceleration_i};
            unused_rounded = (magnitude + 17'd8) >> 4;
            rounded_acceleration = acceleration_i[15] ?
                -unused_rounded[15:0] : unused_rounded[15:0];
        end
    endfunction

    function [2:0] count_four;
        input [3:0] mask_i;
        begin
            count_four = {2'b0, mask_i[0]} + {2'b0, mask_i[1]}
                        + {2'b0, mask_i[2]} + {2'b0, mask_i[3]};
        end
    endfunction

    assign rounded_x_w = rounded_acceleration(ingress_data_r[ingress_read_r][143:128]);
    assign rounded_y_w = rounded_acceleration(ingress_data_r[ingress_read_r][159:144]);
    assign count_low_w = count_four(hit_r[6][3:0]);
    assign count_high_w = count_four(hit_r[6][7:4]);

    assign object_cfg_ready_o = !active_r;
    assign draw_ready_o = active_r && !started_r && !stop_i;
    assign object_record_ready_o = stop_i ||
                                    (started_r && !unit_done_o && ingress_count_r < 2);
    assign ingress_push_w = object_record_valid_i && object_record_ready_o && !stop_i;
    assign ingress_pop_w = advance_w && (ingress_count_r != 0);
    assign outputs_retired_w = (!update_pending_r || object_update_ready_i) &&
                                (!event_pending_r || object_event_ready_i) &&
                                (!quad_pending_r || object_quad_ready_i);
    assign advance_w = outputs_retired_w && !stop_i;

    assign object_update_valid_o = update_pending_r && !stop_i;
    assign object_update_idx_o = idx_r[11];
    assign object_update_data_o = record_r[11];
    assign object_event_valid_o = event_pending_r && !stop_i;
    assign object_event_idx_o = idx_r[11];
    assign object_event_hit_o = hit_r[11];
    assign object_event_free_o = original_alive_r[11] && !record_r[11][0];
    assign object_quad_valid_o = quad_pending_r && !stop_i;
    assign object_quad_data_o = quad_data_r[11];
    assign object_quad_x_o = quad_x_r[11];
    assign object_quad_y_o = quad_y_r[11];
    assign object_result_hit_count_o = hit_count_r[23:0];
    assign object_result_free_count_o = free_count_r;
    assign object_result_alive_count_o = alive_count_r;
    assign object_result_overflow_o = {free_count_r > free_max_r,
                                        hit_count_r > {3'b0, hit_max_r}};
    assign perf_object_busy_o = active_r && !unit_done_o;

    assign velocity_upper_x_w = {{8{record_r[2][111]}}, record_r[2][111:108]};
    assign velocity_upper_y_w = {{8{record_r[2][127]}}, record_r[2][127:124]};
    assign position_x_w = {{2{record_r[4][55]}}, record_r[4][55:40]};
    assign position_y_w = {{2{record_r[4][87]}}, record_r[4][87:72]};

    generate
        for (target = 0; target < 8; target = target + 1) begin : g_target
            wire signed [17:0] x0_w;
            wire signed [17:0] y0_w;
            wire signed [17:0] x1_w;
            wire signed [17:0] y1_w;
            assign x0_w = {{2{targets_r[target*64+15]}}, targets_r[target*64 +: 16]};
            assign y0_w = {{2{targets_r[target*64+31]}}, targets_r[target*64+16 +: 16]};
            assign x1_w = {{2{targets_r[target*64+47]}}, targets_r[target*64+32 +: 16]};
            assign y1_w = {{2{targets_r[target*64+63]}}, targets_r[target*64+48 +: 16]};
            // spec 2.9: the strict inequalities exclude touching edges.
            assign collision_hit_w[target] = step_r && record_r[5][0] &&
                record_r[5][8+target] && collision_x0_r < x1_w && x0_w < collision_x1_r &&
                collision_y0_r < y1_w && y0_w < collision_y1_r;
        end
    endgenerate

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            finish_r <= 1'b1;
            active_r <= 1'b0;
            started_r <= 1'b0;
            published_r <= 1'b0;
            unit_done_o <= 1'b1;
            object_result_valid_o <= 1'b0;
            hit_count_r <= 27'd0;
            free_count_r <= 24'd0;
            alive_count_r <= 24'd0;
        end else begin
            finish_r <= finish_i;
            if (object_cfg_valid_i && object_cfg_ready_o) begin
                active_r <= 1'b1;
                started_r <= 1'b0;
                published_r <= 1'b0;
                unit_done_o <= 1'b0;
                hit_count_r <= 27'd0;
                free_count_r <= 24'd0;
                alive_count_r <= 24'd0;
            end
            if (draw_valid_i && draw_ready_o)
                started_r <= 1'b1;
            if (advance_w && valid_r[11]) begin
                hit_count_r <= hit_count_r + {23'd0, hit_sum_r[11]};
                free_count_r <= free_count_r +
                                {23'd0, (step_r && object_event_free_o)};
                alive_count_r <= alive_count_r + {23'd0, record_r[11][0]};
            end
            if (finish_i && (!active_r || (started_r && ingress_count_r == 0 && valid_r == 0)))
                unit_done_o <= 1'b1;
            // microarch 4.2: falling finish starts every command, including no-cfg commands.
            if (finish_r && !finish_i) unit_done_o <= 1'b0;
            // Publication follows command's DMA-B and rendering drain barrier.
            if (active_r && unit_done_o && object_publish_i && !published_r && !stop_i) begin
                object_result_valid_o <= 1'b1;
                published_r <= 1'b1;
            end
            if (object_result_valid_o && object_result_ready_i) begin
                object_result_valid_o <= 1'b0;
                active_r <= 1'b0;
            end
            if (stop_i) begin
                unit_done_o <= 1'b1;
                object_result_valid_o <= 1'b0;
                active_r <= 1'b0;
                started_r <= 1'b0;
            end
        end
    end

    always @(posedge clk_i) begin
        if (object_cfg_valid_i && object_cfg_ready_o) begin
            live_r <= object_cfg_live_i;
            targets_r <= object_cfg_targets_i;
            hit_max_r <= object_cfg_hit_max_i;
            free_max_r <= object_cfg_free_max_i;
        end
        if (draw_valid_i && draw_ready_o) begin
            step_r <= draw_command_i[32];
            draw_r <= draw_command_i[33];
        end
        if (ingress_push_w) begin
            ingress_data_r[ingress_write_r] <= object_record_data_i;
            ingress_idx_r[ingress_write_r] <= object_record_idx_i;
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            ingress_count_r <= 2'd0;
            ingress_read_r <= 1'b0;
            ingress_write_r <= 1'b0;
            valid_r <= 12'd0;
            update_pending_r <= 1'b0;
            event_pending_r <= 1'b0;
            quad_pending_r <= 1'b0;
        end else if (stop_i) begin
            ingress_count_r <= 2'd0;
            ingress_read_r <= 1'b0;
            ingress_write_r <= 1'b0;
            valid_r <= 12'd0;
            update_pending_r <= 1'b0;
            event_pending_r <= 1'b0;
            quad_pending_r <= 1'b0;
        end else begin
            if (ingress_push_w)
                ingress_write_r <= !ingress_write_r;
            if (ingress_pop_w)
                ingress_read_r <= !ingress_read_r;
            if (advance_w) begin
                valid_r <= {valid_r[10:0], ingress_pop_w};
                update_pending_r <= valid_r[10] && step_r && original_alive_r[10];
                event_pending_r <= valid_r[10] && step_r;
                quad_pending_r <= valid_r[10] && draw_r && record_r[10][0];
            end else begin
                if (object_update_ready_i)
                    update_pending_r <= 1'b0;
                if (object_event_ready_i)
                    event_pending_r <= 1'b0;
                if (object_quad_ready_i)
                    quad_pending_r <= 1'b0;
            end
            case ({ingress_push_w, ingress_pop_w})
                2'b10: ingress_count_r <= ingress_count_r + 2'd1;
                2'b01: ingress_count_r <= ingress_count_r - 2'd1;
                default: ingress_count_r <= ingress_count_r;
            endcase
        end
    end

    // Data has no reset. Each stage transforms only its owned fields, preserving all others.
    always @(posedge clk_i) begin
        if (advance_w) begin
            record_r[0] <= ingress_data_r[ingress_read_r];
            idx_r[0] <= ingress_idx_r[ingress_read_r];
            original_alive_r[0] <= ingress_data_r[ingress_read_r][0];
            acceleration_x_r <= rounded_x_w;
            acceleration_y_r <= rounded_y_w;
            for (stage_r = 1; stage_r < STAGES; stage_r = stage_r + 1) begin
                record_r[stage_r] <= record_r[stage_r-1];
                idx_r[stage_r] <= idx_r[stage_r-1];
                original_alive_r[stage_r] <= original_alive_r[stage_r-1];
            end
            if (step_r && record_r[0][0]) begin
                record_r[1][111:96] <= record_r[0][111:96] + acceleration_x_r;
                record_r[1][127:112] <= record_r[0][127:112] + acceleration_y_r;
            end
            // Two stages for 24-bit position addition; carries survive the split.
            position_low_x_r <= {1'b0, record_r[1][43:32]} +
                                {1'b0, record_r[1][107:96]};
            position_low_y_r <= {1'b0, record_r[1][75:64]} +
                                {1'b0, record_r[1][123:112]};
            if (step_r && record_r[2][0]) begin
                record_r[3][43:32] <= position_low_x_r[11:0];
                record_r[3][55:44] <= record_r[2][55:44] + velocity_upper_x_w +
                                        {11'd0, position_low_x_r[12]};
                record_r[3][75:64] <= position_low_y_r[11:0];
                record_r[3][87:76] <= record_r[2][87:76] + velocity_upper_y_w +
                                        {11'd0, position_low_y_r[12]};
            end
            if (step_r && record_r[3][0]) begin
                if (record_r[3][31:16] != 0)
                    record_r[4][31:16] <= record_r[3][31:16] - 16'd1;
                record_r[4][0] <= record_r[3][31:16] != 16'd1 &&
                    $signed(record_r[3][55:40]) >= $signed(live_r[15:0]) &&
                    $signed(record_r[3][55:40]) < $signed(live_r[47:32]) &&
                    $signed(record_r[3][87:72]) >= $signed(live_r[31:16]) &&
                    $signed(record_r[3][87:72]) < $signed(live_r[63:48]);
            end
            collision_x0_r <= position_x_w - $signed({10'd0, record_r[4][167:160]});
            collision_x1_r <= position_x_w + $signed({10'd0, record_r[4][167:160]});
            collision_y0_r <= position_y_w - $signed({10'd0, record_r[4][175:168]});
            collision_y1_r <= position_y_w + $signed({10'd0, record_r[4][175:168]});
            hit_r[6] <= collision_hit_w;
            for (stage_r = 7; stage_r < STAGES; stage_r = stage_r + 1)
                hit_r[stage_r] <= hit_r[stage_r-1];
            hit_low_r <= count_low_w;
            hit_high_r <= count_high_w;
            hit_sum_r[8] <= {1'b0, hit_low_r} + {1'b0, hit_high_r};
            for (stage_r = 9; stage_r < STAGES; stage_r = stage_r + 1)
                hit_sum_r[stage_r] <= hit_sum_r[stage_r-1];
            // QUAD position bits are unused; non-position fields use gpu.json's layout.
            quad_data_r[9] <= {32'd0, record_r[8][255:224], 6'd0,
                                record_r[8][223:216], record_r[8][209:192],
                                2'd0, record_r[8][215:210], 24'd0};
            quad_x_r[9] <= $signed({record_r[8][55], record_r[8][55:40]}) -
                            $signed({9'd0, record_r[8][200:193]});
            quad_y_r[9] <= $signed({record_r[8][87], record_r[8][87:72]}) -
                            $signed({9'd0, record_r[8][209:202]});
            for (stage_r = 10; stage_r < STAGES; stage_r = stage_r + 1) begin
                quad_data_r[stage_r] <= quad_data_r[stage_r-1];
                quad_x_r[stage_r] <= quad_x_r[stage_r-1];
                quad_y_r[stage_r] <= quad_y_r[stage_r-1];
            end
        end
    end
endmodule
