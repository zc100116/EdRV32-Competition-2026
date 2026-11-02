// File: edrv32_rnd_blit.v
// Spec: rnd-spec 2.2, 2.6 BLIT, 5.2, 7.
// Description: Aligned 1:1 ARGB row streaming, with two source and two target RAM banks.
//              Read loading, two-pixel arithmetic and DDR writeback overlap across rows.
// Clock domain: clk_mem (clk_i).
module edrv32_rnd_blit (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Eligible normal-mode 1:1 command; eligibility is selected by the parent.
    input wire start_i,
    input wire cancel_i,
    input wire [511:0] command_i,
    output wire done_o,
    output wire [4:0] pixel_count_o,
    output wire read_wait_o,
    output wire write_wait_o,

    // Source/target row read DMA client.
    output wire rd_valid_o,
    input wire rd_ready_i,
    output wire [31:0] rd_addr_o,
    output wire [15:0] rd_bytes_o,
    input wire rd_data_valid_i,
    input wire [255:0] rd_data_i,
    input wire rd_done_i,

    // Result row write DMA client.
    output wire wr_valid_o,
    input wire wr_ready_i,
    output wire [31:0] wr_addr_o,
    output wire [15:0] wr_bytes_o,
    output wire wr_data_valid_o,
    input wire wr_data_ready_i,
    output wire [255:0] wr_data_o,
    output wire [31:0] wr_strb_o,
    input wire wr_done_i,

    // Shared alpha pipeline. Tag carries bank ownership and the pair index.
    output wire blend_valid_o,
    input wire blend_ready_i,
    output wire [63:0] blend_src_o,
    output wire [63:0] blend_dst_o,
    output wire [31:0] blend_tag_o,
    input wire blend_valid_i,
    input wire [63:0] blend_pixel_i,
    input wire [31:0] blend_tag_i,
    input wire [7:0] blend_offset_i
);
    localparam [2:0] S_LOAD_IDLE = 3'd0;
    localparam [2:0] S_LOAD_SOURCE = 3'd1;
    localparam [2:0] S_SOURCE_DATA = 3'd2;
    localparam [2:0] S_LOAD_TARGET = 3'd3;
    localparam [2:0] S_TARGET_DATA = 3'd4;
    localparam [2:0] S_LOAD_COORD = 3'd5;
    localparam [2:0] S_LOAD_PRODUCT = 3'd6;
    localparam [2:0] S_LOAD_ADDR = 3'd7;
    localparam [1:0] S_RENDER_IDLE = 2'd0;
    localparam [1:0] S_RENDER_STREAM = 2'd1;
    localparam [1:0] S_RENDER_DRAIN = 2'd2;
    localparam [1:0] S_WRITE_IDLE = 2'd0;
    localparam [1:0] S_WRITE_DESC = 2'd1;
    localparam [1:0] S_WRITE_DATA = 2'd2;
    localparam [1:0] S_WRITE_RESPONSE = 2'd3;
    reg active_r;
    reg done_r;
    reg [2:0] load_state_r;
    reg [1:0] render_state_r;
    reg [1:0] write_state_r;
    reg load_bank_r;
    reg render_bank_r;
    reg write_bank_r;
    reg [1:0] busy_r;
    reg [1:0] loaded_r;
    reg [1:0] rendered_r;
    reg [11:0] bank_y_r [0:1];
    reg [11:0] load_y_r;
    reg loaded_all_r;
    reg [8:0] load_beat_r;
    reg [11:0] issue_pair_r;
    reg memory_valid_r;
    reg source_valid_r;
    reg opacity_valid_r;
    reg [63:0] source_pixel1_r;
    reg [63:0] source_pixel2_r;
    reg [63:0] target_pixel1_r;
    reg [63:0] target_pixel2_r;
    reg [31:0] source_tag1_r;
    reg [31:0] source_tag2_r;
    reg [15:0] opacity_product_r [0:1];
    reg [11:0] clip_left_r;
    reg [11:0] clip_right_r;
    reg [11:0] clip_bottom_r;
    reg [16:0] source_x_offset_r;
    reg [16:0] source_y_offset_r;
    reg [16:0] source_x_r;
    reg [16:0] source_y_r;
    reg [31:0] source_product_r;
    reg [31:0] target_product_r;
    reg [31:0] source_base_r;
    reg [31:0] target_base_r;
    reg [31:0] source_addr_r;
    reg [31:0] bank_target_r [0:1];
    reg [12:0] row_pixels_r;
    reg [11:0] row_pairs_r;
    reg [9:0] row_beats_r;
    reg [10:0] memory_pair_r;
    reg [8:0] write_beat_r;
    wire [7:0] unused_op_w;
    wire unused_argb_w;
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
    wire [17:0] row_pixels_w;
    wire [11:0] row_pairs_w;
    wire [9:0] row_beats_w;
    wire [255:0] src_data_w [0:1];
    wire [255:0] dst_data_w [0:1];
    wire [255:0] render_src_shift_w;
    wire [255:0] render_dst_shift_w;
    wire [63:0] raw_src_w;
    wire load_start_w;
    wire load_finish_w;
    wire render_start_w;
    wire render_finish_w;
    wire write_start_w;
    wire write_finish_w;
    wire issue_w;
    wire [255:0] result_w;
    wire [31:0] result_strb_w;
    wire [9:0] next_write_w;
    wire unused_geometry_w;

    function automatic [7:0] opacity;
        input [15:0] product_i;
        reg [15:0] biased;
        reg [15:0] rounded;
        reg [7:0] unused_low;
        begin
            biased = product_i + 16'd128;
            rounded = biased + (biased >> 8);
            opacity = rounded[15:8];
            unused_low = rounded[7:0];
        end
    endfunction
    // The parent's eligibility check owns opcode validation; only opcode 04 reaches here.
    edrv32_rnd_decode u_decode (
        .command_i({command_i[511:8], 8'h04}),
        .illegal_o(unused_illegal_w),
        .empty_o(unused_empty_w),
        .op_o(unused_op_w),
        .argb_o(unused_argb_w),
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
    assign row_pixels_w = {5'd0, row_pixels_r};
    assign row_pairs_w = row_pairs_r;
    assign row_beats_w = row_beats_r;
    assign load_start_w = active_r && load_state_r == S_LOAD_IDLE &&
        !loaded_all_r && !busy_r[load_bank_r];
    assign load_finish_w = load_state_r == S_TARGET_DATA && rd_done_i;
    assign render_start_w = active_r && render_state_r == S_RENDER_IDLE &&
        loaded_r[render_bank_r];
    assign render_finish_w = blend_valid_i &&
        {1'd0, blend_tag_i[10:0]} + 12'd1 == row_pairs_w;
    assign write_start_w = active_r && write_state_r == S_WRITE_IDLE &&
        rendered_r[write_bank_r];
    assign write_finish_w = write_state_r == S_WRITE_RESPONSE && wr_done_i;
    assign issue_w = render_state_r == S_RENDER_STREAM && issue_pair_r < row_pairs_w;
    assign render_src_shift_w = src_data_w[render_bank_r] >> {memory_pair_r[1:0], 6'd0};
    assign render_dst_shift_w = dst_data_w[render_bank_r] >> {memory_pair_r[1:0], 6'd0};
    assign raw_src_w = render_src_shift_w[63:0];
    assign blend_src_o = {opacity(opacity_product_r[1]), source_pixel2_r[55:32],
        opacity(opacity_product_r[0]), source_pixel2_r[23:0]};
    assign blend_dst_o = target_pixel2_r;
    assign blend_valid_o = opacity_valid_r;
    assign blend_tag_o = source_tag2_r;
    genvar result_quadrant;
    generate for (result_quadrant = 0; result_quadrant < 4;
        result_quadrant = result_quadrant + 1) begin : g_result_shift
        assign result_w[result_quadrant*64 +: 64] =
            blend_offset_i[result_quadrant*2 +: 2] == result_quadrant ? blend_pixel_i : 64'd0;
    end endgenerate
    assign result_strb_w = 32'h0000_00ff << {blend_tag_i[1:0], 3'd0};
    assign next_write_w = {1'd0, write_beat_r} + 10'd1;
    assign rd_valid_o = !cancel_i &&
        (load_state_r == S_LOAD_SOURCE || load_state_r == S_LOAD_TARGET);
    assign rd_addr_o = load_state_r == S_LOAD_SOURCE ?
        source_addr_r : bank_target_r[load_bank_r];
    assign rd_bytes_o = {row_pixels_w[13:0], 2'd0};
    assign wr_valid_o = write_state_r == S_WRITE_DESC && !cancel_i;
    assign wr_addr_o = bank_target_r[write_bank_r];
    assign wr_bytes_o = rd_bytes_o;
    assign wr_data_valid_o = write_state_r == S_WRITE_DATA && !cancel_i;
    genvar write_slice;
    generate for (write_slice = 0; write_slice < 4; write_slice = write_slice + 1) begin
        : g_write_select
        reg bank_r /* synthesis syn_preserve=1 */;
        wire [255:0] selected_w;
        wire unused_selected_w;
        always @(posedge clk_i or negedge rst_n_i) begin
            if (!rst_n_i)
                bank_r <= 1'b0;
            else if (cancel_i || start_i)
                bank_r <= 1'b0;
            else if (write_state_r == S_WRITE_RESPONSE && wr_done_i)
                bank_r <= !write_bank_r;
        end
        assign selected_w = dst_data_w[bank_r];
        assign wr_data_o[write_slice*64 +: 64] = selected_w[write_slice*64 +: 64];
        assign unused_selected_w = ^selected_w;
    end endgenerate
    assign wr_strb_o = 32'hffff_ffff;
    assign done_o = done_r;
    assign pixel_count_o = blend_valid_i ? 5'd2 : 5'd0;
    assign read_wait_o = active_r && render_state_r == S_RENDER_IDLE &&
        !loaded_r[render_bank_r] && !rendered_r[render_bank_r];
    assign write_wait_o = active_r && load_state_r == S_LOAD_IDLE &&
        busy_r[load_bank_r] && write_state_r != S_WRITE_IDLE;
    assign unused_geometry_w = ^{command_i[7:0],left_w[17:12], top_w[17:12], right_w[17:12],
        bottom_w[17:12], row_pixels_w[17:14], row_pixels_w[0], render_src_shift_w[255:64],
        render_dst_shift_w[255:64], blend_tag_i[30:11],
        source_pixel2_r[63:56], source_pixel2_r[31:24]};

    genvar bank;
    generate for (bank = 0; bank < 2; bank = bank + 1) begin : g_bank
        wire load_source_w;
        wire load_target_w;
        wire render_read_w;
        wire write_read_w;
        wire result_write_w;
        wire [8:0] dst_read_addr_w;
        assign load_source_w = load_state_r == S_SOURCE_DATA && load_bank_r == bank &&
            rd_data_valid_i;
        assign load_target_w = load_state_r == S_TARGET_DATA && load_bank_r == bank &&
            rd_data_valid_i;
        assign render_read_w = render_bank_r == bank && issue_w && blend_ready_i;
        assign write_read_w = write_bank_r == bank &&
            ((write_state_r == S_WRITE_DESC && wr_ready_i) ||
            (write_state_r == S_WRITE_DATA && wr_data_ready_i &&
                next_write_w < row_beats_w));
        assign result_write_w = blend_valid_i && blend_tag_i[31] == bank;
        assign dst_read_addr_w = render_read_w ? issue_pair_r[10:2] :
            write_state_r == S_WRITE_DESC ? 9'd0 : next_write_w[8:0];
        edrv32_ram_rnd_line u_source (
            .clk_i(clk_i),
            .wr_en_i(load_source_w && !cancel_i),
            .wr_addr_i(load_beat_r),
            .wr_data_i(rd_data_i),
            .wr_strb_i(32'hffff_ffff),
            .rd_en_i(render_read_w && !cancel_i),
            .rd_addr_i(issue_pair_r[10:2]),
            .rd_data_o(src_data_w[bank])
        );
        edrv32_ram_rnd_line u_target (
            .clk_i(clk_i),
            .wr_en_i((load_target_w || result_write_w) && !cancel_i),
            .wr_addr_i(result_write_w ? blend_tag_i[10:2] : load_beat_r),
            .wr_data_i(result_write_w ? result_w : rd_data_i),
            .wr_strb_i(result_write_w ? result_strb_w : 32'hffff_ffff),
            .rd_en_i((render_read_w || write_read_w) && !cancel_i),
            .rd_addr_i(dst_read_addr_w),
            .rd_data_o(dst_data_w[bank])
        );
    end endgenerate

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            active_r <= 1'b0;
            done_r <= 1'b0;
            busy_r <= 2'd0;
            loaded_r <= 2'd0;
            rendered_r <= 2'd0;
        end else if (cancel_i || start_i) begin
            active_r <= start_i && !cancel_i;
            done_r <= 1'b0;
            busy_r <= 2'd0;
            loaded_r <= 2'd0;
            rendered_r <= 2'd0;
        end else begin
            done_r <= 1'b0;
            if (load_start_w)
                busy_r[load_bank_r] <= 1'b1;
            if (load_finish_w)
                loaded_r[load_bank_r] <= 1'b1;
            if (render_start_w)
                loaded_r[render_bank_r] <= 1'b0;
            if (render_finish_w)
                rendered_r[blend_tag_i[31]] <= 1'b1;
            if (write_start_w)
                rendered_r[write_bank_r] <= 1'b0;
            if (write_finish_w) begin
                busy_r[write_bank_r] <= 1'b0;
                if (bank_y_r[write_bank_r] == clip_bottom_r) begin
                    active_r <= 1'b0;
                    done_r <= 1'b1;
                end
            end
        end
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            load_state_r <= S_LOAD_IDLE;
            load_bank_r <= 1'b0;
            load_y_r <= 12'd0;
            load_beat_r <= 9'd0;
            loaded_all_r <= 1'b0;
        end else if (cancel_i || start_i) begin
            load_state_r <= S_LOAD_IDLE;
            load_bank_r <= 1'b0;
            load_y_r <= top_w[11:0];
            loaded_all_r <= 1'b0;
        end else begin
            case (load_state_r)
                S_LOAD_IDLE: if (load_start_w)
                    load_state_r <= S_LOAD_COORD;
                S_LOAD_COORD: load_state_r <= S_LOAD_PRODUCT;
                S_LOAD_PRODUCT: load_state_r <= S_LOAD_ADDR;
                S_LOAD_ADDR: load_state_r <= S_LOAD_SOURCE;
                S_LOAD_SOURCE: if (rd_ready_i) begin
                    load_state_r <= S_SOURCE_DATA;
                    load_beat_r <= 9'd0;
                end
                S_SOURCE_DATA: begin
                    if (rd_data_valid_i)
                        load_beat_r <= load_beat_r + 9'd1;
                    if (rd_done_i)
                        load_state_r <= S_LOAD_TARGET;
                end
                S_LOAD_TARGET: if (rd_ready_i) begin
                    load_state_r <= S_TARGET_DATA;
                    load_beat_r <= 9'd0;
                end
                S_TARGET_DATA: begin
                    if (rd_data_valid_i)
                        load_beat_r <= load_beat_r + 9'd1;
                    if (rd_done_i) begin
                        load_state_r <= S_LOAD_IDLE;
                        load_bank_r <= !load_bank_r;
                        load_y_r <= load_y_r + 12'd1;
                        if (load_y_r == clip_bottom_r)
                            loaded_all_r <= 1'b1;
                    end
                end
                default: load_state_r <= load_state_r;
            endcase
        end
    end
    // Coordinates, products and final descriptors have independent register boundaries.
    always @(posedge clk_i) begin
        if (start_i) begin
            clip_left_r <= left_w[11:0];
            clip_right_r <= right_w[11:0];
            clip_bottom_r <= bottom_w[11:0];
            source_x_offset_r <= {1'b0, command_i[335:320]} -
                {command_i[175], command_i[175:160]};
            source_y_offset_r <= {1'b0, command_i[351:336]} -
                {command_i[191], command_i[191:176]};
        end
        if (load_start_w)
            bank_y_r[load_bank_r] <= load_y_r;
        if (load_state_r == S_LOAD_COORD) begin
            source_x_r <= source_x_offset_r + {5'd0, clip_left_r};
            source_y_r <= source_y_offset_r + {5'd0, load_y_r};
            row_pixels_r <= {1'b0, clip_right_r} - {1'b0, clip_left_r} + 13'd1;
        end
        if (load_state_r == S_LOAD_PRODUCT) begin
            source_product_r <= source_y_r * command_i[303:288];
            target_product_r <= load_y_r * command_i[79:64];
            source_base_r <= command_i[287:256] + {13'd0, source_x_r, 2'd0};
            target_base_r <= command_i[63:32] + {18'd0, clip_left_r, 2'd0};
            row_pairs_r <= row_pixels_r[12:1];
            row_beats_r <= row_pixels_r[12:3];
        end
        if (load_state_r == S_LOAD_ADDR) begin
            source_addr_r <= source_base_r + source_product_r;
            bank_target_r[load_bank_r] <= target_base_r + target_product_r;
        end
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            render_state_r <= S_RENDER_IDLE;
            render_bank_r <= 1'b0;
            issue_pair_r <= 12'd0;
            memory_valid_r <= 1'b0;
            source_valid_r <= 1'b0;
            opacity_valid_r <= 1'b0;
        end else if (cancel_i || start_i) begin
            render_state_r <= S_RENDER_IDLE;
            render_bank_r <= 1'b0;
            memory_valid_r <= 1'b0;
            source_valid_r <= 1'b0;
            opacity_valid_r <= 1'b0;
        end else begin
            if (blend_ready_i) begin
                memory_valid_r <= issue_w;
                source_valid_r <= memory_valid_r;
                opacity_valid_r <= source_valid_r;
            end
            case (render_state_r)
                S_RENDER_IDLE: if (render_start_w) begin
                    render_state_r <= S_RENDER_STREAM;
                    issue_pair_r <= 12'd0;
                end
                S_RENDER_STREAM: if (blend_ready_i) begin
                    issue_pair_r <= issue_pair_r + 12'd1;
                    if (issue_pair_r + 12'd1 == row_pairs_w)
                        render_state_r <= S_RENDER_DRAIN;
                end
                S_RENDER_DRAIN: if (render_finish_w) begin
                    render_state_r <= S_RENDER_IDLE;
                    render_bank_r <= !render_bank_r;
                end
                default: render_state_r <= render_state_r;
            endcase
        end
    end
    always @(posedge clk_i) begin
        if (blend_ready_i) begin
            if (issue_w)
                memory_pair_r <= issue_pair_r[10:0];
            if (memory_valid_r) begin
                source_pixel1_r <= raw_src_w;
                target_pixel1_r <= render_dst_shift_w[63:0];
                source_tag1_r <= {render_bank_r, 20'd0, memory_pair_r};
            end
            if (source_valid_r) begin
                source_pixel2_r <= source_pixel1_r;
                target_pixel2_r <= target_pixel1_r;
                source_tag2_r <= source_tag1_r;
                opacity_product_r[0] <= source_pixel1_r[31:24] * command_i[255:248];
                opacity_product_r[1] <= source_pixel1_r[63:56] * command_i[255:248];
            end
        end
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            write_state_r <= S_WRITE_IDLE;
            write_bank_r <= 1'b0;
            write_beat_r <= 9'd0;
        end else if (cancel_i || start_i) begin
            write_state_r <= S_WRITE_IDLE;
            write_bank_r <= 1'b0;
        end else begin
            case (write_state_r)
                S_WRITE_IDLE: if (write_start_w)
                    write_state_r <= S_WRITE_DESC;
                S_WRITE_DESC: if (wr_ready_i) begin
                    write_state_r <= S_WRITE_DATA;
                    write_beat_r <= 9'd0;
                end
                S_WRITE_DATA: if (wr_data_ready_i) begin
                    write_beat_r <= next_write_w[8:0];
                    if ({1'd0, write_beat_r} + 10'd1 == row_beats_w)
                        write_state_r <= S_WRITE_RESPONSE;
                end
                S_WRITE_RESPONSE: if (wr_done_i) begin
                    write_state_r <= S_WRITE_IDLE;
                    write_bank_r <= !write_bank_r;
                end
                default: write_state_r <= write_state_r;
            endcase
        end
    end
endmodule
