// File: edrv32_rnd_copy.v
// Spec: rnd-spec 2.6 COPY, 5.2; dma2d 2.
// Description: Snapshot each source row in RAM, realign beats and preserve boundary bytes.
//              Row order implements same-stride overlap; active read/write streams are 1 beat/cycle.
// Clock domain: clk_mem (clk_i).
module edrv32_rnd_copy (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Clipped COPY command.
    input wire start_i,
    input wire cancel_i,
    input wire [511:0] command_i,
    output wire done_o,
    output wire [4:0] pixel_count_o,

    // Source row DMA client.
    output wire rd_valid_o,
    input wire rd_ready_i,
    output wire [31:0] rd_addr_o,
    output wire [15:0] rd_bytes_o,
    input wire rd_data_valid_i,
    input wire [255:0] rd_data_i,
    input wire rd_done_i,

    // Destination row DMA client.
    output wire wr_valid_o,
    input wire wr_ready_i,
    output wire [31:0] wr_addr_o,
    output wire [15:0] wr_bytes_o,
    output wire wr_data_valid_o,
    input wire wr_data_ready_i,
    output wire [255:0] wr_data_o,
    output reg [31:0] wr_strb_o,
    input wire wr_done_i
);
    localparam [3:0] S_IDLE = 4'd0;
    localparam [3:0] S_READ = 4'd1;
    localparam [3:0] S_CAPTURE = 4'd2;
    localparam [3:0] S_TAIL = 4'd3;
    localparam [3:0] S_WRITE = 4'd4;
    localparam [3:0] S_STREAM = 4'd5;
    localparam [3:0] S_RESPONSE = 4'd6;
    localparam [3:0] S_DONE = 4'd7;
    localparam [3:0] S_SETUP = 4'd8;
    reg [3:0] state_r;
    reg reverse_r;
    reg [11:0] y_r;
    reg [9:0] received_r;
    reg [9:0] write_index_r;
    reg zero_r;
    reg [255:0] previous_read_r;
    reg [255:0] previous_write_r;
    wire [7:0] unused_op_w;
    wire argb_w;
    wire [3:0] unused_format_w;
    wire [15:0] unused_flags_w;
    wire signed [17:0] left_w;
    wire signed [17:0] top_w;
    wire signed [17:0] right_w;
    wire signed [17:0] bottom_w;
    wire [16:0] unused_width_w;
    wire [16:0] unused_height_w;
    wire unused_illegal_w;
    wire unused_empty_w;
    wire unused_fast_w;
    wire [31:0] dst_addr_w;
    wire [31:0] src_addr_w;
    wire [31:0] unused_map_w;
    wire [2:0] unused_shift_w;
    wire [7:0] unused_mask_w;
    wire [31:0] unused_x_w;
    wire [31:0] unused_y_w;
    wire [17:0] row_pixels_w;
    wire [17:0] row_bytes_w;
    wire [17:0] source_bytes_w;
    wire [17:0] target_bytes_w;
    wire [17:0] rounded_bytes_w;
    wire [9:0] normalized_beats_w;
    wire [17:0] source_rounded_w;
    wire [17:0] target_rounded_w;
    wire [9:0] source_beats_w;
    wire [9:0] target_beats_w;
    wire [511:0] source_join_w;
    wire [511:0] source_shift_w;
    wire [255:0] source_word_w;
    wire [255:0] ram_data_w;
    wire [255:0] current_write_w;
    wire [511:0] target_shift_w;
    wire [511:0] target_join_w;
    wire [9:0] write_next_w;
    wire ram_wr_en_w;
    wire [8:0] ram_wr_addr_w;
    wire ram_rd_en_w;
    wire [8:0] ram_rd_addr_w;
    wire data_fire_w;
    wire [17:0] write_byte_w;
    wire unused_geometry_w;
    reg [5:0] enabled_bytes_w;
    integer byte_index;

    edrv32_rnd_decode u_decode (
        .command_i(command_i),
        .illegal_o(unused_illegal_w),
        .empty_o(unused_empty_w),
        .op_o(unused_op_w),
        .argb_o(argb_w),
        .src_fmt_o(unused_format_w),
        .flags_o(unused_flags_w),
        .left_o(left_w),
        .top_o(top_w),
        .right_o(right_w),
        .bottom_o(bottom_w),
        .width_o(unused_width_w),
        .height_o(unused_height_w),
        .fast_fill_o(unused_fast_w)
    );
    edrv32_rnd_address u_address (
        .command_i(command_i),
        .x_i(left_w[11:0]),
        .y_i(y_r),
        .map_entry_i(16'd0),
        .dst_addr_o(dst_addr_w),
        .src_addr_o(src_addr_w),
        .map_addr_o(unused_map_w),
        .sub_shift_o(unused_shift_w),
        .sub_mask_o(unused_mask_w),
        .sample_x_o(unused_x_w),
        .sample_y_o(unused_y_w)
    );
    assign row_pixels_w = right_w - left_w + 18'd1;
    assign row_bytes_w = row_pixels_w << (argb_w ? 2 : 1);
    assign source_bytes_w = row_bytes_w + {13'd0, src_addr_w[4:0]};
    assign target_bytes_w = row_bytes_w + {13'd0, dst_addr_w[4:0]};
    assign rounded_bytes_w = row_bytes_w + 18'd31;
    assign source_rounded_w = source_bytes_w + 18'd31;
    assign target_rounded_w = target_bytes_w + 18'd31;
    assign normalized_beats_w = rounded_bytes_w[14:5];
    assign source_beats_w = source_rounded_w[14:5];
    assign target_beats_w = target_rounded_w[14:5];
    assign source_join_w = {rd_data_i, previous_read_r};
    assign source_shift_w = source_join_w >> {src_addr_w[4:0], 3'd0};
    assign source_word_w = state_r == S_TAIL ?
        previous_read_r >> {src_addr_w[4:0], 3'd0} :
        src_addr_w[4:0] == 0 ? rd_data_i : source_shift_w[255:0];
    assign ram_wr_en_w = !cancel_i && (state_r == S_TAIL ||
        (state_r == S_CAPTURE && rd_data_valid_i &&
            (src_addr_w[4:0] == 0 || received_r != 0)));
    assign ram_wr_addr_w = state_r == S_TAIL ? normalized_beats_w[8:0] - 9'd1 :
        received_r[8:0] - (src_addr_w[4:0] == 0 ? 9'd0 : 9'd1);
    assign current_write_w = zero_r ? 256'd0 : ram_data_w;
    assign target_join_w = {current_write_w, previous_write_r};
    assign target_shift_w = target_join_w << {dst_addr_w[4:0], 3'd0};
    assign wr_data_o = dst_addr_w[4:0] == 0 ? current_write_w : target_shift_w[511:256];
    assign write_next_w = write_index_r + 10'd1;
    assign data_fire_w = wr_data_valid_o && wr_data_ready_i;
    assign ram_rd_en_w = !cancel_i && ((state_r == S_WRITE && wr_ready_i) ||
        (data_fire_w && write_next_w < normalized_beats_w));
    assign ram_rd_addr_w = state_r == S_WRITE ? 9'd0 : write_next_w[8:0];
    assign write_byte_w = {3'd0, write_index_r, 5'd0};
    assign unused_geometry_w = ^{left_w[17:12], top_w[17:12], right_w[17:12],
        bottom_w[17:12], row_bytes_w[17:15], source_bytes_w[17:16],
        target_bytes_w[17:16], source_shift_w[511:256], target_shift_w[255:0],
        source_rounded_w[17:15], source_rounded_w[4:0], target_rounded_w[17:15],
        target_rounded_w[4:0], rounded_bytes_w[17:15], rounded_bytes_w[4:0]};
    edrv32_ram_rnd_line u_row (
        .clk_i(clk_i),
        .wr_en_i(ram_wr_en_w),
        .wr_addr_i(ram_wr_addr_w),
        .wr_data_i(source_word_w),
        .wr_strb_i(32'hffff_ffff),
        .rd_en_i(ram_rd_en_w),
        .rd_addr_i(ram_rd_addr_w),
        .rd_data_o(ram_data_w)
    );
    assign done_o = state_r == S_DONE;
    assign rd_valid_o = state_r == S_READ && !cancel_i;
    assign rd_addr_o = {src_addr_w[31:5], 5'd0};
    assign rd_bytes_o = source_bytes_w[15:0];
    assign wr_valid_o = state_r == S_WRITE && !cancel_i;
    assign wr_addr_o = {dst_addr_w[31:5], 5'd0};
    assign wr_bytes_o = target_bytes_w[15:0];
    assign wr_data_valid_o = state_r == S_STREAM && !cancel_i;
    assign pixel_count_o = data_fire_w ?
        (argb_w ? {1'd0, enabled_bytes_w[5:2]} : enabled_bytes_w[5:1]) : 5'd0;
    always @(*) begin
        wr_strb_o = 32'd0;
        enabled_bytes_w = 6'd0;
        for (byte_index = 0; byte_index < 32; byte_index = byte_index + 1) begin
            if ({14'd0, write_byte_w} + byte_index >= {27'd0, dst_addr_w[4:0]} &&
                {14'd0, write_byte_w} + byte_index < {14'd0, target_bytes_w}) begin
                wr_strb_o[byte_index] = 1'b1;
                enabled_bytes_w = enabled_bytes_w + 6'd1;
            end
        end
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            y_r <= 12'd0;
            reverse_r <= 1'b0;
            received_r <= 10'd0;
            write_index_r <= 10'd0;
            zero_r <= 1'b0;
        end else if (cancel_i) begin
            state_r <= S_IDLE;
        end else begin
            case (state_r)
                S_IDLE: if (start_i) begin
                    y_r <= top_w[11:0];
                    state_r <= S_SETUP;
                    received_r <= 10'd0;
                    reverse_r <= 1'b0;
                end
                S_SETUP: begin
                    reverse_r <= dst_addr_w > src_addr_w;
                    if (dst_addr_w > src_addr_w)
                        y_r <= bottom_w[11:0];
                    state_r <= S_READ;
                end
                S_READ: if (rd_ready_i) begin
                    state_r <= S_CAPTURE;
                    received_r <= 10'd0;
                end
                S_CAPTURE: begin
                    if (rd_data_valid_i)
                        received_r <= received_r + 10'd1;
                    if (rd_done_i)
                        state_r <= src_addr_w[4:0] != 0 &&
                            source_beats_w == normalized_beats_w ? S_TAIL : S_WRITE;
                end
                S_TAIL: state_r <= S_WRITE;
                S_WRITE: if (wr_ready_i) begin
                    write_index_r <= 10'd0;
                    zero_r <= 1'b0;
                    state_r <= S_STREAM;
                end
                S_STREAM: if (wr_data_ready_i) begin
                    write_index_r <= write_next_w;
                    zero_r <= write_next_w >= normalized_beats_w;
                    if (write_next_w == target_beats_w)
                        state_r <= S_RESPONSE;
                end
                S_RESPONSE: if (wr_done_i) begin
                    if ((reverse_r && y_r == top_w[11:0]) ||
                        (!reverse_r && y_r == bottom_w[11:0]))
                        state_r <= S_DONE;
                    else begin
                        y_r <= reverse_r ? y_r - 12'd1 : y_r + 12'd1;
                        state_r <= S_READ;
                    end
                end
                S_DONE: state_r <= S_IDLE;
                default: state_r <= state_r;
            endcase
        end
    end
    always @(posedge clk_i) begin
        if (state_r == S_CAPTURE && rd_data_valid_i)
            previous_read_r <= rd_data_i;
        if (state_r == S_WRITE && wr_ready_i)
            previous_write_r <= 256'd0;
        else if (data_fire_w)
            previous_write_r <= current_write_w;
    end
endmodule
