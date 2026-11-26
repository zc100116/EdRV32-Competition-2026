// File: edrv32_gpu_read_dma.v
// Spec: gpu-spec 6; gpu-microarch 4.2, 4.5, 4.9.
// Description: Seven independent byte-range clients share four ordered AXI bursts.
// Each burst reserves a 16-beat pool region before AR; returned beats survive backpressure.
// Clock: clk_gpu.
module edrv32_gpu_read_dma (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Independent logical read clients.
    input wire command_read_req_valid_i,
    output wire command_read_req_ready_o,
    input wire [31:0] command_read_req_addr_i,
    input wire [31:0] command_read_req_bytes_i,
    output wire command_read_data_valid_o,
    input wire command_read_data_ready_i,
    output wire [255:0] command_read_data_data_o,
    output wire [31:0] command_read_data_keep_o,
    output wire command_read_data_last_o,
    output wire command_read_done_o,

    input wire matrix_read_req_valid_i,
    output wire matrix_read_req_ready_o,
    input wire [31:0] matrix_read_req_addr_i,
    input wire [31:0] matrix_read_req_bytes_i,
    output wire matrix_read_data_valid_o,
    input wire matrix_read_data_ready_i,
    output wire [255:0] matrix_read_data_data_o,
    output wire [31:0] matrix_read_data_keep_o,
    output wire matrix_read_data_last_o,
    output wire matrix_read_done_o,

    input wire vertex_read_req_valid_i,
    output wire vertex_read_req_ready_o,
    input wire [31:0] vertex_read_req_addr_i,
    input wire [31:0] vertex_read_req_bytes_i,
    output wire vertex_read_data_valid_o,
    input wire vertex_read_data_ready_i,
    output wire [255:0] vertex_read_data_data_o,
    output wire [31:0] vertex_read_data_keep_o,
    output wire vertex_read_data_last_o,
    output wire vertex_read_done_o,

    input wire quad_read_req_valid_i,
    output wire quad_read_req_ready_o,
    input wire [31:0] quad_read_req_addr_i,
    input wire [31:0] quad_read_req_bytes_i,
    output wire quad_read_data_valid_o,
    input wire quad_read_data_ready_i,
    output wire [255:0] quad_read_data_data_o,
    output wire [31:0] quad_read_data_keep_o,
    output wire quad_read_data_last_o,
    output wire quad_read_done_o,

    input wire object_read_req_valid_i,
    output wire object_read_req_ready_o,
    input wire [31:0] object_read_req_addr_i,
    input wire [31:0] object_read_req_bytes_i,
    output wire object_read_data_valid_o,
    input wire object_read_data_ready_i,
    output wire [255:0] object_read_data_data_o,
    output wire [31:0] object_read_data_keep_o,
    output wire object_read_data_last_o,
    output wire object_read_done_o,

    input wire texture_read_req_valid_i,
    output wire texture_read_req_ready_o,
    input wire [31:0] texture_read_req_addr_i,
    input wire [31:0] texture_read_req_bytes_i,
    output wire texture_read_data_valid_o,
    input wire texture_read_data_ready_i,
    output wire [255:0] texture_read_data_data_o,
    output wire [31:0] texture_read_data_keep_o,
    output wire texture_read_data_last_o,
    output wire texture_read_done_o,

    input wire palette_read_req_valid_i,
    output wire palette_read_req_ready_o,
    input wire [31:0] palette_read_req_addr_i,
    input wire [31:0] palette_read_req_bytes_i,
    output wire palette_read_data_valid_o,
    input wire palette_read_data_ready_i,
    output wire [255:0] palette_read_data_data_o,
    output wire [31:0] palette_read_data_keep_o,
    output wire palette_read_data_last_o,
    output wire palette_read_done_o,

    // AXI256 read master; all transactions use local ID zero.
    output wire m_axi_arid_o,
    output wire [31:0] m_axi_araddr_o,
    output wire [3:0] m_axi_arlen_o,
    output wire m_axi_arvalid_o,
    input wire m_axi_arready_i,
    input wire m_axi_rid_i,
    input wire [255:0] m_axi_rdata_i,
    input wire [1:0] m_axi_rresp_i,
    input wire m_axi_rlast_i,
    input wire m_axi_rvalid_i,
    output wire m_axi_rready_o,

    // Run lifecycle and statistics.
    input wire start_i,
    input wire stop_i,
    output wire dma_idle_o,
    output reg dma_error_o,
    output wire perf_read_wait_o
);
    wire [6:0] req_valid_w;
    wire [6:0] data_ready_w;
    wire [31:0] req_addr_w [0:6];
    wire [31:0] req_bytes_w [0:6];
    reg [6:0] active_r;
    reg [6:0] issue_r;
    reg [6:0] done_r;
    reg [31:0] addr_r [0:6];
    reg [31:0] beats_r [0:6];
    wire [31:0] first_keep_w [0:6];
    reg [31:0] last_keep_r [0:6];
    reg [2:0] round_r;
    reg choose_valid_w;
    reg [2:0] choose_w;
    reg [4:0] length_w;
    reg [8:0] boundary_w;
    integer idx_r;
    integer data_idx_r;

    reg [1:0] prepare_state_r;
    reg [2:0] prepare_client_r;
    reg [31:0] prepare_addr_r;
    reg [4:0] prepare_beats_r;
    reg prepare_small_r;
    reg prepare_final_r;
    reg [31:0] prepare_head_keep_r;
    reg [31:0] prepare_tail_keep_r;
    wire prepare_start_w;
    wire prepare_build_w;
    // Pool region ownership follows AR, R and consumption order independently.
    reg [3:0] occupied_r;
    reg [3:0] filled_r;
    reg [3:0] issued_r;
    reg [31:0] prepare_total_beats_r;
    reg [31:0] prepare_next_addr_r;
    reg [31:0] prepare_remaining_r;
    reg [2:0] owner_r [0:3];
    reg [4:0] length_r [0:3];
    reg [31:0] head_keep_r [0:3];
    reg [31:0] tail_keep_r [0:3];
    reg logical_last_r [0:3];
    reg [1:0] alloc_ptr_r;
    reg [1:0] receive_ptr_r;
    reg [3:0] receive_beat_r;
    reg [1:0] consume_ptr_r;
    reg [4:0] consume_beat_r;
    reg ar_valid_r;
    reg [31:0] ar_addr_r;
    reg [3:0] ar_len_r;
    wire ar_fire_w;
    wire r_fire_w;
    wire pool_read_w;
    wire [5:0] pool_addr_w;
    wire [255:0] pool_data_w;
    reg pending_r;
    reg [2:0] pending_owner_r;
    reg [31:0] pending_keep_r;
    reg pending_last_r;
    reg pending_end_r;
    reg [1:0] pending_slot_r;

    // Two reserved return slots break the ready path through the RAM.
    reg [255:0] data_r [0:1];
    reg [31:0] keep_r [0:1];
    reg [2:0] client_r [0:1];
    reg last_r [0:1];
    reg end_r [0:1];
    reg [1:0] slot_r [0:1];
    reg head_r;
    reg tail_r;
    reg [1:0] count_r;
    wire pop_w;
    wire unused_axi_w;
    assign unused_axi_w = m_axi_rid_i ^ m_axi_rlast_i;
    assign req_valid_w[0] = command_read_req_valid_i;
    assign req_addr_w[0] = command_read_req_addr_i;
    assign req_bytes_w[0] = command_read_req_bytes_i;
    assign command_read_req_ready_o = !active_r[0] && !stop_i;
    assign data_ready_w[0] = command_read_data_ready_i;
    assign command_read_data_valid_o = (count_r != 0) && (client_r[head_r] == 3'd0);
    assign command_read_data_data_o = data_r[head_r];
    assign command_read_data_keep_o = keep_r[head_r];
    assign command_read_data_last_o = last_r[head_r];
    assign command_read_done_o = done_r[0];
    assign req_valid_w[1] = matrix_read_req_valid_i;
    assign req_addr_w[1] = matrix_read_req_addr_i;
    assign req_bytes_w[1] = matrix_read_req_bytes_i;
    assign matrix_read_req_ready_o = !active_r[1] && !stop_i;
    assign data_ready_w[1] = matrix_read_data_ready_i;
    assign matrix_read_data_valid_o = (count_r != 0) && (client_r[head_r] == 3'd1);
    assign matrix_read_data_data_o = data_r[head_r];
    assign matrix_read_data_keep_o = keep_r[head_r];
    assign matrix_read_data_last_o = last_r[head_r];
    assign matrix_read_done_o = done_r[1];
    assign req_valid_w[2] = vertex_read_req_valid_i;
    assign req_addr_w[2] = vertex_read_req_addr_i;
    assign req_bytes_w[2] = vertex_read_req_bytes_i;
    assign vertex_read_req_ready_o = !active_r[2] && !stop_i;
    assign data_ready_w[2] = vertex_read_data_ready_i;
    assign vertex_read_data_valid_o = (count_r != 0) && (client_r[head_r] == 3'd2);
    assign vertex_read_data_data_o = data_r[head_r];
    assign vertex_read_data_keep_o = keep_r[head_r];
    assign vertex_read_data_last_o = last_r[head_r];
    assign vertex_read_done_o = done_r[2];
    assign req_valid_w[3] = quad_read_req_valid_i;
    assign req_addr_w[3] = quad_read_req_addr_i;
    assign req_bytes_w[3] = quad_read_req_bytes_i;
    assign quad_read_req_ready_o = !active_r[3] && !stop_i;
    assign data_ready_w[3] = quad_read_data_ready_i;
    assign quad_read_data_valid_o = (count_r != 0) && (client_r[head_r] == 3'd3);
    assign quad_read_data_data_o = data_r[head_r];
    assign quad_read_data_keep_o = keep_r[head_r];
    assign quad_read_data_last_o = last_r[head_r];
    assign quad_read_done_o = done_r[3];
    assign req_valid_w[4] = object_read_req_valid_i;
    assign req_addr_w[4] = object_read_req_addr_i;
    assign req_bytes_w[4] = object_read_req_bytes_i;
    assign object_read_req_ready_o = !active_r[4] && !stop_i;
    assign data_ready_w[4] = object_read_data_ready_i;
    assign object_read_data_valid_o = (count_r != 0) && (client_r[head_r] == 3'd4);
    assign object_read_data_data_o = data_r[head_r];
    assign object_read_data_keep_o = keep_r[head_r];
    assign object_read_data_last_o = last_r[head_r];
    assign object_read_done_o = done_r[4];
    assign req_valid_w[5] = texture_read_req_valid_i;
    assign req_addr_w[5] = texture_read_req_addr_i;
    assign req_bytes_w[5] = texture_read_req_bytes_i;
    assign texture_read_req_ready_o = !active_r[5] && !stop_i;
    assign data_ready_w[5] = texture_read_data_ready_i;
    assign texture_read_data_valid_o = (count_r != 0) && (client_r[head_r] == 3'd5);
    assign texture_read_data_data_o = data_r[head_r];
    assign texture_read_data_keep_o = keep_r[head_r];
    assign texture_read_data_last_o = last_r[head_r];
    assign texture_read_done_o = done_r[5];
    assign req_valid_w[6] = palette_read_req_valid_i;
    assign req_addr_w[6] = palette_read_req_addr_i;
    assign req_bytes_w[6] = palette_read_req_bytes_i;
    assign palette_read_req_ready_o = !active_r[6] && !stop_i;
    assign data_ready_w[6] = palette_read_data_ready_i;
    assign palette_read_data_valid_o = (count_r != 0) && (client_r[head_r] == 3'd6);
    assign palette_read_data_data_o = data_r[head_r];
    assign palette_read_data_keep_o = keep_r[head_r];
    assign palette_read_data_last_o = last_r[head_r];
    assign palette_read_done_o = done_r[6];

    assign m_axi_arid_o = 1'b0;
    assign m_axi_arvalid_o = ar_valid_r;
    assign m_axi_araddr_o = ar_addr_r;
    assign m_axi_arlen_o = ar_len_r;
    assign ar_fire_w = ar_valid_r && m_axi_arready_i;
    assign m_axi_rready_o = issued_r[receive_ptr_r] && !filled_r[receive_ptr_r];
    assign r_fire_w = m_axi_rvalid_i && m_axi_rready_o;
    assign pop_w = (count_r != 0) && data_ready_w[client_r[head_r]];
    assign dma_idle_o = !(|active_r) && !(|occupied_r) && !ar_valid_r
        && (count_r == 0) && !pending_r;
    assign perf_read_wait_o = (|issued_r) && !m_axi_rvalid_i;
    assign pool_read_w = filled_r[consume_ptr_r]
        && (consume_beat_r < length_r[consume_ptr_r])
        && ({1'b0, count_r} + {2'b0, pending_r} < 3'd2);
    assign pool_addr_w = {consume_ptr_r, consume_beat_r[3:0]};

    edrv32_ram_gpu_read_pool u_pool (
        .clk_i(clk_i),
        .wr_en_i(r_fire_w),
        .wr_addr_i({receive_ptr_r, receive_beat_r}),
        .wr_data_i(m_axi_rdata_i),
        .rd_en_i(pool_read_w),
        .rd_addr_i(pool_addr_w),
        .rd_data_o(pool_data_w)
    );

    wire [6:0] small_beats_w;
    wire [6:0] final_beats_w;
    genvar beat_client;
    generate
        for (beat_client = 0; beat_client < 7; beat_client = beat_client + 1) begin : g_beats
            assign small_beats_w[beat_client] = beats_r[beat_client] < 32'd16;
            assign final_beats_w[beat_client] = beats_r[beat_client][31:5] == 0;
        end
    endgenerate
    // Rotating priority is explicit over the fixed client set; selection is registered.
    assign prepare_start_w = prepare_state_r == 0 && choose_valid_w &&
        !ar_valid_r && !occupied_r[alloc_ptr_r];
    assign prepare_build_w = prepare_state_r == 2;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) prepare_state_r <= 0;
        else begin
            case (prepare_state_r)
                2'd0: if (prepare_start_w) prepare_state_r <= 1;
                2'd1: prepare_state_r <= 2;
                2'd2: prepare_state_r <= 0;
                default: prepare_state_r <= prepare_state_r;
            endcase
        end
    end
    always @(posedge clk_i) begin
        if (prepare_start_w) prepare_client_r <= choose_w;
        if (prepare_state_r == 1) begin
            prepare_addr_r <= addr_r[prepare_client_r];
            prepare_total_beats_r <= beats_r[prepare_client_r];
            prepare_beats_r <= beats_r[prepare_client_r][4:0];
            prepare_small_r <= small_beats_w[prepare_client_r];
            prepare_final_r <= final_beats_w[prepare_client_r];
            prepare_head_keep_r <= first_keep_w[prepare_client_r];
            prepare_tail_keep_r <= last_keep_r[prepare_client_r];
        end
    end


    always @(*) begin
        choose_valid_w = |issue_r;
        choose_w = 0;
        case (round_r)
            3'd0: begin
                casez (issue_r)
                    7'b??????1: choose_w = 3'd0;
                    7'b?????10: choose_w = 3'd1;
                    7'b????100: choose_w = 3'd2;
                    7'b???1000: choose_w = 3'd3;
                    7'b??10000: choose_w = 3'd4;
                    7'b?100000: choose_w = 3'd5;
                    7'b1000000: choose_w = 3'd6;
                    default: choose_w = 0;
                endcase
            end
            3'd1: begin
                casez (issue_r)
                    7'b?????1?: choose_w = 3'd1;
                    7'b????10?: choose_w = 3'd2;
                    7'b???100?: choose_w = 3'd3;
                    7'b??1000?: choose_w = 3'd4;
                    7'b?10000?: choose_w = 3'd5;
                    7'b100000?: choose_w = 3'd6;
                    7'b0000001: choose_w = 3'd0;
                    default: choose_w = 0;
                endcase
            end
            3'd2: begin
                casez (issue_r)
                    7'b????1??: choose_w = 3'd2;
                    7'b???10??: choose_w = 3'd3;
                    7'b??100??: choose_w = 3'd4;
                    7'b?1000??: choose_w = 3'd5;
                    7'b10000??: choose_w = 3'd6;
                    7'b00000?1: choose_w = 3'd0;
                    7'b0000010: choose_w = 3'd1;
                    default: choose_w = 0;
                endcase
            end
            3'd3: begin
                casez (issue_r)
                    7'b???1???: choose_w = 3'd3;
                    7'b??10???: choose_w = 3'd4;
                    7'b?100???: choose_w = 3'd5;
                    7'b1000???: choose_w = 3'd6;
                    7'b0000??1: choose_w = 3'd0;
                    7'b0000?10: choose_w = 3'd1;
                    7'b0000100: choose_w = 3'd2;
                    default: choose_w = 0;
                endcase
            end
            3'd4: begin
                casez (issue_r)
                    7'b??1????: choose_w = 3'd4;
                    7'b?10????: choose_w = 3'd5;
                    7'b100????: choose_w = 3'd6;
                    7'b000???1: choose_w = 3'd0;
                    7'b000??10: choose_w = 3'd1;
                    7'b000?100: choose_w = 3'd2;
                    7'b0001000: choose_w = 3'd3;
                    default: choose_w = 0;
                endcase
            end
            3'd5: begin
                casez (issue_r)
                    7'b?1?????: choose_w = 3'd5;
                    7'b10?????: choose_w = 3'd6;
                    7'b00????1: choose_w = 3'd0;
                    7'b00???10: choose_w = 3'd1;
                    7'b00??100: choose_w = 3'd2;
                    7'b00?1000: choose_w = 3'd3;
                    7'b0010000: choose_w = 3'd4;
                    default: choose_w = 0;
                endcase
            end
            3'd6: begin
                casez (issue_r)
                    7'b1??????: choose_w = 3'd6;
                    7'b0?????1: choose_w = 3'd0;
                    7'b0????10: choose_w = 3'd1;
                    7'b0???100: choose_w = 3'd2;
                    7'b0??1000: choose_w = 3'd3;
                    7'b0?10000: choose_w = 3'd4;
                    7'b0100000: choose_w = 3'd5;
                    default: choose_w = 0;
                endcase
            end
            default: choose_w = 0;
        endcase
    end
    always @(*) begin
        length_w = prepare_small_r ? prepare_beats_r : 5'd16;
        boundary_w = 9'd128 - {2'b0, prepare_addr_r[11:5]};
        if ({4'b0, length_w} > boundary_w) length_w = boundary_w[4:0];
    end

    always @(posedge clk_i) begin
        for (data_idx_r = 0; data_idx_r < 7; data_idx_r = data_idx_r + 1) begin
            if (req_valid_w[data_idx_r] && !active_r[data_idx_r] && !stop_i) begin
                    last_keep_r[data_idx_r] <= 32'hffffffff
                        >> ((32'd0 - req_addr_w[data_idx_r] - req_bytes_w[data_idx_r]) & 32'd31);
            end
        end
        if (prepare_build_w) begin
            ar_addr_r <= prepare_addr_r;
            prepare_next_addr_r <= prepare_addr_r + {22'b0, length_w, 5'b0};
            prepare_remaining_r <= prepare_total_beats_r - {27'b0, length_w};
            ar_len_r <= length_w[3:0] - 4'd1;
            owner_r[alloc_ptr_r] <= prepare_client_r;
            length_r[alloc_ptr_r] <= length_w;
            head_keep_r[alloc_ptr_r] <= prepare_head_keep_r;
            tail_keep_r[alloc_ptr_r] <= (prepare_final_r && prepare_beats_r == length_w)
                ? prepare_tail_keep_r : 32'hffffffff;
            logical_last_r[alloc_ptr_r] <= (prepare_final_r && prepare_beats_r == length_w);
        end
        if (pool_read_w) begin
            pending_owner_r <= owner_r[consume_ptr_r];
            pending_keep_r <= ((consume_beat_r == 0)
                ? head_keep_r[consume_ptr_r] : 32'hffffffff)
                & ((consume_beat_r + 5'd1 == length_r[consume_ptr_r])
                ? tail_keep_r[consume_ptr_r] : 32'hffffffff);
            pending_last_r <= logical_last_r[consume_ptr_r]
                && (consume_beat_r + 5'd1 == length_r[consume_ptr_r]);
            pending_end_r <= (consume_beat_r + 5'd1 == length_r[consume_ptr_r]);
            pending_slot_r <= consume_ptr_r;
        end
        if (pending_r) begin
            data_r[tail_r] <= pool_data_w;
            keep_r[tail_r] <= pending_keep_r;
            client_r[tail_r] <= pending_owner_r;
            last_r[tail_r] <= pending_last_r;
            end_r[tail_r] <= pending_end_r;
            slot_r[tail_r] <= pending_slot_r;
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            active_r <= 7'b0;
            issue_r <= 7'b0;
            done_r <= 7'b0;
            round_r <= 3'b0;
            occupied_r <= 4'b0;
            filled_r <= 4'b0;
            issued_r <= 4'b0;
            alloc_ptr_r <= 2'b0;
            receive_ptr_r <= 2'b0;
            receive_beat_r <= 4'b0;
            consume_ptr_r <= 2'b0;
            consume_beat_r <= 5'b0;
            ar_valid_r <= 1'b0;
            pending_r <= 1'b0;
            head_r <= 1'b0;
            tail_r <= 1'b0;
            count_r <= 2'b0;
            dma_error_o <= 1'b0;
            for (idx_r = 0; idx_r < 7; idx_r = idx_r + 1) begin
                addr_r[idx_r] <= 32'b0;
                beats_r[idx_r] <= 32'b0;
            end
        end else begin
            done_r <= 7'b0;
            if (start_i) dma_error_o <= 1'b0;
            if (r_fire_w && m_axi_rresp_i != 2'b00) dma_error_o <= 1'b1;
            for (idx_r = 0; idx_r < 7; idx_r = idx_r + 1) begin
                if (req_valid_w[idx_r] && !active_r[idx_r] && !stop_i) begin
                    active_r[idx_r] <= 1'b1;
                    issue_r[idx_r] <= 1'b1;
                    addr_r[idx_r] <= {req_addr_w[idx_r][31:5], 5'b0};
                    beats_r[idx_r] <= (req_bytes_w[idx_r]
                        + {27'b0, req_addr_w[idx_r][4:0]} + 32'd31) >> 5;

                end
            end
            if (prepare_build_w) begin
                ar_valid_r <= 1'b1;
                occupied_r[alloc_ptr_r] <= 1'b1;
            end
            if (ar_fire_w) begin
                ar_valid_r <= 1'b0;
                issued_r[alloc_ptr_r] <= 1'b1;
                addr_r[prepare_client_r] <= prepare_next_addr_r;
                beats_r[prepare_client_r] <= prepare_remaining_r;
                if (logical_last_r[alloc_ptr_r]) issue_r[prepare_client_r] <= 1'b0;
                round_r <= (prepare_client_r == 3'd6)
                    ? 3'b0 : prepare_client_r + 3'd1;
                alloc_ptr_r <= alloc_ptr_r + 2'd1;
            end
            if (r_fire_w) begin
                receive_beat_r <= receive_beat_r + 4'd1;
                if ({1'b0, receive_beat_r} + 5'd1 == length_r[receive_ptr_r]) begin
                    receive_beat_r <= 4'b0;
                    filled_r[receive_ptr_r] <= 1'b1;
                    issued_r[receive_ptr_r] <= 1'b0;
                    receive_ptr_r <= receive_ptr_r + 2'd1;
                end
            end
            pending_r <= pool_read_w;
            if (pool_read_w) consume_beat_r <= consume_beat_r + 5'd1;
            if (pending_r) tail_r <= !tail_r;
            if (pop_w) begin
                head_r <= !head_r;
                if (end_r[head_r]) begin
                    occupied_r[slot_r[head_r]] <= 1'b0;
                    filled_r[slot_r[head_r]] <= 1'b0;
                    consume_ptr_r <= consume_ptr_r + 2'd1;
                    consume_beat_r <= 5'b0;
                end
                if (last_r[head_r]) begin
                    active_r[client_r[head_r]] <= 1'b0;
                    done_r[client_r[head_r]] <= 1'b1;
                end
            end
            case ({pending_r, pop_w})
                2'b10: count_r <= count_r + 2'd1;
                2'b01: count_r <= count_r - 2'd1;
                default: begin end
            endcase
        end
    end
    // 7 independent client masks are small registers, not a multi-write RAM array.
    genvar keep_client;
    generate
        for (keep_client = 0; keep_client < 7; keep_client = keep_client + 1) begin : g_keep
            localparam [2:0] CLIENT = keep_client;
            reg [31:0] first_keep_r;
            wire accept_w;
            wire consumed_w;
            assign accept_w = req_valid_w[keep_client] && !active_r[keep_client] && !stop_i;
            assign consumed_w = (ar_fire_w) &&
                owner_r[alloc_ptr_r] == CLIENT;
            assign first_keep_w[keep_client] = first_keep_r;
            always @(posedge clk_i) begin
                if (accept_w || consumed_w) begin
                    first_keep_r <= consumed_w ? 32'hffffffff :
                        32'hffffffff << req_addr_w[keep_client][4:0];
                end
            end
        end
    endgenerate
endmodule
