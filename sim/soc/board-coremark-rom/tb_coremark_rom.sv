// ============================================================================
// File        : tb_coremark_rom.sv
// Author      : Edward ZC
// Description : Pin-UART verification of BootROM and optional CoreMark images.
// Notes       : BOOT_ONLY checks that BootROM reaches the cached SRAM menu.
// ============================================================================
module tb_coremark_rom (
    input wire clk,
    input wire rst_n
);
    localparam integer CLKS_PER_BIT = 868;
    localparam integer MAX_CYCLES = 20000000;

    wire uart_tx_w;
    reg uart_rx_r;
    wire [15:0] unused_gpio_out_w;
    wire [15:0] unused_gpio_oe_w;
    wire [3:0] unused_spi_io_w;
    wire [3:0] unused_spi_io_oe_w;
    wire unused_spi_sclk_w;
    wire [3:0] unused_spi_cs_n_w;
    wire [255:0] unused_debug_w;

    edrv32_soc_top #(
        .RESET_PC       (32'h0000_0000),
        .SRAM_WORDS     (65536),
        .ROM_WORDS      (4096),
        .CPU_HPM_ENABLE (1),
        .TCM_ENABLE     (0),
        .ITCM_ENABLE    (0),
        .DTCM_ENABLE    (0),
        .AXI_MON_ENABLE (0),
        .ROM_INIT_FILE  (""),
        .SRAM_INIT_FILE ("")
    ) u_edrv32_soc_top (
        .clk            (clk),
        .rst_n          (rst_n),
        .ddr_bus_clk_i  (clk),
        .ddr_bus_rst_n_i(rst_n),
        .uart0_tx_o     (uart_tx_w),
        .uart0_rx_i     (uart_rx_r),
        .gpio_in_i      (16'b0),
        .gpio_out_o     (unused_gpio_out_w),
        .gpio_oe_o      (unused_gpio_oe_w),
        .spi_io_i       (4'hf),
        .spi_io_o       (unused_spi_io_w),
        .spi_io_oe_o    (unused_spi_io_oe_w),
        .spi_sclk_o     (unused_spi_sclk_w),
        .spi_cs_n_o     (unused_spi_cs_n_w),
        .platform_irq_i  (28'b0),
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
        .vision_cam0_enable_o(),
        .vision_cam1_enable_o(),
        .vision_cam_cfg_req_toggle_o(),
        .vision_cam_cfg_camera_o(),
        .vision_cam_cfg_read_o(),
        .vision_cam_cfg_reg_addr_o(),
        .vision_cam_cfg_write_data_o(),
        .vision_disp_enable_o(),
        .ddr_awid_o(), .ddr_awaddr_o(), .ddr_awlen_o(),
        .ddr_awsize_o(), .ddr_awburst_o(), .ddr_awqos_o(),
        .ddr_awvalid_o(), .ddr_awready_i(1'b0),
        .ddr_wdata_o(), .ddr_wstrb_o(), .ddr_wlast_o(),
        .ddr_wvalid_o(), .ddr_wready_i(1'b0),
        .ddr_bid_i(4'b0), .ddr_bresp_i(2'b0),
        .ddr_bvalid_i(1'b0), .ddr_bready_o(),
        .ddr_arid_o(), .ddr_araddr_o(), .ddr_arlen_o(),
        .ddr_arsize_o(), .ddr_arburst_o(), .ddr_arqos_o(),
        .ddr_arvalid_o(), .ddr_arready_i(1'b0),
        .ddr_rid_i(4'b0), .ddr_rdata_i(256'b0),
        .ddr_rresp_i(2'b0), .ddr_rlast_i(1'b0),
        .ddr_rvalid_i(1'b0), .ddr_rready_o(),
        .ddr_mon_awid_o(), .ddr_mon_awaddr_o(), .ddr_mon_awlen_o(),
        .ddr_mon_awsize_o(), .ddr_mon_awburst_o(), .ddr_mon_awqos_o(),
        .ddr_mon_awvalid_o(), .ddr_mon_awready_i(1'b0),
        .ddr_mon_wdata_o(), .ddr_mon_wstrb_o(), .ddr_mon_wlast_o(),
        .ddr_mon_wvalid_o(), .ddr_mon_wready_i(1'b0),
        .ddr_mon_bid_i(4'b0), .ddr_mon_bresp_i(2'b0),
        .ddr_mon_bvalid_i(1'b0), .ddr_mon_bready_o(),
        .ddr_mon_arid_o(), .ddr_mon_araddr_o(), .ddr_mon_arlen_o(),
        .ddr_mon_arsize_o(), .ddr_mon_arburst_o(), .ddr_mon_arqos_o(),
        .ddr_mon_arvalid_o(), .ddr_mon_arready_i(1'b0),
        .ddr_mon_rid_i(4'b0), .ddr_mon_rdata_i(256'b0),
        .ddr_mon_rresp_i(2'b0), .ddr_mon_rlast_i(1'b0),
        .ddr_mon_rvalid_i(1'b0), .ddr_mon_rready_o(),
        .debug_o        (unused_debug_w)
    );

    reg [31:0] cycle_r;
    reg [7:0] tx_shift_r;
    integer tx_count_r;
    integer tx_bit_r;
    reg tx_busy_r;
    reg [7:0] tx_buf [0:2047];
    reg [10:0] tx_len_r;
    reg correct_seen_r;
    reg runtime_seen_r;
    reg vision_seen_r;
    reg vision_command_seen_r;
    reg boot_only_r;
    reg vision_menu_r;
    integer scan_i;

    initial begin
        cycle_r = 0;
        tx_shift_r = 0;
        tx_count_r = 0;
        tx_bit_r = 0;
        tx_busy_r = 0;
        tx_len_r = 0;
        correct_seen_r = 0;
        runtime_seen_r = 0;
        vision_seen_r = 0;
        vision_command_seen_r = 0;
        uart_rx_r = 1'b1;
        boot_only_r = $test$plusargs("BOOT_ONLY");
        vision_menu_r = $test$plusargs("VISION_MENU");
        for (scan_i = 0; scan_i < 2048; scan_i = scan_i + 1)
            tx_buf[scan_i] = 0;
    end

    task automatic uart_send_byte;
        input [7:0] value;
        integer bit_index;
        begin
            @(negedge clk);
            uart_rx_r = 1'b0;
            repeat (CLKS_PER_BIT) @(posedge clk);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                uart_rx_r = value[bit_index];
                repeat (CLKS_PER_BIT) @(posedge clk);
            end
            uart_rx_r = 1'b1;
            repeat (CLKS_PER_BIT) @(posedge clk);
        end
    endtask

    initial begin
        wait (vision_menu_r && vision_seen_r);
        repeat (2000) @(posedge clk);
        uart_send_byte("v");
    end

    // r47 debug watchdog: report the pipeline/cache state when retirement
    // stops for a long window (fence cleans legitimately take thousands of
    // cycles, so the threshold is deliberately generous).
    integer last_retire_cycle_r;
    initial last_retire_cycle_r = 0;

    // Event log for the print-based hang analysis: reservation edges, commit
    // kills and redirects are recorded and replayed when the watchdog fires.
    reg prev_resv_r;
    reg prev_lookup_req_r;
    reg [31:0] evt_t   [0:255];
    reg [31:0] evt_a   [0:255];
    reg [127:0] evt_s  [0:255];
    integer evt_head_r;
    integer evt_i;
    integer evt_tail;
    initial begin
        prev_resv_r = 1'b0;
        prev_lookup_req_r = 1'b0;
        evt_head_r = 0;
    end
    always @(posedge clk) begin
        if (!rst_n) begin
            prev_resv_r <= 1'b0;
        end else begin
            if (u_edrv32_soc_top.u_cached_core.u_dcache.store_reservation_valid_w &&
                !prev_resv_r) begin
                evt_t[evt_head_r] <= cycle_r;
                evt_a[evt_head_r] <= u_edrv32_soc_top.u_cached_core.u_dcache.store_reservation_addr_w;
                evt_s[evt_head_r] <= "RESV_SET";
                evt_head_r <= evt_head_r + 1'b1;
            end
            if (!u_edrv32_soc_top.u_cached_core.u_dcache.store_reservation_valid_w &&
                prev_resv_r) begin
                evt_t[evt_head_r] <= cycle_r;
                evt_a[evt_head_r] <= u_edrv32_soc_top.u_cached_core.u_dcache.store_reservation_addr_w;
                evt_s[evt_head_r] <= "RESV_CLEAR";
                evt_head_r <= evt_head_r + 1'b1;
            end
            prev_resv_r <= u_edrv32_soc_top.u_cached_core.u_dcache.store_reservation_valid_w;
            if (u_edrv32_soc_top.u_cached_core.u_dcache.lookup_request_fire_w &&
                !prev_lookup_req_r) begin
                evt_t[evt_head_r] <= cycle_r;
                evt_a[evt_head_r] <= u_edrv32_soc_top.u_cached_core.u_dcache.lookup_req_addr_i;
                evt_s[evt_head_r] <= "LOOKUP_FIRE";
                evt_head_r <= evt_head_r + 1'b1;
            end
            prev_lookup_req_r <= u_edrv32_soc_top.u_cached_core.u_dcache.lookup_request_fire_w;
            if (u_edrv32_soc_top.u_cached_core.u_core.retire_o &&
                (u_edrv32_soc_top.u_cached_core.u_core.u_commit_stage.is_store_w)) begin
                evt_t[evt_head_r] <= cycle_r;
                evt_a[evt_head_r] <= u_edrv32_soc_top.u_cached_core.u_core.u_commit_stage.pc_i;
                evt_s[evt_head_r] <= "STORE_RETIRE";
                evt_head_r <= evt_head_r + 1'b1;
            end
            if (u_edrv32_soc_top.u_cached_core.u_dcache.lookup_cancel_i) begin
                evt_t[evt_head_r] <= cycle_r;
                evt_a[evt_head_r] <= 32'd0;
                evt_s[evt_head_r] <= "X_CANCEL";
                evt_head_r <= evt_head_r + 1'b1;
            end
            if (u_edrv32_soc_top.u_cached_core.u_dcache.local_store_fire_w) begin
                evt_t[evt_head_r] <= cycle_r;
                evt_a[evt_head_r] <= u_edrv32_soc_top.u_cached_core.u_dcache.store_reservation_addr_w;
                evt_s[evt_head_r] <= "X_STORE_FIRE";
                evt_head_r <= evt_head_r + 1'b1;
            end
            if (u_edrv32_soc_top.u_cached_core.u_dcache.lookup_request_fire_w &&
                u_edrv32_soc_top.u_cached_core.u_dcache.lookup_req_store_i) begin
                evt_t[evt_head_r] <= cycle_r;
                evt_a[evt_head_r] <= u_edrv32_soc_top.u_cached_core.u_dcache.lookup_req_addr_i;
                evt_s[evt_head_r] <= "STORE_LOOKUP";
                evt_head_r <= evt_head_r + 1'b1;
            end
            if (u_edrv32_soc_top.u_cached_core.u_core.u_commit_stage.take_interrupt_w) begin
                evt_t[evt_head_r] <= cycle_r;
                evt_a[evt_head_r] <= u_edrv32_soc_top.u_cached_core.u_core.u_commit_stage.pc_i;
                evt_s[evt_head_r] <= "TAKE_IRQ";
                evt_head_r <= evt_head_r + 1'b1;
            end
            if (u_edrv32_soc_top.u_cached_core.u_core.u_mem2_stage.capture_w) begin
                evt_t[evt_head_r] <= cycle_r;
                evt_a[evt_head_r] <= {28'd0,
                    u_edrv32_soc_top.u_cached_core.u_core.u_mem2_stage.op_class_i};
                evt_s[evt_head_r] <= "MEM2_CAPTURE";
                evt_head_r <= evt_head_r + 1'b1;
            end
            if (u_edrv32_soc_top.u_cached_core.u_dcache.lookup_response_fire_w &&
                u_edrv32_soc_top.u_cached_core.u_dcache.lookup_response_error_r) begin
                evt_t[evt_head_r] <= cycle_r;
                evt_a[evt_head_r] <= u_edrv32_soc_top.u_cached_core.u_dcache.lookup_addr_r;
                evt_s[evt_head_r] <= "X_RESP_ERROR";
                evt_head_r <= evt_head_r + 1'b1;
            end
            if (u_edrv32_soc_top.u_cached_core.u_core.commit_kill_younger_w) begin
                evt_t[evt_head_r] <= cycle_r;
                evt_s[evt_head_r] <= "COMMIT_KILL";
                evt_head_r <= evt_head_r + 1'b1;
            end
            if (u_edrv32_soc_top.u_cached_core.u_core.redirect_valid_w) begin
                evt_t[evt_head_r] <= cycle_r;
                evt_s[evt_head_r] <= "REDIRECT_VALID";
                evt_head_r <= evt_head_r + 1'b1;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            cycle_r <= 0;
            tx_count_r <= 0;
            tx_bit_r <= 0;
            tx_busy_r <= 0;
            tx_len_r <= 0;
        end else begin
            cycle_r <= cycle_r + 1'b1;
            if (u_edrv32_soc_top.u_cached_core.u_core.retire_o)
                last_retire_cycle_r <= cycle_r;
            if (boot_only_r &&
                u_edrv32_soc_top.u_cached_core.retire_exception_o) begin
                $display("EDRV32_BOOT_EXCEPTION cycle=%0d pc=%08x insn=%08x cause=%08x",
                         cycle_r,
                         u_edrv32_soc_top.u_cached_core.retire_pc_o,
                         u_edrv32_soc_top.u_cached_core.retire_instr_o,
                         u_edrv32_soc_top.u_cached_core.retire_cause_o);
            end
            if ((cycle_r > 20000) &&
                (cycle_r > last_retire_cycle_r + 20000)) begin
                $display("EDRV32_HANG cycle=%0d last_retire=%0d",
                         cycle_r, last_retire_cycle_r);
                $display("  dcache state=%0d resv=%0d resv_addr=%08x buf=%0d req_ready=%0d cancel=%0d",
                         u_edrv32_soc_top.u_cached_core.u_dcache.state_r,
                         u_edrv32_soc_top.u_cached_core.u_dcache.store_reservation_valid_w,
                         u_edrv32_soc_top.u_cached_core.u_dcache.store_reservation_addr_w,
                         u_edrv32_soc_top.u_cached_core.u_dcache.store_buffer_valid_r,
                         u_edrv32_soc_top.u_cached_core.u_dcache.commit_req_ready_o,
                         u_edrv32_soc_top.u_cached_core.u_core.dcache_lookup_cancel_o);
                $display("  commit pc=%08x op=%0d is_store=%0d cacheable=%0d token=%0d mem_state=%0d dmem_valid=%0d ready=%0d addr=%08x",
                         u_edrv32_soc_top.u_cached_core.u_core.u_commit_stage.pc_i,
                         u_edrv32_soc_top.u_cached_core.u_core.u_commit_stage.op_class_i,
                         u_edrv32_soc_top.u_cached_core.u_core.u_commit_stage.is_store_w,
                         u_edrv32_soc_top.u_cached_core.u_core.u_commit_stage.mem_cacheable_i,
                         u_edrv32_soc_top.u_cached_core.u_core.u_commit_stage.mdu_token_i,
                         u_edrv32_soc_top.u_cached_core.u_core.u_commit_stage.memory_state_r,
                         u_edrv32_soc_top.u_cached_core.u_core.u_commit_stage.dmem_req_valid_o,
                         u_edrv32_soc_top.u_cached_core.u_core.u_commit_stage.ready_o,
                         u_edrv32_soc_top.u_cached_core.u_core.u_commit_stage.mem_addr_i);
                $display("  mdu pending=%0d authorized=%0d result_valid=%0d slot=%0d complete=%0d",
                         u_edrv32_soc_top.u_cached_core.u_core.mdu_pending_w,
                         u_edrv32_soc_top.u_cached_core.u_core.mdu_authorized_w,
                         u_edrv32_soc_top.u_cached_core.u_core.mdu_result_valid_w,
                         u_edrv32_soc_top.u_cached_core.u_core.mdu_slot_valid_w,
                         u_edrv32_soc_top.u_cached_core.u_core.mdu_result_complete_w);
                $display("  mem1_cnt=%0d mem2_valid=%0d mem2_op=%0d mem2_pc=%08x fetch=%08x if2_cnt=%0d",
                         u_edrv32_soc_top.u_cached_core.u_core.u_mem1_stage.pipe_count_r,
                         u_edrv32_soc_top.u_cached_core.u_core.u_mem2_stage.valid_r,
                         u_edrv32_soc_top.u_cached_core.u_core.u_mem2_stage.op_class_r,
                         u_edrv32_soc_top.u_cached_core.u_core.u_mem2_stage.pc_r,
                         u_edrv32_soc_top.u_cached_core.u_core.u_if1_stage.fetch_addr_r,
                         u_edrv32_soc_top.u_cached_core.u_core.u_if2_stage.count_r);
                $display("  ---- event log tail ----");
                evt_tail = evt_head_r;
                for (evt_i = 0; evt_i < 40; evt_i = evt_i + 1) begin
                    evt_tail = evt_tail - 1'b1;
                    if (evt_tail < 0)
                        evt_tail = 255;
                    if (evt_s[evt_tail] != 0)
                        $display("  T%0d %0s addr=%08x", evt_t[evt_tail],
                                 evt_s[evt_tail], evt_a[evt_tail]);
                end
                $finish;
            end
            if (!tx_busy_r) begin
                if (!uart_tx_w) begin
                    tx_busy_r <= 1'b1;
                    tx_count_r <= CLKS_PER_BIT + (CLKS_PER_BIT / 2) - 1;
                    tx_bit_r <= 0;
                end
            end else if (tx_count_r != 0) begin
                tx_count_r <= tx_count_r - 1;
            end else if (tx_bit_r < 8) begin
                tx_shift_r[tx_bit_r] <= uart_tx_w;
                tx_bit_r <= tx_bit_r + 1;
                tx_count_r <= CLKS_PER_BIT - 1;
            end else begin
                if (!uart_tx_w)
                    $fatal(1, "CoreMark UART stop bit low");
                if (tx_len_r < 2048) begin
                    tx_buf[tx_len_r] <= tx_shift_r;
                    tx_len_r <= tx_len_r + 1'b1;
                    $write("%c", tx_shift_r);
                end
                tx_busy_r <= 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        if (tx_len_r >= 27) begin
            for (scan_i = 0; scan_i + 26 < tx_len_r; scan_i = scan_i + 1) begin
                if (tx_buf[scan_i] == "C" && tx_buf[scan_i+1] == "o" &&
                    tx_buf[scan_i+2] == "r" && tx_buf[scan_i+3] == "r" &&
                    tx_buf[scan_i+4] == "e" && tx_buf[scan_i+5] == "c" &&
                    tx_buf[scan_i+6] == "t" && tx_buf[scan_i+7] == " " &&
                    tx_buf[scan_i+8] == "o" && tx_buf[scan_i+9] == "p" &&
                    tx_buf[scan_i+10] == "e" && tx_buf[scan_i+11] == "r" &&
                    tx_buf[scan_i+12] == "a" && tx_buf[scan_i+13] == "t" &&
                    tx_buf[scan_i+14] == "i" && tx_buf[scan_i+15] == "o" &&
                    tx_buf[scan_i+16] == "n" && tx_buf[scan_i+17] == " " &&
                    tx_buf[scan_i+18] == "v" && tx_buf[scan_i+19] == "a" &&
                    tx_buf[scan_i+20] == "l" && tx_buf[scan_i+21] == "i" &&
                    tx_buf[scan_i+22] == "d" && tx_buf[scan_i+23] == "a" &&
                    tx_buf[scan_i+24] == "t" && tx_buf[scan_i+25] == "e" &&
                    tx_buf[scan_i+26] == "d")
                    correct_seen_r <= 1'b1;
            end
        end

        if (tx_len_r >= 22) begin
            for (scan_i = 0; scan_i + 21 < tx_len_r; scan_i = scan_i + 1) begin
                if (tx_buf[scan_i] == "B" && tx_buf[scan_i+1] == "o" &&
                    tx_buf[scan_i+2] == "o" && tx_buf[scan_i+3] == "t" &&
                    tx_buf[scan_i+4] == "R" && tx_buf[scan_i+5] == "O" &&
                    tx_buf[scan_i+6] == "M" && tx_buf[scan_i+7] == " " &&
                    tx_buf[scan_i+8] == "-" && tx_buf[scan_i+9] == ">" &&
                    tx_buf[scan_i+10] == " " && tx_buf[scan_i+11] == "c" &&
                    tx_buf[scan_i+12] == "a" && tx_buf[scan_i+13] == "c" &&
                    tx_buf[scan_i+14] == "h" && tx_buf[scan_i+15] == "e" &&
                    tx_buf[scan_i+16] == "d" && tx_buf[scan_i+17] == " " &&
                    tx_buf[scan_i+18] == "S" && tx_buf[scan_i+19] == "R" &&
                    tx_buf[scan_i+20] == "A" && tx_buf[scan_i+21] == "M")
                    runtime_seen_r <= 1'b1;
            end
        end

        if (tx_len_r >= 20) begin
            for (scan_i = 0; scan_i + 19 < tx_len_r; scan_i = scan_i + 1) begin
                if (tx_buf[scan_i] == "R" && tx_buf[scan_i+1] == "u" &&
                    tx_buf[scan_i+2] == "n" && tx_buf[scan_i+3] == "t" &&
                    tx_buf[scan_i+4] == "i" && tx_buf[scan_i+5] == "m" &&
                    tx_buf[scan_i+6] == "e" && tx_buf[scan_i+7] == " " &&
                    tx_buf[scan_i+8] == "C" && tx_buf[scan_i+9] == "A" &&
                    tx_buf[scan_i+10] == "M" && tx_buf[scan_i+11] == "/" &&
                    tx_buf[scan_i+12] == "D" && tx_buf[scan_i+13] == "I" &&
                    tx_buf[scan_i+14] == "S" && tx_buf[scan_i+15] == "P" &&
                    tx_buf[scan_i+16] == " " && tx_buf[scan_i+17] == "A" &&
                    tx_buf[scan_i+18] == "P" && tx_buf[scan_i+19] == "B")
                    vision_seen_r <= 1'b1;
            end
        end

        if (tx_len_r >= 7) begin
            for (scan_i = 0; scan_i + 6 < tx_len_r; scan_i = scan_i + 1) begin
                if (tx_buf[scan_i] == "C" && tx_buf[scan_i+1] == "A" &&
                    tx_buf[scan_i+2] == "M" && tx_buf[scan_i+3] == " " &&
                    tx_buf[scan_i+4] == " " && tx_buf[scan_i+5] == "I" &&
                    tx_buf[scan_i+6] == "D")
                    vision_command_seen_r <= 1'b1;
            end
        end

        if (correct_seen_r || (boot_only_r && runtime_seen_r) ||
            (vision_menu_r && vision_command_seen_r)) begin
            $display("\nEDRV32_TEST_PASS board-coremark-rom bytes=%0d cycles=%0d",
                     tx_len_r, cycle_r);
            $finish;
        end
        if (cycle_r >= MAX_CYCLES) begin
            $display("EDRV32_TEST_TIMEOUT board-coremark-rom bytes=%0d",
                     tx_len_r);
            $finish;
        end
    end
endmodule
