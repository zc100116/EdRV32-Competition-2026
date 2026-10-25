// ============================================================================
// File        : edrv32_yolo_patch_gen.v
// Description : C16 line-cache reads to pair-major 1x1/3x3 activation rows.
// Notes       : A registered cache-read descriptor cuts the coordinate and
//               bank-enable path. The descriptor slot refills as it issues,
//               so steady-state throughput remains one activation row/clock.
//               One start descriptor covers an output-row chunk and one
//               activation RAM half. Row validity implements zero padding.
// ============================================================================

module edrv32_yolo_patch_gen (
    input  wire         clk_i,
    input  wire         rst_n_i,

    input  wire         start_i,
    output wire         start_ready_o,
    input  wire         kernel3_i,
    input  wire         stride2_i,
    input  wire [10:0]  input_width_i,
    input  wire [5:0]   cin_blocks_i,
    input  wire [8:0]   block_bank_stride_i,
    input  wire [9:0]   pair_x_base_i,
    input  wire [9:0]   pair_count_i,
    input  wire [10:0]  activation_base_i,
    input  wire [9:0]   row_base0_i,
    input  wire [9:0]   row_base1_i,
    input  wire [9:0]   row_base2_i,
    input  wire [2:0]   row_valid_i,

    output wire         cache_rd_valid_o,
    input  wire         cache_rd_ready_i,
    output wire         cache_rd_bank0_o,
    output wire [9:0]   cache_rd_addr0_o,
    output wire         cache_rd_bank1_o,
    output wire [9:0]   cache_rd_addr1_o,
    input  wire [255:0] cache_rd_data0_i,
    input  wire [255:0] cache_rd_data1_i,

    output wire         activation_valid_o,
    output wire [10:0]  activation_addr_o,
    output wire [127:0] activation_data_o,
    output wire         busy_o,
    output wire         done_o
);

    reg active_r;
    reg done_r;
    reg kernel3_r;
    reg stride2_r;
    reg [10:0] input_width_r;
    reg [5:0] cin_blocks_r;
    reg [8:0] block_bank_stride_r;
    reg [9:0] pair_x_r;
    reg [9:0] pair_count_r;
    reg [9:0] pair_index_r;
    reg [10:0] activation_addr_r;
    reg [9:0] row_base_r [0:2];
    reg [2:0] row_valid_r;
    reg [1:0] kernel_y_r;
    reg [1:0] kernel_x_r;
    reg [5:0] cblock_r;
    reg [9:0] cblock_offset_r;
    reg channel_half_r;

    reg desc_valid_r;
    reg desc_last_r;
    reg [10:0] desc_addr_r;
    reg desc_pad0_r;
    reg desc_pad1_r;
    reg desc_pixel_half0_r;
    reg desc_pixel_half1_r;
    reg desc_channel_half_r;
    reg desc_bank0_r;
    reg desc_bank1_r;
    reg [9:0] desc_cache_addr0_r;
    reg [9:0] desc_cache_addr1_r;

    reg pending_valid_r;
    reg pending_last_r;
    reg [10:0] pending_addr_r;
    reg pending_pad0_r;
    reg pending_pad1_r;
    reg pending_pixel_half0_r;
    reg pending_pixel_half1_r;
    reg pending_channel_half_r;

    wire [1:0] last_kernel_w = kernel3_r ? 2'd2 : 2'd0;
    wire last_cblock_w = cblock_r == cin_blocks_r - 6'd1;
    wire last_pair_w = pair_index_r == pair_count_r - 10'd1;
    wire last_row_w = channel_half_r && last_cblock_w &&
        kernel_x_r == last_kernel_w && kernel_y_r == last_kernel_w;
    wire last_all_w = last_row_w && last_pair_w;

    wire signed [12:0] output_x0_w =
        $signed({2'b00, pair_x_r + pair_index_r, 1'b0});
    wire signed [12:0] source_x0_w =
        (stride2_r ? (output_x0_w <<< 1) : output_x0_w) +
        $signed({11'd0, kernel_x_r}) - (kernel3_r ? 13'sd1 : 13'sd0);
    wire signed [12:0] source_x1_w =
        source_x0_w + (stride2_r ? 13'sd2 : 13'sd1);
    wire row_in_bounds_w = row_valid_r[kernel_y_r];
    wire pixel0_in_bounds_w = row_in_bounds_w && source_x0_w >= 13'sd0 &&
        source_x0_w < $signed({2'b00, input_width_r});
    wire pixel1_in_bounds_w = row_in_bounds_w && source_x1_w >= 13'sd0 &&
        source_x1_w < $signed({2'b00, input_width_r});
    wire [9:0] row_base_w = row_base_r[kernel_y_r];
    wire [9:0] addr0_w = row_base_w + cblock_offset_r + source_x0_w[11:2];
    wire [9:0] addr1_w = row_base_w + cblock_offset_r + source_x1_w[11:2];
    wire bank0_w = source_x0_w[1];
    wire bank1_w = source_x1_w[1];
    wire issue_w = desc_valid_r && cache_rd_ready_i;
    wire produce_w = active_r && (!desc_valid_r || issue_w);
    wire selected_bank0_w = pixel0_in_bounds_w ? bank0_w :
                            (pixel1_in_bounds_w ? bank1_w : 1'b0);
    wire [9:0] selected_addr0_w = pixel0_in_bounds_w ? addr0_w :
                                 (pixel1_in_bounds_w ? addr1_w : 10'd0);
    wire selected_bank1_w = pixel1_in_bounds_w ? bank1_w :
                            selected_bank0_w;
    wire [9:0] selected_addr1_w = pixel1_in_bounds_w ? addr1_w :
                                 selected_addr0_w;

    wire [127:0] pixel0_word_w = pending_pixel_half0_r ?
        cache_rd_data0_i[255:128] : cache_rd_data0_i[127:0];
    wire [127:0] pixel1_word_w = pending_pixel_half1_r ?
        cache_rd_data1_i[255:128] : cache_rd_data1_i[127:0];
    wire [63:0] pixel0_channels_w = pending_channel_half_r ?
        pixel0_word_w[127:64] : pixel0_word_w[63:0];
    wire [63:0] pixel1_channels_w = pending_channel_half_r ?
        pixel1_word_w[127:64] : pixel1_word_w[63:0];

    assign start_ready_o = !active_r && !desc_valid_r &&
                           !pending_valid_r &&
                           cin_blocks_i != 6'd0 && pair_count_i != 10'd0;
    assign busy_o = active_r || desc_valid_r || pending_valid_r;
    assign done_o = done_r;
    assign cache_rd_valid_o = desc_valid_r;
    assign cache_rd_bank0_o = desc_bank0_r;
    assign cache_rd_addr0_o = desc_cache_addr0_r;
    assign cache_rd_bank1_o = desc_bank1_r;
    assign cache_rd_addr1_o = desc_cache_addr1_r;
    assign activation_valid_o = pending_valid_r;
    assign activation_addr_o = pending_addr_r;
    assign activation_data_o = {
        pending_pad1_r ? 64'd0 : pixel1_channels_w,
        pending_pad0_r ? 64'd0 : pixel0_channels_w};

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            active_r               <= 1'b0;
            done_r                 <= 1'b0;
            desc_valid_r           <= 1'b0;
            pending_valid_r        <= 1'b0;
            kernel3_r              <= 1'b0;
            stride2_r              <= 1'b0;
            input_width_r          <= 11'd0;
            cin_blocks_r           <= 6'd0;
            block_bank_stride_r    <= 9'd0;
            pair_x_r              <= 10'd0;
            pair_count_r           <= 10'd0;
            pair_index_r           <= 10'd0;
            activation_addr_r      <= 11'd0;
            row_valid_r            <= 3'd0;
            kernel_y_r             <= 2'd0;
            kernel_x_r             <= 2'd0;
            cblock_r               <= 6'd0;
            cblock_offset_r        <= 10'd0;
            channel_half_r         <= 1'b0;
        end else begin
            done_r <= 1'b0;
            pending_valid_r <= issue_w;
            if (pending_valid_r && pending_last_r)
                done_r <= 1'b1;
            if (produce_w)
                desc_valid_r <= 1'b1;
            else if (issue_w)
                desc_valid_r <= 1'b0;
            if (start_i && start_ready_o) begin
                active_r            <= 1'b1;
                kernel3_r           <= kernel3_i;
                stride2_r           <= stride2_i;
                input_width_r       <= input_width_i;
                cin_blocks_r        <= cin_blocks_i;
                block_bank_stride_r <= block_bank_stride_i;
                pair_x_r            <= pair_x_base_i;
                pair_count_r        <= pair_count_i;
                pair_index_r        <= 10'd0;
                activation_addr_r   <= activation_base_i;
                row_base_r[0]       <= row_base0_i;
                row_base_r[1]       <= row_base1_i;
                row_base_r[2]       <= row_base2_i;
                row_valid_r         <= row_valid_i;
                kernel_y_r          <= 2'd0;
                kernel_x_r          <= 2'd0;
                cblock_r            <= 6'd0;
                cblock_offset_r     <= 10'd0;
                channel_half_r      <= 1'b0;
            end else if (produce_w) begin
                desc_last_r             <= last_all_w;
                desc_addr_r             <= activation_addr_r;
                desc_pad0_r             <= !pixel0_in_bounds_w;
                desc_pad1_r             <= !pixel1_in_bounds_w;
                desc_pixel_half0_r      <= source_x0_w[0];
                desc_pixel_half1_r      <= source_x1_w[0];
                desc_channel_half_r     <= channel_half_r;
                desc_bank0_r            <= selected_bank0_w;
                desc_bank1_r            <= selected_bank1_w;
                desc_cache_addr0_r      <= selected_addr0_w;
                desc_cache_addr1_r      <= selected_addr1_w;
                activation_addr_r       <= activation_addr_r + 11'd1;
                if (channel_half_r) begin
                    channel_half_r <= 1'b0;
                    if (last_cblock_w) begin
                        cblock_r        <= 6'd0;
                        cblock_offset_r <= 10'd0;
                        if (kernel_x_r == last_kernel_w) begin
                            kernel_x_r <= 2'd0;
                            if (kernel_y_r == last_kernel_w) begin
                                kernel_y_r <= 2'd0;
                                if (last_pair_w)
                                    active_r <= 1'b0;
                                else
                                    pair_index_r <= pair_index_r + 10'd1;
                            end else
                                kernel_y_r <= kernel_y_r + 2'd1;
                        end else
                            kernel_x_r <= kernel_x_r + 2'd1;
                    end else begin
                        cblock_r        <= cblock_r + 6'd1;
                        cblock_offset_r <= cblock_offset_r +
                                           {1'b0, block_bank_stride_r};
                    end
                end else
                    channel_half_r <= 1'b1;
            end
            if (issue_w) begin
                pending_last_r          <= desc_last_r;
                pending_addr_r          <= desc_addr_r;
                pending_pad0_r          <= desc_pad0_r;
                pending_pad1_r          <= desc_pad1_r;
                pending_pixel_half0_r   <= desc_pixel_half0_r;
                pending_pixel_half1_r   <= desc_pixel_half1_r;
                pending_channel_half_r  <= desc_channel_half_r;
            end
        end
    end

endmodule
