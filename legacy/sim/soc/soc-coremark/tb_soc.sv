// ============================================================================
// File        : tb_soc.sv
// Author      : Edward ZC
// Description : SoC-level software testbench. Instantiates edrv32_soc_top,
//               loads the program into SRAM (+SRAMFILE), and captures the
//               console byte stream at the APB bridge (writes to UART0 TXDATA
//               @0x4000_0000).  On the board the same bytes leave through the
//               real UART pin; in simulation the APB tap avoids serial decode.
//               Completion: the benchmark's exit store to TOHOST (0x8000_1000)
//               hits the DECERR responder in the SoC — the TB watches the
//               dmem fabric request instead, or simply relies on +TIMEOUT.
// Notes       : Verilator 4.038 compatible.  PASS/FAIL markers are derived
//               from the captured console text (benchmark self-checking).
// ============================================================================
module tb_soc #(
    parameter CPU_HPM_ENABLE = 1,
    parameter AXI_MON_ENABLE = 1
)(
    input wire clk,
    input wire rst_n
);

    wire        uart0_tx_w;
    reg         uart0_rx_r;
    reg  [15:0] gpio_in_r;
    wire [15:0] unused_gpio_out_w;
    wire [15:0] unused_gpio_oe_w;
    wire [3:0]  unused_spi_io_w;
    wire [3:0]  unused_spi_io_oe_w;
    wire        unused_spi_sclk_w;
    wire [3:0]  unused_spi_cs_n_w;
    wire        spi_flash_miso_w;
    wire        spi_flash_command_seen_w;
    wire        spi_flash_protocol_error_w;
    wire [`AXI_ID_W+1:0] ddr_awid_w;
    wire [31:0] ddr_awaddr_w;
    wire [`AXI_LEN_W-1:0] ddr_awlen_w;
    wire [`AXI_SIZE_W-1:0] ddr_awsize_w;
    wire [`AXI_BURST_W-1:0] ddr_awburst_w;
    wire ddr_awvalid_w, ddr_awready_w;
    wire [`AXI_DATA_W-1:0] ddr_wdata_w;
    wire [`AXI_STRB_W-1:0] ddr_wstrb_w;
    wire ddr_wlast_w, ddr_wvalid_w, ddr_wready_w;
    wire [`AXI_ID_W+1:0] ddr_bid_w;
    wire [`AXI_RESP_W-1:0] ddr_bresp_w;
    wire ddr_bvalid_w, ddr_bready_w;
    wire [`AXI_ID_W+1:0] ddr_arid_w;
    wire [31:0] ddr_araddr_w;
    wire [`AXI_LEN_W-1:0] ddr_arlen_w;
    wire [`AXI_SIZE_W-1:0] ddr_arsize_w;
    wire [`AXI_BURST_W-1:0] ddr_arburst_w;
    wire ddr_arvalid_w, ddr_arready_w;
    wire [`AXI_ID_W+1:0] ddr_rid_w;
    wire [`AXI_DATA_W-1:0] ddr_rdata_w;
    wire [`AXI_RESP_W-1:0] ddr_rresp_w;
    wire ddr_rlast_w, ddr_rvalid_w, ddr_rready_w;
    wire [255:0] debug_w;

    edrv32_soc_top #(
        .RESET_PC       (32'h1000_0000), // Phase-1 SRAM bring-up
        .CPU_HPM_ENABLE (CPU_HPM_ENABLE),
        .AXI_MON_ENABLE (AXI_MON_ENABLE),
        .DDR_ENABLE     (1),
        .DDR_SIZE_BYTES (32'h0001_0000)
    ) u_soc (
        .clk        (clk),
        .rst_n      (rst_n),
        .uart0_tx_o (uart0_tx_w),
        .uart0_rx_i (uart0_rx_r),
        .gpio_in_i  (gpio_in_r),
        .gpio_out_o (unused_gpio_out_w),
        .gpio_oe_o  (unused_gpio_oe_w),
        .spi_io_i   ({2'b11, spi_flash_miso_w, 1'b1}),
        .spi_io_o   (unused_spi_io_w),
        .spi_io_oe_o(unused_spi_io_oe_w),
        .spi_sclk_o (unused_spi_sclk_w),
        .spi_cs_n_o (unused_spi_cs_n_w),
        .platform_irq_i(28'b0),
        .vision_cam0_init_done_i(1'b0),
        .vision_cam1_init_done_i(1'b0),
        .vision_cam_error_i(1'b0),
        .vision_cam0_frame_count_i(32'b0),
        .vision_cam1_frame_count_i(32'b0),
        .vision_cam_cfg_ack_toggle_i(1'b0),
        .vision_cam_cfg_response_error_i(1'b0),
        .vision_cam_cfg_response_data_i(8'b0),
        .vision_disp_active_buffer_i(2'b0),
        .vision_disp_error_i(1'b0),
        .vision_disp_frame_count_i(32'b0),
        .vision_disp_underflow_count_i(32'b0),
        .vision_cam0_enable_o(), .vision_cam1_enable_o(),
        .vision_cam_cfg_req_toggle_o(), .vision_cam_cfg_camera_o(),
        .vision_cam_cfg_read_o(),
        .vision_cam_cfg_reg_addr_o(), .vision_cam_cfg_write_data_o(),
        .vision_disp_enable_o(),
        .ddr_awid_o (ddr_awid_w), .ddr_awaddr_o(ddr_awaddr_w),
        .ddr_awlen_o(ddr_awlen_w), .ddr_awsize_o(ddr_awsize_w),
        .ddr_awburst_o(ddr_awburst_w), .ddr_awvalid_o(ddr_awvalid_w),
        .ddr_awready_i(ddr_awready_w), .ddr_wdata_o(ddr_wdata_w),
        .ddr_wstrb_o(ddr_wstrb_w), .ddr_wlast_o(ddr_wlast_w),
        .ddr_wvalid_o(ddr_wvalid_w), .ddr_wready_i(ddr_wready_w),
        .ddr_bid_i(ddr_bid_w), .ddr_bresp_i(ddr_bresp_w),
        .ddr_bvalid_i(ddr_bvalid_w), .ddr_bready_o(ddr_bready_w),
        .ddr_arid_o(ddr_arid_w), .ddr_araddr_o(ddr_araddr_w),
        .ddr_arlen_o(ddr_arlen_w), .ddr_arsize_o(ddr_arsize_w),
        .ddr_arburst_o(ddr_arburst_w), .ddr_arvalid_o(ddr_arvalid_w),
        .ddr_arready_i(ddr_arready_w), .ddr_rid_i(ddr_rid_w),
        .ddr_rdata_i(ddr_rdata_w), .ddr_rresp_i(ddr_rresp_w),
        .ddr_rlast_i(ddr_rlast_w), .ddr_rvalid_i(ddr_rvalid_w),
        .ddr_rready_o(ddr_rready_w), .debug_o(debug_w)
    );

    spi_flash_jedec_model u_spi_flash_jedec_model (
        .cs_n_i            (unused_spi_cs_n_w[0]),
        .sclk_i            (unused_spi_sclk_w),
        .mosi_i            (unused_spi_io_w[0]),
        .miso_o            (spi_flash_miso_w),
        .command_seen_o    (spi_flash_command_seen_w),
        .protocol_error_o  (spi_flash_protocol_error_w)
    );

    initial begin
        gpio_in_r = 16'ha500;
    end

    axi_mem_model #(
        .ID_W           (`AXI_ID_W + 2),
        .BASE           (32'h0000_0000),
        .SIZE_BYTES     (32'h0001_0000),
        .SEED           (32'h2026_0830),
        .MAX_OUTSTANDING(8)
    ) u_ddr_model (
        .clk(clk), .rst_n(rst_n), .err_addr_i(32'hffff_ffff),
        .awid_i(ddr_awid_w), .awaddr_i(ddr_awaddr_w),
        .awlen_i(ddr_awlen_w), .awsize_i(ddr_awsize_w),
        .awburst_i(ddr_awburst_w), .awvalid_i(ddr_awvalid_w),
        .awready_o(ddr_awready_w), .wdata_i(ddr_wdata_w),
        .wstrb_i(ddr_wstrb_w), .wlast_i(ddr_wlast_w),
        .wvalid_i(ddr_wvalid_w), .wready_o(ddr_wready_w),
        .bid_o(ddr_bid_w), .bresp_o(ddr_bresp_w),
        .bvalid_o(ddr_bvalid_w), .bready_i(ddr_bready_w),
        .arid_i(ddr_arid_w), .araddr_i(ddr_araddr_w),
        .arlen_i(ddr_arlen_w), .arsize_i(ddr_arsize_w),
        .arburst_i(ddr_arburst_w), .arvalid_i(ddr_arvalid_w),
        .arready_o(ddr_arready_w), .rid_o(ddr_rid_w),
        .rdata_o(ddr_rdata_w), .rresp_o(ddr_rresp_w),
        .rlast_o(ddr_rlast_w), .rvalid_o(ddr_rvalid_w),
        .rready_i(ddr_rready_w)
    );

    // Control outputs must always be known. AXI payload is observable only
    // while its channel is valid; inactive payload registers need not reset.
    always @(posedge clk) begin
        if (rst_n && ((^{uart0_tx_w,
                           unused_gpio_out_w,
                           unused_gpio_oe_w,
                           unused_spi_io_w,
                           unused_spi_io_oe_w,
                           unused_spi_sclk_w,
                           unused_spi_cs_n_w,
                           ddr_awvalid_w, ddr_wvalid_w, ddr_bready_w,
                           ddr_arvalid_w, ddr_rready_w,
                           debug_w[159:128]}) === 1'bx)) begin
            $display("SOC_OUTPUT_X uart=%h gpio=%h/%h spi=%h/%h/%h/%h ddr=%h%h%h%h%h debug=%h",
                     uart0_tx_w, unused_gpio_out_w, unused_gpio_oe_w,
                     unused_spi_io_w, unused_spi_io_oe_w,
                     unused_spi_sclk_w, unused_spi_cs_n_w,
                     ddr_awvalid_w, ddr_wvalid_w, ddr_bready_w,
                     ddr_arvalid_w, ddr_rready_w, debug_w[159:128]);
            $fatal(1, "SoC top-level control output contains X/Z after reset");
        end
        if (rst_n && ddr_awvalid_w &&
            ((^{ddr_awid_w, ddr_awaddr_w, ddr_awlen_w,
                ddr_awsize_w, ddr_awburst_w}) === 1'bx)) begin
            $fatal(1, "SoC DDR AW payload contains X/Z while valid");
        end
        if (rst_n && ddr_wvalid_w &&
            ((^{ddr_wdata_w, ddr_wstrb_w, ddr_wlast_w}) === 1'bx)) begin
            $fatal(1, "SoC DDR W payload contains X/Z while valid");
        end
        if (rst_n && ddr_arvalid_w &&
            ((^{ddr_arid_w, ddr_araddr_w, ddr_arlen_w,
                ddr_arsize_w, ddr_arburst_w}) === 1'bx)) begin
            $fatal(1, "SoC DDR AR payload contains X/Z while valid");
        end
    end

    // ------------------------------------------------------------------
    // Physical UART pin stimulus and decoder for the diagnostics image.
    // The diagnostics build uses 50 MHz / 5 Mbaud, hence 10 clocks/bit.
    // This path is independent of the APB console tap used by old tests.
    // ------------------------------------------------------------------
    localparam integer DIAG_UART_CLKS_PER_BIT = 10;
    localparam [7:0] DIAG_UART_RX_TEST_BYTE = 8'h55;
    reg uart_pin_check_r;
    reg [7:0] uart_pin_buf [0:8191];
    reg [13:0] uart_pin_len_r;
    reg [7:0] uart_pin_shift_r;
    integer uart_pin_count_r;
    integer uart_pin_bit_r;
    reg uart_pin_busy_r;

    initial begin
        uart_pin_len_r = 0;
        uart_pin_shift_r = 0;
        uart_pin_count_r = 0;
        uart_pin_bit_r = 0;
        uart_pin_busy_r = 0;
        uart_pin_check_r = 0;
        if (($test$plusargs("CHECK=diag") != 0) ||
            ($test$plusargs("PIN_UART") != 0))
            uart_pin_check_r = 1;
    end

    reg [31:0] uart_rx_cycle_r;
    reg [3:0] uart_rx_bit_r;
    integer uart_rx_count_r;
    reg uart_rx_active_r;

    always @(posedge clk) begin
        if (!rst_n) begin
            uart0_rx_r <= 1'b1;
            uart_rx_cycle_r <= 0;
            uart_rx_bit_r <= 0;
            uart_rx_count_r <= 0;
            uart_rx_active_r <= 0;
        end else begin
            uart_rx_cycle_r <= uart_rx_cycle_r + 1'b1;
            if (!uart_rx_active_r && uart_rx_cycle_r == 32'd30000) begin
                uart0_rx_r <= 1'b0;
                uart_rx_bit_r <= 0;
                uart_rx_count_r <= DIAG_UART_CLKS_PER_BIT - 1;
                uart_rx_active_r <= 1'b1;
            end else if (uart_rx_active_r && uart_rx_count_r != 0) begin
                uart_rx_count_r <= uart_rx_count_r - 1;
            end else if (uart_rx_active_r && uart_rx_bit_r < 8) begin
                uart0_rx_r <= DIAG_UART_RX_TEST_BYTE[uart_rx_bit_r[2:0]];
                uart_rx_bit_r <= uart_rx_bit_r + 1'b1;
                uart_rx_count_r <= DIAG_UART_CLKS_PER_BIT - 1;
            end else if (uart_rx_active_r && uart_rx_bit_r == 8) begin
                uart0_rx_r <= 1'b1;
                uart_rx_bit_r <= uart_rx_bit_r + 1'b1;
                uart_rx_count_r <= DIAG_UART_CLKS_PER_BIT - 1;
            end else begin
                uart_rx_active_r <= 1'b0;
                uart0_rx_r <= 1'b1;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            uart_pin_len_r <= 0;
            uart_pin_shift_r <= 0;
            uart_pin_count_r <= 0;
            uart_pin_bit_r <= 0;
            uart_pin_busy_r <= 0;
        end else if (!uart_pin_check_r) begin
            uart_pin_busy_r <= 1'b0;
        end else if (!uart_pin_busy_r) begin
            if (!uart0_tx_w) begin
                uart_pin_busy_r <= 1'b1;
                uart_pin_count_r <= DIAG_UART_CLKS_PER_BIT +
                                    (DIAG_UART_CLKS_PER_BIT / 2) - 1;
                uart_pin_bit_r <= 0;
            end
        end else if (uart_pin_count_r != 0) begin
            uart_pin_count_r <= uart_pin_count_r - 1;
        end else if (uart_pin_bit_r < 8) begin
            uart_pin_shift_r[uart_pin_bit_r] <= uart0_tx_w;
            uart_pin_bit_r <= uart_pin_bit_r + 1;
            uart_pin_count_r <= DIAG_UART_CLKS_PER_BIT - 1;
        end else begin
            if (!uart0_tx_w)
                $fatal(1, "UART TX stop bit is low");
            if (uart_pin_len_r < 8192) begin
                uart_pin_buf[uart_pin_len_r[12:0]] <= uart_pin_shift_r;
                uart_pin_len_r <= uart_pin_len_r + 1'b1;
            end
            uart_pin_busy_r <= 1'b0;
        end
    end

    // ------------------------------------------------------------------
    // Console capture: APB writes to UART0 TXDATA (0x4000_0000).
    // ------------------------------------------------------------------
    reg [7:0]  console_buf [0:8191];
    reg [13:0] console_len;
    reg [31:0] perf_vals [0:13];
    integer    pi_i;
    reg [31:0] cycle_r;
    reg        done_r;

    // Liveness guards.  A useful simulation must fail fast with a compact
    // diagnostic instead of filling the log forever after control-flow loss.
    reg [31:0] progress_pc_r;
    reg [31:0] no_progress_cycles_r;
    reg [31:0] watchdog_cycles_r;
    reg [31:0] last_trap_cause_r;
    reg [31:0] last_trap_epc_r;
    reg [31:0] last_trap_tval_r;
    reg [3:0]  repeated_trap_count_r;

    initial begin
        if (!$value$plusargs("WATCHDOG=%d", watchdog_cycles_r))
            watchdog_cycles_r = 32'd100_000;
        stats_en_w = ($test$plusargs("STATS") != 0);
        mmio_trace_en_w = ($test$plusargs("MMIO_TRACE") != 0);
    end

    // AXI protocol guards for the two internal cache masters.  These checks
    // use only channel-level signals and specifically regress the historical
    // bug where an unselected slave's READY falsely accepted an SRAM AR.
    reg        m0_ar_stall_r;
    reg [31:0] m0_araddr_hold_r;
    reg [7:0]  m0_arlen_hold_r;
    reg        m1_ar_stall_r;
    reg [31:0] m1_araddr_hold_r;
    reg [7:0]  m1_arlen_hold_r;
    reg [31:0] read_contention_count_r;
    reg stats_en_w;
    reg mmio_trace_en_w;
    reg [31:0] trace_dmem_addr_r;
    // B1 debug: last committed PC ring (32 entries)
    reg [31:0] pc_ring_r [0:31];
    integer pc_ring_wr_r;
    integer dbg_i;
    // B1 perf-debug: per-window fabric activity counters (absolute since reset)
    reg [31:0] st_m0_ar_r, st_m1_ar_r, st_sram_busy_r, st_sram_rb_r;
    reg [31:0] st_apb_ar_r, st_m0_rb_r, st_m1_rb_r, st_m0_stall_r, st_m1_stall_r;

    wire apb_wr = u_soc.apb_psel_w && u_soc.apb_penable_w && u_soc.apb_pwrite_w;
    wire console_wr = apb_wr && (u_soc.apb_paddr_w == 32'h4000_0000);

    integer ci;
    initial begin
        for (pi_i = 0; pi_i < 14; pi_i = pi_i + 1) perf_vals[pi_i] = 0;
        console_len = 0;
        for (ci = 0; ci < 8192; ci = ci + 1) console_buf[ci] = 8'h0;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m0_ar_stall_r <= 1'b0;
            m0_araddr_hold_r <= 32'h0;
            m0_arlen_hold_r <= 8'h0;
            m1_ar_stall_r <= 1'b0;
            m1_araddr_hold_r <= 32'h0;
            m1_arlen_hold_r <= 8'h0;
            read_contention_count_r <= 32'h0;
        end else begin
            if (m0_ar_stall_r && (!u_soc.m0_arvalid_w
                || (u_soc.m0_araddr_w != m0_araddr_hold_r)
                || (u_soc.m0_arlen_w != m0_arlen_hold_r)))
                $fatal(1, "M0 AR payload changed while stalled");
            if (m1_ar_stall_r && (!u_soc.m1_arvalid_w
                || (u_soc.m1_araddr_w != m1_araddr_hold_r)
                || (u_soc.m1_arlen_w != m1_arlen_hold_r)))
                $fatal(1, "M1 AR payload changed while stalled");

            m0_ar_stall_r <= u_soc.m0_arvalid_w && !u_soc.m0_arready_w;
            m0_araddr_hold_r <= u_soc.m0_araddr_w;
            m0_arlen_hold_r <= u_soc.m0_arlen_w;
            m1_ar_stall_r <= u_soc.m1_arvalid_w && !u_soc.m1_arready_w;
            m1_araddr_hold_r <= u_soc.m1_araddr_w;
            m1_arlen_hold_r <= u_soc.m1_arlen_w;

            // Multi-outstanding fabric: M1 may legally request SRAM while
            // M0 holds the R response; count overlap, do not fail.
            if (u_soc.m1_arvalid_w
                && (u_soc.m1_araddr_w >= 32'h1000_0000)
                && (u_soc.m1_araddr_w < 32'h1004_0000)
                && u_soc.u_axi_interconnect.u_axi_rd_fabric.hold_v_r[0]
                && u_soc.u_axi_interconnect.u_axi_rd_fabric.hold_oh_r[0][1]) begin
                read_contention_count_r <= read_contention_count_r + 32'd1;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_r    <= 0;
            done_r     <= 0;
            pc_ring_wr_r <= 0;
            st_m0_ar_r <= 32'h0;
            st_m1_ar_r <= 32'h0;
            st_sram_busy_r <= 32'h0;
            st_sram_rb_r <= 32'h0;
            st_apb_ar_r <= 32'h0;
            st_m0_rb_r <= 32'h0;
            st_m1_rb_r <= 32'h0;
            st_m0_stall_r <= 32'h0;
            st_m1_stall_r <= 32'h0;
            progress_pc_r <= 32'h0;
            no_progress_cycles_r <= 32'h0;
            last_trap_cause_r <= 32'h0;
            last_trap_epc_r <= 32'h0;
            last_trap_tval_r <= 32'h0;
            repeated_trap_count_r <= 4'h0;
            trace_dmem_addr_r <= 32'h0;
        end else if (!done_r) begin
            cycle_r <= cycle_r + 32'd1;

            // Consecutive retirement-PC stagnation catches a wedged pipeline.
            // Use the current cached-core observation ports rather than the
            // removed u_cw private wrapper used by the old testbench.
            if (u_soc.u_cached_core.retire_o) begin
                pc_ring_r[pc_ring_wr_r] <= u_soc.u_cached_core.retire_pc_o;
                pc_ring_wr_r <= (pc_ring_wr_r == 31) ? 0 : pc_ring_wr_r + 1;
                if (u_soc.u_cached_core.retire_pc_o != progress_pc_r) begin
                    progress_pc_r <= u_soc.u_cached_core.retire_pc_o;
                    no_progress_cycles_r <= 32'h0;
                end else begin
                    no_progress_cycles_r <= no_progress_cycles_r + 32'd1;
                end
            end else begin
                no_progress_cycles_r <= no_progress_cycles_r + 32'd1;
            end

            st_m0_ar_r <= st_m0_ar_r
                          + ((u_soc.m0_arvalid_w && u_soc.m0_arready_w)
                             ? 32'd1 : 32'd0);
            st_m1_ar_r <= st_m1_ar_r
                          + ((u_soc.m1_arvalid_w && u_soc.m1_arready_w)
                             ? 32'd1 : 32'd0);
            st_sram_busy_r <= st_sram_busy_r
                              + (u_soc.u_sram.rd_busy_r ? 32'd1 : 32'd0);
            st_sram_rb_r <= st_sram_rb_r
                            + ((u_soc.u_sram.rvalid_r
                                && u_soc.axi_s_rready_w[1]) ? 32'd1 : 32'd0);
            st_apb_ar_r <= st_apb_ar_r
                           + ((u_soc.axi_s_arvalid_w[4]
                               && u_soc.axi_s_arready_w[4]) ? 32'd1 : 32'd0);
            st_m0_rb_r <= st_m0_rb_r
                          + ((u_soc.m0_rvalid_w && u_soc.m0_rready_w)
                             ? 32'd1 : 32'd0);
            st_m1_rb_r <= st_m1_rb_r
                          + ((u_soc.m1_rvalid_w && u_soc.m1_rready_w)
                             ? 32'd1 : 32'd0);
            st_m0_stall_r <= st_m0_stall_r
                             + ((u_soc.m0_arvalid_w && !u_soc.m0_arready_w)
                                ? 32'd1 : 32'd0);
            st_m1_stall_r <= st_m1_stall_r
                             + ((u_soc.m1_arvalid_w && !u_soc.m1_arready_w)
                                ? 32'd1 : 32'd0);
            if (u_soc.u_cached_core.core_dmem_req_valid_w
                && u_soc.u_cached_core.core_dmem_req_ready_w) begin
                trace_dmem_addr_r <= u_soc.u_cached_core.core_dmem_req_addr_w;
                if (mmio_trace_en_w
                    && (u_soc.u_cached_core.core_dmem_req_addr_w >= 32'h2000_0000)) begin
                    $display("[MMIO-REQ] cyc=%0d addr=%08x we=%b data=%08x strb=%x",
                             cycle_r, u_soc.u_cached_core.core_dmem_req_addr_w,
                             u_soc.u_cached_core.core_dmem_req_write_w,
                             u_soc.u_cached_core.core_dmem_req_wdata_w,
                             u_soc.u_cached_core.core_dmem_req_wstrb_w);
                end
            end
            if (mmio_trace_en_w
                && u_soc.u_cached_core.core_dmem_resp_valid_w
                && u_soc.u_cached_core.core_dmem_resp_ready_w) begin
                $display("[MMIO-RSP] cyc=%0d addr=%08x data=%08x err=%b",
                         cycle_r, trace_dmem_addr_r,
                         u_soc.u_cached_core.core_dmem_resp_data_w,
                         u_soc.u_cached_core.core_dmem_resp_error_w);
            end
            if (no_progress_cycles_r >= watchdog_cycles_r) begin
                done_r <= 1'b1;
                $display("EDRV32_TEST_STUCK soc reason=pc-no-progress cyc=%0d pc=%08x watchdog=%0d",
                         cycle_r, progress_pc_r, watchdog_cycles_r);
                $display("[STUCK] retire=%b retire_pc=%08x dcache_busy=%b dc_state=%0d ar=%b/%b aw=%b/%b w=%b/%b b=%b/%b",
                         u_soc.u_cached_core.retire_o,
                         u_soc.u_cached_core.retire_pc_o,
                         u_soc.u_cached_core.dcache_refill_busy_w,
                          u_soc.u_cached_core.u_dcache.state_r,
                         u_soc.m1_arvalid_w, u_soc.m1_arready_w,
                         u_soc.m1_awvalid_w, u_soc.m1_awready_w,
                         u_soc.m1_wvalid_w, u_soc.m1_wready_w,
                         u_soc.m1_bvalid_w, u_soc.m1_bready_w);
                $finish;
            end
            // Trap capture
            if (u_soc.u_cached_core.retire_exception_o && !done_r) begin
                $display("[TRAP] cause=%0d epc=%08x tval=%08x cyc=%0d",
                         u_soc.u_cached_core.retire_cause_o,
                         u_soc.u_cached_core.retire_pc_o,
                         32'h0, cycle_r);
                if ((u_soc.u_cached_core.retire_cause_o == last_trap_cause_r)
                    && (u_soc.u_cached_core.retire_pc_o == last_trap_epc_r)
                    && (last_trap_tval_r == 32'h0)) begin
                    repeated_trap_count_r <= repeated_trap_count_r + 4'd1;
                    if (repeated_trap_count_r == 4'd7) begin
                        done_r <= 1'b1;
                        $display("EDRV32_TEST_STUCK soc reason=repeated-trap cyc=%0d cause=%0d epc=%08x tval=%08x",
                                 cycle_r,
                                 u_soc.u_cached_core.retire_cause_o,
                                 u_soc.u_cached_core.retire_pc_o,
                                 32'h0);
                        $finish;
                    end
                end else begin
                    last_trap_cause_r <= u_soc.u_cached_core.retire_cause_o;
                    last_trap_epc_r <= u_soc.u_cached_core.retire_pc_o;
                    last_trap_tval_r <= 32'h0;
                    repeated_trap_count_r <= 4'd1;
                end
            end

            // First-response diagnostics for write faults.  This is compact
            // enough to retain in every regression log and exposes stale W
            // payloads captured by an unselected slave.
            if (u_soc.m1_bvalid_w && (u_soc.m1_bresp_w != 2'b00))
                $display("[AXI-WERR] cyc=%0d awaddr=%08x dc_state=%0d apb_state=%0d apb_w_hold=%b apb_w_last=%b apb_bresp=%b err_b=%b",
                         cycle_r, u_soc.m1_awaddr_w,
                          u_soc.u_cached_core.u_dcache.state_r,
                         u_soc.u_a2p.state_r,
                         u_soc.u_a2p.w_hold_r,
                         u_soc.u_a2p.w_last_r,
                         u_soc.apb_bresp_w,
                         u_soc.u_axi_interconnect.u_axi_wr_fabric.errw_active_r[1]);
            // Heartbeat + full interconnect state snapshot.
            if (cycle_r % 32'd200000 == 32'd199999) begin
                $display("[HB] cyc=%0d pc=%08x", cycle_r,
                         u_soc.u_cached_core.retire_pc_o);
                if (stats_en_w) begin
                    for (dbg_i = 0; dbg_i < 32; dbg_i = dbg_i + 1)
                        $display("[PC%0d] %08x", dbg_i,
                                 pc_ring_r[(pc_ring_wr_r + dbg_i) & 32'd31]);
                    $display("[STAT] m0ar=%0d m1ar=%0d srambusy=%0d sramrb=%0d apbar=%0d m0rb=%0d m1rb=%0d m0stall=%0d m1stall=%0d",
                             st_m0_ar_r, st_m1_ar_r, st_sram_busy_r, st_sram_rb_r,
                             st_apb_ar_r, st_m0_rb_r, st_m1_rb_r, st_m0_stall_r, st_m1_stall_r);
                end
                $display("[SNAP] dc st=%0d rbeat=%0d wbeat=%0d awp=%b wdone=%b | ic st=%0d | sram rd=%0d wr=%0d rv=%0d bv=%0d | m1 araddr=%08x ar=%b/%b aw=%b/%b w=%b/%b/%b b=%b/%b | err_r=%b/%b/%b",
                          u_soc.u_cached_core.u_dcache.state_r,
                          u_soc.u_cached_core.u_dcache.refill_beat_r,
                          u_soc.u_cached_core.u_dcache.write_beat_r,
                          u_soc.u_cached_core.u_dcache.write_aw_pending_r,
                          u_soc.u_cached_core.u_dcache.write_w_done_r,
                          u_soc.u_cached_core.u_icache.state_r,
                         u_soc.u_sram.rd_busy_r,
                         u_soc.u_sram.wr_busy_r,
                         u_soc.u_sram.rvalid_r,
                         u_soc.u_sram.bvalid_r,
                         u_soc.m1_araddr_w,
                         u_soc.m1_arvalid_w, u_soc.m1_arready_w,
                         u_soc.m1_awvalid_w, u_soc.m1_awready_w,
                         u_soc.m1_wvalid_w, u_soc.m1_wready_w, u_soc.m1_wlast_w,
                         u_soc.m1_bvalid_w, u_soc.m1_bready_w,
                         u_soc.u_axi_interconnect.u_axi_rd_fabric.err_busy_r[0],
                         u_soc.u_axi_interconnect.u_axi_rd_fabric.err_busy_r[1],
                         u_soc.u_axi_interconnect.u_axi_wr_fabric.errw_active_r[1]);
            end
            if (console_wr && console_len < 14'd8192) begin
                console_buf[console_len[12:0]] <= u_soc.apb_pwdata_w[7:0];
                console_len <= console_len + 14'd1;
            end

            // Perf counter result-block capture: 0x80002010 + 4*n (n=0..13)
            if (u_soc.u_cached_core.core_dmem_req_valid_w
                && u_soc.u_cached_core.core_dmem_req_ready_w
                && u_soc.u_cached_core.core_dmem_req_write_w
                && u_soc.u_cached_core.core_dmem_req_addr_w >= result_base_w + 32'h10
                && u_soc.u_cached_core.core_dmem_req_addr_w < result_base_w + 32'h48)
                perf_vals[(u_soc.u_cached_core.core_dmem_req_addr_w
                           - result_base_w - 32'h10) >> 2]
                    <= u_soc.u_cached_core.core_dmem_req_wdata_w;

            if (cycle_r == 32'd600_000_000) begin
                done_r <= 1'b1;
                $display("EDRV32_TEST_TIMEOUT soc");
                $finish;
            end
        end
    end

    // ------------------------------------------------------------------
    // Completion detection: the benchmark's exit store targets TOHOST
    // (0x8000_1000) which is unmapped in this SoC — the store completes
    // with DECERR and the core takes a store-access-fault trap (correct
    // architecture behaviour).  The TB observes the exit write at the
    // D-cache adapter input (always visible, one fire per store) and then
    // dumps/evaluates the console before the trap loop.
    // ------------------------------------------------------------------
    // The current cached-core contract exposes the precise request before it
    // is routed to D$, TCM or the external fabric.  The old private wrapper
    // probe was removed instead of being recreated.
    wire exit_wr = u_soc.u_cached_core.core_dmem_req_valid_w
                   && u_soc.u_cached_core.core_dmem_req_ready_w
                   && u_soc.u_cached_core.core_dmem_req_write_w
                   && (u_soc.u_cached_core.core_dmem_req_addr_w
                       == 32'h8000_1000);

    integer k;
    reg found_pass_r, found_fail_r;
    initial begin
        found_pass_r = 0;
        found_fail_r = 0;
    end
    // Console pass-marker: CoreMark default ("validated"), or +CHECK=hello
    // for the bring-up program ("SoC OK").
    reg        check_hello_r;
    reg        check_diag_r;
    initial begin
        check_hello_r = 0;
        check_diag_r = 0;
        if ($test$plusargs("CHECK=hello") != 0)
            check_hello_r = 1;
        if ($test$plusargs("CHECK=diag") != 0)
            check_diag_r = 1;
    end

    // Result block base (CoreMark/cpi extension area): default is the
    // cache-level TB address; the SoC image links it into SRAM.
    reg  [31:0] result_base_w;
    initial begin
        if (!$value$plusargs("RESULT=%h", result_base_w))
            result_base_w = 32'h80002000;
    end

    // Scan the captured console for the self-checking markers on exit.
    /* verilator lint_off BLKSEQ */
    always @(posedge clk) begin
        if (exit_wr && !done_r) begin
            found_pass_r = 0;
            found_fail_r = 0;
            for (k = 0; k < console_len; k = k + 1) begin
                if (console_buf[k+22] == "C" && console_buf[k+23] == "o"
                    && console_buf[k+24] == "r" && console_buf[k+25] == "r"
                    && console_buf[k+26] == "e" && console_buf[k+27] == "c"
                    && console_buf[k+28] == "t" && console_buf[k+29] == " ")
                    found_pass_r = 1;
                if (console_buf[k] == "E" && console_buf[k+1] == "r"
                    && console_buf[k+2] == "r" && console_buf[k+3] == "o"
                    && console_buf[k+4] == "r" && console_buf[k+5] == "s")
                    found_fail_r = 1;
            end
            $write("--- console (%0d bytes) ---\n", console_len);
            for (k = 0; k < console_len; k = k + 1)
                $write("%c", console_buf[k]);
            $write("\n--- end ---\n");
            if (check_hello_r) begin
                // hello: look for "SoC OK"
                found_pass_r = 0;
                for (k = 0; k + 5 < console_len; k = k + 1)
                    if (console_buf[k] == "S" && console_buf[k+1] == "o"
                        && console_buf[k+2] == "C" && console_buf[k+3] == " "
                        && console_buf[k+4] == "O" && console_buf[k+5] == "K")
                        found_pass_r = 1;
            end else if (check_diag_r) begin
                found_pass_r = 0;
                for (k = 0; k + 21 < console_len; k = k + 1)
                    if (console_buf[k] == "E" && console_buf[k+1] == "D"
                        && console_buf[k+2] == "R" && console_buf[k+3] == "V"
                        && console_buf[k+4] == "3" && console_buf[k+5] == "2"
                        && console_buf[k+6] == "_" && console_buf[k+7] == "B"
                        && console_buf[k+8] == "O" && console_buf[k+9] == "A"
                        && console_buf[k+10] == "R" && console_buf[k+11] == "D"
                        && console_buf[k+12] == "_" && console_buf[k+13] == "D"
                        && console_buf[k+14] == "I" && console_buf[k+15] == "A"
                        && console_buf[k+16] == "G" && console_buf[k+17] == "_"
                        && console_buf[k+18] == "P" && console_buf[k+19] == "A"
                        && console_buf[k+20] == "S" && console_buf[k+21] == "S")
                        found_pass_r = 1;
                if (!spi_flash_command_seen_w || spi_flash_protocol_error_w) begin
                    $display("SPI flash pin protocol failed command=%b error=%b",
                             spi_flash_command_seen_w,
                             spi_flash_protocol_error_w);
                    found_fail_r = 1;
                end
                if (unused_gpio_oe_w != 16'h00ff ||
                    unused_gpio_out_w[7:0] != 8'h59) begin
                    $display("GPIO pin mismatch oe=%04x out=%04x",
                             unused_gpio_oe_w, unused_gpio_out_w);
                    found_fail_r = 1;
                end
            end
            if (uart_pin_check_r) begin
                if (uart_pin_len_r != console_len) begin
                    $display("UART pin/APB length mismatch pin=%0d apb=%0d",
                             uart_pin_len_r, console_len);
                    found_fail_r = 1;
                end
                for (k = 0; k < uart_pin_len_r; k = k + 1)
                    if (uart_pin_buf[k] != console_buf[k]) begin
                        $display("UART pin byte mismatch index=%0d pin=%02x apb=%02x",
                                 k, uart_pin_buf[k], console_buf[k]);
                        found_fail_r = 1;
                    end
            end
            if (found_pass_r && !found_fail_r)
                $display("EDRV32_TEST_PASS soc");
            else
                $display("EDRV32_TEST_FAIL soc pass=%b fail=%b", found_pass_r, found_fail_r);
            $display("PERF branch=%0d misp=%0d luse=%0d iss=%0d ifstall=%0d memstall=%0d icmiss=%0d dcmiss=%0d dwb=%0d icwait=%0d dcwait=%0d exc=%0d irq=%0d ecall=%0d",
                     perf_vals[0], perf_vals[1], perf_vals[2], perf_vals[3],
                     perf_vals[4], perf_vals[5], perf_vals[6], perf_vals[7],
                     perf_vals[8], perf_vals[9], perf_vals[10],
                     perf_vals[11], perf_vals[12], perf_vals[13]);
            $display("AXI read_contention_cycles=%0d", read_contention_count_r);
            $finish;
        end
    end
    /* verilator lint_on BLKSEQ */

endmodule
