// File: edrv32_fpga_tmds.v
// Spec: disp-spec 2.2; board-plan B2-2.
// Description: Vendor DDR10TO1 cascade sends symbol bit 0 first, including the clock channel.
// Clock domains: related clk_pix and 5x clk_serial.
module edrv32_fpga_tmds (
    // Related PLL clocks and parallel DISP symbols.
    input wire clk_pix_i,
    input wire clk_serial_i,
    input wire [29:0] tmds_sym_i,

    // FPGA-direct TMDS pairs, B/G/R order.
    output wire [2:0] tmds_data_p_o,
    output wire [2:0] tmds_data_n_o,
    output wire tmds_clk_p_o,
    output wire tmds_clk_n_o
);
    wire [39:0] symbols_w;
    wire [3:0] serial_w;
    wire [3:0] cascade0_w;
    wire [3:0] cascade1_w;
    wire [3:0] pair_p_w;
    wire [3:0] pair_n_w;

    assign symbols_w = {10'b1111100000, tmds_sym_i};
    assign {tmds_clk_p_o, tmds_data_p_o} = pair_p_w;
    assign {tmds_clk_n_o, tmds_data_n_o} = pair_n_w;

    // Serializer data registers need no local reset (CLAUDE 5.2).
    /* verilator lint_off PINCONNECTEMPTY */
    genvar channel;
    generate
        for (channel = 0; channel < 4; channel = channel + 1) begin : g_channel
            GTP_OSERDES_E2 #(
                .GRS_EN("TRUE"),
                .OSERDES_MODE("DDR10TO1"),
                .TSERDES_EN("FALSE"),
                .UPD0_SHIFT_EN("FALSE"),
                .UPD1_SHIFT_EN("FALSE"),
                .INIT_SET(2'b00),
                .GRS_TYPE_DQ("RESET"),
                .LRS_TYPE_DQ0("ASYNC_RESET"),
                .LRS_TYPE_DQ1("ASYNC_RESET"),
                .LRS_TYPE_DQ2("ASYNC_RESET"),
                .LRS_TYPE_DQ3("ASYNC_RESET"),
                .GRS_TYPE_TQ("RESET"),
                .LRS_TYPE_TQ0("ASYNC_RESET"),
                .LRS_TYPE_TQ1("ASYNC_RESET"),
                .LRS_TYPE_TQ2("ASYNC_RESET"),
                .LRS_TYPE_TQ3("ASYNC_RESET"),
                .TRI_EN("FALSE"),
                .TBYTE_EN("FALSE"),
                .MIPI_EN("FALSE"),
                .OCASCADE_EN("FALSE")
            ) u_master (
                .RST(1'b0),
                .OCE(1'b1),
                .TCE(1'b0),
                .OCLKDIV(clk_pix_i),
                .SERCLK(clk_serial_i),
                .OCLK(clk_serial_i),
                .MIPI_CTRL(1'b0),
                .UPD0_SHIFT(1'b0),
                .UPD1_SHIFT(1'b0),
                .OSHIFTIN0(cascade0_w[channel]),
                .OSHIFTIN1(cascade1_w[channel]),
                .DI(symbols_w[channel*10 +: 8]),
                .TI(1'b0),
                .TBYTE_IN(1'b0),
                .OSHIFTOUT0(),
                .OSHIFTOUT1(),
                .DO(serial_w[channel]),
                .TQ()
            );

            GTP_OSERDES_E2 #(
                .GRS_EN("TRUE"),
                .OSERDES_MODE("DDR10TO1"),
                .TSERDES_EN("FALSE"),
                .UPD0_SHIFT_EN("FALSE"),
                .UPD1_SHIFT_EN("FALSE"),
                .INIT_SET(2'b00),
                .GRS_TYPE_DQ("RESET"),
                .LRS_TYPE_DQ0("ASYNC_RESET"),
                .LRS_TYPE_DQ1("ASYNC_RESET"),
                .LRS_TYPE_DQ2("ASYNC_RESET"),
                .LRS_TYPE_DQ3("ASYNC_RESET"),
                .GRS_TYPE_TQ("RESET"),
                .LRS_TYPE_TQ0("ASYNC_RESET"),
                .LRS_TYPE_TQ1("ASYNC_RESET"),
                .LRS_TYPE_TQ2("ASYNC_RESET"),
                .LRS_TYPE_TQ3("ASYNC_RESET"),
                .TRI_EN("FALSE"),
                .TBYTE_EN("FALSE"),
                .MIPI_EN("FALSE"),
                .OCASCADE_EN("TRUE")
            ) u_slave (
                .RST(1'b0),
                .OCE(1'b1),
                .TCE(1'b0),
                .OCLKDIV(clk_pix_i),
                .SERCLK(clk_serial_i),
                .OCLK(clk_serial_i),
                .MIPI_CTRL(1'b0),
                .UPD0_SHIFT(1'b0),
                .UPD1_SHIFT(1'b0),
                // Cascade inputs have no fabric route; leave them open as the vendor
                // outputserdes.v and legacy serializer do (B3V Route-2014 on GND).
                .OSHIFTIN0(),
                .OSHIFTIN1(),
                .DI({4'b0, symbols_w[channel*10+8 +: 2], 2'b0}),
                .TI(1'b0),
                .TBYTE_IN(1'b0),
                .OSHIFTOUT0(cascade0_w[channel]),
                .OSHIFTOUT1(cascade1_w[channel]),
                .DO(),
                .TQ()
            );

            GTP_OUTBUFDS #(
                .IOSTANDARD("TMDS")
            ) u_pair (
                .I(serial_w[channel]),
                .O(pair_p_w[channel]),
                .OB(pair_n_w[channel])
            );
        end
    endgenerate
    /* verilator lint_on PINCONNECTEMPTY */
endmodule
