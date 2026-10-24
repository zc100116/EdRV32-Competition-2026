// ============================================================================
// File        : edrv32_ddr_monitor.v
// Description : APB-controlled DDR traffic generator and AXI performance
//               monitor. Commands and result snapshots cross between the SoC
//               APB clock and the 256-bit DDR AXI clock through async FIFOs.
// Notes       : Generates aligned 256-bit INCR traffic and splits long tests
//               locally into requests of at most 16 beats without crossing a
//               4-KiB boundary.  The Pango adapter maps each request to one UI
//               command and does not split requests further.
// ============================================================================
`include "edrv32_periph_abi.vh"

module edrv32_ddr_monitor (
    // --- APB control plane ---
    input  wire         apb_clk_i,
    input  wire         apb_rst_n_i,
    input  wire [31:0]  paddr_i,
    input  wire         psel_i,
    input  wire         penable_i,
    input  wire         pwrite_i,
    input  wire [31:0]  pwdata_i,
    input  wire [3:0]   pstrb_i,
    output wire         pready_o,
    output wire [31:0]  prdata_o,
    output wire         pslverr_o,

    // --- AXI data plane ---
    input  wire         axi_clk_i,
    input  wire         axi_rst_n_i,
    output wire [3:0]   m_awid_o,
    output wire [31:0]  m_awaddr_o,
    output wire [7:0]   m_awlen_o,
    output wire [2:0]   m_awsize_o,
    output wire [1:0]   m_awburst_o,
    output wire [3:0]   m_awqos_o,
    output wire         m_awvalid_o,
    input  wire         m_awready_i,
    output wire [255:0] m_wdata_o,
    output wire [31:0]  m_wstrb_o,
    output wire         m_wlast_o,
    output wire         m_wvalid_o,
    input  wire         m_wready_i,
    input  wire [3:0]   m_bid_i,
    input  wire [1:0]   m_bresp_i,
    input  wire         m_bvalid_i,
    output wire         m_bready_o,
    output wire [3:0]   m_arid_o,
    output wire [31:0]  m_araddr_o,
    output wire [7:0]   m_arlen_o,
    output wire [2:0]   m_arsize_o,
    output wire [1:0]   m_arburst_o,
    output wire [3:0]   m_arqos_o,
    output wire         m_arvalid_o,
    input  wire         m_arready_i,
    input  wire [3:0]   m_rid_i,
    input  wire [255:0] m_rdata_i,
    input  wire [1:0]   m_rresp_i,
    input  wire         m_rlast_i,
    input  wire         m_rvalid_i,
    output wire         m_rready_o
);

    localparam [31:0] MONITOR_ID      = 32'h4444_524d; // "DDRM"
    localparam [31:0] MONITOR_VERSION = 32'h0001_0000;
    localparam [3:0]  MONITOR_AXI_ID  = 4'hd;

    localparam integer CMD_W = 138;
    localparam integer RESULT_W = 352;

    localparam [2:0] STATE_IDLE   = 3'd0;
    localparam [2:0] STATE_W_AW   = 3'd1;
    localparam [2:0] STATE_W_DATA = 3'd2;
    localparam [2:0] STATE_W_RESP = 3'd3;
    localparam [2:0] STATE_R_AR   = 3'd4;
    localparam [2:0] STATE_R_DATA = 3'd5;
    localparam [2:0] STATE_RESULT = 3'd6;

    function [31:0] apply_strobe;
        input [31:0] old_value;
        input [31:0] new_value;
        input [3:0]  strobe;
        integer byte_index;
        begin
            apply_strobe = old_value;
            for (byte_index = 0; byte_index < 4;
                 byte_index = byte_index + 1) begin
                if (strobe[byte_index])
                    apply_strobe[byte_index*8 +: 8] =
                        new_value[byte_index*8 +: 8];
            end
        end
    endfunction

    function [255:0] pattern_data;
        input [31:0] address;
        input [31:0] seed;
        integer lane_index;
        begin
            for (lane_index = 0; lane_index < 8;
                 lane_index = lane_index + 1) begin
                pattern_data[lane_index*32 +: 32] =
                    seed ^ address ^ (lane_index * 32'h0101_0101);
            end
        end
    endfunction

    // ========================================================================
    // APB-domain configuration and result registers
    // ========================================================================
    wire apb_access_w = psel_i & penable_i;
    wire aligned_w = paddr_i[1:0] == 2'b00;
    wire local_slot_w = paddr_i[31:8] == 24'b0;
    wire [7:0] offset_w = paddr_i[7:0];

    wire implemented_w =
        (offset_w == `DDR_MON_ID)               |
        (offset_w == `DDR_MON_VERSION)          |
        (offset_w == `DDR_MON_CONTROL)          |
        (offset_w == `DDR_MON_STATUS)           |
        (offset_w == `DDR_MON_MODE)             |
        (offset_w == `DDR_MON_BASE_ADDR)        |
        (offset_w == `DDR_MON_TOTAL_BEATS)      |
        (offset_w == `DDR_MON_BURST_LEN)        |
        (offset_w == `DDR_MON_PATTERN_SEED)     |
        (offset_w == `DDR_MON_LOOP_COUNT)       |
        (offset_w == `DDR_MON_TOTAL_CYCLES)     |
        (offset_w == `DDR_MON_WRITE_BEATS)      |
        (offset_w == `DDR_MON_READ_BEATS)       |
        (offset_w == `DDR_MON_AW_STALL_CYCLES)  |
        (offset_w == `DDR_MON_W_STALL_CYCLES)   |
        (offset_w == `DDR_MON_AR_STALL_CYCLES)  |
        (offset_w == `DDR_MON_R_WAIT_CYCLES)    |
        (offset_w == `DDR_MON_ERROR_COUNT)      |
        (offset_w == `DDR_MON_FIRST_ERROR_ADDR) |
        (offset_w == `DDR_MON_EXPECTED_DATA)    |
        (offset_w == `DDR_MON_ACTUAL_DATA);

    wire legal_access_w = aligned_w & local_slot_w & implemented_w;
    wire write_access_w = apb_access_w & pwrite_i & legal_access_w;
    wire start_write_w = write_access_w &
                         (offset_w == `DDR_MON_CONTROL) &
                         pstrb_i[0] & pwdata_i[`DDR_MON_CONTROL_START];
    wire clear_write_w = write_access_w &
                         (offset_w == `DDR_MON_CONTROL) &
                         pstrb_i[0] & pwdata_i[`DDR_MON_CONTROL_CLEAR];

    reg [1:0]  mode_r;
    reg [31:0] base_addr_r;
    reg [31:0] total_beats_cfg_r;
    reg [7:0]  burst_len_r;
    reg [31:0] pattern_seed_r;
    reg [31:0] loop_count_r;
    reg        busy_r;
    reg        done_r;
    reg        error_r;
    reg        cmd_pending_r;
    reg [CMD_W-1:0] cmd_data_r;

    reg [31:0] total_cycles_result_r;
    reg [31:0] write_beats_result_r;
    reg [31:0] read_beats_result_r;
    reg [31:0] aw_stall_result_r;
    reg [31:0] w_stall_result_r;
    reg [31:0] ar_stall_result_r;
    reg [31:0] r_wait_result_r;
    reg [31:0] error_count_result_r;
    reg [31:0] first_error_addr_result_r;
    reg [31:0] expected_data_result_r;
    reg [31:0] actual_data_result_r;
    reg [31:0] prdata_r;

    wire cmd_ready_w;
    wire start_ready_w = ~busy_r & ~cmd_pending_r & cmd_ready_w;
    wire start_blocked_w = start_write_w & ~start_ready_w;

    wire [RESULT_W-1:0] result_data_w;
    wire result_valid_w;

    assign pready_o = 1'b1;
    assign pslverr_o = apb_access_w & ~legal_access_w;
    assign prdata_o = prdata_r;

    always @(*) begin
        prdata_r = 32'b0;
        case (offset_w)
            `DDR_MON_ID:               prdata_r = MONITOR_ID;
            `DDR_MON_VERSION:          prdata_r = MONITOR_VERSION;
            `DDR_MON_STATUS:           prdata_r = {
                28'b0, start_ready_w, error_r, done_r, busy_r};
            `DDR_MON_MODE:             prdata_r = {30'b0, mode_r};
            `DDR_MON_BASE_ADDR:        prdata_r = base_addr_r;
            `DDR_MON_TOTAL_BEATS:      prdata_r = total_beats_cfg_r;
            `DDR_MON_BURST_LEN:        prdata_r = {24'b0, burst_len_r};
            `DDR_MON_PATTERN_SEED:     prdata_r = pattern_seed_r;
            `DDR_MON_LOOP_COUNT:       prdata_r = loop_count_r;
            `DDR_MON_TOTAL_CYCLES:     prdata_r = total_cycles_result_r;
            `DDR_MON_WRITE_BEATS:      prdata_r = write_beats_result_r;
            `DDR_MON_READ_BEATS:       prdata_r = read_beats_result_r;
            `DDR_MON_AW_STALL_CYCLES:  prdata_r = aw_stall_result_r;
            `DDR_MON_W_STALL_CYCLES:   prdata_r = w_stall_result_r;
            `DDR_MON_AR_STALL_CYCLES:  prdata_r = ar_stall_result_r;
            `DDR_MON_R_WAIT_CYCLES:    prdata_r = r_wait_result_r;
            `DDR_MON_ERROR_COUNT:      prdata_r = error_count_result_r;
            `DDR_MON_FIRST_ERROR_ADDR: prdata_r = first_error_addr_result_r;
            `DDR_MON_EXPECTED_DATA:    prdata_r = expected_data_result_r;
            `DDR_MON_ACTUAL_DATA:      prdata_r = actual_data_result_r;
            default:                   prdata_r = 32'b0;
        endcase
    end

    always @(posedge apb_clk_i or negedge apb_rst_n_i) begin
        if (!apb_rst_n_i) begin
            mode_r                    <= `DDR_MON_MODE_WRITE_READ;
            base_addr_r               <= 32'b0;
            total_beats_cfg_r         <= 32'd1024;
            burst_len_r               <= 8'hff;
            pattern_seed_r            <= 32'h1ace_b00c;
            loop_count_r              <= 32'd1;
            busy_r                    <= 1'b0;
            done_r                    <= 1'b0;
            error_r                   <= 1'b0;
            cmd_pending_r             <= 1'b0;
            cmd_data_r                <= {CMD_W{1'b0}};
            total_cycles_result_r     <= 32'b0;
            write_beats_result_r      <= 32'b0;
            read_beats_result_r       <= 32'b0;
            aw_stall_result_r         <= 32'b0;
            w_stall_result_r          <= 32'b0;
            ar_stall_result_r         <= 32'b0;
            r_wait_result_r           <= 32'b0;
            error_count_result_r      <= 32'b0;
            first_error_addr_result_r <= 32'b0;
            expected_data_result_r    <= 32'b0;
            actual_data_result_r      <= 32'b0;
        end else begin
            if (cmd_pending_r && cmd_ready_w)
                cmd_pending_r <= 1'b0;

            if (clear_write_w && !busy_r) begin
                done_r                    <= 1'b0;
                error_r                   <= 1'b0;
                total_cycles_result_r     <= 32'b0;
                write_beats_result_r      <= 32'b0;
                read_beats_result_r       <= 32'b0;
                aw_stall_result_r         <= 32'b0;
                w_stall_result_r          <= 32'b0;
                ar_stall_result_r         <= 32'b0;
                r_wait_result_r           <= 32'b0;
                error_count_result_r      <= 32'b0;
                first_error_addr_result_r <= 32'b0;
                expected_data_result_r    <= 32'b0;
                actual_data_result_r      <= 32'b0;
            end

            if (write_access_w && !busy_r) begin
                case (offset_w)
                    `DDR_MON_MODE:
                        mode_r <= apply_strobe(
                            {30'b0, mode_r}, pwdata_i, pstrb_i);
                    `DDR_MON_BASE_ADDR:
                        base_addr_r <= apply_strobe(
                            base_addr_r, pwdata_i, pstrb_i);
                    `DDR_MON_TOTAL_BEATS:
                        total_beats_cfg_r <= apply_strobe(
                            total_beats_cfg_r, pwdata_i, pstrb_i);
                    `DDR_MON_BURST_LEN:
                        burst_len_r <= apply_strobe(
                            {24'b0, burst_len_r}, pwdata_i, pstrb_i);
                    `DDR_MON_PATTERN_SEED:
                        pattern_seed_r <= apply_strobe(
                            pattern_seed_r, pwdata_i, pstrb_i);
                    `DDR_MON_LOOP_COUNT:
                        loop_count_r <= apply_strobe(
                            loop_count_r, pwdata_i, pstrb_i);
                    default: begin
                    end
                endcase
            end

            if (start_write_w && !start_blocked_w) begin
                cmd_data_r <= {
                    loop_count_r,
                    pattern_seed_r,
                    burst_len_r,
                    total_beats_cfg_r,
                    base_addr_r,
                    mode_r
                };
                cmd_pending_r <= 1'b1;
                busy_r <= 1'b1;
                done_r <= 1'b0;
                error_r <= 1'b0;
            end

            if (result_valid_w) begin
                total_cycles_result_r     <= result_data_w[31:0];
                write_beats_result_r      <= result_data_w[63:32];
                read_beats_result_r       <= result_data_w[95:64];
                aw_stall_result_r         <= result_data_w[127:96];
                w_stall_result_r          <= result_data_w[159:128];
                ar_stall_result_r         <= result_data_w[191:160];
                r_wait_result_r           <= result_data_w[223:192];
                error_count_result_r      <= result_data_w[255:224];
                first_error_addr_result_r <= result_data_w[287:256];
                expected_data_result_r    <= result_data_w[319:288];
                actual_data_result_r      <= result_data_w[351:320];
                busy_r                    <= 1'b0;
                done_r                    <= 1'b1;
                error_r                   <= |result_data_w[255:224];
            end
        end
    end

    // ========================================================================
    // Clock-domain crossing queues
    // ========================================================================
    wire [CMD_W-1:0] axi_cmd_data_w;
    wire axi_cmd_valid_w;
    wire axi_cmd_ready_w;

    edrv32_async_fifo #(
        .DATA_W (CMD_W),
        .ADDR_W (2)
    ) u_command_fifo (
        .wr_clk_i   (apb_clk_i),
        .wr_rst_n_i (apb_rst_n_i),
        .wr_data_i  (cmd_data_r),
        .wr_valid_i (cmd_pending_r),
        .wr_ready_o (cmd_ready_w),
        .rd_clk_i   (axi_clk_i),
        .rd_rst_n_i (axi_rst_n_i),
        .rd_data_o  (axi_cmd_data_w),
        .rd_valid_o (axi_cmd_valid_w),
        .rd_ready_i (axi_cmd_ready_w)
    );

    reg [RESULT_W-1:0] axi_result_data_r;
    reg                axi_result_valid_r;
    wire               axi_result_ready_w;

    edrv32_async_fifo #(
        .DATA_W (RESULT_W),
        .ADDR_W (2)
    ) u_result_fifo (
        .wr_clk_i   (axi_clk_i),
        .wr_rst_n_i (axi_rst_n_i),
        .wr_data_i  (axi_result_data_r),
        .wr_valid_i (axi_result_valid_r),
        .wr_ready_o (axi_result_ready_w),
        .rd_clk_i   (apb_clk_i),
        .rd_rst_n_i (apb_rst_n_i),
        .rd_data_o  (result_data_w),
        .rd_valid_o (result_valid_w),
        .rd_ready_i (1'b1)
    );

    // ========================================================================
    // AXI-domain traffic engine
    // ========================================================================
    reg [2:0]  state_r;
    reg [1:0]  test_mode_r;
    reg [31:0] test_base_addr_r;
    reg [31:0] test_total_beats_r;
    reg [7:0]  test_burst_len_r;
    reg [31:0] test_pattern_seed_r;
    reg [31:0] loop_remaining_r;
    reg [31:0] current_addr_r;
    reg [31:0] remaining_beats_r;
    reg [8:0]  burst_beats_left_r;

    reg [31:0] total_cycles_r;
    reg [31:0] write_beats_r;
    reg [31:0] read_beats_r;
    reg [31:0] aw_stall_cycles_r;
    reg [31:0] w_stall_cycles_r;
    reg [31:0] ar_stall_cycles_r;
    reg [31:0] r_wait_cycles_r;
    reg [31:0] error_count_r;
    reg [31:0] first_error_addr_r;
    reg [31:0] expected_data_r;
    reg [31:0] actual_data_r;

    wire [1:0]  cmd_mode_w = axi_cmd_data_w[1:0];
    wire [31:0] cmd_base_addr_w = axi_cmd_data_w[33:2];
    wire [31:0] cmd_total_beats_w = axi_cmd_data_w[65:34];
    wire [7:0]  cmd_burst_len_w = axi_cmd_data_w[73:66];
    wire [31:0] cmd_pattern_seed_w = axi_cmd_data_w[105:74];
    wire [31:0] cmd_loop_count_w = axi_cmd_data_w[137:106];
    wire [31:0] cmd_address_room_beats_w =
        (32'h1000_0000 - cmd_base_addr_w) >> 5;

    wire command_legal_w =
        (cmd_mode_w <= `DDR_MON_MODE_WRITE_READ) &
        (cmd_total_beats_w != 32'b0) &
        (cmd_base_addr_w[4:0] == 5'b0) &
        (cmd_base_addr_w[31:28] == 4'b0) &
        (cmd_total_beats_w <= cmd_address_room_beats_w);

    wire [8:0] configured_burst_beats_w =
        {1'b0, test_burst_len_r} + 9'd1;
    wire [12:0] bytes_to_boundary_w =
        13'd4096 - {1'b0, current_addr_r[11:0]};
    wire [8:0] boundary_beats_w = bytes_to_boundary_w[12:5];
    reg [8:0] burst_beats_r;

    always @(*) begin
        burst_beats_r = configured_burst_beats_w;
        if (burst_beats_r > 9'd16)
            burst_beats_r = 9'd16;
        if (remaining_beats_r < burst_beats_r)
            burst_beats_r = remaining_beats_r[8:0];
        if (boundary_beats_w < burst_beats_r)
            burst_beats_r = boundary_beats_w;
        if (burst_beats_r == 9'b0)
            burst_beats_r = 9'd1;
    end

    wire [255:0] expected_pattern_w =
        pattern_data(current_addr_r, test_pattern_seed_r);
    wire expected_rlast_w = burst_beats_left_r == 9'd1;
    wire read_beat_error_w =
        (m_rresp_i != 2'b00) |
        (m_rid_i != MONITOR_AXI_ID) |
        (m_rlast_i != expected_rlast_w) |
        (m_rdata_i != expected_pattern_w);

    assign axi_cmd_ready_w = state_r == STATE_IDLE;

    assign m_awid_o    = MONITOR_AXI_ID;
    assign m_awaddr_o  = current_addr_r;
    assign m_awlen_o   = burst_beats_r[7:0] - 8'd1;
    assign m_awsize_o  = 3'd5;
    assign m_awburst_o = 2'b01;
    assign m_awqos_o   = 4'b0;
    assign m_awvalid_o = state_r == STATE_W_AW;

    assign m_wdata_o   = expected_pattern_w;
    assign m_wstrb_o   = 32'hffff_ffff;
    assign m_wlast_o   = burst_beats_left_r == 9'd1;
    assign m_wvalid_o  = state_r == STATE_W_DATA;
    assign m_bready_o  = state_r == STATE_W_RESP;

    assign m_arid_o    = MONITOR_AXI_ID;
    assign m_araddr_o  = current_addr_r;
    assign m_arlen_o   = burst_beats_r[7:0] - 8'd1;
    assign m_arsize_o  = 3'd5;
    assign m_arburst_o = 2'b01;
    assign m_arqos_o   = 4'b0;
    assign m_arvalid_o = state_r == STATE_R_AR;
    assign m_rready_o  = state_r == STATE_R_DATA;

    always @(posedge axi_clk_i or negedge axi_rst_n_i) begin
        if (!axi_rst_n_i) begin
            state_r                  <= STATE_IDLE;
            test_mode_r              <= `DDR_MON_MODE_WRITE;
            test_base_addr_r         <= 32'b0;
            test_total_beats_r       <= 32'b0;
            test_burst_len_r         <= 8'b0;
            test_pattern_seed_r      <= 32'b0;
            loop_remaining_r         <= 32'b0;
            current_addr_r           <= 32'b0;
            remaining_beats_r        <= 32'b0;
            burst_beats_left_r       <= 9'b0;
            total_cycles_r           <= 32'b0;
            write_beats_r            <= 32'b0;
            read_beats_r             <= 32'b0;
            aw_stall_cycles_r        <= 32'b0;
            w_stall_cycles_r         <= 32'b0;
            ar_stall_cycles_r        <= 32'b0;
            r_wait_cycles_r          <= 32'b0;
            error_count_r            <= 32'b0;
            first_error_addr_r       <= 32'b0;
            expected_data_r          <= 32'b0;
            actual_data_r            <= 32'b0;
            axi_result_data_r        <= {RESULT_W{1'b0}};
            axi_result_valid_r       <= 1'b0;
        end else begin
            if (axi_result_valid_r && axi_result_ready_w)
                axi_result_valid_r <= 1'b0;

            if ((state_r != STATE_IDLE) && (state_r != STATE_RESULT))
                total_cycles_r <= total_cycles_r + 32'd1;

            if ((state_r == STATE_W_AW) && !m_awready_i)
                aw_stall_cycles_r <= aw_stall_cycles_r + 32'd1;
            if ((state_r == STATE_W_DATA) && !m_wready_i)
                w_stall_cycles_r <= w_stall_cycles_r + 32'd1;
            if ((state_r == STATE_R_AR) && !m_arready_i)
                ar_stall_cycles_r <= ar_stall_cycles_r + 32'd1;
            if ((state_r == STATE_R_DATA) && !m_rvalid_i)
                r_wait_cycles_r <= r_wait_cycles_r + 32'd1;

            case (state_r)
                STATE_IDLE: begin
                    if (axi_cmd_valid_w) begin
                        test_mode_r         <= cmd_mode_w;
                        test_base_addr_r    <= cmd_base_addr_w;
                        test_total_beats_r  <= cmd_total_beats_w;
                        test_burst_len_r    <= cmd_burst_len_w;
                        test_pattern_seed_r <= cmd_pattern_seed_w;
                        loop_remaining_r    <=
                            (cmd_loop_count_w == 32'b0) ?
                            32'd1 : cmd_loop_count_w;
                        current_addr_r      <= cmd_base_addr_w;
                        remaining_beats_r   <= cmd_total_beats_w;
                        total_cycles_r      <= 32'b0;
                        write_beats_r       <= 32'b0;
                        read_beats_r        <= 32'b0;
                        aw_stall_cycles_r   <= 32'b0;
                        w_stall_cycles_r    <= 32'b0;
                        ar_stall_cycles_r   <= 32'b0;
                        r_wait_cycles_r     <= 32'b0;
                        error_count_r       <= 32'b0;
                        first_error_addr_r  <= 32'b0;
                        expected_data_r     <= 32'b0;
                        actual_data_r       <= 32'b0;
                        if (!command_legal_w) begin
                            error_count_r      <= 32'd1;
                            first_error_addr_r <= cmd_base_addr_w;
                            actual_data_r      <= 32'hbad0_0001;
                            state_r            <= STATE_RESULT;
                        end else if (cmd_mode_w ==
                                     `DDR_MON_MODE_READ_VERIFY) begin
                            state_r <= STATE_R_AR;
                        end else begin
                            state_r <= STATE_W_AW;
                        end
                    end
                end

                STATE_W_AW: begin
                    if (m_awready_i) begin
                        burst_beats_left_r <= burst_beats_r;
                        state_r <= STATE_W_DATA;
                    end
                end

                STATE_W_DATA: begin
                    if (m_wready_i) begin
                        write_beats_r      <= write_beats_r + 32'd1;
                        current_addr_r     <= current_addr_r + 32'd32;
                        remaining_beats_r  <= remaining_beats_r - 32'd1;
                        burst_beats_left_r <= burst_beats_left_r - 9'd1;
                        if (burst_beats_left_r == 9'd1)
                            state_r <= STATE_W_RESP;
                    end
                end

                STATE_W_RESP: begin
                    if (m_bvalid_i) begin
                        if ((m_bresp_i != 2'b00) ||
                            (m_bid_i != MONITOR_AXI_ID)) begin
                            error_count_r <= error_count_r + 32'd1;
                            if (error_count_r == 32'b0) begin
                                first_error_addr_r <= current_addr_r - 32'd32;
                                expected_data_r <= 32'b0;
                                actual_data_r <= {26'b0, m_bid_i, m_bresp_i};
                            end
                        end

                        if (remaining_beats_r != 32'b0) begin
                            state_r <= STATE_W_AW;
                        end else if (test_mode_r ==
                                     `DDR_MON_MODE_WRITE_READ) begin
                            current_addr_r    <= test_base_addr_r;
                            remaining_beats_r <= test_total_beats_r;
                            state_r           <= STATE_R_AR;
                        end else if (loop_remaining_r > 32'd1) begin
                            loop_remaining_r  <= loop_remaining_r - 32'd1;
                            current_addr_r    <= test_base_addr_r;
                            remaining_beats_r <= test_total_beats_r;
                            state_r           <= STATE_W_AW;
                        end else begin
                            state_r <= STATE_RESULT;
                        end
                    end
                end

                STATE_R_AR: begin
                    if (m_arready_i) begin
                        burst_beats_left_r <= burst_beats_r;
                        state_r <= STATE_R_DATA;
                    end
                end

                STATE_R_DATA: begin
                    if (m_rvalid_i) begin
                        read_beats_r        <= read_beats_r + 32'd1;
                        current_addr_r       <= current_addr_r + 32'd32;
                        remaining_beats_r    <= remaining_beats_r - 32'd1;
                        burst_beats_left_r   <= burst_beats_left_r - 9'd1;

                        if (read_beat_error_w) begin
                            error_count_r <= error_count_r + 32'd1;
                            if (error_count_r == 32'b0) begin
                                first_error_addr_r <= current_addr_r;
                                expected_data_r <= expected_pattern_w[31:0];
                                actual_data_r <= m_rdata_i[31:0];
                            end
                        end

                        if (burst_beats_left_r == 9'd1) begin
                            if (remaining_beats_r == 32'd1) begin
                                if (loop_remaining_r > 32'd1) begin
                                    loop_remaining_r <=
                                        loop_remaining_r - 32'd1;
                                    current_addr_r <= test_base_addr_r;
                                    remaining_beats_r <= test_total_beats_r;
                                    if (test_mode_r ==
                                        `DDR_MON_MODE_WRITE_READ)
                                        state_r <= STATE_W_AW;
                                    else
                                        state_r <= STATE_R_AR;
                                end else begin
                                    state_r <= STATE_RESULT;
                                end
                            end else begin
                                state_r <= STATE_R_AR;
                            end
                        end
                    end
                end

                STATE_RESULT: begin
                    if (!axi_result_valid_r) begin
                        axi_result_data_r <= {
                            actual_data_r,
                            expected_data_r,
                            first_error_addr_r,
                            error_count_r,
                            r_wait_cycles_r,
                            ar_stall_cycles_r,
                            w_stall_cycles_r,
                            aw_stall_cycles_r,
                            read_beats_r,
                            write_beats_r,
                            total_cycles_r
                        };
                        axi_result_valid_r <= 1'b1;
                    end else if (axi_result_ready_w) begin
                        state_r <= STATE_IDLE;
                    end
                end

                default: state_r <= STATE_IDLE;
            endcase
        end
    end

endmodule
