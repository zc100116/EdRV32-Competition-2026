// File: edrv32_disp_scan.v
// Spec: disp-spec 2.3, 2.4, 2.7, 4.3, 6.
// Description: Scan scrolled RGB565 and rectangular ARGB8888 with independent debt.
//              Eleven stages separate rectangle decode, products and divide-by-255 rounding.
// Clock domain: clk_pix (clk_i).
module edrv32_disp_scan (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Raster, synchronized scan enable and acknowledged frame parameters.
    input wire enable_i,
    input wire de_i,
    input wire [10:0] x_i,
    input wire [9:0] y_i,
    input wire vblank_i,
    input wire frame_start_i,
    input wire params_valid_i,
    input wire [55:0] params_i,

    // Independent L0 and L1 FIFO consumers.
    input wire fifo_valid_i,
    output wire fifo_ready_o,
    input wire [255:0] fifo_data_i,
    input wire fifo1_valid_i,
    output wire fifo1_ready_o,
    input wire [255:0] fifo1_data_i,
    output wire [23:0] rgb_o,

    // Events and unit-step counters for X6 CDC.
    output wire frame_req_o,
    output wire underflow_o,
    output wire underflow1_o,
    output wire [9:0] read_cnt_o,
    output wire [9:0] read1_cnt_o,
    output wire [31:0] perf0_o,
    output wire [31:0] perf1_o
);
    localparam [55:0] RESET_PARAMS = {1'b1, 4'd0, 1'b0, 11'd0, 10'd0,
        11'd1280, 10'd720, 8'd255};
    reg scan_frame_r;
    reg [55:0] params_r;
    reg [55:0] frame_params_r;
    reg group_good_r;
    reg group1_good_r;
    reg underflow_seen_r;
    reg underflow1_seen_r;
    reg [255:0] pixels_r;
    reg [223:0] pixels1_r;
    reg [31:0] debt_r;
    reg [31:0] debt1_r;
    reg [9:0] read_cnt_r;
    reg [9:0] read1_cnt_r;
    reg [1:0] perf_event_r;
    reg [31:0] perf0_r;
    reg [31:0] perf1_r;
    // S0 captures raster; S1 compares row/column; S2 combines registered decisions.
    wire frame_begin_w;
    // Detect the last pixel at S1 and count completion with its S10 RGB output.
    reg [8:0] frame_last_pipe_r;
    reg raster_active_r;
    reg [10:0] raster_x_r;
    reg [9:0] raster_y_r;
    reg [11:0] params_x_end_r;
    reg [10:0] params_y_end_r;
    reg [11:0] frame_x_end_r;
    reg [10:0] frame_y_end_r;
    reg l0_decode_r;
    reg l1_decode_r;
    reg l1_column_r;
    reg l1_row_r;
    reg group_decode_r;
    reg group1_decode_r;
    reg [3:0] phase_decode_r;
    reg [7:0] opacity_decode_r;
    reg l0_active_r;
    reg l1_active_r;
    reg group_start_r;
    reg group1_start_r;
    reg [3:0] phase_r;
    reg [7:0] opacity_r;

    // S3 selects pixels, S4 multiplies alpha, S5/S6 evaluate d(alpha*OPA).
    reg [23:0] select_background_r;
    reg [31:0] select_foreground_r;
    reg [7:0] select_opacity_r;
    reg [23:0] alpha_background_r;
    reg [23:0] alpha_foreground_r;
    reg [15:0] alpha_product_r;
    reg [23:0] round_background_r;
    reg [23:0] round_foreground_r;
    reg [16:0] alpha_round_r;
    reg [23:0] blend_background_r;
    reg [23:0] blend_foreground_r;
    reg [7:0] alpha_r;

    // S7 contains only parallel products; S8 sums; S9/S10 evaluate d(sum).
    reg [15:0] red_foreground_r;
    reg [15:0] green_foreground_r;
    reg [15:0] blue_foreground_r;
    reg [15:0] red_background_r;
    reg [15:0] green_background_r;
    reg [15:0] blue_background_r;
    reg [15:0] red_sum_r;
    reg [15:0] green_sum_r;
    reg [15:0] blue_sum_r;
    reg [16:0] red_round_r;
    reg [16:0] green_round_r;
    reg [16:0] blue_round_r;
    reg [23:0] rgb_r;
    wire [55:0] cfg_w;
    wire l0_en_w;
    wire [3:0] offset_w;
    wire l1_en_w;
    wire [10:0] l1_x_w;
    wire [9:0] l1_y_w;
    wire [10:0] unused_l1_width_w;
    wire [9:0] unused_l1_height_w;
    wire [7:0] opacity_w;
    wire [11:0] l1_x_end_w;
    wire [10:0] l1_y_end_w;
    wire [3:0] phase_w;
    wire group_start_w;
    wire group1_start_w;
    wire group_good_w;
    wire group1_good_w;
    wire missing_w;
    wire missing1_w;
    wire discard_w;
    wire discard1_w;
    wire l0_active_w;
    wire l1_active_w;
    wire l1_column_w;
    wire l1_row_w;
    wire [255:0] l0_packet_w;
    wire l0_good_w;
    wire [15:0] pixel_w;
    wire [31:0] pixel1_w;
    wire [23:0] background_w;
    wire [7:0] inverse_alpha_w;
    wire [16:0] alpha_corrected_w;
    wire [16:0] red_corrected_w;
    wire [16:0] green_corrected_w;
    wire [16:0] blue_corrected_w;
    wire [35:0] unused_correction_w;

    assign frame_req_o = vblank_i && enable_i;
    // A new parameter message during a frame changes only the next frame.
    assign frame_begin_w = scan_frame_r && frame_start_i;
    // The frame-begin comparison terminates at config FFs, before rectangle decode.
    assign cfg_w = frame_params_r;
    assign {l0_en_w, offset_w, l1_en_w, l1_x_w, l1_y_w, unused_l1_width_w,
        unused_l1_height_w, opacity_w} = cfg_w;
    // Cache extent additions on parameter receipt, outside the per-pixel comparator cone.
    assign l1_x_end_w = frame_x_end_r;
    assign l1_y_end_w = frame_y_end_r;
    assign phase_w = raster_x_r[3:0] + offset_w;
    assign l0_active_w = raster_active_r && l0_en_w;
    assign l1_column_w = raster_x_r >= l1_x_w && {1'b0, raster_x_r} < l1_x_end_w;
    assign l1_row_w = raster_y_r >= l1_y_w && {1'b0, raster_y_r} < l1_y_end_w;
    assign l1_active_w = l1_decode_r && l1_column_r && l1_row_r;
    assign group_start_w = l0_active_w && (raster_x_r == 11'd0 || phase_w == 4'd0);
    // X is eight-pixel aligned, so screen and Surface beat boundaries coincide.
    assign group1_start_w = raster_x_r[2:0] == 3'd0;
    assign group_good_w = debt_r == 32'd0 && fifo_valid_i;
    assign group1_good_w = debt1_r == 32'd0 && fifo1_valid_i;
    assign missing_w = group_start_r && !group_good_w;
    assign missing1_w = group1_start_r && !group1_good_w;
    assign discard_w = debt_r != 32'd0 && fifo_valid_i;
    assign discard1_w = debt1_r != 32'd0 && fifo1_valid_i;
    assign fifo_ready_o = debt_r != 32'd0 || group_start_r;
    assign fifo1_ready_o = debt1_r != 32'd0 || group1_start_r;
    assign underflow_o = missing_w && !underflow_seen_r;
    assign underflow1_o = missing1_w && !underflow1_seen_r;
    // Select the lane instead of rotating a whole 256-bit beat by the scroll offset.
    assign l0_packet_w = group_start_r ? fifo_data_i : pixels_r;
    assign l0_good_w = group_start_r ? group_good_w : group_good_r;
    assign pixel_w = l0_active_r && l0_good_w ?
        l0_packet_w[{phase_r, 4'd0} +: 16] : 16'd0;
    assign pixel1_w = !l1_active_r ? 32'd0 : (group1_start_r ?
        (group1_good_w ? fifo1_data_i[31:0] : 32'd0) :
        (group1_good_r ? pixels1_r[31:0] : 32'd0));
    assign background_w = {pixel_w[15:11], pixel_w[15:13], pixel_w[10:5],
        pixel_w[10:9], pixel_w[4:0], pixel_w[4:2]};
    // spec 2.7: retain the carry above bit 15 in both steps of d(x).
    assign alpha_corrected_w = alpha_round_r + (alpha_round_r >> 8);
    assign red_corrected_w = red_round_r + (red_round_r >> 8);
    assign green_corrected_w = green_round_r + (green_round_r >> 8);
    assign blue_corrected_w = blue_round_r + (blue_round_r >> 8);
    assign unused_correction_w = {alpha_corrected_w[16], alpha_corrected_w[7:0],
        red_corrected_w[16], red_corrected_w[7:0], green_corrected_w[16],
        green_corrected_w[7:0], blue_corrected_w[16], blue_corrected_w[7:0]};
    assign inverse_alpha_w = 8'd255 - alpha_r;
    assign rgb_o = rgb_r;
    assign read_cnt_o = read_cnt_r;
    assign read1_cnt_o = read1_cnt_r;
    assign perf0_o = perf0_r;
    assign perf1_o = perf1_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            scan_frame_r <= 1'b0;
            params_r <= RESET_PARAMS;
            frame_params_r <= RESET_PARAMS;
            params_x_end_r <= 12'd1280;
            params_y_end_r <= 11'd720;
            frame_x_end_r <= 12'd1280;
            frame_y_end_r <= 11'd720;
            frame_last_pipe_r <= 9'd0;
            raster_active_r <= 1'b0;
            l0_decode_r <= 1'b0;
            l1_decode_r <= 1'b0;
            l1_column_r <= 1'b0;
            l1_row_r <= 1'b0;
            group_decode_r <= 1'b0;
            group1_decode_r <= 1'b0;
            l0_active_r <= 1'b0;
            l1_active_r <= 1'b0;
            group_start_r <= 1'b0;
            group1_start_r <= 1'b0;
            group_good_r <= 1'b0;
            group1_good_r <= 1'b0;
            underflow_seen_r <= 1'b0;
            underflow1_seen_r <= 1'b0;
            debt_r <= 32'd0;
            debt1_r <= 32'd0;
            read_cnt_r <= 10'd0;
            read1_cnt_r <= 10'd0;
            perf0_r <= 32'd0;
            perf1_r <= 32'd0;
        end else begin
            frame_last_pipe_r <= {frame_last_pipe_r[7:0],
                raster_active_r && raster_x_r == 11'd1279 && raster_y_r == 10'd719};
            raster_active_r <= scan_frame_r && de_i;
            l0_decode_r <= l0_active_w;
            l1_decode_r <= raster_active_r && l1_en_w;
            l1_column_r <= l1_column_w;
            l1_row_r <= l1_row_w;
            group_decode_r <= group_start_w;
            group1_decode_r <= group1_start_w;
            l0_active_r <= l0_decode_r;
            l1_active_r <= l1_active_w;
            group_start_r <= group_decode_r;
            group1_start_r <= l1_active_w && group1_decode_r;
            if (params_valid_i) begin
                params_r <= params_i;
                params_x_end_r <= {1'b0, params_i[49:39]} + {1'b0, params_i[28:18]};
                params_y_end_r <= {1'b0, params_i[38:29]} + {1'b0, params_i[17:8]};
            end
            if (frame_begin_w) begin
                frame_params_r <= params_r;
                frame_x_end_r <= params_x_end_r;
                frame_y_end_r <= params_y_end_r;
            end
            if (vblank_i) begin
                scan_frame_r <= enable_i;
                underflow_seen_r <= 1'b0;
                underflow1_seen_r <= 1'b0;
            end else begin
                if (underflow_o) begin
                    underflow_seen_r <= 1'b1;
                end
                if (underflow1_o) begin
                    underflow1_seen_r <= 1'b1;
                end
            end
            if (group_start_r) begin
                group_good_r <= group_good_w;
            end
            if (group1_start_r) begin
                group1_good_r <= group1_good_w;
            end
            if (fifo_valid_i && fifo_ready_o) begin
                read_cnt_r <= read_cnt_r + 10'd1;
            end
            if (fifo1_valid_i && fifo1_ready_o) begin
                read1_cnt_r <= read1_cnt_r + 10'd1;
            end
            if (perf_event_r[0]) begin
                perf0_r <= perf0_r + 32'd1;
            end
            if (perf_event_r[1]) begin
                perf1_r <= perf1_r + 32'd1;
            end
            if (missing_w != discard_w) begin
                debt_r <= missing_w ? debt_r + 32'd1 : debt_r - 32'd1;
            end
            if (missing1_w != discard1_w) begin
                debt1_r <= missing1_w ? debt1_r + 32'd1 : debt1_r - 32'd1;
            end
        end
    end

    always @(posedge clk_i) begin
        raster_x_r <= x_i;
        raster_y_r <= y_i;
        phase_decode_r <= phase_w;
        opacity_decode_r <= opacity_w;
        phase_r <= phase_decode_r;
        opacity_r <= opacity_decode_r;
        select_background_r <= background_w;
        select_foreground_r <= pixel1_w;
        select_opacity_r <= opacity_r;
        alpha_product_r <= select_foreground_r[31:24] * select_opacity_r;
        alpha_background_r <= select_background_r;
        alpha_foreground_r <= select_foreground_r[23:0];
        alpha_round_r <= {1'b0, alpha_product_r} + 17'd128;
        round_background_r <= alpha_background_r;
        round_foreground_r <= alpha_foreground_r;
        alpha_r <= alpha_corrected_w[15:8];
        blend_background_r <= round_background_r;
        blend_foreground_r <= round_foreground_r;
        red_foreground_r <= alpha_r * blend_foreground_r[23:16];
        green_foreground_r <= alpha_r * blend_foreground_r[15:8];
        blue_foreground_r <= alpha_r * blend_foreground_r[7:0];
        red_background_r <= inverse_alpha_w * blend_background_r[23:16];
        green_background_r <= inverse_alpha_w * blend_background_r[15:8];
        blue_background_r <= inverse_alpha_w * blend_background_r[7:0];
        red_sum_r <= red_foreground_r + red_background_r;
        green_sum_r <= green_foreground_r + green_background_r;
        blue_sum_r <= blue_foreground_r + blue_background_r;
        red_round_r <= {1'b0, red_sum_r} + 17'd128;
        green_round_r <= {1'b0, green_sum_r} + 17'd128;
        blue_round_r <= {1'b0, blue_sum_r} + 17'd128;
        rgb_r <= {red_corrected_w[15:8], green_corrected_w[15:8],
            blue_corrected_w[15:8]};
        if (group_start_r && group_good_w) begin
            pixels_r <= fifo_data_i;
        end
        if (group1_start_r && group1_good_w) begin
            pixels1_r <= fifo1_data_i[255:32];
        end else if (l1_active_r) begin
            pixels1_r <= {32'd0, pixels1_r[223:32]};
        end
    end
    // SoC 7.1: terminate scan events before the performance adders.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            perf_event_r <= 2'd0;
        else
            perf_event_r <= {underflow_o,
                frame_last_pipe_r[8]};
    end
endmodule
