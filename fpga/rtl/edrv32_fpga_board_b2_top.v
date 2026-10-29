// File: edrv32_fpga_board_b2_top.v
// Spec: board-plan B2-2; edrv32-soc-spec 3, 5.2, 5.3.
// Description: Full SoC board wiring; DDR core_clk owns clk_mem and init_done owns mem_ready.
// Clock domains: sys, mem, pix, npu, cam0/1, eth RX/TX.
module edrv32_fpga_board_b2_top (
    // Board oscillator, reset key and DDR reference clock.
    input wire clk_i,
    input wire rst_n_i,
    input wire ddr_ref_clk_p_i,
    input wire ddr_ref_clk_n_i,

    // UART and GPIO keys/LEDs.
    input wire uart_rx_i,
    output wire uart_tx_o,
    input wire [3:0] key_n_i,
    output wire [4:0] led_o,

    // Two independent DVP sources and GPIO13/15 camera resets.
    input wire cam0_pclk_i,
    input wire cam1_pclk_i,
    input wire cam0_vsync_i,
    input wire cam0_href_i,
    input wire [7:0] cam0_data_i,
    input wire cam1_vsync_i,
    input wire cam1_href_i,
    input wire [7:0] cam1_data_i,
    output wire cam0_rst_n_o,
    output wire cam1_rst_n_o,

    // Camera open-drain control buses.
    inout wire [1:0] i2c0_scl_o,
    inout wire [1:0] i2c0_sda_o,

    // FPGA-direct HDMI TMDS outputs.
    output wire [2:0] tmds_data_p_o,
    output wire [2:0] tmds_data_n_o,
    output wire tmds_clk_p_o,
    output wire tmds_clk_n_o,

    // Gigabit PHY data and management.
    input wire rgmii_rxc_i,
    input wire [3:0] rgmii_rxd_i,
    input wire rgmii_rx_ctl_i,
    output wire rgmii_txc_o,
    output wire [3:0] rgmii_txd_o,
    output wire rgmii_tx_ctl_o,
    output wire eth_mdc_o,
    inout wire eth_mdio_o,
    output wire eth_phy_rst_n_o,

    // DDR3 physical bus; inout ports use the repository-required _o suffix.
    output wire mem_cs_n_o,
    output wire mem_rst_n_o,
    output wire mem_ck_o,
    output wire mem_ck_n_o,
    output wire mem_cke_o,
    output wire mem_ras_n_o,
    output wire mem_cas_n_o,
    output wire mem_we_n_o,
    output wire mem_odt_o,
    output wire [14:0] mem_a_o,
    output wire [2:0] mem_ba_o,
    inout wire [3:0] mem_dqs_o,
    inout wire [3:0] mem_dqs_n_o,
    inout wire [31:0] mem_dq_o,
    output wire [3:0] mem_dm_o
);

    // Board IP clocks; DDR initialization does not depend on the SoC reset release.
    wire clk_sys_w;
    wire clk_npu_w;
    wire clk_pix_w;
    wire clk_serial_w;
    wire clk_mem_w;
    wire ddr_ref_clk_w;
    wire clk_eth_w;
    wire pll_sys_lock_w;
    wire pll_video_lock_w;
    wire rst_board_n_w;
    wire ddr_init_done_w;
    wire mem_ready_w;

    // One VCO (900 MHz) serves clk_sys 100 MHz and clk_npu 150 MHz (fpga/ip/ip_pll_sys.md).
    ip_pll_sys u_pll_sys (
        .clkin1(clk_i),
        .clkout0(clk_sys_w),
        .clkout1(clk_npu_w),
        .lock(pll_sys_lock_w)
    );
    ip_pll_video u_pll_video (
        .clkin1(clk_i),
        .clkout0(clk_pix_w),
        .clkout1(clk_serial_w),
        .lock(pll_video_lock_w)
    );
    GTP_INBUFDS u_ddr_ref_clk (
        .I(ddr_ref_clk_p_i),
        .IB(ddr_ref_clk_n_i),
        .O(ddr_ref_clk_w)
    );
    assign rst_board_n_w = rst_n_i & pll_sys_lock_w & pll_video_lock_w;

    // AXI256 connection between SoC and the combinational DDR adapter.
    wire [3:0] ddr_awid_w;
    wire [31:0] ddr_awaddr_w;
    wire [3:0] ddr_awlen_w;
    wire ddr_awvalid_w;
    wire ddr_awready_w;
    wire [255:0] ddr_wdata_w;
    wire [31:0] ddr_wstrb_w;
    wire ddr_wlast_w;
    wire ddr_wvalid_w;
    wire ddr_wready_w;
    wire [3:0] ddr_bid_w;
    wire [1:0] ddr_bresp_w;
    wire ddr_bvalid_w;
    wire [3:0] ddr_arid_w;
    wire [31:0] ddr_araddr_w;
    wire [3:0] ddr_arlen_w;
    wire ddr_arvalid_w;
    wire ddr_arready_w;
    wire [3:0] ddr_rid_w;
    wire [255:0] ddr_rdata_w;
    wire [1:0] ddr_rresp_w;
    wire ddr_rlast_w;
    wire ddr_rvalid_w;
    wire unused_cam0_pwdn_w;
    wire unused_cam1_pwdn_w;
    wire [1:0] i2c0_scl_w;
    wire [1:0] i2c0_scl_oe_w;
    wire [1:0] i2c0_sda_w;
    wire [1:0] i2c0_sda_oe_w;
    wire [29:0] tmds_sym_w;
    wire [7:0] eth_rxd_w;
    wire eth_rx_dv_w;
    wire eth_rx_er_w;
    wire [7:0] eth_txd_w;
    wire eth_tx_en_w;
    wire eth_tx_er_w;
    wire eth_mdio_w;
    wire eth_mdio_oe_w;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [15:0] gpio_w;
    /* verilator lint_on UNUSEDSIGNAL */
    wire [15:0] unused_gpio_oe_w;
    wire [63:0] unused_debug_w;

    wire [27:0] axi_awaddr_w;
    wire axi_awuser_ap_w;
    wire [3:0] axi_awuser_id_w;
    wire [3:0] axi_awlen_w;
    wire axi_awvalid_w;
    wire axi_awready_w;
    wire [255:0] axi_wdata_w;
    wire [31:0] axi_wstrb_w;
    wire axi_wready_w;
    wire [3:0] axi_wusero_id_w;
    wire axi_wusero_last_w;
    wire [27:0] axi_araddr_w;
    wire axi_aruser_ap_w;
    wire [3:0] axi_aruser_id_w;
    wire [3:0] axi_arlen_w;
    wire axi_arvalid_w;
    wire axi_arready_w;
    wire [3:0] axi_rid_w;
    wire [255:0] axi_rdata_w;
    wire axi_rlast_w;
    wire axi_rvalid_w;

    edrv32_soc_top u_soc (
        .clk_sys_i(clk_sys_w),
        .clk_mem_i(clk_mem_w),
        .clk_pix_i(clk_pix_w),
        .clk_npu_i(clk_npu_w),
        .cam0_pclk_i(cam0_pclk_i),
        .cam1_pclk_i(cam1_pclk_i),
        .eth_rx_clk_i(clk_eth_w),
        .eth_tx_clk_i(clk_eth_w),
        .rst_n_i(rst_board_n_w),
        .mem_ready_i(mem_ready_w),

        // DDR master, clk_mem domain.
        .ddr_awid_o(ddr_awid_w),
        .ddr_awaddr_o(ddr_awaddr_w),
        .ddr_awlen_o(ddr_awlen_w),
        .ddr_awvalid_o(ddr_awvalid_w),
        .ddr_awready_i(ddr_awready_w),
        .ddr_wdata_o(ddr_wdata_w),
        .ddr_wstrb_o(ddr_wstrb_w),
        .ddr_wlast_o(ddr_wlast_w),
        .ddr_wvalid_o(ddr_wvalid_w),
        .ddr_wready_i(ddr_wready_w),
        .ddr_bid_i(ddr_bid_w),
        .ddr_bresp_i(ddr_bresp_w),
        .ddr_bvalid_i(ddr_bvalid_w),
        .ddr_arid_o(ddr_arid_w),
        .ddr_araddr_o(ddr_araddr_w),
        .ddr_arlen_o(ddr_arlen_w),
        .ddr_arvalid_o(ddr_arvalid_w),
        .ddr_arready_i(ddr_arready_w),
        .ddr_rid_i(ddr_rid_w),
        .ddr_rdata_i(ddr_rdata_w),
        .ddr_rresp_i(ddr_rresp_w),
        .ddr_rlast_i(ddr_rlast_w),
        .ddr_rvalid_i(ddr_rvalid_w),

        // DVP data and camera reset pins; PWDN is not bonded on this board.
        .cam0_vsync_i(cam0_vsync_i),
        .cam0_href_i(cam0_href_i),
        .cam0_data_i(cam0_data_i),
        .cam1_vsync_i(cam1_vsync_i),
        .cam1_href_i(cam1_href_i),
        .cam1_data_i(cam1_data_i),
        .cam0_pwdn_o(unused_cam0_pwdn_w),
        .cam0_rst_n_o(cam0_rst_n_o),
        .cam1_pwdn_o(unused_cam1_pwdn_w),
        .cam1_rst_n_o(cam1_rst_n_o),

        // Open-drain IO at the board boundary.
        .i2c0_scl_i(i2c0_scl_o),
        .i2c0_scl_o(i2c0_scl_w),
        .i2c0_scl_oe_o(i2c0_scl_oe_w),
        .i2c0_sda_i(i2c0_sda_o),
        .i2c0_sda_o(i2c0_sda_w),
        .i2c0_sda_oe_o(i2c0_sda_oe_w),

        // Video serializer and Ethernet DDR IO adapters.
        .tmds_sym_o(tmds_sym_w),
        .eth_rxd_i(eth_rxd_w),
        .eth_rx_dv_i(eth_rx_dv_w),
        .eth_rx_er_i(eth_rx_er_w),
        .eth_txd_o(eth_txd_w),
        .eth_tx_en_o(eth_tx_en_w),
        .eth_tx_er_o(eth_tx_er_w),
        .eth_mdc_o(eth_mdc_o),
        .eth_mdio_o(eth_mdio_w),
        .eth_mdio_oe_o(eth_mdio_oe_w),
        .eth_mdio_i(eth_mdio_o),
        .eth_phy_rst_n_o(eth_phy_rst_n_o),

        // System peripherals and unbonded debug observation.
        .uart0_rx_i(uart_rx_i),
        .uart0_tx_o(uart_tx_o),
        .gpio_i({12'b0, key_n_i}),
        .gpio_o(gpio_w),
        .gpio_oe_o(unused_gpio_oe_w),
        .debug_o(unused_debug_w)
    );
    // Only the GPIO LED slice is bonded; the camera controls have dedicated ports.
    assign led_o = gpio_w[8:4];
    genvar pin_idx;
    generate
        for (pin_idx = 0; pin_idx < 2; pin_idx = pin_idx + 1) begin : g_i2c
            assign i2c0_scl_o[pin_idx] = i2c0_scl_oe_w[pin_idx]
                ? i2c0_scl_w[pin_idx] : 1'bz;
            assign i2c0_sda_o[pin_idx] = i2c0_sda_oe_w[pin_idx]
                ? i2c0_sda_w[pin_idx] : 1'bz;
        end
    endgenerate
    assign eth_mdio_o = eth_mdio_oe_w ? eth_mdio_w : 1'bz;

    edrv32_fpga_ddr_adapter u_ddr_adapter (
        // SoC-facing AXI256.
        .ddr_awid_i(ddr_awid_w),
        .ddr_awaddr_i(ddr_awaddr_w),
        .ddr_awlen_i(ddr_awlen_w),
        .ddr_awvalid_i(ddr_awvalid_w),
        .ddr_awready_o(ddr_awready_w),
        .ddr_wdata_i(ddr_wdata_w),
        .ddr_wstrb_i(ddr_wstrb_w),
        .ddr_wlast_i(ddr_wlast_w),
        .ddr_wvalid_i(ddr_wvalid_w),
        .ddr_wready_o(ddr_wready_w),
        .ddr_bid_o(ddr_bid_w),
        .ddr_bresp_o(ddr_bresp_w),
        .ddr_bvalid_o(ddr_bvalid_w),
        .ddr_arid_i(ddr_arid_w),
        .ddr_araddr_i(ddr_araddr_w),
        .ddr_arlen_i(ddr_arlen_w),
        .ddr_arvalid_i(ddr_arvalid_w),
        .ddr_arready_o(ddr_arready_w),
        .ddr_rid_o(ddr_rid_w),
        .ddr_rdata_o(ddr_rdata_w),
        .ddr_rresp_o(ddr_rresp_w),
        .ddr_rlast_o(ddr_rlast_w),
        .ddr_rvalid_o(ddr_rvalid_w),

        // Vendor word-addressed user interface.
        .axi_awaddr_o(axi_awaddr_w),
        .axi_awuser_ap_o(axi_awuser_ap_w),
        .axi_awuser_id_o(axi_awuser_id_w),
        .axi_awlen_o(axi_awlen_w),
        .axi_awvalid_o(axi_awvalid_w),
        .axi_awready_i(axi_awready_w),
        .axi_wdata_o(axi_wdata_w),
        .axi_wstrb_o(axi_wstrb_w),
        .axi_wready_i(axi_wready_w),
        .axi_wusero_id_i(axi_wusero_id_w),
        .axi_wusero_last_i(axi_wusero_last_w),
        .axi_araddr_o(axi_araddr_w),
        .axi_aruser_ap_o(axi_aruser_ap_w),
        .axi_aruser_id_o(axi_aruser_id_w),
        .axi_arlen_o(axi_arlen_w),
        .axi_arvalid_o(axi_arvalid_w),
        .axi_arready_i(axi_arready_w),
        .axi_rid_i(axi_rid_w),
        .axi_rdata_i(axi_rdata_w),
        .axi_rlast_i(axi_rlast_w),
        .axi_rvalid_i(axi_rvalid_w),

        // X8 status synchronization remains inside SoC reset_ctrl.
        .ddr_init_done_i(ddr_init_done_w),
        .mem_ready_o(mem_ready_w)
    );
    // Vendor diagnostic outputs are unbonded; debug controls match the camera demo.
    /* verilator lint_off PINCONNECTEMPTY */
    ip_ddr3 u_ddr3 (
        .ref_clk(ddr_ref_clk_w),
        .resetn(rst_board_n_w),
        .core_clk(clk_mem_w),
        .pll_lock(),
        .phy_pll_lock(),
        .gpll_lock(),
        .rst_gpll_lock(),
        .ddrphy_cpd_lock(),
        .ddr_init_done(ddr_init_done_w),

        // DDR user port, synchronous to core_clk.
        .axi_awaddr(axi_awaddr_w),
        .axi_awuser_ap(axi_awuser_ap_w),
        .axi_awuser_id(axi_awuser_id_w),
        .axi_awlen(axi_awlen_w),
        .axi_awready(axi_awready_w),
        .axi_awvalid(axi_awvalid_w),
        .axi_wdata(axi_wdata_w),
        .axi_wstrb(axi_wstrb_w),
        .axi_wready(axi_wready_w),
        .axi_wusero_id(axi_wusero_id_w),
        .axi_wusero_last(axi_wusero_last_w),
        .axi_araddr(axi_araddr_w),
        .axi_aruser_ap(axi_aruser_ap_w),
        .axi_aruser_id(axi_aruser_id_w),
        .axi_arlen(axi_arlen_w),
        .axi_arready(axi_arready_w),
        .axi_arvalid(axi_arvalid_w),
        .axi_rdata(axi_rdata_w),
        .axi_rid(axi_rid_w),
        .axi_rlast(axi_rlast_w),
        .axi_rvalid(axi_rvalid_w),

        // Unused vendor APB diagnostic port.
        .apb_clk(1'd0),
        .apb_rst_n(1'd0),
        .apb_sel(1'd0),
        .apb_enable(1'd0),
        .apb_addr(8'd0),
        .apb_write(1'd0),
        .apb_ready(),
        .apb_wdata(16'd0),
        .apb_rdata(),

        // Physical DDR3 pins.
        .mem_cs_n(mem_cs_n_o),
        .mem_rst_n(mem_rst_n_o),
        .mem_ck(mem_ck_o),
        .mem_ck_n(mem_ck_n_o),
        .mem_cke(mem_cke_o),
        .mem_ras_n(mem_ras_n_o),
        .mem_cas_n(mem_cas_n_o),
        .mem_we_n(mem_we_n_o),
        .mem_odt(mem_odt_o),
        .mem_a(mem_a_o),
        .mem_ba(mem_ba_o),
        .mem_dqs(mem_dqs_o),
        .mem_dqs_n(mem_dqs_n_o),
        .mem_dq(mem_dq_o),
        .mem_dm(mem_dm_o),

        // Vendor debug controls, disabled as in the dual-camera demo.
        .dbg_gate_start(1'd0),
        .dbg_cpd_start(1'd0),
        .dbg_ddrphy_rst_n(1'd1),
        .dbg_gpll_scan_rst(1'd0),
        .samp_position_dyn_adj(1'd0),
        .init_samp_position_even(32'd0),
        .init_samp_position_odd(32'd0),
        .wrcal_position_dyn_adj(1'd0),
        .init_wrcal_position(32'd0),
        .force_read_clk_ctrl(1'd0),
        .init_slip_step(16'd0),
        .init_read_clk_ctrl(12'd0),
        .debug_calib_ctrl(),
        .dbg_slice_status(),
        .dbg_slice_state(),
        .debug_data(),
        .dbg_dll_upd_state(),
        .debug_gpll_dps_phase(),
        .dbg_rst_dps_state(),
        .dbg_tran_err_rst_cnt(),
        .dbg_ddrphy_init_fail(),
        .debug_cpd_offset_adj(1'd0),
        .debug_cpd_offset_dir(1'd0),
        .debug_cpd_offset(10'd0),
        .debug_dps_cnt_dir0(),
        .debug_dps_cnt_dir1(),
        .ck_dly_en(1'd0),
        .init_ck_dly_step(8'd0),
        .ck_dly_set_bin(),
        .align_error(),
        .debug_rst_state(),
        .debug_cpd_state()
    );
    /* verilator lint_on PINCONNECTEMPTY */

    edrv32_fpga_tmds u_tmds (
        .clk_pix_i(clk_pix_w),
        .clk_serial_i(clk_serial_w),
        .tmds_sym_i(tmds_sym_w),
        .tmds_data_p_o(tmds_data_p_o),
        .tmds_data_n_o(tmds_data_n_o),
        .tmds_clk_p_o(tmds_clk_p_o),
        .tmds_clk_n_o(tmds_clk_n_o)
    );
    edrv32_fpga_rgmii u_rgmii (
        .rgmii_rxc_i(rgmii_rxc_i),
        .rgmii_rxd_i(rgmii_rxd_i),
        .rgmii_rx_ctl_i(rgmii_rx_ctl_i),
        .rgmii_txc_o(rgmii_txc_o),
        .rgmii_txd_o(rgmii_txd_o),
        .rgmii_tx_ctl_o(rgmii_tx_ctl_o),
        .clk_eth_o(clk_eth_w),
        .eth_rxd_o(eth_rxd_w),
        .eth_rx_dv_o(eth_rx_dv_w),
        .eth_rx_er_o(eth_rx_er_w),
        .eth_txd_i(eth_txd_w),
        .eth_tx_en_i(eth_tx_en_w),
        .eth_tx_er_i(eth_tx_er_w)
    );

endmodule
