// ============================================================================
// File        : edrv32_pixel_pipeline.v
// Description : Packed RGB565 stream point-processing pipeline.
// Notes       : The external stream format matches Camera FIFO and Display
//               Writer: {sof,eof,16 RGB565 pixels}.
// ============================================================================

module edrv32_pixel_pipeline #(
    parameter integer H_ACTIVE = 1280
) (
    input  wire                clk_i,
    input  wire                rst_n_i,

    input  wire [257:0]        stream_data_i,
    input  wire                stream_valid_i,
    output wire                stream_ready_o,

    output wire [257:0]        stream_data_o,
    output wire                stream_valid_o,
    input  wire                stream_ready_i,

    input  wire                cfg_commit_i,
    input  wire                cfg_enable_i,
    input  wire                cfg_grayscale_i,
    input  wire                cfg_threshold_enable_i,
    input  wire                cfg_invert_i,
    input  wire signed [8:0]   cfg_brightness_i,
    input  wire [8:0]          cfg_contrast_i,
    input  wire [7:0]          cfg_threshold_i,
    input  wire                cfg_spatial_enable_i,
    input  wire [2:0]          cfg_spatial_mode_i,
    input  wire [7:0]          cfg_spatial_threshold_i,
    output wire                cfg_pending_o,
    output wire [31:0]         frame_count_o,
    output wire [31:0]         unpack_frame_count_o,
    output wire [31:0]         point_frame_count_o,
    output wire [31:0]         spatial_frame_count_o
);

    wire [15:0] unpack_pixel0_w;
    wire [15:0] unpack_pixel1_w;
    wire unpack_sof_w;
    wire unpack_eof_w;
    wire unpack_sol_w;
    wire unpack_eol_w;
    wire unpack_valid_w;
    wire unpack_ready_w;

    edrv32_pixel_unpack_2p #(
        .H_ACTIVE(H_ACTIVE)
    ) u_unpack (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .stream_data_i(stream_data_i),
        .stream_valid_i(stream_valid_i),
        .stream_ready_o(stream_ready_o),
        .pixel0_o(unpack_pixel0_w),
        .pixel1_o(unpack_pixel1_w),
        .sof_o(unpack_sof_w),
        .eof_o(unpack_eof_w),
        .sol_o(unpack_sol_w),
        .eol_o(unpack_eol_w),
        .pair_valid_o(unpack_valid_w),
        .pair_ready_i(unpack_ready_w)
    );

    wire [15:0] point_pixel0_w;
    wire [15:0] point_pixel1_w;
    wire point_sof_w;
    wire point_eof_w;
    wire point_sol_w;
    wire point_eol_w;
    wire point_valid_w;
    wire point_ready_w;
    wire point_cfg_pending_w;
    wire spatial_cfg_pending_w;

    edrv32_pixel_point_pipe u_point_pipe (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .pixel0_i(unpack_pixel0_w),
        .pixel1_i(unpack_pixel1_w),
        .sof_i(unpack_sof_w),
        .eof_i(unpack_eof_w),
        .sol_i(unpack_sol_w),
        .eol_i(unpack_eol_w),
        .pair_valid_i(unpack_valid_w),
        .pair_ready_o(unpack_ready_w),
        .pixel0_o(point_pixel0_w),
        .pixel1_o(point_pixel1_w),
        .sof_o(point_sof_w),
        .eof_o(point_eof_w),
        .sol_o(point_sol_w),
        .eol_o(point_eol_w),
        .pair_valid_o(point_valid_w),
        .pair_ready_i(point_ready_w),
        .cfg_commit_i(cfg_commit_i),
        .cfg_enable_i(cfg_enable_i),
        .cfg_grayscale_i(cfg_grayscale_i),
        .cfg_threshold_enable_i(cfg_threshold_enable_i),
        .cfg_invert_i(cfg_invert_i),
        .cfg_brightness_i(cfg_brightness_i),
        .cfg_contrast_i(cfg_contrast_i),
        .cfg_threshold_i(cfg_threshold_i),
        .cfg_pending_o(point_cfg_pending_w)
    );

    wire [15:0] spatial_pixel0_w;
    wire [15:0] spatial_pixel1_w;
    wire spatial_sof_w;
    wire spatial_eof_w;
    wire unused_spatial_sol_w;
    wire unused_spatial_eol_w;
    wire spatial_valid_w;
    wire spatial_ready_w;

    edrv32_pixel_window_3x3_2p #(
        .H_ACTIVE(H_ACTIVE),
        .LINE_ADDR_W(10)
    ) u_spatial (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .pixel0_i(point_pixel0_w), .pixel1_i(point_pixel1_w),
        .sof_i(point_sof_w), .eof_i(point_eof_w),
        .sol_i(point_sol_w), .eol_i(point_eol_w),
        .pair_valid_i(point_valid_w), .pair_ready_o(point_ready_w),
        .pixel0_o(spatial_pixel0_w), .pixel1_o(spatial_pixel1_w),
        .sof_o(spatial_sof_w), .eof_o(spatial_eof_w),
        .sol_o(unused_spatial_sol_w), .eol_o(unused_spatial_eol_w),
        .pair_valid_o(spatial_valid_w), .pair_ready_i(spatial_ready_w),
        .cfg_commit_i(cfg_commit_i),
        .cfg_enable_i(cfg_spatial_enable_i),
        .cfg_mode_i(cfg_spatial_mode_i),
        .cfg_threshold_i(cfg_spatial_threshold_i),
        .cfg_pending_o(spatial_cfg_pending_w)
    );

    edrv32_pixel_pack_2p u_pack (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .pixel0_i(spatial_pixel0_w),
        .pixel1_i(spatial_pixel1_w),
        .sof_i(spatial_sof_w),
        .eof_i(spatial_eof_w),
        .pair_valid_i(spatial_valid_w),
        .pair_ready_o(spatial_ready_w),
        .stream_data_o(stream_data_o),
        .stream_valid_o(stream_valid_o),
        .stream_ready_i(stream_ready_i)
    );

    reg [31:0] frame_count_r;
    reg [31:0] unpack_frame_count_r;
    reg [31:0] point_frame_count_r;
    reg [31:0] spatial_frame_count_r;
    wire output_fire_w = stream_valid_o && stream_ready_i;

    assign frame_count_o = frame_count_r;
    assign unpack_frame_count_o = unpack_frame_count_r;
    assign point_frame_count_o = point_frame_count_r;
    assign spatial_frame_count_o = spatial_frame_count_r;
    assign cfg_pending_o = point_cfg_pending_w | spatial_cfg_pending_w;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            frame_count_r <= 32'b0;
            unpack_frame_count_r <= 32'b0;
            point_frame_count_r <= 32'b0;
            spatial_frame_count_r <= 32'b0;
        end else begin
            if (output_fire_w && stream_data_o[256])
                frame_count_r <= frame_count_r + 1'b1;
            if (unpack_valid_w && unpack_ready_w && unpack_eof_w)
                unpack_frame_count_r <= unpack_frame_count_r + 1'b1;
            if (point_valid_w && point_ready_w && point_eof_w)
                point_frame_count_r <= point_frame_count_r + 1'b1;
            if (spatial_valid_w && spatial_ready_w && spatial_eof_w)
                spatial_frame_count_r <= spatial_frame_count_r + 1'b1;
        end
    end

endmodule
