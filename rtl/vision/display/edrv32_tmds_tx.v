// ============================================================================
// File        : edrv32_tmds_tx.v
// Description : Three-channel RGB TMDS encoder and Pango serializers.
// ============================================================================

module edrv32_tmds_tx (
    input  wire        pixel_clk_i,
    input  wire        serial_clk_i,
    input  wire        pixel_rst_n_i,
    input  wire        serial_rst_n_i,

    input  wire [23:0] rgb_i,
    input  wire        hs_i,
    input  wire        vs_i,
    input  wire        de_i,

    output wire        tmds_clk_p_o,
    output wire        tmds_clk_n_o,
    output wire [2:0]  tmds_data_p_o,
    output wire [2:0]  tmds_data_n_o
);

    wire [9:0] blue_symbol_w;
    wire [9:0] green_symbol_w;
    wire [9:0] red_symbol_w;

    edrv32_tmds_encoder u_blue_encoder (
        .clk_i      (pixel_clk_i),
        .rst_n_i    (pixel_rst_n_i),
        .data_i     (rgb_i[7:0]),
        .control0_i (hs_i),
        .control1_i (vs_i),
        .de_i       (de_i),
        .symbol_o   (blue_symbol_w)
    );

    edrv32_tmds_encoder u_green_encoder (
        .clk_i      (pixel_clk_i),
        .rst_n_i    (pixel_rst_n_i),
        .data_i     (rgb_i[15:8]),
        .control0_i (1'b0),
        .control1_i (1'b0),
        .de_i       (de_i),
        .symbol_o   (green_symbol_w)
    );

    edrv32_tmds_encoder u_red_encoder (
        .clk_i      (pixel_clk_i),
        .rst_n_i    (pixel_rst_n_i),
        .data_i     (rgb_i[23:16]),
        .control0_i (1'b0),
        .control1_i (1'b0),
        .de_i       (de_i),
        .symbol_o   (red_symbol_w)
    );

    edrv32_tmds_serdes u_clock_serializer (
        .pixel_clk_i  (pixel_clk_i),
        .serial_clk_i (serial_clk_i),
        .serial_rst_n_i(serial_rst_n_i),
        .symbol_i     (10'b1111100000),
        .data_p_o     (tmds_clk_p_o),
        .data_n_o     (tmds_clk_n_o)
    );

    edrv32_tmds_serdes u_blue_serializer (
        .pixel_clk_i  (pixel_clk_i),
        .serial_clk_i (serial_clk_i),
        .serial_rst_n_i(serial_rst_n_i),
        .symbol_i     (blue_symbol_w),
        .data_p_o     (tmds_data_p_o[0]),
        .data_n_o     (tmds_data_n_o[0])
    );

    edrv32_tmds_serdes u_green_serializer (
        .pixel_clk_i  (pixel_clk_i),
        .serial_clk_i (serial_clk_i),
        .serial_rst_n_i(serial_rst_n_i),
        .symbol_i     (green_symbol_w),
        .data_p_o     (tmds_data_p_o[1]),
        .data_n_o     (tmds_data_n_o[1])
    );

    edrv32_tmds_serdes u_red_serializer (
        .pixel_clk_i  (pixel_clk_i),
        .serial_clk_i (serial_clk_i),
        .serial_rst_n_i(serial_rst_n_i),
        .symbol_i     (red_symbol_w),
        .data_p_o     (tmds_data_p_o[2]),
        .data_n_o     (tmds_data_n_o[2])
    );

endmodule
