`include "edrv32_axi4.vh"
`include "edrv32_uop.vh"
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
    parameter AXI_MON_ENABLE = 1,
    parameter FRONTEND_DUAL_WINDOW = 0,
    parameter DUAL_ISSUE = 0,
    parameter FETCH_WIDE = 0
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
        .RESET_PC       (32'h0000_0000),
        .CPU_HPM_ENABLE (CPU_HPM_ENABLE),
        .CPU_FRONTEND_DUAL_WINDOW(FRONTEND_DUAL_WINDOW),
        .CPU_DUAL_ISSUE(DUAL_ISSUE),
        .CPU_FETCH_WIDE(FETCH_WIDE),
        .AXI_MON_ENABLE (AXI_MON_ENABLE),
        .DDR_ENABLE     (0)
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
    reg profile_active_r = 1'b0;
    integer profile_load_r = 0;
    integer profile_store_r = 0;
    integer profile_ready_base_r = 0;
    integer profile_resident_base_r = 0;
    integer profile_late_load_base_r = 0;
    integer profile_blocked_base_r = 0;
    integer profile_mem_stall_r = 0;
    integer profile_load_alloc_r = 0;
    integer profile_store_alloc_r = 0;
    integer profile_load_issue_r = 0;

    always @(posedge clk) begin
        if (rst_n && console_wr &&
            {round_end_shift_r[63:0], u_soc.apb_pwdata_w[7:0]} ==
                "ROUND 1/3")
            profile_active_r <= 1'b1;
        if (rst_n && profile_active_r) begin
            if (u_soc.u_cached_core.u_core.u_decode_stage.valid_i &&
                ((u_soc.u_cached_core.u_core.u_decode_stage.dec_op_class_w == 4'd4) ||
                 (u_soc.u_cached_core.u_core.u_decode_stage.dec_op_class_w == 4'd5)) &&
                u_soc.u_cached_core.u_core.u_decode_stage.dependency_stall_o)
                profile_mem_stall_r <= profile_mem_stall_r + 1;
            if (u_soc.u_cached_core.u_core.u_decode_stage.pipe_capture_w &&
                !u_soc.u_cached_core.u_core.u_decode_stage.boundary_kill_i &&
                ((u_soc.u_cached_core.u_core.u_decode_stage.dec_op_class_w == 4'd4) ||
                 (u_soc.u_cached_core.u_core.u_decode_stage.dec_op_class_w == 4'd5))) begin
                if (u_soc.u_cached_core.u_core.u_decode_stage.dec_op_class_w == 4'd4)
                    profile_load_r <= profile_load_r + 1;
                else
                    profile_store_r <= profile_store_r + 1;
                if (u_soc.u_cached_core.u_core.u_decode_stage.resident_bypass_rs1_w)
                    profile_resident_base_r <= profile_resident_base_r + 1;
                else if (u_soc.u_cached_core.u_core.u_decode_stage.rs1_late_load_w)
                    profile_late_load_base_r <= profile_late_load_base_r + 1;
                else if (u_soc.u_cached_core.u_core.u_decode_stage.rs1_blocked_w)
                    profile_blocked_base_r <= profile_blocked_base_r + 1;
                else
                    profile_ready_base_r <= profile_ready_base_r + 1;
            end
            if (u_soc.u_cached_core.u_core.load_alloc_fire_w)
                profile_load_alloc_r <= profile_load_alloc_r + 1;
            if (u_soc.u_cached_core.u_core.store_alloc_fire_w)
                profile_store_alloc_r <= profile_store_alloc_r + 1;
            if (u_soc.u_cached_core.u_core.load_request_valid_w &&
                u_soc.u_cached_core.u_core.load_request_ready_w)
                profile_load_issue_r <= profile_load_issue_r + 1;
        end
    end

    reg [31:0] cycle_r;
    reg        done_r;
    reg [71:0] round_end_shift_r;
    integer round_print_i;
    reg        stats_en_w;
    reg        mmio_trace_en_w;
    reg [31:0] result_base_w;

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
        round_end_shift_r = 72'd0;
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
            if (stats_en_w && cycle_r % 32'd1000 == 32'd999) begin
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
                round_end_shift_r <= {round_end_shift_r[63:0],
                                      u_soc.apb_pwdata_w[7:0]};
                if ($test$plusargs("STOP_FIRST_ROUND") &&
                    {round_end_shift_r[63:0], u_soc.apb_pwdata_w[7:0]}
                        == "ROUND_END") begin
                    $display("EARLY_ADDR_PROFILE load=%0d store=%0d ready_base=%0d resident_base=%0d late_load_base=%0d blocked_base=%0d mem_stall_cycles=%0d load_alloc=%0d store_alloc=%0d load_issue=%0d",
                        profile_load_r, profile_store_r, profile_ready_base_r,
                        profile_resident_base_r, profile_late_load_base_r,
                        profile_blocked_base_r, profile_mem_stall_r,
                        profile_load_alloc_r, profile_store_alloc_r,
                        profile_load_issue_r);
                    $display("FIRST_ROUND_COMPLETE cycle=%0d", cycle_r);
                    for (round_print_i = 0; round_print_i < console_len;
                         round_print_i = round_print_i + 1)
                        $write("%c", console_buf[round_print_i]);
                    $write("%c\n", u_soc.apb_pwdata_w[7:0]);
                    $finish;
                end
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


`define C u_soc.u_cached_core.u_core
reg [151:0] analysis_console_shift_r = 0;
reg analysis_prepared_r = 0;
reg analysis_active_r = 0;
integer analysis_round_r = 0;
integer analysis_idx;
integer analysis_bucket;
integer analysis_collision_r = 0;
reg [31:0] analysis_pc;
reg [31:0] analysis_pc_tag_r [0:16383];
reg analysis_pc_valid_r [0:16383];
reg [63:0] analysis_pc_wait_r [0:16383];
reg [63:0] analysis_pc_waw_r [0:16383];
reg [63:0] analysis_pc_waw_done_r [0:16383];
reg [63:0] analysis_pc_exload_r [0:16383];
initial begin
    for (analysis_idx=0; analysis_idx<16384; analysis_idx=analysis_idx+1) begin
        analysis_pc_valid_r[analysis_idx]=0;
        analysis_pc_wait_r[analysis_idx]=0;
        analysis_pc_waw_r[analysis_idx]=0;
        analysis_pc_waw_done_r[analysis_idx]=0;
        analysis_pc_exload_r[analysis_idx]=0;
    end
end
reg [63:0] analysis_cycles_r = 0;
reg [63:0] analysis_retire_r = 0;
reg [63:0] analysis_pair_retired_r=0;
reg [63:0] analysis_a_accepted_r=0;
reg [63:0] analysis_pair_issued_r=0;
reg [63:0] analysis_b_lhs_parent_a_r=0;
reg [63:0] analysis_b_rhs_parent_a_r=0;
reg [63:0] analysis_b_lhs_parent_b_r=0;
reg [63:0] analysis_b_rhs_parent_b_r=0;
// Class-independent candidate audit: these counters also run before memory
// pairing is enabled, so the opportunity is measured on the frozen baseline.
reg [63:0] analysis_mem_alu_r=0;
reg [63:0] analysis_mem_alu_ready_r=0;
reg [63:0] analysis_mem_alu_raw_r=0;
reg [63:0] analysis_mem_alu_wait_r=0;
reg [63:0] analysis_load_pairs_r=0;
reg [63:0] analysis_store_pairs_r=0;
reg [63:0] analysis_fe_other_r=0;
reg [63:0] analysis_fe_other_ex_r=0;
reg [63:0] analysis_fe_other_decode_r=0;
reg [63:0] analysis_fe_other_align_r=0;
reg [63:0] analysis_fe_other_empty_r=0;
reg [63:0] analysis_class_r[0:6];
integer analysis_class_index;
initial for (analysis_class_index=0;analysis_class_index<7;analysis_class_index=analysis_class_index+1)
    analysis_class_r[analysis_class_index]=0;
reg [63:0] analysis_a_resident_second_wait_r=0;
reg [63:0] analysis_b_absent_r=0;
reg [63:0] analysis_b_class_r=0;
reg [63:0] analysis_b_group_raw_r=0;
reg [63:0] analysis_b_group_waw_r=0;
reg [63:0] analysis_b_older_unready_r=0;
reg [63:0] analysis_b_resident_raw_r=0;
reg [63:0] analysis_b_metadata_r=0;
reg [63:0] analysis_dependency_r = 0;
reg [63:0] analysis_mdu_raw_unready_r = 0;
reg [63:0] analysis_mdu_raw_decode_unready_r = 0;
reg [63:0] analysis_mdu_raw_ex_unready_r = 0;
reg [63:0] analysis_mdu_waw_r = 0;
reg [63:0] analysis_mdu_waw_complete_r = 0;
reg [63:0] analysis_mdu_waw_complete_no_raw_r = 0;
reg [63:0] analysis_mdu_waw_complete_unauthorized_r = 0;
reg [63:0] analysis_mdu_waw_complete_authorized_r = 0;
reg [63:0] analysis_mdu_wb_port_wait_r = 0;
reg [63:0] analysis_commit_mdu_wait_r = 0;
reg [63:0] analysis_commit_csr_wait_r = 0;
reg [63:0] analysis_ex_load_branch_zero_r = 0;
reg [63:0] analysis_ex_load_branch_general_r = 0;
reg [63:0] analysis_ex_load_jalr_r = 0;
reg [63:0] analysis_ex_load_memory_r = 0;
reg [63:0] analysis_ex_load_alu_r = 0;
reg [63:0] analysis_decode_load_memory_base_r = 0;
reg [63:0] analysis_decode_load_store_data_r = 0;
reg [63:0] analysis_resident_load_r = 0;
reg [63:0] analysis_resident_mdu_r = 0;
always @(posedge clk) begin
    if (rst_n && console_wr) begin
        $write("%c",u_soc.apb_pwdata_w[7:0]);
        analysis_console_shift_r = {analysis_console_shift_r[143:0],u_soc.apb_pwdata_w[7:0]};
        if (analysis_console_shift_r == "ALL_ROUNDS_COMPLETE") begin
            $display("\nSIM_ALL_ROUNDS_COMPLETE");
            $finish;
        end
    end
    if (rst_n && `C.u_commit_stage.u_csr_file.mcountinhibit_r[3])
        analysis_prepared_r = 1;
    if (rst_n && analysis_prepared_r && !`C.u_commit_stage.u_csr_file.mcountinhibit_r[3]) begin
        if (!analysis_active_r) begin
            analysis_active_r=1;
            analysis_round_r=analysis_round_r+1;
        end
        if(`C.second_retire_o)analysis_pair_retired_r=analysis_pair_retired_r+1;
        if (`C.retire_o) begin
            // Canonical retired opcode independently checks the RTL HPM class.
            case (`C.retire_instr_o[6:0])
                7'h03: analysis_class_index=0;
                7'h23: analysis_class_index=1;
                7'h63: analysis_class_index=2;
                7'h67,7'h6f: analysis_class_index=3;
                7'h33: analysis_class_index=(`C.retire_instr_o[31:25]==7'd1)?4:5;
                7'h13,7'h17,7'h37: analysis_class_index=5;
                default: analysis_class_index=6;
            endcase
            if (!`C.hpm_events_w[25+analysis_class_index] && analysis_class_index!=6)
                $fatal(1,"Retired HPM/opcode mismatch pc=%08x instr=%08x class=%0d",
                    `C.retire_pc_o,`C.retire_instr_o,analysis_class_index);
            analysis_class_r[analysis_class_index]=analysis_class_r[analysis_class_index]+1;
            if (`C.second_retire_o) begin
                if (!`C.hpm_second_events_w[30]) $fatal(1,"Missing secondary ALU HPM event");
                analysis_class_r[5]=analysis_class_r[5]+1;
                if (analysis_class_index==0) analysis_load_pairs_r=analysis_load_pairs_r+1;
                if (analysis_class_index==1) analysis_store_pairs_r=analysis_store_pairs_r+1;
            end
        end
        if (`C.hpm_events_w[55]) begin
            analysis_fe_other_r=analysis_fe_other_r+1;
            if (`C.ex_valid_w) analysis_fe_other_ex_r=analysis_fe_other_ex_r+1;
            else if (`C.decode_valid_w) analysis_fe_other_decode_r=analysis_fe_other_decode_r+1;
            else if (`C.align_valid_w) analysis_fe_other_align_r=analysis_fe_other_align_r+1;
            else analysis_fe_other_empty_r=analysis_fe_other_empty_r+1;
        end
        if (`C.align_valid_w && `C.align_accept_w && `C.align_second_valid_w &&
            (`C.u_decode_stage.dec_op_class_w==`EDRV32_OP_LOAD ||
             `C.u_decode_stage.dec_op_class_w==`EDRV32_OP_STORE) &&
            `C.u_decode_stage.second_class_w==`EDRV32_OP_ALU) begin
            analysis_mem_alu_r=analysis_mem_alu_r+1;
            if (`C.u_decode_stage.pair_raw_w || `C.u_decode_stage.pair_waw_w)
                analysis_mem_alu_raw_r=analysis_mem_alu_raw_r+1;
            else if (`C.u_decode_stage.second_operand_blocked_w || `C.u_decode_stage.second_resident_raw_w)
                analysis_mem_alu_wait_r=analysis_mem_alu_wait_r+1;
            else if (!`C.u_decode_stage.exception_valid_w && !`C.align_second_fetch_fault_w &&
                     !`C.align_second_compressed_illegal_w && !`C.u_decode_stage.second_illegal_w &&
                     !`C.align_predicted_taken_w && !`C.align_second_predicted_taken_w &&
                     `C.align_epoch_w==`C.align_second_epoch_w && `C.u_decode_stage.pair_sequential_w)
                analysis_mem_alu_ready_r=analysis_mem_alu_ready_r+1;
        end
        if(`C.align_valid_w && `C.align_accept_w)analysis_a_accepted_r=analysis_a_accepted_r+1;
        if(`C.u_decode_stage.pair_accept_w)analysis_pair_issued_r=analysis_pair_issued_r+1;
        if(`C.u_decode_stage.pair_accept_w)begin
            if(`C.u_decode_stage.second_lhs_source_w==1)analysis_b_lhs_parent_a_r=analysis_b_lhs_parent_a_r+1;
            if(`C.u_decode_stage.second_rhs_source_w==1)analysis_b_rhs_parent_a_r=analysis_b_rhs_parent_a_r+1;
            if(`C.u_decode_stage.second_lhs_source_w==2)analysis_b_lhs_parent_b_r=analysis_b_lhs_parent_b_r+1;
            if(`C.u_decode_stage.second_rhs_source_w==2)analysis_b_rhs_parent_b_r=analysis_b_rhs_parent_b_r+1;
        end
        if(`C.decode_dependency_stall_w && `C.u_decode_stage.primary_resident_second_raw_w)analysis_a_resident_second_wait_r=analysis_a_resident_second_wait_r+1;
        if(DUAL_ISSUE!=0 && `C.align_valid_w && `C.align_accept_w && !`C.u_decode_stage.pair_accept_w)begin
            if(!`C.align_second_valid_w)analysis_b_absent_r=analysis_b_absent_r+1;
            else if((`C.u_decode_stage.dec_op_class_w!=`EDRV32_OP_ALU &&
                     `C.u_decode_stage.dec_op_class_w!=`EDRV32_OP_LOAD &&
                     `C.u_decode_stage.dec_op_class_w!=`EDRV32_OP_STORE) ||
                     `C.u_decode_stage.second_class_w!=`EDRV32_OP_ALU)
                analysis_b_class_r=analysis_b_class_r+1;
            else if(`C.u_decode_stage.pair_raw_w)analysis_b_group_raw_r=analysis_b_group_raw_r+1;
            else if(`C.u_decode_stage.pair_waw_w)analysis_b_group_waw_r=analysis_b_group_waw_r+1;
            else if(`C.u_decode_stage.second_operand_blocked_w)
                analysis_b_older_unready_r=analysis_b_older_unready_r+1;
            else if(`C.u_decode_stage.second_resident_raw_w)analysis_b_resident_raw_r=analysis_b_resident_raw_r+1;
            else analysis_b_metadata_r=analysis_b_metadata_r+1;
        end
        if (1'b1) analysis_cycles_r = analysis_cycles_r + 1;
        if (`C.retire_o) analysis_retire_r = analysis_retire_r + `C.retire_count_o;
        if (`C.decode_dependency_stall_w || `C.ex_late_load_stall_w || `C.ex_late_mdu_stall_w) analysis_dependency_r = analysis_dependency_r + 1;
        if ((`C.decode_dependency_stall_w && `C.mdu_raw_hazard_w && !`C.mdu_result_complete_w) || `C.ex_late_mdu_stall_w) analysis_mdu_raw_unready_r = analysis_mdu_raw_unready_r + 1;
        if (`C.decode_dependency_stall_w && `C.mdu_raw_hazard_w && !`C.mdu_result_complete_w) analysis_mdu_raw_decode_unready_r = analysis_mdu_raw_decode_unready_r + 1;
        if (`C.ex_late_mdu_stall_w) analysis_mdu_raw_ex_unready_r = analysis_mdu_raw_ex_unready_r + 1;
        if (`C.decode_mdu_waw_stall_w) analysis_mdu_waw_r = analysis_mdu_waw_r + 1;
        if (`C.decode_mdu_waw_stall_w && `C.mdu_result_complete_w) analysis_mdu_waw_complete_r = analysis_mdu_waw_complete_r + 1;
        if (`C.decode_mdu_waw_stall_w && `C.mdu_result_complete_w && !`C.mdu_raw_hazard_w) analysis_mdu_waw_complete_no_raw_r = analysis_mdu_waw_complete_no_raw_r + 1;
        if (`C.decode_mdu_waw_stall_w && `C.mdu_result_complete_w && !`C.mdu_authorized_w) analysis_mdu_waw_complete_unauthorized_r = analysis_mdu_waw_complete_unauthorized_r + 1;
        if (`C.decode_mdu_waw_stall_w && `C.mdu_result_complete_w && `C.mdu_authorized_w) analysis_mdu_waw_complete_authorized_r = analysis_mdu_waw_complete_authorized_r + 1;
        if (`C.mdu_result_valid_w && !`C.mdu_result_ready_w) analysis_mdu_wb_port_wait_r = analysis_mdu_wb_port_wait_r + 1;
        if (`C.u_commit_stage.valid_i && !`C.u_commit_stage.ready_o && !`C.u_commit_stage.hpm_busy_memory_o && `C.u_commit_stage.authorized_mdu_wait_w) analysis_commit_mdu_wait_r = analysis_commit_mdu_wait_r + 1;
        if (`C.u_commit_stage.valid_i && !`C.u_commit_stage.csr_control_ready_w) analysis_commit_csr_wait_r = analysis_commit_csr_wait_r + 1;
        if (`C.ex_late_load_stall_w && `C.u_ex_stage.is_branch_w && (`C.decode_instr_w[24:20] == 0)) analysis_ex_load_branch_zero_r = analysis_ex_load_branch_zero_r + 1;
        if (`C.ex_late_load_stall_w && `C.u_ex_stage.is_branch_w && (`C.decode_instr_w[24:20] != 0)) analysis_ex_load_branch_general_r = analysis_ex_load_branch_general_r + 1;
        if (`C.ex_late_load_stall_w && `C.u_ex_stage.is_jalr_w) analysis_ex_load_jalr_r = analysis_ex_load_jalr_r + 1;
        if (`C.ex_late_load_stall_w && (`C.u_ex_stage.is_load_w || `C.u_ex_stage.is_store_w)) analysis_ex_load_memory_r = analysis_ex_load_memory_r + 1;
        if (`C.ex_late_load_stall_w && (`C.decode_op_class_w == 1)) analysis_ex_load_alu_r = analysis_ex_load_alu_r + 1;
        if (`C.decode_dependency_stall_w && (`C.u_decode_stage.dec_op_class_w == 4 || `C.u_decode_stage.dec_op_class_w == 5) && `C.decode_rs1_waits_for_load_w) analysis_decode_load_memory_base_r = analysis_decode_load_memory_base_r + 1;
        if (`C.decode_dependency_stall_w && (`C.u_decode_stage.dec_op_class_w == 5) && `C.decode_rs2_waits_for_load_w) analysis_decode_load_store_data_r = analysis_decode_load_store_data_r + 1;
        if (`C.decode_hpm_stall_resident_w && (`C.decode_op_class_w == 4)) analysis_resident_load_r = analysis_resident_load_r + 1;
        if (`C.decode_hpm_stall_resident_w && (`C.decode_op_class_w == 8)) analysis_resident_mdu_r = analysis_resident_mdu_r + 1;

        if (`C.decode_dependency_stall_w || `C.ex_late_load_stall_w || `C.ex_late_mdu_stall_w) begin
            analysis_pc = `C.decode_dependency_stall_w ? `C.align_pc_w : `C.decode_pc_w;
            analysis_bucket = analysis_pc[14:1];
            if (!analysis_pc_valid_r[analysis_bucket]) begin
                analysis_pc_valid_r[analysis_bucket]=1;
                analysis_pc_tag_r[analysis_bucket]=analysis_pc;
            end
            if (analysis_pc_tag_r[analysis_bucket] == analysis_pc) begin
                analysis_pc_wait_r[analysis_bucket]=analysis_pc_wait_r[analysis_bucket]+1;
                if (`C.decode_mdu_waw_stall_w)
                    analysis_pc_waw_r[analysis_bucket]=analysis_pc_waw_r[analysis_bucket]+1;
                if (`C.decode_mdu_waw_stall_w && `C.mdu_result_complete_w)
                    analysis_pc_waw_done_r[analysis_bucket]=analysis_pc_waw_done_r[analysis_bucket]+1;
                if (`C.ex_late_load_stall_w && !`C.decode_dependency_stall_w)
                    analysis_pc_exload_r[analysis_bucket]=analysis_pc_exload_r[analysis_bucket]+1;
            end else analysis_collision_r=analysis_collision_r+1;
        end
    end else if (analysis_active_r) begin
        $display("\nSIM_B_RESIDENT round=%0d lhs_A=%0d rhs_A=%0d lhs_B=%0d rhs_B=%0d",
            analysis_round_r,analysis_b_lhs_parent_a_r,analysis_b_rhs_parent_a_r,
            analysis_b_lhs_parent_b_r,analysis_b_rhs_parent_b_r);
        analysis_b_lhs_parent_a_r=0;analysis_b_rhs_parent_a_r=0;
        analysis_b_lhs_parent_b_r=0;analysis_b_rhs_parent_b_r=0;
        $display("\nSIM_MEM_PAIR round=%0d candidates=%0d ready=%0d raw_waw=%0d older_wait=%0d load_retired=%0d store_retired=%0d",
            analysis_round_r,analysis_mem_alu_r,analysis_mem_alu_ready_r,analysis_mem_alu_raw_r,
            analysis_mem_alu_wait_r,analysis_load_pairs_r,analysis_store_pairs_r);
        $display("SIM_FE_OTHER round=%0d total=%0d ex=%0d decode=%0d align=%0d empty=%0d",
            analysis_round_r,analysis_fe_other_r,analysis_fe_other_ex_r,analysis_fe_other_decode_r,
            analysis_fe_other_align_r,analysis_fe_other_empty_r);
        $display("SIM_RETIRED_CLASS round=%0d load=%0d store=%0d branch=%0d jump=%0d mdu=%0d alu=%0d other=%0d",
            analysis_round_r,analysis_class_r[0],analysis_class_r[1],analysis_class_r[2],
            analysis_class_r[3],analysis_class_r[4],analysis_class_r[5],analysis_class_r[6]);
        analysis_mem_alu_r=0;analysis_mem_alu_ready_r=0;analysis_mem_alu_raw_r=0;analysis_mem_alu_wait_r=0;
        analysis_load_pairs_r=0;analysis_store_pairs_r=0;
        analysis_fe_other_r=0;analysis_fe_other_ex_r=0;analysis_fe_other_decode_r=0;
        analysis_fe_other_align_r=0;analysis_fe_other_empty_r=0;
        for (analysis_class_index=0;analysis_class_index<7;analysis_class_index=analysis_class_index+1)
            analysis_class_r[analysis_class_index]=0;
        $write("\nSIM_PROFILE round=%0d",analysis_round_r);
        $write(" cycles=%0d",analysis_cycles_r);
        $write(" retire=%0d",analysis_retire_r);
        $write(" pair_retired=%0d",analysis_pair_retired_r);
        $write(" a_accepted=%0d",analysis_a_accepted_r);
        $write(" pair_issued=%0d",analysis_pair_issued_r);
        $write(" a_resident_second_wait=%0d",analysis_a_resident_second_wait_r);
        $write(" b_absent=%0d",analysis_b_absent_r);
        $write(" b_class=%0d",analysis_b_class_r);
        $write(" b_group_raw=%0d",analysis_b_group_raw_r);
        $write(" b_group_waw=%0d",analysis_b_group_waw_r);
        $write(" b_older_unready=%0d",analysis_b_older_unready_r);
        $write(" b_resident_raw=%0d",analysis_b_resident_raw_r);
        $write(" b_metadata=%0d",analysis_b_metadata_r);
        $write(" dependency=%0d",analysis_dependency_r);
        $write(" mdu_raw_unready=%0d",analysis_mdu_raw_unready_r);
        $write(" mdu_raw_decode_unready=%0d",analysis_mdu_raw_decode_unready_r);
        $write(" mdu_raw_ex_unready=%0d",analysis_mdu_raw_ex_unready_r);
        $write(" mdu_waw=%0d",analysis_mdu_waw_r);
        $write(" mdu_waw_complete=%0d",analysis_mdu_waw_complete_r);
        $write(" mdu_waw_complete_no_raw=%0d",analysis_mdu_waw_complete_no_raw_r);
        $write(" mdu_waw_complete_unauthorized=%0d",analysis_mdu_waw_complete_unauthorized_r);
        $write(" mdu_waw_complete_authorized=%0d",analysis_mdu_waw_complete_authorized_r);
        $write(" mdu_wb_port_wait=%0d",analysis_mdu_wb_port_wait_r);
        $write(" commit_mdu_wait=%0d",analysis_commit_mdu_wait_r);
        $write(" commit_csr_wait=%0d",analysis_commit_csr_wait_r);
        $write(" ex_load_branch_zero=%0d",analysis_ex_load_branch_zero_r);
        $write(" ex_load_branch_general=%0d",analysis_ex_load_branch_general_r);
        $write(" ex_load_jalr=%0d",analysis_ex_load_jalr_r);
        $write(" ex_load_memory=%0d",analysis_ex_load_memory_r);
        $write(" ex_load_alu=%0d",analysis_ex_load_alu_r);
        $write(" decode_load_memory_base=%0d",analysis_decode_load_memory_base_r);
        $write(" decode_load_store_data=%0d",analysis_decode_load_store_data_r);
        $write(" resident_load=%0d",analysis_resident_load_r);
        $write(" resident_mdu=%0d",analysis_resident_mdu_r);

        $display(" pc_collision_cycles=%0d",analysis_collision_r);
        for (analysis_idx=0; analysis_idx<16384; analysis_idx=analysis_idx+1) begin
            if (analysis_pc_valid_r[analysis_idx])
                $display("SIM_PC round=%0d pc=%08x wait=%0d waw=%0d waw_done=%0d ex_load=%0d",analysis_round_r,analysis_pc_tag_r[analysis_idx],analysis_pc_wait_r[analysis_idx],analysis_pc_waw_r[analysis_idx],analysis_pc_waw_done_r[analysis_idx],analysis_pc_exload_r[analysis_idx]);
            analysis_pc_valid_r[analysis_idx]=0;
            analysis_pc_wait_r[analysis_idx]=0;
            analysis_pc_waw_r[analysis_idx]=0;
            analysis_pc_waw_done_r[analysis_idx]=0;
            analysis_pc_exload_r[analysis_idx]=0;
        end
        analysis_active_r=0;
        analysis_collision_r=0;
        analysis_cycles_r=0;
        analysis_retire_r=0;
        analysis_pair_retired_r=0;
        analysis_a_accepted_r=0;
        analysis_pair_issued_r=0;
        analysis_a_resident_second_wait_r=0;
        analysis_b_absent_r=0;
        analysis_b_class_r=0;
        analysis_b_group_raw_r=0;
        analysis_b_group_waw_r=0;
        analysis_b_older_unready_r=0;
        analysis_b_resident_raw_r=0;
        analysis_b_metadata_r=0;
        analysis_dependency_r=0;
        analysis_mdu_raw_unready_r=0;
        analysis_mdu_raw_decode_unready_r=0;
        analysis_mdu_raw_ex_unready_r=0;
        analysis_mdu_waw_r=0;
        analysis_mdu_waw_complete_r=0;
        analysis_mdu_waw_complete_no_raw_r=0;
        analysis_mdu_waw_complete_unauthorized_r=0;
        analysis_mdu_waw_complete_authorized_r=0;
        analysis_mdu_wb_port_wait_r=0;
        analysis_commit_mdu_wait_r=0;
        analysis_commit_csr_wait_r=0;
        analysis_ex_load_branch_zero_r=0;
        analysis_ex_load_branch_general_r=0;
        analysis_ex_load_jalr_r=0;
        analysis_ex_load_memory_r=0;
        analysis_ex_load_alu_r=0;
        analysis_decode_load_memory_base_r=0;
        analysis_decode_load_store_data_r=0;
        analysis_resident_load_r=0;
        analysis_resident_mdu_r=0;
    end
end
`undef C
endmodule
