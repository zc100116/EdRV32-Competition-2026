// File: edrv32_npu_post.v
// Spec: npu-spec 2.4, 2.6, 4.4-4.5, 5.2, 5.5-5.6.
// Description: Per-head table loading, fixed dual-bank compaction and serial candidate tail.
// Raw box gather, DFL and packed writes share the existing response-fenced DMA engines.
// Clock: clk_npu.
module edrv32_npu_post (
    // Clock and frame lifetime.
    input wire clk_i,
    input wire rst_n_i,
    input wire clear_i,
    input wire stop_i,
    input wire cancel_i,

    // IDLE configuration and descriptor-start table ownership.
    input wire [26:0] int8_th_i,
    input wire [31:0] prob_th_i,
    input wire [31:0] post_base_i,
    input wire [31:0] output_base_i,
    input wire load_i,
    input wire [1:0] load_head_i,
    input wire [31:0] load_addr_i,
    input wire [31:0] box_offset_i,
    input wire [31:0] box_stride_i,
    output wire load_done_o,
    input wire tail_i,
    output wire tail_done_o,
    output wire writer_idle_o,
    output wire [12:0] count_o,

    // Result RAM read outlet, accepts every valid beat without backpressure.
    input wire cls_valid_i,
    input wire [255:0] cls_data_i,
    input wire [1:0] cls_head_i,
    input wire [11:0] cls_row_i,
    input wire [10:0] cls_pair_i,
    input wire [2:0] cls_block_i,
    input wire cls_plane_i,

    // Single-beat requests to the shared read DMA.
    output wire read_req_valid_o,
    input wire read_req_ready_i,
    output wire [31:0] read_req_addr_o,
    input wire read_data_valid_i,
    input wire [255:0] read_data_i,

    // Single-beat requests and guaranteed complete data to shared write DMA.
    output wire write_req_valid_o,
    input wire write_req_ready_i,
    output wire [31:0] write_req_addr_o,
    output wire write_data_valid_o,
    input wire write_data_ready_i,
    output wire [255:0] write_data_o,
    input wire write_stream_idle_i,
    input wire write_idle_i
);
    (* keep = "true", syn_preserve = 1 *) wire [4:0] rst_post_n_w;
    genvar reset_region;
    generate
        for (reset_region = 0; reset_region < 5;
            reset_region = reset_region + 1) begin : g_reset_region
            edrv32_reset_copy u_reset (
                .clk_i(clk_i),
                .rst_n_i(rst_n_i),
                .rst_n_o(rst_post_n_w[reset_region])
            );
        end
    endgenerate
    localparam [4:0] S_IDLE = 5'd0;
    localparam [4:0] S_LOAD_DRAIN = 5'd1;
    localparam [4:0] S_LOAD_REQ = 5'd2;
    localparam [4:0] S_LOAD_READ = 5'd3;
    localparam [4:0] S_LOAD_WORD = 5'd4;
    localparam [4:0] S_LOAD_DONE = 5'd5;
    localparam [4:0] S_DRAIN = 5'd6;
    localparam [4:0] S_QUEUE = 5'd7;
    localparam [4:0] S_QUEUE_WAIT = 5'd8;
    localparam [4:0] S_QUEUE_GET = 5'd9;
    localparam [4:0] S_HEAD = 5'd10;
    localparam [4:0] S_CELL = 5'd11;
    localparam [4:0] S_XY = 5'd12;
    localparam [4:0] S_PROB = 5'd13;
    localparam [4:0] S_ADDR = 5'd14;
    localparam [4:0] S_GATHER = 5'd15;
    localparam [4:0] S_GATHER_WAIT = 5'd16;
    localparam [4:0] S_DFL_START = 5'd17;
    localparam [4:0] S_DFL = 5'd18;
    localparam [4:0] S_COORD = 5'd19;
    localparam [4:0] S_STRIDE = 5'd20;
    localparam [4:0] S_PACK = 5'd21;
    localparam [4:0] S_WRITE_REQ = 5'd22;
    localparam [4:0] S_WRITE_DATA = 5'd23;
    localparam [4:0] S_WRITE_DRAIN = 5'd24;
    localparam [4:0] S_NEXT = 5'd25;
    localparam [4:0] S_FLUSH = 5'd26;
    localparam [4:0] S_FENCE = 5'd27;
    localparam [4:0] S_DONE = 5'd28;
    reg [4:0] state_r;
    (* keep = "true", syn_keep = 1 *) wire phase_cell_w;
    assign phase_cell_w = state_r == S_CELL;
    (* keep = "true", syn_keep = 1 *) wire phase_stride_w;
    assign phase_stride_w = state_r == S_STRIDE;
    (* keep = "true", syn_keep = 1 *) wire phase_addr_w;
    assign phase_addr_w = state_r == S_ADDR;
    (* keep = "true", syn_keep = 1 *) wire phase_pack_w;
    assign phase_pack_w = state_r == S_PACK;
    (* keep = "true", syn_keep = 1 *) wire phase_head_w;
    assign phase_head_w = state_r == S_HEAD;
    (* keep = "true", syn_keep = 1 *) wire phase_xy_w;
    assign phase_xy_w = state_r == S_XY;
    (* keep = "true", syn_keep = 1 *) wire phase_prob_w;
    assign phase_prob_w = state_r == S_PROB;
    (* keep = "true", syn_keep = 1 *) wire phase_load_word_w;
    assign phase_load_word_w = state_r == S_LOAD_WORD;
    (* keep = "true", syn_keep = 1 *) wire phase_next_w;
    assign phase_next_w = state_r == S_NEXT;
    (* keep = "true", syn_keep = 1 *) wire phase_queue_get_w;
    assign phase_queue_get_w = state_r == S_QUEUE_GET;
    reg [1:0] head_r;
    (* keep = "true", syn_preserve = 1 *) reg [1:0] box_offset_head_copy_r;
    (* keep = "true", syn_preserve = 1 *) reg [1:0] box_stride_head_copy_r;
    (* keep = "true", syn_preserve = 1 *) reg [1:0] read_address_copy_r;
    (* keep = "true", syn_preserve = 1 *) reg [1:0] table_advance_copy_r;
    reg [31:0] box_offset_r [0:2];
    reg [31:0] box_stride_r [0:2];
    reg [31:0] table_addr_r;
    reg [5:0] load_beat_r;
    reg [2:0] load_word_r;
    (* keep = "true", syn_preserve = 1 *) reg [2:0] load_word_copy_r [0:1];
    reg [255:0] load_data_r;
    wire [9:0] load_index_w;
    wire load_exp_w;
    wire load_prob_w;
    wire [31:0] load_word_w;
    wire [1:0] candidate_valid_w;
    wire [31:0] candidate0_w;
    wire [31:0] candidate1_w;
    wire classify_idle_w;
    reg [12:0] count_r;
    wire [1:0] enqueue_w;
    wire [31:0] first_w;
    wire [31:0] queue_data_w [0:1];
    wire [11:0] second_addr_w;
    reg [12:0] cursor_r;
    reg [31:0] candidate_r;
    (* keep = "true", syn_preserve = 1 *) reg queue_bank_copy_r;
    reg [11:0] cell_r;
    reg [11:0] x_remainder_r;
    reg [6:0] x_r;
    reg [5:0] y_r;
    reg [6:0] width_r;
    reg [2:0] shift_r;
    (* keep = "true", syn_preserve = 1 *) reg [1:0] side_r;
    (* keep = "true", syn_preserve = 1 *) reg [1:0] side_coord_copy_r;
    reg [31:0] side_addr_r;
    reg [31:0] gather_addr_r;
    reg [127:0] bins_r;
    reg [31:0] coordinate_r;
    reg [191:0] record_r;
    reg [127:0] carry_r;
    reg [1:0] packing_r;
    reg [255:0] write_data_r;
    reg [31:0] write_addr_r;
    reg flushing_r;
    reg last_candidate_r;
    (* keep = "true", syn_preserve = 1 *) reg [2:0] cell_copy_r;
    (* keep = "true", syn_preserve = 1 *) reg [1:0] stride_copy_r;
    (* keep = "true", syn_preserve = 1 *) reg [1:0] clear_queue_copy_r;
    genvar clear_region;
    generate
        for (clear_region = 0; clear_region < 2; clear_region = clear_region + 1)
            begin : g_clear_region
            always @(posedge clk_i or negedge rst_post_n_w[1]) begin
                if (!rst_post_n_w[1]) clear_queue_copy_r[clear_region] <= 1'b0;
                else clear_queue_copy_r[clear_region] <= clear_i || cancel_i;
            end
        end
    endgenerate
    genvar cell_region;
    generate
        for (cell_region = 0; cell_region < 3; cell_region = cell_region + 1)
            begin : g_cell_region
            always @(posedge clk_i) cell_copy_r[cell_region] <= phase_head_w;
        end
    endgenerate
    wire dfl_done_w;
    wire [11:0] distance_w;
    wire exp_en_w;
    wire [7:0] exp_addr_w;
    wire [31:0] exp_data_w;
    wire prob_en_w;
    wire [9:0] prob_addr0_w;
    wire [9:0] prob_addr1_w;
    wire [31:0] prob_data0_w;
    wire [31:0] prob_data1_w;
    wire tail_prob_w;
    wire unused_queue_w;
    assign unused_queue_w = ^{candidate_r[31:28], gather_addr_r[4:0]};
    wire [31:0] unused_exp_b_w;
    wire [31:0] center_w;
    assign center_w = (side_coord_copy_r[0] ? {18'd0, y_r, 8'h80} : {17'd0, x_r, 8'h80});
    assign load_index_w = {head_r, load_beat_r[4:0], load_word_r};
    assign load_word_w = {load_data_r[32*load_word_copy_r[1]+16+:16],
        load_data_r[32*load_word_copy_r[0]+:16]};
    assign load_exp_w = phase_load_word_w && !load_beat_r[5];
    assign load_prob_w = phase_load_word_w && load_beat_r[5];
    assign tail_prob_w = phase_xy_w;
    assign enqueue_w = {1'b0, candidate_valid_w[0]} + {1'b0, candidate_valid_w[1]};
    assign first_w = candidate_valid_w[0] ? candidate0_w : candidate1_w;
    assign second_addr_w = count_r[12:1] + 12'd1;
    assign count_o = count_r;
    assign load_done_o = state_r == S_LOAD_DONE;
    assign tail_done_o = state_r == S_DONE;
    assign writer_idle_o = state_r != S_WRITE_DATA;
    assign read_req_valid_o = !stop_i && (state_r == S_LOAD_REQ || state_r == S_GATHER);
    assign read_req_addr_o[15:0] = read_address_copy_r[0]
        ? table_addr_r[15:0] : {gather_addr_r[15:5], 5'd0};
    assign read_req_addr_o[31:16] = read_address_copy_r[1]
        ? table_addr_r[31:16] : gather_addr_r[31:16];
    assign write_req_valid_o = state_r == S_WRITE_REQ && !stop_i;
    assign write_req_addr_o = write_addr_r;
    assign write_data_valid_o = state_r == S_WRITE_DATA;
    assign write_data_o = write_data_r;

    edrv32_npu_post_classify u_classify (
        .clk_i(clk_i),
        .rst_n_i(rst_post_n_w[4]),
        .clear_i(clear_i || cancel_i),
        .valid_i(cls_valid_i),
        .data_i(cls_data_i),
        .head_i(cls_head_i),
        .row_i(cls_row_i),
        .pair_i(cls_pair_i),
        .block_i(cls_block_i),
        .plane_i(cls_plane_i),
        .int8_th_i(int8_th_i),
        .prob_th_i(prob_th_i),
        .prob_en_o(prob_en_w),
        .prob_addr0_o(prob_addr0_w),
        .prob_addr1_o(prob_addr1_w),
        .prob_data0_i(prob_data0_w),
        .prob_data1_i(prob_data1_w),
        .candidate_valid_o(candidate_valid_w),
        .candidate0_o(candidate0_w),
        .candidate1_o(candidate1_w),
        .idle_o(classify_idle_w)
    );
    edrv32_ram_npu_post_table u_exp (
        .clk_i(clk_i),
        .a_en_i(load_exp_w || exp_en_w),
        .a_write_i(load_exp_w),
        .a_addr_i(load_exp_w ? load_index_w : {head_r, exp_addr_w}),
        .a_data_i(load_word_w),
        .a_data_o(exp_data_w),
        .b_en_i(1'b0),
        .b_addr_i(10'd0),
        .b_data_o(unused_exp_b_w)
    );
    edrv32_ram_npu_post_table u_probability (
        .clk_i(clk_i),
        .a_en_i(load_prob_w || prob_en_w || tail_prob_w),
        .a_write_i(load_prob_w),
        .a_addr_i(load_prob_w ? load_index_w
            : tail_prob_w ? {head_r, candidate_r[27:20]} : prob_addr0_w),
        .a_data_i(load_word_w),
        .a_data_o(prob_data0_w),
        .b_en_i(prob_en_w),
        .b_addr_i(prob_addr1_w),
        .b_data_o(prob_data1_w)
    );
    edrv32_ram_npu_post_queue u_queue_even (
        .clk_i(clk_i),
        .wr_en_i((enqueue_w != 2'd0 && !count_r[0]) || enqueue_w == 2'd2),
        .wr_addr_i(count_r[0] ? second_addr_w : count_r[12:1]),
        .wr_data_i(count_r[0] ? candidate1_w : first_w),
        .rd_en_i(state_r == S_QUEUE && !cursor_r[0]),
        .rd_addr_i(cursor_r[12:1]),
        .rd_data_o(queue_data_w[0])
    );
    edrv32_ram_npu_post_queue u_queue_odd (
        .clk_i(clk_i),
        .wr_en_i((enqueue_w != 2'd0 && count_r[0]) || enqueue_w == 2'd2),
        .wr_addr_i(count_r[12:1]),
        .wr_data_i(count_r[0] ? first_w : candidate1_w),
        .rd_en_i(state_r == S_QUEUE && cursor_r[0]),
        .rd_addr_i(cursor_r[12:1]),
        .rd_data_o(queue_data_w[1])
    );
    edrv32_npu_post_dfl u_dfl (
        .clk_i(clk_i),
        .rst_n_i(rst_post_n_w[3]),
        .cancel_i(cancel_i || stop_i),
        .start_i(state_r == S_DFL_START),
        .bins_i(bins_r),
        .done_o(dfl_done_w),
        .distance_o(distance_w),
        .exp_en_o(exp_en_w),
        .exp_addr_o(exp_addr_w),
        .exp_data_i(exp_data_w)
    );
    always @(posedge clk_i or negedge rst_post_n_w[1]) begin
        if (!rst_post_n_w[1]) count_r <= 13'd0;
        else if (clear_queue_copy_r[0]) count_r <= 13'd0;
        else count_r <= count_r + {11'd0, enqueue_w};
    end
    reg [4:0] state_next_w;
    always @(*) begin
        state_next_w = state_r;
        if (cancel_i || clear_i || (stop_i && state_r != S_WRITE_DATA)) begin
            state_next_w = S_IDLE;
        end else begin
            case (state_r)
                S_IDLE: begin
                    if (load_i) state_next_w = S_LOAD_DRAIN;
                    else if (tail_i) state_next_w = S_DRAIN;
                end
                S_LOAD_DRAIN: if (classify_idle_w) state_next_w = S_LOAD_REQ;
                S_LOAD_REQ: if (read_req_ready_i) state_next_w = S_LOAD_READ;
                S_LOAD_READ: if (read_data_valid_i) state_next_w = S_LOAD_WORD;
                S_LOAD_WORD: begin
                    if (load_word_r == 3'd7)
                        state_next_w = load_beat_r == 6'd63 ? S_LOAD_DONE : S_LOAD_REQ;
                end
                S_LOAD_DONE: state_next_w = S_IDLE;
                S_DRAIN: begin
                    if (classify_idle_w)
                        state_next_w = count_r == 13'd0 ? S_FENCE : S_QUEUE;
                end
                S_QUEUE: state_next_w = S_QUEUE_WAIT;
                S_QUEUE_WAIT: state_next_w = S_QUEUE_GET;
                S_QUEUE_GET: state_next_w = S_HEAD;
                S_HEAD: state_next_w = S_CELL;
                S_CELL: state_next_w = S_XY;
                S_XY: if (x_remainder_r < {5'd0, width_r}) state_next_w = S_PROB;
                S_PROB: state_next_w = S_ADDR;
                S_ADDR: state_next_w = S_GATHER;
                S_GATHER: if (read_req_ready_i) state_next_w = S_GATHER_WAIT;
                S_GATHER_WAIT: if (read_data_valid_i) state_next_w = S_DFL_START;
                S_DFL_START: state_next_w = S_DFL;
                S_DFL: if (dfl_done_w) state_next_w = S_COORD;
                S_COORD: state_next_w = S_STRIDE;
                S_STRIDE: state_next_w = side_r == 2'd3 ? S_PACK : S_ADDR;
                S_PACK: state_next_w = packing_r == 2'd0 ? S_NEXT : S_WRITE_REQ;
                S_WRITE_REQ: if (write_req_ready_i) state_next_w = S_WRITE_DATA;
                S_WRITE_DATA: begin
                    if (write_data_ready_i) state_next_w = stop_i ? S_IDLE : S_WRITE_DRAIN;
                end
                S_WRITE_DRAIN: begin
                    if (write_stream_idle_i) state_next_w = flushing_r ? S_FENCE : S_NEXT;
                end
                S_NEXT: begin
                    if (last_candidate_r)
                        state_next_w = packing_r == 2'd0 ? S_FENCE : S_FLUSH;
                    else state_next_w = S_QUEUE;
                end
                S_FLUSH: state_next_w = S_WRITE_REQ;
                S_FENCE: if (write_idle_i) state_next_w = S_DONE;
                S_DONE: state_next_w = S_IDLE;
                default: begin end
            endcase
        end
    end
    always @(posedge clk_i or negedge rst_post_n_w[0]) begin
        if (!rst_post_n_w[0]) state_r <= S_IDLE;
        else state_r <= state_next_w;
    end
    always @(posedge clk_i or negedge rst_post_n_w[1]) begin
        if (!rst_post_n_w[1]) begin
            cursor_r <= 13'd0;
            packing_r <= 2'd0;
            flushing_r <= 1'b0;
        end else if (clear_queue_copy_r[1]) begin
            cursor_r <= 13'd0;
            packing_r <= 2'd0;
            flushing_r <= 1'b0;
        end else begin
            if (state_r == S_IDLE && tail_i) begin
                cursor_r <= 13'd0;
                packing_r <= 2'd0;
            end
            if (phase_pack_w) packing_r <= packing_r + 2'd1;
            if (phase_next_w) cursor_r <= cursor_r + 13'd1;
            if (state_r == S_FLUSH) flushing_r <= 1'b1;
        end
    end
    always @(posedge clk_i or negedge rst_post_n_w[2]) begin
        if (!rst_post_n_w[2]) begin
            load_beat_r <= 6'd0;
            load_word_r <= 3'd0;
            side_r <= 2'd0;
            side_coord_copy_r <= 2'd0;
        end else begin
            if (state_r == S_IDLE && load_i) begin
                load_beat_r <= 6'd0;
                load_word_r <= 3'd0;
            end
            if (phase_load_word_w) begin
                load_word_r <= load_word_r + 3'd1;
                if (load_word_r == 3'd7) load_beat_r <= load_beat_r + 6'd1;
            end
            if (phase_prob_w) begin
                side_r <= 2'd0;
                side_coord_copy_r <= 2'd0;
            end
            if (phase_stride_w) begin
                side_r <= side_r + 2'd1;
                side_coord_copy_r <= side_r + 2'd1;
            end
        end
    end
    always @(posedge clk_i) begin
        if (load_config_copy_r[2]) begin
            head_r <= load_head_i;
            box_offset_head_copy_r <= load_head_i;
            box_stride_head_copy_r <= load_head_i;
        end
        if (load_config_copy_r[3]) begin
            box_offset_r[load_head_i] <= box_offset_i;
            box_stride_r[load_head_i] <= box_stride_i;
        end

        if (state_r == S_QUEUE) queue_bank_copy_r <= cursor_r[0];
        if (phase_queue_get_w) begin
            candidate_r <= queue_data_w[queue_bank_copy_r];
            last_candidate_r <= cursor_r + 13'd1 == count_r;
        end
        if (phase_head_w) begin
            head_r <= candidate_head_w;
            box_offset_head_copy_r <= candidate_head_w;
            box_stride_head_copy_r <= candidate_head_w;
            cell_r <= candidate_r[12:0] < 13'd3840 ? candidate_r[11:0]
                : candidate_r[12:0] < 13'd4800 ? (candidate_r[11:0] - 12'd3840)
                : (candidate_r[11:0] - 12'd704);
        end
        if (cell_copy_r[0]) begin
            // Repeated width subtraction avoids a second full divider in the tail.
            x_remainder_r <= cell_r;
            y_r <= 6'd0;
            width_r <= head_r == 2'd0 ? 7'd80 : head_r == 2'd1 ? 7'd40 : 7'd20;
            shift_r <= head_r == 2'd0 ? 3'd3 : head_r == 2'd1 ? 3'd4 : 3'd5;
        end
        if (phase_xy_w) begin
            if (x_remainder_r >= {5'd0, width_r}) begin
                x_remainder_r <= x_remainder_r - {5'd0, width_r};
                y_r <= y_r + 6'd1;
            end else x_r <= x_remainder_r[6:0];
        end
        if (phase_addr_w) gather_addr_r <= side_addr_r + {16'd0, cell_r, 4'd0};
        coordinate_r <= side_coord_copy_r[1] ? center_w + {20'd0, distance_w}
                : center_w - {20'd0, distance_w};
    end
    (* keep = "true", syn_preserve = 1 *) reg [3:0] load_config_copy_r;
    (* keep = "true", syn_preserve = 1 *) reg [1:0] tail_copy_r;
    genvar load_region;
    generate
        for (load_region = 0; load_region < 4; load_region = load_region + 1)
            begin : g_load_region
            always @(posedge clk_i) load_config_copy_r[load_region] <= load_i;
        end
    endgenerate
    genvar address_region;
    generate
        for (address_region = 0; address_region < 2;
            address_region = address_region + 1) begin : g_address_region
            always @(posedge clk_i) begin
                tail_copy_r[address_region] <= tail_i;
                read_address_copy_r[address_region] <= state_r == S_LOAD_DRAIN
                    || state_r == S_LOAD_REQ || state_r == S_LOAD_READ
                    || phase_load_word_w;
                table_advance_copy_r[address_region] <= phase_load_word_w
                    && load_word_r == 3'd6;
                stride_copy_r[address_region] <= state_r == S_COORD;
                if (cell_copy_r[address_region+1])
                    side_addr_r[16*address_region+:16] <= box_base_w[16*address_region+:16];
                else if (stride_copy_r[address_region])
                    side_addr_r[16*address_region+:16] <= next_side_addr_w[16*address_region+:16];
                if (state_r == S_IDLE && load_i) load_word_copy_r[address_region] <= 3'd0;
                if (phase_load_word_w)
                    load_word_copy_r[address_region] <= load_word_r + 3'd1;
                if (load_config_copy_r[address_region])
                    table_addr_r[16*address_region+:16] <= load_addr_i[16*address_region+:16];
                else if (table_advance_copy_r[address_region])
                    table_addr_r[16*address_region+:16] <= next_table_addr_w[16*address_region+:16];
                if (tail_copy_r[address_region])
                    write_addr_r[16*address_region+:16] <= post_base_i[16*address_region+:16];
                else if (state_r == S_WRITE_DRAIN && write_stream_idle_i)
                    write_addr_r[16*address_region+:16] <= next_write_addr_w[16*address_region+:16];
            end
        end
    endgenerate
    wire [1:0] candidate_head_w;
    assign candidate_head_w = candidate_r[12:0] < 13'd3840 ? 2'd0
        : candidate_r[12:0] < 13'd4800 ? 2'd1 : 2'd2;
    wire [31:0] box_base_w;
    wire [31:0] next_side_addr_w;
    assign box_base_w = output_base_i + box_offset_r[box_offset_head_copy_r];
    assign next_side_addr_w = side_addr_r + box_stride_r[box_stride_head_copy_r];
    wire [31:0] next_table_addr_w;
    wire [31:0] next_write_addr_w;
    assign next_table_addr_w = table_addr_r + 32'd32;
    assign next_write_addr_w = write_addr_r + 32'd32;
    wire [31:0] shifted_w;
    wire [63:0] metadata_w;
    assign shifted_w = coordinate_r << shift_r;
    assign metadata_w = {3'd0, candidate_r[12:0], 9'd0, candidate_r[19:13], prob_data0_w};
    wire [255:0] pack0_w;
    wire [255:0] flush_w;
    wire [127:0] carry2_w;
    assign pack0_w = {64'd0, record_r};
    assign flush_w = {128'd0, carry_r};
    assign carry2_w = {64'd0, record_r[191:128]};
    wire [255:0] pack1_w;
    wire [255:0] pack2_w;
    wire [255:0] pack3_w;
    assign pack1_w = {record_r[63:0], write_data_r[191:0]};
    assign pack2_w = {record_r[127:0], carry_r};
    assign pack3_w = {record_r, carry_r[63:0]};
    genvar region;
    generate
        for (region = 0; region < 16; region = region + 1) begin : g_payload_region
            (* keep = "true", syn_preserve = 1 *) reg load_copy_r;
            (* keep = "true", syn_preserve = 1 *) reg [3:0] pack_copy_r;
            (* keep = "true", syn_preserve = 1 *) reg flush_copy_r;
            always @(posedge clk_i) begin
                load_copy_r <= (state_r == S_LOAD_REQ && read_req_ready_i)
                    || (state_r == S_LOAD_READ && !read_data_valid_i);
                pack_copy_r[0] <= phase_stride_w
                    && side_r == 2'd3 && packing_r == 2'd0;
                pack_copy_r[1] <= phase_stride_w
                    && side_r == 2'd3 && packing_r == 2'd1;
                pack_copy_r[2] <= phase_stride_w
                    && side_r == 2'd3 && packing_r == 2'd2;
                pack_copy_r[3] <= phase_stride_w
                    && side_r == 2'd3 && packing_r == 2'd3;
                flush_copy_r <= phase_next_w && last_candidate_r
                    && packing_r != 2'd0 && packing_r != 2'd1;
                if (load_copy_r) load_data_r[16*region+:16] <= read_data_i[16*region+:16];
                if (pack_copy_r[0]) write_data_r[16*region+:16] <= pack0_w[16*region+:16];
                if (pack_copy_r[1]) write_data_r[16*region+:16] <= pack1_w[16*region+:16];
                if (pack_copy_r[2]) write_data_r[16*region+:16] <= pack2_w[16*region+:16];
                if (pack_copy_r[3]) write_data_r[16*region+:16] <= pack3_w[16*region+:16];
                if (flush_copy_r) write_data_r[16*region+:16] <= flush_w[16*region+:16];
            end
            if (region < 8) begin : g_side
                localparam [1:0] SIDE = region[2:1];
                (* keep = "true", syn_preserve = 1 *) reg gather_copy_r;
                (* keep = "true", syn_preserve = 1 *) reg half_copy_r;
                (* keep = "true", syn_preserve = 1 *) reg coord_copy_r;
                (* keep = "true", syn_preserve = 1 *) reg carry1_copy_r;
                (* keep = "true", syn_preserve = 1 *) reg carry2_copy_r;
                always @(posedge clk_i) begin
                    gather_copy_r <= (state_r == S_GATHER && read_req_ready_i)
                        || (state_r == S_GATHER_WAIT && !read_data_valid_i);
                    if (phase_cell_w) half_copy_r <= cell_r[0];
                    coord_copy_r <= state_r == S_DFL && dfl_done_w && side_r == SIDE;
                    carry1_copy_r <= phase_stride_w
                        && side_r == 2'd3 && packing_r == 2'd1;
                    carry2_copy_r <= phase_stride_w
                        && side_r == 2'd3 && packing_r == 2'd2;
                    if (gather_copy_r) bins_r[16*region+:16] <= half_copy_r
                        ? read_data_i[128+16*region+:16] : read_data_i[16*region+:16];
                    if (coord_copy_r) record_r[16*region+:16] <= shifted_w[16*(region%2)+:16];
                    if (carry1_copy_r) carry_r[16*region+:16] <= record_r[64+16*region+:16];
                    if (carry2_copy_r) carry_r[16*region+:16] <= carry2_w[16*region+:16];
                end
            end
            if (region >= 8 && region < 12) begin : g_metadata
                (* keep = "true", syn_preserve = 1 *) reg metadata_copy_r;
                always @(posedge clk_i) begin
                    metadata_copy_r <= phase_prob_w;
                    if (metadata_copy_r)
                        record_r[16*region+:16] <= metadata_w[16*(region-8)+:16];
                end
            end
        end
    endgenerate
endmodule
