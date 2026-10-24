// ============================================================================
// File        : edrv32_yolo_feature_loader.v
// Description : Copy one C16 feature-map row into a line-cache row slot.
// Notes       : DDR is [C16 block][row][pixel pair]. One AXI read request per
//               channel block; returned beats are striped across cache banks.
//               Input width must be divisible by four pixels.
// ============================================================================

module edrv32_yolo_feature_loader (
    input  wire         clk_i,
    input  wire         rst_n_i,

    input  wire         start_i,
    output wire         start_ready_o,
    input  wire [31:0]  row_addr_i,
    input  wire [31:0]  plane_stride_i,
    input  wire [9:0]   cache_row_base_i,
    input  wire [8:0]   bank_stride_i,
    input  wire [9:0]   width_pairs_i,
    input  wire [5:0]   channel_blocks_i,

    output wire         rd_req_valid_o,
    input  wire         rd_req_ready_i,
    output wire [31:0]  rd_req_addr_o,
    output wire [15:0]  rd_req_beats_o,
    input  wire         rd_beat_valid_i,
    input  wire [15:0]  rd_beat_index_i,
    input  wire [255:0] rd_beat_data_i,
    input  wire         rd_done_i,
    input  wire         rd_error_i,

    output wire         cache_wr_valid_o,
    output wire         cache_wr_bank_o,
    output wire [9:0]   cache_wr_addr_o,
    output wire [255:0] cache_wr_data_o,
    output wire         busy_o,
    output wire         done_o,
    output wire         error_o
);

    localparam [1:0] IDLE = 2'd0;
    localparam [1:0] ISSUE = 2'd1;
    localparam [1:0] WAIT_READ = 2'd2;

    reg [1:0] state_r;
    reg done_r;
    reg error_r;
    reg [31:0] row_addr_r;
    reg [31:0] plane_stride_r;
    reg [9:0] cache_row_base_r;
    reg [8:0] bank_stride_r;
    reg [9:0] width_pairs_r;
    reg [5:0] channel_blocks_r;
    reg [5:0] block_r;
    reg [31:0] block_ddr_offset_r;
    reg [9:0] block_cache_offset_r;

    assign start_ready_o = state_r == IDLE && width_pairs_i != 10'd0 &&
                           channel_blocks_i != 6'd0;
    assign busy_o = state_r != IDLE;
    assign done_o = done_r;
    assign error_o = error_r;
    assign rd_req_valid_o = state_r == ISSUE;
    assign rd_req_addr_o = row_addr_r + block_ddr_offset_r;
    assign rd_req_beats_o = {6'd0, width_pairs_r};
    assign cache_wr_valid_o = state_r == WAIT_READ && rd_beat_valid_i;
    assign cache_wr_bank_o = rd_beat_index_i[0];
    assign cache_wr_addr_o = cache_row_base_r + block_cache_offset_r +
                             rd_beat_index_i[9:1];
    assign cache_wr_data_o = rd_beat_data_i;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r              <= IDLE;
            done_r               <= 1'b0;
            error_r              <= 1'b0;
            row_addr_r           <= 32'd0;
            plane_stride_r       <= 32'd0;
            cache_row_base_r     <= 10'd0;
            bank_stride_r        <= 9'd0;
            width_pairs_r        <= 10'd0;
            channel_blocks_r     <= 6'd0;
            block_r              <= 6'd0;
            block_ddr_offset_r   <= 32'd0;
            block_cache_offset_r <= 10'd0;
        end else begin
            done_r <= 1'b0;
            if (start_i && start_ready_o) begin
                state_r              <= ISSUE;
                error_r              <= 1'b0;
                row_addr_r           <= row_addr_i;
                plane_stride_r       <= plane_stride_i;
                cache_row_base_r     <= cache_row_base_i;
                bank_stride_r        <= bank_stride_i;
                width_pairs_r        <= width_pairs_i;
                channel_blocks_r     <= channel_blocks_i;
                block_r              <= 6'd0;
                block_ddr_offset_r   <= 32'd0;
                block_cache_offset_r <= 10'd0;
            end else begin
                case (state_r)
                    ISSUE: if (rd_req_valid_o && rd_req_ready_i)
                        state_r <= WAIT_READ;
                    WAIT_READ: if (rd_done_i) begin
                        if (rd_error_i)
                            error_r <= 1'b1;
                        if (block_r == channel_blocks_r - 6'd1) begin
                            state_r <= IDLE;
                            done_r <= 1'b1;
                        end else begin
                            block_r <= block_r + 6'd1;
                            block_ddr_offset_r <= block_ddr_offset_r +
                                                  plane_stride_r;
                            block_cache_offset_r <= block_cache_offset_r +
                                                    {1'b0, bank_stride_r};
                            state_r <= ISSUE;
                        end
                    end
                    default: state_r <= IDLE;
                endcase
            end
        end
    end
endmodule
