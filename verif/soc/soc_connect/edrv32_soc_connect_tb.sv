// File: edrv32_soc_connect_tb.sv
// Spec: B2-1a connection smoke; SoC 3-6, 7.1; CLAUDE.md 9.2.
// Description: Boot ROM transfers control to a preloaded SRAM connection test.
//              External DDR uses the shared model; UART and SIM_EXIT are observed.
// Clock domains: independent sys, mem, pix, npu, camera and Ethernet domains.
`timescale 1ns/1ps
module edrv32_soc_connect_tb;
    reg clk_sys_i = 0;
    always #5 clk_sys_i = ~clk_sys_i;
    reg clk_mem_i = 0;
    always #4 clk_mem_i = ~clk_mem_i;
    reg clk_pix_i = 0;
    always #7 clk_pix_i = ~clk_pix_i;
    reg clk_npu_i = 0;
    always #3 clk_npu_i = ~clk_npu_i;
    reg cam0_pclk_i = 0;
    always #11 cam0_pclk_i = ~cam0_pclk_i;
    reg cam1_pclk_i = 0;
    always #13 cam1_pclk_i = ~cam1_pclk_i;
    reg eth_rx_clk_i = 0;
    always #17 eth_rx_clk_i = ~eth_rx_clk_i;
    reg eth_tx_clk_i = 0;
    always #19 eth_tx_clk_i = ~eth_tx_clk_i;
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
    wire cam0_vsync_i = 1'b0;
    wire cam0_href_i = 1'b0;
    wire [7:0] cam0_data_i = 8'b0;
    wire cam1_vsync_i = 1'b0;
    wire cam1_href_i = 1'b0;
    wire [7:0] cam1_data_i = 8'b0;
    wire cam0_pwdn_o;
    wire cam0_rst_n_o;
    wire cam1_pwdn_o;
    wire cam1_rst_n_o;
    wire [1:0] i2c0_scl_i = 2'b11;
    wire [1:0] i2c0_scl_o;
    wire [1:0] i2c0_scl_oe_o;
    wire [1:0] i2c0_sda_i = 2'b11;
    wire [1:0] i2c0_sda_o;
    wire [1:0] i2c0_sda_oe_o;
    wire [29:0] tmds_sym_o;
    wire [7:0] eth_rxd_i = 8'b0;
    wire eth_rx_dv_i = 1'b0;
    wire eth_rx_er_i = 1'b0;
    wire [7:0] eth_txd_o;
    wire eth_tx_en_o;
    wire eth_tx_er_o;
    wire eth_mdc_o;
    wire eth_mdio_o;
    wire eth_mdio_oe_o;
    wire eth_mdio_i = 1'b1;
    wire eth_phy_rst_n_o;
    wire uart0_rx_i = 1'b1;
    wire uart0_tx_o;
    wire [15:0] gpio_i = 16'hffff;
    wire [15:0] gpio_o;
    wire [15:0] gpio_oe_o;
    wire [63:0] debug_o;

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
        .cam0_pwdn_o(cam0_pwdn_o),
        .cam0_rst_n_o(cam0_rst_n_o),
        .cam1_pwdn_o(cam1_pwdn_o),
        .cam1_rst_n_o(cam1_rst_n_o),
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
        .eth_mdc_o(eth_mdc_o),
        .eth_mdio_o(eth_mdio_o),
        .eth_mdio_oe_o(eth_mdio_oe_o),
        .eth_mdio_i(eth_mdio_i),
        .eth_phy_rst_n_o(eth_phy_rst_n_o),
        .uart0_rx_i(uart0_rx_i),
        .uart0_tx_o(uart0_tx_o),
        .gpio_i(gpio_i),
        .gpio_o(gpio_o),
        .gpio_oe_o(gpio_oe_o),
        .debug_o(debug_o)
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

    // UART bit time is the software-configured 115200 baud at 100 MHz.
    localparam UART_BIT_NS = 8680;
    byte uart_byte;
    initial begin
        forever begin
            @(negedge uart0_tx_o);
            #(UART_BIT_NS + UART_BIT_NS/2);
            for (int b = 0; b < 8; b++) begin
                uart_byte[b] = uart0_tx_o;
                #UART_BIT_NS;
            end
            $write("%c", uart_byte);
        end
    end

    always @(posedge clk_sys_i) begin
        if (u_dut.unused_sim_exit_valid_w) begin
            if (u_dut.unused_sim_exit_code_w != 0)
                $fatal(1, "FAIL soc_connect SIM_EXIT=%h at %0t",
                    u_dut.unused_sim_exit_code_w, $time);
            $display("PASS soc_connect");
            $finish;
        end
    end

    initial begin
        repeat (8) @(negedge clk_sys_i);
        rst_n_i = 1;
        repeat (8) @(negedge clk_mem_i);
        mem_ready_i = 1;
    end

    initial begin
        #20000000;
        $fatal(1, "FAIL soc_connect timeout at %0t", $time);
    end
endmodule
