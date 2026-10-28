// File: edrv32_eth_regs.v
// Spec: eth 4, 2.7, 6; SoC 7.1.
// Description: APB register bank, event counters and write-response notifications.
//              Events set IRQ bits after RW1C, so simultaneous new events remain visible.
// Clock domain: clk_mem.
module edrv32_eth_regs (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // APB slave.
    input wire [11:0] apb_paddr_i,
    input wire apb_psel_i,
    input wire apb_penable_i,
    input wire apb_pwrite_i,
    input wire [31:0] apb_pwdata_i,
    input wire [3:0] apb_pstrb_i,
    output wire apb_pready_o,
    output reg [31:0] apb_prdata_o,
    output wire apb_pslverr_o,

    // Work and completion events.
    input wire busy_i,
    input wire tx_busy_i,
    input wire done_i,
    input wire desc_done_i,
    input wire [15:0] current_i,
    input wire read_error_i,
    input wire write_error_i,
    input wire frame_i,
    input wire [3:0] drop_i,
    input wire rx_complete_i,
    input wire [10:0] rx_length_i,
    input wire [1:0] rx_window_i,
    input wire rx_notify_i,
    input wire [95:0] peer_i,
    input wire udp_done_i,
    input wire arp_done_i,
    input wire mdio_busy_i,
    input wire [15:0] mdio_data_i,

    // Configuration and commands.
    output reg enable_o,
    output reg [11:0] irq_en_o,
    output reg [31:0] desc_base_o,
    output reg [15:0] desc_count_o,
    output reg [31:0] mac_lo_o,
    output reg [15:0] mac_hi_o,
    output reg [31:0] ip_o,
    output reg [15:0] rx_port_o,
    output reg [31:0] dst_mac_lo_o,
    output reg [15:0] dst_mac_hi_o,
    output reg [31:0] dst_ip_o,
    output reg [31:0] ports_o,
    output reg phy_o,
    output wire [127:0] bases_o,
    output wire [111:0] sizes_o,
    output wire clear_o,
    output wire start_o,
    output wire abort_o,
    output wire mdio_start_o,
    output wire error_o,
    output wire irq_o
);
    reg [11:0] irq_stat_r;
    reg [1:0] err_code_r;
    reg [31:0] done_count_r;
    reg [31:0] peer_mac_lo_r;
    reg [15:0] peer_mac_hi_r;
    reg [31:0] peer_ip_r;
    reg [15:0] peer_port_r;
    reg [31:0] base_r [0:3];
    reg [27:0] size_r [0:3];
    reg [31:0] bytes_r [0:3];
    reg [31:0] perf_r [0:10];
    wire write_w;
    wire [11:0] irq_clear_w;
    wire [11:0] irq_set_w;
    wire unused_w;
    integer idx;
    reg clear_regs_r;
    reg [8:0] perf_event_r;
    reg [10:0] perf_length_r;
    reg perf_rx_complete_r;
    assign write_w = apb_psel_i && apb_penable_i && apb_pwrite_i;
    assign clear_o = write_w && apb_paddr_i == 12'h004 && apb_pwdata_i[3] && !busy_i;
    // Preserve the command boundary at the parser; only the register bank's
    // high-fanout reset enable is delayed. New events settle after that clear.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            clear_regs_r <= 1'b0;
        else
            clear_regs_r <= clear_o;
    end
    assign start_o = write_w && apb_paddr_i == 12'h028 && !busy_i;
    assign abort_o = write_w && apb_paddr_i == 12'h004 && apb_pwdata_i[2];
    assign mdio_start_o = write_w && apb_paddr_i == 12'h180;
    assign error_o = irq_stat_r[1];
    assign irq_o = |(irq_stat_r & irq_en_o);
    assign apb_pready_o = 1'b1;
    assign apb_pslverr_o = 1'b0;
    assign unused_w = &{1'b0, apb_pstrb_i};
    assign irq_clear_w = write_w && apb_paddr_i == 12'h010 ? apb_pwdata_i[11:0] : 12'd0;
    assign irq_set_w = {rx_complete_i && rx_notify_i ? (4'b0001 << rx_window_i) : 4'd0,
        6'd0, read_error_i || write_error_i, done_i};
    genvar window_idx;
    generate
        for (window_idx = 0; window_idx < 4; window_idx = window_idx + 1) begin : g_windows
            assign bases_o[window_idx * 32 +: 32] = base_r[window_idx];
            assign sizes_o[window_idx * 28 +: 28] = size_r[window_idx];
        end
    endgenerate
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            enable_o <= 1'd0;
            irq_en_o <= 12'd0;
            desc_base_o <= 32'd0;
            desc_count_o <= 16'd0;
            mac_lo_o <= 32'd0;
            mac_hi_o <= 16'd0;
            ip_o <= 32'd0;
            rx_port_o <= 16'd0;
            dst_mac_lo_o <= 32'd0;
            dst_mac_hi_o <= 16'd0;
            dst_ip_o <= 32'd0;
            ports_o <= 32'd0;
            phy_o <= 1'd1;
            irq_stat_r <= 12'd0;
            err_code_r <= 2'd0;
            done_count_r <= 32'd0;
            peer_mac_lo_r <= 32'd0;
            peer_mac_hi_r <= 16'd0;
            peer_ip_r <= 32'd0;
            peer_port_r <= 16'd0;
            for (idx = 0; idx < 4; idx = idx + 1) begin
                base_r[idx] <= 32'd0;
                size_r[idx] <= 28'd0;
                bytes_r[idx] <= 32'd0;
            end
            for (idx = 0; idx < 11; idx = idx + 1)
                perf_r[idx] <= 32'd0;
        end else if (clear_regs_r) begin
            enable_o <= 1'd0;
            irq_en_o <= 12'd0;
            desc_base_o <= 32'd0;
            desc_count_o <= 16'd0;
            mac_lo_o <= 32'd0;
            mac_hi_o <= 16'd0;
            ip_o <= 32'd0;
            rx_port_o <= 16'd0;
            dst_mac_lo_o <= 32'd0;
            dst_mac_hi_o <= 16'd0;
            dst_ip_o <= 32'd0;
            ports_o <= 32'd0;
            phy_o <= 1'd1;
            irq_stat_r <= 12'd0;
            err_code_r <= 2'd0;
            done_count_r <= 32'd0;
            peer_mac_lo_r <= 32'd0;
            peer_mac_hi_r <= 16'd0;
            peer_ip_r <= 32'd0;
            peer_port_r <= 16'd0;
            for (idx = 0; idx < 4; idx = idx + 1) begin
                base_r[idx] <= 32'd0;
                size_r[idx] <= 28'd0;
                bytes_r[idx] <= 32'd0;
            end
            for (idx = 0; idx < 11; idx = idx + 1)
                perf_r[idx] <= 32'd0;
        end else begin
            irq_stat_r <= (irq_stat_r & ~irq_clear_w) | irq_set_w;
            if (irq_clear_w[1])
                err_code_r <= 2'd0;
            if (read_error_i)
                err_code_r <= 2'd1;
            if (write_error_i)
                err_code_r <= 2'd2;
            if (desc_done_i)
                done_count_r <= done_count_r + 32'd1;
            if (perf_event_r[0])
                perf_r[0] <= perf_r[0] + 32'd1;
            if (perf_event_r[1])
                perf_r[3] <= perf_r[3] + 32'd1;
            if (perf_event_r[2])
                perf_r[4] <= perf_r[4] + 32'd1;
            if (perf_event_r[3])
                perf_r[5] <= perf_r[5] + 32'd1;
            if (perf_event_r[4])
                perf_r[6] <= perf_r[6] + 32'd1;
            if (perf_event_r[5])
                perf_r[7] <= perf_r[7] + 32'd1;
            if (rx_complete_i) begin

                if (rx_window_i == 2'd0)
                    bytes_r[0] <= bytes_r[0] + {21'd0, rx_length_i};
                if (rx_window_i == 2'd1)
                    bytes_r[1] <= bytes_r[1] + {21'd0, rx_length_i};
                if (rx_window_i == 2'd2)
                    bytes_r[2] <= bytes_r[2] + {21'd0, rx_length_i};
                if (rx_window_i == 2'd3)
                    bytes_r[3] <= bytes_r[3] + {21'd0, rx_length_i};
                peer_mac_lo_r <= peer_i[79:48];
                peer_mac_hi_r <= peer_i[95:80];
                peer_ip_r <= peer_i[47:16];
                peer_port_r <= peer_i[15:0];
            end
            if (perf_length_r != 0)
                perf_r[2] <= perf_r[2] + {21'd0, perf_length_r};
            if (perf_rx_complete_r)
                perf_r[1] <= perf_r[1] + 32'd1;
            if (perf_event_r[6])
                perf_r[8] <= perf_r[8] + 32'd1;
            if (perf_event_r[7])
                perf_r[9] <= perf_r[9] + 32'd1;
            if (perf_event_r[8])
                perf_r[10] <= perf_r[10] + 32'd1;
            if (start_o) begin
                perf_r[9] <= 32'd0;
                perf_r[10] <= 32'd0;
            end
            if (write_w) begin
                case (apb_paddr_i)
                    12'h004: enable_o <= apb_pwdata_i[0];
                    12'h00c: irq_en_o <= apb_pwdata_i[11:0] & 12'hf03;
                    12'h020: desc_base_o <= {apb_pwdata_i[31:5], 5'd0};
                    12'h024: desc_count_o <= apb_pwdata_i[15:0];
                    12'h100: mac_lo_o <= apb_pwdata_i[31:0];
                    12'h104: mac_hi_o <= apb_pwdata_i[15:0];
                    12'h108: ip_o <= apb_pwdata_i[31:0];
                    12'h10c: rx_port_o <= apb_pwdata_i[15:0];
                    12'h110: dst_mac_lo_o <= apb_pwdata_i[31:0];
                    12'h114: dst_mac_hi_o <= apb_pwdata_i[15:0];
                    12'h118: dst_ip_o <= apb_pwdata_i[31:0];
                    12'h11c: ports_o <= apb_pwdata_i[31:0];
                    12'h188: phy_o <= apb_pwdata_i[0];
                    12'h140: base_r[0] <= {apb_pwdata_i[31:5], 5'd0};
                    12'h144: size_r[0] <= apb_pwdata_i[27:0];
                    12'h148: bytes_r[0] <= 32'd0;
                    12'h150: base_r[1] <= {apb_pwdata_i[31:5], 5'd0};
                    12'h154: size_r[1] <= apb_pwdata_i[27:0];
                    12'h158: bytes_r[1] <= 32'd0;
                    12'h160: base_r[2] <= {apb_pwdata_i[31:5], 5'd0};
                    12'h164: size_r[2] <= apb_pwdata_i[27:0];
                    12'h168: bytes_r[2] <= 32'd0;
                    12'h170: base_r[3] <= {apb_pwdata_i[31:5], 5'd0};
                    12'h174: size_r[3] <= apb_pwdata_i[27:0];
                    12'h178: bytes_r[3] <= 32'd0;
                    default: begin end
                endcase
            end
        end
    end
    always @(*) begin
        apb_prdata_o = 32'd0;
        case (apb_paddr_i)
            12'h000: apb_prdata_o = 32'h00070001;
            12'h008: apb_prdata_o = {29'd0, error_o, !busy_i, busy_i};
            12'h010: apb_prdata_o = {20'd0, irq_stat_r};
            12'h014: apb_prdata_o = {30'd0, err_code_r};
            12'h02c: apb_prdata_o = done_count_r;
            12'h120: apb_prdata_o = peer_mac_lo_r;
            12'h124: apb_prdata_o = {16'd0, peer_mac_hi_r};
            12'h128: apb_prdata_o = peer_ip_r;
            12'h12c: apb_prdata_o = {16'd0, peer_port_r};
            12'h130: apb_prdata_o = {16'd0, current_i};
            12'h184: apb_prdata_o = {mdio_data_i, 15'd0, mdio_busy_i};
            12'h004: apb_prdata_o = {31'd0, enable_o};
            12'h00c: apb_prdata_o = {20'd0, irq_en_o};
            12'h020: apb_prdata_o = desc_base_o;
            12'h024: apb_prdata_o = {16'd0, desc_count_o};
            12'h100: apb_prdata_o = mac_lo_o;
            12'h104: apb_prdata_o = {16'd0, mac_hi_o};
            12'h108: apb_prdata_o = ip_o;
            12'h10c: apb_prdata_o = {16'd0, rx_port_o};
            12'h110: apb_prdata_o = dst_mac_lo_o;
            12'h114: apb_prdata_o = {16'd0, dst_mac_hi_o};
            12'h118: apb_prdata_o = dst_ip_o;
            12'h11c: apb_prdata_o = ports_o;
            12'h188: apb_prdata_o = {31'd0, phy_o};
            12'h140: apb_prdata_o = base_r[0];
            12'h144: apb_prdata_o = {4'd0, size_r[0]};
            12'h148: apb_prdata_o = bytes_r[0];
            12'h150: apb_prdata_o = base_r[1];
            12'h154: apb_prdata_o = {4'd0, size_r[1]};
            12'h158: apb_prdata_o = bytes_r[1];
            12'h160: apb_prdata_o = base_r[2];
            12'h164: apb_prdata_o = {4'd0, size_r[2]};
            12'h168: apb_prdata_o = bytes_r[2];
            12'h170: apb_prdata_o = base_r[3];
            12'h174: apb_prdata_o = {4'd0, size_r[3]};
            12'h178: apb_prdata_o = bytes_r[3];
            12'h040: apb_prdata_o = perf_r[0];
            12'h044: apb_prdata_o = perf_r[1];
            12'h048: apb_prdata_o = perf_r[2];
            12'h04c: apb_prdata_o = perf_r[3];
            12'h050: apb_prdata_o = perf_r[4];
            12'h054: apb_prdata_o = perf_r[5];
            12'h058: apb_prdata_o = perf_r[6];
            12'h05c: apb_prdata_o = perf_r[7];
            12'h060: apb_prdata_o = perf_r[8];
            12'h064: apb_prdata_o = perf_r[9];
            12'h068: apb_prdata_o = perf_r[10];
            default: apb_prdata_o = 32'd0;
        endcase
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            perf_event_r <= 9'd0;
            perf_length_r <= 11'd0;
            perf_rx_complete_r <= 1'b0;
        end else if (clear_o) begin
            perf_event_r <= 9'd0;
            perf_length_r <= 11'd0;
            perf_rx_complete_r <= 1'b0;
        end else begin
            perf_event_r <= {udp_done_i && !start_o, tx_busy_i && !start_o, arp_done_i,
                drop_i == 4'd7, drop_i == 4'd6, drop_i == 4'd5, drop_i == 4'd4,
                drop_i == 4'd3, frame_i};
            perf_length_r <= rx_complete_i ? rx_length_i : 11'd0;
            perf_rx_complete_r <= rx_complete_i;
        end
    end
endmodule
