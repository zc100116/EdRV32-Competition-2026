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
    localparam [4:0] S_IDLE = 5'd0;
    localparam [4:0] S_READ = 5'd1;
    localparam [4:0] S_CAPTURE = 5'd2;
    localparam [4:0] S_TAIL = 5'd3;
    localparam [4:0] S_WRITE = 5'd4;
    localparam [4:0] S_STREAM = 5'd5;
    localparam [4:0] S_RESPONSE = 5'd6;
    localparam [4:0] S_DONE = 5'd7;
    localparam [4:0] S_SETUP = 5'd8;
    localparam [4:0] S_COORD = 5'd9;
    localparam [4:0] S_SOURCE = 5'd10;
    localparam [4:0] S_MULT = 5'd11;
    localparam [4:0] S_BASE = 5'd12;
    localparam [4:0] S_SPAN = 5'd13;
    localparam [4:0] S_COUNTS = 5'd14;
    localparam [4:0] S_OFFSET1 = 5'd15;
    localparam [4:0] S_OFFSET2 = 5'd16;
    localparam [4:0] S_OFFSET3 = 5'd17;
    localparam [4:0] S_BASE2 = 5'd18;
    localparam [4:0] S_BASE3 = 5'd19;
    localparam [4:0] S_INITIAL_ROW = 5'd20;
    localparam [4:0] S_DRAIN = 5'd21;
    localparam [4:0] S_PRIME = 5'd22;
    reg [4:0] state_r;
    reg [2:0] source_words_r;
    reg [2:0] target_words_r;
    reg source_aligned_r;
    reg source_valid_r;
    reg [8:0] source_index_r;
    reg [279:0] source_word_r;
    reg [279:0] target_word_r;
    wire [511:0] source_words_w;
    wire source_write_w;
    reg [11:0] top_r;
    reg [11:0] bottom_r;
    reg [19:0] src_bytes_r;
    reg [13:0] dst_bytes_r;
    reg [31:0] src_offset_r;
    reg [31:0] dst_offset_r;
    reg signed [16:0] src_step_r;
    reg signed [16:0] dst_step_r;
    reg signed [16:0] src_neg_step_r;
    reg signed [16:0] dst_neg_step_r;
    reg [31:0] src_next_r;
    reg [31:0] dst_next_r;
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
    reg [31:0] dst_addr_r;
    reg [31:0] src_addr_r;
    reg [15:0] source_kx_r;
    reg [15:0] source_ky_r;
    reg [16:0] source_x_r;
    reg [16:0] source_y_r;
    reg [27:0] dst_product_r;
    reg [31:0] src_product_r;
    reg [12:0] row_pixels_r;
    reg [14:0] row_bytes_r;
    reg [15:0] source_bytes_r;
    reg [15:0] target_bytes_r;
    reg [5:0] src_span_low_r;
    reg [5:0] dst_span_low_r;
    reg [9:0] normalized_beats_r;
    reg [9:0] source_beats_r;
    reg [9:0] target_last_r;
    reg [9:0] normalized_last_r;
    reg [11:0] left_r;
    reg [11:0] right_r;
    wire [31:0] src_init_a_w;
    wire [31:0] src_init_b_w;
    reg [12:0] src_init_low_r;
    reg [12:0] src_init_mid_r;
    reg [7:0] src_init_high_r;
    reg [11:0] src_init_low_delay_r;
    reg [12:0] src_init_mid_carry_r;
    reg [7:0] src_init_high_delay_r;
    wire [31:0] src_row_a_w;
    wire [31:0] src_row_b_w;
    reg [12:0] src_row_low_r;
    reg [12:0] src_row_mid_r;
    reg [7:0] src_row_high_r;
    reg [11:0] src_row_low_delay_r;
    reg [12:0] src_row_mid_carry_r;
    reg [7:0] src_row_high_delay_r;
    wire [31:0] dst_init_a_w;
    wire [31:0] dst_init_b_w;
    reg [12:0] dst_init_low_r;
    reg [12:0] dst_init_mid_r;
    reg [7:0] dst_init_high_r;
    reg [11:0] dst_init_low_delay_r;
    reg [12:0] dst_init_mid_carry_r;
    reg [7:0] dst_init_high_delay_r;
    wire [31:0] dst_row_a_w;
    wire [31:0] dst_row_b_w;
    reg [12:0] dst_row_low_r;
    reg [12:0] dst_row_mid_r;
    reg [7:0] dst_row_high_r;
    reg [11:0] dst_row_low_delay_r;
    reg [12:0] dst_row_mid_carry_r;
    reg [7:0] dst_row_high_delay_r;
    wire [19:0] source_x_bytes_w;
    wire [15:0] rounded_bytes_w;
    wire [15:0] source_rounded_w;
    wire [15:0] target_last_bytes_w;
    wire [14:0] row_last_bytes_w;
    wire [511:0] source_join_w;
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
    wire unused_geometry_w;
    reg [4:0] head_pixels_r;
    reg [4:0] tail_pixels_r;
    reg [4:0] single_pixels_r;
    wire [5:0] head_bytes_w;
    wire [5:0] tail_bytes_w;
    wire [4:0] beat_pixels_w;
    wire [4:0] tail_invalid_w;
    wire first_beat_w;
    wire last_beat_w;

    // Parent dispatch owns the opcode; this engine receives only opcode 05.
    edrv32_rnd_decode u_decode (
        .command_i({command_i[511:8], 8'h05}),
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
    assign src_init_a_w = state_r == S_OFFSET1 ? src_product_r : command_i[287:256];
    assign src_init_b_w = state_r == S_OFFSET1 ? {12'd0, src_bytes_r} : src_offset_r;
    assign src_row_a_w = src_addr_r;
    assign src_row_b_w = {{15{src_step_r[16]}}, src_step_r};
    assign dst_init_a_w = state_r == S_OFFSET1 ? {4'd0, dst_product_r} : command_i[63:32];
    assign dst_init_b_w = state_r == S_OFFSET1 ? {18'd0, dst_bytes_r} : dst_offset_r;
    assign dst_row_a_w = dst_addr_r;
    assign dst_row_b_w = {{15{dst_step_r[16]}}, dst_step_r};
    assign source_x_bytes_w = {3'd0, source_x_r} << (argb_w ? 2 : 1);
    assign rounded_bytes_w = {1'b0, row_bytes_r} + 16'd31;
    assign source_rounded_w = source_bytes_r + 16'd31;
    assign target_last_bytes_w = target_bytes_r - 16'd1;
    assign row_last_bytes_w = row_bytes_r - 15'd1;
    // Local controls drive 128 data bits each without delaying the source stream.
    genvar join_slice;
    generate for (join_slice = 0; join_slice < 4; join_slice = join_slice + 1) begin
        : g_source_join
        reg aligned_r /* synthesis syn_preserve=1 */;
        reg tail_r /* synthesis syn_preserve=1 */;
        always @(posedge clk_i) begin
            if (state_r == S_COUNTS)
                aligned_r <= src_addr_r[4:0] == 0;
        end
        always @(posedge clk_i or negedge rst_n_i) begin
            if (!rst_n_i)
                tail_r <= 1'b0;
            else if (cancel_i)
                tail_r <= 1'b0;
            else
                tail_r <= state_r == S_CAPTURE && rd_done_i && src_addr_r[4:0] != 0 &&
                    source_beats_r == normalized_beats_r;
        end
        if (join_slice < 2) begin : g_low
            assign source_join_w[join_slice*128 +: 128] = !tail_r && aligned_r ?
                rd_data_i[join_slice*128 +: 128] : previous_read_r[join_slice*128 +: 128];
        end else begin : g_high
            assign source_join_w[join_slice*128 +: 128] = tail_r || aligned_r ? 128'd0 :
                rd_data_i[(join_slice-2)*128 +: 128];
        end
    end endgenerate
    assign source_words_w = source_join_w >> {source_words_r, 5'd0};
    assign source_write_w = !cancel_i && (state_r == S_TAIL ||
        (state_r == S_CAPTURE && rd_data_valid_i &&
            (source_aligned_r || received_r != 0)));
    assign ram_wr_en_w = source_valid_r && !cancel_i;
    assign ram_wr_addr_w = source_index_r;
    assign current_write_w = zero_r ? 256'd0 : ram_data_w;
    assign target_join_w = {current_write_w, previous_write_r};
    assign target_shift_w = target_join_w << {target_words_r, 5'd0};
    assign write_next_w = write_index_r + 10'd1;
    assign data_fire_w = wr_data_valid_o && wr_data_ready_i;
    assign ram_rd_en_w = !cancel_i && ((state_r == S_WRITE && wr_ready_i) ||
        ((state_r == S_PRIME || data_fire_w) && (state_r == S_PRIME ? normalized_last_r != 0 :
            write_next_w < normalized_last_r)));
    assign ram_rd_addr_w = state_r == S_WRITE ? 9'd0 :
        state_r == S_PRIME ? 9'd1 : write_index_r[8:0] + 9'd2;
    assign unused_geometry_w = ^{command_i[7:0], head_bytes_w[0], tail_bytes_w[0],
        left_w[17:12], top_w[17:12], right_w[17:12],
        bottom_w[17:12], source_x_bytes_w[19:18],
        source_words_w[511:280], target_shift_w[231:0],
        source_rounded_w[15], source_rounded_w[4:0], target_last_bytes_w[15],
        target_last_bytes_w[4:0], row_last_bytes_w[4:0], rounded_bytes_w[15], rounded_bytes_w[4:0]};
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
    assign rd_addr_o = {src_addr_r[31:5], 5'd0};
    assign rd_bytes_o = source_bytes_r[15:0];
    assign wr_valid_o = state_r == S_WRITE && !cancel_i;
    assign wr_addr_o = {dst_addr_r[31:5], 5'd0};
    assign wr_bytes_o = target_bytes_r[15:0];
    assign wr_data_valid_o = state_r == S_STREAM && !cancel_i;
    assign head_bytes_w = 6'd32 - {1'b0, dst_addr_r[4:0]};
    assign tail_bytes_w = target_bytes_r[4:0] == 0 ? 6'd32 : {1'b0, target_bytes_r[4:0]};
    assign beat_pixels_w = first_beat_w && last_beat_w ? single_pixels_r :
        first_beat_w ? head_pixels_r : last_beat_w ? tail_pixels_r : argb_w ? 5'd8 : 5'd16;
    assign pixel_count_o = data_fire_w ? beat_pixels_w : 5'd0;
    // Only boundary beats need masking; the interior is a full 256-bit transfer.
    assign first_beat_w = write_index_r == 0;
    assign last_beat_w = write_index_r == target_last_r;
    assign tail_invalid_w = 5'd0 - target_bytes_r[4:0];
    always @(*) begin
        wr_strb_o = (first_beat_w ? 32'hffff_ffff << dst_addr_r[4:0] : 32'hffff_ffff) &
            (last_beat_w ? 32'hffff_ffff >> tail_invalid_w : 32'hffff_ffff);
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
                    state_r <= S_INITIAL_ROW;
                    received_r <= 10'd0;
                    reverse_r <= 1'b0;
                end
                S_INITIAL_ROW: begin
                    y_r <= top_r;
                    state_r <= S_COORD;
                end
                S_COORD: state_r <= S_SOURCE;
                S_SOURCE: state_r <= S_MULT;
                S_MULT: state_r <= S_OFFSET1;
                S_OFFSET1: state_r <= S_OFFSET2;
                S_OFFSET2: state_r <= S_OFFSET3;
                S_OFFSET3: state_r <= S_BASE;
                S_BASE: state_r <= S_BASE2;
                S_BASE2: state_r <= S_BASE3;
                S_BASE3: state_r <= reverse_r ? S_SPAN : S_SETUP;
                S_SPAN: state_r <= S_COUNTS;
                S_COUNTS: state_r <= S_READ;
                S_SETUP: begin
                    reverse_r <= dst_addr_r > src_addr_r;
                    if (dst_addr_r > src_addr_r) begin
                        y_r <= bottom_r;
                        state_r <= S_COORD;
                    end else
                        state_r <= S_SPAN;
                end
                S_READ: if (rd_ready_i) begin
                    state_r <= S_CAPTURE;
                    received_r <= 10'd0;
                end
                S_CAPTURE: begin
                    if (rd_data_valid_i)
                        received_r <= received_r + 10'd1;
                    if (rd_done_i)
                        state_r <= src_addr_r[4:0] != 0 &&
                            source_beats_r == normalized_beats_r ? S_TAIL : S_DRAIN;
                end
                S_TAIL: state_r <= S_DRAIN;
                S_DRAIN: state_r <= S_WRITE;
                S_WRITE: if (wr_ready_i) begin
                    write_index_r <= 10'd0;
                    zero_r <= 1'b0;
                    state_r <= S_PRIME;
                end
                S_PRIME: begin
                    zero_r <= normalized_last_r == 0;
                    state_r <= S_STREAM;
                end
                S_STREAM: if (wr_data_ready_i) begin
                    write_index_r <= write_next_w;
                    zero_r <= write_next_w >= normalized_last_r;
                    if (write_index_r == target_last_r)
                        state_r <= S_RESPONSE;
                end
                S_RESPONSE: if (wr_done_i) begin
                    if ((reverse_r && y_r == top_r) ||
                        (!reverse_r && y_r == bottom_r))
                        state_r <= S_DONE;
                    else begin
                        y_r <= reverse_r ? y_r - 12'd1 : y_r + 12'd1;
                        state_r <= S_SPAN;
                    end
                end
                S_DONE: state_r <= S_IDLE;
                default: state_r <= state_r;
            endcase
        end
    end
    // Each 64-bit slice owns the residual byte selection after the word register.
    genvar slice;
    generate for (slice = 0; slice < 4; slice = slice + 1) begin : g_align
        (* keep = "true", syn_preserve = 1 *) reg [1:0] source_byte_r;
        (* keep = "true", syn_preserve = 1 *) reg [1:0] target_byte_r;
        wire [87:0] source_shift_w;
        wire [87:0] target_slice_w;
        wire unused_shift_w;
        assign source_shift_w = source_word_r[slice*64 +: 88] >> {source_byte_r, 3'd0};
        assign target_slice_w = target_word_r[slice*64 +: 88] << {target_byte_r, 3'd0};
        assign source_word_w[slice*64 +: 64] = source_shift_w[63:0];
        assign wr_data_o[slice*64 +: 64] = target_slice_w[87:24];
        assign unused_shift_w = ^{source_shift_w[87:64], target_slice_w[23:0]};
        localparam [4:0] SELECT_STATE = slice == 0 ? S_SPAN : slice == 1 ? S_COUNTS :
            slice == 2 ? S_READ : S_CAPTURE;
        always @(posedge clk_i) begin
            if (state_r == SELECT_STATE) begin
                source_byte_r <= src_addr_r[1:0];
                target_byte_r <= dst_addr_r[1:0];
            end
        end
    end endgenerate
    // Word selection is registered before the residual 0..3 byte shift.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            source_valid_r <= 1'b0;
        else if (cancel_i)
            source_valid_r <= 1'b0;
        else
            source_valid_r <= source_write_w;
    end
    always @(posedge clk_i) begin
        if (state_r == S_COUNTS) begin
            source_words_r <= src_addr_r[4:2];
            source_aligned_r <= src_addr_r[4:0] == 0;
            target_words_r <= dst_addr_r[4:2];
        end
        // source_valid_r qualifies this payload on the following RAM-write edge.
        source_word_r <= source_words_w[279:0];
        source_index_r <= state_r == S_TAIL ? normalized_last_r[8:0] :
            received_r[8:0] - (source_aligned_r ? 9'd0 : 9'd1);
        if (state_r == S_PRIME || data_fire_w)
            target_word_r <= target_shift_w[511:232];
    end
    // Descriptor setup prepares boundary counts before the streaming datapath starts.
    always @(posedge clk_i) begin
        if (state_r == S_WRITE && wr_ready_i) begin
            head_pixels_r <= argb_w ? {1'b0, head_bytes_w[5:2]} : head_bytes_w[5:1];
            tail_pixels_r <= argb_w ? {1'b0, tail_bytes_w[5:2]} : tail_bytes_w[5:1];
            single_pixels_r <= argb_w ? row_bytes_r[6:2] : row_bytes_r[5:1];
        end
    end
    // spec rnd 5.2: reuse registered 12/12/8-bit sums for row offsets and initial bases.
    always @(posedge clk_i) begin
        if (state_r == S_OFFSET1 || state_r == S_BASE) begin
            src_init_low_r <= {1'b0, src_init_a_w[11:0]} + {1'b0, src_init_b_w[11:0]};
            src_init_mid_r <= {1'b0, src_init_a_w[23:12]} + {1'b0, src_init_b_w[23:12]};
            src_init_high_r <= src_init_a_w[31:24] + src_init_b_w[31:24];
        end
        if (state_r == S_OFFSET2 || state_r == S_BASE2) begin
            src_init_low_delay_r <= src_init_low_r[11:0];
            src_init_mid_carry_r <= src_init_mid_r + {12'd0, src_init_low_r[12]};
            src_init_high_delay_r <= src_init_high_r;
        end
        if (state_r == S_BASE3) begin
            src_addr_r <= {src_init_high_delay_r + {7'd0, src_init_mid_carry_r[12]},
                src_init_mid_carry_r[11:0], src_init_low_delay_r};
        end
        if (state_r == S_OFFSET3)
            src_offset_r <= {src_init_high_delay_r + {7'd0, src_init_mid_carry_r[12]},
                src_init_mid_carry_r[11:0], src_init_low_delay_r};
        if (state_r == S_RESPONSE && wr_done_i)
            src_addr_r <= src_next_r;
    end
    always @(posedge clk_i) begin
        src_row_low_r <= {1'b0, src_row_a_w[11:0]} + {1'b0, src_row_b_w[11:0]};
        src_row_mid_r <= {1'b0, src_row_a_w[23:12]} + {1'b0, src_row_b_w[23:12]};
        src_row_high_r <= src_row_a_w[31:24] + src_row_b_w[31:24];
        src_row_low_delay_r <= src_row_low_r[11:0];
        src_row_mid_carry_r <= src_row_mid_r + {12'd0, src_row_low_r[12]};
        src_row_high_delay_r <= src_row_high_r;
        src_next_r <= {src_row_high_delay_r + {7'd0, src_row_mid_carry_r[12]},
            src_row_mid_carry_r[11:0], src_row_low_delay_r};
    end
    always @(posedge clk_i) begin
        if (state_r == S_OFFSET1 || state_r == S_BASE) begin
            dst_init_low_r <= {1'b0, dst_init_a_w[11:0]} + {1'b0, dst_init_b_w[11:0]};
            dst_init_mid_r <= {1'b0, dst_init_a_w[23:12]} + {1'b0, dst_init_b_w[23:12]};
            dst_init_high_r <= dst_init_a_w[31:24] + dst_init_b_w[31:24];
        end
        if (state_r == S_OFFSET2 || state_r == S_BASE2) begin
            dst_init_low_delay_r <= dst_init_low_r[11:0];
            dst_init_mid_carry_r <= dst_init_mid_r + {12'd0, dst_init_low_r[12]};
            dst_init_high_delay_r <= dst_init_high_r;
        end
        if (state_r == S_BASE3) begin
            dst_addr_r <= {dst_init_high_delay_r + {7'd0, dst_init_mid_carry_r[12]},
                dst_init_mid_carry_r[11:0], dst_init_low_delay_r};
        end
        if (state_r == S_OFFSET3)
            dst_offset_r <= {dst_init_high_delay_r + {7'd0, dst_init_mid_carry_r[12]},
                dst_init_mid_carry_r[11:0], dst_init_low_delay_r};
        if (state_r == S_RESPONSE && wr_done_i)
            dst_addr_r <= dst_next_r;
    end
    always @(posedge clk_i) begin
        dst_row_low_r <= {1'b0, dst_row_a_w[11:0]} + {1'b0, dst_row_b_w[11:0]};
        dst_row_mid_r <= {1'b0, dst_row_a_w[23:12]} + {1'b0, dst_row_b_w[23:12]};
        dst_row_high_r <= dst_row_a_w[31:24] + dst_row_b_w[31:24];
        dst_row_low_delay_r <= dst_row_low_r[11:0];
        dst_row_mid_carry_r <= dst_row_mid_r + {12'd0, dst_row_low_r[12]};
        dst_row_high_delay_r <= dst_row_high_r;
        dst_next_r <= {dst_row_high_delay_r + {7'd0, dst_row_mid_carry_r[12]},
            dst_row_mid_carry_r[11:0], dst_row_low_delay_r};
    end
    // spec rnd 2.5/2.6 COPY: 12-bit CLIP, 16-bit unsigned SRC_X/Y and stride,
    // Valid clipping gives 0<=x-X0,y-Y0<=36863 (16 bits); adding SRC_X/Y fits 17 bits.
    // COPY has no scaling; each row advances the registered addresses by one stride.
    always @(posedge clk_i) begin
        if (state_r == S_IDLE && start_i) begin
            top_r <= top_w[11:0];
            bottom_r <= bottom_w[11:0];
            left_r <= left_w[11:0];
            right_r <= right_w[11:0];
            src_neg_step_r <= -$signed({1'b0, command_i[303:288]});
            dst_neg_step_r <= -$signed({1'b0, command_i[79:64]});
        end
        if (state_r == S_COORD) begin
            source_kx_r <= {4'd0, left_r} - command_i[175:160];
            source_ky_r <= {4'd0, y_r} - command_i[191:176];
        end
        if (state_r == S_SOURCE) begin
            source_x_r <= {1'b0, command_i[335:320]} + {1'b0, source_kx_r};
            source_y_r <= {1'b0, command_i[351:336]} + {1'b0, source_ky_r};
            row_pixels_r <= {1'b0, right_r} - {1'b0, left_r} + 13'd1;
        end
        if (state_r == S_MULT) begin
            dst_product_r <= y_r * command_i[79:64];
            src_product_r <= source_y_r * command_i[303:288];
            src_bytes_r <= source_x_bytes_w;
            dst_bytes_r <= {2'd0, left_r} << (argb_w ? 2 : 1);
            row_bytes_r <= {2'd0, row_pixels_r} << (argb_w ? 2 : 1);
        end
        if (state_r == S_BASE3)
            normalized_beats_r <= rounded_bytes_w[14:5];
        if (state_r == S_SETUP) begin
            src_step_r <= dst_addr_r > src_addr_r ? src_neg_step_r :
                $signed({1'b0, command_i[303:288]});
            dst_step_r <= dst_addr_r > src_addr_r ? dst_neg_step_r :
                $signed({1'b0, command_i[79:64]});
        end
        if (state_r == S_BASE3) begin
            src_span_low_r <= {1'b0, row_bytes_r[4:0]} + {1'b0, src_init_low_delay_r[4:0]};
            dst_span_low_r <= {1'b0, row_bytes_r[4:0]} + {1'b0, dst_init_low_delay_r[4:0]};
        end
        if (state_r == S_RESPONSE && wr_done_i) begin
            src_span_low_r <= {1'b0, row_bytes_r[4:0]} + {1'b0, src_next_r[4:0]};
            dst_span_low_r <= {1'b0, row_bytes_r[4:0]} + {1'b0, dst_next_r[4:0]};
        end
        if (state_r == S_SPAN) begin
            source_bytes_r <= {{1'b0, row_bytes_r[14:5]} + {10'd0, src_span_low_r[5]},
                src_span_low_r[4:0]};
            target_bytes_r <= {{1'b0, row_bytes_r[14:5]} + {10'd0, dst_span_low_r[5]},
                dst_span_low_r[4:0]};
        end
        if (state_r == S_COUNTS) begin
            source_beats_r <= source_rounded_w[14:5];
            target_last_r <= target_last_bytes_w[14:5];
            normalized_last_r <= row_last_bytes_w[14:5];
        end
    end
    always @(posedge clk_i) begin
        if (state_r == S_CAPTURE && rd_data_valid_i)
            previous_read_r <= rd_data_i;
        if (state_r == S_WRITE && wr_ready_i)
            previous_write_r <= 256'd0;
        else if (state_r == S_PRIME || data_fire_w)
            previous_write_r <= current_write_w;
    end
endmodule
