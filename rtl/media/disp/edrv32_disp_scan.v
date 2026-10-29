// File: edrv32_disp_scan.v
// Spec: disp-spec 2.3, 2.4, 2.7, 4.3, 6.
// Description: Scan scrolled RGB565 and rectangular ARGB8888 with independent debt.
//              Blend non-premultiplied pixels using the specified divide-by-255 rounding.
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
    output wire [31:0] perf1_o,
    output wire [31:0] perf2_o,
    output wire [31:0] perf5_o,
    output wire [31:0] perf6_o
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
    reg [31:0] perf0_r;
    reg [31:0] perf1_r;
    reg [31:0] perf2_r;
    reg [31:0] perf5_r;
    reg [31:0] perf6_r;
    wire frame_begin_w;
    wire [55:0] cfg_w;
    wire l0_en_w;
    wire [3:0] offset_w;
    wire l1_en_w;
    wire [10:0] l1_x_w;
    wire [9:0] l1_y_w;
    wire [10:0] l1_width_w;
    wire [9:0] l1_height_w;
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
    wire [255:0] l0_packet_w;
    wire l0_good_w;
    wire [15:0] pixel_w;
    wire [31:0] pixel1_w;
    wire [23:0] background_w;
    wire [15:0] alpha_product_w;
    wire [7:0] alpha_w;
    wire [7:0] inverse_alpha_w;
    wire [15:0] red_w;
    wire [15:0] green_w;
    wire [15:0] blue_w;

    // spec 2.7: t and its shifted correction retain the carry above bit 15.
    function [7:0] divide255;
        input [15:0] value_i;
        reg [16:0] t_w;
        reg [16:0] corrected_w;
        reg [8:0] unused_correction_w;
        begin
            t_w = {1'b0, value_i} + 17'd128;
            corrected_w = t_w + (t_w >> 8);
            divide255 = corrected_w[15:8];
            unused_correction_w = {corrected_w[16], corrected_w[7:0]};
        end
    endfunction

    assign frame_req_o = vblank_i && enable_i;
    assign frame_begin_w = scan_frame_r && de_i && x_i == 11'd0 && y_i == 10'd0;
    // A new parameter message during a frame changes only the next frame.
    assign cfg_w = frame_begin_w ? params_r : frame_params_r;
    assign {l0_en_w, offset_w, l1_en_w, l1_x_w, l1_y_w, l1_width_w,
        l1_height_w, opacity_w} = cfg_w;
    assign l1_x_end_w = {1'b0, l1_x_w} + {1'b0, l1_width_w};
    assign l1_y_end_w = {1'b0, l1_y_w} + {1'b0, l1_height_w};
    assign phase_w = x_i[3:0] + offset_w;
    assign l0_active_w = scan_frame_r && de_i && l0_en_w;
    assign l1_active_w = scan_frame_r && de_i && l1_en_w && x_i >= l1_x_w &&
        {1'b0, x_i} < l1_x_end_w && y_i >= l1_y_w && {1'b0, y_i} < l1_y_end_w;
    assign group_start_w = l0_active_w && (x_i == 11'd0 || phase_w == 4'd0);
    // X is eight-pixel aligned, so screen and Surface beat boundaries coincide.
    assign group1_start_w = l1_active_w && x_i[2:0] == 3'd0;
    assign group_good_w = debt_r == 32'd0 && fifo_valid_i;
    assign group1_good_w = debt1_r == 32'd0 && fifo1_valid_i;
    assign missing_w = group_start_w && !group_good_w;
    assign missing1_w = group1_start_w && !group1_good_w;
    assign discard_w = debt_r != 32'd0 && fifo_valid_i;
    assign discard1_w = debt1_r != 32'd0 && fifo1_valid_i;
    assign fifo_ready_o = debt_r != 32'd0 || group_start_w;
    assign fifo1_ready_o = debt1_r != 32'd0 || group1_start_w;
    assign underflow_o = missing_w && !underflow_seen_r;
    assign underflow1_o = missing1_w && !underflow1_seen_r;
    // Select the lane instead of rotating a whole 256-bit beat by the scroll offset.
    assign l0_packet_w = group_start_w ? fifo_data_i : pixels_r;
    assign l0_good_w = group_start_w ? group_good_w : group_good_r;
    assign pixel_w = l0_active_w && l0_good_w ?
        l0_packet_w[{phase_w, 4'd0} +: 16] : 16'd0;
    assign pixel1_w = !l1_active_w ? 32'd0 : (group1_start_w ?
        (group1_good_w ? fifo1_data_i[31:0] : 32'd0) :
        (group1_good_r ? pixels1_r[31:0] : 32'd0));
    assign background_w = {pixel_w[15:11], pixel_w[15:13], pixel_w[10:5],
        pixel_w[10:9], pixel_w[4:0], pixel_w[4:2]};
    assign alpha_product_w = pixel1_w[31:24] * opacity_w;
    assign alpha_w = divide255(alpha_product_w);
    assign inverse_alpha_w = 8'd255 - alpha_w;
    assign red_w = alpha_w * pixel1_w[23:16] + inverse_alpha_w * background_w[23:16];
    assign green_w = alpha_w * pixel1_w[15:8] + inverse_alpha_w * background_w[15:8];
    assign blue_w = alpha_w * pixel1_w[7:0] + inverse_alpha_w * background_w[7:0];
    assign rgb_o = {divide255(red_w), divide255(green_w), divide255(blue_w)};
    assign read_cnt_o = read_cnt_r;
    assign read1_cnt_o = read1_cnt_r;
    assign perf0_o = perf0_r;
    assign perf1_o = perf1_r;
    assign perf2_o = perf2_r;
    assign perf5_o = perf5_r;
    assign perf6_o = perf6_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            scan_frame_r <= 1'b0;
            params_r <= RESET_PARAMS;
            frame_params_r <= RESET_PARAMS;
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
            perf2_r <= 32'd0;
            perf5_r <= 32'd0;
            perf6_r <= 32'd0;
        end else begin
            if (params_valid_i) begin
                params_r <= params_i;
            end
            if (frame_begin_w) begin
                frame_params_r <= params_r;
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
            if (group_start_w) begin
                group_good_r <= group_good_w;
            end
            if (group1_start_w) begin
                group1_good_r <= group1_good_w;
            end
            if (fifo_valid_i && fifo_ready_o) begin
                read_cnt_r <= read_cnt_r + 10'd1;
            end
            if (fifo1_valid_i && fifo1_ready_o) begin
                read1_cnt_r <= read1_cnt_r + 10'd1;
            end
            if (scan_frame_r && de_i && x_i == 11'd1279 && y_i == 10'd719) begin
                perf0_r <= perf0_r + 32'd1;
            end
            if (underflow_o) begin
                perf1_r <= perf1_r + 32'd1;
            end
            if (underflow1_o) begin
                perf5_r <= perf5_r + 32'd1;
            end
            if (missing_w) begin
                perf2_r <= perf2_r + 32'd1;
            end
            if (missing1_w) begin
                perf6_r <= perf6_r + 32'd1;
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
        if (group_start_w && group_good_w) begin
            pixels_r <= fifo_data_i;
        end
        if (group1_start_w && group1_good_w) begin
            pixels1_r <= fifo1_data_i[255:32];
        end else if (l1_active_w) begin
            pixels1_r <= {32'd0, pixels1_r[223:32]};
        end
    end
endmodule
