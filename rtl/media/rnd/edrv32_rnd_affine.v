// File: edrv32_rnd_affine.v
// Spec: rnd-spec v0.3 2.6 AFFINE_BLIT, 5.2.
// Description: Signed48 inverse-map increments follow the clipped 32x16 traversal;
//              initial offsets use shift/add, then the window feeds one filter lane.
// Clock domain: clk_mem (clk_i).
module edrv32_rnd_affine (
    // Clock and command ownership.
    input wire clk_i,
    input wire rst_n_i,
    input wire clear_i,
    input wire start_i,
    input wire [511:0] command_i,
    input wire [1023:0] parameters_i,
    input wire [11:0] left_i,
    input wire [11:0] top_i,
    input wire [11:0] right_i,
    input wire [11:0] bottom_i,

    // One destination pixel in traversal order.
    input wire in_valid_i,
    output wire in_ready_o,
    input wire [31:0] destination_i,
    input wire [31:0] tag_i,
    input wire [7:0] coverage_i,
    output wire out_valid_o,
    input wire out_ready_i,
    output wire [31:0] pixel_o,
    output wire [31:0] destination_o,
    output wire [31:0] tag_o,
    output wire [7:0] coverage_o,
    output wire read_wait_o,

    // Window miss/decoded palette clients.
    output wire rd_valid_o,
    input wire rd_ready_i,
    output wire [31:0] rd_addr_o,
    output wire [15:0] rd_bytes_o,
    input wire rd_data_valid_i,
    input wire [255:0] rd_data_i,
    input wire rd_done_i,
    output wire palette_valid_o,
    output wire [15:0] palette_index_o,
    input wire [63:0] palette_data_i
);
    localparam [2:0] S_IDLE = 3'd0;
    localparam [2:0] S_X = 3'd1;
    localparam [2:0] S_Y = 3'd2;
    localparam [2:0] S_SEED = 3'd3;
    localparam [2:0] S_READY = 3'd4;
    reg [2:0] state_r;
    reg [3:0] bit_r;
    reg [15:0] initial_mask_r;
    reg signed [47:0] initial_u_r;
    reg signed [47:0] initial_v_r;
    reg signed [47:0] step_u_r;
    reg signed [47:0] step_v_r;
    reg signed [47:0] u_r;
    reg signed [47:0] v_r;
    reg signed [47:0] row_u_r;
    reg signed [47:0] row_v_r;
    reg signed [47:0] tile_end_u_r;
    reg signed [47:0] tile_end_v_r;
    reg signed [47:0] band_next_u_r;
    reg signed [47:0] band_next_v_r;
    reg [11:0] x_r;
    reg [11:0] y_r;
    reg [11:0] tile_left_r;
    reg [11:0] tile_right_r;
    reg [11:0] tile_top_r;
    reg [11:0] tile_bottom_r;
    wire signed [17:0] offset_x_w;
    wire signed [17:0] offset_y_w;
    wire [12:0] first_right_w;
    wire [12:0] first_bottom_w;
    wire [12:0] next_right_w;
    wire [12:0] next_bottom_w;
    wire signed [47:0] du_x_w;
    wire signed [47:0] dv_x_w;
    wire signed [47:0] du_y_w;
    wire signed [47:0] dv_y_w;
    wire signed [47:0] sample_u_w;
    wire signed [47:0] sample_v_w;
    wire signed [47:0] next_tile_u_w;
    wire signed [47:0] next_tile_v_w;
    wire signed [47:0] next_band_u_w;
    wire signed [47:0] next_band_v_w;
    wire window_ready_w;
    wire window_valid_w;
    wire filter_ready_w;
    wire [127:0] taps_w;
    wire [7:0] fraction_x_w;
    wire [7:0] fraction_y_w;
    wire [31:0] destination_w;
    wire [31:0] tag_w;
    wire [7:0] coverage_w;
    wire unused_parameters_w;
    assign offset_x_w = $signed({6'd0, left_i}) -
        $signed({{2{command_i[175]}}, command_i[175:160]});
    assign offset_y_w = $signed({6'd0, top_i}) -
        $signed({{2{command_i[191]}}, command_i[191:176]});
    assign first_right_w = {1'b0, left_i} + 13'd31 - {8'd0, offset_x_w[4:0]};
    assign first_bottom_w = {1'b0, top_i} + 13'd15 - {9'd0, offset_y_w[3:0]};
    assign next_right_w = {1'b0, tile_right_r} + 13'd32;
    assign next_bottom_w = {1'b0, tile_bottom_r} + 13'd16;
    assign du_x_w = {{16{parameters_i[95]}}, parameters_i[95:64]};
    assign dv_x_w = {{16{parameters_i[127]}}, parameters_i[127:96]};
    assign du_y_w = {{16{parameters_i[159]}}, parameters_i[159:128]};
    assign dv_y_w = {{16{parameters_i[191]}}, parameters_i[191:160]};
    assign sample_u_w = u_r - (command_i[16] ? 48'sd32768 : 48'sd0);
    assign sample_v_w = v_r - (command_i[16] ? 48'sd32768 : 48'sd0);
    assign next_tile_u_w = (y_r == tile_top_r ? u_r : tile_end_u_r) + du_x_w;
    assign next_tile_v_w = (y_r == tile_top_r ? v_r : tile_end_v_r) + dv_x_w;
    assign next_band_u_w = tile_left_r == left_i ? row_u_r + du_y_w : band_next_u_r;
    assign next_band_v_w = tile_left_r == left_i ? row_v_r + dv_y_w : band_next_v_r;
    assign in_ready_o = state_r == S_READY && window_ready_w;
    assign unused_parameters_w = ^{parameters_i[1023:192], offset_x_w[17:16],
        offset_y_w[17:16], sample_u_w[7:0], sample_v_w[7:0]};
    edrv32_rnd_window u_window (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .clear_i(clear_i),
        .start_i(start_i),
        .command_i(command_i),
        .in_valid_i(in_valid_i && state_r == S_READY),
        .in_ready_o(window_ready_w),
        .x_i(sample_u_w[47:16]),
        .y_i(sample_v_w[47:16]),
        .fraction_x_i(command_i[16] ? sample_u_w[15:8] : 8'd0),
        .fraction_y_i(command_i[16] ? sample_v_w[15:8] : 8'd0),
        .destination_i(destination_i),
        .tag_i(tag_i),
        .coverage_i(coverage_i),
        .out_valid_o(window_valid_w),
        .out_ready_i(filter_ready_w),
        .taps_o(taps_w),
        .fraction_x_o(fraction_x_w),
        .fraction_y_o(fraction_y_w),
        .destination_o(destination_w),
        .tag_o(tag_w),
        .coverage_o(coverage_w),
        .read_wait_o(read_wait_o),
        .rd_valid_o(rd_valid_o),
        .rd_ready_i(rd_ready_i),
        .rd_addr_o(rd_addr_o),
        .rd_bytes_o(rd_bytes_o),
        .rd_data_valid_i(rd_data_valid_i),
        .rd_data_i(rd_data_i),
        .rd_done_i(rd_done_i),
        .palette_valid_o(palette_valid_o),
        .palette_index_o(palette_index_o),
        .palette_data_i(palette_data_i)
    );
    edrv32_rnd_filter u_filter (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .clear_i(clear_i || start_i),
        .in_valid_i(window_valid_w),
        .in_ready_o(filter_ready_w),
        .bilinear_i(command_i[16]),
        .taps_i(taps_w),
        .fraction_x_i(fraction_x_w),
        .fraction_y_i(fraction_y_w),
        .destination_i(destination_w),
        .tag_i(tag_w),
        .coverage_i(coverage_w),
        .out_valid_o(out_valid_o),
        .out_ready_i(out_ready_i),
        .pixel_o(pixel_o),
        .destination_o(destination_o),
        .tag_o(tag_o),
        .coverage_o(coverage_o)
    );
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            bit_r <= 4'd0;
        end else if (clear_i || start_i) begin
            state_r <= clear_i ? S_IDLE : S_X;
            bit_r <= 4'd0;
        end else begin
            case (state_r)
                S_X: begin
                    bit_r <= bit_r + 4'd1;
                    if (bit_r == 15)
                        state_r <= S_Y;
                end
                S_Y: begin
                    bit_r <= bit_r + 4'd1;
                    if (bit_r == 15)
                        state_r <= S_SEED;
                end
                S_SEED: state_r <= S_READY;
                default: state_r <= state_r;
            endcase
        end
    end
    // Start seeds the offset before S_X/S_Y serially consume its bits.
    always @(posedge clk_i) begin
        if (clear_i || start_i)
            initial_mask_r <= offset_x_w[15:0];
        else if (state_r == S_X)
            initial_mask_r <= bit_r == 15 ? offset_y_w[15:0] : initial_mask_r >> 1;
        else if (state_r == S_Y)
            initial_mask_r <= initial_mask_r >> 1;
    end
    always @(posedge clk_i) begin
        if (start_i) begin
            initial_u_r <= {{16{parameters_i[31]}}, parameters_i[31:0]};
            initial_v_r <= {{16{parameters_i[63]}}, parameters_i[63:32]};
            step_u_r <= du_x_w;
            step_v_r <= dv_x_w;
            x_r <= left_i;
            y_r <= top_i;
            tile_left_r <= left_i;
            tile_top_r <= top_i;
            tile_right_r <= first_right_w < {1'b0, right_i} ? first_right_w[11:0] : right_i;
            tile_bottom_r <= first_bottom_w < {1'b0, bottom_i} ?
                first_bottom_w[11:0] : bottom_i;
        end else begin
            if (state_r == S_X || state_r == S_Y) begin
                if (initial_mask_r[0]) begin
                    initial_u_r <= initial_u_r + step_u_r;
                    initial_v_r <= initial_v_r + step_v_r;
                end
                step_u_r <= state_r == S_X && bit_r == 15 ? du_y_w : step_u_r <<< 1;
                step_v_r <= state_r == S_X && bit_r == 15 ? dv_y_w : step_v_r <<< 1;
            end
            if (state_r == S_SEED) begin
                u_r <= initial_u_r;
                v_r <= initial_v_r;
                row_u_r <= initial_u_r;
                row_v_r <= initial_v_r;
            end
            if (in_valid_i && in_ready_o) begin
                if (x_r == tile_right_r && y_r == tile_top_r) begin
                    tile_end_u_r <= u_r;
                    tile_end_v_r <= v_r;
                end
                if (x_r == tile_right_r && y_r == tile_bottom_r && tile_left_r == left_i) begin
                    band_next_u_r <= row_u_r + du_y_w;
                    band_next_v_r <= row_v_r + dv_y_w;
                end
                if (x_r < tile_right_r) begin
                    x_r <= x_r + 12'd1;
                    u_r <= u_r + du_x_w;
                    v_r <= v_r + dv_x_w;
                end else if (y_r < tile_bottom_r) begin
                    x_r <= tile_left_r;
                    y_r <= y_r + 12'd1;
                    row_u_r <= row_u_r + du_y_w;
                    row_v_r <= row_v_r + dv_y_w;
                    u_r <= row_u_r + du_y_w;
                    v_r <= row_v_r + dv_y_w;
                end else if (tile_right_r < right_i) begin
                    x_r <= tile_right_r + 12'd1;
                    y_r <= tile_top_r;
                    tile_left_r <= tile_right_r + 12'd1;
                    tile_right_r <= next_right_w < {1'b0, right_i} ?
                        next_right_w[11:0] : right_i;
                    row_u_r <= next_tile_u_w;
                    row_v_r <= next_tile_v_w;
                    u_r <= next_tile_u_w;
                    v_r <= next_tile_v_w;
                end else begin
                    x_r <= left_i;
                    y_r <= tile_bottom_r + 12'd1;
                    tile_left_r <= left_i;
                    tile_right_r <= first_right_w < {1'b0, right_i} ?
                        first_right_w[11:0] : right_i;
                    tile_top_r <= tile_bottom_r + 12'd1;
                    tile_bottom_r <= next_bottom_w < {1'b0, bottom_i} ?
                        next_bottom_w[11:0] : bottom_i;
                    row_u_r <= next_band_u_w;
                    row_v_r <= next_band_v_w;
                    u_r <= next_band_u_w;
                    v_r <= next_band_v_w;
                end
            end
        end
    end
endmodule
