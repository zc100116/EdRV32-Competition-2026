// ============================================================================
// File        : edrv32_hdmi_scanout.v
// Description : RGB565 FIFO unpacker and fixed-mode HDMI pixel source.
// ============================================================================

module edrv32_hdmi_scanout #(
    parameter integer H_ACTIVE = 1280,
    parameter integer H_FP = 110,
    parameter integer H_SYNC = 40,
    parameter integer H_BP = 220,
    parameter integer V_ACTIVE = 720,
    parameter integer V_FP = 5,
    parameter integer V_SYNC = 5,
    parameter integer V_BP = 20,
    parameter integer H_POL = 1,
    parameter integer V_POL = 1
) (
    input  wire         clk_i,
    input  wire         rst_n_i,
    input  wire         enable_i,
    input  wire         output_enable_i,

    input  wire [255:0] fifo_data_i,
    input  wire         fifo_valid_i,
    output wire         fifo_ready_o,

    output wire [23:0]  rgb_o,
    output wire         hs_o,
    output wire         vs_o,
    output wire         de_o,
    output wire [15:0]  active_x_o,
    output wire [15:0]  active_y_o,
    output wire [31:0]  frame_count_o,
    output wire [31:0]  underflow_count_o
);

    wire timing_hs_w;
    wire timing_vs_w;
    wire timing_de_w;
    wire [15:0] timing_x_w;
    wire [15:0] timing_y_w;
    wire frame_start_w;

    edrv32_hdmi_timing #(
        .H_ACTIVE (H_ACTIVE),
        .H_FP     (H_FP),
        .H_SYNC   (H_SYNC),
        .H_BP     (H_BP),
        .V_ACTIVE (V_ACTIVE),
        .V_FP     (V_FP),
        .V_SYNC   (V_SYNC),
        .V_BP     (V_BP),
        .H_POL    (H_POL),
        .V_POL    (V_POL)
    ) u_timing (
        .clk_i         (clk_i),
        .rst_n_i       (rst_n_i),
        .enable_i      (enable_i),
        .hs_o          (timing_hs_w),
        .vs_o          (timing_vs_w),
        .de_o          (timing_de_w),
        .x_o           (timing_x_w),
        .y_o           (timing_y_w),
        .frame_start_o (frame_start_w)
    );

    function [23:0] rgb565_to_rgb888;
        input [15:0] pixel;
        begin
            rgb565_to_rgb888 = {
                pixel[15:11], pixel[15:13],
                pixel[10:5],  pixel[10:9],
                pixel[4:0],   pixel[4:2]
            };
        end
    endfunction

    reg [3:0] pixel_index_r;
    reg [23:0] rgb_r;
    reg hs_r;
    reg vs_r;
    reg de_r;
    reg [15:0] active_x_r;
    reg [15:0] active_y_r;
    reg [31:0] frame_count_r;
    reg [31:0] underflow_count_r;
    reg output_enable_r;

    wire [15:0] selected_pixel_w =
        fifo_data_i[pixel_index_r*16 +: 16];
    wire consume_word_w = timing_de_w && fifo_valid_i &&
        (pixel_index_r == 4'd15);

    assign fifo_ready_o = enable_i && consume_word_w;
    assign rgb_o = output_enable_r ? rgb_r : 24'b0;
    assign hs_o = hs_r;
    assign vs_o = vs_r;
    assign de_o = de_r && output_enable_r;
    assign active_x_o = active_x_r;
    assign active_y_o = active_y_r;
    assign frame_count_o = frame_count_r;
    assign underflow_count_o = underflow_count_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            pixel_index_r <= 4'b0;
            rgb_r <= 24'b0;
            hs_r <= 1'b0;
            vs_r <= 1'b0;
            de_r <= 1'b0;
            active_x_r <= 16'b0;
            active_y_r <= 16'b0;
            frame_count_r <= 32'b0;
            underflow_count_r <= 32'b0;
            output_enable_r <= 1'b0;
        end else if (!enable_i) begin
            pixel_index_r <= 4'b0;
            rgb_r <= 24'b0;
            hs_r <= timing_hs_w;
            vs_r <= timing_vs_w;
            de_r <= 1'b0;
            active_x_r <= 16'b0;
            active_y_r <= 16'b0;
            output_enable_r <= 1'b0;
        end else begin
            hs_r <= timing_hs_w;
            vs_r <= timing_vs_w;
            de_r <= timing_de_w;
            active_x_r <= timing_x_w;
            active_y_r <= timing_y_w;

            if (frame_start_w) begin
                frame_count_r <= frame_count_r + 1'b1;
                output_enable_r <= output_enable_i;
            end

            if (!timing_de_w) begin
                rgb_r <= 24'b0;
            end else if (fifo_valid_i) begin
                rgb_r <= rgb565_to_rgb888(selected_pixel_w);
                if (pixel_index_r == 4'd15)
                    pixel_index_r <= 4'b0;
                else
                    pixel_index_r <= pixel_index_r + 1'b1;
            end else begin
                rgb_r <= 24'b0;
                underflow_count_r <= underflow_count_r + 1'b1;
            end
        end
    end

    generate
        if ((H_ACTIVE % 16) != 0) begin : gen_bad_line_width
            edrv32_hdmi_scanout_width_must_be_multiple_of_16
                u_static_assert ();
        end
    endgenerate

endmodule
