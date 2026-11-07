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
    input wire [1:0] rst_sys_dlru_n_i,

    // Core data interface.
    input wire dc_req_valid_i,
    input wire dc_req_early_i,
    input wire [31:0] dc_req_addr_i,
    input wire dc_req_store_i,
    input wire [1:0] dc_req_size_i,
    output wire dc_req_ready_o,
    output wire dc_resp_valid_o,
    output wire [63:0] dc_resp_way_data_o,
    output wire [1:0] dc_resp_way_hit_o,
    output wire dc_resp_err_o,
    output wire dc_resp_device_o,
    input wire dc_kill_i,
    input wire dc_commit_i,
    input wire [31:0] dc_store_data_i,
    input wire dc_fence_i,
    input wire dc_clean_all_i,
    output wire dc_fence_done_o,
    output wire dc_wb_event_o,

    // Read-only D-stage query; ordinary requests retain array priority.
    input wire dc_early_valid_i,
    input wire [31:0] dc_early_addr_i,
    output wire [1:0] dc_early_way_hit_o,
    output wire [63:0] dc_early_way_data_o,

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
    reg early_valid_r;
    reg [31:0] early_addr_r;
    reg [17:0] early_tag_r;
    reg early_response_r;
    reg [63:0] early_response_data_r;
    reg [1:0] early_response_way_r;
    reg [7:0] early_byte_select_r;
    reg [7:0] lookup_byte_select_r;
    wire early_hit_enable_w;
    wire [18:0] early_tag0_w;
    wire [1:0] unused_early_dirty_w;
    wire [18:0] early_tag1_w;
    wire [63:0] early_data0_w;
    wire [63:0] early_data1_w;
    wire early_read_w;
    wire early_cacheable_w;
    wire unused_early_device_w;
    wire unused_early_pma_err_w;
    wire early_conflict_w;
    wire early_hit0_w;
    wire early_hit1_w;
    wire early_promote_w;
    wire lookup_accept_w;
    wire [31:0] early_shift0_w;
    wire [31:0] early_shift1_w;
    edrv32_cache_pma u_early_pma (
        .addr_i(dc_early_addr_i),
        .execute_i(1'b0),
        .store_i(1'b0),
        .cacheable_o(early_cacheable_w),
        .device_o(unused_early_device_w),
        .err_o(unused_early_pma_err_w)
    );
    assign early_conflict_w =
        (buffer_valid_r && buffer_addr_r[31:2] == dc_early_addr_i[31:2]) ||
        (store_pending_r && store_addr_r[31:2] == dc_early_addr_i[31:2]) ||
        (lookup_valid_r && store_r && addr_r[31:2] == dc_early_addr_i[31:2]);
    // cache-spec 2.2/5.2: replicas always read independently of main-array traffic.
    assign early_read_w = dc_early_valid_i;
    // Equality chooses speculative data even when invalid; only hit grants its use.
    // Six LUT6 comparisons and one reduction precede the final way/source selection.
    (* keep = "true" *) wire [5:0] early_tag0_match_w;
    (* keep = "true" *) wire [5:0] early_tag1_match_w;
    genvar early_tag_part;
    generate
        for (early_tag_part = 0; early_tag_part < 6;
            early_tag_part = early_tag_part + 1) begin : g_early_tag_match
            assign early_tag0_match_w[early_tag_part] =
                early_tag0_w[early_tag_part*3 +: 3] == early_tag_r[early_tag_part*3 +: 3];
            assign early_tag1_match_w[early_tag_part] =
                early_tag1_w[early_tag_part*3 +: 3] == early_tag_r[early_tag_part*3 +: 3];
        end
    endgenerate
    assign early_hit0_w = &early_tag0_match_w;
    assign early_hit1_w = &early_tag1_match_w;
    assign early_hit_enable_w = early_valid_r && !maintenance_r && !maintenance_start_w &&
        !(buffer_valid_r && buffer_addr_r[31:2] == early_addr_r[31:2]) &&
        !(store_pending_r && store_addr_r[31:2] == early_addr_r[31:2]) &&
        !(lookup_valid_r && store_r && addr_r[31:2] == early_addr_r[31:2]);
    assign dc_early_way_hit_o = {2{early_hit_enable_w}} &
        {early_tag1_w[18] && early_hit1_w, early_tag0_w[18] && early_hit0_w};
    // One-hot byte positions are prepared before the synchronous RAM edge.
    // Align both ways independently; tag comparison never selects these data.
    function [31:0] shifted_word;
        input [63:0] data_i;
        input [7:0] select_i;
        input [3:0] mask_i;
        integer offset;
        integer byte_number;
        begin
            shifted_word = 0;
            for (offset = 0; offset < 8; offset = offset + 1) begin
                for (byte_number = 0; byte_number < 4;
                    byte_number = byte_number + 1) begin
                    if ((offset%4 + byte_number) < 4)
                        shifted_word[byte_number*8 +: 8] =
                            shifted_word[byte_number*8 +: 8] |
                            ({8{select_i[offset] && mask_i[byte_number]}} &
                                data_i[(offset+byte_number)*8 +: 8]);
                end
            end
        end
    endfunction
    assign early_shift0_w = shifted_word(early_data0_w, early_byte_select_r, 4'hf);
    assign early_shift1_w = shifted_word(early_data1_w, early_byte_select_r, 4'hf);
    assign dc_early_way_data_o = {early_shift1_w, early_shift0_w};
    assign early_promote_w = accept_w && dc_req_early_i && !dc_req_store_i &&
        (|dc_early_way_hit_o) &&
        dc_req_addr_i == early_addr_r;
    assign lookup_accept_w = accept_w && !early_promote_w;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            early_valid_r <= 0;
            early_response_r <= 0;
        end else begin
            early_valid_r <= dc_early_valid_i && early_cacheable_w && !early_conflict_w &&
                !maintenance_r && !maintenance_start_w;
            early_response_r <= early_promote_w;
        end
    end
    always @(posedge clk_i) begin
        if (early_read_w) begin
            early_addr_r <= dc_early_addr_i;
            early_tag_r <= dc_early_addr_i[31:14];
            early_byte_select_r <= 8'b1 << dc_early_addr_i[2:0];
        end
        // early_response_r owns the payload. Capture continuously so tag hit
        // and request acceptance do not drive the 64-bit response clock enable.
        early_response_data_r <= dc_early_way_data_o;
        // Promotion already requires early-hit eligibility. Its registered
        // valid qualifies this raw tag match, so eligibility need not gate data.
        early_response_way_r <= {early_tag1_w[18] && early_hit1_w,
            early_tag0_w[18] && early_hit0_w};
        if (lookup_accept_w)
            lookup_byte_select_r <= 8'b1 << dc_req_addr_i[2:0];
    end
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
    localparam [3:0] S_MSEG = 4'd10;
    localparam [3:0] S_REPLAY = 4'd11;
    localparam [3:0] S_MWAIT = 4'd12;
    localparam [3:0] S_MINIT = 4'd13;
    localparam [3:0] S_MPREP = 4'd14;
    localparam [3:0] S_RESET = 4'd15;
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
    reg lookup_valid_r;
    reg lookup_hit_enable_r;
    wire lookup_valid0_w;
    wire lookup_valid1_w;
    reg [17:0] lookup_tag_r;
    reg [31:0] addr_r;
    reg store_r;
    reg [1:0] size_r;
    reg deferred_lookup_r;
    reg victim_r;
    reg [8:0] victim_idx_r;
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
    reg buffer_match_r;
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
    reg [17:0] maint_first_tag_r;
    reg [18:0] maint_last_tag_r;
    reg [18:0] maint_first_after_tag_r;
    reg [18:0] maint_last_before_tag_r;
    reg [14:0] maint_low_sum_r;
    reg [18:0] maint_upper_sum_r;
    reg [8:0] maint_first_idx_r;
    reg [8:0] maint_last_idx_r;
    reg [8:0] maint_next_idx_r;
    reg [9:0] maint_left_r;
    reg [8:0] scan_idx_r;
    reg [18:0] scan_first_tag_r;
    reg [18:0] scan_last_tag_r;
    wire [1:0] scan_dirty_w;
    wire [1:0] scan_valid_w;
    reg [1:0] maint_pending_r;
    reg scan_prefetched_r;
    reg [17:0] maint_tag1_r;
    reg [4:0] segment_r;
    reg [15:0] segment_mask_r;
    wire lookup_dirty0_w;
    wire lookup_dirty1_w;
    wire lookup_lru_w;
    wire [31:0] lookup_lru_bank_r;
    reg fence_done_r;
    wire cacheable_w;
    wire device_w;
    wire pma_err_w;
    wire accept_w;
    wire request_cacheable_w;
    wire request_device_w;
    wire request_pma_err_w;
    wire device_accept_w;
    (* keep = "true" *) wire [5:0] tag0_match_w;
    (* keep = "true" *) wire [5:0] tag1_match_w;
    wire hit0_w;
    wire hit1_w;
    wire hit_w;
    wire lookup_done_w;
    wire pma_result_w;
    wire return_store_w;
    wire store_result_w;
    wire buffer_push_w;
    wire [31:0] push_addr_w;
    wire [31:0] push_data_w;
    wire [31:0] lookup_store_data_w;
    wire [31:0] pending_store_data_w;
    wire [3:0] lookup_store_mask_w;
    wire [3:0] pending_store_mask_w;
    wire push_way_w;
    wire [3:0] push_mask_w;
    wire [63:0] buffer_data64_w;
    wire [7:0] buffer_mask64_w;
    wire fill_write_w;
    wire tag_write_w;
    wire [10:0] read_addr_w;
    wire ram_read_w;
    wire [10:0] write_addr_w;
    wire [63:0] write_data_w;
    wire [7:0] write_mask_w;
    wire [19:0] tag0_w;
    wire [19:0] tag1_w;
    wire [63:0] data0_w;
    wire [63:0] data1_w;
    wire [1:0] scan_match_w;
    wire [1:0] scan_writeback_w;
    wire [1:0] scan_invalidate_w;
    wire [6:0] maint_offset_sum_w;
    wire [9:0] maint_lines_w;
    wire scan_read_w;
    wire [8:0] scan_read_idx_w;
    reg [31:0] segment_dirty_r;
    reg [8:0] reset_idx_r;
    reg [1:0] lookup_drain_r;
    wire [1:0] tag_update_w;
    wire [8:0] tag_update_idx_w;
    wire [19:0] tag_update0_w;
    wire [19:0] tag_update1_w;
    wire metadata_fill_w;
    wire metadata_wb_w;
    reg [3:0] segment_index_w;
    integer segment_bit_w;
    wire maintenance_start_w;
    wire maintenance_array_start_w;
    wire device_bus_free_w;
    wire device_bus_active_w;
    wire [31:0] raw_return_w;
    reg [31:0] merged_return_w;
    wire [31:0] shifted_load0_w;
    wire [31:0] shifted_load1_w;
    wire [31:0] shifted_return_w;
    wire [31:0] nonlookup_data_w;
    wire [31:0] nonlookup_data1_w;
    wire lookup_data_select_w;
    wire [63:0] device_shifted_w;
    wire unused_axi_w;
    integer byte_idx_w;
    genvar tag_idx;
    genvar bank;
    reg [8:0] lookup_index_r;
    wire [31:0] lookup_bank_r;
    wire [15:0] lookup_slot_r;
    assign lookup_bank_r = 32'b1 << lookup_index_r[8:4];
    assign lookup_slot_r = 16'b1 << lookup_index_r[3:0];
    // cache-spec 2.2/5.2: metadata shares the synchronous tag read. Old-data
    // collisions need only a dirty bypass for the buffer draining on that edge.
    assign scan_valid_w = {tag1_w[19], tag0_w[19]};
    assign scan_dirty_w = {tag1_w[18], tag0_w[18]};
    assign lookup_valid0_w = tag0_w[19];
    assign lookup_valid1_w = tag1_w[19];
    assign lookup_dirty0_w = tag0_w[18] || lookup_drain_r[0];
    assign lookup_dirty1_w = tag1_w[18] || lookup_drain_r[1];
    assign lookup_lru_w = |(lookup_lru_bank_r & lookup_bank_r);
    assign device_shifted_w = axi_rdata_i >> {device_addr_r[2:0], 3'b0};
    assign unused_axi_w = &{1'b0, axi_rid_i, axi_bid_i, device_shifted_w[63:32],
                                buffer_addr_r[1:0], request_cacheable_w,
                                maint_offset_sum_w[4:0]};
    // C-F1 paths 2-4: prepare cached-hit eligibility with the E-stage address.
    // Request acceptance stays independent of this PMA classification (cpu-spec 3.3).
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
    // Six three-bit comparisons and one reduction; no data-way mux follows hit.
    generate
        for (tag_idx = 0; tag_idx < 6; tag_idx = tag_idx + 1) begin : g_tag_match
            assign tag0_match_w[tag_idx] =
                tag0_w[tag_idx*3 +: 3] == lookup_tag_r[tag_idx*3 +: 3];
            assign tag1_match_w[tag_idx] =
                tag1_w[tag_idx*3 +: 3] == lookup_tag_r[tag_idx*3 +: 3];
        end
    endgenerate
    always @(posedge clk_i) begin
        if (lookup_accept_w)
            lookup_tag_r <= dc_req_addr_i[31:14];
    end
    assign hit0_w = lookup_valid0_w && (&tag0_match_w);
    assign hit1_w = lookup_valid1_w && (&tag1_match_w);
    assign hit_w = hit0_w || hit1_w;
    // cache-spec 2.3/5.4: M-stage PMA errors return even while arrays are maintained.
    assign pma_result_w = lookup_valid_r && pma_err_w;
    assign lookup_done_w = pma_result_w || (lookup_hit_enable_r && hit_w);
    // Hit eligibility already owns IDLE and excludes maintenance/device requests.
    assign dc_req_ready_o = early_response_r || (lookup_hit_enable_r && hit_w) ||
        (device_state_r == D_IDLE && (maintenance_r ? !lookup_valid_r :
            (state_r == S_IDLE && (!lookup_valid_r || pma_result_w))));
    assign accept_w = dc_req_valid_i && dc_req_ready_o;
    assign device_accept_w = lookup_valid_r && device_w;
    // PMA classification occurs after the E/M acceptance edge (cache-spec 5.3).
    assign dc_resp_device_o = device_state_r != D_IDLE || device_accept_w;
    assign dc_resp_valid_o = early_response_r ||
        (pma_result_w || (lookup_hit_enable_r && hit_w) ||
            (state_r == S_RETURN && !killed_r) || device_state_r == D_RETURN);
    // cache-spec 6: qualify errors with registered response state, never tag hit.
    assign dc_resp_err_o = device_state_r == D_RETURN ? device_err_r :
        (state_r == S_RETURN ? (!killed_r && fill_err_r) :
        pma_result_w);
    // RAM alignment runs in parallel with forwarding control and registered data.
    assign raw_return_w = addr_r[2] ? result_r[63:32] : result_r[31:0];
    wire [31:0] aligned_ram0_w;
    wire [31:0] aligned_ram1_w;
    wire [31:0] aligned_forward_w;
    wire [31:0] aligned_buffer_w;
    wire [3:0] aligned_forward_mask_w;
    wire [3:0] aligned_buffer_mask_w;
    wire [31:0] forwarded_data_w;
    wire [3:0] ram_mask_w;
    assign aligned_ram0_w = shifted_word(data0_w, lookup_byte_select_r, ram_mask_w);
    assign aligned_ram1_w = shifted_word(data1_w, lookup_byte_select_r, ram_mask_w);
    assign aligned_forward_w = forward_data_r >> {addr_r[1:0], 3'b0};
    assign aligned_buffer_w = buffer_data_r >> {addr_r[1:0], 3'b0};
    assign aligned_forward_mask_w = forward_mask_r >> addr_r[1:0];
    assign aligned_buffer_mask_w = (buffer_mask_r >> addr_r[1:0]) &
        {4{buffer_valid_r && buffer_match_r}};
    genvar forward_byte;
    generate
        for (forward_byte = 0; forward_byte < 4;
            forward_byte = forward_byte + 1) begin : g_forward_byte
            wire buffer_select_w;
            wire forward_select_w;
            assign buffer_select_w = aligned_buffer_mask_w[forward_byte];
            assign forward_select_w = aligned_forward_mask_w[forward_byte] && !buffer_select_w;
            assign ram_mask_w[forward_byte] = lookup_data_select_w &&
                !buffer_select_w && !forward_select_w;
            assign forwarded_data_w[forward_byte*8 +: 8] =
                ({8{lookup_data_select_w && buffer_select_w}} &
                    aligned_buffer_w[forward_byte*8 +: 8]) |
                ({8{lookup_data_select_w && forward_select_w}} &
                    aligned_forward_w[forward_byte*8 +: 8]);
        end
    endgenerate
    assign shifted_load0_w = aligned_ram0_w | forwarded_data_w;
    assign shifted_load1_w = aligned_ram1_w | forwarded_data_w;
    // Fill returns are FF-originated and do not consume the DRM timing budget.
    always @(*) begin
        merged_return_w = raw_return_w;
        for (byte_idx_w = 0; byte_idx_w < 4; byte_idx_w = byte_idx_w + 1) begin
            if (forward_mask_r[byte_idx_w])
                merged_return_w[byte_idx_w*8 +: 8] = forward_data_r[byte_idx_w*8 +: 8];
            if (buffer_valid_r && buffer_addr_r[31:2] == addr_r[31:2] &&
                buffer_mask_r[byte_idx_w])
                merged_return_w[byte_idx_w*8 +: 8] = buffer_data_r[byte_idx_w*8 +: 8];
        end
    end
    assign shifted_return_w = merged_return_w >> {addr_r[1:0], 3'b0};
    // cpu-spec 4.9: select slow responses independently of tag RAM output.
    // The final cached-way selection and response gating fit one LUT6 per bit.
    assign lookup_data_select_w = !early_response_r &&
        device_state_r != D_RETURN && state_r != S_RETURN;
    assign nonlookup_data_w =
        ({32{early_response_r}} & early_response_data_r[31:0]) |
        ({32{!early_response_r && device_state_r == D_RETURN}} & device_result_r) |
        ({32{!early_response_r && device_state_r != D_RETURN && state_r == S_RETURN}} &
            shifted_return_w);
    assign nonlookup_data1_w = {32{early_response_r}} & early_response_data_r[63:32];
    assign dc_resp_way_data_o = {
        nonlookup_data1_w | shifted_load1_w,
        nonlookup_data_w | shifted_load0_w};
    assign dc_resp_way_hit_o = early_response_r ? early_response_way_r :
        device_state_r == D_RETURN || state_r == S_RETURN || pma_result_w ? 2'b01 :
        {2{lookup_hit_enable_r}} & {hit1_w, hit0_w};
    assign return_store_w = state_r == S_RETURN && store_r && !fill_err_r && !killed_r;
    assign store_result_w = (state_r == S_IDLE && lookup_done_w && !pma_err_w && store_r) ||
                            return_store_w;
    assign buffer_push_w = dc_commit_i && device_state_r == D_IDLE &&
                            (store_pending_r || store_result_w);
    assign push_addr_w = store_pending_r ? store_addr_r : addr_r;
    assign push_way_w = store_pending_r ? store_way_r :
        (return_store_w ? victim_r : hit1_w);
    // Byte placement precedes the current-hit/pending-store selection, keeping
    // tag comparison out of the barrel shifter and size decoder.
    assign lookup_store_data_w = dc_store_data_i << {addr_r[1:0], 3'b0};
    assign pending_store_data_w = dc_store_data_i << {store_addr_r[1:0], 3'b0};
    assign lookup_store_mask_w = (size_r == 0 ? 4'b0001 :
        size_r == 1 ? 4'b0011 : 4'b1111) << addr_r[1:0];
    assign pending_store_mask_w = (store_size_r == 0 ? 4'b0001 :
        store_size_r == 1 ? 4'b0011 : 4'b1111) << store_addr_r[1:0];
    assign push_data_w = store_pending_r ? pending_store_data_w : lookup_store_data_w;
    assign push_mask_w = store_pending_r ? pending_store_mask_w : lookup_store_mask_w;
    assign buffer_data64_w = buffer_addr_r[2] ? {buffer_data_r, 32'b0} :
                                                                {32'b0, buffer_data_r};
    assign buffer_mask64_w = buffer_addr_r[2] ? {buffer_mask_r, 4'b0} :
                                                                {4'b0, buffer_mask_r};
    assign fill_write_w = state_r == S_FILL && axi_rvalid_i;
    assign tag_write_w = fill_write_w && axi_rlast_i && !fill_err_r && axi_rresp_i == 0;
    assign write_addr_w = buffer_valid_r ? buffer_addr_r[13:3] : {addr_r[13:5], beat_r};
    assign write_data_w = buffer_valid_r ? buffer_data64_w : axi_rdata_i;
    assign write_mask_w = buffer_valid_r ? buffer_mask64_w : 8'hff;
    assign read_addr_w = state_r == S_WB_READ ? {victim_idx_r, beat_r} :
        scan_read_w ? {scan_read_idx_w, 2'b0} :
        state_r == S_REPLAY ? addr_r[13:3] :
        dc_req_addr_i[13:3];
    assign ram_read_w = (lookup_accept_w && !maintenance_r && !maintenance_array_start_w &&
                        !request_device_w) || state_r == S_REPLAY ||
                        state_r == S_WB_READ || scan_read_w;
    // cache-spec 5.4: prefetch the next group while checking both current tags.
    // Tag RAM holds a prefetched group during writeback; only data RAM reads then.
    assign scan_read_w = state_r == S_MREAD ||
        (state_r == S_MCHECK && maint_cmd_r != 4 && maint_left_r != 0);
    assign scan_read_idx_w = maint_cmd_r == 4 ?
        {segment_r, segment_index_w} : maint_next_idx_r;
    // Saturate the line count before wide address arithmetic; upper size bits
    // already imply at least 512 groups. Endpoint addition has its own stage.
    assign maint_offset_sum_w = {2'b0, maint_addr_i[4:0]} +
        {2'b0, maint_size_i[4:0]} + 7'd31;
    assign maint_lines_w = {1'b0, maint_size_i[13:5]} + {8'b0, maint_offset_sum_w[6:5]};
    // Per-group inclusive tag bounds are ready with the synchronous RAM result.
    assign scan_match_w[0] = scan_valid_w[0] && (maint_cmd_r == 4 ||
        ({1'b0, tag0_w[17:0]} >= scan_first_tag_r && {1'b0, tag0_w[17:0]} <= scan_last_tag_r));
    assign scan_match_w[1] = scan_valid_w[1] && (maint_cmd_r == 4 ||
        ({1'b0, tag1_w[17:0]} >= scan_first_tag_r && {1'b0, tag1_w[17:0]} <= scan_last_tag_r));
    assign scan_writeback_w = scan_match_w & scan_dirty_w & {2{maint_cmd_r != 2}};
    assign scan_invalidate_w = scan_match_w & {2{maint_cmd_r == 2 || maint_cmd_r == 3}};
    always @(*) begin
        segment_index_w = 4'b0;
        for (segment_bit_w = 15; segment_bit_w >= 0; segment_bit_w = segment_bit_w - 1)
            if (segment_mask_r[segment_bit_w]) segment_index_w = segment_bit_w[3:0];
    end
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
    // C-F1 paths 2-4: FENCE and memory commit are mutually exclusive in M
    // (cpu-spec 4.3/4.7). A FENCE cannot push the store buffer on this edge.
    assign dc_fence_done_o = fence_done_r || (dc_fence_i && !buffer_valid_r);
    // cache-spec v0.3, 5.2: one HPM event for each accepted dirty-line AW.
    assign dc_wb_event_o = state_r == S_WB_AW && axi_awready_i;
    assign wb_err_o = state_r == S_WB_B && axi_bvalid_i && axi_bresp_i != 0;
    assign wb_err_addr_o = wb_addr_r;

    // Only the maintenance scan yields the shared bus to device transactions.
    assign device_bus_free_w = state_r == S_IDLE || state_r == S_MREAD ||
                                state_r == S_MCHECK || state_r == S_MSEG ||
                                state_r == S_MWAIT || state_r == S_MINIT || state_r == S_MPREP;
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
        .wr_en_i(tag_update_w[0]),
        .wr_addr_i(tag_update_idx_w),
        .wr_data_i(tag_update0_w),
        .rd_en_i(ram_read_w && state_r != S_WB_READ),
        .rd_addr_i(read_addr_w[10:2]),
        .rd_data_o(tag0_w)
    );
    edrv32_ram_dcache_tag u_early_tag0 (
        .clk_i(clk_i),
        .wr_en_i(tag_update_w[0]),
        .wr_addr_i(tag_update_idx_w),
        .wr_data_i(tag_update0_w),
        .rd_en_i(early_read_w),
        .rd_addr_i(dc_early_addr_i[13:5]),
        .rd_data_o({early_tag0_w[18], unused_early_dirty_w[0], early_tag0_w[17:0]})
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
    edrv32_ram_dcache_data u_early_data0 (
        .clk_i(clk_i),
        .wr_en_i((buffer_valid_r && buffer_way_r == 1'b0) ||
                    (fill_write_w && victim_r == 1'b0)),
        .wr_addr_i(write_addr_w),
        .wr_data_i(write_data_w),
        .wr_byte_en_i(write_mask_w),
        .rd_en_i(early_read_w),
        .rd_addr_i(dc_early_addr_i[13:3]),
        .rd_data_o(early_data0_w)
    );
    edrv32_ram_dcache_tag u_tag1 (
        .clk_i(clk_i),
        .wr_en_i(tag_update_w[1]),
        .wr_addr_i(tag_update_idx_w),
        .wr_data_i(tag_update1_w),
        .rd_en_i(ram_read_w && state_r != S_WB_READ),
        .rd_addr_i(read_addr_w[10:2]),
        .rd_data_o(tag1_w)
    );
    edrv32_ram_dcache_tag u_early_tag1 (
        .clk_i(clk_i),
        .wr_en_i(tag_update_w[1]),
        .wr_addr_i(tag_update_idx_w),
        .wr_data_i(tag_update1_w),
        .rd_en_i(early_read_w),
        .rd_addr_i(dc_early_addr_i[13:5]),
        .rd_data_o({early_tag1_w[18], unused_early_dirty_w[1], early_tag1_w[17:0]})
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
    edrv32_ram_dcache_data u_early_data1 (
        .clk_i(clk_i),
        .wr_en_i((buffer_valid_r && buffer_way_r == 1'b1) ||
                    (fill_write_w && victim_r == 1'b1)),
        .wr_addr_i(write_addr_w),
        .wr_data_i(write_data_w),
        .wr_byte_en_i(write_mask_w),
        .rd_en_i(early_read_w),
        .rd_addr_i(dc_early_addr_i[13:3]),
        .rd_data_o(early_data1_w)
    );
    // Payload registers deliberately have no reset (cache-spec 5.5).
    always @(posedge clk_i) begin
        // Match the store entering the buffer against the request entering M.
        // A held lookup retains its address while the one-cycle buffer drains.
        buffer_match_r <= push_addr_w[31:2] ==
            (lookup_accept_w ? dc_req_addr_i[31:2] : addr_r[31:2]);
        if (ram_read_w) begin
            lookup_index_r <= read_addr_w[10:2];
        end
        if (lookup_accept_w) begin
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
        if (!store_pending_r) begin
            store_addr_r <= addr_r;
            store_size_r <= size_r;
            store_way_r <= return_store_w ? victim_r : hit1_w;
        end
        // The one-cycle buffer valid owns this payload; the previous entry
        // drains at this edge while the next registered owner is prepared.
        begin
            buffer_addr_r <= push_addr_w;
            buffer_way_r <= push_way_w;
            buffer_data_r <= push_data_w;
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
            wb_addr_r <= {lookup_lru_w ? tag1_w[17:0] : tag0_w[17:0], addr_r[13:5], 5'b0};
        end
        if (scan_read_w) begin
            scan_idx_r <= scan_read_idx_w;
            if (maint_cmd_r != 4) begin
                scan_first_tag_r <= maint_next_idx_r < maint_first_idx_r ?
                    maint_first_after_tag_r : {1'b0, maint_first_tag_r};
                scan_last_tag_r <= maint_next_idx_r > maint_last_idx_r ?
                    maint_last_before_tag_r : maint_last_tag_r;
            end
        end
        if (state_r == S_MCHECK && |scan_writeback_w) begin
            wb_addr_r <= {scan_writeback_w[0] ? tag0_w[17:0] : tag1_w[17:0], scan_idx_r, 5'b0};
            maint_tag1_r <= tag1_w[17:0];
        end
        if (state_r == S_WB_B && axi_bvalid_i && maintenance_r &&
            !victim_r && maint_pending_r[1])
            wb_addr_r <= {maint_tag1_r, victim_idx_r, 5'b0};
        if (maintenance_start_w) begin
            maint_cmd_r <= dc_clean_all_i ? 3'd4 : maint_cmd_i;
            maint_first_tag_r <= maint_addr_i[31:14];
            maint_first_after_tag_r <= {1'b0, maint_addr_i[31:14]} + 1'b1;
            maint_low_sum_r <= {1'b0, maint_addr_i[13:0]} + {1'b0, maint_size_i[13:0]};
            maint_upper_sum_r <= {1'b0, maint_addr_i[31:14]} + {1'b0, maint_size_i[31:14]};
            maint_first_idx_r <= maint_addr_i[13:5];
        end
        if (state_r == S_MPREP) maint_last_before_tag_r <= maint_last_tag_r - 1'b1;
        if (state_r == S_MINIT) begin
            maint_last_tag_r <= maint_upper_sum_r +
                (maint_low_sum_r > 16384 ? 19'd1 :
                    maint_low_sum_r == 0 ? 19'h7ffff : 19'd0);
            maint_last_idx_r <= maint_low_sum_r[13:5] -
                {8'b0, maint_low_sum_r[4:0] == 0};
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
            lookup_hit_enable_r <= 1'b0;
            deferred_lookup_r <= 1'b0;
        end else begin
            // This predicate belongs to the accepted lookup, before RAM outputs.
            if (state_r == S_IDLE)
                lookup_hit_enable_r <= 1'b0;
            if (state_r == S_REPLAY)
                lookup_hit_enable_r <= 1'b1;
            if (dc_kill_i)
                lookup_hit_enable_r <= 1'b0;
            if (lookup_accept_w) begin
                lookup_hit_enable_r <= !maintenance_r && !maintenance_array_start_w &&
                    !request_device_w && !request_pma_err_w;
                lookup_valid_r <= 1'b1;
                deferred_lookup_r <= maintenance_r || maintenance_array_start_w;
            end else if (device_accept_w || pma_result_w || dc_kill_i ||
                (state_r == S_IDLE && !maintenance_r && !deferred_lookup_r)) begin
                lookup_valid_r <= 1'b0;
            end
            if (state_r == S_REPLAY) deferred_lookup_r <= 1'b0;
        end
    end

    assign metadata_fill_w = state_r == S_FILL && axi_rvalid_i && axi_rlast_i;
    assign metadata_wb_w = state_r == S_WB_B && axi_bvalid_i;
    // cache-spec 5.2/5.4/5.5: one write per way. Buffer drain precedes miss
    // traffic; maintenance starts after it drains. Fill, B and MCHECK are
    // disjoint states. Invalidation of a replacement is merged into the final
    // fill write (including failed fills), while the blocking miss owns arrays.
    assign tag_update_idx_w = state_r == S_RESET ? reset_idx_r :
        buffer_valid_r ? buffer_addr_r[13:5] :
        metadata_fill_w ? addr_r[13:5] : metadata_wb_w ? victim_idx_r : scan_idx_r;
    assign tag_update_w[0] = state_r == S_RESET || (buffer_valid_r && !buffer_way_r) ||
        ((metadata_fill_w || metadata_wb_w) && !victim_r) ||
        (state_r == S_MCHECK && scan_invalidate_w[0] && !scan_writeback_w[0]);
    assign tag_update_w[1] = state_r == S_RESET || (buffer_valid_r && buffer_way_r) ||
        ((metadata_fill_w || metadata_wb_w) && victim_r) ||
        (state_r == S_MCHECK && scan_invalidate_w[1] && !scan_writeback_w[1]);
    assign tag_update0_w = state_r == S_RESET ? 20'b0 :
        buffer_valid_r ? {2'b11, buffer_addr_r[31:14]} :
        metadata_fill_w ? {tag_write_w, 1'b0, addr_r[31:14]} :
        metadata_wb_w ? {maintenance_r && maint_cmd_r != 3, 1'b0, wb_addr_r[31:14]} :
        {2'b00, tag0_w[17:0]};
    assign tag_update1_w = state_r == S_RESET ? 20'b0 :
        buffer_valid_r ? {2'b11, buffer_addr_r[31:14]} :
        metadata_fill_w ? {tag_write_w, 1'b0, addr_r[31:14]} :
        metadata_wb_w ? {maintenance_r && maint_cmd_r != 3, 1'b0, wb_addr_r[31:14]} :
        {2'b00, tag1_w[17:0]};
    always @(posedge clk_i) begin
        if (ram_read_w) begin
            lookup_drain_r[0] <= buffer_valid_r && !buffer_way_r &&
                buffer_addr_r[13:5] == read_addr_w[10:2];
            lookup_drain_r[1] <= buffer_valid_r && buffer_way_r &&
                buffer_addr_r[13:5] == read_addr_w[10:2];
        end
    end
    // cache-spec 2.2/5.4: conservative segment flags; range operations do not
    // clear them. The whole-clean walker owns arrays until its segment ends.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) segment_dirty_r <= 32'b0;
        else begin
            if (buffer_valid_r) segment_dirty_r[buffer_addr_r[13:9]] <= 1'b1;
            if (state_r == S_MWAIT && maint_cmd_r == 4 && maint_pending_r == 0 &&
                (segment_mask_r & ~(16'b1 << scan_idx_r[3:0])) == 0)
                segment_dirty_r[segment_r] <= 1'b0;
        end
    end
    // Registered hit packets update LRU one edge later. Copies keep each
    // 16-bit bank local; slot copies serve four banks and at most eight uses.
    wire [127:0] metadata_slot_w;
    wire [71:0] early_response_index_w;
    wire [7:0] early_response_copy_w;
    genvar metadata_group;
    generate
        for (metadata_group = 0; metadata_group < 8;
            metadata_group = metadata_group + 1) begin : g_metadata_slot
            (* keep = "true", syn_preserve = 1 *) reg [15:0] slot_copy1_r;
            (* keep = "true", syn_preserve = 1 *) reg early_response_copy1_r;
            (* keep = "true", syn_preserve = 1 *) reg [8:0] early_response_index_copy1_r;
            assign metadata_slot_w[metadata_group*16 +: 16] = slot_copy1_r;
            assign early_response_copy_w[metadata_group] = early_response_copy1_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i)
                    early_response_copy1_r <= 0;
                else
                    early_response_copy1_r <= early_promote_w;
            end
            assign early_response_index_w[metadata_group*9 +: 9] = early_response_index_copy1_r;
            always @(posedge clk_i) begin
                slot_copy1_r <= lookup_slot_r;
                early_response_index_copy1_r <= dc_req_addr_i[13:5];
            end
        end
        for (bank = 0; bank < 32; bank = bank + 1) begin : g_metadata
            reg [15:0] lru_bank_r;
            reg [15:0] lookup_lru_data_r;
            reg metadata_valid_r;
            reg metadata_bank_r;
            (* keep = "true", syn_preserve = 1 *) reg [1:0] hit_copy1_r;
            (* keep = "true", syn_preserve = 1 *) reg way_copy1_r;
            (* keep = "true", syn_preserve = 1 *) reg early_way_copy1_r;
            wire [15:0] metadata_slot_w_local;
            wire [8:0] early_index_w;
            wire [15:0] normal_mask_w;
            wire [15:0] early_mask_w;
            wire normal_update_w;
            wire early_update_w;
            wire rst_dlru_n_w;
            assign metadata_slot_w_local = metadata_slot_w[(bank/4)*16 +: 16];
            assign early_index_w = early_response_index_w[(bank/4)*9 +: 9];
            assign normal_update_w = metadata_valid_r && metadata_bank_r && (|hit_copy1_r);
            assign early_update_w = early_response_copy_w[bank/4] &&
                early_index_w[8:4] == bank[4:0];
            assign normal_mask_w = metadata_slot_w_local & {16{normal_update_w}};
            assign early_mask_w = (16'b1 << early_index_w[3:0]) &
                {16{early_update_w}};
            assign lookup_lru_bank_r[bank] = |(lookup_lru_data_r & lookup_slot_r);
            assign rst_dlru_n_w = rst_sys_dlru_n_i[bank/16];
            always @(posedge clk_i) begin
                // Raw compare results enter FFs before bank writes or forwarding.
                hit_copy1_r <= {hit1_w, hit0_w};
                way_copy1_r <= hit0_w;
                early_way_copy1_r <= early_tag0_w[18] && early_hit0_w;
                metadata_bank_r <= lookup_bank_r[bank];
                // Capture all slot values; the registered raw index selects next cycle.
                // Forward both pending metadata writes without this cycle's E address.
                lookup_lru_data_r <= (lru_bank_r & ~normal_mask_w & ~early_mask_w) |
                    (normal_mask_w & {16{way_copy1_r}} & ~early_mask_w) |
                    (early_mask_w & {16{early_way_copy1_r}});
            end
            always @(posedge clk_i or negedge rst_dlru_n_w) begin
                if (!rst_dlru_n_w) begin
                    metadata_valid_r <= 0;
                    lru_bank_r <= 0;
                end else begin
                    metadata_valid_r <= state_r == S_IDLE && lookup_hit_enable_r;
                    if (tag_write_w && lookup_bank_r[bank])
                        lru_bank_r <= (lru_bank_r & ~lookup_slot_r) |
                            (lookup_slot_r & {16{!victim_r}});
                    else
                        // An early-promoted request is younger than pending normal metadata.
                        lru_bank_r <= (lru_bank_r & ~normal_mask_w & ~early_mask_w) |
                            (normal_mask_w & {16{way_copy1_r}} & ~early_mask_w) |
                            (early_mask_w & {16{early_way_copy1_r}});
                end
            end
        end
    endgenerate

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_RESET;
            reset_idx_r <= 9'b0;
            victim_r <= 1'b0;
            victim_idx_r <= 9'b0;
            killed_r <= 1'b0;
            fill_err_r <= 1'b0;
            beat_r <= 2'b0;
            maintenance_r <= 1'b0;
            fence_clean_r <= 1'b0;
            clean_seen_r <= 1'b0;
            maint_next_idx_r <= 9'b0;
            maint_left_r <= 10'b0;
            segment_r <= 5'b0;
            segment_mask_r <= 16'b0;
            maint_pending_r <= 2'b0;
            scan_prefetched_r <= 1'b0;
            fence_done_r <= 1'b0;
        end else begin
            fence_done_r <= 1'b0;
            if (!dc_clean_all_i) clean_seen_r <= 1'b0;
            if (maintenance_start_w && dc_clean_all_i) clean_seen_r <= 1'b1;
            if (dc_kill_i && !maintenance_r && state_r != S_IDLE) killed_r <= 1'b1;
            case (state_r)
                // cache-spec 5.5: exactly 512 writes after reset release.
                S_RESET: begin
                    reset_idx_r <= reset_idx_r + 1'b1;
                    if (reset_idx_r == 511) state_r <= S_IDLE;
                end
                S_IDLE: begin
                    if (lookup_valid_r && !deferred_lookup_r && !device_w && !pma_err_w) begin
                        if (!hit_w) begin
                            victim_r <= lookup_lru_w;
                            victim_idx_r <= addr_r[13:5];
                            killed_r <= dc_kill_i;
                            fill_err_r <= 1'b0;
                            beat_r <= 2'b0;
                            state_r <= S_AR;
                            if ((lookup_lru_w ? lookup_dirty1_w : lookup_dirty0_w) ||
                                (buffer_valid_r && buffer_addr_r[13:5] == addr_r[13:5] &&
                                    buffer_way_r == lookup_lru_w)) begin
                                state_r <= S_WB_AW;
                            end
                        end
                    end
                    if (lookup_valid_r && deferred_lookup_r && cacheable_w && !dc_kill_i)
                        state_r <= S_REPLAY;
                    if (maintenance_start_w) begin
                        maintenance_r <= 1'b1;
                        fence_clean_r <= dc_clean_all_i;
                        maint_next_idx_r <= maint_addr_i[13:5];
                        maint_left_r <= |maint_size_i[31:14] || maint_lines_w[9] ?
                            10'd512 : maint_lines_w;
                        segment_r <= 5'b0;
                        state_r <= dc_clean_all_i || maint_cmd_i == 4 ? S_MSEG : S_MINIT;
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
                    beat_r <= 2'b0;
                    state_r <= maintenance_r ? S_MWAIT : S_AR;
                    if (maintenance_r) begin
                        maint_pending_r[victim_r] <= 1'b0;
                        if (!victim_r && maint_pending_r[1]) victim_r <= 1'b1;
                    end
                end
                S_MINIT: state_r <= S_MPREP;
                S_MPREP: state_r <= S_MREAD;
                S_MREAD: begin
                    state_r <= S_MCHECK;
                    if (maint_cmd_r != 4) begin
                        maint_next_idx_r <= maint_next_idx_r + 1'b1;
                        maint_left_r <= maint_left_r - 1'b1;
                    end
                end
                S_MCHECK: begin
                    scan_prefetched_r <= scan_read_w;
                    if (scan_read_w) begin
                        maint_next_idx_r <= maint_next_idx_r + 1'b1;
                        maint_left_r <= maint_left_r - 1'b1;
                    end
                    if (|scan_writeback_w) begin
                        maint_pending_r <= scan_writeback_w;
                        victim_r <= !scan_writeback_w[0];
                        victim_idx_r <= scan_idx_r;
                        state_r <= S_MWAIT;
                    end else if (maint_cmd_r == 4) begin
                        state_r <= S_MWAIT;
                        maint_pending_r <= 2'b0;
                    end else if (maint_left_r == 0) begin
                        maintenance_r <= 1'b0;
                        fence_done_r <= fence_clean_r;
                        state_r <= S_IDLE;
                    end
                end
                S_MWAIT: begin
                    if (|maint_pending_r) begin
                        // Device transactions already granted run to completion.
                        // D_BUS wins a simultaneous request; a granted writeback
                        // holds AXI ownership through B, so neither can starve.
                        if (!device_bus_active_w && device_state_r != D_BUS)
                            state_r <= S_WB_AW;
                    end else if (maint_cmd_r != 4) begin
                        if (scan_prefetched_r) state_r <= S_MCHECK;
                        else begin
                            maintenance_r <= 1'b0;
                            fence_done_r <= fence_clean_r;
                            state_r <= S_IDLE;
                        end
                    end else begin
                        segment_mask_r[scan_idx_r[3:0]] <= 1'b0;
                        if ((segment_mask_r & ~(16'b1 << scan_idx_r[3:0])) != 0)
                            state_r <= S_MREAD;
                        else if (segment_r != 31) begin
                            segment_r <= segment_r + 1'b1;
                            state_r <= S_MSEG;
                        end else begin
                            maintenance_r <= 1'b0;
                            fence_done_r <= fence_clean_r;
                            state_r <= S_IDLE;
                        end
                    end
                end
                S_MSEG: begin
                    segment_mask_r <= 16'hffff;
                    if (segment_dirty_r[segment_r]) state_r <= S_MREAD;
                    else if (segment_r != 31) segment_r <= segment_r + 1'b1;
                    else begin
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
