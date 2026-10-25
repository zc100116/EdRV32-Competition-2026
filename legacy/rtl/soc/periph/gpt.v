// ============================================================================
// File        : gpt.v
// Author      : Edward ZC
// Description : SOC3 APB general-purpose timer with four compare/capture/PWM
//               channels.
// Notes       : Verilog-2001. Counter and channel values are 32-bit. Capture
//               sampling is independent of the counter prescaler. Sticky
//               events win over a simultaneous write-one-to-clear operation.
// ============================================================================
`include "edrv32_apb.vh"
`include "edrv32_soc_map.vh"

// ============================================================================
// gpt - canonical SOC3 general-purpose timer
// ============================================================================
module gpt #(
    parameter integer INSTANCE_ID = 0,
    parameter integer CHANNELS = 4
)(
    // --- Clock and reset ---
    input  wire                   clk,
    input  wire                   rst_n,

    // --- APB interface ---
    input  wire [`APB_AW-1:0]     paddr_i,
    input  wire                   psel_i,
    input  wire                   penable_i,
    input  wire                   pwrite_i,
    input  wire [31:0]            pwdata_i,
    input  wire [3:0]             pstrb_i,
    output wire                   pready_o,
    output reg  [31:0]            prdata_o,
    output wire                   pslverr_o,

    // --- Capture, PWM, and interrupt ---
    input  wire [CHANNELS-1:0]     cap_i,
    output wire [CHANNELS-1:0]     pwm_o,
    output wire [CHANNELS-1:0]     pwm_oe_o,
    output wire                   irq_o
);

    function [31:0] apply_strobe;
        input [31:0] old_value;
        input [31:0] new_value;
        input [3:0] strobe;
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
    wire apb_access_w = psel_i & penable_i;
    wire [7:0] offset_w = paddr_i[7:0];
    wire aligned_w = (paddr_i[1:0] == 2'b00);
    wire local_slot_w = (paddr_i[`APB_AW-1:8] == 0);
    localparam [7:0] CH0_CCR = `TIMER_CH_BASE;
    localparam [7:0] CH0_CCTRL = `TIMER_CH_BASE + 8'h04;
    localparam [7:0] CH1_CCR = `TIMER_CH_BASE + 8'h08;
    localparam [7:0] CH1_CCTRL = `TIMER_CH_BASE + 8'h0C;
    localparam [7:0] CH2_CCR = `TIMER_CH_BASE + 8'h10;
    localparam [7:0] CH2_CCTRL = `TIMER_CH_BASE + 8'h14;
    localparam [7:0] CH3_CCR = `TIMER_CH_BASE + 8'h18;
    localparam [7:0] CH3_CCTRL = `TIMER_CH_BASE + 8'h1C;

    wire instance_valid_w =
        (INSTANCE_ID >= 0) & (INSTANCE_ID < 4) & (CHANNELS == 4);
    wire implemented_w =
        (offset_w == `TIMER_CTRL)   |
        (offset_w == `TIMER_STATUS) |
        (offset_w == `TIMER_CNT)    |
        (offset_w == `TIMER_PERIOD) |
        (offset_w == `TIMER_IP)     |
        (offset_w == `TIMER_IE)     |
        (offset_w == `TIMER_PSC)    |
        (offset_w == CH0_CCR)       |
        (offset_w == CH0_CCTRL)     |
        (offset_w == CH1_CCR)       |
        (offset_w == CH1_CCTRL)     |
        (offset_w == CH2_CCR)       |
        (offset_w == CH2_CCTRL)     |
        (offset_w == CH3_CCR)       |
        (offset_w == CH3_CCTRL);

    wire legal_access_w =
        aligned_w & local_slot_w & implemented_w & instance_valid_w;
    wire write_access_w =
        apb_access_w & pwrite_i & legal_access_w;
    wire [31:0] write_mask_w = {
        {8{pstrb_i[3]}}, {8{pstrb_i[2]}},
        {8{pstrb_i[1]}}, {8{pstrb_i[0]}}
    };

    assign pready_o = 1'b1;
    assign pslverr_o = apb_access_w & ~legal_access_w;

    // ========================================================================
    // Counter configuration and state
    // ========================================================================
    reg en_r;
    reg oneshot_r;
    reg down_r;
    reg [31:0] cnt_r;
    reg [31:0] period_r;
    reg [7:0] psc_r;
    reg [7:0] psc_count_r;
    reg [8:0] ie_r;
    reg [8:0] ip_r;

    wire ctrl_write_w =
        write_access_w & (offset_w == `TIMER_CTRL);
    wire cnt_write_w =
        write_access_w & (offset_w == `TIMER_CNT);
    wire period_write_w =
        write_access_w & (offset_w == `TIMER_PERIOD);
    wire ip_write_w =
        write_access_w & (offset_w == `TIMER_IP);
    wire ie_write_w =
        write_access_w & (offset_w == `TIMER_IE);
    wire psc_write_w =
        write_access_w & (offset_w == `TIMER_PSC);

    wire [31:0] ctrl_value_w = {
        29'b0, down_r, oneshot_r, en_r
    };
    wire [31:0] ctrl_merge_w =
        apply_strobe(ctrl_value_w, pwdata_i, pstrb_i);
    wire [31:0] cnt_merge_w =
        apply_strobe(cnt_r, pwdata_i, pstrb_i);
    wire [31:0] period_merge_w =
        apply_strobe(period_r, pwdata_i, pstrb_i);
    wire [31:0] ie_merge_w =
        apply_strobe({23'b0, ie_r}, pwdata_i, pstrb_i);
    wire [31:0] psc_merge_w =
        apply_strobe({24'b0, psc_r}, pwdata_i, pstrb_i);
    wire [22:0] unused_write_mask_upper_w = write_mask_w[31:9];
    wire [28:0] unused_ctrl_merge_upper_w = ctrl_merge_w[31:3];
    wire [22:0] unused_ie_merge_upper_w = ie_merge_w[31:9];
    wire [23:0] unused_psc_merge_upper_w = psc_merge_w[31:8];

    wire counter_tick_w =
        en_r & (psc_count_r == psc_r);
    wire up_terminal_w = cnt_r >= period_r;
    wire down_terminal_w = (cnt_r == 0) | (cnt_r > period_r);
    wire terminal_w =
        counter_tick_w & (down_r ? down_terminal_w : up_terminal_w);
    wire [31:0] next_count_w =
        down_r ?
            (down_terminal_w ? period_r : cnt_r - 1'b1) :
            (up_terminal_w ? 32'b0 : cnt_r + 1'b1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            en_r <= 1'b0;
            oneshot_r <= 1'b0;
            down_r <= 1'b0;
        end else begin
            if (ctrl_write_w) begin
                en_r <= ctrl_merge_w[`TIMER_CTRL_EN];
                oneshot_r <= ctrl_merge_w[`TIMER_CTRL_ONESHOT];
                down_r <= ctrl_merge_w[`TIMER_CTRL_DOWN];
            end
            if (terminal_w & oneshot_r)
                en_r <= 1'b0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_r <= 32'b0;
            psc_count_r <= 8'b0;
        end else if (cnt_write_w) begin
            cnt_r <= cnt_merge_w;
        end else if (!en_r) begin
            psc_count_r <= 8'b0;
        end else if (counter_tick_w) begin
            cnt_r <= next_count_w;
            psc_count_r <= 8'b0;
        end else begin
            psc_count_r <= psc_count_r + 1'b1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            period_r <= 32'hFFFF_FFFF;
            psc_r <= 8'b0;
            ie_r <= 9'b0;
        end else begin
            if (period_write_w)
                period_r <= period_merge_w;
            if (psc_write_w)
                psc_r <= psc_merge_w[7:0];
            if (ie_write_w)
                ie_r <= ie_merge_w[8:0];
        end
    end

    // ========================================================================
    // Per-channel compare, capture synchronizer/filter, and PWM
    // ========================================================================
    reg [31:0] ccr_r [0:CHANNELS-1];
    reg [4:0] cctrl_r [0:CHANNELS-1];
    reg [CHANNELS-1:0] cap_meta_r;
    reg [CHANNELS-1:0] cap_sync_r;
    reg [CHANNELS-1:0] cap_filtered_r;
    reg [CHANNELS-1:0] cap_previous_r;
    reg [CHANNELS-1:0] cap_candidate_r;
    reg [1:0] cap_stable_count_r [0:CHANNELS-1];
    wire [CHANNELS-1:0] cap_signal_w;
    wire [CHANNELS-1:0] cap_edge_w;
    wire [CHANNELS-1:0] compare_event_w;
    wire [CHANNELS-1:0] capture_event_w;

    genvar channel;
    generate
        for (channel = 0; channel < CHANNELS;
             channel = channel + 1) begin : gen_gpt_channel
            localparam [7:0] CCR_OFFSET =
                `TIMER_CH_BASE + channel * 8;
            localparam [7:0] CCTRL_OFFSET = CCR_OFFSET + 4;
            wire ccr_write_w =
                write_access_w & (offset_w == CCR_OFFSET);
            wire cctrl_write_w =
                write_access_w & (offset_w == CCTRL_OFFSET);
            wire [31:0] ccr_merge_w =
                apply_strobe(ccr_r[channel], pwdata_i, pstrb_i);
            wire [31:0] cctrl_merge_w =
                apply_strobe({27'b0, cctrl_r[channel]},
                             pwdata_i, pstrb_i);
            wire [26:0] unused_cctrl_merge_upper_w =
                cctrl_merge_w[31:5];

            assign cap_signal_w[channel] =
                cctrl_r[channel][`TIMER_CCTRL_CAP_FILTER] ?
                    cap_filtered_r[channel] : cap_sync_r[channel];
            assign cap_edge_w[channel] =
                cctrl_r[channel][`TIMER_CCTRL_CAP_RISE] ?
                    (cap_signal_w[channel] &
                     ~cap_previous_r[channel]) :
                    (~cap_signal_w[channel] &
                     cap_previous_r[channel]);
            assign capture_event_w[channel] =
                cctrl_r[channel][`TIMER_CCTRL_CAP_EN] &
                cap_edge_w[channel];
            assign compare_event_w[channel] =
                counter_tick_w & (next_count_w == ccr_r[channel]);

            assign pwm_o[channel] =
                cctrl_r[channel][`TIMER_CCTRL_PWM_EN] ?
                    (((ccr_r[channel] == 0) ? 1'b0 :
                      ((ccr_r[channel] > period_r) ? 1'b1 :
                       (cnt_r < ccr_r[channel]))) ^
                     cctrl_r[channel][`TIMER_CCTRL_PWM_POL]) :
                1'b0;
            assign pwm_oe_o[channel] =
                cctrl_r[channel][`TIMER_CCTRL_PWM_EN];

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    ccr_r[channel] <= 32'b0;
                    cctrl_r[channel] <= 5'b0;
                end else begin
                    if (ccr_write_w)
                        ccr_r[channel] <= ccr_merge_w;
                    if (capture_event_w[channel])
                        ccr_r[channel] <= cnt_r;
                    if (cctrl_write_w)
                        cctrl_r[channel] <= cctrl_merge_w[4:0];
                end
            end

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    cap_meta_r[channel] <= 1'b0;
                    cap_sync_r[channel] <= 1'b0;
                    cap_filtered_r[channel] <= 1'b0;
                    cap_previous_r[channel] <= 1'b0;
                    cap_candidate_r[channel] <= 1'b0;
                    cap_stable_count_r[channel] <= 2'b0;
                end else begin
                    cap_meta_r[channel] <= cap_i[channel];
                    cap_sync_r[channel] <= cap_meta_r[channel];
                    cap_previous_r[channel] <= cap_signal_w[channel];
                    if (cap_sync_r[channel] ==
                        cap_candidate_r[channel]) begin
                        if (cap_stable_count_r[channel] < 2)
                            cap_stable_count_r[channel] <=
                                cap_stable_count_r[channel] + 1'b1;
                        if (cap_stable_count_r[channel] == 1)
                            cap_filtered_r[channel] <=
                                cap_candidate_r[channel];
                    end else begin
                        cap_candidate_r[channel] <= cap_sync_r[channel];
                        cap_stable_count_r[channel] <= 2'd1;
                    end
                end
            end
        end
    endgenerate

    // ========================================================================
    // Sticky pending register: event has priority over RW1C
    // ========================================================================
    wire [8:0] event_w = {
        capture_event_w[3:0],
        compare_event_w[3:0],
        terminal_w
    };
    wire [8:0] clear_ip_w = pwdata_i[8:0] & write_mask_w[8:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ip_r <= 9'b0;
        end else begin
            if (ip_write_w)
                ip_r <= ip_r & ~clear_ip_w;
            if (|event_w)
                ip_r <= (ip_r & ~(ip_write_w ? clear_ip_w : 9'b0)) |
                        event_w;
        end
    end

    assign irq_o = |(ip_r & ie_r);

    // ========================================================================
    // APB read data
    // ========================================================================
    always @* begin
        prdata_o = 32'b0;
        if (legal_access_w) begin
            case (offset_w)
                `TIMER_CTRL:
                    prdata_o = ctrl_value_w;
                `TIMER_STATUS:
                    prdata_o = {31'b0, en_r};
                `TIMER_CNT:
                    prdata_o = cnt_r;
                `TIMER_PERIOD:
                    prdata_o = period_r;
                `TIMER_IP:
                    prdata_o = {23'b0, ip_r};
                `TIMER_IE:
                    prdata_o = {23'b0, ie_r};
                `TIMER_PSC:
                    prdata_o = {24'b0, psc_r};
                CH0_CCR:
                    prdata_o = ccr_r[0];
                CH0_CCTRL:
                    prdata_o = {27'b0, cctrl_r[0]};
                CH1_CCR:
                    prdata_o = ccr_r[1];
                CH1_CCTRL:
                    prdata_o = {27'b0, cctrl_r[1]};
                CH2_CCR:
                    prdata_o = ccr_r[2];
                CH2_CCTRL:
                    prdata_o = {27'b0, cctrl_r[2]};
                CH3_CCR:
                    prdata_o = ccr_r[3];
                CH3_CCTRL:
                    prdata_o = {27'b0, cctrl_r[3]};
                default:
                    prdata_o = 32'b0;
            endcase
        end
    end

endmodule
