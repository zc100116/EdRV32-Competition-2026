// File: edrv32_fpga_rgmii.v
// Spec: eth-spec 3; edrv32-soc-spec 3.4, 5.2 X7.
// Description: Vendor SAME_PIPELINED RX and SAME_EDGE TX with fixed IO delays.
//              Both MAC clocks use the vendor RX PLL output; ETH owns the async FIFOs.
// Clock domains: eth RX/TX (125 MHz).
module edrv32_fpga_rgmii (
    // PHY source clock and DDR receive pins.
    input wire rgmii_rxc_i,
    input wire [3:0] rgmii_rxd_i,
    input wire rgmii_rx_ctl_i,
    output wire clk_eth_o,

    // SoC single-edge MAC interface.
    output wire [7:0] eth_rxd_o,
    output wire eth_rx_dv_o,
    output wire eth_rx_er_o,
    input wire [7:0] eth_txd_i,
    input wire eth_tx_en_i,
    input wire eth_tx_er_i,

    // PHY DDR transmit pins.
    output wire rgmii_txc_o,
    output wire [3:0] rgmii_txd_o,
    output wire rgmii_tx_ctl_o
);
    wire clk_eth_pll_w;
    wire [4:0] rx_pin_w;
    wire [4:0] rx_buf_w;
    wire [4:0] rx_delay_w;
    wire [4:0] rx_rise_w;
    wire [4:0] rx_fall_w;
    wire [5:0] tx_rise_w;
    wire [5:0] tx_fall_w;
    wire [5:0] tx_ddr_w;
    wire tx_clk_delay_w;
    wire [4:0] tx_pin_w;

    assign {rgmii_tx_ctl_o, rgmii_txd_o} = tx_pin_w;

    // ref_clock.idf requests 30 degrees despite the vendor wire name "90p".
    /* verilator lint_off PINCONNECTEMPTY */
    ip_pll_eth u_pll_eth (
        .clkin1(rgmii_rxc_i),
        .clkout0(clk_eth_pll_w),
        .lock()
    );
    /* verilator lint_on PINCONNECTEMPTY */
    GTP_CLKBUFG u_eth_clk (
        .CLKIN(clk_eth_pll_w),
        .CLKOUT(clk_eth_o)
    );

    assign rx_pin_w = {rgmii_rx_ctl_i, rgmii_rxd_i};
    assign eth_rxd_o = {rx_fall_w[3:0], rx_rise_w[3:0]};
    assign eth_rx_dv_o = rx_rise_w[4];
    assign eth_rx_er_o = rx_rise_w[4] ^ rx_fall_w[4];
    assign tx_rise_w = {1'b1, eth_tx_en_i, eth_txd_i[3:0]};
    assign tx_fall_w = {1'b0, eth_tx_en_i ^ eth_tx_er_i, eth_txd_i[7:4]};

    genvar pin_idx;
    generate
        for (pin_idx = 0; pin_idx < 5; pin_idx = pin_idx + 1) begin : g_rx
            GTP_INBUF #(
                .IOSTANDARD("LVCMOS33")
            ) u_input (
                .I(rx_pin_w[pin_idx]),
                .O(rx_buf_w[pin_idx])
            );
            // Vendor 247 x 10 ps; DELAY_STEP is Gray-coded (247 ^ (247 >> 1)).
            GTP_IODELAY_E2 #(
                .DELAY_STEP_SEL("PORT"),
                .DELAY_STEP_VALUE(8'd0),
                .TDELAY_EN("FALSE")
            ) u_delay (
                .DI(rx_buf_w[pin_idx]),
                .DELAY_SEL(1'b1),
                .DELAY_STEP(8'h8c),
                .EN_N(1'b0),
                .DO(rx_delay_w[pin_idx])
            );
            GTP_IDDR_E1 #(
                .GRS_EN("TRUE"),
                .IDDR_MODE("SAME_PIPELINED"),
                .RS_TYPE("ASYNC_RESET")
            ) u_ddr (
                .D(rx_delay_w[pin_idx]),
                .CLK(clk_eth_o),
                .CE(1'b1),
                .RS(1'b0),
                .Q0(rx_rise_w[pin_idx]),
                .Q1(rx_fall_w[pin_idx])
            );
        end
        for (pin_idx = 0; pin_idx < 6; pin_idx = pin_idx + 1) begin : g_tx
            GTP_ODDR_E1 #(
                .GRS_EN("TRUE"),
                .ODDR_MODE("SAME_EDGE"),
                .RS_TYPE("ASYNC_RESET")
            ) u_ddr (
                .CLK(clk_eth_o),
                .CE(1'b1),
                .RS(1'b0),
                .D0(tx_rise_w[pin_idx]),
                .D1(tx_fall_w[pin_idx]),
                .Q(tx_ddr_w[pin_idx])
            );
        end
        for (pin_idx = 0; pin_idx < 5; pin_idx = pin_idx + 1) begin : g_tx_buf
            GTP_OUTBUF #(
                .IOSTANDARD("LVCMOS33"),
                .SLEW_RATE("FAST"),
                .DRIVE_STRENGTH("4")
            ) u_output (
                .I(tx_ddr_w[pin_idx]),
                .O(tx_pin_w[pin_idx])
            );
        end
    endgenerate

    // Vendor 100 x 10 ps; 100 ^ (100 >> 1) = 0x56.
    GTP_IODELAY_E2 #(
        .DELAY_STEP_SEL("PORT"),
        .DELAY_STEP_VALUE(8'd0),
        .TDELAY_EN("FALSE")
    ) u_tx_clk_delay (
        .DI(tx_ddr_w[5]),
        .DELAY_SEL(1'b1),
        .DELAY_STEP(8'h56),
        .EN_N(1'b0),
        .DO(tx_clk_delay_w)
    );
    GTP_OUTBUF #(
        .IOSTANDARD("LVCMOS33"),
        .SLEW_RATE("FAST"),
        .DRIVE_STRENGTH("4")
    ) u_tx_clk_output (
        .I(tx_clk_delay_w),
        .O(rgmii_txc_o)
    );
endmodule
