// File: edrv32_npu_nonconv.v
// Spec: npu-spec 2.1, 2.2, 5.2, 5.3, 5.5.
// Description: Pipelined C16 max-pool and nearest-neighbor upsample using two scratch RAMs.
// A POOL plane and each UPSAMPLE source row are read exactly once from DDR.
// Clock: clk_npu.
module edrv32_npu_nonconv (
    // Clock and execution lifetime.
    input wire clk_i,
    input wire rst_n_i,
    input wire start_i,
    input wire stop_i,
    input wire cancel_i,
    input wire [511:0] desc_i,
    input wire [31:0] in_addr_i,
    input wire [31:0] out_addr_i,

    // Read DMA interface.
    output wire read_req_valid_o,
    input wire read_req_ready_i,
    output wire [31:0] read_req_addr_o,
    output wire [4:0] read_req_beats_o,
    output wire [31:0] read_req_tag_o,
    input wire read_data_valid_i,
    output wire read_data_ready_o,
    input wire [255:0] read_data_i,
    input wire [31:0] read_data_tag_i,
    input wire [3:0] read_data_index_i,
    input wire read_data_last_i,

    // Write DMA interface.
    output wire write_req_valid_o,
    input wire write_req_ready_i,
    output wire [31:0] write_req_addr_o,
    output wire [4:0] write_req_beats_o,
    output wire write_data_valid_o,
    input wire write_data_ready_i,
    output wire [255:0] write_data_o,
    input wire write_stream_idle_i,

    // Local completion; writer ownership must survive ABORT.
    output wire done_o,
    output wire writer_idle_o,
    output wire active_o
);
    localparam [4:0] S_IDLE = 5'd0;
    localparam [4:0] S_COUNT = 5'd1;
    localparam [4:0] S_LOAD_INIT = 5'd2;
    localparam [4:0] S_LOAD = 5'd3;
    localparam [4:0] S_LOAD_WAIT = 5'd4;
    localparam [4:0] S_CALC_INIT = 5'd5;
    localparam [4:0] S_SAMPLE_ADDR = 5'd6;
    localparam [4:0] S_SAMPLE_WAIT = 5'd7;
    localparam [4:0] S_WRITE_INIT = 5'd10;
    localparam [4:0] S_WRITE_REQUEST = 5'd11;
    localparam [4:0] S_SOURCE_ADDR = 5'd12;
    localparam [4:0] S_SOURCE_WAIT = 5'd13;
    localparam [4:0] S_SEND = 5'd14;
    localparam [4:0] S_WRITE_DRAIN = 5'd15;
    localparam [4:0] S_NEXT_ROW = 5'd16;
    localparam [4:0] S_DONE = 5'd17;
    localparam [4:0] S_HALT = 5'd18;
    reg [511:0] desc_r;
    wire [511:0] unused_desc_w;
    wire [31:0] unused_tag_w;
    assign unused_desc_w = desc_r;
    assign unused_tag_w = read_data_tag_i;
    reg [4:0] state_r;
    reg upsample_r;
    reg [5:0] plane_r;
    reg [11:0] row_r;
    reg [10:0] pair_r;
    reg pixel_r;
    reg vertical_r;
    reg [11:0] count_row_r;
    reg [8:0] plane_beats_r;
    reg [8:0] read_remaining_r;
    reg [8:0] read_index_r;
    reg [31:0] read_addr_r;
    reg [31:0] in_plane_addr_r;
    reg [31:0] in_row_addr_r;
    reg [31:0] out_plane_addr_r;
    reg [31:0] out_row_addr_r;
    reg [31:0] write_addr_r;
    reg [10:0] write_pair_r;
    reg [4:0] write_beats_r;
    reg [4:0] write_sent_r;
    reg [2:0] kernel_x_r;
    reg [2:0] kernel_y_r;
    reg signed [31:0] center_row_base_r;
    reg signed [31:0] sample_row_base_r;
    reg sample_pixel_r;
    reg sample_end_r;
    reg sample_right_r;
    reg [8:0] sample_pair_r;
    reg sample_issue_r;
    (* syn_preserve = 1 *) reg [3:0] compare_valid_r;
    (* syn_preserve = 1 *) reg [3:0] compare_init_r;
    (* syn_preserve = 1 *) reg [3:0] compare_end_r;
    (* syn_preserve = 1 *) reg [3:0] compare_right_r;
    reg [8:0] compare_pair_r;
    reg sample_valid_r;
    reg [127:0] sample_data_r;
    reg [127:0] maximum_r;
    reg [127:0] left_pixel_r;
    reg [127:0] maximum_w;
    reg row_write_r;
    reg [8:0] row_write_addr_r;
    reg [255:0] row_write_data_r;
    reg [255:0] write_data_r;
    wire [11:0] in_w_w;
    wire [11:0] in_h_w;
    wire [11:0] unused_out_w_w;
    wire [11:0] out_h_w;
    wire [10:0] in_row_pairs_w;
    wire [10:0] out_row_pairs_w;
    wire [31:0] in_row_bytes_w;
    wire [31:0] out_row_bytes_w;
    wire [4:0] read_beats_w;
    wire [4:0] write_boundary_w;
    wire [10:0] write_remaining_w;
    wire read_accept_w;
    wire response_w;
    wire source_active_w;
    wire signed [13:0] sample_x_w;
    wire signed [13:0] sample_y_w;
    wire sample_inside_w;
    wire [31:0] unused_sample_addr_w;
    wire plane_wr_en_w;
    wire [8:0] plane_wr_addr_w;
    wire plane_rd_en_w;
    wire [255:0] plane_rd_data_w;
    wire row_wr_en_w;
    wire [8:0] row_wr_addr_w;
    wire [255:0] row_wr_data_w;
    wire row_rd_en_w;
    wire [8:0] row_rd_addr_w;
    wire [255:0] row_rd_data_w;
    integer channel_idx;

    assign in_w_w = desc_r[267:256];
    assign in_h_w = desc_r[283:272];
    assign unused_out_w_w = desc_r[299:288];
    assign out_h_w = desc_r[315:304];
    assign in_row_pairs_w = in_w_w[11:1];
    assign out_row_pairs_w = unused_out_w_w[11:1];
    assign in_row_bytes_w = {16'd0, in_row_pairs_w, 5'd0};
    assign out_row_bytes_w = {16'd0, out_row_pairs_w, 5'd0};
    assign read_req_valid_o = (state_r == S_LOAD) && !stop_i;
    assign read_req_addr_o = read_addr_r;
    assign read_beats_w = (read_remaining_r < {4'd0, 5'd16 - {1'b0, read_addr_r[8:5]}})
        ? read_remaining_r[4:0] : 5'd16 - {1'b0, read_addr_r[8:5]};
    assign read_req_beats_o = read_beats_w;
    assign read_req_tag_o = {3'd0, (read_remaining_r == {4'd0, read_beats_w}),
        19'd0, read_index_r};
    assign read_accept_w = read_req_valid_o && read_req_ready_i;
    assign read_data_ready_o = 1'b1;
    assign response_w = read_data_valid_i && !stop_i;
    assign write_req_valid_o = (state_r == S_WRITE_REQUEST) && !stop_i;
    assign write_req_addr_o = write_addr_r;
    assign write_req_beats_o = write_beats_r;
    assign write_data_valid_o = (state_r == S_SEND);
    assign write_data_o = write_data_r;
    assign write_boundary_w = 5'd16 - {1'b0, write_addr_r[8:5]};
    assign write_remaining_w = out_row_pairs_w - write_pair_r;
    assign source_active_w = (state_r == S_SOURCE_ADDR) || (state_r == S_SOURCE_WAIT)
        || (state_r == S_SEND) || (state_r == S_WRITE_DRAIN);
    assign writer_idle_o = !source_active_w && write_stream_idle_i;
    assign done_o = (state_r == S_DONE);
    assign active_o = (state_r != S_IDLE) && (state_r != S_DONE) && (state_r != S_HALT);
    assign sample_x_w = $signed({2'd0, pair_r, pixel_r})
        + $signed({11'd0, kernel_x_r}) - 14'sd2;
    assign sample_y_w = $signed({2'd0, row_r})
        + $signed({11'd0, kernel_y_r}) - 14'sd2;
    assign sample_inside_w = (sample_x_w >= 14'sd0)
        && (sample_x_w < $signed({2'd0, in_w_w})) && (sample_y_w >= 14'sd0)
        && (sample_y_w < $signed({2'd0, in_h_w}));
    assign unused_sample_addr_w = sample_row_base_r + {19'd0, sample_x_w[13:1]};
    assign plane_wr_en_w = response_w && !upsample_r;
    assign plane_wr_addr_w = read_data_tag_i[8:0] + {5'd0, read_data_index_i};
    assign plane_rd_en_w = (state_r == S_SAMPLE_ADDR) && sample_inside_w && !stop_i;
    assign row_wr_en_w = (response_w && upsample_r) || row_write_r;
    assign row_wr_addr_w = upsample_r ? plane_wr_addr_w : row_write_addr_r;
    assign row_wr_data_w = upsample_r ? read_data_i : row_write_data_r;
    assign row_rd_en_w = (state_r == S_SOURCE_ADDR);
    assign row_rd_addr_w = upsample_r ? {1'b0, write_pair_r[8:1]} : write_pair_r[8:0];
    always @(*) begin
        maximum_w = maximum_r;
        for (channel_idx = 0; channel_idx < 16; channel_idx = channel_idx + 1) begin
            if ($signed(sample_data_r[8*channel_idx+:8])
                > $signed(maximum_r[8*channel_idx+:8])) begin
                maximum_w[8*channel_idx+:8] = sample_data_r[8*channel_idx+:8];
            end
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            plane_r <= 6'd0;
            row_r <= 12'd0;
            pair_r <= 11'd0;
            pixel_r <= 1'b0;
            vertical_r <= 1'b0;
            count_row_r <= 12'd0;
            plane_beats_r <= 9'd0;
            read_remaining_r <= 9'd0;
            read_index_r <= 9'd0;
            write_pair_r <= 11'd0;
            write_beats_r <= 5'd0;
            write_sent_r <= 5'd0;
            kernel_x_r <= 3'd0;
            kernel_y_r <= 3'd0;
            row_write_r <= 1'b0;
        end else if (cancel_i) begin
            state_r <= S_IDLE;
            row_write_r <= 1'b0;
        end else begin
            row_write_r <= compare_valid_r[0] && compare_end_r[0] && compare_right_r[0]
                && !stop_i;
            if (stop_i && !source_active_w && (state_r != S_IDLE)) begin
                state_r <= S_HALT;
            end else begin
                case (state_r)
                    S_IDLE: begin
                        if (start_i) begin
                            state_r <= S_COUNT;
                            plane_r <= 6'd0;
                            row_r <= 12'd0;
                            vertical_r <= 1'b0;
                            count_row_r <= 12'd0;
                            plane_beats_r <= 9'd0;
                        end
                    end
                    S_COUNT: begin
                        plane_beats_r <= plane_beats_r + in_row_pairs_w[8:0];
                        count_row_r <= count_row_r + 12'd1;
                        if (count_row_r == in_h_w - 12'd1) begin
                            state_r <= S_LOAD_INIT;
                        end
                    end
                    S_LOAD_INIT: begin
                        read_remaining_r <= upsample_r ? {1'b0, in_row_pairs_w[7:0]}
                            : plane_beats_r;
                        read_index_r <= 9'd0;
                        state_r <= S_LOAD;
                    end
                    S_LOAD: begin
                        if (read_accept_w) begin
                            read_remaining_r <= read_remaining_r - {4'd0, read_beats_w};
                            read_index_r <= read_index_r + {4'd0, read_beats_w};
                            if (read_remaining_r == {4'd0, read_beats_w}) begin
                                state_r <= S_LOAD_WAIT;
                            end
                        end
                    end
                    S_LOAD_WAIT: begin
                        if (response_w && read_data_last_i && read_data_tag_i[28]) begin
                            state_r <= upsample_r ? S_WRITE_INIT : S_CALC_INIT;
                        end
                    end
                    S_CALC_INIT: begin
                        pair_r <= 11'd0;
                        pixel_r <= 1'b0;
                        kernel_x_r <= 3'd0;
                        kernel_y_r <= 3'd0;
                        state_r <= S_SAMPLE_ADDR;
                    end
                    // Address/RAM and comparison advance independently across pixels.
                    S_SAMPLE_ADDR: begin
                        if (kernel_x_r == 3'd4) begin
                            kernel_x_r <= 3'd0;
                            if (kernel_y_r == 3'd4) begin
                                kernel_y_r <= 3'd0;
                                pixel_r <= !pixel_r;
                                if (pixel_r) begin
                                    if (pair_r == out_row_pairs_w - 11'd1) begin
                                        state_r <= S_SAMPLE_WAIT;
                                    end else begin
                                        pair_r <= pair_r + 11'd1;
                                    end
                                end
                            end else begin
                                kernel_y_r <= kernel_y_r + 3'd1;
                            end
                        end else begin
                            kernel_x_r <= kernel_x_r + 3'd1;
                        end
                    end
                    S_SAMPLE_WAIT: begin
                        if (compare_valid_r[0] && compare_end_r[0] && compare_right_r[0]) begin
                            state_r <= S_WRITE_INIT;
                        end
                    end
                    S_WRITE_INIT: begin
                        write_pair_r <= 11'd0;
                        state_r <= S_WRITE_DRAIN;
                    end
                    S_WRITE_REQUEST: begin
                        if (write_req_ready_i) begin
                            write_sent_r <= 5'd0;
                            state_r <= S_SOURCE_ADDR;
                        end
                    end
                    S_SOURCE_ADDR: state_r <= S_SOURCE_WAIT;
                    S_SOURCE_WAIT: state_r <= S_SEND;
                    S_SEND: begin
                        if (write_data_ready_i) begin
                            write_pair_r <= write_pair_r + 11'd1;
                            write_sent_r <= write_sent_r + 5'd1;
                            state_r <= (write_sent_r == write_beats_r - 5'd1)
                                ? S_WRITE_DRAIN : S_SOURCE_ADDR;
                        end
                    end
                    S_WRITE_DRAIN: begin
                        if (write_stream_idle_i) begin
                            if (stop_i) begin
                                state_r <= S_HALT;
                            end else if (write_pair_r == out_row_pairs_w) begin
                                state_r <= S_NEXT_ROW;
                            end else begin
                                write_beats_r <= (write_remaining_w < {6'd0, write_boundary_w})
                                    ? write_remaining_w[4:0] : write_boundary_w;
                                state_r <= S_WRITE_REQUEST;
                            end
                        end
                    end
                    S_NEXT_ROW: begin
                        if (upsample_r && !vertical_r) begin
                            vertical_r <= 1'b1;
                            state_r <= S_WRITE_INIT;
                        end else if (row_r == (upsample_r ? in_h_w : out_h_w) - 12'd1) begin
                            if (plane_r == desc_r[325:320] - 6'd1) begin
                                state_r <= S_DONE;
                            end else begin
                                plane_r <= plane_r + 6'd1;
                                row_r <= 12'd0;
                                vertical_r <= 1'b0;
                                state_r <= S_LOAD_INIT;
                            end
                        end else begin
                            row_r <= row_r + 12'd1;
                            vertical_r <= 1'b0;
                            state_r <= upsample_r ? S_LOAD_INIT : S_CALC_INIT;
                        end
                    end
                    S_DONE: state_r <= S_IDLE;
                    default: begin end
                endcase
            end
        end
    end
    always @(posedge clk_i) begin
        if (start_i) begin
            desc_r <= desc_i;
            upsample_r <= (desc_i[3:0] == 4'd2);
            in_plane_addr_r <= in_addr_i;
            in_row_addr_r <= in_addr_i;
            out_plane_addr_r <= out_addr_i;
            out_row_addr_r <= out_addr_i;
            center_row_base_r <= 32'sd0;
        end
        if (state_r == S_LOAD_INIT) begin
            read_addr_r <= in_row_addr_r;
        end else if (read_accept_w) begin
            read_addr_r <= read_addr_r + {22'd0, read_beats_w, 5'd0};
        end
        if (state_r == S_CALC_INIT) begin
            sample_row_base_r <= center_row_base_r - {20'd0, in_row_pairs_w, 1'b0};
        end
        if (state_r == S_SAMPLE_ADDR) begin
            sample_pixel_r <= sample_x_w[0];
            sample_valid_r <= sample_inside_w;
            sample_end_r <= (kernel_x_r == 3'd4) && (kernel_y_r == 3'd4);
            sample_right_r <= pixel_r;
            sample_pair_r <= pair_r[8:0];
            if (kernel_x_r == 3'd4) begin
                sample_row_base_r <= (kernel_y_r == 3'd4)
                    ? center_row_base_r - {20'd0, in_row_pairs_w, 1'b0}
                    : sample_row_base_r + {21'd0, in_row_pairs_w};
            end
        end
        if (sample_issue_r) begin
            sample_data_r <= sample_valid_r
                ? (sample_pixel_r ? plane_rd_data_w[255:128] : plane_rd_data_w[127:0])
                : {16{8'h80}};
            compare_pair_r <= sample_pair_r;
        end
        if (compare_valid_r[0] && compare_end_r[0] && compare_right_r[0]) begin
            row_write_addr_r <= compare_pair_r;
            row_write_data_r <= {maximum_w, left_pixel_r};
        end
        if (state_r == S_WRITE_INIT) begin
            write_addr_r <= out_row_addr_r;
        end else if ((state_r == S_SEND) && write_data_ready_i) begin
            write_addr_r <= write_addr_r + 32'd32;
        end
        if (state_r == S_SOURCE_WAIT) begin
            write_data_r <= !upsample_r ? row_rd_data_w : (write_pair_r[0]
                ? {row_rd_data_w[255:128], row_rd_data_w[255:128]}
                : {row_rd_data_w[127:0], row_rd_data_w[127:0]});
        end
        if (state_r == S_NEXT_ROW) begin
            out_row_addr_r <= out_row_addr_r + out_row_bytes_w;
            if (!upsample_r || vertical_r) begin
                if (row_r == (upsample_r ? in_h_w : out_h_w) - 12'd1) begin
                    in_plane_addr_r <= in_plane_addr_r + desc_r[95:64];
                    in_row_addr_r <= in_plane_addr_r + desc_r[95:64];
                    out_plane_addr_r <= out_plane_addr_r + desc_r[159:128];
                    out_row_addr_r <= out_plane_addr_r + desc_r[159:128];
                    center_row_base_r <= 32'sd0;
                end else begin
                    in_row_addr_r <= in_row_addr_r + in_row_bytes_w;
                    center_row_base_r <= center_row_base_r + {21'd0, in_row_pairs_w};
                end
            end
        end
    end

    // One enabled scratch read, one pixel-selection stage, then signed max.
    // End/right ownership follows the read even for boundary padding samples.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            sample_issue_r <= 1'b0;
            compare_valid_r <= 4'd0;
            compare_init_r <= 4'd0;
        end else if (cancel_i || stop_i) begin
            sample_issue_r <= 1'b0;
            compare_valid_r <= 4'd0;
            compare_init_r <= 4'd0;
        end else begin
            sample_issue_r <= (state_r == S_SAMPLE_ADDR);
            compare_valid_r <= {4{sample_issue_r}};
            compare_init_r <= {4{state_r == S_CALC_INIT}};
        end
    end
    always @(posedge clk_i) begin
        compare_end_r <= {4{sample_end_r}};
        compare_right_r <= {4{sample_right_r}};
    end
    genvar maximum_group;
    generate
        for (maximum_group = 0; maximum_group < 4; maximum_group = maximum_group + 1) begin
            : g_maximum
            always @(posedge clk_i) begin
                if (compare_init_r[maximum_group]) begin
                    maximum_r[maximum_group*32+:32] <= {4{8'h80}};
                end else if (compare_valid_r[maximum_group]) begin
                    maximum_r[maximum_group*32+:32] <= compare_end_r[maximum_group]
                        ? {4{8'h80}} : maximum_w[maximum_group*32+:32];
                    if (compare_end_r[maximum_group] && !compare_right_r[maximum_group]) begin
                        left_pixel_r[maximum_group*32+:32] <= maximum_w[maximum_group*32+:32];
                    end
                end
            end
        end
    endgenerate

    edrv32_ram_npu_scratch u_plane_scratch (
        // Clocks and domain-local resets.
        .clk_i(clk_i),

        // Descriptor configuration and execution status.
        .wr_en_i(plane_wr_en_w),
        .wr_addr_i(plane_wr_addr_w),
        .wr_data_i(read_data_i),
        .rd_en_i(plane_rd_en_w),
        .rd_addr_i(unused_sample_addr_w[8:0]),
        .rd_data_o(plane_rd_data_w)
    );
    edrv32_ram_npu_scratch u_row_scratch (
        // Clocks and domain-local resets.
        .clk_i(clk_i),

        // Descriptor configuration and execution status.
        .wr_en_i(row_wr_en_w),
        .wr_addr_i(row_wr_addr_w),
        .wr_data_i(row_wr_data_w),
        .rd_en_i(row_rd_en_w),
        .rd_addr_i(row_rd_addr_w),
        .rd_data_o(row_rd_data_w)
    );
endmodule
