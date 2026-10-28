// File: edrv32_eth_tx.v
// Spec: eth 2.5-2.6, 5.2-5.3, 6.
// Description: Descriptor DMA, two packet banks, and concurrent frame construction.
//              A packet enters the byte FIFO only after all its data has been read.
// Clock domain: clk_mem.
module edrv32_eth_tx (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,
    input wire clear_i,

    // Descriptor command and packet addressing.
    input wire start_i,
    input wire abort_i,
    input wire [31:0] desc_base_i,
    input wire [15:0] desc_count_i,
    input wire [47:0] mac_i,
    input wire [31:0] ip_i,
    input wire [47:0] dst_mac_i,
    input wire [31:0] dst_ip_i,
    input wire [31:0] ports_i,

    // Pending ARP reply, owned by the register side until accepted.
    input wire arp_valid_i,
    output wire arp_ready_o,
    input wire [47:0] arp_mac_i,
    input wire [31:0] arp_ip_i,

    // FIFO byte stream and synchronized wire completion.
    output wire valid_o,
    input wire ready_i,
    output wire [9:0] data_o,
    input wire frame_done_i,

    // AXI256 read port.
    output wire axi_arid_o,
    output wire [31:0] axi_araddr_o,
    output wire [3:0] axi_arlen_o,
    output wire axi_arvalid_o,
    input wire axi_arready_i,
    input wire axi_rid_i,
    input wire [255:0] axi_rdata_i,
    input wire [1:0] axi_rresp_i,
    input wire axi_rlast_i,
    input wire axi_rvalid_i,
    output wire axi_rready_o,

    // Execution and accounting.
    output wire busy_o,
    output wire running_o,
    output reg done_o,
    output reg error_o,
    output reg [15:0] current_o,
    output reg descriptor_done_o,
    output wire udp_done_o,
    output wire arp_done_o
);
    localparam [3:0] S_IDLE = 4'd0;
    localparam [3:0] S_DESC = 4'd1;
    localparam [3:0] S_DESC_DATA = 4'd2;
    localparam [3:0] S_PLAN = 4'd3;
    localparam [3:0] S_DATA_DESC = 4'd4;
    localparam [3:0] S_DATA = 4'd5;
    localparam [3:0] S_WRITE = 4'd6;
    localparam [3:0] S_PUSH = 4'd7;
    localparam [3:0] S_FINISH = 4'd8;
    localparam [2:0] S_FRAME_IDLE = 3'd0;
    localparam [2:0] S_HEADER = 3'd1;
    localparam [2:0] S_PAYLOAD = 3'd2;
    localparam [2:0] S_FRAME_WAIT = 3'd3;
    reg [3:0] state_r;
    reg [2:0] frame_state_r;
    reg active_r;
    reg abort_r;
    reg error_r;
    reg [31:0] table_r;
    reg [31:0] src_r;
    reg [23:0] remaining_r;
    reg [31:0] offset_r;
    reg [2:0] flags_r;
    reg [10:0] length_r;
    reg final_r;
    reg bank_r;
    reg [1:0] occupied_r;
    reg [255:0] beat_r;
    reg [2:0] word_idx_r;
    reg [8:0] write_idx_r;
    reg eof_r;
    wire rd_desc_ready_w;
    wire rd_valid_w;
    wire rd_ready_w;
    wire [255:0] rd_data_w;
    wire rd_eof_w;
    wire rd_idle_w;
    wire rd_done_w;
    wire rd_error_w;
    wire [31:0] rd_base_w;
    wire [15:0] rd_width_w;
    wire rd_sol_w;
    wire rd_eol_w;
    reg [15:0] count_r;
    wire unused_w;
    wire packet_ready_w;
    wire packet_valid_w;
    wire packet_take_w;
    wire [48:0] packet_data_w;
    wire [48:0] packet_head_w;
    wire queue_empty_w;
    reg [48:0] frame_r;
    reg arp_r;
    reg [47:0] arp_mac_r;
    reg [31:0] arp_ip_r;
    reg [10:0] byte_idx_r;
    reg [15:0] identification_r;
    reg [15:0] packet_id_r;
    reg [31:0] read_word_r;
    reg [7:0] header_w;
    wire [31:0] ram_data_w;
    wire ram_read_w;
    wire [9:0] ram_addr_w;
    wire [10:0] frame_length_w;
    wire [15:0] ip_length_w;
    wire [15:0] udp_length_w;
    reg [31:0] src_sum_r;
    reg [31:0] dst_sum_r;
    reg [31:0] address_sum_r;
    reg [31:0] ip_length_sum_r;
    reg [31:0] length_sum_r;
    reg [31:0] sum_r;
    reg [16:0] fold_r;
    reg [15:0] checksum_r;
    wire frame_complete_w;
    wire packet_drop_w;
    wire reserved_w;
    wire [10:0] next_length_w;
    assign running_o = active_r;
    assign busy_o = active_r || frame_state_r != S_FRAME_IDLE;
    assign rd_base_w = state_r == S_DESC ? table_r : src_r;
    assign rd_width_w = state_r == S_DESC ? 16'd32 : {5'd0, length_r};
    assign rd_ready_w = state_r == S_DESC_DATA || state_r == S_DATA;
    assign next_length_w = remaining_r > 24'd1024 ? 11'd1024 : remaining_r[10:0];
    assign reserved_w = state_r == S_PLAN && !abort_r && !error_r && !occupied_r[bank_r];
    assign packet_data_w = {bank_r, final_r, flags_r[2] && final_r,
        flags_r[1:0], offset_r, 1'b0, length_r};
    assign packet_take_w = frame_state_r == S_FRAME_IDLE &&
        (abort_r || abort_i || !arp_valid_i);
    assign packet_drop_w = packet_valid_w && packet_take_w && (abort_r || abort_i);
    assign queue_empty_w = !packet_valid_w;
    edrv32_sync_fifo #(
        .WIDTH(49),
        .DEPTH(2)
    ) u_packets (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .valid_i(state_r == S_PUSH && !abort_r),
        .ready_o(packet_ready_w),
        .data_i(packet_data_w),
        .valid_o(packet_valid_w),
        .ready_i(packet_take_w),
        .data_o(packet_head_w)
    );
    edrv32_dma2d_rd #(
        .OUTSTANDING(4)
    ) u_read (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .desc_valid_i((state_r == S_DESC || state_r == S_DATA_DESC) &&
            !abort_i && !abort_r && !error_r),
        .desc_ready_o(rd_desc_ready_w),
        .desc_base_i(rd_base_w),
        .desc_stride_i(32'd0),
        .desc_width_bytes_i(rd_width_w),
        .desc_height_i(12'd1),
        .data_valid_o(rd_valid_w),
        .data_ready_i(rd_ready_w),
        .data_o(rd_data_w),
        .data_sol_o(rd_sol_w),
        .data_eol_o(rd_eol_w),
        .data_eof_o(rd_eof_w),
        .axi_arid_o(axi_arid_o),
        .axi_araddr_o(axi_araddr_o),
        .axi_arlen_o(axi_arlen_o),
        .axi_arvalid_o(axi_arvalid_o),
        .axi_arready_i(axi_arready_i),
        .axi_rid_i(axi_rid_i),
        .axi_rdata_i(axi_rdata_i),
        .axi_rresp_i(axi_rresp_i),
        .axi_rlast_i(axi_rlast_i),
        .axi_rvalid_i(axi_rvalid_i),
        .axi_rready_o(axi_rready_o),
        .abort_i(abort_i || error_r),
        .idle_o(rd_idle_w),
        .done_o(rd_done_w),
        .err_o(rd_error_w)
    );
    edrv32_ram_eth_buf u_buffer (
        .clk_i(clk_i),
        .wr_en_i(state_r == S_WRITE && !abort_r && !error_r),
        .wr_addr_i({bank_r, write_idx_r}),
        .wr_data_i(beat_r[31:0]),
        .rd_en_i(ram_read_w),
        .rd_addr_i(ram_addr_w),
        .rd_data_o(ram_data_w)
    );
    assign frame_length_w = frame_r[10:0];
    assign ip_length_w = {5'd0, frame_length_w} + 16'd36;
    assign udp_length_w = {5'd0, frame_length_w} + 16'd16;
    // The checksum is transmitted at byte 24; derive it while earlier header bytes leave.
    always @(posedge clk_i) begin
        src_sum_r <= {16'd0, ip_i[31:16]} + {16'd0, ip_i[15:0]};
        dst_sum_r <= {16'd0, dst_ip_i[31:16]} + {16'd0, dst_ip_i[15:0]};
        address_sum_r <= src_sum_r + dst_sum_r;
        ip_length_sum_r <= 32'h0000c511 + {16'd0, ip_length_w};
        length_sum_r <= ip_length_sum_r + {16'd0, packet_id_r};
        sum_r <= address_sum_r + length_sum_r;
        fold_r <= {1'b0, sum_r[15:0]} + {1'b0, sum_r[31:16]};
        checksum_r <= ~(fold_r[15:0] + {15'd0, fold_r[16]});
    end
    assign arp_ready_o = frame_state_r == S_FRAME_IDLE;
    assign valid_o = (frame_state_r == S_HEADER || frame_state_r == S_PAYLOAD) &&
        !(frame_state_r == S_HEADER && byte_idx_r == 0 && !arp_r && (abort_i || abort_r));
    assign data_o = {1'b0, arp_r ? byte_idx_r == 11'd41 :
        byte_idx_r == frame_length_w + 11'd49,
        frame_state_r == S_HEADER ? header_w : read_word_r[7:0]};
    // Prefetch the first word during the application header and each later word
    // while the current word's second-last byte is being consumed.
    assign ram_read_w = valid_o && ready_i && !arp_r && frame_length_w != 0 &&
        ((frame_state_r == S_HEADER && byte_idx_r == 11'd48) ||
        (frame_state_r == S_PAYLOAD && byte_idx_r[1:0] == 2'd0));
    assign ram_addr_w = {frame_r[48], 9'd0} +
        (frame_state_r == S_HEADER ? 10'd0 :
        ((byte_idx_r[9:0] - 10'd48) >> 2));
    assign frame_complete_w = frame_state_r == S_FRAME_WAIT && frame_done_i;
    assign udp_done_o = frame_complete_w && !arp_r;
    assign arp_done_o = frame_complete_w && arp_r;
    assign unused_w = &{1'b0, rd_done_w, rd_error_w, rd_sol_w, rd_eol_w, frame_r[11]};

    always @(*) begin
        header_w = 8'd0;
        if (arp_r) begin
            case (byte_idx_r)
                11'd0: header_w = arp_mac_r[47:40];
                11'd1: header_w = arp_mac_r[39:32];
                11'd2: header_w = arp_mac_r[31:24];
                11'd3: header_w = arp_mac_r[23:16];
                11'd4: header_w = arp_mac_r[15:8];
                11'd5: header_w = arp_mac_r[7:0];
                11'd6: header_w = mac_i[47:40];
                11'd7: header_w = mac_i[39:32];
                11'd8: header_w = mac_i[31:24];
                11'd9: header_w = mac_i[23:16];
                11'd10: header_w = mac_i[15:8];
                11'd11: header_w = mac_i[7:0];
                11'd12: header_w = 8'd8;
                11'd13: header_w = 8'd6;
                11'd14: header_w = 8'd0;
                11'd15: header_w = 8'd1;
                11'd16: header_w = 8'd8;
                11'd17: header_w = 8'd0;
                11'd18: header_w = 8'd6;
                11'd19: header_w = 8'd4;
                11'd20: header_w = 8'd0;
                11'd21: header_w = 8'd2;
                11'd22: header_w = mac_i[47:40];
                11'd23: header_w = mac_i[39:32];
                11'd24: header_w = mac_i[31:24];
                11'd25: header_w = mac_i[23:16];
                11'd26: header_w = mac_i[15:8];
                11'd27: header_w = mac_i[7:0];
                11'd28: header_w = ip_i[31:24];
                11'd29: header_w = ip_i[23:16];
                11'd30: header_w = ip_i[15:8];
                11'd31: header_w = ip_i[7:0];
                11'd32: header_w = arp_mac_r[47:40];
                11'd33: header_w = arp_mac_r[39:32];
                11'd34: header_w = arp_mac_r[31:24];
                11'd35: header_w = arp_mac_r[23:16];
                11'd36: header_w = arp_mac_r[15:8];
                11'd37: header_w = arp_mac_r[7:0];
                11'd38: header_w = arp_ip_r[31:24];
                11'd39: header_w = arp_ip_r[23:16];
                11'd40: header_w = arp_ip_r[15:8];
                11'd41: header_w = arp_ip_r[7:0];
                default: header_w = 8'd0;
            endcase
        end else begin
            case (byte_idx_r)
                11'd0: header_w = dst_mac_i[47:40];
                11'd1: header_w = dst_mac_i[39:32];
                11'd2: header_w = dst_mac_i[31:24];
                11'd3: header_w = dst_mac_i[23:16];
                11'd4: header_w = dst_mac_i[15:8];
                11'd5: header_w = dst_mac_i[7:0];
                11'd6: header_w = mac_i[47:40];
                11'd7: header_w = mac_i[39:32];
                11'd8: header_w = mac_i[31:24];
                11'd9: header_w = mac_i[23:16];
                11'd10: header_w = mac_i[15:8];
                11'd11: header_w = mac_i[7:0];
                11'd12: header_w = 8'd8;
                11'd13: header_w = 8'd0;
                11'd14: header_w = 8'd69;
                11'd15: header_w = 8'd0;
                11'd16: header_w = ip_length_w[15:8];
                11'd17: header_w = ip_length_w[7:0];
                11'd18: header_w = packet_id_r[15:8];
                11'd19: header_w = packet_id_r[7:0];
                11'd20: header_w = 8'd64;
                11'd21: header_w = 8'd0;
                11'd22: header_w = 8'd64;
                11'd23: header_w = 8'd17;
                11'd24: header_w = checksum_r[15:8];
                11'd25: header_w = checksum_r[7:0];
                11'd26: header_w = ip_i[31:24];
                11'd27: header_w = ip_i[23:16];
                11'd28: header_w = ip_i[15:8];
                11'd29: header_w = ip_i[7:0];
                11'd30: header_w = dst_ip_i[31:24];
                11'd31: header_w = dst_ip_i[23:16];
                11'd32: header_w = dst_ip_i[15:8];
                11'd33: header_w = dst_ip_i[7:0];
                11'd34: header_w = ports_i[31:24];
                11'd35: header_w = ports_i[23:16];
                11'd36: header_w = ports_i[15:8];
                11'd37: header_w = ports_i[7:0];
                11'd38: header_w = udp_length_w[15:8];
                11'd39: header_w = udp_length_w[7:0];
                11'd40: header_w = 8'd0;
                11'd41: header_w = 8'd0;
                11'd42: header_w = {6'd0, frame_r[45:44]};
                11'd43: header_w = {7'd0, frame_r[46]};
                11'd44: header_w = 8'd0;
                11'd45: header_w = 8'd0;
                11'd46: header_w = frame_r[43:36];
                11'd47: header_w = frame_r[35:28];
                11'd48: header_w = frame_r[27:20];
                11'd49: header_w = frame_r[19:12];
                default: header_w = 8'd0;
            endcase
        end
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            active_r <= 1'b0;
            abort_r <= 1'b0;
            error_r <= 1'b0;
            occupied_r <= 2'd0;
            current_o <= 16'd0;
            descriptor_done_o <= 1'b0;
            done_o <= 1'b0;
            error_o <= 1'b0;
            bank_r <= 1'b0;
            word_idx_r <= 3'd0;
            write_idx_r <= 9'd0;
        end else begin
            descriptor_done_o <= 1'b0;
            done_o <= 1'b0;
            error_o <= 1'b0;
            if (clear_i) begin
                current_o <= 16'd0;
                abort_r <= 1'b0;
                error_r <= 1'b0;
                occupied_r <= 2'd0;
                bank_r <= 1'b0;
            end
            if (start_i) begin
                active_r <= desc_count_i != 0;
                state_r <= desc_count_i == 0 ? S_IDLE : S_DESC;
                current_o <= 16'd0;
                abort_r <= 1'b0;
                error_r <= 1'b0;
                done_o <= desc_count_i == 0;
            end
            if (active_r && abort_i)
                abort_r <= 1'b1;
            if (axi_rvalid_i && axi_rready_o && axi_rresp_i != 0) begin
                error_r <= 1'b1;
                error_o <= 1'b1;
            end
            if (reserved_w)
                occupied_r[bank_r] <= 1'b1;
            if (udp_done_o)
                occupied_r[frame_r[48]] <= 1'b0;
            if (packet_drop_w)
                occupied_r[packet_head_w[48]] <= 1'b0;
            case (state_r)
                S_DESC: begin
                    if (rd_desc_ready_w)
                        state_r <= S_DESC_DATA;
                end
                S_DESC_DATA: begin
                    if (rd_valid_w) begin
                        state_r <= (error_r || axi_rresp_i != 0) ? S_FINISH : S_PLAN;
                    end
                end
                S_PLAN: begin
                    if (abort_r || error_r)
                        state_r <= S_FINISH;
                    else if (reserved_w) begin
                        length_r <= next_length_w;
                        final_r <= remaining_r <= 24'd1024;
                        write_idx_r <= 9'd0;
                        state_r <= remaining_r == 0 ? S_PUSH : S_DATA_DESC;
                    end
                end
                S_DATA_DESC: begin
                    if (rd_desc_ready_w)
                        state_r <= S_DATA;
                end
                S_DATA: begin
                    if (rd_valid_w) begin
                        word_idx_r <= 3'd0;
                        state_r <= S_WRITE;
                    end
                end
                S_WRITE: begin
                    write_idx_r <= write_idx_r + 9'd1;
                    word_idx_r <= word_idx_r + 3'd1;
                    if (word_idx_r == 3'd7)
                        state_r <= eof_r ? S_PUSH : S_DATA;
                end
                S_PUSH: begin
                    if (packet_ready_w) begin
                        bank_r <= !bank_r;
                        state_r <= final_r || error_r ? S_FINISH : S_PLAN;
                    end
                end
                S_FINISH: begin
                    if (abort_r || error_r) begin
                        if (rd_idle_w && queue_empty_w &&
                            frame_state_r == S_FRAME_IDLE) begin
                            active_r <= 1'b0;
                            state_r <= S_IDLE;
                            occupied_r <= 2'd0;
                        end
                    end else if (udp_done_o && frame_r[47]) begin
                        descriptor_done_o <= 1'b1;
                        current_o <= current_o + 16'd1;
                        if (current_o + 16'd1 == count_r) begin
                            done_o <= 1'b1;
                            active_r <= 1'b0;
                            state_r <= S_IDLE;
                        end else begin
                            state_r <= S_DESC;
                        end
                    end
                end
                default: begin end
            endcase
            // ABORT drains the shared DMA and discards work that never entered the FIFO.
            begin
                if (active_r && (abort_i || abort_r ||
                    (error_r && state_r != S_PUSH)) && state_r != S_IDLE)
                    state_r <= S_FINISH;
            end
        end
    end
    always @(posedge clk_i) begin
        if (start_i) begin
            table_r <= desc_base_i;
            count_r <= desc_count_i;
        end
        else if (udp_done_o && frame_r[47] && !abort_r && !error_r)
            table_r <= table_r + 32'd32;
        if (state_r == S_DESC_DATA && rd_valid_w) begin
            src_r <= {rd_data_w[31:5], 5'd0};
            remaining_r <= rd_data_w[55:32];
            flags_r <= {rd_data_w[72], rd_data_w[65:64]};
            offset_r <= rd_data_w[127:96];
        end else if (state_r == S_PUSH && packet_ready_w) begin
            src_r <= src_r + 32'd1024;
            remaining_r <= remaining_r - {13'd0, length_r};
            offset_r <= offset_r + 32'd1024;
        end
        if (state_r == S_DATA && rd_valid_w) begin
            beat_r <= rd_data_w;
            eof_r <= rd_eof_w;
        end else if (state_r == S_WRITE)
            beat_r <= {32'd0, beat_r[255:32]};
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            frame_state_r <= S_FRAME_IDLE;
            byte_idx_r <= 11'd0;
            arp_r <= 1'b0;
            identification_r <= 16'd0;
        end else begin
            if (clear_i)
                identification_r <= 16'd0;
            case (frame_state_r)
                S_FRAME_IDLE: begin
                    if (arp_valid_i && !clear_i) begin
                        arp_r <= 1'b1;
                        byte_idx_r <= 11'd0;
                        frame_state_r <= S_HEADER;
                    end else if (packet_valid_w && !abort_r && !abort_i) begin
                        arp_r <= 1'b0;
                        byte_idx_r <= 11'd0;
                        frame_state_r <= S_HEADER;
                    end
                end
                S_HEADER: begin
                    if (byte_idx_r == 0 && !arp_r && (abort_i || abort_r)) begin
                        frame_state_r <= S_FRAME_IDLE;
                    end else if (ready_i) begin
                        if (byte_idx_r == 0 && !arp_r)
                            identification_r <= identification_r + 16'd1;
                        byte_idx_r <= byte_idx_r + 11'd1;
                        if (arp_r && byte_idx_r == 11'd41)
                            frame_state_r <= S_FRAME_WAIT;
                        else if (!arp_r && byte_idx_r == 11'd49)
                            frame_state_r <= frame_length_w == 0 ? S_FRAME_WAIT : S_PAYLOAD;
                    end
                end
                S_PAYLOAD: begin
                    if (ready_i) begin
                        byte_idx_r <= byte_idx_r + 11'd1;
                        if (byte_idx_r == frame_length_w + 11'd49)
                            frame_state_r <= S_FRAME_WAIT;
                    end
                end
                S_FRAME_WAIT: begin
                    if (frame_done_i)
                        frame_state_r <= S_FRAME_IDLE;
                end
                default: frame_state_r <= S_FRAME_IDLE;
            endcase
        end
    end
    always @(posedge clk_i) begin
        if (frame_state_r == S_FRAME_IDLE) begin
            if (arp_valid_i) begin
                arp_mac_r <= arp_mac_i;
                arp_ip_r <= arp_ip_i;
            end else if (packet_valid_w) begin
                frame_r <= packet_head_w;
            end
        end
        if (valid_o && ready_i && !arp_r) begin
            if (byte_idx_r == 0)
                packet_id_r <= identification_r;
            if (byte_idx_r == 11'd49 ||
                (frame_state_r == S_PAYLOAD && byte_idx_r[1:0] == 2'd1))
                read_word_r <= ram_data_w;
            else if (frame_state_r == S_PAYLOAD)
                read_word_r <= {8'd0, read_word_r[31:8]};
        end
    end
endmodule
