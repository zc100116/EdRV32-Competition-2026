// ============================================================================
// File        : edrv32_ov5640_capture.v
// Description : OV5640 8-bit DVP RGB565 receiver and 256-bit beat packer.
// Notes       : The sensor cannot be backpressured. A full output slot marks
//               the current frame bad; the following frame starts cleanly.
// ============================================================================

module edrv32_ov5640_capture #(
    parameter integer H_ACTIVE = 1280,
    parameter integer V_ACTIVE = 720,
    parameter integer DISCARD_FRAMES = 2
) (
    input  wire         clk_i,
    input  wire         rst_n_i,
    input  wire         enable_i,
    input  wire         init_done_i,
    input  wire [7:0]   data_i,
    input  wire         href_i,
    input  wire         vsync_i,

    output wire [257:0] stream_data_o,
    output wire         stream_valid_o,
    input  wire         stream_ready_i,
    output wire         frame_active_o,
    output wire [31:0]  frame_count_o,
    output wire         overflow_o
);

    localparam integer FRAME_PIXELS = H_ACTIVE * V_ACTIVE;

    reg init_meta_r;
    reg init_sync_r;
    reg enable_meta_r;
    reg enable_sync_r;
    reg vsync_d_r;
    reg frame_active_r;
    reg byte_phase_r;
    reg [7:0] byte_hi_r;
    reg [3:0] lane_r;
    reg [31:0] pixel_count_r;
    reg [255:0] pack_r;
    reg [257:0] stream_data_r;
    reg stream_valid_r;
    reg [7:0] discard_count_r;
    reg [31:0] frame_count_r;
    reg overflow_r;
    reg drop_frame_r;

    wire frame_start_w = vsync_d_r && !vsync_i;
    wire stream_fire_w = stream_valid_r && stream_ready_i;
    wire pixel_fire_w = frame_active_r && href_i && byte_phase_r;
    wire [15:0] pixel_w = {byte_hi_r, data_i};

    reg [255:0] completed_word_w;
    always @(*) begin
        completed_word_w = pack_r;
        completed_word_w[lane_r*16 +: 16] = pixel_w;
    end

    assign stream_data_o = stream_data_r;
    assign stream_valid_o = stream_valid_r;
    assign frame_active_o = frame_active_r;
    assign frame_count_o = frame_count_r;
    assign overflow_o = overflow_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            init_meta_r <= 1'b0;
            init_sync_r <= 1'b0;
            enable_meta_r <= 1'b0;
            enable_sync_r <= 1'b0;
            vsync_d_r <= 1'b1;
        end else begin
            init_meta_r <= init_done_i;
            init_sync_r <= init_meta_r;
            enable_meta_r <= enable_i;
            enable_sync_r <= enable_meta_r;
            vsync_d_r <= vsync_i;
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            frame_active_r <= 1'b0;
            byte_phase_r <= 1'b0;
            byte_hi_r <= 8'b0;
            lane_r <= 4'b0;
            pixel_count_r <= 32'b0;
            pack_r <= 256'b0;
            stream_data_r <= 258'b0;
            stream_valid_r <= 1'b0;
            discard_count_r <= 8'b0;
            frame_count_r <= 32'b0;
            overflow_r <= 1'b0;
            drop_frame_r <= 1'b0;
        end else begin
            if (stream_fire_w)
                stream_valid_r <= 1'b0;

            if (frame_start_w) begin
                byte_phase_r <= 1'b0;
                lane_r <= 4'b0;
                pixel_count_r <= 32'b0;
                pack_r <= 256'b0;
                drop_frame_r <= 1'b0;

                if (enable_sync_r && init_sync_r) begin
                    if (discard_count_r < DISCARD_FRAMES) begin
                        discard_count_r <= discard_count_r + 1'b1;
                        frame_active_r <= 1'b0;
                    end else begin
                        frame_active_r <= 1'b1;
                    end
                end else begin
                    frame_active_r <= 1'b0;
                    discard_count_r <= 8'b0;
                end
            end else if (frame_active_r && href_i) begin
                if (!byte_phase_r) begin
                    byte_hi_r <= data_i;
                    byte_phase_r <= 1'b1;
                end else begin
                    byte_phase_r <= 1'b0;
                    pack_r[lane_r*16 +: 16] <= pixel_w;

                    if (lane_r == 4'd15) begin
                        lane_r <= 4'b0;
                        if (!drop_frame_r) begin
                            if (!stream_valid_r || stream_ready_i) begin
                                stream_data_r <= {
                                    pixel_count_r == 32'd15,
                                    pixel_count_r == FRAME_PIXELS - 1,
                                    completed_word_w
                                };
                                stream_valid_r <= 1'b1;
                            end else begin
                                overflow_r <= 1'b1;
                                drop_frame_r <= 1'b1;
                            end
                        end
                    end else begin
                        lane_r <= lane_r + 1'b1;
                    end

                    if (pixel_count_r == FRAME_PIXELS - 1) begin
                        pixel_count_r <= 32'b0;
                        frame_active_r <= 1'b0;
                        if (!drop_frame_r &&
                            (!stream_valid_r || stream_ready_i))
                            frame_count_r <= frame_count_r + 1'b1;
                    end else begin
                        pixel_count_r <= pixel_count_r + 1'b1;
                    end
                end
            end else if (!href_i) begin
                byte_phase_r <= 1'b0;
            end
        end
    end

    generate
        if ((H_ACTIVE % 16) != 0 || H_ACTIVE < 16 || V_ACTIVE < 1) begin : gen_bad_geometry
            edrv32_ov5640_capture_width_must_be_multiple_of_16
                u_static_assert ();
        end
    endgenerate

endmodule
