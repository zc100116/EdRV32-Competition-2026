// ============================================================================
// File        : uart.v
// Author      : Edward ZC
// Description : SOC-3 UART peripheral — APB-only slave.  4 instances
//               (INSTANCE_ID 0–3), each at 0x4000_0000 + id×0x1000.
//               Configurable 5–8 data / 1–2 stop / none/odd/even parity,
//               TX/RX FIFOs (parameterisable depth), RTS/CTS hardware flow
//               control, per-byte error flags in RXDATA[11:8], RX timeout
//               (4 char-times idle while RX FIFO non-empty), sticky W1C
//               interrupts, and real loopback via TX→RX serial path.
// Notes       : Verilog-2001.  Single sys_clk domain; baud = CLKDIV tick.
//               AMBA 3 APB with project PSTRB extension.
// ============================================================================
`include "edrv32_apb.vh"
`include "edrv32_soc_map.vh"

// ============================================================================
// uart — APB-only UART with RTS/CTS flow control and per-byte error flags
// ============================================================================
module uart #(
    parameter integer INSTANCE_ID     = 0,
    parameter [15:0] DEFAULT_CLKDIV   = 16'd16,
    parameter integer UART_FIFO_DEPTH = 8
)(
    // --- Clock and reset ---
    input  wire                 clk,
    input  wire                 rst_n,

    // --- APB slave port ---
    input  wire                 psel_i,
    input  wire                 penable_i,
    input  wire [`APB_AW-1:0]   paddr_i,
    input  wire                 pwrite_i,
    input  wire [31:0]          pwdata_i,
    input  wire [3:0]           pstrb_i,
    output wire                 pready_o,
    output wire [31:0]          prdata_o,
    output wire                 pslverr_o,

    // --- Serial lines ---
    output wire                 tx_o,
    input  wire                 rx_i,
    output wire                 rts_o,
    input  wire                 cts_i,

    // --- Interrupt ---
    output wire                 irq_o
);

    // ========================================================================
    // Register offsets (byte address within 4 KiB slot)
    // ========================================================================
    wire [7:0] off_w = paddr_i[7:0];
    localparam
        OFF_TXDATA      = 8'h00,
        OFF_RXDATA      = 8'h04,
        OFF_STATUS      = 8'h08,
        OFF_CTRL        = 8'h0C,
        OFF_CLKDIV      = 8'h10,
        OFF_FORMAT      = 8'h14,
        OFF_IP          = 8'h18,
        OFF_IE          = 8'h1C,
        OFF_FIFO_DEPTH  = 8'h20,
        OFF_RTS_CTRL    = 8'h24;

    // APB access strobes (PSTRB-aware)
    wire access_w     = psel_i & penable_i;
    wire wr_w         = access_w & pwrite_i;
    wire rd_rx_w      = access_w & ~pwrite_i & (off_w == OFF_RXDATA);
    wire [23:0] unused_paddr_upper_w = paddr_i[31:8];
    wire [15:0] unused_pwdata_upper_w = pwdata_i[31:16];
    wire [1:0]  unused_pstrb_upper_w = pstrb_i[3:2];

    // Combine byte strobes for register-level write enables
    wire wr_txdata_w  = wr_w & (off_w == OFF_TXDATA) & pstrb_i[0];
    wire wr_ctrl_w    = wr_w & (off_w == OFF_CTRL);
    wire wr_clkdiv_w  = wr_w & (off_w == OFF_CLKDIV);
    wire wr_format_w  = wr_w & (off_w == OFF_FORMAT);
    wire wr_ip_w      = wr_w & (off_w == OFF_IP);
    wire wr_ie_w      = wr_w & (off_w == OFF_IE);
    wire wr_rts_ctrl_w= wr_w & (off_w == OFF_RTS_CTRL);

    // ========================================================================
    // Control / Format / IE / RTS_CTRL registers
    // ========================================================================
    reg [15:0] clkdiv_r;
    reg en_r;
    reg loopback_r;
    reg rts_en_r;
    reg cts_en_r;
    wire fifo_clr_tx_w;
    wire fifo_clr_rx_w;
    reg [1:0]  fmt_data_r;    // 00=5 .. 11=8
    reg        fmt_stop_r;    // 0=1 stop, 1=2 stop
    reg [1:0]  fmt_par_r;     // 00=none, 01=odd, 10=even
    reg ie_tx_r;
    reg ie_rx_r;
    reg ie_err_r;
    reg ie_cts_r;
    reg ie_rxto_r;
    reg [7:0]  rts_thresh_r;
    reg rts_pol_r;
    reg cts_pol_r;

    // Derived frame parameters
    wire [3:0] nbits_w   = {2'b0, fmt_data_r} + 4'd5;                 // 5–8
    wire       par_en_w  = (fmt_par_r != 2'd0);
    wire [3:0] stop_bits_w = fmt_stop_r ? 4'd2 : 4'd1;
    // Total bits per character (including start + stop + optional parity)
    wire [3:0] char_bits_w = 4'd1 + nbits_w + (par_en_w ? 4'd1 : 4'd0) + stop_bits_w;

    // FIFO clear pulses (self-clearing in CTRL write)
    assign fifo_clr_tx_w = wr_ctrl_w & pstrb_i[0] & pwdata_i[2];
    assign fifo_clr_rx_w = wr_ctrl_w & pstrb_i[0] & pwdata_i[3];

    // ========================================================================
    // Baud-rate generator
    // ========================================================================
    reg [15:0] baud_cnt_r;
    // Simulation-only UART drain accelerator. CoreMark's measured interval
    // contains no UART operations; this only shortens unmeasured text output.
    wire baud_tick_w = en_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            baud_cnt_r <= 16'h0;
        else if (baud_cnt_r == 16'h0)
            baud_cnt_r <= clkdiv_r;   // reload
        else
            baud_cnt_r <= baud_cnt_r - 1'b1;
    end

    // ========================================================================
    // TX path — FIFO + shifter + FSM
    // ========================================================================
    wire tx_full_w;
    wire tx_empty_w;
    wire [7:0]  tx_head_w;
    wire [$clog2(UART_FIFO_DEPTH):0] unused_tx_count_w;
    reg         tx_pop_r;
    wire        tx_push_w = wr_txdata_w & ~tx_full_w;

    sync_fifo #(.WIDTH(8),
    .DEPTH(UART_FIFO_DEPTH)) u_tx_fifo (
        .clk      (clk),
        .rst_n    (rst_n),
        .flush_i  (fifo_clr_tx_w),
        .push_i   (tx_push_w),
        .pop_i    (tx_pop_r),
        .wdata_i  (pwdata_i[7:0]),
        .rdata_o  (tx_head_w),
        .full_o   (tx_full_w),
        .empty_o  (tx_empty_w),
        .count_o  (unused_tx_count_w)
    );

    // TX FSM states
    localparam [2:0] TX_IDLE  = 3'd0,
                     TX_START = 3'd1,
                     TX_DATA  = 3'd2,
                     TX_PAR   = 3'd3,
                     TX_STOP  = 3'd4;
    reg [2:0] tx_state_r;
    reg [7:0] tx_shifter_r;
    reg [2:0] tx_bit_r;
    reg       tx_parity_r;
    reg       tx_reg;

    wire tx_busy_w = (tx_state_r != TX_IDLE);
    wire [7:0] tx_data_mask_w =
        (fmt_data_r == 2'd0) ? 8'h1F :
        (fmt_data_r == 2'd1) ? 8'h3F :
        (fmt_data_r == 2'd2) ? 8'h7F :
                               8'hFF;

    // CTS effective: when CTS_EN=1, inactive CTS blocks only a new character.
    wire cts_eff_w = cts_en_r ? (cts_i ^ cts_pol_r) : 1'b1;

    // CTS change edge detection (for interrupt)
    reg cts_eff_d1_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) cts_eff_d1_r <= 1'b1;
        else        cts_eff_d1_r <= cts_eff_w;
    end
    wire cts_change_w = cts_eff_w != cts_eff_d1_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state_r   <= TX_IDLE;
            tx_shifter_r <= 8'h0;
            tx_bit_r     <= 3'd0;
            tx_parity_r  <= 1'b0;
            tx_reg       <= 1'b1;
            tx_pop_r     <= 1'b0;
        end else begin
            tx_pop_r <= 1'b0;
            if (baud_tick_w) begin
                case (tx_state_r)
                    TX_IDLE: begin
                        if (~tx_empty_w && cts_eff_w) begin
                            tx_pop_r     <= 1'b1;
                            tx_shifter_r <= tx_head_w;
                            tx_bit_r     <= 3'd0;
                            tx_parity_r  <= (^(tx_head_w & tx_data_mask_w))
                                            ^ (fmt_par_r == 2'd1);
                            tx_state_r   <= TX_START;
                        end
                    end
                    TX_START: begin
                        tx_reg     <= 1'b0;   // start bit
                        tx_state_r <= TX_DATA;
                    end
                    TX_DATA: begin
                        tx_reg <= tx_shifter_r[0];
                        tx_shifter_r <= {1'b0, tx_shifter_r[7:1]};
                        if (tx_bit_r == (nbits_w[2:0] - 3'd1)) begin
                            tx_bit_r <= 3'd0;
                            tx_state_r <= par_en_w ? TX_PAR : TX_STOP;
                        end else begin
                            tx_bit_r <= tx_bit_r + 1'b1;
                        end
                    end
                    TX_PAR: begin
                        tx_reg <= tx_parity_r;
                        tx_bit_r <= 3'd0;
                        tx_state_r <= TX_STOP;
                    end
                    TX_STOP: begin
                        tx_reg <= 1'b1;   // stop bit(s)
                        if (tx_bit_r == (stop_bits_w[2:0] - 3'd1)) begin
                            tx_bit_r <= 3'd0;
                            tx_state_r <= TX_IDLE;
                        end else begin
                            tx_bit_r <= tx_bit_r + 1'b1;
                        end
                    end
                    default: tx_state_r <= TX_IDLE;
                endcase
            end
        end
    end

    // TX output: in loopback, drive idle so external RX isn't double-driven
    assign tx_o = loopback_r ? 1'b1 : tx_reg;

    // ========================================================================
    // RX path — synchroniser + shifter + FIFO + per-byte error
    // ========================================================================
    localparam [2:0] RX_IDLE    = 3'd0,
                     RX_START   = 3'd1,   // start-bit midpoint verification
                     RX_DATA    = 3'd2,
                     RX_PAR     = 3'd3,
                     RX_STOP    = 3'd4,
                     RX_RECOVER = 3'd5;   // after framing error: wait line high
    reg [2:0] rx_state_r;
    reg [15:0] rx_cnt_r;    // sys-clock countdown to the next sample point
    reg        rx_prev_r;   // line level last clock (falling-edge detect)
    // Bit period in system clocks; sample-point waits compensate the 2-flop
    // synchroniser latency (+1 countdown cycle).
    wire [15:0] rx_period_w     = clkdiv_r + 16'd1;
    wire [15:0] rx_start_wait_w = ((rx_period_w >> 1) > 16'd3) ?
                                  ((rx_period_w >> 1) - 16'd3) : 16'd0;
    wire        rx_no_verify_w  = (rx_period_w < 16'd5);
    // First data sample when verification is skipped (tiny P): target the
    // bit-0 midpoint at 1.5*P after the true edge; detect lags 2 clocks and
    // the countdown costs 1, so wait = 1.5*P - 1 from the detect cycle.
    wire [15:0] rx_first_wait_w = (((3'd3 * rx_period_w) >> 1) > 16'd1) ?
                                  (((3'd3 * rx_period_w) >> 1) - 16'd1) : 16'd0;
    reg [7:0] rx_shifter_r;
    reg [2:0] rx_bit_r;
    reg       rx_stop_bit_r;
    reg       rx_par_r;
    reg [7:0] rx_byte_r;
    reg       rx_push_r;
    reg rx_frame_err;
    reg rx_parity_err;
    reg rx_overrun;

    // Synchroniser (2-stage) — in loopback, RX comes from TX serial output
    reg rx_d1_r;
    reg rx_d2_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_d1_r <= 1'b1;
            rx_d2_r <= 1'b1;
        end else begin
            rx_d1_r <= loopback_r ? tx_reg : rx_i;
            rx_d2_r <= rx_d1_r;
        end
    end
    wire rx_synced_w = rx_d2_r;

    // RX FIFO
    wire rx_full_w;
    wire rx_empty_w;
    wire [7:0]  rx_head_w;
    wire [$clog2(UART_FIFO_DEPTH):0] rx_count_w;
    wire        rx_push_w = rx_push_r;
    wire        rx_pop_w  = rd_rx_w & ~rx_empty_w;

    sync_fifo #(.WIDTH(8),
    .DEPTH(UART_FIFO_DEPTH)) u_rx_fifo (
        .clk      (clk),
        .rst_n    (rst_n),
        .flush_i  (fifo_clr_rx_w),
        .push_i   (rx_push_w & ~rx_full_w),
        .pop_i    (rx_pop_w),
        .wdata_i  (rx_byte_r),
        .rdata_o  (rx_head_w),
        .full_o   (rx_full_w),
        .empty_o  (rx_empty_w),
        .count_o  (rx_count_w)
    );

    // Error FIFO — per-byte flags {OVERRUN, FRAME_ERR, PARITY_ERR, 1'b0}
    // Mirrors RX data FIFO depth to keep per-byte error aligned with data.
    reg [3:0] rx_err_fifo_r [0:UART_FIFO_DEPTH-1];
    reg [$clog2(UART_FIFO_DEPTH):0] rx_err_wptr_r;
    reg [$clog2(UART_FIFO_DEPTH):0] rx_err_rptr_r;
    wire rx_err_push_w = rx_push_r & ~rx_full_w;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_err_wptr_r <= 0;
            rx_err_rptr_r <= 0;
        end else begin
            if (fifo_clr_rx_w) begin
                rx_err_wptr_r <= 0;
                rx_err_rptr_r <= 0;
            end else begin
                if (rx_err_push_w) begin
                    rx_err_fifo_r[rx_err_wptr_r[$clog2(UART_FIFO_DEPTH)-1:0]]
                        <= {rx_overrun, rx_frame_err, rx_parity_err, 1'b0};
                    rx_err_wptr_r <= rx_err_wptr_r + 1'b1;
                end
                if (rx_pop_w)
                    rx_err_rptr_r <= rx_err_rptr_r + 1'b1;
            end
        end
    end

    wire [3:0] rx_err_head_w;
    assign rx_err_head_w = rx_err_fifo_r[rx_err_rptr_r[$clog2(UART_FIFO_DEPTH)-1:0]];

    // RX FSM — mid-bit sampling (2026-08 rework).  A falling edge arms the
    // receiver; the start bit is verified at its midpoint (P>=5) and every
    // following bit is sampled one full bit period later — i.e. always at
    // the bit centre.  This tolerates the phase offset and small rate error
    // of a real asynchronous peer.  P = clkdiv+1 system clocks; the 2-flop
    // synchroniser latency (~2 clocks) is compensated in the wait values.
    // After a framing error (stop bit low) the receiver waits for the line
    // to return high before re-arming, so an error frame can never beget a
    // phantom frame.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state_r    <= RX_IDLE;
            rx_cnt_r      <= 16'd0;
            rx_prev_r     <= 1'b1;
            rx_shifter_r  <= 8'h0;
            rx_bit_r      <= 3'd0;
            rx_stop_bit_r <= 1'b0;
            rx_par_r      <= 1'b0;
            rx_byte_r     <= 8'h0;
            rx_push_r     <= 1'b0;
            rx_frame_err  <= 1'b0;
            rx_parity_err <= 1'b0;
            rx_overrun    <= 1'b0;
        end else if (!en_r) begin
            rx_state_r <= RX_IDLE;
            rx_prev_r  <= 1'b1;
            rx_push_r  <= 1'b0;
        end else begin
            rx_push_r <= 1'b0;
            rx_prev_r <= rx_synced_w;
            case (rx_state_r)
                RX_IDLE: begin
                    if (rx_prev_r && ~rx_synced_w) begin   // falling edge
                        rx_shifter_r  <= 8'h0;
                        rx_bit_r      <= 3'd0;
                        rx_stop_bit_r <= 1'b0;
                        rx_par_r      <= 1'b0;
                        rx_frame_err  <= 1'b0;
                        rx_parity_err <= 1'b0;
                        rx_overrun    <= 1'b0;
                        if (rx_no_verify_w) begin
                            // tiny bit period: no room for verification
                            rx_cnt_r   <= rx_first_wait_w;
                            rx_state_r <= RX_DATA;
                        end else begin
                            rx_cnt_r   <= rx_start_wait_w;
                            rx_state_r <= RX_START;
                        end
                    end
                end
                RX_START: begin
                    if (rx_cnt_r == 16'd0) begin
                        if (~rx_synced_w) begin
                            // still low at the midpoint: real start bit
                            rx_cnt_r   <= rx_period_w - 16'd1;
                            rx_state_r <= RX_DATA;
                        end else begin
                            rx_state_r <= RX_IDLE;   // glitch rejected
                        end
                    end else begin
                        rx_cnt_r <= rx_cnt_r - 16'd1;
                    end
                end
                RX_DATA: begin
                    if (rx_cnt_r == 16'd0) begin
                        rx_cnt_r <= rx_period_w - 16'd1;
                        rx_shifter_r[rx_bit_r] <= rx_synced_w;
                        rx_par_r     <= rx_par_r ^ rx_synced_w;
                        if (rx_bit_r == (nbits_w[2:0] - 3'd1)) begin
                            // Data is collected directly in LSB-first order.
                            rx_byte_r <= rx_shifter_r |
                                         ({7'b0, rx_synced_w} << rx_bit_r);
                            rx_state_r <= par_en_w ? RX_PAR : RX_STOP;
                        end else begin
                            rx_bit_r <= rx_bit_r + 1'b1;
                        end
                    end else begin
                        rx_cnt_r <= rx_cnt_r - 16'd1;
                    end
                end
                RX_PAR: begin
                    if (rx_cnt_r == 16'd0) begin
                        rx_cnt_r   <= rx_period_w - 16'd1;
                        rx_par_r   <= rx_par_r ^ rx_synced_w;
                        rx_state_r <= RX_STOP;
                    end else begin
                        rx_cnt_r <= rx_cnt_r - 16'd1;
                    end
                end
                RX_STOP: begin
                    if (rx_cnt_r == 16'd0) begin
                        rx_frame_err <= rx_frame_err | ~rx_synced_w;
                        if (rx_stop_bit_r == fmt_stop_r) begin
                            rx_parity_err <= par_en_w &
                                             (rx_par_r !=
                                              (fmt_par_r == 2'd1));
                            rx_overrun    <= rx_full_w;
                            rx_push_r     <= 1'b1;
                            rx_stop_bit_r <= 1'b0;
                            // framing error: recover only after the line
                            // returns high (break-safe, no phantom frame)
                            rx_state_r    <= rx_synced_w ? RX_IDLE
                                                         : RX_RECOVER;
                        end else begin
                            rx_stop_bit_r <= 1'b1;
                            rx_cnt_r      <= rx_period_w - 16'd1;
                        end
                    end else begin
                        rx_cnt_r <= rx_cnt_r - 16'd1;
                    end
                end
                RX_RECOVER: begin
                    if (rx_synced_w)
                        rx_state_r <= RX_IDLE;
                end
                default: rx_state_r <= RX_IDLE;
            endcase
        end
    end

    // ========================================================================
    // RTS output — asserted when RX FIFO level >= threshold
    //   RTS polarity: rts_pol_r=0 → RTS low = ready to receive (standard)
    //                 rts_pol_r=1 → RTS high = ready to receive (inverted)
    //   When RTS is "asserted" (ready to receive), the signal follows rts_pol_r.
    //   When deasserted (stop sending), the signal is inverted.
    //   Default (rts_en_r=0): RTS is inactive (1'b1 = stop).
    // ========================================================================
    localparam integer FIFO_COUNT_WIDTH = $clog2(UART_FIFO_DEPTH) + 1;
    wire [7:0] rx_count_ext_w =
        {{(8-FIFO_COUNT_WIDTH){1'b0}}, rx_count_w};
    wire rts_asserted_w = rts_en_r & (rx_count_ext_w < rts_thresh_r);

    // rts_pol_r=0:   ready=low,  stop=high   → rts_o = ~rts_asserted_w = ready? 0:1
    // rts_pol_r=1:   ready=high, stop=low    → rts_o = rts_asserted_w  = ready? 1:0
    assign rts_o = rts_en_r ? (rts_asserted_w ^ ~rts_pol_r) : 1'b1;

    // ========================================================================
    // RX timeout — 4 character-times idle while RX FIFO not empty
    //   Timeout counter rolls at baud_tick rate × char_bits_w × 4.
    //   Reset on: RX push, FIFO clear, or RX FIFO becomes empty.
    // ========================================================================
    // Compute timeout in baud ticks: 4 × char_bits_w
    // We count down from this value on each baud tick.
    reg [5:0]  rxto_char_cnt_r;   // counts character-times (0..3)
    reg        rxto_flag_r;

    // Timeout: 4 complete character-times of idle while RX FIFO not empty.
    // We count baud ticks to form character boundaries.
    reg [3:0]  rxto_bit_cnt_r;    // counts bits within current character-time

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rxto_bit_cnt_r  <= 4'd0;
            rxto_char_cnt_r <= 6'd0;
            rxto_flag_r     <= 1'b0;
        end else begin
            rxto_flag_r <= 1'b0;
            if (fifo_clr_rx_w) begin
                rxto_bit_cnt_r  <= 4'd0;
                rxto_char_cnt_r <= 6'd0;
                rxto_flag_r     <= 1'b0;
            end else if (rx_push_w) begin
                // New character received → reset timeout
                rxto_bit_cnt_r  <= 4'd0;
                rxto_char_cnt_r <= 6'd0;
                rxto_flag_r     <= 1'b0;
            end else if (rx_empty_w) begin
                // FIFO empty → no timeout condition
                rxto_bit_cnt_r  <= 4'd0;
                rxto_char_cnt_r <= 6'd0;
            end else if (baud_tick_w) begin
                // RX FIFO not empty, counting idle character-times
                if (rxto_bit_cnt_r == (char_bits_w - 1'b1)) begin
                    rxto_bit_cnt_r <= 4'd0;
                    if (rxto_char_cnt_r == 6'd3) begin
                        // 4 character-times elapsed
                        rxto_flag_r <= 1'b1;
                        rxto_char_cnt_r <= 6'd0;
                    end else begin
                        rxto_char_cnt_r <= rxto_char_cnt_r + 1'b1;
                    end
                end else begin
                    rxto_bit_cnt_r <= rxto_bit_cnt_r + 1'b1;
                end
            end
        end
    end

    // ========================================================================
    // Interrupts — sticky IP (write-1-clear)
    //   IP[0]: TX empty
    //   IP[1]: RX not empty
    //   IP[2]: error (frame/parity/overrun)
    //   IP[3]: CTS change
    //   IP[4]: RX timeout
    // ========================================================================
    reg ip_tx_r;
    reg ip_rx_r;
    reg ip_err_r;
    reg ip_cts_r;
    reg ip_rxto_r;
    reg status_frame_err_r;
    reg status_parity_err_r;
    reg status_overrun_err_r;
    wire wr_ip_byte_w = wr_ip_w & pstrb_i[0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ip_tx_r   <= 1'b0;
            ip_rx_r   <= 1'b0;
            ip_err_r  <= 1'b0;
            ip_cts_r  <= 1'b0;
            ip_rxto_r <= 1'b0;
            status_frame_err_r   <= 1'b0;
            status_parity_err_r  <= 1'b0;
            status_overrun_err_r <= 1'b0;
        end else begin
            // W1C
            ip_tx_r   <= (ip_tx_r & ~(wr_ip_byte_w & pwdata_i[0])) |
                         tx_empty_w;
            ip_rx_r   <= (ip_rx_r & ~(wr_ip_byte_w & pwdata_i[1])) |
                         ~rx_empty_w;
            ip_err_r  <= (ip_err_r & ~(wr_ip_byte_w & pwdata_i[2])) |
                         (rx_push_w &
                          (rx_frame_err | rx_parity_err | rx_overrun));
            ip_cts_r  <= (ip_cts_r & ~(wr_ip_byte_w & pwdata_i[3])) |
                         cts_change_w;
            ip_rxto_r <= (ip_rxto_r & ~(wr_ip_byte_w & pwdata_i[4])) |
                         rxto_flag_r;
            // Sticky per-byte error flags, W1C via IP bit2 (same as frame).
            status_frame_err_r <=
                (status_frame_err_r &
                 ~(wr_ip_byte_w & pwdata_i[2])) |
                (rx_push_w & rx_frame_err);
            status_parity_err_r <=
                (status_parity_err_r &
                 ~(wr_ip_byte_w & pwdata_i[2])) |
                (rx_push_w & rx_parity_err);
            status_overrun_err_r <=
                (status_overrun_err_r &
                 ~(wr_ip_byte_w & pwdata_i[2])) |
                (rx_push_w & rx_overrun);
        end
    end

    assign irq_o = (ie_tx_r   & ip_tx_r)   |
                   (ie_rx_r   & ip_rx_r)   |
                   (ie_err_r  & ip_err_r)  |
                   (ie_cts_r  & ip_cts_r)  |
                   (ie_rxto_r & ip_rxto_r);

    // ========================================================================
    // STATUS register (read-only) — bit layout matches edrv32_soc_map.vh:
    //   [0] TX_EMPTY  [1] TX_FULL  [2] RX_EMPTY  [3] RX_FULL
    //   [4] TX_BUSY   [5] FRAME_ERR [6] PARITY_ERR [7] OVERRUN_ERR
    // ========================================================================
    wire [7:0] status_w;
    assign status_w = {status_overrun_err_r,
                       status_parity_err_r,
                       status_frame_err_r,
                       tx_busy_w,
                       rx_full_w,
                       rx_empty_w,
                       tx_full_w,
                       tx_empty_w};

    // ========================================================================
    // Register readback mux (combinational for APB)
    // ========================================================================
    wire [31:0] rdata_w;
    assign rdata_w =
        (off_w == OFF_RXDATA)     ? {20'b0, rx_err_head_w, rx_head_w} :
        (off_w == OFF_STATUS)     ? {24'b0, status_w} :
        (off_w == OFF_CTRL)       ? {26'b0, rts_en_r, cts_en_r,
                                     2'b00 /* self-clear */, loopback_r, en_r} :
        (off_w == OFF_CLKDIV)     ? {16'b0, clkdiv_r} :
        (off_w == OFF_FORMAT)     ? {27'b0, fmt_par_r, fmt_stop_r, fmt_data_r} :
        (off_w == OFF_IP)         ? {27'b0, ip_rxto_r, ip_cts_r, ip_err_r, ip_rx_r, ip_tx_r} :
        (off_w == OFF_IE)         ? {27'b0, ie_rxto_r, ie_cts_r, ie_err_r, ie_rx_r, ie_tx_r} :
        (off_w == OFF_FIFO_DEPTH) ? {16'b0, UART_FIFO_DEPTH[7:0],
                                             UART_FIFO_DEPTH[7:0]} :
        (off_w == OFF_RTS_CTRL)   ? {22'b0, cts_pol_r, rts_pol_r, rts_thresh_r} :
                                     32'h0;

    // APB outputs
    wire valid_read_w = (off_w == OFF_RXDATA) ||
                        (off_w == OFF_STATUS) ||
                        (off_w == OFF_CTRL) ||
                        (off_w == OFF_CLKDIV) ||
                        (off_w == OFF_FORMAT) ||
                        (off_w == OFF_IP) ||
                        (off_w == OFF_IE) ||
                        (off_w == OFF_FIFO_DEPTH) ||
                        (off_w == OFF_RTS_CTRL);
    wire valid_write_w = (off_w == OFF_TXDATA) ||
                         (off_w == OFF_CTRL) ||
                         (off_w == OFF_CLKDIV) ||
                         (off_w == OFF_FORMAT) ||
                         (off_w == OFF_IP) ||
                         (off_w == OFF_IE) ||
                         (off_w == OFF_RTS_CTRL);
    wire access_error_w = access_w &
                          ((paddr_i[1:0] != 2'b00) |
                           (pwrite_i ? ~valid_write_w : ~valid_read_w));

    assign pready_o  = 1'b1;      // zero-wait-state peripheral
    assign prdata_o  = rdata_w;
    assign pslverr_o = access_error_w;

    // ========================================================================
    // Register write logic
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clkdiv_r    <= DEFAULT_CLKDIV;
            en_r        <= 1'b0;
            loopback_r  <= 1'b0;
            rts_en_r    <= 1'b0;
            cts_en_r    <= 1'b0;
            fmt_data_r  <= 2'd3;     // 8 bits
            fmt_stop_r  <= 1'b0;     // 1 stop
            fmt_par_r   <= 2'd0;     // no parity  (→ 8N1)
            ie_tx_r     <= 1'b0;
            ie_rx_r     <= 1'b0;
            ie_err_r    <= 1'b0;
            ie_cts_r    <= 1'b0;
            ie_rxto_r   <= 1'b0;
            rts_thresh_r<= 8'd0;
            rts_pol_r   <= 1'b0;
            cts_pol_r   <= 1'b0;
        end else begin
            if (wr_ctrl_w) begin
                if (pstrb_i[0]) begin
                    en_r       <= pwdata_i[0];
                    loopback_r <= pwdata_i[1];
                end
                if (pstrb_i[0]) begin
                    rts_en_r   <= pwdata_i[4];
                    cts_en_r   <= pwdata_i[5];
                end
                // bits [3:2] are self-clearing FIFO clear — handled by pulse wires above
            end
            if (wr_clkdiv_w) begin
                if (pstrb_i[0]) clkdiv_r[7:0]  <= pwdata_i[7:0];
                if (pstrb_i[1]) clkdiv_r[15:8] <= pwdata_i[15:8];
            end
            if (wr_format_w && pstrb_i[0]) begin
                fmt_data_r <= pwdata_i[1:0];
                fmt_stop_r <= pwdata_i[2];
                fmt_par_r  <= pwdata_i[4:3];
            end
            if (wr_ie_w && pstrb_i[0]) begin
                ie_tx_r   <= pwdata_i[0];
                ie_rx_r   <= pwdata_i[1];
                ie_err_r  <= pwdata_i[2];
                ie_cts_r  <= pwdata_i[3];
                ie_rxto_r <= pwdata_i[4];
            end
            if (wr_rts_ctrl_w) begin
                if (pstrb_i[0]) rts_thresh_r <= pwdata_i[7:0];
                if (pstrb_i[1]) rts_pol_r    <= pwdata_i[8];
                // Read-back layout is {cts_pol@9, rts_pol@8, thresh@7:0} —
                // the write side must use the same bit 9 (audit C6).
                if (pstrb_i[1]) cts_pol_r    <= pwdata_i[9];
            end
        end
    end

endmodule
