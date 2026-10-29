// File: edrv32_rnd_draw.v
// Spec: rnd-spec 2.2, 2.3, 2.6 FILL/BORDER/GLYPH/BLIT/TILEMAP, 5.
// Description: Clipped two-pixel drawing scheduler with source beat reuse and target writeback.
//              Command, DMA arbitration, COPY and the two blur passes belong to the parent.
// Clock domain: clk_mem (clk_i).
module edrv32_rnd_draw (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // One drawing command; held constant through done.
    input wire start_i,
    input wire [511:0] command_i,
    input wire [31:0] source_stride_i,
    input wire cancel_i,
    output wire idle_o,
    output wire done_o,
    output wire [4:0] pixel_count_o,
    output wire read_wait_o,
    output wire write_wait_o,

    // Arbitrated one-beat read requests and their ordered data responses.
    output wire rd_valid_o,
    input wire rd_ready_i,
    output wire [31:0] rd_addr_o,
    input wire rd_data_valid_i,
    input wire [255:0] rd_data_i,

    // One-beat writeback, completed by the final DDR B response.
    output wire wr_valid_o,
    input wire wr_ready_i,
    output wire [31:0] wr_addr_o,
    output wire [255:0] wr_data_o,
    output wire [31:0] wr_strb_o,
    input wire wr_done_i,

    // Shared two-pixel alpha datapath.
    output wire blend_valid_o,
    input wire blend_ready_i,
    output wire [63:0] blend_src_o,
    output wire [63:0] blend_dst_o,
    input wire blend_valid_i,
    input wire [63:0] blend_pixel_i
);
    localparam [4:0] S_IDLE = 5'd0;
    localparam [4:0] S_ROW = 5'd1;
    localparam [4:0] S_EDGE_REQ = 5'd2;
    localparam [4:0] S_EDGE_WAIT = 5'd3;
    localparam [4:0] S_PIXEL = 5'd4;
    localparam [4:0] S_DEST = 5'd5;
    localparam [4:0] S_SOURCE = 5'd6;
    localparam [4:0] S_MAP = 5'd7;
    localparam [4:0] S_SAMPLE = 5'd8;
    localparam [4:0] S_PALETTE = 5'd9;
    localparam [4:0] S_CONVERT = 5'd10;
    localparam [4:0] S_BLEND = 5'd11;
    localparam [4:0] S_BLEND_WAIT = 5'd12;
    localparam [4:0] S_READ = 5'd13;
    localparam [4:0] S_READ_WAIT = 5'd14;
    localparam [4:0] S_WRITE = 5'd15;
    localparam [4:0] S_WRITE_WAIT = 5'd16;
    localparam [4:0] S_NEXT_ROW = 5'd17;
    localparam [4:0] S_DONE = 5'd18;
    localparam [4:0] S_PALETTE_LOAD = 5'd19;

    reg [4:0] state_r;
    reg [4:0] read_return_r;
    reg [4:0] write_return_r;
    reg read_dest_r;
    reg [31:0] read_addr_r;
    reg [11:0] x_r;
    reg [11:0] y_r;
    reg lane_r;
    reg pair_r;
    reg [63:0] src_r;
    reg [31:0] raw_r;
    reg [15:0] map_entry_r;
    reg [7:0] palette_index_r;
    reg map_valid_r;
    reg [31:0] map_addr_r;
    reg [255:0] map_data_r;
    reg source_valid_r;
    reg [31:0] source_addr_r;
    reg [255:0] source_data_r;
    reg target_valid_r;
    reg [31:0] target_addr_r;
    reg [255:0] target_data_r;
    reg [31:0] target_strb_r;
    reg inner_r;
    reg [15:0] outer_edge_r;
    reg [15:0] inner_edge_r;
    reg outer_inside_r;
    reg inner_inside_r;
    reg [4:0] pixel_count_r;

    wire [7:0] op_w;
    wire argb_w;
    wire [3:0] format_w;
    wire [15:0] flags_w;
    wire signed [17:0] left_w;
    wire signed [17:0] top_w;
    wire signed [17:0] right_w;
    wire signed [17:0] bottom_w;
    wire [16:0] width_w;
    wire [16:0] height_w;
    wire unused_decode_w;
    wire unused_empty_w;
    wire unused_fast_w;
    wire signed [17:0] rect_left_w;
    wire signed [17:0] rect_top_w;
    wire signed [17:0] rect_right_w;
    wire signed [17:0] rect_bottom_w;
    wire [16:0] half_min_w;
    wire [11:0] radius_w;
    wire [11:0] inner_radius_w;
    wire signed [17:0] border_w;
    wire signed [17:0] extension_w;
    wire signed [17:0] inner_left_w;
    wire signed [17:0] inner_top_w;
    wire signed [17:0] inner_right_w;
    wire signed [17:0] inner_bottom_w;
    wire signed [17:0] inner_width_w;
    wire signed [17:0] inner_height_w;
    wire signed [17:0] row_local_w;
    wire [17:0] row_width_w;
    wire [17:0] row_height_w;
    wire row_valid_w;
    wire row_ready_w;
    wire edge_valid_w;
    wire [15:0] edge_w;
    wire [11:0] unused_radius_w;
    wire [15:0] outer_cov_w;
    wire [15:0] inner_cov_w;
    wire [7:0] coverage_w;
    wire [7:0] inverse_inner_w;
    wire [7:0] fill_a0_w;
    wire [255:0] target_wide_w;
    wire [7:0] border_coverage_w;
    wire [11:0] sample_target_x_w;
    wire [31:0] dst_addr_w;
    wire [31:0] src_addr_w;
    wire [31:0] src_adjusted_w;
    wire [31:0] map_addr_w;
    wire [2:0] sub_shift_w;
    wire [7:0] sub_mask_w;
    wire [31:0] unused_sample_x_w;
    wire [31:0] unused_sample_y_w;
    wire [7:0] index_w;
    wire [7:0] palette_last_w;
    wire [31:0] palette_data_w [0:1];
    wire palette_write_w;
    wire [31:0] converted_w;
    wire [31:0] query_addr_w;
    wire [255:0] query_shifted_w;
    wire query_hit_w;
    wire [63:0] target_shifted_w;
    wire [7:0] gradient_a_w;
    wire [23:0] gradient_color_w;
    wire [31:0] gradient_k_w;
    wire [31:0] fill_pixel_w;
    wire [31:0] border_pixel_w;
    wire unused_geometry_w;
    integer lane;

    function automatic [7:0] divide255;
        input [15:0] value_i;
        reg [15:0] biased;
        reg [15:0] rounded;
        reg [7:0] unused_low;
        begin
            biased = value_i + 16'd128;
            rounded = biased + (biased >> 8);
            divide255 = rounded[15:8];
            unused_low = rounded[7:0];
        end
    endfunction
    function automatic [7:0] gradient;
        input [7:0] channel_start_i;
        input [15:0] k_i;
        input signed [31:0] step_i;
        reg signed [48:0] value;
        begin
            value = $signed({1'd0, k_i}) * step_i +
                $signed({25'd0, channel_start_i, 16'd0}) + 49'sd32768;
            if (value < 0)
                gradient = 8'd0;
            else if (value >= 49'sd16777216)
                gradient = 8'd255;
            else
                gradient = value[23:16];
        end
    endfunction

    edrv32_rnd_decode u_decode (
        .command_i(command_i),
        .illegal_o(unused_decode_w),
        .empty_o(unused_empty_w),
        .op_o(op_w),
        .argb_o(argb_w),
        .src_fmt_o(format_w),
        .flags_o(flags_w),
        .left_o(left_w),
        .top_o(top_w),
        .right_o(right_w),
        .bottom_o(bottom_w),
        .width_o(width_w),
        .height_o(height_w),
        .fast_fill_o(unused_fast_w)
    );
    assign rect_left_w = {{2{command_i[175]}}, command_i[175:160]};
    assign rect_top_w = {{2{command_i[191]}}, command_i[191:176]};
    assign rect_right_w = {{2{command_i[207]}}, command_i[207:192]};
    assign rect_bottom_w = {{2{command_i[223]}}, command_i[223:208]};
    assign half_min_w = (width_w < height_w ? width_w : height_w) >> 1;
    assign radius_w = {5'd0, command_i[267:256]} < half_min_w ?
        command_i[267:256] : half_min_w[11:0];
    assign border_w = $signed({6'd0, command_i[299:288]});
    assign extension_w = $signed({6'd0, radius_w}) + 18'sd1;
    assign inner_left_w = rect_left_w + (command_i[306] ? border_w : -extension_w);
    assign inner_top_w = rect_top_w + (command_i[304] ? border_w : -extension_w);
    assign inner_right_w = rect_right_w - (command_i[307] ? border_w : -extension_w);
    assign inner_bottom_w = rect_bottom_w - (command_i[305] ? border_w : -extension_w);
    assign inner_width_w = inner_right_w - inner_left_w + 18'sd1;
    assign inner_height_w = inner_bottom_w - inner_top_w + 18'sd1;
    assign inner_radius_w = radius_w > command_i[299:288] ?
        radius_w - command_i[299:288] : 12'd0;
    assign row_local_w = $signed({6'd0, y_r}) - (inner_r ? inner_top_w : rect_top_w);
    assign row_width_w = inner_r ? inner_width_w : {1'd0, width_w};
    assign row_height_w = inner_r ? inner_height_w : {1'd0, height_w};
    assign row_valid_w = state_r == S_EDGE_REQ;
    assign unused_geometry_w = ^{gradient_k_w[31:16], flags_w[15:4], target_wide_w[255:64],
        row_width_w[17], row_height_w[17], row_local_w[17],
        inner_width_w[17], inner_height_w[17], query_shifted_w[255:32],
        left_w[17:12], top_w[17:12], right_w[17:12], bottom_w[17:12]};
    edrv32_rnd_round_row u_round_row (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .clear_i(cancel_i),
        .row_valid_i(row_valid_w),
        .row_ready_o(row_ready_w),
        .width_i(row_width_w[16:0]),
        .height_i(row_height_w[16:0]),
        .row_y_i(row_local_w[16:0]),
        .radius_i(inner_r ? inner_radius_w : command_i[267:256]),
        .edge_valid_o(edge_valid_w),
        .edge_ready_i(state_r == S_EDGE_WAIT || cancel_i),
        .edge_q4_o(edge_w),
        .radius_o(unused_radius_w)
    );
    edrv32_rnd_coverage u_outer_coverage (
        .x_i($signed({6'd0, x_r}) - rect_left_w),
        .width_i(width_w),
        .edge_q4_i(outer_edge_r),
        .row_inside_i(outer_inside_r),
        .coverage_o(outer_cov_w)
    );
    edrv32_rnd_coverage u_inner_coverage (
        .x_i($signed({6'd0, x_r}) - inner_left_w),
        .width_i(inner_width_w[16:0]),
        .edge_q4_i(inner_edge_r),
        .row_inside_i(inner_inside_r),
        .coverage_o(inner_cov_w)
    );
    assign coverage_w = lane_r ? outer_cov_w[15:8] : outer_cov_w[7:0];
    assign inverse_inner_w = 8'd255 - (lane_r ? inner_cov_w[15:8] : inner_cov_w[7:0]);
    assign border_coverage_w = divide255(coverage_w * inverse_inner_w);
    assign sample_target_x_w = x_r + {11'd0, lane_r};
    edrv32_rnd_address u_address (
        .command_i(command_i),
        .x_i(sample_target_x_w),
        .y_i(y_r),
        .map_entry_i(map_entry_r),
        .dst_addr_o(dst_addr_w),
        .src_addr_o(src_addr_w),
        .map_addr_o(map_addr_w),
        .sub_shift_o(sub_shift_w),
        .sub_mask_o(sub_mask_w),
        .sample_x_o(unused_sample_x_w),
        .sample_y_o(unused_sample_y_w)
    );
    edrv32_rnd_source u_source (
        .format_i(format_w),
        .glyph_i(op_w == 8'h03),
        .raw_i(raw_r),
        .sub_shift_i(sub_shift_w),
        .sub_mask_i(sub_mask_w),
        .palette_i(palette_data_w[lane_r]),
        .color_i(command_i[247:224]),
        .opacity_i(command_i[255:248]),
        .colorkey_i(flags_w[2]),
        .key_i(command_i[463:448]),
        .recolor_i(op_w == 8'h04 && flags_w[3]),
        .recolor_value_i(command_i[511:480]),
        .index_o(index_w),
        .pixel_o(converted_w)
    );
    assign src_adjusted_w = src_addr_w + unused_sample_y_w *
        (source_stride_i - {16'd0, command_i[303:288]});
    assign palette_last_w = format_w == 4'd6 ? 8'd255 : format_w == 4'd7 ? 8'd15 :
        format_w == 4'd8 ? 8'd3 : 8'd1;
    assign query_addr_w = state_r == S_MAP ? map_addr_w : state_r == S_PALETTE_LOAD ?
        command_i[447:416] + {22'd0, palette_index_r, 2'd0} : src_adjusted_w;
    assign query_hit_w = state_r == S_MAP ?
        map_valid_r && map_addr_r == {query_addr_w[31:5], 5'd0} :
        source_valid_r && source_addr_r == {query_addr_w[31:5], 5'd0};
    assign query_shifted_w = (state_r == S_MAP ? map_data_r : source_data_r) >>
        {query_addr_w[4:0], 3'd0};
    assign palette_write_w = state_r == S_PALETTE_LOAD && query_hit_w && !cancel_i;
    genvar palette_lane;
    generate for (palette_lane = 0; palette_lane < 2; palette_lane = palette_lane + 1)
    begin : g_palette
        edrv32_ram_rnd_palette u_palette (
            .clk_i(clk_i),
            .wr_en_i(palette_write_w),
            .wr_addr_i(palette_index_r),
            .wr_data_i(query_shifted_w[31:0]),
            .rd_en_i(state_r == S_PALETTE && lane_r == palette_lane && !cancel_i),
            .rd_addr_i(index_w),
            .rd_data_o(palette_data_w[palette_lane])
        );
    end endgenerate
    assign target_wide_w = target_data_r >> {dst_addr_w[4:0], 3'd0};
    assign target_shifted_w = target_wide_w[63:0];
    assign gradient_k_w = flags_w[1] ? {20'd0, y_r} -
        {{16{command_i[191]}}, command_i[191:176]} : {20'd0, sample_target_x_w} -
        {{16{command_i[175]}}, command_i[175:160]};
    assign gradient_a_w = gradient(command_i[319:312], gradient_k_w[15:0], command_i[351:320]);
    assign gradient_color_w = {
        gradient(command_i[311:304], gradient_k_w[15:0], command_i[383:352]),
        gradient(command_i[303:296], gradient_k_w[15:0], command_i[415:384]),
        gradient(command_i[295:288], gradient_k_w[15:0], command_i[447:416])};
    assign fill_a0_w = flags_w[0] ? gradient_a_w : 8'd255;
    assign fill_pixel_w = {divide255(divide255(command_i[255:248] *
        fill_a0_w) * coverage_w),
        flags_w[0] ? gradient_color_w : command_i[247:224]};
    assign border_pixel_w = {divide255(command_i[255:248] * border_coverage_w),
        command_i[247:224]};
    assign blend_valid_o = state_r == S_BLEND;
    assign blend_src_o = src_r;
    assign blend_dst_o = argb_w ? target_shifted_w :
        {16'd0, target_shifted_w[31:16], 16'd0, target_shifted_w[15:0]};
    assign idle_o = state_r == S_IDLE;
    assign done_o = state_r == S_DONE;
    assign rd_valid_o = state_r == S_READ && !cancel_i;
    assign rd_addr_o = read_addr_r;
    assign wr_valid_o = state_r == S_WRITE && !cancel_i;
    assign wr_addr_o = target_addr_r;
    assign wr_data_o = target_data_r;
    assign wr_strb_o = target_strb_r;
    assign pixel_count_o = pixel_count_r;
    assign read_wait_o = state_r == S_READ_WAIT;
    assign write_wait_o = state_r == S_WRITE && !wr_ready_i;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            read_return_r <= S_IDLE;
            write_return_r <= S_IDLE;
            read_dest_r <= 1'b0;
            x_r <= 12'd0;
            y_r <= 12'd0;
            lane_r <= 1'b0;
            pair_r <= 1'b0;
            source_valid_r <= 1'b0;
            map_valid_r <= 1'b0;
            palette_index_r <= 8'd0;
            target_valid_r <= 1'b0;
            inner_r <= 1'b0;
            outer_inside_r <= 1'b0;
            inner_inside_r <= 1'b0;
            pixel_count_r <= 5'd0;
        end else if (cancel_i) begin
            state_r <= S_IDLE;
            source_valid_r <= 1'b0;
            map_valid_r <= 1'b0;
            palette_index_r <= 8'd0;
            target_valid_r <= 1'b0;
            pixel_count_r <= 5'd0;
        end else begin
            pixel_count_r <= 5'd0;
            case (state_r)
                S_IDLE: if (start_i) begin
                    x_r <= left_w[11:0];
                    y_r <= top_w[11:0];
                    source_valid_r <= 1'b0;
                    map_valid_r <= 1'b0;
                    palette_index_r <= 8'd0;
                    target_valid_r <= 1'b0;
                    state_r <= (op_w == 8'h04 || op_w == 8'h08) && format_w >= 4'd6 ?
                        S_PALETTE_LOAD : S_ROW;
                end
                S_ROW: begin
                    inner_r <= 1'b0;
                    outer_inside_r <= 1'b1;
                    inner_inside_r <= 1'b0;
                    state_r <= (op_w == 8'h01 || op_w == 8'h02) ? S_EDGE_REQ : S_PIXEL;
                end
                S_EDGE_REQ: if (row_ready_w)
                    state_r <= S_EDGE_WAIT;
                S_EDGE_WAIT: if (edge_valid_w) begin
                    if (!inner_r && op_w == 8'h02 && inner_width_w > 0 &&
                        inner_height_w > 0 && $signed({6'd0, y_r}) >= inner_top_w &&
                        $signed({6'd0, y_r}) <= inner_bottom_w) begin
                        inner_r <= 1'b1;
                        inner_inside_r <= 1'b1;
                        state_r <= S_EDGE_REQ;
                    end else
                        state_r <= S_PIXEL;
                end
                S_PIXEL: begin
                    lane_r <= 1'b0;
                    pair_r <= x_r < right_w[11:0] &&
                        dst_addr_w[4:0] <= (argb_w ? 5'd24 : 5'd28);
                    if (target_valid_r && target_addr_r != {dst_addr_w[31:5], 5'd0}) begin
                        write_return_r <= S_PIXEL;
                        state_r <= S_WRITE;
                    end else if (!target_valid_r) begin
                        read_dest_r <= 1'b1;
                        read_return_r <= S_DEST;
                        state_r <= S_READ;
                    end else
                        state_r <= S_SOURCE;
                end
                S_DEST: begin
                    target_valid_r <= 1'b1;
                    state_r <= S_SOURCE;
                end
                S_SOURCE: begin
                    if (op_w == 8'h01 || op_w == 8'h02) begin
                        if (!lane_r && pair_r)
                            lane_r <= 1'b1;
                        else begin
                            lane_r <= 1'b0;
                            state_r <= S_BLEND;
                        end
                    end else
                        state_r <= op_w == 8'h08 ? S_MAP : S_SAMPLE;
                end
                S_MAP, S_SAMPLE: begin
                    if (query_hit_w) begin
                        if (state_r == S_MAP)
                            state_r <= S_SAMPLE;
                        else
                            state_r <= format_w >= 4'd6 ? S_PALETTE : S_CONVERT;
                    end else begin
                        read_dest_r <= 1'b0;
                        read_return_r <= state_r;
                        state_r <= S_READ;
                    end
                end
                S_PALETTE: state_r <= S_CONVERT;
                S_PALETTE_LOAD: begin
                    if (query_hit_w) begin
                        if (palette_index_r == palette_last_w)
                            state_r <= S_ROW;
                        else
                            palette_index_r <= palette_index_r + 8'd1;
                    end else begin
                        read_dest_r <= 1'b0;
                        read_return_r <= S_PALETTE_LOAD;
                        state_r <= S_READ;
                    end
                end
                S_CONVERT: begin
                    if (!lane_r && pair_r) begin
                        lane_r <= 1'b1;
                        state_r <= S_SOURCE;
                    end else begin
                        lane_r <= 1'b0;
                        state_r <= S_BLEND;
                    end
                end
                S_BLEND: if (blend_ready_i)
                    state_r <= S_BLEND_WAIT;
                S_BLEND_WAIT: if (blend_valid_i) begin
                    pixel_count_r <= pair_r ? 5'd2 : 5'd1;
                    if ({1'd0, x_r} + (pair_r ? 13'd1 : 13'd0) >= {1'd0, right_w[11:0]}) begin
                        write_return_r <= y_r == bottom_w[11:0] ? S_DONE : S_NEXT_ROW;
                        state_r <= S_WRITE;
                    end else begin
                        x_r <= x_r + (pair_r ? 12'd2 : 12'd1);
                        state_r <= S_PIXEL;
                    end
                end
                S_READ: if (rd_ready_i)
                    state_r <= S_READ_WAIT;
                S_READ_WAIT: if (rd_data_valid_i) begin
                    if (!read_dest_r) begin
                        if (read_return_r == S_MAP)
                            map_valid_r <= 1'b1;
                        else
                            source_valid_r <= 1'b1;
                    end
                    state_r <= read_return_r;
                end
                S_WRITE: if (wr_ready_i)
                    state_r <= S_WRITE_WAIT;
                S_WRITE_WAIT: if (wr_done_i) begin
                    target_valid_r <= 1'b0;
                    state_r <= write_return_r;
                end
                S_NEXT_ROW: begin
                    x_r <= left_w[11:0];
                    y_r <= y_r + 12'd1;
                    state_r <= S_ROW;
                end
                S_DONE: state_r <= S_IDLE;
                default: state_r <= state_r;
            endcase
        end
    end
    always @(posedge clk_i) begin
        if (state_r == S_EDGE_WAIT && edge_valid_w) begin
            if (inner_r)
                inner_edge_r <= edge_w;
            else
                outer_edge_r <= edge_w;
        end
        if (state_r == S_PIXEL && !target_valid_r) begin
            read_addr_r <= {dst_addr_w[31:5], 5'd0};
            target_addr_r <= {dst_addr_w[31:5], 5'd0};
        end
        if ((state_r == S_MAP || state_r == S_SAMPLE || state_r == S_PALETTE_LOAD) &&
            !query_hit_w)
            read_addr_r <= {query_addr_w[31:5], 5'd0};
        if (state_r == S_READ_WAIT && rd_data_valid_i) begin
            if (read_dest_r) begin
                target_data_r <= rd_data_i;
                target_strb_r <= 32'd0;
            end else if (read_return_r == S_MAP) begin
                map_data_r <= rd_data_i;
                map_addr_r <= read_addr_r;
            end else begin
                source_data_r <= rd_data_i;
                source_addr_r <= read_addr_r;
            end
        end
        if (query_hit_w) begin
            if (state_r == S_MAP)
                map_entry_r <= query_shifted_w[15:0];
            if (state_r == S_SAMPLE)
                raw_r <= query_shifted_w[31:0];
        end
        if (state_r == S_CONVERT)
            src_r[lane_r*32 +: 32] <= converted_w;
        if (state_r == S_SOURCE && (op_w == 8'h01 || op_w == 8'h02))
            src_r[lane_r*32 +: 32] <= op_w == 8'h01 ? fill_pixel_w : border_pixel_w;
        if (state_r == S_BLEND_WAIT && blend_valid_i) begin
            for (lane = 0; lane < 2; lane = lane + 1) begin
                if (lane == 0 || pair_r) begin
                    if (argb_w) begin
                        target_data_r[({27'd0, dst_addr_w[4:0]}+lane*4)*8 +: 32] <=
                            blend_pixel_i[lane*32 +: 32];
                        target_strb_r[{27'd0, dst_addr_w[4:0]}+lane*4 +: 4] <= 4'hf;
                    end else begin
                        target_data_r[({27'd0, dst_addr_w[4:0]}+lane*2)*8 +: 16] <=
                            blend_pixel_i[lane*32 +: 16];
                        target_strb_r[{27'd0, dst_addr_w[4:0]}+lane*2 +: 2] <= 2'b11;
                    end
                end
            end
        end
    end
endmodule
