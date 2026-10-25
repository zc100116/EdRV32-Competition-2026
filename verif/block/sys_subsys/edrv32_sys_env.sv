// File: edrv32_sys_env.sv
// Spec: sys-subsys 3.4; sys-subsys-testplan 2, 5.
// Description: Two-master independent SB environment and external device peers.
// Clock domains: asynchronous clk_sys and clk_mem, plus reset-only peripheral clocks.
module edrv32_sys_env;
    // The generated map intentionally also contains constants for other clients.
    /* verilator lint_off UNUSEDPARAM */
    `include "edrv32_soc_map.vh"
    /* verilator lint_on UNUSEDPARAM */
    logic clk_sys = 0;
    logic clk_mem = 0;
    logic clk_pix = 0;
    logic cam0_pclk = 0;
    logic cam1_pclk = 0;
    logic eth_rx_clk = 0;
    logic eth_tx_clk = 0;
    realtime sys_half = 3.333;
    realtime mem_half = 4.0;
    logic rst_n = 0;
    logic mem_ready = 0;
    logic irq_cache = 0;
    logic [15:8] irq_src = 0;
    logic [15:0] gpio = 0;
    logic uart_rx;
    logic uart_tx;
    logic [1:0] scl_i;
    logic [1:0] sda_i;
    logic [1:0] scl_o;
    logic [1:0] sda_o;
    logic [1:0] scl_oe;
    logic [1:0] sda_oe;
    logic [1:0] peer_sda_oe;
    logic [1:0] test_scl_oe = 0;
    logic [1:0] test_sda_oe = 0;
    logic [15:0] gpio_out;
    logic [15:0] gpio_oe;
    logic irq_meip;
    logic irq_msip;
    logic irq_mtip;
    logic [63:0] mtime;
    logic sim_exit_valid;
    logic [31:0] sim_exit_code;
    // Reset outputs are deliberately sampled by checks and used as asynchronous resets.
    /* verilator lint_off SYNCASYNCNET */
    logic rst_sys_n;
    logic rst_mem_core_n;
    logic rst_mem_n;
    logic rst_pix_n;
    logic rst_cam0_n;
    logic rst_cam1_n;
    logic rst_eth_rx_n;
    logic rst_eth_tx_n;
    /* verilator lint_on SYNCASYNCNET */
    edrv32_axi64_if m0();
    edrv32_axi64_if m1();
    edrv32_axi64_if s6();
    edrv32_apb_if media();
    edrv32_apb_if cache();
    edrv32_axi64_master u_m0 (
        .clk_i(clk_sys),
        .rst_n_i(rst_sys_n),
        .bus(m0)
    );
    edrv32_axi64_master u_m1 (
        .clk_i(clk_sys),
        .rst_n_i(rst_sys_n),
        .bus(m1)
    );
    edrv32_axi64_memory u_ddr (
        .clk_i(clk_sys),
        .rst_n_i(rst_sys_n),
        .bus(s6)
    );
    edrv32_apb_memory u_media (
        .clk_i(clk_mem),
        .rst_n_i(rst_mem_n),
        .bus(media)
    );
    edrv32_apb_memory u_cache (
        .clk_i(clk_sys),
        .rst_n_i(rst_sys_n),
        .bus(cache)
    );
    edrv32_apb_checker u_media_check (
        .clk_i(clk_mem),
        .rst_n_i(rst_mem_n),
        .bus(media)
    );
    edrv32_apb_checker u_cache_check (
        .clk_i(clk_sys),
        .rst_n_i(rst_sys_n),
        .bus(cache)
    );
    uart_model u_uart (
        .tx_i(uart_tx),
        .rx_o(uart_rx)
    );
    sccb_model u_cam0 (
        .scl_i(scl_i[0]),
        .sda_i(sda_i[0]),
        .sda_oe_o(peer_sda_oe[0])
    );
    sccb_model u_cam1 (
        .scl_i(scl_i[1]),
        .sda_i(sda_i[1]),
        .sda_oe_o(peer_sda_oe[1])
    );
    assign scl_i = ~((scl_oe & ~scl_o) | test_scl_oe);
    assign sda_i = ~((sda_oe & ~sda_o) | peer_sda_oe | test_sda_oe);
    // Simulation clock generators require immediate toggles after their delays.
    /* verilator lint_off BLKSEQ */
    always #(sys_half) clk_sys = ~clk_sys;
    initial begin
        #1.137;
        forever #(mem_half) clk_mem = ~clk_mem;
    end
    always #6.734 clk_pix = ~clk_pix;
    always #7.7 cam0_pclk = ~cam0_pclk;
    always #8.3 cam1_pclk = ~cam1_pclk;
    always #4.1 eth_rx_clk = ~eth_rx_clk;
    always #4.3 eth_tx_clk = ~eth_tx_clk;
    /* verilator lint_on BLKSEQ */
    edrv32_sys_subsys u_dut (
        .clk_sys_i(clk_sys),
        .clk_mem_i(clk_mem),
        .clk_pix_i(clk_pix),
        .cam0_pclk_i(cam0_pclk),
        .cam1_pclk_i(cam1_pclk),
        .eth_rx_clk_i(eth_rx_clk),
        .eth_tx_clk_i(eth_tx_clk),
        .rst_n_i(rst_n),
        .mem_ready_i(mem_ready),
        .rst_sys_n_o(rst_sys_n),
        .rst_mem_core_n_o(rst_mem_core_n),
        .rst_mem_n_o(rst_mem_n),
        .rst_pix_n_o(rst_pix_n),
        .rst_cam0_n_o(rst_cam0_n),
        .rst_cam1_n_o(rst_cam1_n),
        .rst_eth_rx_n_o(rst_eth_rx_n),
        .rst_eth_tx_n_o(rst_eth_tx_n),
        .m0_arid_i(m0.arid),
        .m0_araddr_i(m0.araddr),
        .m0_arlen_i(m0.arlen),
        .m0_arsize_i(m0.arsize),
        .m0_arburst_i(m0.arburst),
        .m0_arvalid_i(m0.arvalid),
        .m0_arready_o(m0.arready),
        .m0_rid_o(m0.rid),
        .m0_rdata_o(m0.rdata),
        .m0_rresp_o(m0.rresp),
        .m0_rlast_o(m0.rlast),
        .m0_rvalid_o(m0.rvalid),
        .m0_rready_i(m0.rready),
        .m1_awid_i(m1.awid),
        .m1_awaddr_i(m1.awaddr),
        .m1_awlen_i(m1.awlen),
        .m1_awsize_i(m1.awsize),
        .m1_awburst_i(m1.awburst),
        .m1_awvalid_i(m1.awvalid),
        .m1_awready_o(m1.awready),
        .m1_wdata_i(m1.wdata),
        .m1_wstrb_i(m1.wstrb),
        .m1_wlast_i(m1.wlast),
        .m1_wvalid_i(m1.wvalid),
        .m1_wready_o(m1.wready),
        .m1_bid_o(m1.bid),
        .m1_bresp_o(m1.bresp),
        .m1_bvalid_o(m1.bvalid),
        .m1_bready_i(m1.bready),
        .m1_arid_i(m1.arid),
        .m1_araddr_i(m1.araddr),
        .m1_arlen_i(m1.arlen),
        .m1_arsize_i(m1.arsize),
        .m1_arburst_i(m1.arburst),
        .m1_arvalid_i(m1.arvalid),
        .m1_arready_o(m1.arready),
        .m1_rid_o(m1.rid),
        .m1_rdata_o(m1.rdata),
        .m1_rresp_o(m1.rresp),
        .m1_rlast_o(m1.rlast),
        .m1_rvalid_o(m1.rvalid),
        .m1_rready_i(m1.rready),
        .s6_awid_o(s6.awid),
        .s6_awaddr_o(s6.awaddr),
        .s6_awlen_o(s6.awlen),
        .s6_awsize_o(s6.awsize),
        .s6_awburst_o(s6.awburst),
        .s6_awvalid_o(s6.awvalid),
        .s6_awready_i(s6.awready),
        .s6_wdata_o(s6.wdata),
        .s6_wstrb_o(s6.wstrb),
        .s6_wlast_o(s6.wlast),
        .s6_wvalid_o(s6.wvalid),
        .s6_wready_i(s6.wready),
        .s6_bid_i(s6.bid),
        .s6_bresp_i(s6.bresp),
        .s6_bvalid_i(s6.bvalid),
        .s6_bready_o(s6.bready),
        .s6_arid_o(s6.arid),
        .s6_araddr_o(s6.araddr),
        .s6_arlen_o(s6.arlen),
        .s6_arsize_o(s6.arsize),
        .s6_arburst_o(s6.arburst),
        .s6_arvalid_o(s6.arvalid),
        .s6_arready_i(s6.arready),
        .s6_rid_i(s6.rid),
        .s6_rdata_i(s6.rdata),
        .s6_rresp_i(s6.rresp),
        .s6_rlast_i(s6.rlast),
        .s6_rvalid_i(s6.rvalid),
        .s6_rready_o(s6.rready),
        .media_apb_paddr_o(media.paddr),
        .media_apb_psel_o(media.psel),
        .media_apb_penable_o(media.penable),
        .media_apb_pwrite_o(media.pwrite),
        .media_apb_pwdata_o(media.pwdata),
        .media_apb_pstrb_o(media.pstrb),
        .media_apb_prdata_i(media.prdata),
        .media_apb_pready_i(media.pready),
        .media_apb_pslverr_i(media.pslverr),
        .cache_apb_paddr_o(cache.paddr),
        .cache_apb_psel_o(cache.psel[5]),
        .cache_apb_penable_o(cache.penable),
        .cache_apb_pwrite_o(cache.pwrite),
        .cache_apb_pwdata_o(cache.pwdata),
        .cache_apb_pstrb_o(cache.pstrb),
        .cache_apb_prdata_i(cache.prdata[5*32 +: 32]),
        .cache_apb_pready_i(cache.pready[5]),
        .cache_apb_pslverr_i(cache.pslverr[5]),
        .irq_cache_i(irq_cache),
        .irq_src_i(irq_src),
        .irq_meip_o(irq_meip),
        .irq_msip_o(irq_msip),
        .irq_mtip_o(irq_mtip),
        .mtime_o(mtime),
        .uart0_tx_o(uart_tx),
        .uart0_rx_i(uart_rx),
        .gpio_o(gpio_out),
        .gpio_oe_o(gpio_oe),
        .gpio_i(gpio),
        .i2c0_scl_o(scl_o),
        .i2c0_scl_oe_o(scl_oe),
        .i2c0_scl_i(scl_i),
        .i2c0_sda_o(sda_o),
        .i2c0_sda_oe_o(sda_oe),
        .i2c0_sda_i(sda_i),
        .sim_exit_valid_o(sim_exit_valid),
        .sim_exit_code_o(sim_exit_code)
    );
    // CACHE_CTRL is the only connected system APB slot at this boundary.
    assign cache.psel[4:0] = 0;
    assign cache.psel[15:6] = 0;
    edrv32_axi64_checker #(.CACHE_CONTRACT(0)) u_m0_check (
        .clk_i(clk_sys),
        .rst_n_i(rst_sys_n),
        .bus(m0)
    );
    edrv32_axi64_checker #(.CACHE_CONTRACT(0)) u_m1_check (
        .clk_i(clk_sys),
        .rst_n_i(rst_sys_n),
        .bus(m1)
    );
    edrv32_axi64_checker #(.CACHE_CONTRACT(0)) u_s6_check (
        .clk_i(clk_sys),
        .rst_n_i(rst_sys_n),
        .bus(s6)
    );
    // Only a dropped VALID or changed payload under backpressure is an injected violation.
    task automatic check(
        input bit ok,
        input string what,
        input bit [63:0] expected,
        input bit [63:0] actual
    );
        if (!ok) $fatal(1, "FAIL %s expected=%h actual=%h time=%0t",
                        what, expected, actual, $time);
    endtask
    task automatic boot();
        load_reference_images();
        u_m0.idle();
        u_m1.idle();
        u_cache.used_slots = 16'h0020;
        repeat (5) @(negedge clk_sys);
        rst_n = 1;
        repeat (7) @(negedge clk_mem);
        mem_ready = 1;
        wait (rst_sys_n);
        repeat (2) @(negedge clk_sys);
    endtask
    `include "edrv32_sys_cases.svh"
endmodule
