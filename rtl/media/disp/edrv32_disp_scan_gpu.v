// File: edrv32_disp_scan_gpu.v
// Spec: gpu-soc-spec 8.2; disp-spec 2.3, 2.4, 2.7, 4.3, 6.
// Description: Scan scrolled RGB565 with beat debt and optional 2x replication.
//              Retain eleven-stage raster/RGB alignment after removing L1 mixing.
// Clock domain: clk_pix (clk_i).
module edrv32_disp_scan_gpu (
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
    input wire [5:0] params_i,

    // L0 FIFO consumer.
    input wire fifo_valid_i,
    output wire fifo_ready_o,
    input wire [255:0] fifo_data_i,
    output wire [23:0] rgb_o,

    // Events and unit-step counters for X6 CDC.
    output wire frame_req_o,
    output wire underflow_o,
    output wire [9:0] read_cnt_o,
    output wire [31:0] perf0_o,
    output wire [31:0] perf1_o
);
    localparam [5:0] RESET_PARAMS = {1'b0, 1'b1, 4'd0};
    reg scan_frame_r;
    reg [5:0] params_r;
    reg [5:0] frame_params_r;
    reg group_good_r;
    reg underflow_seen_r;
    reg [255:0] pixels_r;
    reg [31:0] debt_r;
    reg [9:0] read_cnt_r;
    reg [1:0] perf_event_r;
    reg [31:0] perf0_r;
    reg [31:0] perf1_r;
    wire frame_begin_w;
    reg [8:0] frame_last_pipe_r;
    reg raster_active_r;
    reg [10:0] raster_x_r;
    reg [9:0] raster_y_r;
    reg l0_decode_r;
    reg group_decode_r;
    reg [3:0] phase_decode_r;
    reg l0_active_r;
    reg group_start_r;
    reg [3:0] phase_r;
    reg [23:0] rgb_pipe_r [0:7];
    wire [23:0] rgb_next_w [0:7];
    genvar pixel_stage;
    wire l0_en_w;
    wire l0_x2_w;
    wire [3:0] offset_w;
    wire [3:0] phase_w;
    wire group_start_w;
    wire group_good_w;
    wire missing_w;
    wire discard_w;
    wire l0_active_w;
    wire [255:0] l0_packet_w;
    wire l0_good_w;
    wire [15:0] pixel_w;
    wire [15:0] lanes_w [0:15];
    genvar lane;
    wire [23:0] background_w;
    integer stage_idx;
    assign frame_req_o = vblank_i && enable_i;
    // A new parameter message during a frame changes only the next frame.
    assign frame_begin_w = scan_frame_r && frame_start_i;
    assign {l0_x2_w, l0_en_w, offset_w} = frame_params_r;
    // gpu-soc-spec 8.2: each beat covers 32 outputs; adjacent outputs share a lane.
    assign phase_w = l0_x2_w ? raster_x_r[4:1] : raster_x_r[3:0] + offset_w;
    assign l0_active_w = raster_active_r && l0_en_w;
    assign group_start_w = l0_active_w && (raster_x_r == 11'd0 ||
        (phase_w == 4'd0 && (!l0_x2_w || !raster_x_r[0])));
    assign group_good_w = debt_r == 32'd0 && fifo_valid_i;
    assign missing_w = group_start_r && !group_good_w;
    assign discard_w = debt_r != 32'd0 && fifo_valid_i;
    assign fifo_ready_o = debt_r != 32'd0 || group_start_r;
    assign underflow_o = missing_w && !underflow_seen_r;
    // Select the lane instead of rotating a whole 256-bit beat by the scroll offset.
    assign l0_packet_w = group_start_r ? fifo_data_i : pixels_r;
    assign l0_good_w = group_start_r ? group_good_w : group_good_r;
    generate
        for (lane = 0; lane < 16; lane = lane + 1) begin : g_lane
            assign lanes_w[lane] = l0_packet_w[lane*16 +: 16];
        end
    endgenerate
    assign pixel_w = l0_active_r && l0_good_w ?
        lanes_w[phase_r] : 16'd0;
    assign background_w = {pixel_w[15:11], pixel_w[15:13], pixel_w[10:5],
        pixel_w[10:9], pixel_w[4:0], pixel_w[4:2]};
    assign rgb_o = rgb_pipe_r[7];
    assign read_cnt_o = read_cnt_r;
    assign perf0_o = perf0_r;
    assign perf1_o = perf1_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            scan_frame_r <= 1'b0;
            params_r <= RESET_PARAMS;
            frame_params_r <= RESET_PARAMS;
            frame_last_pipe_r <= 9'd0;
            raster_active_r <= 1'b0;
            l0_decode_r <= 1'b0;
            group_decode_r <= 1'b0;
            l0_active_r <= 1'b0;
            group_start_r <= 1'b0;
            group_good_r <= 1'b0;
            underflow_seen_r <= 1'b0;
            debt_r <= 32'd0;
            read_cnt_r <= 10'd0;
            perf0_r <= 32'd0;
            perf1_r <= 32'd0;
        end else begin
            frame_last_pipe_r <= {frame_last_pipe_r[7:0],
                raster_active_r && raster_x_r == 11'd1279 && raster_y_r == 10'd719};
            raster_active_r <= scan_frame_r && de_i;
            l0_decode_r <= l0_active_w;
            group_decode_r <= group_start_w;
            l0_active_r <= l0_decode_r;
            group_start_r <= group_decode_r;

            if (params_valid_i) begin
                params_r <= params_i;
            end
            if (frame_begin_w) begin
                frame_params_r <= params_r;
            end
            if (vblank_i) begin
                scan_frame_r <= enable_i;
                underflow_seen_r <= 1'b0;
            end else begin
                if (underflow_o) begin
                    underflow_seen_r <= 1'b1;
                end
            end
            if (group_start_r) begin
                group_good_r <= group_good_w;
            end
            if (fifo_valid_i && fifo_ready_o) begin
                read_cnt_r <= read_cnt_r + 10'd1;
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
        end
    end

    assign rgb_next_w[0] = background_w;
    generate
        for (pixel_stage = 1; pixel_stage < 8; pixel_stage = pixel_stage + 1) begin : g_rgb_next
            assign rgb_next_w[pixel_stage] = rgb_pipe_r[pixel_stage-1];
        end
    endgenerate
    // S3 captures RGB565 expansion; S4-S10 retain the raster alignment contract.
    always @(posedge clk_i) begin
        raster_x_r <= x_i;
        raster_y_r <= y_i;
        phase_decode_r <= phase_w;
        phase_r <= phase_decode_r;
        for (stage_idx = 0; stage_idx < 8; stage_idx = stage_idx + 1) begin
            rgb_pipe_r[stage_idx] <= rgb_next_w[stage_idx];
        end
        if (group_start_r && group_good_w) pixels_r <= fifo_data_i;
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
