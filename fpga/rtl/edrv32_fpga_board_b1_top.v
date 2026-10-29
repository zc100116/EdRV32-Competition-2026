// File: edrv32_fpga_board_b1_top.v
// Spec: board-plan B1-4; edrv32-soc-spec 3.5 (GPIO0 bit map), 7.5; sys-subsys-spec 3.4.
// Description: Bootable CPU/cache/system board top, with 27 MHz to 100 MHz PLL.
//              External reset and PLL lock feed the subsystem reset sequencer.
// Clock domain: clk_sys (100 MHz); clk_i is the 27 MHz PLL reference.
module edrv32_fpga_board_b1_top (
    // Board clock and active-low reset key.
    input wire clk_i,
    input wire rst_n_i,

    // UART0 and GPIO pins.
    input wire uart_rx_i,
    output wire uart_tx_o,
    // KEY1-KEY4 (active low) and LED0-LED4, SoC 3.5 GPIO0 bits 0-3 and 4-8.
    input wire [3:0] key_n_i,
    output wire [4:0] led_o
);

    // PLL lock qualifies asynchronous reset; reset_ctrl synchronizes its release.
    wire clk_sys_w;
    wire clk_npu_w;
    wire pll_lock_w;
    wire rst_board_n_w;

    ip_pll_sys u_pll_sys (
        .clkin1(clk_i),
        .clkout0(clk_sys_w),
        .clkout1(clk_npu_w),
        .lock(pll_lock_w)
    );

    assign rst_board_n_w = rst_n_i & pll_lock_w;

    // Sequenced resets from the system subsystem.
    wire rst_sys_n_w;

    // I$ read master to sys_xbar m0.
    wire [3:0] iaxi_arid_w;
    wire [31:0] iaxi_araddr_w;
    wire [7:0] iaxi_arlen_w;
    wire [2:0] iaxi_arsize_w;
    wire [1:0] iaxi_arburst_w;
    wire iaxi_arvalid_w;
    wire iaxi_arready_w;
    wire [3:0] iaxi_rid_w;
    wire [63:0] iaxi_rdata_w;
    wire [1:0] iaxi_rresp_w;
    wire iaxi_rlast_w;
    wire iaxi_rvalid_w;
    wire iaxi_rready_w;

    // D$ read/write master to sys_xbar m1.
    wire [3:0] daxi_awid_w;
    wire [31:0] daxi_awaddr_w;
    wire [7:0] daxi_awlen_w;
    wire [2:0] daxi_awsize_w;
    wire [1:0] daxi_awburst_w;
    wire daxi_awvalid_w;
    wire daxi_awready_w;
    wire [63:0] daxi_wdata_w;
    wire [7:0] daxi_wstrb_w;
    wire daxi_wlast_w;
    wire daxi_wvalid_w;
    wire daxi_wready_w;
    wire [3:0] daxi_bid_w;
    wire [1:0] daxi_bresp_w;
    wire daxi_bvalid_w;
    wire daxi_bready_w;
    wire [3:0] daxi_arid_w;
    wire [31:0] daxi_araddr_w;
    wire [7:0] daxi_arlen_w;
    wire [2:0] daxi_arsize_w;
    wire [1:0] daxi_arburst_w;
    wire daxi_arvalid_w;
    wire daxi_arready_w;
    wire [3:0] daxi_rid_w;
    wire [63:0] daxi_rdata_w;
    wire [1:0] daxi_rresp_w;
    wire daxi_rlast_w;
    wire daxi_rvalid_w;
    wire daxi_rready_w;

    // Cache control APB from the system APB decoder.
    wire [11:0] cache_apb_paddr_w;
    wire cache_apb_psel_w;
    wire cache_apb_penable_w;
    wire cache_apb_pwrite_w;
    wire [31:0] cache_apb_pwdata_w;
    wire [3:0] cache_apb_pstrb_w;
    wire [31:0] cache_apb_prdata_w;
    wire cache_apb_pready_w;
    wire cache_apb_pslverr_w;

    // Interrupts and machine timer.
    wire irq_cache_w;
    wire irq_meip_w;
    wire irq_msip_w;
    wire irq_mtip_w;
    wire [63:0] mtime_w;

    // GPIO bit0 is the boot key (spec SoC 7.5, active-low); bits 3:0 drive LEDs.
    /* verilator lint_off UNUSEDSIGNAL */
    wire [15:0] gpio_o_w;
    /* verilator lint_on UNUSEDSIGNAL */

    // Outputs with no pin or target in this B1 board top are left open.
    /* verilator lint_off PINCONNECTEMPTY */

    edrv32_cpu_subsys u_cpu_subsys (
        // Clock and reset.
        .clk_i(clk_sys_w),
        .rst_n_i(rst_sys_n_w),

        // I$ AXI64 read master.
        .iaxi_arid_o(iaxi_arid_w),
        .iaxi_araddr_o(iaxi_araddr_w),
        .iaxi_arlen_o(iaxi_arlen_w),
        .iaxi_arsize_o(iaxi_arsize_w),
        .iaxi_arburst_o(iaxi_arburst_w),
        .iaxi_arvalid_o(iaxi_arvalid_w),
        .iaxi_arready_i(iaxi_arready_w),
        .iaxi_rid_i(iaxi_rid_w),
        .iaxi_rdata_i(iaxi_rdata_w),
        .iaxi_rresp_i(iaxi_rresp_w),
        .iaxi_rlast_i(iaxi_rlast_w),
        .iaxi_rvalid_i(iaxi_rvalid_w),
        .iaxi_rready_o(iaxi_rready_w),

        // D$ AXI64 read/write master.
        .daxi_awid_o(daxi_awid_w),
        .daxi_awaddr_o(daxi_awaddr_w),
        .daxi_awlen_o(daxi_awlen_w),
        .daxi_awsize_o(daxi_awsize_w),
        .daxi_awburst_o(daxi_awburst_w),
        .daxi_awvalid_o(daxi_awvalid_w),
        .daxi_awready_i(daxi_awready_w),
        .daxi_wdata_o(daxi_wdata_w),
        .daxi_wstrb_o(daxi_wstrb_w),
        .daxi_wlast_o(daxi_wlast_w),
        .daxi_wvalid_o(daxi_wvalid_w),
        .daxi_wready_i(daxi_wready_w),
        .daxi_bid_i(daxi_bid_w),
        .daxi_bresp_i(daxi_bresp_w),
        .daxi_bvalid_i(daxi_bvalid_w),
        .daxi_bready_o(daxi_bready_w),
        .daxi_arid_o(daxi_arid_w),
        .daxi_araddr_o(daxi_araddr_w),
        .daxi_arlen_o(daxi_arlen_w),
        .daxi_arsize_o(daxi_arsize_w),
        .daxi_arburst_o(daxi_arburst_w),
        .daxi_arvalid_o(daxi_arvalid_w),
        .daxi_arready_i(daxi_arready_w),
        .daxi_rid_i(daxi_rid_w),
        .daxi_rdata_i(daxi_rdata_w),
        .daxi_rresp_i(daxi_rresp_w),
        .daxi_rlast_i(daxi_rlast_w),
        .daxi_rvalid_i(daxi_rvalid_w),
        .daxi_rready_o(daxi_rready_w),

        // APB cache control slave.
        .apb_paddr_i(cache_apb_paddr_w),
        .apb_psel_i(cache_apb_psel_w),
        .apb_penable_i(cache_apb_penable_w),
        .apb_pwrite_i(cache_apb_pwrite_w),
        .apb_pwdata_i(cache_apb_pwdata_w),
        .apb_pstrb_i(cache_apb_pstrb_w),
        .apb_pready_o(cache_apb_pready_w),
        .apb_prdata_o(cache_apb_prdata_w),
        .apb_pslverr_o(cache_apb_pslverr_w),

        // Interrupts and debug.
        .irq_meip_i(irq_meip_w),
        .irq_msip_i(irq_msip_w),
        .irq_mtip_i(irq_mtip_w),
        .mtime_i(mtime_w),
        .debug_o(),
        .irq_o(irq_cache_w)
    );

    edrv32_sys_subsys u_sys_subsys (
        // Unused engine domains share clk_sys in the CPU-only B1 system.
        .clk_sys_i(clk_sys_w),
        .clk_mem_i(clk_sys_w),
        .clk_pix_i(clk_sys_w),
        .cam0_pclk_i(clk_sys_w),
        .cam1_pclk_i(clk_sys_w),
        .eth_rx_clk_i(clk_sys_w),
        .eth_tx_clk_i(clk_sys_w),
        .clk_npu_i(clk_npu_w),
        .rst_n_i(rst_board_n_w),
        .mem_ready_i(1'b1),

        // Sequenced domain resets.
        .rst_sys_por_n_o(),
        .rst_sys_n_o(rst_sys_n_w),
        .rst_mem_core_n_o(),
        .rst_mem_n_o(),
        .rst_pix_n_o(),
        .rst_cam0_n_o(),
        .rst_cam1_n_o(),
        .rst_eth_rx_n_o(),
        .rst_eth_tx_n_o(),
        .rst_npu_n_o(),

        // m0: I$ read master.
        .m0_arid_i(iaxi_arid_w),
        .m0_araddr_i(iaxi_araddr_w),
        .m0_arlen_i(iaxi_arlen_w),
        .m0_arsize_i(iaxi_arsize_w),
        .m0_arburst_i(iaxi_arburst_w),
        .m0_arvalid_i(iaxi_arvalid_w),
        .m0_arready_o(iaxi_arready_w),
        .m0_rid_o(iaxi_rid_w),
        .m0_rdata_o(iaxi_rdata_w),
        .m0_rresp_o(iaxi_rresp_w),
        .m0_rlast_o(iaxi_rlast_w),
        .m0_rvalid_o(iaxi_rvalid_w),
        .m0_rready_i(iaxi_rready_w),

        // m1: D$ read/write master.
        .m1_awid_i(daxi_awid_w),
        .m1_awaddr_i(daxi_awaddr_w),
        .m1_awlen_i(daxi_awlen_w),
        .m1_awsize_i(daxi_awsize_w),
        .m1_awburst_i(daxi_awburst_w),
        .m1_awvalid_i(daxi_awvalid_w),
        .m1_awready_o(daxi_awready_w),
        .m1_wdata_i(daxi_wdata_w),
        .m1_wstrb_i(daxi_wstrb_w),
        .m1_wlast_i(daxi_wlast_w),
        .m1_wvalid_i(daxi_wvalid_w),
        .m1_wready_o(daxi_wready_w),
        .m1_bid_o(daxi_bid_w),
        .m1_bresp_o(daxi_bresp_w),
        .m1_bvalid_o(daxi_bvalid_w),
        .m1_bready_i(daxi_bready_w),
        .m1_arid_i(daxi_arid_w),
        .m1_araddr_i(daxi_araddr_w),
        .m1_arlen_i(daxi_arlen_w),
        .m1_arsize_i(daxi_arsize_w),
        .m1_arburst_i(daxi_arburst_w),
        .m1_arvalid_i(daxi_arvalid_w),
        .m1_arready_o(daxi_arready_w),
        .m1_rid_o(daxi_rid_w),
        .m1_rdata_o(daxi_rdata_w),
        .m1_rresp_o(daxi_rresp_w),
        .m1_rlast_o(daxi_rlast_w),
        .m1_rvalid_o(daxi_rvalid_w),
        .m1_rready_i(daxi_rready_w),

        // s6: DDR window has no target here; software must not access it.
        .s6_awid_o(),
        .s6_awaddr_o(),
        .s6_awlen_o(),
        .s6_awsize_o(),
        .s6_awburst_o(),
        .s6_awvalid_o(),
        .s6_awready_i(1'b0),
        .s6_wdata_o(),
        .s6_wstrb_o(),
        .s6_wlast_o(),
        .s6_wvalid_o(),
        .s6_wready_i(1'b0),
        .s6_bid_i(4'd0),
        .s6_bresp_i(2'd0),
        .s6_bvalid_i(1'b0),
        .s6_bready_o(),
        .s6_arid_o(),
        .s6_araddr_o(),
        .s6_arlen_o(),
        .s6_arsize_o(),
        .s6_arburst_o(),
        .s6_arvalid_o(),
        .s6_arready_i(1'b0),
        .s6_rid_i(4'd0),
        .s6_rdata_i(64'd0),
        .s6_rresp_i(2'd0),
        .s6_rlast_i(1'b0),
        .s6_rvalid_i(1'b0),
        .s6_rready_o(),

        // Media APB slots are tied off like reserved slots (spec 2.3).
        .media_apb_paddr_o(),
        .media_apb_psel_o(),
        .media_apb_penable_o(),
        .media_apb_pwrite_o(),
        .media_apb_pwdata_o(),
        .media_apb_pstrb_o(),
        .media_apb_prdata_i(512'd0),
        .media_apb_pready_i(16'hffff),
        .media_apb_pslverr_i(16'hffff),

        // Cache control APB to the CPU subsystem.
        .cache_apb_paddr_o(cache_apb_paddr_w),
        .cache_apb_psel_o(cache_apb_psel_w),
        .cache_apb_penable_o(cache_apb_penable_w),
        .cache_apb_pwrite_o(cache_apb_pwrite_w),
        .cache_apb_pwdata_o(cache_apb_pwdata_w),
        .cache_apb_pstrb_o(cache_apb_pstrb_w),
        .cache_apb_prdata_i(cache_apb_prdata_w),
        .cache_apb_pready_i(cache_apb_pready_w),
        .cache_apb_pslverr_i(cache_apb_pslverr_w),

        // External interrupt sources.
        .irq_cache_i(irq_cache_w),
        .irq_src_i(8'd0),

        // CLINT.
        .mtime_o(mtime_w),
        .irq_mtip_o(irq_mtip_w),
        .irq_msip_o(irq_msip_w),

        // PLIC.
        .irq_meip_o(irq_meip_w),

        // UART0.
        .uart0_rx_i(uart_rx_i),
        .uart0_tx_o(uart_tx_o),

        // GPIO.
        .gpio_i({12'd0, key_n_i}),
        .gpio_o(gpio_o_w),
        .gpio_oe_o(),

        // I2C0 pins are idle-high inputs in this top.
        .i2c0_scl_i(2'b11),
        .i2c0_scl_o(),
        .i2c0_scl_oe_o(),
        .i2c0_sda_i(2'b11),
        .i2c0_sda_o(),
        .i2c0_sda_oe_o(),

        // SYSCTRL simulation exit is unused on the board.
        .sim_exit_valid_o(),
        .sim_exit_code_o()
    );

    /* verilator lint_on PINCONNECTEMPTY */

    assign led_o = gpio_o_w[8:4];

endmodule
