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
    reg [23:0] hit_max_r;
    reg [23:0] free_max_r;
    reg [26:0] hit_count_r;
    reg [23:0] free_count_r;
    reg [23:0] alive_count_r;

    // The registered occupancy breaks the ready path at the unit boundary.
    wire [255:0] ingress_data_w;
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

    wire [255:0] record_w [0:STAGES-1];
    wire [23:0] idx_11_r;
    reg [8:0] index_write_r;
    wire [8:0] index_read_w;
    wire [71:0] unused_index_data_w;
    reg [STAGES-1:0] original_alive_r;
    reg [15:0] acceleration_x_r;
    reg [15:0] acceleration_y_r;
    reg [12:0] position_low_x_r;
    reg [12:0] position_low_y_r;
    reg signed [17:0] collision_x0_r;
    reg signed [17:0] collision_x1_r;
    reg signed [17:0] collision_y0_r;
    reg signed [17:0] collision_y1_r;
    reg [7:0] hit_6_r;
    reg [7:0] hit_7_r;
    reg [7:0] hit_8_r;
    reg [7:0] hit_9_r;
    reg [7:0] hit_10_r;
    reg [7:0] hit_11_r;
    reg [2:0] hit_low_r;
    reg [2:0] hit_high_r;
    reg [3:0] hit_sum_8_r;
    reg [3:0] hit_sum_9_r;
    reg [3:0] hit_sum_10_r;
    reg [3:0] hit_sum_11_r;
    reg [127:0] quad_data_9_r;
    reg [127:0] quad_data_10_r;
    reg [127:0] quad_data_11_r;
    reg [16:0] quad_x_9_r;
    reg [16:0] quad_x_10_r;
    reg [16:0] quad_x_11_r;
    reg [16:0] quad_y_9_r;
    reg [16:0] quad_y_10_r;
    reg [16:0] quad_y_11_r;
    wire [11:0] velocity_upper_x_w;
    wire [11:0] velocity_upper_y_w;
    wire signed [17:0] position_x_w;
    wire signed [17:0] position_y_w;
    wire [7:0] collision_hit_w;
    wire [15:0] rounded_x_w;
    wire [15:0] rounded_y_w;
    wire [2:0] count_low_w;
    wire [2:0] count_high_w;
    genvar stage;
    genvar target;

    // DMA adapters own list bases; only capacities participate in this core.
    wire unused_snapshot_w;
    assign unused_snapshot_w = ^{object_cfg_hit_base_i, object_cfg_free_base_i,
                                    draw_command_i[255:34], draw_command_i[31:0]};

    // Stage 0: two 16-bit signed rounding units; stage 7: two four-bit popcounts.
    // Stage 8: one 4-bit count sum; stages 5/6: four bounds adders, 8 x 4 comparisons.
    // spec 2.12: signed nearest rounding, ties away from zero.
    function [15:0] rounded_acceleration;
        input [15:0] acceleration_i;
        reg [15:0] magnitude;
        reg [15:0] unused_rounded;
        begin
            magnitude = acceleration_i[15] ? -acceleration_i : acceleration_i;
            unused_rounded = (magnitude + 16'd8) >> 4;
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

    // Index metadata advances with all twelve object stages, including their common stall.
    assign index_read_w = index_write_r - 9'd11;
    assign idx_11_r = unused_index_data_w[23:0];
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) index_write_r <= 0;
        else if (advance_w) index_write_r <= index_write_r + 1'b1;
    end
    edrv32_ram_gpu_delay u_index (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(index_write_r),
        .wr_data_i({48'b0, ingress_idx_r[ingress_read_r]}),
        .rd_en_i(advance_w),
        .rd_addr_i(index_read_w),
        .rd_data_o(unused_index_data_w)
    );

    assign rounded_x_w = rounded_acceleration(ingress_data_w[143:128]);
    assign rounded_y_w = rounded_acceleration(ingress_data_w[159:144]);
    assign count_low_w = count_four(hit_6_r[3:0]);
    assign count_high_w = count_four(hit_6_r[7:4]);

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
    assign object_update_idx_o = idx_11_r;
    assign object_update_data_o = record_w[11];
    assign object_event_valid_o = event_pending_r && !stop_i;
    assign object_event_idx_o = idx_11_r;
    assign object_event_hit_o = hit_11_r;
    assign object_event_free_o = original_alive_r[11] && !record_w[11][0];
    assign object_quad_valid_o = quad_pending_r && !stop_i;
    assign object_quad_data_o = quad_data_11_r;
    assign object_quad_x_o = quad_x_11_r;
    assign object_quad_y_o = quad_y_11_r;
    assign object_result_hit_count_o = hit_count_r[23:0];
    assign object_result_free_count_o = free_count_r;
    assign object_result_alive_count_o = alive_count_r;
    assign object_result_overflow_o = {free_count_r > free_max_r,
                                        hit_count_r > {3'b0, hit_max_r}};
    assign perf_object_busy_o = active_r && !unit_done_o;

    assign velocity_upper_x_w = {{8{record_w[2][111]}}, record_w[2][111:108]};
    assign velocity_upper_y_w = {{8{record_w[2][127]}}, record_w[2][127:124]};
    assign position_x_w = {{2{record_w[4][55]}}, record_w[4][55:40]};
    assign position_y_w = {{2{record_w[4][87]}}, record_w[4][87:72]};

    generate
        for (target = 0; target < 8; target = target + 1) begin : g_target
            wire signed [17:0] x0_w;
            wire signed [17:0] y0_w;
            wire signed [17:0] x1_w;
            wire signed [17:0] y1_w;
            reg [15:0] target_x0_r;
            assign x0_w = {{2{target_x0_r[15]}}, target_x0_r};
            reg [15:0] target_y0_r;
            assign y0_w = {{2{target_y0_r[15]}}, target_y0_r};
            reg [15:0] target_x1_r;
            assign x1_w = {{2{target_x1_r[15]}}, target_x1_r};
            reg [15:0] target_y1_r;
            assign y1_w = {{2{target_y1_r[15]}}, target_y1_r};
            // Configuration stage: eight independent four-coordinate target registers.
            always @(posedge clk_i) begin
                if (object_cfg_valid_i && object_cfg_ready_o) begin
                    target_x0_r <= object_cfg_targets_i[target*64+0 +: 16];
                    target_y0_r <= object_cfg_targets_i[target*64+16 +: 16];
                    target_x1_r <= object_cfg_targets_i[target*64+32 +: 16];
                    target_y1_r <= object_cfg_targets_i[target*64+48 +: 16];
                end
            end
            // spec 2.9: the strict inequalities exclude touching edges.
            assign collision_hit_w[target] = step_r && record_w[5][0] &&
                record_w[5][8+target] && collision_x0_r < x1_w && x0_w < collision_x1_r &&
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
                hit_count_r <= hit_count_r + {23'd0, hit_sum_11_r};
                free_count_r <= free_count_r +
                                {23'd0, (step_r && object_event_free_o)};
                alive_count_r <= alive_count_r + {23'd0, record_w[11][0]};
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
            hit_max_r <= object_cfg_hit_max_i;
            free_max_r <= object_cfg_free_max_i;
        end
        if (draw_valid_i && draw_ready_o) begin
            step_r <= draw_command_i[32];
            draw_r <= draw_command_i[33];
        end
        if (ingress_push_w) begin
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
                quad_pending_r <= valid_r[10] && draw_r && record_w[10][0];
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
            original_alive_r[0] <= ingress_data_w[0];
            original_alive_r[1] <= original_alive_r[0];
            original_alive_r[2] <= original_alive_r[1];
            original_alive_r[3] <= original_alive_r[2];
            original_alive_r[4] <= original_alive_r[3];
            original_alive_r[5] <= original_alive_r[4];
            original_alive_r[6] <= original_alive_r[5];
            original_alive_r[7] <= original_alive_r[6];
            original_alive_r[8] <= original_alive_r[7];
            original_alive_r[9] <= original_alive_r[8];
            original_alive_r[10] <= original_alive_r[9];
            original_alive_r[11] <= original_alive_r[10];
            hit_6_r <= collision_hit_w;
            hit_7_r <= hit_6_r;
            hit_8_r <= hit_7_r;
            hit_9_r <= hit_8_r;
            hit_10_r <= hit_9_r;
            hit_11_r <= hit_10_r;
            hit_sum_8_r <= {1'b0, hit_low_r} + {1'b0, hit_high_r};
            hit_sum_9_r <= hit_sum_8_r;
            hit_sum_10_r <= hit_sum_9_r;
            hit_sum_11_r <= hit_sum_10_r;
            // QUAD position bits are unused; other fields follow gpu.json.
            quad_data_9_r <= {32'd0, record_w[8][255:224], 6'd0,
                                record_w[8][223:216], record_w[8][209:192],
                                2'd0, record_w[8][215:210], 24'd0};
            quad_x_9_r <= $signed({record_w[8][55], record_w[8][55:40]}) -
                            $signed({9'd0, record_w[8][200:193]});
            quad_y_9_r <= $signed({record_w[8][87], record_w[8][87:72]}) -
                            $signed({9'd0, record_w[8][209:202]});
            quad_data_10_r <= quad_data_9_r;
            quad_x_10_r <= quad_x_9_r;
            quad_y_10_r <= quad_y_9_r;
            quad_data_11_r <= quad_data_10_r;
            quad_x_11_r <= quad_x_10_r;
            quad_y_11_r <= quad_y_10_r;
            acceleration_x_r <= rounded_x_w;
            acceleration_y_r <= rounded_y_w;
            // Two stages for 24-bit position addition; carries survive the split.
            position_low_x_r <= {1'b0, record_w[1][43:32]} +
                                {1'b0, record_w[1][107:96]};
            position_low_y_r <= {1'b0, record_w[1][75:64]} +
                                {1'b0, record_w[1][123:112]};
            collision_x0_r <= position_x_w - $signed({10'd0, record_w[4][167:160]});
            collision_x1_r <= position_x_w + $signed({10'd0, record_w[4][167:160]});
            collision_y0_r <= position_y_w - $signed({10'd0, record_w[4][175:168]});
            collision_y1_r <= position_y_w + $signed({10'd0, record_w[4][175:168]});
            hit_low_r <= count_low_w;
            hit_high_r <= count_high_w;
        end
    end
    // Twelve stages, each with independent field registers; only owned fields change.
    // Stage 1: two 16-bit velocity adders; stage 3: two 12-bit carry additions.
    // Stage 4: one lifetime decrement and four signed live-bound comparisons.
    generate
        begin : g_alive
            (* keep = 1 *) reg region_update_pending_r /* synthesis syn_preserve=1 */;
            (* keep = 1 *) reg region_event_pending_r /* synthesis syn_preserve=1 */;
            (* keep = 1 *) reg region_quad_pending_r /* synthesis syn_preserve=1 */;
            wire region_advance_w;
            assign region_advance_w = (!region_update_pending_r || object_update_ready_i) &&
                (!region_event_pending_r || object_event_ready_i) &&
                (!region_quad_pending_r || object_quad_ready_i) && !stop_i;
            (* keep = 1 *) always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    region_update_pending_r <= 0;
                    region_event_pending_r <= 0;
                    region_quad_pending_r <= 0;
                end else if (stop_i) begin
                    region_update_pending_r <= 0;
                    region_event_pending_r <= 0;
                    region_quad_pending_r <= 0;
                end else if (region_advance_w) begin
                    region_update_pending_r <= valid_r[10] && step_r && original_alive_r[10];
                    region_event_pending_r <= valid_r[10] && step_r;
                    region_quad_pending_r <= valid_r[10] && draw_r && record_w[10][0];
                end else begin
                    if (object_update_ready_i) region_update_pending_r <= 0;
                    if (object_event_ready_i) region_event_pending_r <= 0;
                    if (object_quad_ready_i) region_quad_pending_r <= 0;
                end
            end
            reg [0:0] ingress_r [0:1];
            assign ingress_data_w[0:0] = ingress_r[ingress_read_r];
            always @(posedge clk_i) begin
                if (ingress_push_w) ingress_r[ingress_write_r] <= object_record_data_i[0:0];
            end
            for (stage = 0; stage < STAGES; stage = stage + 1) begin : g_stage
                reg [0:0] data_r;
                reg [0:0] data_w;
                assign record_w[stage][0:0] = data_r;
                always @(*) begin
                    data_w = 0;
                    if (stage == 0) begin
                        data_w = ingress_data_w[0:0];
                    end else begin
                        data_w = record_w[stage-1][0:0];
                        if (stage == 4 && step_r && record_w[3][0])
                            data_w = record_w[3][31:16] != 16'd1 &&
                                $signed(record_w[3][55:40]) >= $signed(live_r[15:0]) &&
                                $signed(record_w[3][55:40]) < $signed(live_r[47:32]) &&
                                $signed(record_w[3][87:72]) >= $signed(live_r[31:16]) &&
                                $signed(record_w[3][87:72]) < $signed(live_r[63:48]);
                    end
                end
                always @(posedge clk_i) begin
                    if (region_advance_w) data_r <= data_w;
                end
            end
        end
        begin : g_flags
            (* keep = 1 *) reg region_update_pending_r /* synthesis syn_preserve=1 */;
            (* keep = 1 *) reg region_event_pending_r /* synthesis syn_preserve=1 */;
            (* keep = 1 *) reg region_quad_pending_r /* synthesis syn_preserve=1 */;
            wire region_advance_w;
            assign region_advance_w = (!region_update_pending_r || object_update_ready_i) &&
                (!region_event_pending_r || object_event_ready_i) &&
                (!region_quad_pending_r || object_quad_ready_i) && !stop_i;
            (* keep = 1 *) always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    region_update_pending_r <= 0;
                    region_event_pending_r <= 0;
                    region_quad_pending_r <= 0;
                end else if (stop_i) begin
                    region_update_pending_r <= 0;
                    region_event_pending_r <= 0;
                    region_quad_pending_r <= 0;
                end else if (region_advance_w) begin
                    region_update_pending_r <= valid_r[10] && step_r && original_alive_r[10];
                    region_event_pending_r <= valid_r[10] && step_r;
                    region_quad_pending_r <= valid_r[10] && draw_r && record_w[10][0];
                end else begin
                    if (object_update_ready_i) region_update_pending_r <= 0;
                    if (object_event_ready_i) region_event_pending_r <= 0;
                    if (object_quad_ready_i) region_quad_pending_r <= 0;
                end
            end
            reg [14:0] ingress_r [0:1];
            assign ingress_data_w[15:1] = ingress_r[ingress_read_r];
            always @(posedge clk_i) begin
                if (ingress_push_w) ingress_r[ingress_write_r] <= object_record_data_i[15:1];
            end
            for (stage = 0; stage < STAGES; stage = stage + 1) begin : g_stage
                reg [14:0] data_r;
                reg [14:0] data_w;
                assign record_w[stage][15:1] = data_r;
                always @(*) begin
                    data_w = 0;
                    if (stage == 0) begin
                        data_w = ingress_data_w[15:1];
                    end else begin
                        data_w = record_w[stage-1][15:1];
                    end
                end
                always @(posedge clk_i) begin
                    if (region_advance_w) data_r <= data_w;
                end
            end
        end
        begin : g_lifetime
            (* keep = 1 *) reg region_update_pending_r /* synthesis syn_preserve=1 */;
            (* keep = 1 *) reg region_event_pending_r /* synthesis syn_preserve=1 */;
            (* keep = 1 *) reg region_quad_pending_r /* synthesis syn_preserve=1 */;
            wire region_advance_w;
            assign region_advance_w = (!region_update_pending_r || object_update_ready_i) &&
                (!region_event_pending_r || object_event_ready_i) &&
                (!region_quad_pending_r || object_quad_ready_i) && !stop_i;
            (* keep = 1 *) always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    region_update_pending_r <= 0;
                    region_event_pending_r <= 0;
                    region_quad_pending_r <= 0;
                end else if (stop_i) begin
                    region_update_pending_r <= 0;
                    region_event_pending_r <= 0;
                    region_quad_pending_r <= 0;
                end else if (region_advance_w) begin
                    region_update_pending_r <= valid_r[10] && step_r && original_alive_r[10];
                    region_event_pending_r <= valid_r[10] && step_r;
                    region_quad_pending_r <= valid_r[10] && draw_r && record_w[10][0];
                end else begin
                    if (object_update_ready_i) region_update_pending_r <= 0;
                    if (object_event_ready_i) region_event_pending_r <= 0;
                    if (object_quad_ready_i) region_quad_pending_r <= 0;
                end
            end
            reg [15:0] ingress_r [0:1];
            assign ingress_data_w[31:16] = ingress_r[ingress_read_r];
            always @(posedge clk_i) begin
                if (ingress_push_w) ingress_r[ingress_write_r] <= object_record_data_i[31:16];
            end
            for (stage = 0; stage < STAGES; stage = stage + 1) begin : g_stage
                reg [15:0] data_r;
                reg [15:0] data_w;
                assign record_w[stage][31:16] = data_r;
                always @(*) begin
                    data_w = 0;
                    if (stage == 0) begin
                        data_w = ingress_data_w[31:16];
                    end else begin
                        data_w = record_w[stage-1][31:16];
                        if (stage == 4 && step_r && record_w[3][0] && record_w[3][31:16] != 0)
                            data_w = record_w[3][31:16] - 16'd1;
                    end
                end
                always @(posedge clk_i) begin
                    if (region_advance_w) data_r <= data_w;
                end
            end
        end
        begin : g_position_x
            (* keep = 1 *) reg region_update_pending_r /* synthesis syn_preserve=1 */;
            (* keep = 1 *) reg region_event_pending_r /* synthesis syn_preserve=1 */;
            (* keep = 1 *) reg region_quad_pending_r /* synthesis syn_preserve=1 */;
            wire region_advance_w;
            assign region_advance_w = (!region_update_pending_r || object_update_ready_i) &&
                (!region_event_pending_r || object_event_ready_i) &&
                (!region_quad_pending_r || object_quad_ready_i) && !stop_i;
            (* keep = 1 *) always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    region_update_pending_r <= 0;
                    region_event_pending_r <= 0;
                    region_quad_pending_r <= 0;
                end else if (stop_i) begin
                    region_update_pending_r <= 0;
                    region_event_pending_r <= 0;
                    region_quad_pending_r <= 0;
                end else if (region_advance_w) begin
                    region_update_pending_r <= valid_r[10] && step_r && original_alive_r[10];
                    region_event_pending_r <= valid_r[10] && step_r;
                    region_quad_pending_r <= valid_r[10] && draw_r && record_w[10][0];
                end else begin
                    if (object_update_ready_i) region_update_pending_r <= 0;
                    if (object_event_ready_i) region_event_pending_r <= 0;
                    if (object_quad_ready_i) region_quad_pending_r <= 0;
                end
            end
            reg [23:0] ingress_r [0:1];
            assign ingress_data_w[55:32] = ingress_r[ingress_read_r];
            always @(posedge clk_i) begin
                if (ingress_push_w) ingress_r[ingress_write_r] <= object_record_data_i[55:32];
            end
            for (stage = 0; stage < STAGES; stage = stage + 1) begin : g_stage
                reg [23:0] data_r;
                reg [23:0] data_w;
                assign record_w[stage][55:32] = data_r;
                always @(*) begin
                    data_w = 0;
                    if (stage == 0) begin
                        data_w = ingress_data_w[55:32];
                    end else begin
                        data_w = record_w[stage-1][55:32];
                        if (stage == 3 && step_r && record_w[2][0])
                            data_w = {record_w[2][55:44] + velocity_upper_x_w +
                                {11'd0, position_low_x_r[12]}, position_low_x_r[11:0]};
                    end
                end
                always @(posedge clk_i) begin
                    if (region_advance_w) data_r <= data_w;
                end
            end
        end
        begin : g_reserved_x
            (* keep = 1 *) reg region_update_pending_r /* synthesis syn_preserve=1 */;
            (* keep = 1 *) reg region_event_pending_r /* synthesis syn_preserve=1 */;
            (* keep = 1 *) reg region_quad_pending_r /* synthesis syn_preserve=1 */;
            wire region_advance_w;
            assign region_advance_w = (!region_update_pending_r || object_update_ready_i) &&
                (!region_event_pending_r || object_event_ready_i) &&
                (!region_quad_pending_r || object_quad_ready_i) && !stop_i;
            (* keep = 1 *) always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    region_update_pending_r <= 0;
                    region_event_pending_r <= 0;
                    region_quad_pending_r <= 0;
                end else if (stop_i) begin
                    region_update_pending_r <= 0;
                    region_event_pending_r <= 0;
                    region_quad_pending_r <= 0;
                end else if (region_advance_w) begin
                    region_update_pending_r <= valid_r[10] && step_r && original_alive_r[10];
                    region_event_pending_r <= valid_r[10] && step_r;
                    region_quad_pending_r <= valid_r[10] && draw_r && record_w[10][0];
                end else begin
                    if (object_update_ready_i) region_update_pending_r <= 0;
                    if (object_event_ready_i) region_event_pending_r <= 0;
                    if (object_quad_ready_i) region_quad_pending_r <= 0;
                end
            end
            reg [7:0] ingress_r [0:1];
            assign ingress_data_w[63:56] = ingress_r[ingress_read_r];
            always @(posedge clk_i) begin
                if (ingress_push_w) ingress_r[ingress_write_r] <= object_record_data_i[63:56];
            end
            for (stage = 0; stage < STAGES; stage = stage + 1) begin : g_stage
                reg [7:0] data_r;
                reg [7:0] data_w;
                assign record_w[stage][63:56] = data_r;
                always @(*) begin
                    data_w = 0;
                    if (stage == 0) begin
                        data_w = ingress_data_w[63:56];
                    end else begin
                        data_w = record_w[stage-1][63:56];
                    end
                end
                always @(posedge clk_i) begin
                    if (region_advance_w) data_r <= data_w;
                end
            end
        end
        begin : g_position_y
            (* keep = 1 *) reg region_update_pending_r /* synthesis syn_preserve=1 */;
            (* keep = 1 *) reg region_event_pending_r /* synthesis syn_preserve=1 */;
            (* keep = 1 *) reg region_quad_pending_r /* synthesis syn_preserve=1 */;
            wire region_advance_w;
            assign region_advance_w = (!region_update_pending_r || object_update_ready_i) &&
                (!region_event_pending_r || object_event_ready_i) &&
                (!region_quad_pending_r || object_quad_ready_i) && !stop_i;
            (* keep = 1 *) always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    region_update_pending_r <= 0;
                    region_event_pending_r <= 0;
                    region_quad_pending_r <= 0;
                end else if (stop_i) begin
                    region_update_pending_r <= 0;
                    region_event_pending_r <= 0;
                    region_quad_pending_r <= 0;
                end else if (region_advance_w) begin
                    region_update_pending_r <= valid_r[10] && step_r && original_alive_r[10];
                    region_event_pending_r <= valid_r[10] && step_r;
                    region_quad_pending_r <= valid_r[10] && draw_r && record_w[10][0];
                end else begin
                    if (object_update_ready_i) region_update_pending_r <= 0;
                    if (object_event_ready_i) region_event_pending_r <= 0;
                    if (object_quad_ready_i) region_quad_pending_r <= 0;
                end
            end
            reg [23:0] ingress_r [0:1];
            assign ingress_data_w[87:64] = ingress_r[ingress_read_r];
            always @(posedge clk_i) begin
                if (ingress_push_w) ingress_r[ingress_write_r] <= object_record_data_i[87:64];
            end
            for (stage = 0; stage < STAGES; stage = stage + 1) begin : g_stage
                reg [23:0] data_r;
                reg [23:0] data_w;
                assign record_w[stage][87:64] = data_r;
                always @(*) begin
                    data_w = 0;
                    if (stage == 0) begin
                        data_w = ingress_data_w[87:64];
                    end else begin
                        data_w = record_w[stage-1][87:64];
                        if (stage == 3 && step_r && record_w[2][0])
                            data_w = {record_w[2][87:76] + velocity_upper_y_w +
                                {11'd0, position_low_y_r[12]}, position_low_y_r[11:0]};
                    end
                end
                always @(posedge clk_i) begin
                    if (region_advance_w) data_r <= data_w;
                end
            end
        end
        begin : g_reserved_y
            (* keep = 1 *) reg region_update_pending_r /* synthesis syn_preserve=1 */;
            (* keep = 1 *) reg region_event_pending_r /* synthesis syn_preserve=1 */;
            (* keep = 1 *) reg region_quad_pending_r /* synthesis syn_preserve=1 */;
            wire region_advance_w;
            assign region_advance_w = (!region_update_pending_r || object_update_ready_i) &&
                (!region_event_pending_r || object_event_ready_i) &&
                (!region_quad_pending_r || object_quad_ready_i) && !stop_i;
            (* keep = 1 *) always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    region_update_pending_r <= 0;
                    region_event_pending_r <= 0;
                    region_quad_pending_r <= 0;
                end else if (stop_i) begin
                    region_update_pending_r <= 0;
                    region_event_pending_r <= 0;
                    region_quad_pending_r <= 0;
                end else if (region_advance_w) begin
                    region_update_pending_r <= valid_r[10] && step_r && original_alive_r[10];
                    region_event_pending_r <= valid_r[10] && step_r;
                    region_quad_pending_r <= valid_r[10] && draw_r && record_w[10][0];
                end else begin
                    if (object_update_ready_i) region_update_pending_r <= 0;
                    if (object_event_ready_i) region_event_pending_r <= 0;
                    if (object_quad_ready_i) region_quad_pending_r <= 0;
                end
            end
            reg [7:0] ingress_r [0:1];
            assign ingress_data_w[95:88] = ingress_r[ingress_read_r];
            always @(posedge clk_i) begin
                if (ingress_push_w) ingress_r[ingress_write_r] <= object_record_data_i[95:88];
            end
            for (stage = 0; stage < STAGES; stage = stage + 1) begin : g_stage
                reg [7:0] data_r;
                reg [7:0] data_w;
                assign record_w[stage][95:88] = data_r;
                always @(*) begin
                    data_w = 0;
                    if (stage == 0) begin
                        data_w = ingress_data_w[95:88];
                    end else begin
                        data_w = record_w[stage-1][95:88];
                    end
                end
                always @(posedge clk_i) begin
                    if (region_advance_w) data_r <= data_w;
                end
            end
        end
        begin : g_velocity_x
            (* keep = 1 *) reg region_update_pending_r /* synthesis syn_preserve=1 */;
            (* keep = 1 *) reg region_event_pending_r /* synthesis syn_preserve=1 */;
            (* keep = 1 *) reg region_quad_pending_r /* synthesis syn_preserve=1 */;
            wire region_advance_w;
            assign region_advance_w = (!region_update_pending_r || object_update_ready_i) &&
                (!region_event_pending_r || object_event_ready_i) &&
                (!region_quad_pending_r || object_quad_ready_i) && !stop_i;
            (* keep = 1 *) always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    region_update_pending_r <= 0;
                    region_event_pending_r <= 0;
                    region_quad_pending_r <= 0;
                end else if (stop_i) begin
                    region_update_pending_r <= 0;
                    region_event_pending_r <= 0;
                    region_quad_pending_r <= 0;
                end else if (region_advance_w) begin
                    region_update_pending_r <= valid_r[10] && step_r && original_alive_r[10];
                    region_event_pending_r <= valid_r[10] && step_r;
                    region_quad_pending_r <= valid_r[10] && draw_r && record_w[10][0];
                end else begin
                    if (object_update_ready_i) region_update_pending_r <= 0;
                    if (object_event_ready_i) region_event_pending_r <= 0;
                    if (object_quad_ready_i) region_quad_pending_r <= 0;
                end
            end
            reg [15:0] ingress_r [0:1];
            assign ingress_data_w[111:96] = ingress_r[ingress_read_r];
            always @(posedge clk_i) begin
                if (ingress_push_w) ingress_r[ingress_write_r] <= object_record_data_i[111:96];
            end
            for (stage = 0; stage < STAGES; stage = stage + 1) begin : g_stage
                reg [15:0] data_r;
                reg [15:0] data_w;
                assign record_w[stage][111:96] = data_r;
                always @(*) begin
                    data_w = 0;
                    if (stage == 0) begin
                        data_w = ingress_data_w[111:96];
                    end else begin
                        data_w = record_w[stage-1][111:96];
                        if (stage == 1 && step_r && record_w[0][0])
                            data_w = record_w[0][111:96] + acceleration_x_r;
                    end
                end
                always @(posedge clk_i) begin
                    if (region_advance_w) data_r <= data_w;
                end
            end
        end
        begin : g_velocity_y
            (* keep = 1 *) reg region_update_pending_r /* synthesis syn_preserve=1 */;
            (* keep = 1 *) reg region_event_pending_r /* synthesis syn_preserve=1 */;
            (* keep = 1 *) reg region_quad_pending_r /* synthesis syn_preserve=1 */;
            wire region_advance_w;
            assign region_advance_w = (!region_update_pending_r || object_update_ready_i) &&
                (!region_event_pending_r || object_event_ready_i) &&
                (!region_quad_pending_r || object_quad_ready_i) && !stop_i;
            (* keep = 1 *) always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    region_update_pending_r <= 0;
                    region_event_pending_r <= 0;
                    region_quad_pending_r <= 0;
                end else if (stop_i) begin
                    region_update_pending_r <= 0;
                    region_event_pending_r <= 0;
                    region_quad_pending_r <= 0;
                end else if (region_advance_w) begin
                    region_update_pending_r <= valid_r[10] && step_r && original_alive_r[10];
                    region_event_pending_r <= valid_r[10] && step_r;
                    region_quad_pending_r <= valid_r[10] && draw_r && record_w[10][0];
                end else begin
                    if (object_update_ready_i) region_update_pending_r <= 0;
                    if (object_event_ready_i) region_event_pending_r <= 0;
                    if (object_quad_ready_i) region_quad_pending_r <= 0;
                end
            end
            reg [15:0] ingress_r [0:1];
            assign ingress_data_w[127:112] = ingress_r[ingress_read_r];
            always @(posedge clk_i) begin
                if (ingress_push_w) ingress_r[ingress_write_r] <= object_record_data_i[127:112];
            end
            for (stage = 0; stage < STAGES; stage = stage + 1) begin : g_stage
                reg [15:0] data_r;
                reg [15:0] data_w;
                assign record_w[stage][127:112] = data_r;
                always @(*) begin
                    data_w = 0;
                    if (stage == 0) begin
                        data_w = ingress_data_w[127:112];
                    end else begin
                        data_w = record_w[stage-1][127:112];
                        if (stage == 1 && step_r && record_w[0][0])
                            data_w = record_w[0][127:112] + acceleration_y_r;
                    end
                end
                always @(posedge clk_i) begin
                    if (region_advance_w) data_r <= data_w;
                end
            end
        end
        begin : g_acceleration_x
            (* keep = 1 *) reg region_update_pending_r /* synthesis syn_preserve=1 */;
            (* keep = 1 *) reg region_event_pending_r /* synthesis syn_preserve=1 */;
            (* keep = 1 *) reg region_quad_pending_r /* synthesis syn_preserve=1 */;
            wire region_advance_w;
            assign region_advance_w = (!region_update_pending_r || object_update_ready_i) &&
                (!region_event_pending_r || object_event_ready_i) &&
                (!region_quad_pending_r || object_quad_ready_i) && !stop_i;
            (* keep = 1 *) always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    region_update_pending_r <= 0;
                    region_event_pending_r <= 0;
                    region_quad_pending_r <= 0;
                end else if (stop_i) begin
                    region_update_pending_r <= 0;
                    region_event_pending_r <= 0;
                    region_quad_pending_r <= 0;
                end else if (region_advance_w) begin
                    region_update_pending_r <= valid_r[10] && step_r && original_alive_r[10];
                    region_event_pending_r <= valid_r[10] && step_r;
                    region_quad_pending_r <= valid_r[10] && draw_r && record_w[10][0];
                end else begin
                    if (object_update_ready_i) region_update_pending_r <= 0;
                    if (object_event_ready_i) region_event_pending_r <= 0;
                    if (object_quad_ready_i) region_quad_pending_r <= 0;
                end
            end
            reg [15:0] ingress_r [0:1];
            assign ingress_data_w[143:128] = ingress_r[ingress_read_r];
            always @(posedge clk_i) begin
                if (ingress_push_w) ingress_r[ingress_write_r] <= object_record_data_i[143:128];
            end
            for (stage = 0; stage < STAGES; stage = stage + 1) begin : g_stage
                reg [15:0] data_r;
                reg [15:0] data_w;
                assign record_w[stage][143:128] = data_r;
                always @(*) begin
                    data_w = 0;
                    if (stage == 0) begin
                        data_w = ingress_data_w[143:128];
                    end else begin
                        data_w = record_w[stage-1][143:128];
                    end
                end
                always @(posedge clk_i) begin
                    if (region_advance_w) data_r <= data_w;
                end
            end
        end
        begin : g_acceleration_y
            (* keep = 1 *) reg region_update_pending_r /* synthesis syn_preserve=1 */;
            (* keep = 1 *) reg region_event_pending_r /* synthesis syn_preserve=1 */;
            (* keep = 1 *) reg region_quad_pending_r /* synthesis syn_preserve=1 */;
            wire region_advance_w;
            assign region_advance_w = (!region_update_pending_r || object_update_ready_i) &&
                (!region_event_pending_r || object_event_ready_i) &&
                (!region_quad_pending_r || object_quad_ready_i) && !stop_i;
            (* keep = 1 *) always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    region_update_pending_r <= 0;
                    region_event_pending_r <= 0;
                    region_quad_pending_r <= 0;
                end else if (stop_i) begin
                    region_update_pending_r <= 0;
                    region_event_pending_r <= 0;
                    region_quad_pending_r <= 0;
                end else if (region_advance_w) begin
                    region_update_pending_r <= valid_r[10] && step_r && original_alive_r[10];
                    region_event_pending_r <= valid_r[10] && step_r;
                    region_quad_pending_r <= valid_r[10] && draw_r && record_w[10][0];
                end else begin
                    if (object_update_ready_i) region_update_pending_r <= 0;
                    if (object_event_ready_i) region_event_pending_r <= 0;
                    if (object_quad_ready_i) region_quad_pending_r <= 0;
                end
            end
            reg [15:0] ingress_r [0:1];
            assign ingress_data_w[159:144] = ingress_r[ingress_read_r];
            always @(posedge clk_i) begin
                if (ingress_push_w) ingress_r[ingress_write_r] <= object_record_data_i[159:144];
            end
            for (stage = 0; stage < STAGES; stage = stage + 1) begin : g_stage
                reg [15:0] data_r;
                reg [15:0] data_w;
                assign record_w[stage][159:144] = data_r;
                always @(*) begin
                    data_w = 0;
                    if (stage == 0) begin
                        data_w = ingress_data_w[159:144];
                    end else begin
                        data_w = record_w[stage-1][159:144];
                    end
                end
                always @(posedge clk_i) begin
                    if (region_advance_w) data_r <= data_w;
                end
            end
        end
        begin : g_half_width
            (* keep = 1 *) reg region_update_pending_r /* synthesis syn_preserve=1 */;
            (* keep = 1 *) reg region_event_pending_r /* synthesis syn_preserve=1 */;
            (* keep = 1 *) reg region_quad_pending_r /* synthesis syn_preserve=1 */;
            wire region_advance_w;
            assign region_advance_w = (!region_update_pending_r || object_update_ready_i) &&
                (!region_event_pending_r || object_event_ready_i) &&
                (!region_quad_pending_r || object_quad_ready_i) && !stop_i;
            (* keep = 1 *) always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    region_update_pending_r <= 0;
                    region_event_pending_r <= 0;
                    region_quad_pending_r <= 0;
                end else if (stop_i) begin
                    region_update_pending_r <= 0;
                    region_event_pending_r <= 0;
                    region_quad_pending_r <= 0;
                end else if (region_advance_w) begin
                    region_update_pending_r <= valid_r[10] && step_r && original_alive_r[10];
                    region_event_pending_r <= valid_r[10] && step_r;
                    region_quad_pending_r <= valid_r[10] && draw_r && record_w[10][0];
                end else begin
                    if (object_update_ready_i) region_update_pending_r <= 0;
                    if (object_event_ready_i) region_event_pending_r <= 0;
                    if (object_quad_ready_i) region_quad_pending_r <= 0;
                end
            end
            reg [7:0] ingress_r [0:1];
            assign ingress_data_w[167:160] = ingress_r[ingress_read_r];
            always @(posedge clk_i) begin
                if (ingress_push_w) ingress_r[ingress_write_r] <= object_record_data_i[167:160];
            end
            for (stage = 0; stage < STAGES; stage = stage + 1) begin : g_stage
                reg [7:0] data_r;
                reg [7:0] data_w;
                assign record_w[stage][167:160] = data_r;
                always @(*) begin
                    data_w = 0;
                    if (stage == 0) begin
                        data_w = ingress_data_w[167:160];
                    end else begin
                        data_w = record_w[stage-1][167:160];
                    end
                end
                always @(posedge clk_i) begin
                    if (region_advance_w) data_r <= data_w;
                end
            end
        end
        begin : g_half_height
            (* keep = 1 *) reg region_update_pending_r /* synthesis syn_preserve=1 */;
            (* keep = 1 *) reg region_event_pending_r /* synthesis syn_preserve=1 */;
            (* keep = 1 *) reg region_quad_pending_r /* synthesis syn_preserve=1 */;
            wire region_advance_w;
            assign region_advance_w = (!region_update_pending_r || object_update_ready_i) &&
                (!region_event_pending_r || object_event_ready_i) &&
                (!region_quad_pending_r || object_quad_ready_i) && !stop_i;
            (* keep = 1 *) always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    region_update_pending_r <= 0;
                    region_event_pending_r <= 0;
                    region_quad_pending_r <= 0;
                end else if (stop_i) begin
                    region_update_pending_r <= 0;
                    region_event_pending_r <= 0;
                    region_quad_pending_r <= 0;
                end else if (region_advance_w) begin
                    region_update_pending_r <= valid_r[10] && step_r && original_alive_r[10];
                    region_event_pending_r <= valid_r[10] && step_r;
                    region_quad_pending_r <= valid_r[10] && draw_r && record_w[10][0];
                end else begin
                    if (object_update_ready_i) region_update_pending_r <= 0;
                    if (object_event_ready_i) region_event_pending_r <= 0;
                    if (object_quad_ready_i) region_quad_pending_r <= 0;
                end
            end
            reg [7:0] ingress_r [0:1];
            assign ingress_data_w[175:168] = ingress_r[ingress_read_r];
            always @(posedge clk_i) begin
                if (ingress_push_w) ingress_r[ingress_write_r] <= object_record_data_i[175:168];
            end
            for (stage = 0; stage < STAGES; stage = stage + 1) begin : g_stage
                reg [7:0] data_r;
                reg [7:0] data_w;
                assign record_w[stage][175:168] = data_r;
                always @(*) begin
                    data_w = 0;
                    if (stage == 0) begin
                        data_w = ingress_data_w[175:168];
                    end else begin
                        data_w = record_w[stage-1][175:168];
                    end
                end
                always @(posedge clk_i) begin
                    if (region_advance_w) data_r <= data_w;
                end
            end
        end
        begin : g_reserved_shape
            (* keep = 1 *) reg region_update_pending_r /* synthesis syn_preserve=1 */;
            (* keep = 1 *) reg region_event_pending_r /* synthesis syn_preserve=1 */;
            (* keep = 1 *) reg region_quad_pending_r /* synthesis syn_preserve=1 */;
            wire region_advance_w;
            assign region_advance_w = (!region_update_pending_r || object_update_ready_i) &&
                (!region_event_pending_r || object_event_ready_i) &&
                (!region_quad_pending_r || object_quad_ready_i) && !stop_i;
            (* keep = 1 *) always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    region_update_pending_r <= 0;
                    region_event_pending_r <= 0;
                    region_quad_pending_r <= 0;
                end else if (stop_i) begin
                    region_update_pending_r <= 0;
                    region_event_pending_r <= 0;
                    region_quad_pending_r <= 0;
                end else if (region_advance_w) begin
                    region_update_pending_r <= valid_r[10] && step_r && original_alive_r[10];
                    region_event_pending_r <= valid_r[10] && step_r;
                    region_quad_pending_r <= valid_r[10] && draw_r && record_w[10][0];
                end else begin
                    if (object_update_ready_i) region_update_pending_r <= 0;
                    if (object_event_ready_i) region_event_pending_r <= 0;
                    if (object_quad_ready_i) region_quad_pending_r <= 0;
                end
            end
            reg [15:0] ingress_r [0:1];
            assign ingress_data_w[191:176] = ingress_r[ingress_read_r];
            always @(posedge clk_i) begin
                if (ingress_push_w) ingress_r[ingress_write_r] <= object_record_data_i[191:176];
            end
            for (stage = 0; stage < STAGES; stage = stage + 1) begin : g_stage
                reg [15:0] data_r;
                reg [15:0] data_w;
                assign record_w[stage][191:176] = data_r;
                always @(*) begin
                    data_w = 0;
                    if (stage == 0) begin
                        data_w = ingress_data_w[191:176];
                    end else begin
                        data_w = record_w[stage-1][191:176];
                    end
                end
                always @(posedge clk_i) begin
                    if (region_advance_w) data_r <= data_w;
                end
            end
        end
        begin : g_quad
            (* keep = 1 *) reg region_update_pending_r /* synthesis syn_preserve=1 */;
            (* keep = 1 *) reg region_event_pending_r /* synthesis syn_preserve=1 */;
            (* keep = 1 *) reg region_quad_pending_r /* synthesis syn_preserve=1 */;
            wire region_advance_w;
            assign region_advance_w = (!region_update_pending_r || object_update_ready_i) &&
                (!region_event_pending_r || object_event_ready_i) &&
                (!region_quad_pending_r || object_quad_ready_i) && !stop_i;
            (* keep = 1 *) always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    region_update_pending_r <= 0;
                    region_event_pending_r <= 0;
                    region_quad_pending_r <= 0;
                end else if (stop_i) begin
                    region_update_pending_r <= 0;
                    region_event_pending_r <= 0;
                    region_quad_pending_r <= 0;
                end else if (region_advance_w) begin
                    region_update_pending_r <= valid_r[10] && step_r && original_alive_r[10];
                    region_event_pending_r <= valid_r[10] && step_r;
                    region_quad_pending_r <= valid_r[10] && draw_r && record_w[10][0];
                end else begin
                    if (object_update_ready_i) region_update_pending_r <= 0;
                    if (object_event_ready_i) region_event_pending_r <= 0;
                    if (object_quad_ready_i) region_quad_pending_r <= 0;
                end
            end
            reg [63:0] ingress_r [0:1];
            assign ingress_data_w[255:192] = ingress_r[ingress_read_r];
            always @(posedge clk_i) begin
                if (ingress_push_w) ingress_r[ingress_write_r] <= object_record_data_i[255:192];
            end
            for (stage = 0; stage < STAGES; stage = stage + 1) begin : g_stage
                reg [63:0] data_r;
                reg [63:0] data_w;
                assign record_w[stage][255:192] = data_r;
                always @(*) begin
                    data_w = 0;
                    if (stage == 0) begin
                        data_w = ingress_data_w[255:192];
                    end else begin
                        data_w = record_w[stage-1][255:192];
                    end
                end
                always @(posedge clk_i) begin
                    if (region_advance_w) data_r <= data_w;
                end
            end
        end
    endgenerate
endmodule
