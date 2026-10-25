// ============================================================================
// File        : edrv32_yolo_serial_dma.v
// Description : Paced UART packet receiver and 256-bit AXI model DMA.
// Notes       : The transport file sends 1024-byte chunks, except the final.
//               Every chunk and the complete padded image have CRC32 checks.
//               Each packet is committed after its AXI write responses; the
//               sender inserts guard bytes while the reply is transmitted.
// ============================================================================
`include "edrv32_build_mode.vh"

module edrv32_yolo_serial_dma #(
    parameter [3:0] AXI_ID = 4'hb
) (
    input  wire         clk_i,
    input  wire         rst_n_i,

    input  wire         start_i,
    output wire         start_ready_o,
    input  wire [31:0]  base_i,
    input  wire [31:0]  size_i,
    input  wire [31:0]  expected_crc_i,
    input  wire         rx_valid_i,
    input  wire [7:0]   rx_data_i,
    input  wire         rx_frame_error_i,
    output wire         tx_valid_o,
    input  wire         tx_ready_i,
    output wire [7:0]   tx_data_o,
    output wire         busy_o,
    output wire         done_o,
    output wire         error_o,
    output wire [31:0]  received_bytes_o,
    output wire [15:0]  next_seq_o,

    output wire [3:0]   m_awid_o,
    output wire [31:0]  m_awaddr_o,
    output wire [7:0]   m_awlen_o,
    output wire [2:0]   m_awsize_o,
    output wire [1:0]   m_awburst_o,
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
    output wire         m_bready_o
);

    localparam [4:0] S_IDLE    = 5'd0;
    localparam [4:0] S_SYNC0   = 5'd1;
    localparam [4:0] S_SYNC1   = 5'd2;
    localparam [4:0] S_SEQ0    = 5'd3;
    localparam [4:0] S_SEQ1    = 5'd4;
    localparam [4:0] S_LEN0    = 5'd5;
    localparam [4:0] S_LEN1    = 5'd6;
    localparam [4:0] S_PAYLOAD = 5'd7;
    localparam [4:0] S_CRC0    = 5'd8;
    localparam [4:0] S_CRC1    = 5'd9;
    localparam [4:0] S_CRC2    = 5'd10;
    localparam [4:0] S_CRC3    = 5'd11;
    localparam [4:0] S_EVAL    = 5'd12;
    localparam [4:0] S_AW      = 5'd13;
    localparam [4:0] S_W       = 5'd14;
    localparam [4:0] S_B       = 5'd15;
    localparam [4:0] S_REPLY   = 5'd16;
    localparam [4:0] S_COMPLETE = 5'd17;
    localparam [4:0] S_W_PREP  = 5'd18;

    // Responses are text lines: Y + status + four hex sequence digits + CRLF.
    localparam [7:0] RESP_ACK   = 8'h41;
    localparam [7:0] RESP_NACK  = 8'h4e;
    localparam [7:0] RESP_DONE  = 8'h44;
    localparam [7:0] RESP_ERROR = 8'h45;
    localparam [7:0] RESP_READY = 8'h52;

    reg [4:0] state_r;
    reg done_r;
    reg error_r;
    reg finish_reply_r;
    reg [2:0] reply_index_r;
    reg [7:0] reply_code_r;
    reg [31:0] base_r;
    reg [31:0] size_r;
    reg [31:0] expected_crc_r;
    reg [31:0] accepted_bytes_r;
    reg [15:0] expected_seq_r;
    reg [15:0] packet_seq_r;
    reg [15:0] packet_len_r;
    reg [9:0] payload_index_r;
    reg [31:0] packet_crc_r;
    reg [31:0] packet_crc_rx_r;
    reg [31:0] model_crc_r;
    reg [31:0] candidate_crc_r;
    reg [5:0] dma_index_r;
    reg [5:0] burst_end_r;
    reg [255:0] write_data_r;
    reg [15:0] last_len_r;
    reg [31:0] last_packet_crc_r;
    reg [255:0] packet_assembly_r;
    reg [255:0] packet_assembled_w;
    wire [255:0] packet_complete_w =
        {rx_data_i, packet_assembly_r[247:0]};
    wire packet_word_wr_w = state_r == S_PAYLOAD && rx_valid_i &&
                            payload_index_r[4:0] == 5'd31;
    wire packet_word_rd_w = (state_r == S_AW && m_awready_i) ||
                            (state_r == S_W && w_fire_w && !m_wlast_o);
    wire [4:0] packet_word_rd_addr_w = state_r == S_AW ?
        dma_index_r[4:0] : dma_index_r[4:0] + 5'd1;
    wire [255:0] packet_word_data_w;

    always @(*) begin
        packet_assembled_w = packet_assembly_r;
        packet_assembled_w[payload_index_r[4:0]*8 +: 8] = rx_data_i;
    end

`ifdef EDRV32_BUILD_MODE_CONFLICT
    edrv32_build_mode_error__define_only_one_of_FPGA_MODE_or_SIM_MODE
        u_build_mode_error ();
`elsif EDRV32_FPGA_MEMORY_MODE
    yolo_weight_ram u_packet_ram (
        .wr_data(packet_complete_w),
        .wr_addr({4'd0, payload_index_r[9:5]}),
        .wr_en(packet_word_wr_w),
        .wr_clk(clk_i), .wr_rst(~rst_n_i),
        .wr_byte_en(32'hffff_ffff),
        .rd_data(packet_word_data_w),
        .rd_addr({4'd0, packet_word_rd_addr_w}),
        .rd_clk(clk_i), .rd_rst(~rst_n_i),
        .rd_clk_en(packet_word_rd_w)
    );
`else
    reg [255:0] packet_mem_r [0:31];
    reg [255:0] packet_read_r;
    always @(posedge clk_i) begin
        if (packet_word_wr_w)
            packet_mem_r[payload_index_r[9:5]] <= packet_complete_w;
        if (packet_word_rd_w)
            packet_read_r <= packet_mem_r[packet_word_rd_addr_w];
    end
    assign packet_word_data_w = packet_read_r;
`endif

    function [31:0] crc32_byte;
        input [31:0] crc;
        input [7:0] data;
        reg [31:0] value;
        integer bit_index;
        begin
            value = crc ^ {24'd0, data};
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1)
                value = value[0] ? (value >> 1) ^ 32'hedb8_8320 :
                                   (value >> 1);
            crc32_byte = value;
        end
    endfunction

    function [7:0] hex_digit;
        input [3:0] value;
        begin
            hex_digit = value < 4'd10 ?
                        8'h30 + {4'd0, value} :
                        8'h41 + {4'd0, value} - 8'd10;
        end
    endfunction

    wire [31:0] remaining_w = size_r - accepted_bytes_r;
    wire [15:0] expected_len_w = remaining_w >= 32'd1024 ?
                                 16'd1024 : remaining_w[15:0];
    wire [31:0] dma_addr_w = base_r + accepted_bytes_r +
                             {21'd0, dma_index_r, 5'd0};
    wire [5:0] remaining_beats_w = packet_len_r[10:5] - dma_index_r;
    wire [7:0] boundary_beats_w = 8'd128 - {1'b0, dma_addr_w[11:5]};
    wire [5:0] limited_beats_w = remaining_beats_w > 6'd16 ?
                                 6'd16 : remaining_beats_w;
    wire [5:0] issue_beats_w = limited_beats_w > boundary_beats_w ?
                               boundary_beats_w[5:0] : limited_beats_w;
    wire w_fire_w = m_wvalid_o && m_wready_i;
    wire b_fire_w = m_bvalid_i && m_bready_o;

    // A new YCFG's initial 'Y' is also seen by this parser. Its following
    // 'C' returns a completed session to S_SYNC0 before the new start pulse.
    assign start_ready_o = state_r == S_IDLE || state_r == S_COMPLETE ||
                           (done_r && state_r == S_SYNC0);
    assign busy_o = state_r != S_IDLE && state_r != S_COMPLETE;
    assign done_o = done_r;
    assign error_o = error_r;
    assign received_bytes_o = accepted_bytes_r;
    assign next_seq_o = expected_seq_r;
    assign tx_valid_o = state_r == S_REPLY;
    assign tx_data_o = reply_index_r == 3'd0 ? 8'h59 :
                       reply_index_r == 3'd1 ? reply_code_r :
                       reply_index_r == 3'd2 ?
                           hex_digit(expected_seq_r[15:12]) :
                       reply_index_r == 3'd3 ?
                           hex_digit(expected_seq_r[11:8]) :
                       reply_index_r == 3'd4 ?
                           hex_digit(expected_seq_r[7:4]) :
                       reply_index_r == 3'd5 ?
                           hex_digit(expected_seq_r[3:0]) :
                       reply_index_r == 3'd6 ? 8'h0d : 8'h0a;

    assign m_awid_o = AXI_ID;
    assign m_awaddr_o = dma_addr_w;
    assign m_awlen_o = {2'd0, issue_beats_w} - 8'd1;
    assign m_awsize_o = 3'd5;
    assign m_awburst_o = 2'b01;
    assign m_awvalid_o = state_r == S_AW;
    assign m_wdata_o = write_data_r;
    assign m_wstrb_o = 32'hffff_ffff;
    assign m_wlast_o = dma_index_r + 6'd1 == burst_end_r;
    assign m_wvalid_o = state_r == S_W;
    assign m_bready_o = state_r == S_B;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            done_r <= 1'b0;
            error_r <= 1'b0;
            finish_reply_r <= 1'b0;
            reply_index_r <= 3'd0;
            reply_code_r <= RESP_NACK;
            base_r <= 32'd0;
            size_r <= 32'd0;
            expected_crc_r <= 32'd0;
            accepted_bytes_r <= 32'd0;
            expected_seq_r <= 16'd0;
            packet_seq_r <= 16'd0;
            packet_len_r <= 16'd0;
            payload_index_r <= 10'd0;
            packet_crc_r <= 32'hffff_ffff;
            packet_crc_rx_r <= 32'd0;
            model_crc_r <= 32'hffff_ffff;
            candidate_crc_r <= 32'hffff_ffff;
            dma_index_r <= 6'd0;
            burst_end_r <= 6'd0;
            write_data_r <= 256'd0;
            last_len_r <= 16'd0;
            last_packet_crc_r <= 32'd0;
        end else begin
            if (start_i && start_ready_o) begin
                    done_r <= 1'b0;
                    error_r <= 1'b0;
                    if (base_i[4:0] != 5'd0 || size_i[4:0] != 5'd0 ||
                        size_i == 32'd0 || size_i > 32'd67107840 ||
                        base_i > 32'hffff_ffff - size_i) begin
                        error_r <= 1'b1;
                    end else begin
                        base_r <= base_i;
                        size_r <= size_i;
                        expected_crc_r <= expected_crc_i;
                        accepted_bytes_r <= 32'd0;
                        expected_seq_r <= 16'd0;
                        model_crc_r <= 32'hffff_ffff;
                        last_len_r <= 16'd0;
                        reply_code_r <= RESP_READY;
                        reply_index_r <= 3'd0;
                        finish_reply_r <= 1'b0;
                        state_r <= S_REPLY;
                    end
            end else if (rx_frame_error_i && state_r <= S_CRC3) begin
                reply_code_r <= RESP_NACK;
                reply_index_r <= 3'd0;
                finish_reply_r <= done_r;
                state_r <= S_REPLY;
            end else begin
                case (state_r)
                    S_SYNC0, S_COMPLETE:
                        if (rx_valid_i && rx_data_i == 8'h59)
                        state_r <= S_SYNC1;
                    S_SYNC1: if (rx_valid_i) begin
                        if (rx_data_i == 8'h4d) begin
                            packet_crc_r <= 32'hffff_ffff;
                            candidate_crc_r <= model_crc_r;
                            state_r <= S_SEQ0;
                        end else if (rx_data_i != 8'h59)
                            state_r <= S_SYNC0;
                    end
                    S_SEQ0: if (rx_valid_i) begin
                        packet_seq_r[7:0] <= rx_data_i;
                        packet_crc_r <= crc32_byte(packet_crc_r, rx_data_i);
                        state_r <= S_SEQ1;
                    end
                    S_SEQ1: if (rx_valid_i) begin
                        packet_seq_r[15:8] <= rx_data_i;
                        packet_crc_r <= crc32_byte(packet_crc_r, rx_data_i);
                        state_r <= S_LEN0;
                    end
                    S_LEN0: if (rx_valid_i) begin
                        packet_len_r[7:0] <= rx_data_i;
                        packet_crc_r <= crc32_byte(packet_crc_r, rx_data_i);
                        state_r <= S_LEN1;
                    end
                    S_LEN1: if (rx_valid_i) begin
                        packet_len_r[15:8] <= rx_data_i;
                        packet_crc_r <= crc32_byte(packet_crc_r, rx_data_i);
                        payload_index_r <= 10'd0;
                        if ({rx_data_i, packet_len_r[7:0]} == 16'd0 ||
                            {rx_data_i, packet_len_r[7:0]} > 16'd1024) begin
                            reply_code_r <= RESP_NACK;
                            reply_index_r <= 3'd0;
                            finish_reply_r <= done_r;
                            state_r <= S_REPLY;
                        end else
                            state_r <= S_PAYLOAD;
                    end
                    S_PAYLOAD: if (rx_valid_i) begin
                        packet_assembly_r <= packet_assembled_w;
                        packet_crc_r <= crc32_byte(packet_crc_r, rx_data_i);
                        candidate_crc_r <= crc32_byte(candidate_crc_r,
                                                       rx_data_i);
                        if ({6'd0, payload_index_r} + 16'd1 == packet_len_r)
                            state_r <= S_CRC0;
                        else
                            payload_index_r <= payload_index_r + 10'd1;
                    end
                    S_CRC0: if (rx_valid_i) begin
                        packet_crc_rx_r[7:0] <= rx_data_i;
                        state_r <= S_CRC1;
                    end
                    S_CRC1: if (rx_valid_i) begin
                        packet_crc_rx_r[15:8] <= rx_data_i;
                        state_r <= S_CRC2;
                    end
                    S_CRC2: if (rx_valid_i) begin
                        packet_crc_rx_r[23:16] <= rx_data_i;
                        state_r <= S_CRC3;
                    end
                    S_CRC3: if (rx_valid_i) begin
                        packet_crc_rx_r[31:24] <= rx_data_i;
                        state_r <= S_EVAL;
                    end
                    S_EVAL: begin
                        reply_index_r <= 3'd0;
                        finish_reply_r <= done_r;
                        if (~packet_crc_r != packet_crc_rx_r ||
                            packet_len_r[4:0] != 5'd0) begin
                            reply_code_r <= RESP_NACK;
                            state_r <= S_REPLY;
                        end else if (packet_seq_r == expected_seq_r &&
                                     packet_len_r == expected_len_w) begin
                            dma_index_r <= 6'd0;
                            state_r <= S_AW;
                        end else begin
                            finish_reply_r <= done_r;
                            reply_code_r <= packet_seq_r + 16'd1 ==
                                            expected_seq_r &&
                                            packet_len_r == last_len_r &&
                                            packet_crc_rx_r ==
                                            last_packet_crc_r ?
                                            (done_r ? RESP_DONE : RESP_ACK) :
                                            RESP_NACK;
                            state_r <= S_REPLY;
                        end
                    end
                    S_AW: if (m_awready_i) begin
                        burst_end_r <= dma_index_r + issue_beats_w;
                        state_r <= S_W_PREP;
                    end
                    S_W_PREP: begin
                        write_data_r <= packet_word_data_w;
                        state_r <= S_W;
                    end
                    S_W: if (w_fire_w) begin
                        dma_index_r <= dma_index_r + 6'd1;
                        if (m_wlast_o)
                            state_r <= S_B;
                        else
                            state_r <= S_W_PREP;
                    end
                    S_B: if (b_fire_w) begin
                        if (m_bresp_i != 2'b00 || m_bid_i != AXI_ID) begin
                            error_r <= 1'b1;
                            reply_code_r <= RESP_ERROR;
                            reply_index_r <= 3'd0;
                            finish_reply_r <= 1'b1;
                            state_r <= S_REPLY;
                        end else if (dma_index_r != packet_len_r[10:5]) begin
                            state_r <= S_AW;
                        end else begin
                            accepted_bytes_r <= accepted_bytes_r +
                                                {16'd0, packet_len_r};
                            expected_seq_r <= expected_seq_r + 16'd1;
                            model_crc_r <= candidate_crc_r;
                            last_len_r <= packet_len_r;
                            last_packet_crc_r <= packet_crc_rx_r;
                            reply_index_r <= 3'd0;
                            if (accepted_bytes_r + {16'd0, packet_len_r} ==
                                size_r) begin
                                finish_reply_r <= 1'b1;
                                if (~candidate_crc_r == expected_crc_r) begin
                                    done_r <= 1'b1;
                                    reply_code_r <= RESP_DONE;
                                end else begin
                                    error_r <= 1'b1;
                                    reply_code_r <= RESP_ERROR;
                                end
                            end else begin
                                finish_reply_r <= 1'b0;
                                reply_code_r <= RESP_ACK;
                            end
                            state_r <= S_REPLY;
                        end
                    end
                    S_REPLY: if (tx_ready_i) begin
                        if (reply_index_r == 3'd7)
                            state_r <= finish_reply_r ?
                                       (done_r ? S_COMPLETE : S_IDLE) :
                                       S_SYNC0;
                        else
                            reply_index_r <= reply_index_r + 3'd1;
                    end
                    default: state_r <= S_IDLE;
                endcase
            end
        end
    end
endmodule
