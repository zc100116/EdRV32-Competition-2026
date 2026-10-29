// File: edrv32_soc_tb.sv
// Spec: soc-testplan 2; SoC 3-6, 7.1; CLAUDE.md 9.2.
// Description: Boot ROM transfers control to a preloaded SRAM connection test.
//              External DDR uses the shared model; UART and SIM_EXIT are observed.
// Clock domains: independent sys, mem, pix, npu, camera and Ethernet domains.
`timescale 1ns/1ps
/* verilator lint_off BLKSEQ */
module edrv32_soc_tb;
    reg clk_sys_i = 0;
    always #5 clk_sys_i = ~clk_sys_i;
    reg clk_mem_i = 0;
    always #4 clk_mem_i = ~clk_mem_i;
    reg clk_pix_i = 0;
    always #6.734007 clk_pix_i = ~clk_pix_i;
    reg clk_npu_i = 0;
    always #3.333333 clk_npu_i = ~clk_npu_i;
    wire cam0_pclk_i;
    wire cam1_pclk_i;
    reg eth_rx_clk_i = 0;
    always #4 eth_rx_clk_i = ~eth_rx_clk_i;
    reg eth_tx_clk_i = 0;
    always #4 eth_tx_clk_i = ~eth_tx_clk_i;
    reg rst_n_i = 0;
    reg mem_ready_i = 0;
    wire [3:0] ddr_awid_o;
    wire [31:0] ddr_awaddr_o;
    wire [3:0] ddr_awlen_o;
    wire ddr_awvalid_o;
    wire ddr_awready_i;
    wire [255:0] ddr_wdata_o;
    wire [31:0] ddr_wstrb_o;
    wire ddr_wlast_o;
    wire ddr_wvalid_o;
    wire ddr_wready_i;
    wire [3:0] ddr_bid_i;
    wire [1:0] ddr_bresp_i;
    wire ddr_bvalid_i;
    wire [3:0] ddr_arid_o;
    wire [31:0] ddr_araddr_o;
    wire [3:0] ddr_arlen_o;
    wire ddr_arvalid_o;
    wire ddr_arready_i;
    wire [3:0] ddr_rid_i;
    wire [255:0] ddr_rdata_i;
    wire [1:0] ddr_rresp_i;
    wire ddr_rlast_i;
    wire ddr_rvalid_i;
    wire cam0_vsync_i;
    wire cam0_href_i;
    wire [7:0] cam0_data_i;
    wire cam1_vsync_i;
    wire cam1_href_i;
    wire [7:0] cam1_data_i;
    wire unused_cam0_pwdn_o;
    wire unused_cam0_rst_n_o;
    wire unused_cam1_pwdn_o;
    wire unused_cam1_rst_n_o;
    wire [1:0] i2c0_scl_i;
    wire [1:0] i2c0_scl_o;
    wire [1:0] i2c0_scl_oe_o;
    wire [1:0] i2c0_sda_i;
    wire [1:0] sccb_sda_oe;
    wire [1:0] i2c0_sda_o;
    wire [1:0] i2c0_sda_oe_o;
    wire [29:0] tmds_sym_o;
    wire [7:0] eth_rxd_i;
    wire eth_rx_dv_i;
    wire eth_rx_er_i;
    wire [7:0] eth_txd_o;
    wire eth_tx_en_o;
    wire eth_tx_er_o;
    wire unused_eth_mdc_o;
    wire unused_eth_mdio_o;
    wire unused_eth_mdio_oe_o;
    wire eth_mdio_i = 1'b1;
    wire unused_eth_phy_rst_n_o;
    wire uart0_rx_i;
    wire uart0_tx_o;
    reg [15:0] gpio_i = 16'hffff;
    wire [15:0] unused_gpio_o;
    wire [15:0] unused_gpio_oe_o;
    wire [63:0] unused_debug_o;

    edrv32_soc_top u_dut (
        .clk_sys_i(clk_sys_i),
        .clk_mem_i(clk_mem_i),
        .clk_pix_i(clk_pix_i),
        .clk_npu_i(clk_npu_i),
        .cam0_pclk_i(cam0_pclk_i),
        .cam1_pclk_i(cam1_pclk_i),
        .eth_rx_clk_i(eth_rx_clk_i),
        .eth_tx_clk_i(eth_tx_clk_i),
        .rst_n_i(rst_n_i),
        .mem_ready_i(mem_ready_i),
        .ddr_awid_o(ddr_awid_o),
        .ddr_awaddr_o(ddr_awaddr_o),
        .ddr_awlen_o(ddr_awlen_o),
        .ddr_awvalid_o(ddr_awvalid_o),
        .ddr_awready_i(ddr_awready_i),
        .ddr_wdata_o(ddr_wdata_o),
        .ddr_wstrb_o(ddr_wstrb_o),
        .ddr_wlast_o(ddr_wlast_o),
        .ddr_wvalid_o(ddr_wvalid_o),
        .ddr_wready_i(ddr_wready_i),
        .ddr_bid_i(ddr_bid_i),
        .ddr_bresp_i(ddr_bresp_i),
        .ddr_bvalid_i(ddr_bvalid_i),
        .ddr_arid_o(ddr_arid_o),
        .ddr_araddr_o(ddr_araddr_o),
        .ddr_arlen_o(ddr_arlen_o),
        .ddr_arvalid_o(ddr_arvalid_o),
        .ddr_arready_i(ddr_arready_i),
        .ddr_rid_i(ddr_rid_i),
        .ddr_rdata_i(ddr_rdata_i),
        .ddr_rresp_i(ddr_rresp_i),
        .ddr_rlast_i(ddr_rlast_i),
        .ddr_rvalid_i(ddr_rvalid_i),
        .cam0_vsync_i(cam0_vsync_i),
        .cam0_href_i(cam0_href_i),
        .cam0_data_i(cam0_data_i),
        .cam1_vsync_i(cam1_vsync_i),
        .cam1_href_i(cam1_href_i),
        .cam1_data_i(cam1_data_i),
        .cam0_pwdn_o(unused_cam0_pwdn_o),
        .cam0_rst_n_o(unused_cam0_rst_n_o),
        .cam1_pwdn_o(unused_cam1_pwdn_o),
        .cam1_rst_n_o(unused_cam1_rst_n_o),
        .i2c0_scl_i(i2c0_scl_i),
        .i2c0_scl_o(i2c0_scl_o),
        .i2c0_scl_oe_o(i2c0_scl_oe_o),
        .i2c0_sda_i(i2c0_sda_i),
        .i2c0_sda_o(i2c0_sda_o),
        .i2c0_sda_oe_o(i2c0_sda_oe_o),
        .tmds_sym_o(tmds_sym_o),
        .eth_rxd_i(eth_rxd_i),
        .eth_rx_dv_i(eth_rx_dv_i),
        .eth_rx_er_i(eth_rx_er_i),
        .eth_txd_o(eth_txd_o),
        .eth_tx_en_o(eth_tx_en_o),
        .eth_tx_er_o(eth_tx_er_o),
        .eth_mdc_o(unused_eth_mdc_o),
        .eth_mdio_o(unused_eth_mdio_o),
        .eth_mdio_oe_o(unused_eth_mdio_oe_o),
        .eth_mdio_i(eth_mdio_i),
        .eth_phy_rst_n_o(unused_eth_phy_rst_n_o),
        .uart0_rx_i(uart0_rx_i),
        .uart0_tx_o(uart0_tx_o),
        .gpio_i(gpio_i),
        .gpio_o(unused_gpio_o),
        .gpio_oe_o(unused_gpio_oe_o),
        .debug_o(unused_debug_o)
    );

    ddr3_axi256_model u_ddr (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_n_i),
        .awid_i(ddr_awid_o),
        .awaddr_i(ddr_awaddr_o),
        .awlen_i(ddr_awlen_o),
        .awvalid_i(ddr_awvalid_o),
        .awready_o(ddr_awready_i),
        .wdata_i(ddr_wdata_o),
        .wstrb_i(ddr_wstrb_o),
        .wlast_i(ddr_wlast_o),
        .wvalid_i(ddr_wvalid_o),
        .wready_o(ddr_wready_i),
        .bid_o(ddr_bid_i),
        .bresp_o(ddr_bresp_i),
        .bvalid_o(ddr_bvalid_i),
        .arid_i(ddr_arid_o),
        .araddr_i(ddr_araddr_o),
        .arlen_i(ddr_arlen_o),
        .arvalid_i(ddr_arvalid_o),
        .arready_o(ddr_arready_i),
        .rid_o(ddr_rid_i),
        .rdata_o(ddr_rdata_i),
        .rresp_o(ddr_rresp_i),
        .rlast_o(ddr_rlast_i),
        .rvalid_o(ddr_rvalid_i)
    );

    // External sensor configuration and pixel streams (soc-testplan 2).
    dvp_camera_model u_cam0 (
        .pclk_o(cam0_pclk_i),
        .vsync_o(cam0_vsync_i),
        .href_o(cam0_href_i),
        .data_o(cam0_data_i)
    );
    dvp_camera_model u_cam1 (
        .pclk_o(cam1_pclk_i),
        .vsync_o(cam1_vsync_i),
        .href_o(cam1_href_i),
        .data_o(cam1_data_i)
    );
    for (genvar port = 0; port < 2; port++) begin : g_sccb
        assign i2c0_scl_i[port] = !(i2c0_scl_oe_o[port] && !i2c0_scl_o[port]);
        assign i2c0_sda_i[port] = !(sccb_sda_oe[port] ||
            (i2c0_sda_oe_o[port] && !i2c0_sda_o[port]));
        sccb_model u_sccb (
            .scl_i(i2c0_scl_i[port]),
            .sda_i(i2c0_sda_i[port]),
            .sda_oe_o(sccb_sda_oe[port])
        );
    end
    wire unused_hdmi_hs;
    wire unused_hdmi_vs;
    wire unused_hdmi_de;
    wire [23:0] unused_hdmi_rgb;
    wire signed [31:0] unused_hdmi_frames;
    wire signed [31:0] unused_hdmi_pixels;
    tmds_rx_model u_hdmi (
        .clk_pix_i(clk_pix_i),
        .rst_n_i(1'b0),
        .sym_i(tmds_sym_o),
        .hs_o(unused_hdmi_hs),
        .vs_o(unused_hdmi_vs),
        .de_o(unused_hdmi_de),
        .rgb_o(unused_hdmi_rgb),
        .frame_count_o(unused_hdmi_frames),
        .frame_pixel_count_o(unused_hdmi_pixels)
    );
    eth_peer_model u_eth (
        .rx_clk_i(eth_rx_clk_i),
        .tx_clk_i(eth_tx_clk_i),
        .rst_n_i(rst_n_i),
        .rxd_o(eth_rxd_i),
        .rx_dv_o(eth_rx_dv_i),
        .rx_er_o(eth_rx_er_i),
        .txd_i(eth_txd_o),
        .tx_en_i(eth_tx_en_o),
        .tx_er_i(eth_tx_er_o)
    );
    uart_model u_uart (
        .tx_i(uart0_tx_o),
        .rx_o(uart0_rx_i)
    );
    string uart_log = "";
    initial begin
        forever begin
            wait (u_uart.received.size() != 0);
            while (u_uart.received.size() != 0) begin
                uart_log = {uart_log, string'(u_uart.received.pop_front())};
                $write("%c", uart_log[uart_log.len()-1]);
                $fflush();
            end
        end
    end
    int case_number;
    string data_dir;
    bit checks_complete = 0;
    initial begin
        if (!$value$plusargs("CASE=%d", case_number)) $fatal(1, "missing +CASE");
        if (!$value$plusargs("DATA_DIR=%s", data_dir)) $fatal(1, "missing +DATA_DIR");
    end

    // The same byte image plusarg convention as ROM/SRAM, through the model API.
    initial begin : preload_ddr
        string path;
        int fd;
        int result;
        int unused_value;
        bit [31:0] address;
        string token;
        if ($value$plusargs("DDR_HEX=%s", path)) begin
            fd = $fopen(path, "r");
            if (fd == 0) $fatal(1, "DDR_HEX open failed path=%s", path);
            address = 0;
            while (!$feof(fd)) begin
                result = $fscanf(fd, "%s", token);
                if (result == 1) begin
                    if (token[0] == "@") result = $sscanf(token, "@%h", address);
                    else begin
                        result = $sscanf(token, "%h", unused_value);
                        u_ddr.poke(address, 8'(unused_value));
                        address++;
                    end
                end
            end
            $fclose(fd);
        end
    end

    `include "eth_stimulus.svh"
    `include "media_stimulus.svh"
    always @(posedge clk_sys_i) begin
        if (u_dut.unused_sim_exit_valid_w) begin
            if (u_dut.unused_sim_exit_code_w != 0)
                $fatal(1, "FAIL soc SIM_EXIT=%h at %0t",
                    u_dut.unused_sim_exit_code_w, $time);
            begin
                if (!checks_complete)
                    $fatal(1, "FAIL SC-%02d external checks incomplete time=%0t",
                        case_number, $time);
                $display("PASS SC-%02d", case_number);
                $finish;
            end
        end
    end

    initial begin
        repeat (8) @(negedge clk_sys_i);
        rst_n_i = 1;
        repeat (8) @(negedge clk_mem_i);
        mem_ready_i = 1;
    end

    initial begin
        #1000000;
        $display("SIM SC-%02d time=%0t debug=%h", case_number, $time, unused_debug_o);
        $fflush();
    end

    initial begin
        #600000000;
        $fatal(1, "FAIL soc timeout at %0t", $time);
    end
endmodule
