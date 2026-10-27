// File: edrv32_npu_conv_write.v
// Spec: npu-spec 5.1 W2, 5.5; datapath design 4.2.2, 4.8.
// Description: Convert a result chunk into plane bursts with four return reservations.
// B credits live in write_dma; this module releases result credit after copying W data.
// Clock: clk_npu.
module edrv32_npu_conv_write (
    // Clock and local lifetime; cancellation follows the active AXI burst drain.
    input wire clk_i,
    input wire rst_n_i,
    input wire stop_i,
    input wire cancel_i,
    input wire start_i,

    // Layer output address and completed result chunks.
    input wire [31:0] out_addr_i,
    input wire [31:0] out_plane_stride_i,
    input wire [11:0] out_w_i,
    input wire [3:0] cout_blocks_i,
    input wire result_chunk_valid_i,
    output wire result_chunk_ready_o,
    input wire [4:0] result_chunk_base_i,
    input wire [4:0] result_chunk_pairs_i,
    input wire [2:0] result_chunk_block_i,
    input wire [10:0] result_chunk_pair_i,
    input wire result_chunk_half_i,
    input wire result_chunk_last_i,
    output wire result_rd_en_o,
    output wire [4:0] result_rd_index_o,
    output wire result_rd_plane_o,
    input wire result_rd_valid_i,
    input wire [255:0] result_rd_data_i,
    output wire result_release_o,

    // Burst requests and W data to the common write DMA.
    output wire write_req_valid_o,
    input wire write_req_ready_i,
    output wire [31:0] write_req_addr_o,
    output wire [4:0] write_req_beats_o,
    output wire write_data_valid_o,
    input wire write_data_ready_i,
    output wire [255:0] write_data_o,
    input wire write_stream_idle_i,
    output wire idle_o
);
    localparam [2:0] S_IDLE = 3'd0;
    localparam [2:0] S_ADDRESS = 3'd1;
    localparam [2:0] S_BURST = 3'd2;
    localparam [2:0] S_REQUEST = 3'd3;
    localparam [2:0] S_STREAM = 3'd4;
    localparam [2:0] S_DRAIN = 3'd5;
    localparam [2:0] S_RELEASE = 3'd6;
    wire unused_out_w_w;
    assign unused_out_w_w = out_w_i[0];
    reg [2:0] state_r;
    reg [4:0] base_r;
    reg [4:0] pairs_r;
    reg half_r;
    reg plane_r;
    reg [4:0] plane_sent_r;
    reg [4:0] burst_beats_r;
    reg [4:0] requested_r;
    reg [4:0] streamed_r;
    reg [31:0] row_addr_r;
    reg [31:0] block_addr_r;
    reg [2:0] block_r;
    reg last_r;
    reg [31:0] pair_offset_r;
    reg [31:0] low_addr_r;
    reg [31:0] addr_r;
    reg [255:0] data_r [0:3];
    reg [1:0] write_ptr_r;
    reg [1:0] read_ptr_r;
    reg [2:0] reserved_r;
    reg [2:0] ready_r;
    reg result_rd_en_r;
    reg [4:0] result_rd_index_r;
    reg result_rd_plane_r;
    wire read_w;
    wire send_w;
    wire [4:0] boundary_w;
    wire [4:0] remaining_w;
    assign result_chunk_ready_o = (state_r == S_IDLE) && !stop_i;
    assign write_req_valid_o = (state_r == S_REQUEST) && !stop_i;
    assign write_req_addr_o = addr_r;
    assign write_req_beats_o = burst_beats_r;
    assign read_w = (state_r == S_STREAM) && (requested_r < burst_beats_r)
        && (reserved_r < 3'd4);
    assign result_rd_en_o = result_rd_en_r;
    assign result_rd_index_o = result_rd_index_r;
    assign result_rd_plane_o = result_rd_plane_r;
    assign write_data_valid_o = (state_r == S_STREAM) && (ready_r != 3'd0);
    assign write_data_o = data_r[read_ptr_r];
    assign send_w = write_data_valid_o && write_data_ready_i;
    // On stop, cancel will reclaim the loan after AXI drains; an incomplete chunk
    // must not use the normal all-planes-complete release handshake.
    assign result_release_o = (state_r == S_RELEASE) && !stop_i;
    assign idle_o = (state_r == S_IDLE) && write_stream_idle_i;
    assign boundary_w = 5'd16 - {1'b0, addr_r[8:5]};
    assign remaining_w = pairs_r - plane_sent_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            plane_r <= 1'b0;
            plane_sent_r <= 5'd0;
            burst_beats_r <= 5'd0;
            requested_r <= 5'd0;
            streamed_r <= 5'd0;
            write_ptr_r <= 2'd0;
            read_ptr_r <= 2'd0;
            reserved_r <= 3'd0;
            ready_r <= 3'd0;
            result_rd_en_r <= 1'b0;
        end else if (cancel_i) begin
            state_r <= S_IDLE;
            reserved_r <= 3'd0;
            ready_r <= 3'd0;
            result_rd_en_r <= 1'b0;
        end else begin
            result_rd_en_r <= read_w;
            if (read_w && !send_w) begin
                reserved_r <= reserved_r + 3'd1;
            end else if (!read_w && send_w) begin
                reserved_r <= reserved_r - 3'd1;
            end
            if (result_rd_valid_i && !send_w) begin
                ready_r <= ready_r + 3'd1;
            end else if (!result_rd_valid_i && send_w) begin
                ready_r <= ready_r - 3'd1;
            end
            if (result_rd_valid_i) begin
                write_ptr_r <= write_ptr_r + 2'd1;
            end
            if (send_w) begin
                read_ptr_r <= read_ptr_r + 2'd1;
            end
            case (state_r)
                S_IDLE: begin
                    if (result_chunk_valid_i && result_chunk_ready_o) begin
                        state_r <= S_ADDRESS;
                        plane_r <= 1'b0;
                        plane_sent_r <= 5'd0;
                    end
                end
                S_ADDRESS: state_r <= S_BURST;
                S_BURST: begin
                    burst_beats_r <= (remaining_w < boundary_w) ? remaining_w : boundary_w;
                    state_r <= stop_i ? S_RELEASE : S_REQUEST;
                end
                S_REQUEST: begin
                    if (stop_i) begin
                        state_r <= S_RELEASE;
                    end else if (write_req_ready_i) begin
                        state_r <= S_STREAM;
                        requested_r <= 5'd0;
                        streamed_r <= 5'd0;
                    end
                end
                S_STREAM: begin
                    if (read_w) begin
                        requested_r <= requested_r + 5'd1;
                    end
                    if (send_w) begin
                        streamed_r <= streamed_r + 5'd1;
                        if (streamed_r == burst_beats_r - 5'd1) begin
                            state_r <= S_DRAIN;
                        end
                    end
                end
                S_DRAIN: begin
                    if (write_stream_idle_i) begin
                        if (stop_i) begin
                            state_r <= S_RELEASE;
                        end else if (plane_sent_r + burst_beats_r != pairs_r) begin
                            plane_sent_r <= plane_sent_r + burst_beats_r;
                            state_r <= S_BURST;
                        end else if (!half_r && !plane_r) begin
                            plane_r <= 1'b1;
                            plane_sent_r <= 5'd0;
                            state_r <= S_BURST;
                        end else begin
                            state_r <= S_RELEASE;
                        end
                    end
                end
                S_RELEASE: state_r <= S_IDLE;
                default: begin end
            endcase
        end
    end
    always @(posedge clk_i) begin
        if (start_i) begin
            row_addr_r <= out_addr_i;
            block_addr_r <= out_addr_i;
        end
        if (read_w) begin
            result_rd_index_r <= base_r + plane_sent_r + requested_r;
            result_rd_plane_r <= plane_r;
        end
        if ((state_r == S_RELEASE) && last_r) begin
            if ({1'b0, block_r} == cout_blocks_i - 4'd1) begin
                row_addr_r <= row_addr_r + {16'd0, out_w_i[11:1], 5'd0};
                block_addr_r <= row_addr_r + {16'd0, out_w_i[11:1], 5'd0};
            end else begin
                block_addr_r <= block_addr_r + (out_plane_stride_i << 1);
            end
        end
        if (result_chunk_valid_i && result_chunk_ready_o) begin
            base_r <= result_chunk_base_i;
            pairs_r <= result_chunk_pairs_i;
            half_r <= result_chunk_half_i;
            block_r <= result_chunk_block_i;
            last_r <= result_chunk_last_i;
            pair_offset_r <= {16'd0, result_chunk_pair_i, 5'd0};
        end
        if (state_r == S_ADDRESS) begin
            addr_r <= block_addr_r + pair_offset_r;
            low_addr_r <= block_addr_r + pair_offset_r;
        end
        if ((state_r == S_DRAIN) && write_stream_idle_i) begin
            if (plane_sent_r + burst_beats_r != pairs_r) begin
                addr_r <= addr_r + {22'd0, burst_beats_r, 5'd0};
            end else if (!half_r && !plane_r) begin
                addr_r <= low_addr_r + out_plane_stride_i;
            end
        end
        if (result_rd_valid_i) begin
            data_r[write_ptr_r] <= result_rd_data_i;
        end
    end
endmodule
