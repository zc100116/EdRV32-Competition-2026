// File: edrv32_dcache.v
// Spec: cache-spec 2–6; cpu-spec 3.3, 4.7.
// Description: Write-back data cache, forwarding buffer and maintenance walker.
// Two-way write-back cache with a one-entry forwarding store buffer.
// Maintenance scans synchronous tag RAM; committed device requests use a
// separate sequencer so software can poll during maintenance. Clock: clk_sys.
module edrv32_dcache (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Core data interface.
    input wire dc_req_valid_i,
    input wire [31:0] dc_req_addr_i,
    input wire dc_req_store_i,
    input wire [1:0] dc_req_size_i,
    output wire dc_req_ready_o,
    output wire dc_resp_valid_o,
    output wire [31:0] dc_resp_data_o,
    output wire dc_resp_err_o,
    output wire dc_resp_device_o,
    input wire dc_kill_i,
    input wire dc_commit_i,
    input wire [31:0] dc_store_data_i,
    input wire dc_fence_i,
    input wire dc_clean_all_i,
    output wire dc_fence_done_o,
    output wire dc_wb_event_o,

    // AXI64 read/write master.
    output wire [3:0] axi_awid_o,
    output wire [31:0] axi_awaddr_o,
    output wire [7:0] axi_awlen_o,
    output wire [2:0] axi_awsize_o,
    output wire [1:0] axi_awburst_o,
    output wire axi_awvalid_o,
    input wire axi_awready_i,
    output wire [63:0] axi_wdata_o,
    output wire [7:0] axi_wstrb_o,
    output wire axi_wlast_o,
    output wire axi_wvalid_o,
    input wire axi_wready_i,
    input wire [3:0] axi_bid_i,
    input wire [1:0] axi_bresp_i,
    input wire axi_bvalid_i,
    output wire axi_bready_o,
    output wire [3:0] axi_arid_o,
    output wire [31:0] axi_araddr_o,
    output wire [7:0] axi_arlen_o,
    output wire [2:0] axi_arsize_o,
    output wire [1:0] axi_arburst_o,
    output wire axi_arvalid_o,
    input wire axi_arready_i,
    input wire [3:0] axi_rid_i,
    input wire [63:0] axi_rdata_i,
    input wire [1:0] axi_rresp_i,
    input wire axi_rlast_i,
    input wire axi_rvalid_i,
    output wire axi_rready_o,

    // Maintenance and writeback error interface.
    input wire maint_req_valid_i,
    output wire maint_req_ready_o,
    input wire [2:0] maint_cmd_i,
    input wire [31:0] maint_addr_i,
    input wire [31:0] maint_size_i,
    output wire maint_busy_o,
    output wire wb_err_o,
    output wire [31:0] wb_err_addr_o
);
    localparam [3:0] S_IDLE = 4'd0;
    localparam [3:0] S_AR = 4'd1;
    localparam [3:0] S_FILL = 4'd2;
    localparam [3:0] S_RETURN = 4'd3;
    localparam [3:0] S_WB_AW = 4'd4;
    localparam [3:0] S_WB_READ = 4'd5;
    localparam [3:0] S_WB_W = 4'd6;
    localparam [3:0] S_WB_B = 4'd7;
    localparam [3:0] S_MREAD = 4'd8;
    localparam [3:0] S_MCHECK = 4'd9;
    localparam [3:0] S_MNEXT = 4'd10;
    localparam [3:0] S_REPLAY = 4'd11;
    localparam [3:0] D_IDLE = 4'd0;
    localparam [3:0] D_COMMIT = 4'd1;
    localparam [3:0] D_BUS = 4'd2;
    localparam [3:0] D_AR = 4'd3;
    localparam [3:0] D_R = 4'd4;
    localparam [3:0] D_AW = 4'd5;
    localparam [3:0] D_W = 4'd6;
    localparam [3:0] D_B = 4'd7;
    localparam [3:0] D_RETURN = 4'd8;
    reg [3:0] state_r;
    reg [3:0] device_state_r;
    reg [127:0] valid0_r;
    reg [127:0] valid1_r;
    reg [127:0] dirty0_r;
    reg [127:0] dirty1_r;
    reg [127:0] lru_r;
    reg lookup_valid_r;
    reg [31:0] addr_r;
    reg store_r;
    reg [1:0] size_r;
    reg deferred_lookup_r;
    reg victim_r;
    reg [6:0] victim_idx_r;
    reg [31:0] wb_addr_r;
    reg killed_r;
    reg fill_err_r;
    reg [1:0] beat_r;
    reg [63:0] result_r;
    reg store_pending_r;
    reg store_way_r;
    reg [31:0] store_addr_r;
    reg [1:0] store_size_r;
    reg buffer_valid_r;
    reg buffer_way_r;
    reg [31:0] buffer_addr_r;
    reg [31:0] buffer_data_r;
    reg [3:0] buffer_mask_r;
    reg [31:0] forward_data_r;
    reg [3:0] forward_mask_r;
    reg [31:0] device_addr_r;
    reg [1:0] device_size_r;
    reg device_store_r;
    reg [31:0] device_data_r;
    reg [31:0] device_result_r;
    reg device_err_r;
    reg maintenance_r;
    reg fence_clean_r;
    reg clean_seen_r;
    reg [2:0] maint_cmd_r;
    reg [31:0] maint_addr_r;
    reg [32:0] maint_end_r;
    reg [7:0] maint_scan_r;
    reg fence_done_r;
    wire cacheable_w;
    wire device_w;
    wire pma_err_w;
    wire accept_w;
    wire request_cacheable_w;
    wire request_device_w;
    wire request_pma_err_w;
    wire device_accept_w;
    wire hit0_w;
    wire hit1_w;
    wire hit_w;
    wire lookup_done_w;
    wire return_store_w;
    wire store_result_w;
    wire buffer_push_w;
    wire [31:0] push_addr_w;
    wire [1:0] push_size_w;
    wire push_way_w;
    wire [3:0] push_mask_w;
    wire [63:0] buffer_data64_w;
    wire [7:0] buffer_mask64_w;
    wire fill_write_w;
    wire tag_write_w;
    wire [8:0] read_addr_w;
    wire ram_read_w;
    wire [8:0] write_addr_w;
    wire [63:0] write_data_w;
    wire [7:0] write_mask_w;
    wire [19:0] tag0_w;
    wire [19:0] tag1_w;
    wire [63:0] data0_w;
    wire [63:0] data1_w;
    wire [19:0] scan_tag_w;
    wire scan_valid_w;
    wire scan_dirty_w;
    wire [31:0] scan_addr_w;
    wire scan_match_w;
    wire maintenance_start_w;
    wire maintenance_array_start_w;
    wire device_bus_free_w;
    wire device_bus_active_w;
    wire [31:0] raw_load_w;
    reg [31:0] merged_load_w;
    wire [63:0] device_shifted_w;
    wire unused_axi_w;
    integer byte_idx_w;

    assign device_shifted_w = axi_rdata_i >> {device_addr_r[2:0], 3'b0};
    assign unused_axi_w = &{1'b0, axi_rid_i, axi_bid_i, device_shifted_w[63:32],
                                buffer_addr_r[1:0], cacheable_w,
                                request_cacheable_w, request_pma_err_w};
    // cache-spec 5.2/5.3: this early decode only suppresses device RAM reads.
    // Acceptance and request control use the registered address's M-stage PMA.
    edrv32_cache_pma u_request_pma (
        .addr_i(dc_req_addr_i),
        .execute_i(1'b0),
        .store_i(dc_req_store_i),
        .cacheable_o(request_cacheable_w),
        .device_o(request_device_w),
        .err_o(request_pma_err_w)
    );
    edrv32_cache_pma u_pma (
        .addr_i(addr_r),
        .execute_i(1'b0),
        .store_i(store_r),
        .cacheable_o(cacheable_w),
        .device_o(device_w),
        .err_o(pma_err_w)
    );
    assign hit0_w = valid0_r[addr_r[11:5]] && tag0_w == addr_r[31:12];
    assign hit1_w = valid1_r[addr_r[11:5]] && tag1_w == addr_r[31:12];
    assign hit_w = hit0_w || hit1_w;
    assign lookup_done_w = lookup_valid_r && !device_w && !deferred_lookup_r &&
                            (pma_err_w || hit_w);
    assign dc_req_ready_o = device_state_r == D_IDLE &&
        (maintenance_r ? !lookup_valid_r :
            (state_r == S_IDLE && (!lookup_valid_r || lookup_done_w)));
    assign accept_w = dc_req_valid_i && dc_req_ready_o;
    assign device_accept_w = lookup_valid_r && device_w;
    // PMA classification occurs after the E/M acceptance edge (cache-spec 5.3).
    assign dc_resp_device_o = device_state_r != D_IDLE || device_accept_w;
    assign dc_resp_valid_o =
        ((state_r == S_IDLE && lookup_done_w) ||
            (state_r == S_RETURN && !killed_r) || device_state_r == D_RETURN);
    // cache-spec 6: qualify errors with registered response state, never tag hit.
    assign dc_resp_err_o = device_state_r == D_RETURN ? device_err_r :
        (state_r == S_RETURN ? (!killed_r && fill_err_r) :
        (state_r == S_IDLE && lookup_valid_r && !deferred_lookup_r && pma_err_w));
    assign raw_load_w = state_r == S_RETURN ?
                        (addr_r[2] ? result_r[63:32] : result_r[31:0]) :
                        (addr_r[2] ? (hit0_w ? data0_w[63:32] : data1_w[63:32]) :
                                        (hit0_w ? data0_w[31:0] : data1_w[31:0]));
    always @(*) begin
        merged_load_w = raw_load_w;
        for (byte_idx_w = 0; byte_idx_w < 4; byte_idx_w = byte_idx_w + 1) begin
            if (forward_mask_r[byte_idx_w]) begin
                merged_load_w[byte_idx_w*8 +: 8] = forward_data_r[byte_idx_w*8 +: 8];
            end
            if (buffer_valid_r && buffer_addr_r[31:2] == addr_r[31:2] &&
                buffer_mask_r[byte_idx_w]) begin
                merged_load_w[byte_idx_w*8 +: 8] = buffer_data_r[byte_idx_w*8 +: 8];
            end
        end
    end
    assign dc_resp_data_o = device_state_r == D_RETURN ? device_result_r :
                            merged_load_w >> {addr_r[1:0], 3'b0};
    assign return_store_w = state_r == S_RETURN && store_r && !fill_err_r && !killed_r;
    assign store_result_w = (state_r == S_IDLE && lookup_done_w && !pma_err_w && store_r) ||
                            return_store_w;
    assign buffer_push_w = dc_commit_i && device_state_r == D_IDLE &&
                            (store_pending_r || store_result_w);
    assign push_addr_w = store_result_w ? addr_r : store_addr_r;
    assign push_size_w = store_result_w ? size_r : store_size_r;
    assign push_way_w = return_store_w ? victim_r :
                        (store_result_w ? hit1_w : store_way_r);
    assign push_mask_w = (push_size_w == 0 ? 4'b0001 :
                            push_size_w == 1 ? 4'b0011 : 4'b1111) << push_addr_w[1:0];
    assign buffer_data64_w = buffer_addr_r[2] ? {buffer_data_r, 32'b0} :
                                                                {32'b0, buffer_data_r};
    assign buffer_mask64_w = buffer_addr_r[2] ? {buffer_mask_r, 4'b0} :
                                                                {4'b0, buffer_mask_r};
    assign fill_write_w = state_r == S_FILL && axi_rvalid_i;
    assign tag_write_w = fill_write_w && axi_rlast_i && !fill_err_r && axi_rresp_i == 0;
    assign write_addr_w = buffer_valid_r ? buffer_addr_r[11:3] : {addr_r[11:5], beat_r};
    assign write_data_w = buffer_valid_r ? buffer_data64_w : axi_rdata_i;
    assign write_mask_w = buffer_valid_r ? buffer_mask64_w : 8'hff;
    assign read_addr_w = state_r == S_WB_READ ? {victim_idx_r, beat_r} :
                            (state_r == S_MREAD ? {maint_scan_r[7:1], 2'b0} :
                                (state_r == S_REPLAY ? addr_r[11:3] : dc_req_addr_i[11:3]));
    assign ram_read_w = (accept_w && !maintenance_r && !maintenance_array_start_w &&
                        !request_device_w) || state_r == S_REPLAY ||
                        state_r == S_WB_READ || state_r == S_MREAD;
    assign scan_tag_w = maint_scan_r[0] ? tag1_w : tag0_w;
    assign scan_valid_w = maint_scan_r[0] ? valid1_r[maint_scan_r[7:1]] :
                                            valid0_r[maint_scan_r[7:1]];
    assign scan_dirty_w = maint_scan_r[0] ? dirty1_r[maint_scan_r[7:1]] :
                                            dirty0_r[maint_scan_r[7:1]];
    assign scan_addr_w = {scan_tag_w, maint_scan_r[7:1], 5'b0};
    assign scan_match_w = scan_valid_w && (maint_cmd_r == 4 ||
        ({1'b0, scan_addr_w} < maint_end_r &&
            {1'b0, scan_addr_w} + 33'd32 > {1'b0, maint_addr_r}));
    assign maint_busy_o = maintenance_r;
    assign maint_req_ready_o = state_r == S_IDLE && device_state_r == D_IDLE &&
                                !lookup_valid_r && !store_pending_r && !buffer_valid_r &&
                                !dc_clean_all_i;
    assign maintenance_start_w = (maint_req_valid_i && maint_req_ready_o) ||
        (dc_clean_all_i && !clean_seen_r && !maintenance_r && state_r == S_IDLE &&
            device_state_r == D_IDLE && !lookup_valid_r && !store_pending_r && !buffer_valid_r);
    // cache-spec 5.4: zero-length range commands finish without array ownership.
    assign maintenance_array_start_w = maintenance_start_w &&
        (dc_clean_all_i || maint_cmd_i == 4 || maint_size_i != 0);
    assign dc_fence_done_o = fence_done_r ||
        (dc_fence_i && !buffer_valid_r && !buffer_push_w);
    // cache-spec v0.3, 5.2: one HPM event for each accepted dirty-line AW.
    assign dc_wb_event_o = state_r == S_WB_AW && axi_awready_i;
    assign wb_err_o = state_r == S_WB_B && axi_bvalid_i && axi_bresp_i != 0;
    assign wb_err_addr_o = wb_addr_r;

    // Only the maintenance scan yields the shared bus to device transactions.
    assign device_bus_free_w = state_r == S_IDLE || state_r == S_MREAD ||
                                state_r == S_MCHECK || state_r == S_MNEXT;
    assign device_bus_active_w = device_state_r >= D_AR && device_state_r <= D_B;
    assign axi_arid_o = 4'b0;
    assign axi_araddr_o = device_bus_active_w ? device_addr_r : {addr_r[31:5], 5'b0};
    assign axi_arlen_o = device_bus_active_w ? 8'd0 : 8'd3;
    assign axi_arsize_o = device_bus_active_w ? {1'b0, device_size_r} : 3'd3;
    assign axi_arburst_o = 2'b01;
    assign axi_arvalid_o = state_r == S_AR || device_state_r == D_AR;
    assign axi_rready_o = state_r == S_FILL || device_state_r == D_R;
    assign axi_awid_o = 4'b0;
    assign axi_awaddr_o = device_bus_active_w ? device_addr_r : wb_addr_r;
    assign axi_awlen_o = device_bus_active_w ? 8'd0 : 8'd3;
    assign axi_awsize_o = device_bus_active_w ? {1'b0, device_size_r} : 3'd3;
    assign axi_awburst_o = 2'b01;
    assign axi_awvalid_o = state_r == S_WB_AW || device_state_r == D_AW;
    assign axi_wdata_o = device_bus_active_w ?
                        ({32'b0, device_data_r} << {device_addr_r[2:0], 3'b0}) :
                        (victim_r ? data1_w : data0_w);
    assign axi_wstrb_o = device_bus_active_w ?
        ((device_size_r == 0 ? 8'h01 : device_size_r == 1 ? 8'h03 : 8'h0f)
            << device_addr_r[2:0]) : 8'hff;
    assign axi_wlast_o = device_bus_active_w || beat_r == 3;
    assign axi_wvalid_o = state_r == S_WB_W || device_state_r == D_W;
    assign axi_bready_o = state_r == S_WB_B || device_state_r == D_B;
    edrv32_ram_dcache_tag u_tag0 (
        .clk_i(clk_i),
        .wr_en_i(tag_write_w && victim_r == 1'b0),
        .wr_addr_i(addr_r[11:5]),
        .wr_data_i(addr_r[31:12]),
        .rd_en_i(ram_read_w),
        .rd_addr_i(read_addr_w[8:2]),
        .rd_data_o(tag0_w)
    );
    edrv32_ram_dcache_data u_data0 (
        .clk_i(clk_i),
        .wr_en_i((buffer_valid_r && buffer_way_r == 1'b0) ||
                    (fill_write_w && victim_r == 1'b0)),
        .wr_addr_i(write_addr_w),
        .wr_data_i(write_data_w),
        .wr_byte_en_i(write_mask_w),
        .rd_en_i(ram_read_w),
        .rd_addr_i(read_addr_w),
        .rd_data_o(data0_w)
    );
    edrv32_ram_dcache_tag u_tag1 (
        .clk_i(clk_i),
        .wr_en_i(tag_write_w && victim_r == 1'b1),
        .wr_addr_i(addr_r[11:5]),
        .wr_data_i(addr_r[31:12]),
        .rd_en_i(ram_read_w),
        .rd_addr_i(read_addr_w[8:2]),
        .rd_data_o(tag1_w)
    );
    edrv32_ram_dcache_data u_data1 (
        .clk_i(clk_i),
        .wr_en_i((buffer_valid_r && buffer_way_r == 1'b1) ||
                    (fill_write_w && victim_r == 1'b1)),
        .wr_addr_i(write_addr_w),
        .wr_data_i(write_data_w),
        .wr_byte_en_i(write_mask_w),
        .rd_en_i(ram_read_w),
        .rd_addr_i(read_addr_w),
        .rd_data_o(data1_w)
    );
    // Payload registers deliberately have no reset (cache-spec 5.5).
    always @(posedge clk_i) begin
        if (accept_w) begin
            addr_r <= dc_req_addr_i;
            size_r <= dc_req_size_i;
            store_r <= dc_req_store_i;
            forward_data_r <= buffer_data_r;
            forward_mask_r <= buffer_valid_r &&
                                buffer_addr_r[31:2] == dc_req_addr_i[31:2] ? buffer_mask_r : 4'b0;
        end
        if (state_r == S_FILL && axi_rvalid_i && beat_r == addr_r[4:3]) begin
            result_r <= axi_rdata_i;
        end
        if (store_result_w) begin
            store_addr_r <= addr_r;
            store_size_r <= size_r;
            store_way_r <= return_store_w ? victim_r : hit1_w;
        end
        if (buffer_push_w) begin
            buffer_addr_r <= push_addr_w;
            buffer_way_r <= push_way_w;
            buffer_data_r <= dc_store_data_i << {push_addr_w[1:0], 3'b0};
            buffer_mask_r <= push_mask_w;
        end
        if (device_accept_w) begin
            device_addr_r <= addr_r;
            device_size_r <= size_r;
            device_store_r <= store_r;
        end
        if ((device_accept_w || device_state_r == D_COMMIT) && dc_commit_i)
            device_data_r <= dc_store_data_i;
        if (device_state_r == D_R && axi_rvalid_i) begin
            device_result_r <= device_shifted_w[31:0];
        end
        if (state_r == S_IDLE && lookup_valid_r && !deferred_lookup_r &&
            !device_w && !pma_err_w && !hit_w) begin
            wb_addr_r <= {lru_r[addr_r[11:5]] ? tag1_w : tag0_w, addr_r[11:5], 5'b0};
        end
        if (state_r == S_MCHECK && device_state_r == D_IDLE && !device_accept_w) begin
            wb_addr_r <= scan_addr_w;
        end
        if (maintenance_start_w) begin
            maint_cmd_r <= dc_clean_all_i ? 3'd4 : maint_cmd_i;
            maint_addr_r <= maint_addr_i;
            maint_end_r <= {1'b0, maint_addr_i} + {1'b0, maint_size_i};
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            device_state_r <= D_IDLE;
            device_err_r <= 1'b0;
        end else begin
            case (device_state_r)
                D_IDLE: if (device_accept_w && !dc_kill_i) begin
                    device_state_r <= dc_commit_i ? D_BUS : D_COMMIT;
                end
                D_COMMIT: begin
                    if (dc_kill_i) device_state_r <= D_IDLE;
                    else if (dc_commit_i) device_state_r <= D_BUS;
                end
                D_BUS: if (device_bus_free_w) begin
                    device_state_r <= device_store_r ? D_AW : D_AR;
                end
                D_AR: if (axi_arready_i) device_state_r <= D_R;
                D_R: if (axi_rvalid_i) begin
                    device_err_r <= axi_rresp_i != 0;
                    device_state_r <= D_RETURN;
                end
                D_AW: if (axi_awready_i) device_state_r <= D_W;
                D_W: if (axi_wready_i) device_state_r <= D_B;
                D_B: if (axi_bvalid_i) begin
                    device_err_r <= axi_bresp_i != 0;
                    device_state_r <= D_RETURN;
                end
                D_RETURN: device_state_r <= D_IDLE;
                default: begin end
            endcase
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            buffer_valid_r <= 1'b0;
            store_pending_r <= 1'b0;
        end else begin
            buffer_valid_r <= buffer_push_w;
            if (store_result_w) store_pending_r <= 1'b1;
            if (buffer_push_w || dc_kill_i) store_pending_r <= 1'b0;
        end
    end

    // A maintenance-time cached request owns the payload until its array replay.
    // Device requests transfer to their sequencer without stopping the walker.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            lookup_valid_r <= 1'b0;
            deferred_lookup_r <= 1'b0;
        end else begin
            if (accept_w) begin
                lookup_valid_r <= 1'b1;
                deferred_lookup_r <= maintenance_r || maintenance_array_start_w;
            end else if (device_accept_w || dc_kill_i ||
                (state_r == S_IDLE && !maintenance_r && !deferred_lookup_r)) begin
                lookup_valid_r <= 1'b0;
            end
            if (state_r == S_REPLAY) deferred_lookup_r <= 1'b0;
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            valid0_r <= 128'b0;
            valid1_r <= 128'b0;
            dirty0_r <= 128'b0;
            dirty1_r <= 128'b0;
            lru_r <= 128'b0;
            victim_r <= 1'b0;
            victim_idx_r <= 7'b0;
            killed_r <= 1'b0;
            fill_err_r <= 1'b0;
            beat_r <= 2'b0;
            maintenance_r <= 1'b0;
            fence_clean_r <= 1'b0;
            clean_seen_r <= 1'b0;
            maint_scan_r <= 8'b0;
            fence_done_r <= 1'b0;
        end else begin
            fence_done_r <= 1'b0;
            if (!dc_clean_all_i) clean_seen_r <= 1'b0;
            if (maintenance_start_w && dc_clean_all_i) clean_seen_r <= 1'b1;
            if (buffer_valid_r) begin
                if (buffer_way_r) dirty1_r[buffer_addr_r[11:5]] <= 1'b1;
                else dirty0_r[buffer_addr_r[11:5]] <= 1'b1;
            end
            if (dc_kill_i && !maintenance_r && state_r != S_IDLE) killed_r <= 1'b1;
            case (state_r)
                S_IDLE: begin
                    if (lookup_valid_r && !deferred_lookup_r && !device_w && !pma_err_w) begin
                        if (hit_w) lru_r[addr_r[11:5]] <= hit0_w;
                        else begin
                            victim_r <= lru_r[addr_r[11:5]];
                            victim_idx_r <= addr_r[11:5];
                            killed_r <= dc_kill_i;
                            fill_err_r <= 1'b0;
                            beat_r <= 2'b0;
                            state_r <= S_AR;
                            if ((lru_r[addr_r[11:5]] ? dirty1_r[addr_r[11:5]] :
                                                                        dirty0_r[addr_r[11:5]]) ||
                                (buffer_valid_r && buffer_addr_r[11:5] == addr_r[11:5] &&
                                    buffer_way_r == lru_r[addr_r[11:5]])) begin
                                state_r <= S_WB_AW;
                            end
                            if (lru_r[addr_r[11:5]]) valid1_r[addr_r[11:5]] <= 1'b0;
                            else valid0_r[addr_r[11:5]] <= 1'b0;
                        end
                    end
                    if (lookup_valid_r && deferred_lookup_r && !device_w && !dc_kill_i)
                        state_r <= S_REPLAY;
                    if (maintenance_start_w) begin
                        maintenance_r <= 1'b1;
                        fence_clean_r <= dc_clean_all_i;
                        maint_scan_r <= 8'b0;
                        state_r <= S_MREAD;
                        if (!dc_clean_all_i && maint_cmd_i != 4 && maint_size_i == 0) begin
                            maintenance_r <= 1'b0;
                            state_r <= S_IDLE;
                        end
                    end
                end
                S_REPLAY: state_r <= S_IDLE;
                S_AR: if (axi_arready_i) state_r <= S_FILL;
                S_FILL: if (axi_rvalid_i) begin
                    fill_err_r <= fill_err_r || axi_rresp_i != 0;
                    beat_r <= beat_r + 1'b1;
                    if (axi_rlast_i) begin
                        state_r <= S_RETURN;
                        if (victim_r) dirty1_r[addr_r[11:5]] <= 1'b0;
                        else dirty0_r[addr_r[11:5]] <= 1'b0;
                        if (tag_write_w) begin
                            if (victim_r) valid1_r[addr_r[11:5]] <= 1'b1;
                            else valid0_r[addr_r[11:5]] <= 1'b1;
                            lru_r[addr_r[11:5]] <= !victim_r;
                        end
                    end
                end
                S_RETURN: state_r <= S_IDLE;
                S_WB_AW: if (axi_awready_i) begin
                    beat_r <= 2'b0;
                    state_r <= S_WB_READ;
                end
                S_WB_READ: state_r <= S_WB_W;
                S_WB_W: if (axi_wready_i) begin
                    beat_r <= beat_r + 1'b1;
                    state_r <= beat_r == 3 ? S_WB_B : S_WB_READ;
                end
                S_WB_B: if (axi_bvalid_i) begin
                    if (victim_r) dirty1_r[victim_idx_r] <= 1'b0;
                    else dirty0_r[victim_idx_r] <= 1'b0;
                    beat_r <= 2'b0;
                    state_r <= maintenance_r ? S_MNEXT : S_AR;
                    if (maintenance_r && maint_cmd_r == 3) begin
                        if (victim_r) valid1_r[victim_idx_r] <= 1'b0;
                        else valid0_r[victim_idx_r] <= 1'b0;
                    end
                end
                S_MREAD: if (device_state_r == D_IDLE && !device_accept_w) begin
                    state_r <= S_MCHECK;
                end
                S_MCHECK: if (device_state_r == D_IDLE && !device_accept_w) begin
                    state_r <= S_MNEXT;
                    if (scan_match_w) begin
                        if (maint_cmd_r == 2 || (maint_cmd_r == 3 && !scan_dirty_w)) begin
                            if (maint_scan_r[0]) begin
                                valid1_r[maint_scan_r[7:1]] <= 1'b0;
                                dirty1_r[maint_scan_r[7:1]] <= 1'b0;
                            end else begin
                                valid0_r[maint_scan_r[7:1]] <= 1'b0;
                                dirty0_r[maint_scan_r[7:1]] <= 1'b0;
                            end
                        end else if (scan_dirty_w) begin
                            victim_r <= maint_scan_r[0];
                            victim_idx_r <= maint_scan_r[7:1];
                            state_r <= S_WB_AW;
                        end
                    end
                end
                S_MNEXT: if (device_state_r == D_IDLE && !device_accept_w) begin
                    maint_scan_r <= maint_scan_r + 1'b1;
                    state_r <= S_MREAD;
                    if (maint_scan_r == 8'hff) begin
                        maintenance_r <= 1'b0;
                        fence_done_r <= fence_clean_r;
                        state_r <= S_IDLE;
                    end
                end
                default: begin end
            endcase
        end
    end
endmodule
