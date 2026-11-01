// File: edrv32_eth_regs.v
// Spec: eth 4, 2.7, 6; SoC 7.1.
// Description: APB register bank, event counters and write-response notifications.
//              Events set IRQ bits after RW1C, so simultaneous new events remain visible.
// Clock domain: clk_mem.
module edrv32_eth_regs (
    // Equal-edge regional reset copies for architectural banks and PERF groups.
    input wire clk_i,
    input wire [3:0] rst_n_i,
    input wire [3:0] rst_mem_perf_n_i,


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
    output reg [23:0] tx_gap_o,
    output reg phy_o,
    output wire [127:0] bases_o,
    output wire [127:0] sizes_o,
    output wire clear_o,
    output reg [3:0] clear_units_o /* synthesis syn_preserve=1 */,
    output reg start_o,
    output reg abort_o,
    output reg mdio_start_o,
    output wire [31:0] mdio_command_o,
    output wire error_o,
    output wire irq_o
);
    reg [11:0] apb_paddr_r;
    reg apb_pwrite_r;
    reg [31:0] apb_pwdata_r;
    reg [3:0] apb_pstrb_r;

    // SoC 4.3: the shared APB payload terminates at the setup-phase registers.
    always @(posedge clk_i) begin
        if (apb_psel_i && !apb_penable_i) begin
            apb_paddr_r <= apb_paddr_i;
            apb_pwrite_r <= apb_pwrite_i;
            apb_pwdata_r <= apb_pwdata_i;
            apb_pstrb_r <= apb_pstrb_i;
        end
    end

    reg [11:0] irq_stat_r;
    reg [1:0] err_code_r;
    reg [31:0] done_count_r;
    reg [31:0] peer_mac_lo_r;
    reg [15:0] peer_mac_hi_r;
    reg [31:0] peer_ip_r;
    reg [15:0] peer_port_r;
    reg [31:0] base_r [0:3];
    reg [31:0] size_r [0:3];
    reg [31:0] bytes_r [0:3];
    wire [31:0] perf_r [0:10];
    wire write_w;
    wire [11:0] irq_clear_w;
    wire [11:0] irq_set_w;
    wire unused_w;
    integer idx;
    reg clear_regs_r /* synthesis syn_preserve=1 */;
    reg [8:0] perf_event_r;
    reg [10:0] perf_length_r;
    reg perf_rx_complete_r;
    assign write_w = apb_psel_i && apb_penable_i && apb_pwrite_r;
    assign mdio_command_o = apb_pwdata_r;
    assign clear_o = clear_regs_r;
    // Apply the same registered SOFT_RST command to the parser and register bank.
    always @(posedge clk_i or negedge rst_n_i[0]) begin
        if (!rst_n_i[0]) begin
            clear_regs_r <= 1'b0;
            clear_units_o <= 4'd0;
        end else begin
            clear_regs_r <= write_w && apb_paddr_r == 12'h004 &&
                apb_pwdata_r[3] && !busy_i;
            clear_units_o <= {4{write_w && apb_paddr_r == 12'h004 &&
                apb_pwdata_r[3] && !busy_i}};
        end
    end

    assign error_o = irq_stat_r[1];
    assign irq_o = |(irq_stat_r & irq_en_o);
    assign apb_pready_o = 1'b1;
    assign apb_pslverr_o = 1'b0;
    assign unused_w = &{1'b0, apb_pstrb_r};
    assign irq_clear_w = write_w && apb_paddr_r == 12'h010 ? apb_pwdata_r[11:0] : 12'd0;
    assign irq_set_w = {rx_complete_i && rx_notify_i ? (4'b0001 << rx_window_i) : 4'd0,
        6'd0, read_error_i || write_error_i, done_i};
    genvar window_idx;
    generate
        for (window_idx = 0; window_idx < 4; window_idx = window_idx + 1) begin : g_windows
            assign bases_o[window_idx * 32 +: 32] = base_r[window_idx];
            assign sizes_o[window_idx * 32 +: 32] = size_r[window_idx];
        end
    endgenerate
    // Independent control copies preserve the original D, enable and effective edge.
    always @(posedge clk_i or negedge rst_n_i[0]) begin
        if (!rst_n_i[0]) begin
            enable_o <= 1'd0;
            irq_en_o <= 12'd0;
            desc_base_o <= 32'd0;
            desc_count_o <= 16'd0;
            irq_stat_r <= 12'd0;
            err_code_r <= 2'd0;
            done_count_r <= 32'd0;
        end else begin
            if (clear_local_r[0]) begin
                enable_o <= 1'd0;
                irq_en_o <= 12'd0;
                desc_base_o <= 32'd0;
                desc_count_o <= 16'd0;
                irq_stat_r <= 12'd0;
                err_code_r <= 2'd0;
                done_count_r <= 32'd0;
            end else begin
                irq_stat_r <= (irq_stat_r & ~irq_clear_w) | irq_set_w;
                if (irq_clear_w[1]) begin
                    err_code_r <= 2'd0;
                end
                if (read_error_i) begin
                    err_code_r <= 2'd1;
                end
                if (write_error_i) begin
                    err_code_r <= 2'd2;
                end
                if (desc_done_i) begin
                    done_count_r <= done_count_r + 32'd1;
                end
                if (write_w) begin
                    case (apb_paddr_r)
                        12'h004: begin
                            enable_o <= apb_pwdata_r[0];
                        end
                        12'h00c: begin
                            irq_en_o <= apb_pwdata_r[11:0] & 12'hf03;
                        end
                        12'h020: begin
                            desc_base_o <= {apb_pwdata_r[31:5], 5'd0};
                        end
                        12'h024: begin
                            desc_count_o <= apb_pwdata_r[15:0];
                        end
                        default: begin end
                    endcase
                end
            end
        end
    end
    always @(posedge clk_i or negedge rst_n_i[1]) begin
        if (!rst_n_i[1]) begin
            mac_lo_o <= 32'd0;
            mac_hi_o <= 16'd0;
            ip_o <= 32'd0;
            rx_port_o <= 16'd0;
            dst_mac_lo_o <= 32'd0;
            dst_mac_hi_o <= 16'd0;
            dst_ip_o <= 32'd0;
            ports_o <= 32'd0;
            tx_gap_o <= 24'd0;
            phy_o <= 1'd1;
        end else begin
            if (clear_local_r[1]) begin
                mac_lo_o <= 32'd0;
                mac_hi_o <= 16'd0;
                ip_o <= 32'd0;
                rx_port_o <= 16'd0;
                dst_mac_lo_o <= 32'd0;
                dst_mac_hi_o <= 16'd0;
                dst_ip_o <= 32'd0;
                ports_o <= 32'd0;
                tx_gap_o <= 24'd0;
                phy_o <= 1'd1;
            end else begin
                if (write_w) begin
                    case (apb_paddr_r)
                        12'h100: begin
                            mac_lo_o <= apb_pwdata_r[31:0];
                        end
                        12'h104: begin
                            mac_hi_o <= apb_pwdata_r[15:0];
                        end
                        12'h108: begin
                            ip_o <= apb_pwdata_r[31:0];
                        end
                        12'h10c: begin
                            rx_port_o <= apb_pwdata_r[15:0];
                        end
                        12'h110: begin
                            dst_mac_lo_o <= apb_pwdata_r[31:0];
                        end
                        12'h114: begin
                            dst_mac_hi_o <= apb_pwdata_r[15:0];
                        end
                        12'h118: begin
                            dst_ip_o <= apb_pwdata_r[31:0];
                        end
                        12'h11c: begin
                            ports_o <= apb_pwdata_r[31:0];
                        end
                        12'h134: begin
                            tx_gap_o <= apb_pwdata_r[23:0];
                        end
                        12'h188: begin
                            phy_o <= apb_pwdata_r[0];
                        end
                        default: begin end
                    endcase
                end
            end
        end
    end
    always @(posedge clk_i or negedge rst_n_i[2]) begin
        if (!rst_n_i[2]) begin
            for (idx = 0; idx < 4; idx = idx + 1) begin
                base_r[idx] <= 32'd0;
                size_r[idx] <= 32'd0;
                bytes_r[idx] <= 32'd0;
            end
        end else begin
            if (clear_local_r[2]) begin
                for (idx = 0; idx < 4; idx = idx + 1) begin
                    base_r[idx] <= 32'd0;
                    size_r[idx] <= 32'd0;
                    bytes_r[idx] <= 32'd0;
                end
            end else begin
                if (rx_complete_i) begin
                    if (rx_window_i == 2'd0) begin
                        bytes_r[0] <= bytes_r[0] + {21'd0, rx_length_i};
                    end
                    if (rx_window_i == 2'd1) begin
                        bytes_r[1] <= bytes_r[1] + {21'd0, rx_length_i};
                    end
                    if (rx_window_i == 2'd2) begin
                        bytes_r[2] <= bytes_r[2] + {21'd0, rx_length_i};
                    end
                    if (rx_window_i == 2'd3) begin
                        bytes_r[3] <= bytes_r[3] + {21'd0, rx_length_i};
                    end
                end
                if (write_w) begin
                    case (apb_paddr_r)
                        12'h140: begin
                            base_r[0] <= {apb_pwdata_r[31:5], 5'd0};
                        end
                        12'h144: begin
                            size_r[0] <= apb_pwdata_r;
                        end
                        12'h148: begin
                            bytes_r[0] <= 32'd0;
                        end
                        12'h150: begin
                            base_r[1] <= {apb_pwdata_r[31:5], 5'd0};
                        end
                        12'h154: begin
                            size_r[1] <= apb_pwdata_r;
                        end
                        12'h158: begin
                            bytes_r[1] <= 32'd0;
                        end
                        12'h160: begin
                            base_r[2] <= {apb_pwdata_r[31:5], 5'd0};
                        end
                        12'h164: begin
                            size_r[2] <= apb_pwdata_r;
                        end
                        12'h168: begin
                            bytes_r[2] <= 32'd0;
                        end
                        12'h170: begin
                            base_r[3] <= {apb_pwdata_r[31:5], 5'd0};
                        end
                        12'h174: begin
                            size_r[3] <= apb_pwdata_r;
                        end
                        12'h178: begin
                            bytes_r[3] <= 32'd0;
                        end
                        default: begin end
                    endcase
                end
            end
        end
    end
    always @(posedge clk_i or negedge rst_n_i[3]) begin
        if (!rst_n_i[3]) begin
            peer_mac_lo_r <= 32'd0;
            peer_mac_hi_r <= 16'd0;
            peer_ip_r <= 32'd0;
            peer_port_r <= 16'd0;
        end else begin
            if (clear_local_r[3]) begin
                peer_mac_lo_r <= 32'd0;
                peer_mac_hi_r <= 16'd0;
                peer_ip_r <= 32'd0;
                peer_port_r <= 16'd0;
            end else begin
                if (rx_complete_i) begin
                    peer_mac_lo_r <= peer_i[79:48];
                    peer_mac_hi_r <= peer_i[95:80];
                    peer_ip_r <= peer_i[47:16];
                    peer_port_r <= peer_i[15:0];
                end
            end
        end
    end


    // SoC 4.3: setup captures group and local addresses together; no wait state.
    reg [4:0] read_addr0_r /* synthesis syn_preserve=1 */;
    reg read_select0_r;
    reg [31:0] read_group0_w;
    always @(posedge clk_i) begin
        if (apb_psel_i && !apb_penable_i) begin
            read_addr0_r <= apb_paddr_i[4:0];
            read_select0_r <= apb_paddr_i[11:5] == 7'd0;
        end
    end
    always @(*) begin
        read_group0_w = 32'd0;
        case (read_addr0_r)
            5'h00: read_group0_w = 32'h00070001;
            5'h08: read_group0_w = {29'd0, error_o, !busy_i, busy_i};
            5'h10: read_group0_w = {20'd0, irq_stat_r};
            5'h14: read_group0_w = {30'd0, err_code_r};
            5'h04: read_group0_w = {31'd0, enable_o};
            5'h0c: read_group0_w = {20'd0, irq_en_o};
            default: begin end
        endcase
    end
    reg [4:0] read_addr1_r /* synthesis syn_preserve=1 */;
    reg read_select1_r;
    reg [31:0] read_group1_w;
    always @(posedge clk_i) begin
        if (apb_psel_i && !apb_penable_i) begin
            read_addr1_r <= apb_paddr_i[4:0];
            read_select1_r <= apb_paddr_i[11:5] == 7'd1;
        end
    end
    always @(*) begin
        read_group1_w = 32'd0;
        case (read_addr1_r)
            5'h0c: read_group1_w = done_count_r;
            5'h00: read_group1_w = desc_base_o;
            5'h04: read_group1_w = {16'd0, desc_count_o};
            default: begin end
        endcase
    end
    reg [4:0] read_addr2_r /* synthesis syn_preserve=1 */;
    reg read_select2_r;
    reg [31:0] read_group2_w;
    always @(posedge clk_i) begin
        if (apb_psel_i && !apb_penable_i) begin
            read_addr2_r <= apb_paddr_i[4:0];
            read_select2_r <= apb_paddr_i[11:5] == 7'd2;
        end
    end
    always @(*) begin
        read_group2_w = 32'd0;
        case (read_addr2_r)
            5'h00: read_group2_w = perf_r[0];
            5'h04: read_group2_w = perf_r[1];
            5'h08: read_group2_w = perf_r[2];
            5'h0c: read_group2_w = perf_r[3];
            5'h10: read_group2_w = perf_r[4];
            5'h14: read_group2_w = perf_r[5];
            5'h18: read_group2_w = perf_r[6];
            5'h1c: read_group2_w = perf_r[7];
            default: begin end
        endcase
    end
    reg [4:0] read_addr3_r /* synthesis syn_preserve=1 */;
    reg read_select3_r;
    reg [31:0] read_group3_w;
    always @(posedge clk_i) begin
        if (apb_psel_i && !apb_penable_i) begin
            read_addr3_r <= apb_paddr_i[4:0];
            read_select3_r <= apb_paddr_i[11:5] == 7'd3;
        end
    end
    always @(*) begin
        read_group3_w = 32'd0;
        case (read_addr3_r)
            5'h00: read_group3_w = perf_r[8];
            5'h04: read_group3_w = perf_r[9];
            5'h08: read_group3_w = perf_r[10];
            default: begin end
        endcase
    end
    reg [4:0] read_addr4_r /* synthesis syn_preserve=1 */;
    reg read_select4_r;
    reg [31:0] read_group4_w;
    always @(posedge clk_i) begin
        if (apb_psel_i && !apb_penable_i) begin
            read_addr4_r <= apb_paddr_i[4:0];
            read_select4_r <= apb_paddr_i[11:5] == 7'd8;
        end
    end
    always @(*) begin
        read_group4_w = 32'd0;
        case (read_addr4_r)
            5'h00: read_group4_w = mac_lo_o;
            5'h04: read_group4_w = {16'd0, mac_hi_o};
            5'h08: read_group4_w = ip_o;
            5'h0c: read_group4_w = {16'd0, rx_port_o};
            5'h10: read_group4_w = dst_mac_lo_o;
            5'h14: read_group4_w = {16'd0, dst_mac_hi_o};
            5'h18: read_group4_w = dst_ip_o;
            5'h1c: read_group4_w = ports_o;
            default: begin end
        endcase
    end
    reg [4:0] read_addr5_r /* synthesis syn_preserve=1 */;
    reg read_select5_r;
    reg [31:0] read_group5_w;
    always @(posedge clk_i) begin
        if (apb_psel_i && !apb_penable_i) begin
            read_addr5_r <= apb_paddr_i[4:0];
            read_select5_r <= apb_paddr_i[11:5] == 7'd9;
        end
    end
    always @(*) begin
        read_group5_w = 32'd0;
        case (read_addr5_r)
            5'h00: read_group5_w = peer_mac_lo_r;
            5'h04: read_group5_w = {16'd0, peer_mac_hi_r};
            5'h08: read_group5_w = peer_ip_r;
            5'h0c: read_group5_w = {16'd0, peer_port_r};
            5'h10: read_group5_w = {16'd0, current_i};
            5'h14: read_group5_w = {8'd0, tx_gap_o};
            default: begin end
        endcase
    end
    reg [4:0] read_addr6_r /* synthesis syn_preserve=1 */;
    reg read_select6_r;
    reg [31:0] read_group6_w;
    always @(posedge clk_i) begin
        if (apb_psel_i && !apb_penable_i) begin
            read_addr6_r <= apb_paddr_i[4:0];
            read_select6_r <= apb_paddr_i[11:5] == 7'd10;
        end
    end
    always @(*) begin
        read_group6_w = 32'd0;
        case (read_addr6_r)
            5'h00: read_group6_w = base_r[0];
            5'h04: read_group6_w = size_r[0];
            5'h08: read_group6_w = bytes_r[0];
            5'h10: read_group6_w = base_r[1];
            5'h14: read_group6_w = size_r[1];
            5'h18: read_group6_w = bytes_r[1];
            default: begin end
        endcase
    end
    reg [4:0] read_addr7_r /* synthesis syn_preserve=1 */;
    reg read_select7_r;
    reg [31:0] read_group7_w;
    always @(posedge clk_i) begin
        if (apb_psel_i && !apb_penable_i) begin
            read_addr7_r <= apb_paddr_i[4:0];
            read_select7_r <= apb_paddr_i[11:5] == 7'd11;
        end
    end
    always @(*) begin
        read_group7_w = 32'd0;
        case (read_addr7_r)
            5'h00: read_group7_w = base_r[2];
            5'h04: read_group7_w = size_r[2];
            5'h08: read_group7_w = bytes_r[2];
            5'h10: read_group7_w = base_r[3];
            5'h14: read_group7_w = size_r[3];
            5'h18: read_group7_w = bytes_r[3];
            default: begin end
        endcase
    end
    reg [4:0] read_addr8_r /* synthesis syn_preserve=1 */;
    reg read_select8_r;
    reg [31:0] read_group8_w;
    always @(posedge clk_i) begin
        if (apb_psel_i && !apb_penable_i) begin
            read_addr8_r <= apb_paddr_i[4:0];
            read_select8_r <= apb_paddr_i[11:5] == 7'd12;
        end
    end
    always @(*) begin
        read_group8_w = 32'd0;
        case (read_addr8_r)
            5'h04: read_group8_w = {mdio_data_i, 15'd0, mdio_busy_i};
            5'h08: read_group8_w = {31'd0, phy_o};
            default: begin end
        endcase
    end
    always @(*) begin
        apb_prdata_o = 32'd0;
        apb_prdata_o = apb_prdata_o | (read_group0_w & {32{read_select0_r}});
        apb_prdata_o = apb_prdata_o | (read_group1_w & {32{read_select1_r}});
        apb_prdata_o = apb_prdata_o | (read_group2_w & {32{read_select2_r}});
        apb_prdata_o = apb_prdata_o | (read_group3_w & {32{read_select3_r}});
        apb_prdata_o = apb_prdata_o | (read_group4_w & {32{read_select4_r}});
        apb_prdata_o = apb_prdata_o | (read_group5_w & {32{read_select5_r}});
        apb_prdata_o = apb_prdata_o | (read_group6_w & {32{read_select6_r}});
        apb_prdata_o = apb_prdata_o | (read_group7_w & {32{read_select7_r}});
        apb_prdata_o = apb_prdata_o | (read_group8_w & {32{read_select8_r}});
    end
    always @(posedge clk_i or negedge rst_n_i[0]) begin
        if (!rst_n_i[0]) begin
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
    // SoC 7.1: APB command decode ends at this register stage.
    always @(posedge clk_i or negedge rst_n_i[0]) begin
        if (!rst_n_i[0]) begin
            start_o <= 1'b0;
            abort_o <= 1'b0;
            mdio_start_o <= 1'b0;
        end else begin
            start_o <= write_w && apb_paddr_r == 12'h028 && !busy_i;
            abort_o <= write_w && apb_paddr_r == 12'h004 && apb_pwdata_r[2];
            mdio_start_o <= write_w && apb_paddr_r == 12'h180;
        end
    end
    reg [3:0] clear_local_r /* synthesis syn_preserve=1 */;
    always @(posedge clk_i or negedge rst_n_i[0]) begin
        if (!rst_n_i[0])
            clear_local_r <= 4'd0;
        else
            clear_local_r <= {4{write_w && apb_paddr_r == 12'h004 &&
                apb_pwdata_r[3] && !busy_i}};
    end
    reg [3:0] clear_perf_r /* synthesis syn_preserve=1 */;
    always @(posedge clk_i or negedge rst_n_i[0]) begin
        if (!rst_n_i[0])
            clear_perf_r <= 4'd0;
        else
            clear_perf_r <= {4{write_w && apb_paddr_r == 12'h004 &&
                apb_pwdata_r[3] && !busy_i}};
    end
    genvar perf_bank;
    generate
        for (perf_bank = 0; perf_bank < 11; perf_bank = perf_bank + 1) begin : g_perf_bank
            reg [31:0] count_r;
            assign perf_r[perf_bank] = count_r;
            wire event_w;
            wire [31:0] increment_w;
            if (perf_bank == 0) begin : g_frame
                assign event_w = perf_event_r[0];
                assign increment_w = 32'd1;
            end else if (perf_bank == 1) begin : g_complete
                assign event_w = perf_rx_complete_r;
                assign increment_w = 32'd1;
            end else if (perf_bank == 2) begin : g_length
                assign event_w = perf_length_r != 0;
                assign increment_w = {21'd0, perf_length_r};
            end else begin : g_event
                assign event_w = perf_event_r[perf_bank-2];
                assign increment_w = 32'd1;
            end
            always @(posedge clk_i or negedge rst_mem_perf_n_i[perf_bank/3]) begin
                if (!rst_mem_perf_n_i[perf_bank/3])
                    count_r <= 32'd0;
                else if (clear_perf_r[perf_bank/3] || (perf_bank >= 9 && start_o))
                    count_r <= 32'd0;
                else if (event_w)
                    count_r <= count_r + increment_w;
            end
        end
    endgenerate
endmodule
