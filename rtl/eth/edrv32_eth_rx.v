// File: edrv32_eth_rx.v
// Spec: eth 2.2-2.5, 5.1-5.2.
// Description: Streaming parser, ordered filtering and speculative store-forward ring.
//              Committed packets own whole RAM words until their write response returns.
// Clock domain: clk_mem.
module edrv32_eth_rx (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,
    input wire clear_i,

    // Receive FIFO, continuously drained.
    input wire valid_i,
    input wire [9:0] data_i,
    input wire enable_i,
    input wire error_i,
    input wire [47:0] mac_i,
    input wire [31:0] ip_i,
    input wire [15:0] port_i,
    input wire [111:0] sizes_i,
    input wire [10:0] release_i,

    // Packet metadata queue and RAM write port.
    output reg packet_o,
    output reg [151:0] metadata_o,
    input wire metadata_ready_i,
    output wire wr_en_o,
    output wire [9:0] wr_addr_o,
    output wire [31:0] wr_data_o,
    output wire busy_o,

    // Accepted ARP and accounting events.
    input wire arp_pending_i,
    output reg arp_o,
    output reg [47:0] arp_mac_o,
    output reg [31:0] arp_ip_o,
    output reg frame_o,
    output reg [3:0] drop_o
);
    reg discard_r;
    reg overflow_r;
    reg [399:0] header_r;
    reg [15:0] count_r;
    reg [31:0] ip_sum_r;
    reg [31:0] udp_sum_r;
    reg [7:0] high_r;
    reg [10:0] commit_r;
    reg [10:0] start_r;
    reg [31:0] word_r;
    wire [15:0] ip_length_w;
    wire [15:0] udp_length_w;
    wire [31:0] offset_w;
    wire [1:0] window_w;
    reg [15:0] payload_r;
    reg [10:0] words_r;
    reg [10:0] end_r;
    reg [32:0] limit_r;
    reg [16:0] ip_end_r;
    reg [16:0] ip_final_r;
    reg [16:0] ip_frame_r;
    reg [15:0] ip_udp_length_r;
    reg [31:0] src_sum_r;
    reg [31:0] dst_sum_r;
    reg [31:0] address_sum_r;
    reg [31:0] udp_length_sum_r;
    reg [31:0] pseudo_header_r;
    reg [31:0] pseudo_r;
    reg [16:0] udp_fold_r;
    reg ip_good_r;
    reg udp_good_r;
    wire [27:0] size_w;
    wire [16:0] ip_fold_w;
    wire payload_byte_w;
    wire store_word_w;
    wire space_w;
    wire final_byte_w;
    wire [1:0] lane_w;
    reg [31:0] word_w;
    reg [3:0] action_w;
    wire [11:0] payload_idx_w;
    wire [10:0] word_idx_w;
    wire unused_w;
    wire [47:0] dst_w;
    assign dst_w = header_r[399:352];
    wire [47:0] src_w;
    assign src_w = header_r[351:304];
    wire [15:0] type_w;
    assign type_w = header_r[303:288];
    wire [7:0] version_w;
    assign version_w = header_r[287:280];
    wire [15:0] fragment_w;
    assign fragment_w = header_r[239:224];
    wire [7:0] protocol_w;
    assign protocol_w = header_r[215:208];
    wire [31:0] src_ip_w;
    assign src_ip_w = header_r[191:160];
    wire [31:0] dst_ip_w;
    assign dst_ip_w = header_r[159:128];
    wire [15:0] src_port_w;
    assign src_port_w = header_r[127:112];
    wire [15:0] dst_port_w;
    assign dst_port_w = header_r[111:96];
    wire [15:0] udp_check_w;
    assign udp_check_w = header_r[79:64];
    wire [7:0] flags_w;
    assign flags_w = header_r[55:48];
    wire [63:0] arp_type_w;
    assign arp_type_w = header_r[287:224];
    wire [47:0] arp_mac_w;
    assign arp_mac_w = header_r[223:176];
    wire [31:0] arp_ip_w;
    assign arp_ip_w = header_r[175:144];
    wire [31:0] arp_target_w;
    assign arp_target_w = header_r[95:64];
    assign ip_length_w = header_r[271:256];
    assign udp_length_w = header_r[95:80];
    assign offset_w = header_r[31:0];
    assign window_w = header_r[57:56];
    assign size_w = sizes_i[window_w * 28 +: 28];
    assign ip_fold_w = {1'b0, ip_sum_r[15:0]} + {1'b0, ip_sum_r[31:16]};
    // Header-derived arithmetic settles during reception, before the FCS tail.
    // The final UDP sum has four FCS byte clocks to cross these three stages.
    always @(posedge clk_i) begin
        payload_r <= udp_length_w - 16'd16;
        words_r <= {2'd0, payload_r[10:2]} + {10'd0, |payload_r[1:0]};
        end_r <= commit_r + words_r;
        limit_r <= {1'b0, offset_w} + {17'd0, payload_r};
        ip_end_r <= {1'b0, ip_length_w} + 17'd14;
        ip_final_r <= {1'b0, ip_length_w} + 17'd13;
        ip_frame_r <= {1'b0, ip_length_w} + 17'd18;
        ip_udp_length_r <= ip_length_w - 16'd20;
        src_sum_r <= {16'd0, src_ip_w[31:16]} + {16'd0, src_ip_w[15:0]};
        dst_sum_r <= {16'd0, dst_ip_w[31:16]} + {16'd0, dst_ip_w[15:0]};
        address_sum_r <= src_sum_r + dst_sum_r;
        udp_length_sum_r <= {16'd0, udp_length_w} + 32'd17;
        pseudo_header_r <= address_sum_r + udp_length_sum_r;
        pseudo_r <= pseudo_header_r + udp_sum_r;
        udp_fold_r <= {1'b0, pseudo_r[15:0]} + {1'b0, pseudo_r[31:16]};
        udp_good_r <= udp_check_w == 0 ||
            (udp_fold_r[15:0] + {15'd0, udp_fold_r[16]}) == 16'hffff;
        ip_good_r <= (ip_fold_w[15:0] + {15'd0, ip_fold_w[16]}) == 16'hffff;
    end
    assign lane_w = count_r[1:0] - 2'd2;
    assign payload_byte_w = valid_i && !data_i[9] && count_r >= 16'd50 &&
        {1'b0, count_r} < ip_end_r;
    assign final_byte_w = {1'b0, count_r} == ip_final_r;
    assign payload_idx_w = count_r[11:0] - 12'd50;
    assign word_idx_w = {1'b0, payload_idx_w[11:2]};
    assign store_word_w = payload_byte_w && (lane_w == 2'd3 || final_byte_w);
    assign space_w = (start_r - release_i) + word_idx_w < 11'd1024;
    assign wr_en_o = store_word_w && space_w;
    assign wr_addr_o = start_r[9:0] + word_idx_w[9:0];
    assign wr_data_o = word_w;
    assign busy_o = commit_r != release_i || packet_o;
    assign unused_w = &{1'b0, header_r[63:58], header_r[47:32], flags_w[7:1],
        payload_idx_w[1:0], window_w};
    always @(*) begin
        word_w = word_r;
        word_w[lane_w * 8 +: 8] = data_i[7:0];
        action_w = 4'd1;
        // spec 2.2: first failing rule owns the drop counter.
        if (clear_i || discard_r || !enable_i || error_i)
            action_w = 4'd0;
        else if (data_i[8] || count_r < 16'd64 || count_r > 16'd1518)
            action_w = 4'd3;
        else if (!(dst_w == mac_i || (dst_w == 48'hffffffffffff && type_w == 16'h0806)))
            action_w = 4'd5;
        else if (type_w == 16'h0806) begin
            action_w = arp_type_w == 64'h0001080006040001 && arp_target_w == ip_i &&
                !arp_pending_i ? 4'd2 : 4'd5;
        end else if (type_w != 16'h0800 || version_w != 8'h45 ||
            (fragment_w & 16'h3fff) != 0 || protocol_w != 8'd17 || dst_ip_w != ip_i ||
            ip_frame_r > {1'b0, count_r})
            action_w = 4'd5;
        else if (!ip_good_r || !udp_good_r)
            action_w = 4'd4;
        else if (dst_port_w != port_i || udp_length_w != ip_udp_length_r ||
            udp_length_w < 16'd16)
            action_w = 4'd5;
        else if (size_w == 0 || limit_r > {5'd0, size_w})
            action_w = 4'd6;
        else if (overflow_r || (end_r - release_i) > 11'd1024 || !metadata_ready_i)
            action_w = 4'd7;
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            count_r <= 16'd0;
            discard_r <= 1'b0;
            overflow_r <= 1'b0;
            commit_r <= 11'd0;
            start_r <= 11'd0;
            packet_o <= 1'b0;
            arp_o <= 1'b0;
            frame_o <= 1'b0;
            drop_o <= 4'd0;
        end else begin
            packet_o <= valid_i && data_i[9] && action_w == 4'd1;
            arp_o <= valid_i && data_i[9] && action_w == 4'd2;
            frame_o <= 1'b0;
            drop_o <= 4'd0;
            if (clear_i)
                discard_r <= count_r != 0 || (valid_i && !data_i[9]);
            else if (valid_i && data_i[9])
                discard_r <= 1'b0;
            if (clear_i || (valid_i && data_i[9]))
                overflow_r <= 1'b0;
            else if (store_word_w && !space_w)
                overflow_r <= 1'b1;
            if (clear_i) begin
                commit_r <= 11'd0;
                start_r <= 11'd0;
            end
            if (valid_i) begin
                if (data_i[9]) begin
                    frame_o <= 1'b1;
                    drop_o <= action_w >= 3 ? action_w : 4'd0;
                    count_r <= 16'd0;
                    if (action_w == 4'd1) begin
                        commit_r <= end_r;
                        start_r <= end_r;
                    end
                end else begin
                    if (count_r != 16'd1519)
                        count_r <= count_r + 16'd1;
                end
            end
        end
    end
    // Capture the decision and its payload together before either downstream CE.
    // The next header may begin immediately; the accepted packet retains ownership.
    always @(posedge clk_i) begin
        if (valid_i && data_i[9]) begin
            metadata_o <= {start_r[9:0], payload_r[10:0], offset_w, window_w,
                flags_w[0], src_w, src_ip_w, src_port_w};
            arp_mac_o <= arp_mac_w;
            arp_ip_o <= arp_ip_w;
        end
    end
    genvar header_idx;
    generate
        for (header_idx = 0; header_idx < 50; header_idx = header_idx + 1) begin : g_header
            always @(posedge clk_i) begin
                if (valid_i && !data_i[9] && count_r == header_idx)
                    header_r[399 - header_idx * 8 -: 8] <= data_i[7:0];
            end
        end
    endgenerate
    always @(posedge clk_i) begin
        if (payload_byte_w)
            word_r <= word_w;
        if (valid_i && data_i[9]) begin
            ip_sum_r <= 32'd0;
            udp_sum_r <= 32'd0;
        end else if (valid_i) begin
            high_r <= data_i[7:0];
            if (count_r == 0) begin
                ip_sum_r <= 32'd0;
                udp_sum_r <= 32'd0;
            end
            if (count_r >= 16'd14 && count_r < 16'd34 && count_r[0])
                ip_sum_r <= ip_sum_r + {16'd0, high_r, data_i[7:0]};
            if (count_r >= 16'd34 &&
                {1'b0, count_r} < ip_end_r) begin
                if (count_r[0])
                    udp_sum_r <= udp_sum_r + {16'd0, high_r, data_i[7:0]};
                else if (final_byte_w)
                    udp_sum_r <= udp_sum_r + {16'd0, data_i[7:0], 8'd0};
            end
        end
    end
endmodule
