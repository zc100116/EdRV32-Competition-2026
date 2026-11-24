// File: edrv32_gpu_resolve.v
// Spec: gpu-spec 2.10, 5; gpu-microarch 4.2, 4.5, 4.8, 4.9.
// Description: Three original-color rows feed four-lane edge filtering and Surface packing.
// Region edges repeat their own pixel; target offsets affect reads, Surface stride affects writes.
// Clock: clk_gpu.
module edrv32_gpu_resolve (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Command snapshot.
    input wire resolve_valid_i,
    output wire resolve_ready_o,
    input wire [255:0] resolve_command_i,
    input wire [255:0] resolve_target_i,
    input wire resolve_wide_i,

    // Target color access.
    output wire resolve_read_valid_o,
    input wire resolve_read_ready_i,
    output wire [15:0] resolve_read_addr_o,
    input wire resolve_color_valid_i,
    output wire resolve_color_ready_o,
    input wire [63:0] resolve_color_data_i,

    // Surface row write client.
    output wire write_req_valid_o,
    input wire write_req_ready_i,
    output wire [31:0] write_req_addr_o,
    output wire [31:0] write_req_bytes_o,
    output wire write_data_valid_o,
    input wire write_data_ready_i,
    output wire [255:0] write_data_data_o,
    output wire [31:0] write_data_keep_o,
    output wire write_data_last_o,
    input wire write_done_i,

    // Command lifecycle.
    input wire finish_i,
    input wire stop_i,
    output wire unit_done_o,
    output wire perf_resolve_busy_o
);
    localparam [3:0] S_IDLE = 4'd0;
    localparam [3:0] S_FILL = 4'd1;
    localparam [3:0] S_REQ = 4'd2;
    localparam [3:0] S_SCAN = 4'd3;
    localparam [3:0] S_FLUSH = 4'd4;
    localparam [3:0] S_WAIT = 4'd5;
    localparam [3:0] S_DONE = 4'd6;
    localparam [3:0] S_EMPTY = 4'd7;
    reg [3:0] state_r;
    reg aa_r;
    reg [7:0] threshold_r;
    reg [31:0] base_r;
    reg [15:0] stride_r;
    reg [15:0] x0_r;
    reg [15:0] x1_r;
    reg [15:0] y0_r;
    reg [15:0] y1_r;
    reg [15:0] target_x_r;
    reg [15:0] target_y_r;
    reg [8:0] target_words_r;
    reg [15:0] y_r;
    reg [15:0] fill_y_r;
    reg [1:0] north_bank_r;
    reg [1:0] center_bank_r;
    reg [1:0] south_bank_r;
    reg [1:0] fill_bank_r;
    reg initial_r;
    reg second_r;
    reg [8:0] groups_r;
    reg [8:0] sent_r;
    reg [8:0] returned_r;
    reg [8:0] scan_r;
    wire request_fire_w;
    wire color_fire_w;
    wire advance_w;
    wire line_read_w;
    wire [8:0] line_addr_w;
    wire [71:0] line_data_w [0:2];
    reg read_valid_r;
    reg [8:0] read_group_r;
    reg previous_valid_r;
    reg [8:0] previous_group_r;
    reg [63:0] previous_center_r;
    reg [63:0] previous_north_r;
    reg [63:0] previous_south_r;
    reg [15:0] west_r;
    reg [255:0] pack_r;
    reg [255:0] pack_data_w;
    reg [31:0] pack_keep_r;
    reg row_done_r;
    reg done_r;
    reg finish_r;
    wire [15:0] unused_region_width_w;
    wire unused_command_w;
    assign unused_region_width_w = resolve_command_i[175:160] - resolve_command_i[143:128];
    assign unused_command_w = ^{resolve_command_i[255:192],
        resolve_command_i[127:112], resolve_command_i[100:96],
        resolve_command_i[75:48], resolve_command_i[39:33], resolve_command_i[31:0],
        resolve_target_i[255:64], resolve_target_i[31:0]};
    reg [1:0] pack_group_r;
    reg [255:0] output_r [0:1];
    reg output_last_r [0:1];
    reg [31:0] output_keep_r [0:1];
    reg output_head_r;
    reg output_tail_r;
    reg [1:0] output_count_r;
    wire output_pop_w;
    wire emit_w;
    wire flush_w;
    wire beat_push_w;
    wire [63:0] filtered_w;
    reg [5:0] aa_valid_r;
    reg [8:0] aa_group_r [0:5];
    wire pack_emit_w;
    integer stage_r;
    reg row_started_r;
    wire [63:0] current_center_w;
    wire [63:0] current_north_w;
    wire [63:0] current_south_w;
    wire [15:0] east_w;
    genvar bank;
    genvar channel;

    // E565 expansion and P565 truncation occur at the specified arithmetic boundaries.
    function [23:0] expand;
        input [15:0] color_i;
        begin
            expand = {color_i[15:11], color_i[15:13], color_i[10:5], color_i[10:9],
                color_i[4:0], color_i[4:2]};
        end
    endfunction
    function [7:0] luminance;
        input [23:0] color_i;
        reg [9:0] unused_sum;
        begin
            unused_sum = {2'b0, color_i[23:16]} + {1'b0, color_i[15:8], 1'b0}
                + {2'b0, color_i[7:0]};
            luminance = unused_sum[9:2];
        end
    endfunction
    assign resolve_ready_o = state_r == S_IDLE || state_r == S_DONE;
    assign unit_done_o = done_r;
    assign perf_resolve_busy_o = state_r != S_IDLE && state_r != S_DONE;
    assign resolve_color_ready_o = 1'b1;
    // During scan, the retired north row is replaced only after its original word was read.
    assign resolve_read_valid_o = !stop_i && ((state_r == S_FILL && sent_r < groups_r)
        || ((state_r == S_SCAN || state_r == S_FLUSH || state_r == S_WAIT)
            && y_r + 16'd2 < y1_r && sent_r < scan_r));
    assign resolve_read_addr_o = (fill_y_r - target_y_r) * {7'b0, target_words_r}
        + ((x0_r - target_x_r) >> 2) + {7'b0, sent_r};
    assign request_fire_w = resolve_read_valid_o && resolve_read_ready_i;
    assign color_fire_w = resolve_color_valid_i;
    assign write_req_valid_o = state_r == S_REQ && !stop_i;
    assign write_req_addr_o = base_r + {16'b0, y_r} * {16'b0, stride_r}
        + {15'b0, x0_r, 1'b0};
    assign write_req_bytes_o = {15'b0, x1_r - x0_r, 1'b0};
    assign write_data_valid_o = output_count_r != 0;
    assign write_data_data_o = output_r[output_head_r];
    assign write_data_keep_o = output_keep_r[output_head_r];
    assign write_data_last_o = output_last_r[output_head_r];
    assign output_pop_w = write_data_valid_o && write_data_ready_i;
    assign advance_w = output_count_r < 2;
    assign line_read_w = state_r == S_SCAN && scan_r < groups_r && advance_w;
    assign line_addr_w = scan_r;
    assign current_center_w = line_data_w[center_bank_r][63:0];
    assign current_north_w = y_r == y0_r ? current_center_w
        : line_data_w[north_bank_r][63:0];
    assign current_south_w = y_r + 16'd1 == y1_r ? current_center_w
        : line_data_w[south_bank_r][63:0];
    assign flush_w = state_r == S_FLUSH && !read_valid_r;
    assign emit_w = advance_w && previous_valid_r && (read_valid_r || flush_w);
    assign east_w = flush_w ? previous_center_r[63:48] : current_center_w[15:0];
    assign pack_emit_w = advance_w && aa_valid_r[5];
    assign beat_push_w = pack_emit_w && (pack_group_r == 2'd3
        || aa_group_r[5] + 9'd1 == groups_r);

    // microarch 4.5/4.9: place four pixels at their aligned DDR byte lanes.
    always @(*) begin
        pack_data_w = pack_r;
        pack_data_w[pack_group_r*64 +: 64] = filtered_w;
    end

    generate
        for (bank = 0; bank < 3; bank = bank + 1) begin : g_line
            edrv32_ram_gpu_resolve_line u_line (
                .clk_i(clk_i),
                .wr_en_i(color_fire_w && fill_bank_r == bank),
                .wr_addr_i(returned_r),
                .wr_data_i({8'b0, resolve_color_data_i}),
                .rd_en_i(line_read_w),
                .rd_addr_i(line_addr_w),
                .rd_data_o(line_data_w[bank])
            );
        end
    endgenerate

    // Six arithmetic stages retain four pixels per cycle without a long AA feedback path.
    generate
        for (bank = 0; bank < 4; bank = bank + 1) begin : g_aa
            reg [23:0] color_a_r [0:4];
            reg [23:0] color_b_r [0:4];
            reg [23:0] color_c_r [0:4];
            reg [23:0] color_d_r [0:4];
            reg [7:0] light_b_r [0:4];
            wire [8*5-1:0] light_w;
            for (channel = 0; channel < 5; channel = channel + 1) begin : g_luminance
                assign light_w[8*channel +: 8] = luminance(color_a_r[channel]);
            end
            reg [7:0] center_c_r;
            reg [7:0] max_ns_c_r;
            reg [7:0] max_we_c_r;
            reg [7:0] min_ns_c_r;
            reg [7:0] min_we_c_r;
            reg [7:0] vertical_c_r;
            reg [7:0] horizontal_c_r;
            wire [7:0] max_neighbors_w;
            wire [7:0] min_neighbors_w;
            wire [7:0] max_w;
            wire [7:0] min_w;
            reg [7:0] range_d_r;
            reg horizontal_d_r;
            reg [9:0] unused_red_e_r;
            reg [9:0] unused_green_e_r;
            reg [9:0] unused_blue_e_r;
            reg bypass_e_r;
            reg [15:0] original_e_r;
            reg [15:0] result_f_r;
            integer color_r;
            assign max_neighbors_w = max_ns_c_r > max_we_c_r ? max_ns_c_r : max_we_c_r;
            assign min_neighbors_w = min_ns_c_r < min_we_c_r ? min_ns_c_r : min_we_c_r;
            assign max_w = center_c_r > max_neighbors_w ? center_c_r : max_neighbors_w;
            assign min_w = center_c_r < min_neighbors_w ? center_c_r : min_neighbors_w;
            assign filtered_w[bank*16 +: 16] = result_f_r;
            always @(posedge clk_i) begin
                if (advance_w) begin
                    color_a_r[0] <= expand(previous_center_r[bank*16 +: 16]);
                    color_a_r[1] <= expand(previous_north_r[bank*16 +: 16]);
                    color_a_r[2] <= expand(previous_south_r[bank*16 +: 16]);
                    color_a_r[3] <= expand(bank == 0 ? west_r
                        : previous_center_r[((bank+3)%4)*16 +: 16]);
                    color_a_r[4] <= expand(bank == 3 ? east_w
                        : previous_center_r[((bank+1)%4)*16 +: 16]);
                    for (color_r = 0; color_r < 5; color_r = color_r + 1) begin
                        color_b_r[color_r] <= color_a_r[color_r];
                        light_b_r[color_r] <= light_w[8*color_r +: 8];
                        color_c_r[color_r] <= color_b_r[color_r];
                        color_d_r[color_r] <= color_c_r[color_r];
                    end
                    center_c_r <= light_b_r[0];
                    max_ns_c_r <= light_b_r[1] > light_b_r[2] ? light_b_r[1] : light_b_r[2];
                    min_ns_c_r <= light_b_r[1] < light_b_r[2] ? light_b_r[1] : light_b_r[2];
                    max_we_c_r <= light_b_r[3] > light_b_r[4] ? light_b_r[3] : light_b_r[4];
                    min_we_c_r <= light_b_r[3] < light_b_r[4] ? light_b_r[3] : light_b_r[4];
                    vertical_c_r <= light_b_r[1] >= light_b_r[2]
                        ? light_b_r[1] - light_b_r[2] : light_b_r[2] - light_b_r[1];
                    horizontal_c_r <= light_b_r[3] >= light_b_r[4]
                        ? light_b_r[3] - light_b_r[4] : light_b_r[4] - light_b_r[3];
                    range_d_r <= max_w - min_w;
                    horizontal_d_r <= vertical_c_r >= horizontal_c_r;
                    bypass_e_r <= !aa_r || range_d_r < threshold_r;
                    original_e_r <= {color_d_r[0][23:19], color_d_r[0][15:10],
                        color_d_r[0][7:3]};
                    unused_red_e_r <= {1'b0, color_d_r[0][23:16], 1'b0}
                        + {2'b0, color_d_r[horizontal_d_r ? 1 : 3][23:16]}
                        + {2'b0, color_d_r[horizontal_d_r ? 2 : 4][23:16]};
                    unused_green_e_r <= {1'b0, color_d_r[0][15:8], 1'b0}
                        + {2'b0, color_d_r[horizontal_d_r ? 1 : 3][15:8]}
                        + {2'b0, color_d_r[horizontal_d_r ? 2 : 4][15:8]};
                    unused_blue_e_r <= {1'b0, color_d_r[0][7:0], 1'b0}
                        + {2'b0, color_d_r[horizontal_d_r ? 1 : 3][7:0]}
                        + {2'b0, color_d_r[horizontal_d_r ? 2 : 4][7:0]};
                    result_f_r <= bypass_e_r ? original_e_r
                        : {unused_red_e_r[9:5], unused_green_e_r[9:4], unused_blue_e_r[9:5]};
                end
            end
        end
    endgenerate

    always @(posedge clk_i) begin
        if (resolve_valid_i && resolve_ready_o) begin
            aa_r <= resolve_command_i[32];
            threshold_r <= resolve_command_i[47:40];
            base_r <= {resolve_command_i[95:76], 12'b0};
            stride_r <= {resolve_command_i[111:101], 5'b0};
            x0_r <= resolve_command_i[143:128];
            y0_r <= resolve_command_i[159:144];
            x1_r <= resolve_command_i[175:160];
            y1_r <= resolve_command_i[191:176];
            target_x_r <= resolve_target_i[47:32];
            target_y_r <= resolve_target_i[63:48];
            target_words_r <= resolve_wide_i ? 9'd320 : 9'd160;
        end
        if (advance_w && read_valid_r) begin
            previous_center_r <= current_center_w;
            previous_north_r <= current_north_w;
            previous_south_r <= current_south_w;
            west_r <= previous_valid_r ? previous_center_r[63:48] : current_center_w[15:0];
            previous_group_r <= read_group_r;
        end
        if (pack_emit_w) begin
            pack_r <= pack_data_w;
            if (beat_push_w) begin
                output_r[output_tail_r] <= pack_data_w;
                output_keep_r[output_tail_r] <= pack_keep_r
                    | (32'hff << {pack_group_r, 3'b0});
                output_last_r[output_tail_r] <= aa_group_r[5] + 9'd1 == groups_r;
            end
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            aa_valid_r <= 6'b0;
            row_started_r <= 1'b0;
            row_done_r <= 1'b0;
            done_r <= 1'b1;
            finish_r <= 1'b1;
            y_r <= 16'b0;
            fill_y_r <= 16'b0;
            groups_r <= 9'b0;
            north_bank_r <= 2'b0;
            center_bank_r <= 2'd1;
            south_bank_r <= 2'd2;
            fill_bank_r <= 2'd1;
            initial_r <= 1'b1;
            second_r <= 1'b0;
            sent_r <= 9'b0;
            returned_r <= 9'b0;
            scan_r <= 9'b0;
            read_valid_r <= 1'b0;
            read_group_r <= 9'b0;
            previous_valid_r <= 1'b0;
            pack_group_r <= 2'b0;
            pack_keep_r <= 32'b0;
            output_head_r <= 1'b0;
            output_tail_r <= 1'b0;
            output_count_r <= 2'b0;
        end else begin
            if (advance_w) begin
                aa_valid_r <= {aa_valid_r[4:0], emit_w};
                aa_group_r[0] <= previous_group_r;
                for (stage_r = 1; stage_r < 6; stage_r = stage_r + 1)
                    aa_group_r[stage_r] <= aa_group_r[stage_r-1];
            end
            finish_r <= finish_i;
            if (finish_i && (state_r == S_IDLE || state_r == S_DONE)) done_r <= 1'b1;
            if ((finish_r && !finish_i) || (resolve_valid_i && resolve_ready_o))
                done_r <= 1'b0;
            if (write_done_i) row_done_r <= 1'b1;
            if (request_fire_w) sent_r <= sent_r + 9'd1;
            if (color_fire_w) returned_r <= returned_r + 9'd1;
            if (advance_w) begin
                read_valid_r <= line_read_w;
                if (line_read_w) begin
                    read_group_r <= scan_r;
                    scan_r <= scan_r + 9'd1;
                end
                if (read_valid_r) previous_valid_r <= 1'b1;
                if (pack_emit_w) begin
                    pack_group_r <= pack_group_r + 2'd1;
                    pack_keep_r <= beat_push_w ? 32'b0
                        : pack_keep_r | (32'hff << {pack_group_r, 3'b0});
                end
                if (flush_w && emit_w) previous_valid_r <= 1'b0;
            end
            if (beat_push_w) output_tail_r <= !output_tail_r;
            if (output_pop_w) output_head_r <= !output_head_r;
            begin
                case ({beat_push_w, output_pop_w})
                    2'b10: output_count_r <= output_count_r + 2'd1;
                    2'b01: output_count_r <= output_count_r - 2'd1;
                    default: begin end
                endcase
            end
            case (state_r)
                S_IDLE, S_DONE: begin
                    if (resolve_valid_i) begin
                        aa_valid_r <= 6'b0;
                        row_started_r <= 1'b0;
                        y_r <= resolve_command_i[159:144];
                        fill_y_r <= resolve_command_i[159:144];
                        groups_r <= unused_region_width_w[10:2];
                        center_bank_r <= 2'd1;
                        north_bank_r <= 2'd0;
                        south_bank_r <= 2'd2;
                        fill_bank_r <= 2'd1;
                        initial_r <= 1'b1;
                        second_r <= 1'b0;
                        sent_r <= 9'b0;
                        returned_r <= 9'b0;
                        state_r <= (resolve_command_i[143:128] == resolve_command_i[175:160]
                            || resolve_command_i[159:144] == resolve_command_i[191:176])
                            ? S_EMPTY : S_FILL;
                    end
                end
                S_EMPTY: if (finish_i) state_r <= S_DONE;
                S_FILL: begin
                    if (stop_i) state_r <= S_WAIT;
                    else if ((!initial_r && fill_y_r >= y1_r)
                        || (sent_r == groups_r && returned_r == groups_r)) begin
                        if (initial_r && !second_r && y_r + 16'd1 < y1_r) begin
                            second_r <= 1'b1;
                            fill_y_r <= y_r + 16'd1;
                            fill_bank_r <= south_bank_r;
                            sent_r <= 9'b0;
                            returned_r <= 9'b0;
                        end else begin
                            initial_r <= 1'b0;
                            state_r <= S_REQ;
                        end
                    end
                end
                S_REQ: begin
                    if (stop_i) state_r <= S_WAIT;
                    else if (write_req_ready_i) begin
                        row_done_r <= 1'b0;
                        row_started_r <= 1'b1;
                        scan_r <= 9'b0;
                        previous_valid_r <= 1'b0;
                        read_valid_r <= 1'b0;
                        pack_group_r <= x0_r[3:2];
                        pack_keep_r <= 32'b0;
                        fill_y_r <= y_r + 16'd2;
                        fill_bank_r <= north_bank_r;
                        sent_r <= 9'b0;
                        returned_r <= 9'b0;
                        state_r <= S_SCAN;
                    end
                end
                S_SCAN: if (scan_r == groups_r) state_r <= S_FLUSH;
                S_FLUSH: if (flush_w && emit_w) state_r <= S_WAIT;
                S_WAIT: begin
                    if (stop_i && output_count_r == 0 && sent_r == returned_r
                        && aa_valid_r == 0 && (!row_started_r || row_done_r)) begin
                        if (finish_i) state_r <= S_DONE;
                    end else if (row_done_r && (y_r + 16'd2 >= y1_r
                        || (sent_r == groups_r && returned_r == groups_r))) begin
                        if (y_r + 16'd1 == y1_r) begin
                            if (finish_i) state_r <= S_DONE;
                        end else begin
                            y_r <= y_r + 16'd1;
                            north_bank_r <= center_bank_r;
                            center_bank_r <= south_bank_r;
                            south_bank_r <= north_bank_r;
                            row_started_r <= 1'b0;
                            state_r <= S_FILL;
                        end
                    end
                end
                default: begin end
            endcase
        end
    end
endmodule
