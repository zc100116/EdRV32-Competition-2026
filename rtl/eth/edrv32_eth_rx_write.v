// File: edrv32_eth_rx_write.v
// Spec: eth 2.4, 5.1; dma2d 2.4, 5.2.
// Description: Align four-byte receive RAM words into masked AXI256 beats.
//              Packet ownership and notification retire only after DMA write completion.
// Clock domain: clk_mem.
module edrv32_eth_rx_write (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,
    input wire clear_i,

    // Ordered receive packet queue.
    input wire valid_i,
    output wire ready_o,
    input wire [151:0] data_i,
    input wire [127:0] bases_i,

    // RAM read port.
    output wire rd_en_o,
    output wire [9:0] rd_addr_o,
    input wire [31:0] rd_data_i,

    // DMA write descriptor and data stream.
    output wire desc_valid_o,
    input wire desc_ready_i,
    output wire [31:0] desc_base_o,
    output wire [15:0] desc_width_o,
    output wire data_valid_o,
    input wire data_ready_i,
    output wire [255:0] data_o,
    output wire [31:0] strb_o,
    input wire done_i,
    input wire error_i,

    // Retired packet and ring ownership.
    output wire busy_o,
    output wire complete_o,
    output wire error_o,
    output wire [10:0] release_o,
    output wire [10:0] length_o,
    output wire [1:0] window_o,
    output wire notify_o,
    output wire [95:0] peer_o
);
    wire unused_w;
    assign unused_w = &{1'b0, metadata_r[151:142], metadata_r[130:99]};
    localparam [2:0] S_IDLE = 3'd0;
    localparam [2:0] S_DESC = 3'd1;
    localparam [2:0] S_READ = 3'd2;
    localparam [2:0] S_PACK = 3'd3;
    localparam [2:0] S_SEND = 3'd4;
    localparam [2:0] S_WAIT = 3'd5;
    localparam [2:0] S_DONE = 3'd6;
    reg [2:0] state_r;
    reg [151:0] metadata_r;
    reg [31:0] addr_r;
    reg [9:0] read_addr_r;
    reg [10:0] left_r;
    reg [5:0] count_r;
    reg [255:0] pack_r;
    reg [31:0] carry_r;
    reg [4:0] pad_r;
    reg [15:0] mask_left_r;
    wire [63:0] aligned_word_w;
    wire [31:0] end_mask_w;
    wire [2:0] next_word_w;
    assign next_word_w = count_r[4:2] + 3'd1;
    reg [10:0] release_r;
    wire [2:0] amount_w;
    wire [5:0] after_w;
    wire [31:0] packet_addr_w;
    wire [10:0] words_w;
    assign packet_addr_w = bases_i[data_i[98:97] * 32 +: 32] + data_i[130:99];
    assign amount_w = left_r >= 11'd4 ? 3'd4 : left_r[2:0];
    assign after_w = count_r + {3'd0, amount_w};
    assign aligned_word_w = {32'd0, rd_data_i} << {addr_r[1:0], 3'd0};
    assign end_mask_w = mask_left_r >= 16'd32 ? 32'hffffffff :
        ((32'd1 << mask_left_r[4:0]) - 32'd1);
    assign ready_o = state_r == S_IDLE;
    assign busy_o = state_r != S_IDLE;
    assign rd_en_o = state_r == S_READ;
    assign rd_addr_o = read_addr_r;
    assign desc_valid_o = state_r == S_DESC;
    assign desc_base_o = {addr_r[31:5], 5'd0};
    assign desc_width_o = {5'd0, metadata_r[141:131]} + {11'd0, addr_r[4:0]};
    assign data_valid_o = state_r == S_SEND;
    assign data_o = pack_r;
    assign strb_o = (32'hffffffff << pad_r) & end_mask_w;
    assign complete_o = state_r == S_DONE;
    assign error_o = state_r == S_WAIT && done_i && error_i;
    assign release_o = release_r;
    assign length_o = metadata_r[141:131];
    assign window_o = metadata_r[98:97];
    assign notify_o = metadata_r[96];
    assign peer_o = metadata_r[95:0];
    assign words_w = {2'd0, length_o[10:2]} + {10'd0, |length_o[1:0]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            release_r <= 11'd0;
            left_r <= 11'd0;
            count_r <= 6'd0;
        end else begin
            if (clear_i)
                release_r <= 11'd0;
            case (state_r)
                S_IDLE: begin
                    if (valid_i) begin
                        left_r <= data_i[141:131];
                        count_r <= {1'b0, packet_addr_w[4:0]};
                        state_r <= data_i[141:131] == 0 ? S_DONE : S_DESC;
                    end
                end
                S_DESC: begin
                    if (desc_ready_i)
                        state_r <= S_READ;
                end
                S_READ: state_r <= S_PACK;
                S_PACK: begin
                    left_r <= left_r - {8'd0, amount_w};
                    count_r <= after_w;
                    if (after_w >= 6'd32 || left_r <= 11'd4)
                        state_r <= S_SEND;
                    else
                        state_r <= S_READ;
                end
                S_SEND: begin
                    if (data_ready_i) begin
                        if (count_r > 6'd32) begin
                            count_r <= count_r - 6'd32;
                            state_r <= left_r == 0 ? S_SEND : S_READ;
                        end else begin
                            count_r <= 6'd0;
                            state_r <= left_r == 0 ? S_WAIT : S_READ;
                        end
                    end
                end
                S_WAIT: begin
                    if (done_i)
                        state_r <= S_DONE;
                end
                S_DONE: begin
                    release_r <= release_r + words_w;
                    state_r <= S_IDLE;
                end
                default: state_r <= S_IDLE;
            endcase
        end
    end
    always @(posedge clk_i) begin
        if (state_r == S_IDLE && valid_i) begin
            metadata_r <= data_i;
            addr_r <= packet_addr_w;
            read_addr_r <= data_i[151:142];
            carry_r <= 32'd0;
            pad_r <= packet_addr_w[4:0];
            mask_left_r <= {5'd0, data_i[141:131]} + {11'd0, packet_addr_w[4:0]};
        end
        if (state_r == S_PACK) begin
            read_addr_r <= read_addr_r + 10'd1;
            pack_r[count_r[4:2] * 32 +: 32] <= carry_r | aligned_word_w[31:0];
            carry_r <= aligned_word_w[63:32];
            if (count_r[4:2] != 3'd7)
                pack_r[next_word_w * 32 +: 32] <= aligned_word_w[63:32];
        end
        if (state_r == S_SEND && data_ready_i) begin
            pack_r[31:0] <= carry_r;
            pad_r <= 5'd0;
            mask_left_r <= mask_left_r - 16'd32;
        end
    end
endmodule
