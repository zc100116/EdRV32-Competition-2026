// File: edrv32_rnd_fill.v
// Spec: rnd-spec 2.6 FILL, 5.2.
// Description: Opaque solid-color fast path, with one streaming write descriptor per row.
//              Source color replication is constant throughout the command; no target reads.
// Clock domain: clk_mem (clk_i).
module edrv32_rnd_fill (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Clipped opaque non-gradient FILL.
    input wire start_i,
    input wire cancel_i,
    input wire [511:0] command_i,
    output wire done_o,
    output wire [4:0] pixel_count_o,

    // Row descriptor and one-beat-per-cycle data stream.
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
    localparam [3:0] S_DESC = 4'd1;
    localparam [3:0] S_DATA = 4'd2;
    localparam [3:0] S_RESPONSE = 4'd3;
    localparam [3:0] S_DONE = 4'd4;
    localparam [3:0] S_SETUP = 4'd5;
    localparam [3:0] S_ADDRESS = 4'd6;
    localparam [3:0] S_SPAN = 4'd7;
    localparam [3:0] S_OFFSET_LOW = 4'd8;
    localparam [3:0] S_OFFSET_HIGH = 4'd9;
    localparam [3:0] S_ADDR_CARRY = 4'd10;
    localparam [3:0] S_ADDR_COMMIT = 4'd11;
    reg [3:0] state_r;
    reg [14:0] offset_low_r;
    reg [13:0] offset_high_r;
    reg [27:0] row_offset_r;
    reg [31:0] next_addr_r;
    reg [11:0] y_r;
    reg [9:0] beat_r;
    reg [31:0] dst_addr_r;
    reg [27:0] row_product_r;
    reg [13:0] x_bytes_r;
    reg [12:0] row_pixels_r;
    reg [14:0] row_bytes_r;
    reg [15:0] span_bytes_r;
    reg [5:0] span_low_r;
    reg [9:0] last_index_r;
    reg [11:0] left_r;
    reg [11:0] right_r;
    wire [31:0] initial_addr_a_w;
    wire [31:0] initial_addr_b_w;
    reg [12:0] initial_addr_low_r;
    reg [12:0] initial_addr_mid_r;
    reg [7:0] initial_addr_high_r;
    reg [11:0] initial_addr_low_delay_r;
    reg [12:0] initial_addr_mid_carry_r;
    reg [7:0] initial_addr_high_delay_r;
    wire [31:0] next_row_a_w;
    wire [31:0] next_row_b_w;
    reg [12:0] next_row_low_r;
    reg [12:0] next_row_mid_r;
    reg [7:0] next_row_high_r;
    reg [11:0] next_row_low_delay_r;
    reg [12:0] next_row_mid_carry_r;
    reg [7:0] next_row_high_delay_r;
    wire [15:0] span_last_w;
    wire argb_w;
    wire [15:0] color565_w;
    wire signed [17:0] left_w;
    wire signed [17:0] top_w;
    wire signed [17:0] right_w;
    wire signed [17:0] bottom_w;
    wire [16:0] unused_width_w;
    wire [16:0] unused_height_w;
    wire [7:0] unused_op_w;
    wire [3:0] unused_format_w;
    wire [15:0] unused_flags_w;
    wire unused_illegal_w;
    wire unused_empty_w;
    wire unused_fast_w;
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
    // Parent dispatch owns the opcode; this engine receives only opcode 01.
    edrv32_rnd_decode u_decode (
        .command_i({command_i[511:8], 8'h01}),
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
    assign initial_addr_a_w = command_i[63:32];
    assign initial_addr_b_w = {4'd0, row_offset_r};
    assign next_row_a_w = dst_addr_r;
    assign next_row_b_w = {16'd0, command_i[79:64]};
    assign span_last_w = span_bytes_r - 16'd1;
    assign color565_w = {command_i[247:243], command_i[239:234], command_i[231:227]};
    assign wr_data_o = argb_w ? {8{{8'hff, command_i[247:224]}}} : {16{color565_w}};
    assign wr_addr_o = {dst_addr_r[31:5], 5'd0};
    assign wr_bytes_o = span_bytes_r[15:0];
    assign wr_valid_o = state_r == S_DESC && !cancel_i;
    assign wr_data_valid_o = state_r == S_DATA && !cancel_i;
    assign head_bytes_w = 6'd32 - {1'b0, dst_addr_r[4:0]};
    assign tail_bytes_w = span_bytes_r[4:0] == 0 ? 6'd32 : {1'b0, span_bytes_r[4:0]};
    assign beat_pixels_w = first_beat_w && last_beat_w ? single_pixels_r :
        first_beat_w ? head_pixels_r : last_beat_w ? tail_pixels_r : argb_w ? 5'd8 : 5'd16;
    assign pixel_count_o = wr_data_valid_o && wr_data_ready_i ? beat_pixels_w : 5'd0;
    assign done_o = state_r == S_DONE;
    assign unused_geometry_w = ^{command_i[7:0], head_bytes_w[0], tail_bytes_w[0],
        left_w[17:12], top_w[17:12], right_w[17:12],
        bottom_w[17:12], span_last_w[15], span_last_w[4:0]};
    // Only boundary beats need masking; the interior is a full 256-bit transfer.
    assign first_beat_w = beat_r == 0;
    assign last_beat_w = beat_r == last_index_r;
    assign tail_invalid_w = 5'd0 - span_bytes_r[4:0];
    always @(*) begin
        wr_strb_o = (first_beat_w ? 32'hffff_ffff << dst_addr_r[4:0] : 32'hffff_ffff) &
            (last_beat_w ? 32'hffff_ffff >> tail_invalid_w : 32'hffff_ffff);
    end
    // Descriptor setup prepares boundary counts before the streaming datapath starts.
    always @(posedge clk_i) begin
        if (state_r == S_DESC) begin
            head_pixels_r <= argb_w ? {1'b0, head_bytes_w[5:2]} : head_bytes_w[5:1];
            tail_pixels_r <= argb_w ? {1'b0, tail_bytes_w[5:2]} : tail_bytes_w[5:1];
            single_pixels_r <= argb_w ? row_bytes_r[6:2] : row_bytes_r[5:1];
        end
    end
    // spec rnd 5.2: register 12/12/8-bit address sums; stream cycles hide row-step latency.
    always @(posedge clk_i) begin
        if (state_r == S_ADDRESS) begin
            initial_addr_low_r <= {1'b0, initial_addr_a_w[11:0]} + {1'b0, initial_addr_b_w[11:0]};
            initial_addr_mid_r <= {1'b0, initial_addr_a_w[23:12]} + {1'b0, initial_addr_b_w[23:12]};
            initial_addr_high_r <= initial_addr_a_w[31:24] + initial_addr_b_w[31:24];
        end
        if (state_r == S_ADDR_CARRY) begin
            initial_addr_low_delay_r <= initial_addr_low_r[11:0];
            initial_addr_mid_carry_r <= initial_addr_mid_r + {12'd0, initial_addr_low_r[12]};
            initial_addr_high_delay_r <= initial_addr_high_r;
        end
        if (state_r == S_ADDR_COMMIT) begin
            dst_addr_r <= {initial_addr_high_delay_r + {7'd0, initial_addr_mid_carry_r[12]},
                initial_addr_mid_carry_r[11:0], initial_addr_low_delay_r};
        end
        if (state_r == S_RESPONSE && wr_done_i)
            dst_addr_r <= next_addr_r;
    end
    always @(posedge clk_i) begin
        next_row_low_r <= {1'b0, next_row_a_w[11:0]} + {1'b0, next_row_b_w[11:0]};
        next_row_mid_r <= {1'b0, next_row_a_w[23:12]} + {1'b0, next_row_b_w[23:12]};
        next_row_high_r <= next_row_a_w[31:24] + next_row_b_w[31:24];
        next_row_low_delay_r <= next_row_low_r[11:0];
        next_row_mid_carry_r <= next_row_mid_r + {12'd0, next_row_low_r[12]};
        next_row_high_delay_r <= next_row_high_r;
        next_addr_r <= {next_row_high_delay_r + {7'd0, next_row_mid_carry_r[12]},
            next_row_mid_carry_r[11:0], next_row_low_delay_r};
    end
    // spec rnd 2.5: clipped coordinates are 12 bits; DST_STRIDE is 16 bits.
    // The first row uses one registered multiply; later rows advance by DST_STRIDE.
    always @(posedge clk_i) begin
        if (state_r == S_IDLE && start_i) begin
            left_r <= left_w[11:0];
            right_r <= right_w[11:0];
            x_bytes_r <= {2'd0, left_w[11:0]} << (argb_w ? 2 : 1);
        end
        if (state_r == S_SETUP) begin
            row_product_r <= y_r * command_i[79:64];
            row_pixels_r <= {1'b0, right_r} - {1'b0, left_r} + 13'd1;
        end
        if (state_r == S_OFFSET_LOW) begin
            offset_low_r <= {1'b0, row_product_r[13:0]} + {1'b0, x_bytes_r};
            offset_high_r <= row_product_r[27:14];
        end
        if (state_r == S_OFFSET_HIGH)
            row_offset_r <= {offset_high_r + {13'd0, offset_low_r[14]}, offset_low_r[13:0]};
        if (state_r == S_ADDRESS) begin
            row_bytes_r <= {2'd0, row_pixels_r} << (argb_w ? 2 : 1);
        end
        if (state_r == S_ADDR_COMMIT)
            span_low_r <= {1'b0, row_bytes_r[4:0]} + {1'b0, initial_addr_low_delay_r[4:0]};
        if (state_r == S_RESPONSE && wr_done_i)
            span_low_r <= {1'b0, row_bytes_r[4:0]} + {1'b0, next_addr_r[4:0]};
        if (state_r == S_SPAN)
            span_bytes_r <= {{1'b0, row_bytes_r[14:5]} + {10'd0, span_low_r[5]},
                span_low_r[4:0]};
        if (state_r == S_DESC)
            last_index_r <= span_last_w[14:5];
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            y_r <= 12'd0;
            beat_r <= 10'd0;
        end else if (cancel_i)
            state_r <= S_IDLE;
        else begin
            case (state_r)
                S_IDLE: if (start_i) begin
                    y_r <= top_w[11:0];
                    state_r <= S_SETUP;
                end
                S_SETUP: state_r <= S_OFFSET_LOW;
                S_OFFSET_LOW: state_r <= S_OFFSET_HIGH;
                S_OFFSET_HIGH: state_r <= S_ADDRESS;
                S_ADDRESS: state_r <= S_ADDR_CARRY;
                S_ADDR_CARRY: state_r <= S_ADDR_COMMIT;
                S_ADDR_COMMIT: state_r <= S_SPAN;
                S_SPAN: state_r <= S_DESC;
                S_DESC: if (wr_ready_i) begin
                    beat_r <= 10'd0;
                    state_r <= S_DATA;
                end
                S_DATA: if (wr_data_ready_i) begin
                    beat_r <= beat_r + 10'd1;
                    if (beat_r == last_index_r)
                        state_r <= S_RESPONSE;
                end
                S_RESPONSE: if (wr_done_i) begin
                    if (y_r == bottom_w[11:0])
                        state_r <= S_DONE;
                    else begin
                        y_r <= y_r + 12'd1;
                        state_r <= S_SPAN;
                    end
                end
                S_DONE: state_r <= S_IDLE;
                default: state_r <= state_r;
            endcase
        end
    end
endmodule
