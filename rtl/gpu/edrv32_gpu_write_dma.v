// File: edrv32_gpu_write_dma.v
// Spec: gpu-spec 5, 6; gpu-microarch 4.5, 4.9.
// Description: Four byte-range clients share two ordered AXI write bursts.
// A complete burst is buffered before AW; accepted requests finish through stop.
// Clock: clk_gpu.
module edrv32_gpu_write_dma (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Independent logical write clients.
    input wire object_write_req_valid_i,
    output wire object_write_req_ready_o,
    input wire [31:0] object_write_req_addr_i,
    input wire [31:0] object_write_req_bytes_i,
    input wire object_write_data_valid_i,
    output wire object_write_data_ready_o,
    input wire [255:0] object_write_data_data_i,
    input wire [31:0] object_write_data_keep_i,
    input wire object_write_data_last_i,
    output wire object_write_done_o,

    input wire hit_write_req_valid_i,
    output wire hit_write_req_ready_o,
    input wire [31:0] hit_write_req_addr_i,
    input wire [31:0] hit_write_req_bytes_i,
    input wire hit_write_data_valid_i,
    output wire hit_write_data_ready_o,
    input wire [255:0] hit_write_data_data_i,
    input wire [31:0] hit_write_data_keep_i,
    input wire hit_write_data_last_i,
    output wire hit_write_done_o,

    input wire free_write_req_valid_i,
    output wire free_write_req_ready_o,
    input wire [31:0] free_write_req_addr_i,
    input wire [31:0] free_write_req_bytes_i,
    input wire free_write_data_valid_i,
    output wire free_write_data_ready_o,
    input wire [255:0] free_write_data_data_i,
    input wire [31:0] free_write_data_keep_i,
    input wire free_write_data_last_i,
    output wire free_write_done_o,

    input wire resolve_write_req_valid_i,
    output wire resolve_write_req_ready_o,
    input wire [31:0] resolve_write_req_addr_i,
    input wire [31:0] resolve_write_req_bytes_i,
    input wire resolve_write_data_valid_i,
    output wire resolve_write_data_ready_o,
    input wire [255:0] resolve_write_data_data_i,
    input wire [31:0] resolve_write_data_keep_i,
    input wire resolve_write_data_last_i,
    output wire resolve_write_done_o,

    // AXI256 write master.
    output wire m_axi_awid_o,
    output wire [31:0] m_axi_awaddr_o,
    output wire [3:0] m_axi_awlen_o,
    output wire m_axi_awvalid_o,
    input wire m_axi_awready_i,
    output wire [255:0] m_axi_wdata_o,
    output wire [31:0] m_axi_wstrb_o,
    output wire m_axi_wlast_o,
    output wire m_axi_wvalid_o,
    input wire m_axi_wready_i,
    input wire m_axi_bid_i,
    input wire [1:0] m_axi_bresp_i,
    input wire m_axi_bvalid_i,
    output wire m_axi_bready_o,

    // Run lifecycle.
    input wire start_i,
    input wire stop_i,
    output wire dma_idle_o,
    output reg dma_error_o
);
    wire [3:0] req_valid_w;
    wire [31:0] req_addr_w [0:3];
    wire [31:0] req_bytes_w [0:3];
    wire [3:0] data_valid_w;
    wire [255:0] data_w [0:3];
    wire [31:0] keep_w [0:3];
    wire [3:0] last_w;
    reg [3:0] active_r;
    reg [3:0] issue_r;
    reg [3:0] done_r;
    reg [31:0] addr_r [0:3];
    reg [31:0] beats_r [0:3];
    reg [31:0] first_keep_r [0:3];
    reg [31:0] last_keep_r [0:3];
    reg [1:0] round_r;
    reg choose_valid_w;
    reg [1:0] choose_w;
    reg [4:0] length_w;
    reg [8:0] boundary_w;
    integer scan_w;
    reg [1:0] client_w;
    integer idx_r;
    integer data_idx_r;

    reg [1:0] occupied_r;
    reg [1:0] filled_r;
    reg [1:0] issued_r;
    reg [1:0] sent_r;
    reg [1:0] owner_r [0:1];
    reg [31:0] burst_addr_r [0:1];
    reg [4:0] length_r [0:1];
    reg logical_last_r [0:1];
    reg alloc_ptr_r;
    reg aw_ptr_r;
    reg write_ptr_r;
    reg response_ptr_r;
    reg filling_r;
    reg [3:0] fill_beat_r;
    reg [4:0] send_beat_r;
    reg [31:0] strobe_r [0:31];
    wire fill_w;
    wire [31:0] fill_keep_w;
    wire aw_fire_w;
    wire b_fire_w;
    wire pool_read_w;
    wire [4:0] pool_addr_w;
    wire [255:0] pool_data_w;
    reg pending_r;
    reg [31:0] pending_keep_r;
    reg pending_last_r;
    reg [255:0] out_data_r [0:1];
    reg [31:0] out_keep_r [0:1];
    reg out_last_r [0:1];
    reg head_r;
    reg tail_r;
    reg [1:0] count_r;
    wire pop_w;
    wire unused_axi_w;
    assign unused_axi_w = m_axi_bid_i;
    assign req_valid_w[0] = object_write_req_valid_i;
    assign req_addr_w[0] = object_write_req_addr_i;
    assign req_bytes_w[0] = object_write_req_bytes_i;
    assign object_write_req_ready_o = !active_r[0] && !stop_i;
    assign data_valid_w[0] = object_write_data_valid_i;
    assign data_w[0] = object_write_data_data_i;
    assign keep_w[0] = object_write_data_keep_i;
    assign last_w[0] = object_write_data_last_i;
    assign object_write_data_ready_o = filling_r && (owner_r[alloc_ptr_r] == 2'd0);
    assign object_write_done_o = done_r[0];
    assign req_valid_w[1] = hit_write_req_valid_i;
    assign req_addr_w[1] = hit_write_req_addr_i;
    assign req_bytes_w[1] = hit_write_req_bytes_i;
    assign hit_write_req_ready_o = !active_r[1] && !stop_i;
    assign data_valid_w[1] = hit_write_data_valid_i;
    assign data_w[1] = hit_write_data_data_i;
    assign keep_w[1] = hit_write_data_keep_i;
    assign last_w[1] = hit_write_data_last_i;
    assign hit_write_data_ready_o = filling_r && (owner_r[alloc_ptr_r] == 2'd1);
    assign hit_write_done_o = done_r[1];
    assign req_valid_w[2] = free_write_req_valid_i;
    assign req_addr_w[2] = free_write_req_addr_i;
    assign req_bytes_w[2] = free_write_req_bytes_i;
    assign free_write_req_ready_o = !active_r[2] && !stop_i;
    assign data_valid_w[2] = free_write_data_valid_i;
    assign data_w[2] = free_write_data_data_i;
    assign keep_w[2] = free_write_data_keep_i;
    assign last_w[2] = free_write_data_last_i;
    assign free_write_data_ready_o = filling_r && (owner_r[alloc_ptr_r] == 2'd2);
    assign free_write_done_o = done_r[2];
    assign req_valid_w[3] = resolve_write_req_valid_i;
    assign req_addr_w[3] = resolve_write_req_addr_i;
    assign req_bytes_w[3] = resolve_write_req_bytes_i;
    assign resolve_write_req_ready_o = !active_r[3] && !stop_i;
    assign data_valid_w[3] = resolve_write_data_valid_i;
    assign data_w[3] = resolve_write_data_data_i;
    assign keep_w[3] = resolve_write_data_keep_i;
    assign last_w[3] = resolve_write_data_last_i;
    assign resolve_write_data_ready_o = filling_r && (owner_r[alloc_ptr_r] == 2'd3);
    assign resolve_write_done_o = done_r[3];

    assign fill_w = filling_r && data_valid_w[owner_r[alloc_ptr_r]];
    assign fill_keep_w = keep_w[owner_r[alloc_ptr_r]]
        & ((fill_beat_r == 0) ? first_keep_r[owner_r[alloc_ptr_r]] : 32'hffffffff)
        & (({1'b0, fill_beat_r} + 5'd1 == length_r[alloc_ptr_r])
            && logical_last_r[alloc_ptr_r]
            ? last_keep_r[owner_r[alloc_ptr_r]] : 32'hffffffff);
    assign m_axi_awid_o = 1'b0;
    assign m_axi_awaddr_o = burst_addr_r[aw_ptr_r];
    assign m_axi_awlen_o = length_r[aw_ptr_r][3:0] - 4'd1;
    assign m_axi_awvalid_o = filled_r[aw_ptr_r] && !issued_r[aw_ptr_r];
    assign aw_fire_w = m_axi_awvalid_o && m_axi_awready_i;
    assign m_axi_wdata_o = out_data_r[head_r];
    assign m_axi_wstrb_o = out_keep_r[head_r];
    assign m_axi_wlast_o = out_last_r[head_r];
    assign m_axi_wvalid_o = count_r != 0;
    assign pop_w = m_axi_wvalid_o && m_axi_wready_i;
    assign m_axi_bready_o = sent_r[response_ptr_r];
    assign b_fire_w = m_axi_bvalid_i && m_axi_bready_o;
    assign dma_idle_o = !(|active_r) && !(|occupied_r) && !filling_r
        && !pending_r && (count_r == 0);
    assign pool_read_w = issued_r[write_ptr_r] && !sent_r[write_ptr_r]
        && (send_beat_r < length_r[write_ptr_r])
        && ({1'b0, count_r} + {2'b0, pending_r} < 3'd2);
    assign pool_addr_w = {write_ptr_r, send_beat_r[3:0]};

    edrv32_ram_gpu_write_pool u_pool (
        .clk_i(clk_i),
        .wr_en_i(fill_w),
        .wr_addr_i({alloc_ptr_r, fill_beat_r}),
        .wr_data_i(data_w[owner_r[alloc_ptr_r]]),
        .rd_en_i(pool_read_w),
        .rd_addr_i(pool_addr_w),
        .rd_data_o(pool_data_w)
    );

    always @(*) begin
        choose_valid_w = 1'b0;
        choose_w = 2'b0;
        client_w = 0;
        length_w = 5'd16;
        boundary_w = 9'b0;
        for (scan_w = 0; scan_w < 4; scan_w = scan_w + 1) begin
            client_w = round_r + scan_w[1:0];
            if (!choose_valid_w && issue_r[client_w]) begin
                choose_valid_w = 1'b1;
                choose_w = client_w[1:0];
            end
        end
        boundary_w = 9'd128 - {2'b0, addr_r[choose_w][11:5]};
        if (beats_r[choose_w] < 32'd16) length_w = beats_r[choose_w][4:0];
        if ({4'b0, length_w} > boundary_w) length_w = boundary_w[4:0];
    end

    always @(posedge clk_i) begin
        for (data_idx_r = 0; data_idx_r < 4; data_idx_r = data_idx_r + 1) begin
            if (req_valid_w[data_idx_r] && !active_r[data_idx_r] && !stop_i) begin
                    first_keep_r[data_idx_r] <= 32'hffffffff << req_addr_w[data_idx_r][4:0];
                    last_keep_r[data_idx_r] <= 32'hffffffff
                        >> ((32'd0 - req_addr_w[data_idx_r] - req_bytes_w[data_idx_r]) & 32'd31);
            end
        end
        if (fill_w && {1'b0, fill_beat_r} + 5'd1 == length_r[alloc_ptr_r])
            first_keep_r[owner_r[alloc_ptr_r]] <= 32'hffffffff;
        if (!filling_r && choose_valid_w && !occupied_r[alloc_ptr_r]) begin
            owner_r[alloc_ptr_r] <= choose_w;
            burst_addr_r[alloc_ptr_r] <= addr_r[choose_w];
            length_r[alloc_ptr_r] <= length_w;
            logical_last_r[alloc_ptr_r] <= (beats_r[choose_w] == {27'b0, length_w});
        end
        if (fill_w) strobe_r[{alloc_ptr_r, fill_beat_r}] <= fill_keep_w;
        if (pool_read_w) begin
            pending_keep_r <= strobe_r[pool_addr_w];
            pending_last_r <= (send_beat_r + 5'd1 == length_r[write_ptr_r]);
        end
        if (pending_r) begin
            out_data_r[tail_r] <= pool_data_w;
            out_keep_r[tail_r] <= pending_keep_r;
            out_last_r[tail_r] <= pending_last_r;
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            active_r <= 4'b0;
            issue_r <= 4'b0;
            done_r <= 4'b0;
            round_r <= 2'b0;
            occupied_r <= 2'b0;
            filled_r <= 2'b0;
            issued_r <= 2'b0;
            sent_r <= 2'b0;
            alloc_ptr_r <= 1'b0;
            aw_ptr_r <= 1'b0;
            write_ptr_r <= 1'b0;
            response_ptr_r <= 1'b0;
            filling_r <= 1'b0;
            fill_beat_r <= 4'b0;
            send_beat_r <= 5'b0;
            pending_r <= 1'b0;
            head_r <= 1'b0;
            tail_r <= 1'b0;
            count_r <= 2'b0;
            dma_error_o <= 1'b0;
            for (idx_r = 0; idx_r < 4; idx_r = idx_r + 1) begin
                addr_r[idx_r] <= 32'b0;
                beats_r[idx_r] <= 32'b0;
            end
        end else begin
            done_r <= 4'b0;
            if (start_i) dma_error_o <= 1'b0;
            if (b_fire_w && m_axi_bresp_i != 2'b00) dma_error_o <= 1'b1;
            for (idx_r = 0; idx_r < 4; idx_r = idx_r + 1) begin
                if (req_valid_w[idx_r] && !active_r[idx_r] && !stop_i) begin
                    active_r[idx_r] <= 1'b1;
                    issue_r[idx_r] <= 1'b1;
                    addr_r[idx_r] <= {req_addr_w[idx_r][31:5], 5'b0};
                    beats_r[idx_r] <= (req_bytes_w[idx_r]
                        + {27'b0, req_addr_w[idx_r][4:0]} + 32'd31) >> 5;

                end
            end
            if (!filling_r && choose_valid_w && !occupied_r[alloc_ptr_r]) begin
                occupied_r[alloc_ptr_r] <= 1'b1;
                filling_r <= 1'b1;
                fill_beat_r <= 4'b0;
            end
            if (fill_w) begin
                fill_beat_r <= fill_beat_r + 4'd1;
                if ({1'b0, fill_beat_r} + 5'd1 == length_r[alloc_ptr_r]) begin
                    filling_r <= 1'b0;
                    filled_r[alloc_ptr_r] <= 1'b1;
                    addr_r[owner_r[alloc_ptr_r]] <= addr_r[owner_r[alloc_ptr_r]]
                        + {22'b0, length_r[alloc_ptr_r], 5'b0};
                    beats_r[owner_r[alloc_ptr_r]] <= beats_r[owner_r[alloc_ptr_r]]
                        - {27'b0, length_r[alloc_ptr_r]};
                    if (last_w[owner_r[alloc_ptr_r]]) issue_r[owner_r[alloc_ptr_r]] <= 1'b0;
                    round_r <= owner_r[alloc_ptr_r] + 2'd1;
                    alloc_ptr_r <= !alloc_ptr_r;
                end
            end
            if (aw_fire_w) begin
                issued_r[aw_ptr_r] <= 1'b1;
                aw_ptr_r <= !aw_ptr_r;
            end
            pending_r <= pool_read_w;
            if (pool_read_w) send_beat_r <= send_beat_r + 5'd1;
            if (pending_r) tail_r <= !tail_r;
            if (pop_w) begin
                head_r <= !head_r;
                if (out_last_r[head_r]) begin
                    sent_r[write_ptr_r] <= 1'b1;
                    write_ptr_r <= !write_ptr_r;
                    send_beat_r <= 5'b0;
                end
            end
            if (b_fire_w) begin
                occupied_r[response_ptr_r] <= 1'b0;
                filled_r[response_ptr_r] <= 1'b0;
                issued_r[response_ptr_r] <= 1'b0;
                sent_r[response_ptr_r] <= 1'b0;
                response_ptr_r <= !response_ptr_r;
                if (logical_last_r[response_ptr_r]) begin
                    active_r[owner_r[response_ptr_r]] <= 1'b0;
                    done_r[owner_r[response_ptr_r]] <= 1'b1;
                end
            end            case ({pending_r, pop_w})
                2'b10: count_r <= count_r + 2'd1;
                2'b01: count_r <= count_r - 2'd1;
                default: begin end
            endcase

        end
    end
endmodule
