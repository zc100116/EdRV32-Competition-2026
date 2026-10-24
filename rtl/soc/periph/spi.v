// ============================================================================
// File        : spi.v
// Author      : Edward ZC
// Description : SOC3 APB SPI master with Single/Dual/Quad transfers.
// Notes       : Verilog-2001.  All serial data is driven and sampled per SCLK
//               edge.  IO0=MOSI and IO1=MISO in single full-duplex mode.
// ============================================================================
`include "edrv32_apb.vh"
`include "edrv32_soc_map.vh"

// ============================================================================
// spi - configurable edge-driven SPI master
// ============================================================================
module spi #(
    parameter integer INSTANCE_ID = 0,
    parameter [15:0]  DEFAULT_CLKDIV = 16'd4,
    parameter integer FIFO_DEPTH = 4,
    parameter integer NUM_CS = 4
)(
    // --- Clock and reset ---
    input  wire                 clk,
    input  wire                 rst_n,

    // --- APB interface ---
    input  wire [`APB_AW-1:0]   paddr_i,
    input  wire                 psel_i,
    input  wire                 penable_i,
    input  wire                 pwrite_i,
    input  wire [31:0]          pwdata_i,
    input  wire [3:0]           pstrb_i,
    output wire                 pready_o,
    output reg  [31:0]          prdata_o,
    output wire                 pslverr_o,

    // --- SPI pins ---
    input  wire [3:0]           io_i,
    output reg  [3:0]           io_o,
    output reg  [3:0]           io_oe_o,
    output wire                 sclk_o,
    output wire [NUM_CS-1:0]    cs_n_o,

    // --- Interrupt ---
    output wire                 irq_o
);

    localparam [8:0] CTRL_STORAGE_MASK = 9'b1_0111_1111;
    localparam [1:0] IP_VALID_MASK = 2'b11;

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

    // ========================================================================
    // APB decode
    // ========================================================================
    wire apb_access_w;
    wire aligned_w;
    wire local_slot_w;
    wire implemented_w;
    wire legal_access_w;
    wire write_access_w;
    wire read_access_w;
    wire [7:0] offset_w;
    wire instance_valid_w;

    assign apb_access_w = psel_i & penable_i;
    assign aligned_w = (paddr_i[1:0] == 2'b00);
    assign local_slot_w = (paddr_i[`APB_AW-1:8] == 0);
    assign offset_w = paddr_i[7:0];
    assign instance_valid_w = (INSTANCE_ID >= 0);
    assign implemented_w =
        (offset_w == `SPI_CTRL)   |
        (offset_w == `SPI_STATUS) |
        (offset_w == `SPI_TXDATA) |
        (offset_w == `SPI_RXDATA) |
        (offset_w == `SPI_CLKDIV) |
        (offset_w == `SPI_CSMASK) |
        (offset_w == `SPI_BITS)   |
        (offset_w == `SPI_IP)     |
        (offset_w == `SPI_IE)     |
        (offset_w == `SPI_MODE)   |
        (offset_w == `SPI_CMD);
    assign legal_access_w =
        aligned_w & local_slot_w & implemented_w & instance_valid_w;
    assign write_access_w =
        apb_access_w & legal_access_w & pwrite_i;
    assign read_access_w =
        apb_access_w & legal_access_w & ~pwrite_i;

    assign pready_o = 1'b1;
    assign pslverr_o = apb_access_w & ~legal_access_w;

    // ========================================================================
    // Configuration registers
    // ========================================================================
    reg [8:0] ctrl_r;
    reg [15:0] clkdiv_r;
    reg [NUM_CS-1:0] csmask_r;
    reg [5:0] bits_r;
    reg [4:0] mode_r;
    reg [11:0] cmd_r;
    reg [1:0] ie_r;

    wire [31:0] ctrl_merged_w;
    wire [31:0] clkdiv_merged_w;
    wire [31:0] csmask_merged_w;
    wire [31:0] bits_merged_w;
    wire [31:0] mode_merged_w;
    wire [31:0] cmd_merged_w;
    wire [31:0] ie_merged_w;
    wire [22:0] unused_ctrl_merged_upper_w;
    wire [15:0] unused_clkdiv_merged_upper_w;
    wire [32-NUM_CS-1:0] unused_csmask_merged_upper_w;
    wire [25:0] unused_bits_merged_upper_w;
    wire [26:0] unused_mode_merged_upper_w;
    wire [19:0] unused_cmd_merged_upper_w;
    wire [29:0] unused_ie_merged_upper_w;
    wire fifo_clear_w;

    assign ctrl_merged_w =
        apply_strobe({23'b0, ctrl_r}, pwdata_i, pstrb_i);
    assign clkdiv_merged_w =
        apply_strobe({16'b0, clkdiv_r}, pwdata_i, pstrb_i);
    assign csmask_merged_w =
        apply_strobe({{(32-NUM_CS){1'b0}}, csmask_r},
                     pwdata_i, pstrb_i);
    assign bits_merged_w =
        apply_strobe({26'b0, bits_r}, pwdata_i, pstrb_i);
    assign mode_merged_w =
        apply_strobe({27'b0, mode_r}, pwdata_i, pstrb_i);
    assign cmd_merged_w =
        apply_strobe({20'b0, cmd_r}, pwdata_i, pstrb_i);
    assign ie_merged_w =
        apply_strobe({30'b0, ie_r}, pwdata_i, pstrb_i);
    assign unused_ctrl_merged_upper_w = ctrl_merged_w[31:9];
    assign unused_clkdiv_merged_upper_w = clkdiv_merged_w[31:16];
    assign unused_csmask_merged_upper_w =
        csmask_merged_w[31:NUM_CS];
    assign unused_bits_merged_upper_w = bits_merged_w[31:6];
    assign unused_mode_merged_upper_w = mode_merged_w[31:5];
    assign unused_cmd_merged_upper_w = cmd_merged_w[31:12];
    assign unused_ie_merged_upper_w = ie_merged_w[31:2];
    assign fifo_clear_w =
        write_access_w & (offset_w == `SPI_CTRL) &
        pstrb_i[0] & pwdata_i[`SPI_CTRL_FIFO_CLR];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctrl_r <= 9'b0;
            clkdiv_r <= DEFAULT_CLKDIV;
            csmask_r <= {NUM_CS{1'b0}};
            bits_r <= 6'd8;
            mode_r <= 5'b0;
            cmd_r <= 12'b0;
            ie_r <= 2'b0;
        end else if (write_access_w) begin
            case (offset_w)
                `SPI_CTRL:
                    ctrl_r <= ctrl_merged_w[8:0] &
                              CTRL_STORAGE_MASK &
                              ~(9'b1 << `SPI_CTRL_FIFO_CLR);
                `SPI_CLKDIV:
                    clkdiv_r <= clkdiv_merged_w[15:0];
                `SPI_CSMASK:
                    csmask_r <= csmask_merged_w[NUM_CS-1:0];
                `SPI_BITS:
                    bits_r <= bits_merged_w[5:0];
                `SPI_IE:
                    ie_r <= ie_merged_w[1:0] & IP_VALID_MASK;
                `SPI_MODE:
                    mode_r <= mode_merged_w[4:0];
                `SPI_CMD:
                    cmd_r <= cmd_merged_w[11:0];
                default: begin
                end
            endcase
        end
    end

    wire ctrl_en_w;
    wire ctrl_cpol_w;
    wire ctrl_cpha_w;
    wire ctrl_lsb_w;
    wire ctrl_half_w;
    wire ctrl_half_dir_w;
    wire ctrl_cs_auto_w;
    wire [1:0] bus_width_w;
    wire cmd_phase_enable_w;
    wire [5:0] data_bits_w;
    wire [3:0] command_bits_w;
    wire [2:0] data_lanes_w;

    assign ctrl_en_w = ctrl_r[`SPI_CTRL_EN];
    assign ctrl_cpol_w = ctrl_r[`SPI_CTRL_CPOL];
    assign ctrl_cpha_w = ctrl_r[`SPI_CTRL_CPHA];
    assign ctrl_lsb_w = ctrl_r[`SPI_CTRL_LSB];
    assign ctrl_half_w = ctrl_r[`SPI_CTRL_HALF];
    assign ctrl_half_dir_w = ctrl_r[`SPI_CTRL_HALF_DIR];
    assign ctrl_cs_auto_w = ctrl_r[`SPI_CTRL_CS_AUTO];
    assign bus_width_w =
        mode_r[`SPI_MODE_WIDTH_MSB:`SPI_MODE_WIDTH_LSB];
    assign cmd_phase_enable_w = mode_r[`SPI_MODE_CMD_PHASE];
    assign data_bits_w = (bits_r == 0) ? 6'd32 : bits_r;
    assign command_bits_w =
        (cmd_r[`SPI_CMD_BITS_MSB:`SPI_CMD_BITS_LSB] == 0)
        ? 4'd8
        : cmd_r[`SPI_CMD_BITS_MSB:`SPI_CMD_BITS_LSB];
    assign data_lanes_w =
        (bus_width_w == `SPI_MODE_QUAD) ? 3'd4 :
        (bus_width_w == `SPI_MODE_DUAL) ? 3'd2 :
                                         3'd1;

    // ========================================================================
    // FIFOs
    // ========================================================================
    wire [31:0] tx_head_w;
    wire [31:0] rx_head_w;
    wire tx_full_w;
    wire tx_empty_w;
    wire rx_full_w;
    wire rx_empty_w;
    wire [$clog2(FIFO_DEPTH):0] tx_count_w;
    wire [$clog2(FIFO_DEPTH):0] rx_count_w;
    wire tx_push_request_w;
    wire tx_push_w;
    wire tx_pop_w;
    wire rx_pop_request_w;
    wire rx_pop_w;
    wire rx_push_w;
    wire [31:0] tx_write_data_w;
    wire [31:0] rx_push_data_w;

    assign tx_push_request_w =
        write_access_w & (offset_w == `SPI_TXDATA);
    assign tx_push_w = tx_push_request_w & ~tx_full_w;
    assign tx_write_data_w =
        apply_strobe(32'b0, pwdata_i, pstrb_i);
    assign rx_pop_request_w =
        read_access_w & (offset_w == `SPI_RXDATA);
    assign rx_pop_w = rx_pop_request_w & ~rx_empty_w;

    sync_fifo #(
        .WIDTH(32),
        .DEPTH(FIFO_DEPTH)
    ) u_sync_fifo_tx (
        // --- Clock and reset ---
        .clk     (clk),
        .rst_n   (rst_n),

        // --- Control ---
        .flush_i (fifo_clear_w),
        .push_i  (tx_push_w),
        .wdata_i (tx_write_data_w),
        .pop_i   (tx_pop_w),

        // --- Data and status ---
        .rdata_o (tx_head_w),
        .full_o  (tx_full_w),
        .empty_o (tx_empty_w),
        .count_o (tx_count_w)
    );

    sync_fifo #(
        .WIDTH(32),
        .DEPTH(FIFO_DEPTH)
    ) u_sync_fifo_rx (
        // --- Clock and reset ---
        .clk     (clk),
        .rst_n   (rst_n),

        // --- Control ---
        .flush_i (fifo_clear_w),
        .push_i  (rx_push_w),
        .wdata_i (rx_push_data_w),
        .pop_i   (rx_pop_w),

        // --- Data and status ---
        .rdata_o (rx_head_w),
        .full_o  (rx_full_w),
        .empty_o (rx_empty_w),
        .count_o (rx_count_w)
    );

    // ========================================================================
    // Edge-driven transfer engine
    // ========================================================================
    reg busy_r;
    reg command_phase_r;
    reg [5:0] bit_position_r;
    reg [31:0] tx_word_r;
    reg [31:0] rx_word_r;
    reg [15:0] sclk_count_r;
    reg sclk_r;

    wire config_valid_w;
    wire start_request_w;
    wire edge_tick_w;
    wire leading_edge_w;
    wire trailing_edge_w;
    wire sample_edge_w;
    wire [5:0] phase_bits_w;
    wire [2:0] phase_lanes_w;
    wire [5:0] remaining_bits_w;
    wire [2:0] group_bits_w;
    wire [4:0] phase_last_index_w;
    wire final_group_w;
    wire data_receive_w;
    wire complete_w;
    wire continue_w;
    reg [31:0] rx_sample_data_w;
    integer sample_lane;
    reg [4:0] sample_index;
    reg [1:0] sample_io;

    assign config_valid_w =
        (bus_width_w != 2'b11) &
        ((bus_width_w == `SPI_MODE_SINGLE) | ctrl_half_w) &
        (data_bits_w >= 1) & (data_bits_w <= 32) &
        (command_bits_w >= 1) & (command_bits_w <= 8) &
        (|csmask_r);
    assign start_request_w =
        ctrl_en_w & ~busy_r & ~tx_empty_w;
    assign edge_tick_w =
        busy_r & (sclk_count_r == 0);
    assign leading_edge_w =
        edge_tick_w & (sclk_r == ctrl_cpol_w);
    assign trailing_edge_w =
        edge_tick_w & (sclk_r != ctrl_cpol_w);
    assign sample_edge_w =
        ctrl_cpha_w ? trailing_edge_w : leading_edge_w;
    assign phase_bits_w =
        command_phase_r ? {2'b0, command_bits_w} : data_bits_w;
    assign phase_lanes_w =
        command_phase_r ? 3'd1 : data_lanes_w;
    assign remaining_bits_w = phase_bits_w - bit_position_r;
    assign phase_last_index_w = phase_bits_w[4:0] - 5'd1;
    assign group_bits_w =
        (remaining_bits_w < {3'b0, phase_lanes_w})
        ? remaining_bits_w[2:0]
        : phase_lanes_w;
    assign final_group_w =
        (remaining_bits_w <= {3'b0, phase_lanes_w});
    assign data_receive_w =
        ~command_phase_r &
        ((~ctrl_half_w & (bus_width_w == `SPI_MODE_SINGLE)) |
         (ctrl_half_w & ~ctrl_half_dir_w));
    assign complete_w =
        trailing_edge_w & ~command_phase_r & final_group_w;
    assign continue_w =
        complete_w & ~tx_empty_w & config_valid_w;
    assign tx_pop_w =
        (start_request_w & config_valid_w) | continue_w |
        (start_request_w & ~config_valid_w);
    assign rx_push_w =
        complete_w & data_receive_w & ~rx_full_w;
    assign rx_push_data_w = rx_sample_data_w;

    always @* begin
        rx_sample_data_w = rx_word_r;
        sample_index = 0;
        sample_io = 0;
        if (sample_edge_w & data_receive_w) begin
            for (sample_lane = 0; sample_lane < 4;
                 sample_lane = sample_lane + 1) begin
                if (sample_lane < group_bits_w) begin
                    sample_io =
                        ((~ctrl_half_w) &
                         (bus_width_w == `SPI_MODE_SINGLE))
                        ? 2'd1
                        : sample_lane[1:0];
                    if (ctrl_lsb_w)
                        sample_index =
                            bit_position_r[4:0] +
                            sample_lane[4:0];
                    else
                        sample_index =
                            phase_last_index_w -
                            bit_position_r[4:0] -
                            sample_lane[4:0];
                    rx_sample_data_w[sample_index] = io_i[sample_io];
                end
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy_r <= 1'b0;
            command_phase_r <= 1'b0;
            bit_position_r <= 6'b0;
            tx_word_r <= 32'b0;
            rx_word_r <= 32'b0;
        end else begin
            if (sample_edge_w & data_receive_w)
                rx_word_r <= rx_sample_data_w;

            if (start_request_w) begin
                if (config_valid_w) begin
                    busy_r <= 1'b1;
                    command_phase_r <= cmd_phase_enable_w;
                    bit_position_r <= 6'b0;
                    tx_word_r <= tx_head_w;
                    rx_word_r <= 32'b0;
                end else begin
                    busy_r <= 1'b0;
                end
            end else if (trailing_edge_w) begin
                if (final_group_w) begin
                    if (command_phase_r) begin
                        command_phase_r <= 1'b0;
                        bit_position_r <= 6'b0;
                    end else if (continue_w) begin
                        busy_r <= 1'b1;
                        command_phase_r <= cmd_phase_enable_w;
                        bit_position_r <= 6'b0;
                        tx_word_r <= tx_head_w;
                        rx_word_r <= 32'b0;
                    end else begin
                        busy_r <= 1'b0;
                        bit_position_r <= 6'b0;
                    end
                end else begin
                    bit_position_r <=
                        bit_position_r + {3'b0, group_bits_w};
                end
            end

            if (~ctrl_en_w)
                busy_r <= 1'b0;
            if (fifo_clear_w) begin
                busy_r <= 1'b0;
                command_phase_r <= 1'b0;
                bit_position_r <= 6'b0;
                rx_word_r <= 32'b0;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sclk_count_r <= 16'b0;
            sclk_r <= 1'b0;
        end else if (~busy_r) begin
            sclk_count_r <= clkdiv_r;
            sclk_r <= ctrl_cpol_w;
        end else if (sclk_count_r == 0) begin
            sclk_count_r <= clkdiv_r;
            sclk_r <= ~sclk_r;
        end else begin
            sclk_count_r <= sclk_count_r - 1'b1;
        end
    end

    // ========================================================================
    // Pin drive and chip selects
    // ========================================================================
    integer drive_lane;
    reg [4:0] drive_index;
    reg [4:0] drive_last_index_w;
    reg [31:0] drive_source_w;
    reg drive_enable_w;

    always @* begin
        io_o = 4'b0;
        io_oe_o = 4'b0;
        drive_source_w = command_phase_r
            ? {24'b0, cmd_r[`SPI_CMD_DATA_MSB:`SPI_CMD_DATA_LSB]}
            : tx_word_r;
        drive_last_index_w = command_phase_r
            ? ({1'b0, command_bits_w} - 5'd1)
            : (data_bits_w[4:0] - 5'd1);
        drive_enable_w =
            busy_r &
            (command_phase_r |
             ((~ctrl_half_w) &
              (bus_width_w == `SPI_MODE_SINGLE)) |
             (ctrl_half_w & ctrl_half_dir_w));
        drive_index = 0;

        if (drive_enable_w) begin
            for (drive_lane = 0; drive_lane < 4;
                 drive_lane = drive_lane + 1) begin
                if (drive_lane < phase_lanes_w) begin
                    io_oe_o[drive_lane] = 1'b1;
                    if (drive_lane < group_bits_w) begin
                        if (ctrl_lsb_w)
                            drive_index =
                                bit_position_r[4:0] +
                                drive_lane[4:0];
                        else
                            drive_index =
                                drive_last_index_w -
                                bit_position_r[4:0] -
                                drive_lane[4:0];
                        io_o[drive_lane] =
                            drive_source_w[drive_index];
                    end
                end
            end
        end
    end

    assign sclk_o = busy_r ? sclk_r : ctrl_cpol_w;
    assign cs_n_o =
        ~ctrl_en_w ? {NUM_CS{1'b1}} :
        ctrl_cs_auto_w
            ? (busy_r ? ~csmask_r : {NUM_CS{1'b1}})
            : ~csmask_r;

    // ========================================================================
    // Sticky status and interrupt pending
    // ========================================================================
    reg done_status_r;
    reg mode_fault_r;
    reg tx_overflow_r;
    reg rx_underflow_r;
    reg rx_overflow_r;
    reg [1:0] ip_r;
    wire mode_fault_event_w;
    wire tx_overflow_event_w;
    wire rx_underflow_event_w;
    wire rx_overflow_event_w;
    wire error_event_w;
    wire [1:0] ip_clear_w;

    assign mode_fault_event_w =
        start_request_w & ~config_valid_w;
    assign tx_overflow_event_w =
        tx_push_request_w & tx_full_w;
    assign rx_underflow_event_w =
        rx_pop_request_w & rx_empty_w;
    assign rx_overflow_event_w =
        complete_w & data_receive_w & rx_full_w;
    assign error_event_w =
        mode_fault_event_w | tx_overflow_event_w |
        rx_underflow_event_w | rx_overflow_event_w;
    assign ip_clear_w =
        (write_access_w & (offset_w == `SPI_IP))
        ? (pwdata_i[1:0] &
           {pstrb_i[0], pstrb_i[0]})
        : 2'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done_status_r <= 1'b0;
            mode_fault_r <= 1'b0;
            tx_overflow_r <= 1'b0;
            rx_underflow_r <= 1'b0;
            rx_overflow_r <= 1'b0;
            ip_r <= 2'b0;
        end else begin
            if (start_request_w & config_valid_w)
                done_status_r <= 1'b0;
            if (complete_w)
                done_status_r <= 1'b1;
            if (mode_fault_event_w)
                mode_fault_r <= 1'b1;
            if (tx_overflow_event_w)
                tx_overflow_r <= 1'b1;
            if (rx_underflow_event_w)
                rx_underflow_r <= 1'b1;
            if (rx_overflow_event_w)
                rx_overflow_r <= 1'b1;

            ip_r <= (ip_r & ~ip_clear_w) |
                    {error_event_w, complete_w};

            if (fifo_clear_w) begin
                done_status_r <= 1'b0;
                mode_fault_r <= 1'b0;
                tx_overflow_r <= 1'b0;
                rx_underflow_r <= 1'b0;
                rx_overflow_r <= 1'b0;
            end
        end
    end

    assign irq_o = |(ip_r & ie_r);

    // ========================================================================
    // APB readback
    // ========================================================================
    always @* begin
        prdata_o = 32'b0;
        case (offset_w)
            `SPI_CTRL:
                prdata_o = {23'b0, ctrl_r};
            `SPI_STATUS: begin
                prdata_o[`SPI_STATUS_BUSY] = busy_r;
                prdata_o[`SPI_STATUS_DONE] = done_status_r;
                prdata_o[`SPI_STATUS_TX_EMPTY] = tx_empty_w;
                prdata_o[`SPI_STATUS_TX_FULL] = tx_full_w;
                prdata_o[`SPI_STATUS_RX_EMPTY] = rx_empty_w;
                prdata_o[`SPI_STATUS_RX_FULL] = rx_full_w;
                prdata_o[`SPI_STATUS_MODE_FAULT] = mode_fault_r;
                prdata_o[`SPI_STATUS_TX_OVERFLOW] = tx_overflow_r;
                prdata_o[`SPI_STATUS_RX_UNDERFLOW] = rx_underflow_r;
                prdata_o[`SPI_STATUS_RX_OVERFLOW] = rx_overflow_r;
            end
            `SPI_TXDATA:
                prdata_o = 32'b0;
            `SPI_RXDATA:
                prdata_o = rx_empty_w ? 32'b0 : rx_head_w;
            `SPI_CLKDIV:
                prdata_o = {16'b0, clkdiv_r};
            `SPI_CSMASK:
                prdata_o = {{(32-NUM_CS){1'b0}}, csmask_r};
            `SPI_BITS:
                prdata_o = {26'b0, bits_r};
            `SPI_IP:
                prdata_o = {30'b0, ip_r};
            `SPI_IE:
                prdata_o = {30'b0, ie_r};
            `SPI_MODE:
                prdata_o = {27'b0, mode_r};
            `SPI_CMD:
                prdata_o = {20'b0, cmd_r};
            default:
                prdata_o = 32'b0;
        endcase
    end

    wire unused_fifo_counts_w;
    assign unused_fifo_counts_w =
        ^tx_count_w ^ ^rx_count_w;

endmodule
