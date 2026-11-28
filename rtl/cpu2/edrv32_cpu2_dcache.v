// File: edrv32_cpu2_dcache.v
// Spec: cpu-v2-spec 3.7, 5.5, 6.4; cache-spec 2.3, 5.3, 5.4, 6.
// Description: Shared read port, two reserved response contexts and tagged store preparation.
// One write buffer and serialized maintenance/refill use synchronous RAM. Clock: clk_sys.
module edrv32_cpu2_dcache #(
    parameter [31:0] FPU_FORMAT = "NONE"
) (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // LSU request and prepared response.
    input wire dc_req_valid_i,
    output wire dc_req_ready_o,
    input wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] dc_req_tag_i,
    input wire dc_req_beat_i,
    input wire [31:0] dc_req_addr_i,
    input wire dc_req_store_i,
    input wire [1:0] dc_req_size_i,
    input wire [31:0] dc_req_data_i,
    input wire [3:0] dc_req_mask_i,
    input wire dc_req_early_i,
    output wire dc_resp_valid_o,
    input wire dc_resp_ready_i,
    output wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] dc_resp_tag_o,
    output wire dc_resp_beat_o,
    output wire [1:0] dc_resp_way_hit_o,
    output wire [31:0] dc_resp_way0_data_o,
    output wire [31:0] dc_resp_way1_data_o,
    output wire dc_resp_error_o,
    output wire dc_resp_device_o,

    // Head authorization and final beat completion.
    input wire dc_commit_valid_i,
    output wire dc_commit_ready_o,
    input wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] dc_commit_tag_i,
    input wire dc_commit_beat_i,
    input wire [31:0] dc_commit_data_i,
    input wire [3:0] dc_commit_mask_i,
    output wire dc_done_valid_o,
    input wire dc_done_ready_i,
    output wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] dc_done_tag_o,
    output wire dc_done_beat_o,
    output wire dc_done_error_o,
    output wire [31:0] dc_done_data_o,

    // Shared-port early query.
    input wire dc_early_valid_i,
    input wire [31:0] dc_early_addr_i,
    input wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] dc_early_tag_i,
    output wire dc_early_resp_valid_o,
    output wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] dc_early_resp_tag_o,
    output wire [1:0] dc_early_hit_o,
    output wire [31:0] dc_early_way0_data_o,
    output wire [31:0] dc_early_way1_data_o,

    // AXI64 read and write master.
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

    // Age cancellation and fences.
    input wire dc_cancel_valid_i,
    input wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] dc_cancel_tag_i,
    input wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] dc_age_head_i,
    input wire dc_fence_valid_i,
    output wire dc_fence_ready_o,
    input wire dc_fence_clean_all_i,
    output wire dc_fence_done_o,

    // Maintenance mailbox.
    input wire maint_req_valid_i,
    output wire maint_req_ready_o,
    input wire [2:0] maint_cmd_i,
    input wire [31:0] maint_addr_i,
    input wire [31:0] maint_size_i,
    output wire maint_busy_o,

    // Error and performance events.
    output wire wb_err_o,
    output wire [31:0] wb_err_addr_o,
    output wire dc_wb_event_o,
    output wire dc_miss_event_o,
    // I06: architectural store beat observation, no IP external ports.
    output wire trace_mem_effect_valid_o,
    output wire [(FPU_FORMAT=="FD" ? 4 : FPU_FORMAT=="F" ? 3 : 2)-1:0] trace_mem_effect_tag_o,
    output wire [31:0] trace_mem_effect_addr_o,
    output wire [31:0] trace_mem_effect_data_o,
    output wire [3:0] trace_mem_effect_mask_o,
    output wire debug_miss_o
);
    /* verilator lint_off UNUSEDPARAM */
    `include "edrv32_soc_map.vh"
    /* verilator lint_on UNUSEDPARAM */
    localparam T = FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2;
    localparam N = 1 << T;
    localparam ROM_BITS = $clog2(EDRV32_ROM_SIZE);
    localparam SRAM_BITS = $clog2(EDRV32_SRAM_SIZE);
    localparam CLINT_BITS = $clog2(EDRV32_CLINT_SIZE);
    localparam PLIC_BITS = $clog2(EDRV32_PLIC_SIZE);
    localparam SYS_BITS = $clog2(EDRV32_SYS_APB_SIZE);
    localparam MEDIA_BITS = $clog2(EDRV32_MEDIA_APB_SIZE);
    localparam DDR_BITS = $clog2(EDRV32_DDR_SIZE);
    localparam ALIAS_BITS = $clog2(EDRV32_DDR_UNCACHED_SIZE);
    localparam [3:0] S_IDLE = 4'd0;
    localparam [3:0] S_WB_AR = 4'd1;
    localparam [3:0] S_WB_READ = 4'd2;
    localparam [3:0] S_WB_DATA = 4'd3;
    localparam [3:0] S_WB_B = 4'd4;
    localparam [3:0] S_FILL_AR = 4'd5;
    localparam [3:0] S_FILL = 4'd6;
    localparam [2:0] M_IDLE = 3'd0;
    localparam [2:0] M_START = 3'd1;
    localparam [2:0] M_READ = 3'd2;
    localparam [2:0] M_CHECK = 3'd3;
    localparam [2:0] M_WAY1 = 3'd4;
    localparam [2:0] M_WAIT = 3'd5;
    localparam [2:0] M_NEXT = 3'd6;
    localparam [2:0] D_IDLE = 3'd0;
    localparam [2:0] D_READ_AR = 3'd1;
    localparam [2:0] D_READ = 3'd2;
    localparam [2:0] D_WRITE = 3'd3;
    localparam [2:0] D_B = 3'd4;
    reg [3:0] state_r;
    reg [2:0] maint_state_r;
    reg [2:0] device_state_r;
    reg scan_r;
    reg [8:0] scan_idx_r;
    reg [1:0] valid_r;
    reg [1:0] resolved_r;
    reg [1:0] canceled_r;
    reg head_r;
    reg tail_r;
    reg [1:0] count_r;
    reg [31:0] addr_r [0:1];
    reg [T-1:0] tag_r [0:1];
    reg [1:0] beat_r;
    reg [1:0] store_r;
    reg [1:0] size_r [0:1];
    reg [31:0] result0_r [0:1];
    reg [31:0] result1_r [0:1];
    reg [1:0] result_hit_r [0:1];
    reg [1:0] result_error_r;
    reg [1:0] result_device_r;
    reg pipe_valid_r;
    reg pipe_slot_r;
    reg pipe_array_r;
    reg pipe_early_r;
    reg pipe_cached_r;
    reg pipe_device_r;
    reg pipe_error_r;
    reg [31:0] pipe_addr_r;
    reg [T-1:0] pipe_tag_r;
    reg pipe_beat_r;
    reg pipe_store_r;
    reg [1:0] pipe_size_r;
    reg [31:0] pipe_early0_r;
    reg [31:0] pipe_early1_r;
    reg [1:0] pipe_early_hit_r;
    reg [2*N-1:0] pending_valid_r;
    reg [31:0] pending_addr_r [0:2*N-1];
    reg pending_store_r [0:2*N-1];
    reg pending_device_r [0:2*N-1];
    reg [1:0] pending_size_r [0:2*N-1];
    reg pending_way_r [0:2*N-1];
    reg buffer_valid_r;
    reg [31:0] buffer_addr_r;
    reg buffer_way_r;
    reg [31:0] buffer_data_r;
    reg [3:0] buffer_mask_r;
    reg pipe_buffer_valid_r;
    reg [31:0] pipe_buffer_addr_r;
    reg pipe_buffer_way_r;
    reg [31:0] pipe_buffer_data_r;
    reg [3:0] pipe_buffer_mask_r;
    reg early_valid_r;
    reg early_grant_r;
    reg [31:0] early_addr_r;
    reg [T-1:0] early_tag_r;
    reg early_cached_r;
    reg [31:0] miss_addr_r;
    reg miss_slot_r;
    reg victim_r;
    reg [1:0] bus_beat_r;
    reg fill_error_r;
    reg wb_maint_r;
    reg [31:0] wb_addr_r;
    reg [31:0] segment_dirty_r;
    reg [2:0] maint_cmd_r;
    reg [32:0] maint_start_r;
    reg [32:0] maint_end_r;
    reg [8:0] maint_idx_r;
    reg [9:0] maint_left_r;
    reg maint_fence_r;
    reg maint_way_r;
    reg [19:0] maint_tag1_r;
    reg fence_done_r;
    reg wb_err_r;
    reg [31:0] wb_err_addr_r;
    reg lru_valid_r;
    reg [8:0] lru_set_r;
    reg lru_data_r;
    reg done_valid_r;
    reg [T-1:0] done_tag_r;
    reg done_beat_r;
    reg done_error_r;
    reg [31:0] done_data_r;
    reg [T:0] device_index_r;
    reg [31:0] device_addr_r;
    reg [1:0] device_size_r;
    reg [31:0] device_data_r;
    reg [3:0] device_mask_r;
    reg device_aw_r;
    reg device_w_r;
    wire accept_w;
    wire pop_w;
    wire replay_w;
    wire query_w;
    wire read_array_w;
    wire [31:0] query_addr_w;
    wire query_store_w;
    wire [1:0] query_size_w;
    wire query_cached_w;
    wire query_device_w;
    wire query_error_w;
    wire query_rom_w;
    wire query_device_region_w;
    wire promote_w;
    wire array_free_w;
    wire early_read_w;
    wire [2*N-1:0] early_conflict_w;
    wire [1:0] early_hit_w;
    wire [1:0] hit_w;
    wire pipe_use_w;
    wire pipe_resolved_w;
    wire pipe_miss_w;
    wire response_pipe_w;
    wire [31:0] response0_w;
    wire [31:0] response1_w;
    wire [19:0] tag0_w;
    wire [19:0] tag1_w;
    wire [63:0] data0_w;
    wire [63:0] data1_w;
    wire [19:0] tag_way_w [0:1];
    wire [63:0] data_way_w [0:1];
    wire lru_w;
    wire [63:0] selected_data_w;
    wire [31:0] raw0_w;
    wire [31:0] raw1_w;
    wire [31:0] merged0_w;
    wire [31:0] merged1_w;
    wire current_merge_w;
    wire [31:0] current_mask_w;
    wire [31:0] final0_w;
    wire [31:0] final1_w;
    wire [31:0] merge_mask_w;
    wire merge_w;
    wire replacement_w;
    wire victim_dirty_w;
    wire [T:0] pipe_index_w;
    wire [T:0] commit_index_w;
    wire commit_cached_w;
    wire commit_device_w;
    wire commit_fire_w;
    wire done_space_w;
    wire [T-1:0] pipe_age_w;
    wire [T-1:0] cancel_age_w;
    wire pipe_canceled_w;
    wire maint_accept_w;
    wire fence_accept_w;
    wire [32:0] range_end_w;
    wire [33:0] range_lines_w;
    wire maint_read_w;
    wire maint_match0_w;
    wire maint_match1_w;
    wire [31:0] maint_line0_w;
    wire [31:0] maint_line1_w;
    wire maint_clean_w;
    wire maint_inv_w;
    wire maint_clear0_w;
    wire maint_clear1_w;
    wire wb_finish_w;
    wire fill_last_w;
    wire [31:0] fill_word_w;
    wire [63:0] early_shift0_w;
    wire [63:0] early_shift1_w;
    wire [63:0] device_shift_w;
    wire read_enable_w;
    wire [8:0] read_set_w;
    wire [10:0] read_data_addr_w;
    wire [31:0] port_addr_w;
    wire data_write_w;
    wire [10:0] data_write_addr_w;
    wire [63:0] data_write_data_w;
    wire [7:0] data_write_mask_w;
    wire tag_fill_w;
    wire tag_replace_w;
    wire unused_w;
    integer entry;

    assign tag0_w = tag_way_w[0];
    assign tag1_w = tag_way_w[1];
    assign data0_w = data_way_w[0];
    assign data1_w = data_way_w[1];
    assign array_free_w = !scan_r && state_r == S_IDLE && maint_state_r == M_IDLE &&
        device_state_r == D_IDLE;
    assign dc_req_ready_o = !scan_r && count_r < 2 && state_r == S_IDLE &&
        (!valid_r[head_r] || pipe_valid_r || resolved_r[head_r]);
    assign accept_w = dc_req_valid_i && dc_req_ready_o;
    assign pop_w = dc_resp_valid_o && dc_resp_ready_i;
    assign replay_w = !pipe_valid_r && array_free_w && valid_r[head_r] &&
        !resolved_r[head_r];
    assign query_w = accept_w || replay_w;
    assign query_addr_w = replay_w ? addr_r[head_r] : dc_req_addr_i;
    assign query_store_w = replay_w ? store_r[head_r] : dc_req_store_i;
    assign query_size_w = replay_w ? size_r[head_r] : dc_req_size_i;
    assign query_rom_w = query_addr_w[31:ROM_BITS] == EDRV32_ROM_BASE[31:ROM_BITS];
    assign query_cached_w =
        query_addr_w[31:SRAM_BITS] == EDRV32_SRAM_BASE[31:SRAM_BITS] ||
        query_addr_w[31:DDR_BITS] == EDRV32_DDR_BASE[31:DDR_BITS];
    assign query_device_region_w =
        query_addr_w[31:CLINT_BITS] == EDRV32_CLINT_BASE[31:CLINT_BITS] ||
        query_addr_w[31:PLIC_BITS] == EDRV32_PLIC_BASE[31:PLIC_BITS] ||
        query_addr_w[31:SYS_BITS] == EDRV32_SYS_APB_BASE[31:SYS_BITS] ||
        query_addr_w[31:MEDIA_BITS] == EDRV32_MEDIA_APB_BASE[31:MEDIA_BITS] ||
        query_addr_w[31:ALIAS_BITS] == EDRV32_DDR_UNCACHED_BASE[31:ALIAS_BITS];
    assign query_device_w = query_device_region_w || (query_rom_w && !query_store_w);
    assign query_error_w = !(query_cached_w || query_device_w);
    assign promote_w = accept_w && dc_req_early_i && early_valid_r &&
        early_tag_r == dc_req_tag_i && |dc_early_hit_o;
    assign read_array_w = query_w && array_free_w && !promote_w;
    assign early_read_w = dc_early_valid_i && array_free_w && !read_array_w;
    assign port_addr_w = early_read_w ? dc_early_addr_i : query_addr_w;
    assign pipe_use_w = pipe_valid_r && !resolved_r[pipe_slot_r];
    assign hit_w = pipe_early_r ? pipe_early_hit_r :
        {tag1_w[19] && tag1_w[17:0] == pipe_addr_r[31:14],
        tag0_w[19] && tag0_w[17:0] == pipe_addr_r[31:14]};
    assign pipe_resolved_w = pipe_error_r || pipe_device_r ||
        (pipe_cached_r && pipe_array_r && |hit_w);
    assign pipe_miss_w = pipe_use_w && pipe_cached_r && pipe_array_r && !(|hit_w) &&
        state_r == S_IDLE && maint_state_r == M_IDLE &&
        device_state_r == D_IDLE && !commit_device_w;
    assign pipe_age_w = pipe_tag_r - dc_age_head_i;
    assign cancel_age_w = dc_cancel_tag_i - dc_age_head_i;
    assign pipe_canceled_w = canceled_r[pipe_slot_r] ||
        (dc_cancel_valid_i && pipe_age_w >= cancel_age_w);
    assign response_pipe_w = pipe_use_w && pipe_slot_r == head_r && pipe_resolved_w;
    assign dc_resp_valid_o = valid_r[head_r] && !canceled_r[head_r] &&
        (resolved_r[head_r] || response_pipe_w) &&
        (maint_state_r == M_IDLE || (response_pipe_w ? pipe_device_r || pipe_error_r :
        result_device_r[head_r] || result_error_r[head_r]));
    assign dc_resp_tag_o = tag_r[head_r];
    assign dc_resp_beat_o = beat_r[head_r];
    assign dc_resp_way_hit_o = response_pipe_w ?
        (pipe_device_r || pipe_error_r ? 2'b01 : hit_w) : result_hit_r[head_r];
    assign dc_resp_way0_data_o = response_pipe_w ? response0_w : result0_r[head_r];
    assign dc_resp_way1_data_o = response_pipe_w ? response1_w : result1_r[head_r];
    assign dc_resp_error_o = dc_resp_valid_o &&
        (response_pipe_w ? pipe_error_r : result_error_r[head_r]);
    assign dc_resp_device_o = response_pipe_w ? pipe_device_r : result_device_r[head_r];
    assign raw0_w = pipe_addr_r[2] ? data0_w[63:32] : data0_w[31:0];
    assign raw1_w = pipe_addr_r[2] ? data1_w[63:32] : data1_w[31:0];
    assign merge_w = pipe_buffer_valid_r && pipe_buffer_addr_r[31:2] == pipe_addr_r[31:2];
    assign merge_mask_w = {{8{pipe_buffer_mask_r[3]}}, {8{pipe_buffer_mask_r[2]}},
                        {8{pipe_buffer_mask_r[1]}}, {8{pipe_buffer_mask_r[0]}}};
    assign merged0_w = merge_w ? (raw0_w & ~merge_mask_w) |
        (pipe_buffer_data_r & merge_mask_w) : raw0_w;
    assign merged1_w = merge_w ? (raw1_w & ~merge_mask_w) |
        (pipe_buffer_data_r & merge_mask_w) : raw1_w;
    assign current_merge_w = buffer_valid_r && buffer_addr_r[31:2] == pipe_addr_r[31:2];
    assign current_mask_w = {{8{buffer_mask_r[3]}}, {8{buffer_mask_r[2]}},
                            {8{buffer_mask_r[1]}}, {8{buffer_mask_r[0]}}};
    assign final0_w = current_merge_w ? (merged0_w & ~current_mask_w) |
        (buffer_data_r & current_mask_w) : merged0_w;
    assign final1_w = current_merge_w ? (merged1_w & ~current_mask_w) |
        (buffer_data_r & current_mask_w) : merged1_w;
    assign response0_w = pipe_early_r ? pipe_early0_r :
        final0_w >> {pipe_addr_r[1:0], 3'd0};
    assign response1_w = pipe_early_r ? pipe_early1_r :
        final1_w >> {pipe_addr_r[1:0], 3'd0};
    assign replacement_w = !tag0_w[19] ? 1'b0 : !tag1_w[19] ? 1'b1 : lru_w;
    assign victim_dirty_w = (replacement_w ? tag1_w[19:18] == 2'b11 :
        tag0_w[19:18] == 2'b11) || (pipe_buffer_valid_r &&
        pipe_buffer_addr_r[13:5] == pipe_addr_r[13:5] &&
        pipe_buffer_way_r == replacement_w) || (buffer_valid_r &&
        buffer_addr_r[13:5] == pipe_addr_r[13:5] && buffer_way_r == replacement_w) ||
        (commit_cached_w && pending_addr_r[commit_index_w][13:5] == pipe_addr_r[13:5] &&
        pending_way_r[commit_index_w] == replacement_w);
    assign pipe_index_w = {pipe_tag_r, pipe_beat_r};
    assign commit_index_w = {dc_commit_tag_i, dc_commit_beat_i};
    assign done_space_w = !done_valid_r || dc_done_ready_i;
    assign dc_commit_ready_o = !scan_r && done_space_w && device_state_r == D_IDLE &&
        state_r == S_IDLE && (pending_device_r[commit_index_w] || maint_state_r == M_IDLE);
    assign commit_fire_w = dc_commit_valid_i && dc_commit_ready_o;
    assign commit_cached_w = commit_fire_w && !pending_device_r[commit_index_w];
    assign commit_device_w = commit_fire_w && pending_device_r[commit_index_w];
    assign dc_done_valid_o = done_valid_r;
    assign dc_done_tag_o = done_tag_r;
    assign dc_done_beat_o = done_beat_r;
    assign dc_done_error_o = done_error_r;
    assign dc_done_data_o = done_data_r;
    assign dc_early_resp_valid_o = early_valid_r;
    assign dc_early_resp_tag_o = early_tag_r;
    assign early_hit_w = {tag1_w[19] && tag1_w[17:0] == early_addr_r[31:14],
                        tag0_w[19] && tag0_w[17:0] == early_addr_r[31:14]};
    assign dc_early_hit_o = early_grant_r && early_cached_r && array_free_w &&
        !maint_accept_w && !fence_accept_w &&
        !(buffer_valid_r && buffer_addr_r[31:2] == early_addr_r[31:2]) ? early_hit_w : 2'b00;
    assign early_shift0_w = data0_w >> {early_addr_r[2:0], 3'd0};
    assign dc_early_way0_data_o = early_shift0_w[31:0];
    assign early_shift1_w = data1_w >> {early_addr_r[2:0], 3'd0};
    assign dc_early_way1_data_o = early_shift1_w[31:0];
    assign device_shift_w = axi_rdata_i >> {device_addr_r[2:0], 3'd0};
    assign maint_req_ready_o = !scan_r && maint_state_r == M_IDLE;
    assign dc_fence_ready_o = maint_req_ready_o && !maint_req_valid_i;
    assign maint_accept_w = maint_req_valid_i && maint_req_ready_o;
    assign fence_accept_w = dc_fence_valid_i && dc_fence_ready_o;
    assign maint_busy_o = maint_state_r != M_IDLE;
    assign dc_fence_done_o = fence_done_r;
    assign range_end_w = {1'b0, maint_addr_i} + {1'b0, maint_size_i};
    assign range_lines_w = ({1'b0, range_end_w} + 34'd31) >> 5;
    assign maint_read_w = maint_state_r == M_READ && state_r == S_IDLE &&
        !buffer_valid_r && device_state_r == D_IDLE;
    assign maint_line0_w = {tag0_w[17:0], maint_idx_r, 5'd0};
    assign maint_line1_w = {tag1_w[17:0], maint_idx_r, 5'd0};
    assign maint_match0_w = tag0_w[19] && (maint_cmd_r == 4 ||
        ({1'b0, maint_line0_w} < maint_end_r &&
        {1'b0, maint_line0_w} + 33'd32 > maint_start_r));
    assign maint_match1_w = tag1_w[19] && (maint_cmd_r == 4 ||
        ({1'b0, maint_line1_w} < maint_end_r &&
        {1'b0, maint_line1_w} + 33'd32 > maint_start_r));
    assign maint_clean_w = maint_cmd_r != 2;
    assign maint_inv_w = maint_cmd_r == 2 || maint_cmd_r == 3;
    assign maint_clear0_w = maint_state_r == M_CHECK && state_r == S_IDLE &&
        maint_match0_w && !(maint_clean_w && tag0_w[18]);
    assign maint_clear1_w = maint_state_r == M_CHECK && state_r == S_IDLE &&
        maint_match1_w && !(maint_clean_w && tag1_w[18]);
    assign wb_finish_w = state_r == S_WB_B && axi_bvalid_i;
    assign fill_last_w = state_r == S_FILL && axi_rvalid_i && axi_rlast_i;
    assign fill_word_w = miss_addr_r[2] ? axi_rdata_i[63:32] : axi_rdata_i[31:0];
    assign read_enable_w = read_array_w || early_read_w || maint_read_w ||
        state_r == S_WB_READ;
    assign read_set_w = maint_read_w ? maint_idx_r :
        state_r == S_WB_READ ? wb_addr_r[13:5] : port_addr_w[13:5];
    assign read_data_addr_w = state_r == S_WB_READ ? {wb_addr_r[13:5], bus_beat_r} :
        port_addr_w[13:3];
    assign data_write_w = buffer_valid_r || (state_r == S_FILL && axi_rvalid_i);
    assign data_write_addr_w = buffer_valid_r ? buffer_addr_r[13:3] :
        {miss_addr_r[13:5], bus_beat_r};
    assign data_write_data_w = buffer_valid_r ?
        (buffer_addr_r[2] ? {buffer_data_r, 32'd0} : {32'd0, buffer_data_r}) : axi_rdata_i;
    assign data_write_mask_w = buffer_valid_r ?
        (buffer_addr_r[2] ? {buffer_mask_r, 4'd0} : {4'd0, buffer_mask_r}) : 8'hff;
    assign tag_fill_w = fill_last_w && !fill_error_r && axi_rresp_i == 0;
    assign tag_replace_w = state_r == S_FILL && axi_rvalid_i && bus_beat_r == 0;
    assign dc_wb_event_o = state_r == S_WB_AR && axi_awready_i;
    assign dc_miss_event_o = pipe_miss_w && !pipe_canceled_w;
    assign wb_err_o = wb_err_r;
    assign wb_err_addr_o = wb_err_addr_r;
    assign selected_data_w = victim_r ? data1_w : data0_w;
    assign axi_arid_o = 4'd0;
    assign axi_araddr_o = device_state_r == D_READ_AR ? device_addr_r :
        {miss_addr_r[31:5], 5'd0};
    assign axi_arlen_o = device_state_r == D_READ_AR ? 8'd0 : 8'd3;
    assign axi_arsize_o = device_state_r == D_READ_AR ? {1'b0, device_size_r} : 3'd3;
    assign axi_arburst_o = 2'b01;
    assign axi_arvalid_o = device_state_r == D_READ_AR || state_r == S_FILL_AR;
    assign axi_rready_o = device_state_r == D_READ ? done_space_w : state_r == S_FILL;
    assign axi_awid_o = 4'd0;
    assign axi_awaddr_o = device_state_r == D_WRITE ? device_addr_r : wb_addr_r;
    assign axi_awlen_o = device_state_r == D_WRITE ? 8'd0 : 8'd3;
    assign axi_awsize_o = device_state_r == D_WRITE ? {1'b0, device_size_r} : 3'd3;
    assign axi_awburst_o = 2'b01;
    assign axi_awvalid_o = device_state_r == D_WRITE ? !device_aw_r : state_r == S_WB_AR;
    assign axi_wdata_o = device_state_r == D_WRITE ?
        {32'd0, device_data_r} << {device_addr_r[2:0], 3'd0} : selected_data_w;
    assign axi_wstrb_o = device_state_r == D_WRITE ?
        {4'd0, device_mask_r} << device_addr_r[2:0] : 8'hff;
    assign axi_wlast_o = device_state_r == D_WRITE || bus_beat_r == 3;
    assign axi_wvalid_o = device_state_r == D_WRITE ? !device_w_r : state_r == S_WB_DATA;
    assign axi_bready_o = device_state_r == D_B ? done_space_w : state_r == S_WB_B;
    assign unused_w = ^{dc_req_data_i, dc_req_mask_i, axi_rid_i, axi_bid_i,
        miss_addr_r[1:0],
        pipe_buffer_addr_r[1:0], early_shift0_w[63:32], early_shift1_w[63:32],
        device_shift_w[63:32], port_addr_w[31:14], port_addr_w[2:0]};
    wire drop_w;
    wire release_w;
    wire [33:0] range_count_w;
    reg device_canceled_r;
    wire [T-1:0] device_age_w;
    wire device_cancel_w;
    assign device_age_w = device_index_r[T:1] - dc_age_head_i;
    assign device_cancel_w = device_canceled_r ||
        (dc_cancel_valid_i && device_age_w >= cancel_age_w);
    assign drop_w = valid_r[head_r] && canceled_r[head_r] && state_r == S_IDLE;
    assign release_w = pop_w || drop_w;
    assign range_count_w = range_lines_w - {7'd0, maint_addr_i[31:5]};
    genvar way;
    genvar record;
    generate
        for (record = 0; record < 2*N; record = record + 1) begin : g_conflict
            // Comparison leaves are independent; the reduction only qualifies an early hit.
            assign early_conflict_w[record] = pending_valid_r[record] &&
                pending_store_r[record] &&
                pending_addr_r[record][31:2] == dc_early_addr_i[31:2];
        end
        for (way = 0; way < 2; way = way + 1) begin : g_way
            localparam WAY = way != 0;
            wire tag_write_w;
            reg [8:0] tag_addr_w;
            reg [19:0] tag_data_w;
            wire clear_w;
            wire [19:0] read_tag_w;
            wire unused_tag_dirty_w;
            assign unused_tag_dirty_w = read_tag_w[18];
            assign read_tag_w = WAY ? tag1_w : tag0_w;
            assign clear_w = WAY ? maint_clear1_w : maint_clear0_w;
            assign tag_write_w = scan_r || (buffer_valid_r && buffer_way_r == WAY) ||
                ((tag_fill_w || tag_replace_w) && victim_r == WAY) || clear_w ||
                (wb_finish_w && wb_maint_r && victim_r == WAY);
            always @(*) begin
                tag_addr_w = miss_addr_r[13:5];
                tag_data_w = {tag_fill_w, 1'b0, miss_addr_r[31:14]};
                if (clear_w) begin
                    tag_addr_w = maint_idx_r;
                    tag_data_w = {read_tag_w[19] && !maint_inv_w, 1'b0, read_tag_w[17:0]};
                end
                if (wb_finish_w && wb_maint_r) begin
                    tag_addr_w = wb_addr_r[13:5];
                    tag_data_w = {!maint_inv_w, 1'b0, wb_addr_r[31:14]};
                end
                if (buffer_valid_r) begin
                    tag_addr_w = buffer_addr_r[13:5];
                    tag_data_w = {2'b11, buffer_addr_r[31:14]};
                end
                if (scan_r) begin
                    tag_addr_w = scan_idx_r;
                    tag_data_w = 20'd0;
                end
            end
            edrv32_ram_cpu2_cache_dtag u_tag (
                .clk_i(clk_i),
                .wr_en_i(tag_write_w),
                .wr_addr_i(tag_addr_w),
                .wr_data_i(tag_data_w),
                .rd_en_i(read_enable_w),
                .rd_addr_i(read_set_w),
                .rd_data_o(tag_way_w[way])
            );
            edrv32_ram_cpu2_cache_data64 u_data (
                .clk_i(clk_i),
                .wr_en_i(data_write_w &&
                    (buffer_valid_r ? buffer_way_r == WAY : victim_r == WAY)),
                .wr_addr_i(data_write_addr_w),
                .wr_data_i(data_write_data_w),
                .wr_mask_i(data_write_mask_w),
                .rd_en_i(read_enable_w),
                .rd_addr_i(read_data_addr_w),
                .rd_data_o(data_way_w[way])
            );
        end
    endgenerate
    edrv32_ram_cpu2_cache_lru u_lru (
        .clk_i(clk_i),
        .wr_en_i(scan_r || lru_valid_r),
        .wr_addr_i(scan_r ? scan_idx_r : lru_set_r),
        .wr_data_i(scan_r ? 1'b0 : lru_data_r),
        .rd_en_i(read_array_w),
        .rd_addr_i(query_addr_w[13:5]),
        .rd_data_o(lru_w)
    );

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            maint_state_r <= M_IDLE;
            device_state_r <= D_IDLE;
            scan_r <= 1'b1;
            scan_idx_r <= 9'd0;
            valid_r <= 2'd0;
            resolved_r <= 2'd0;
            canceled_r <= 2'd0;
            head_r <= 1'b0;
            tail_r <= 1'b0;
            count_r <= 2'd0;
            pipe_valid_r <= 1'b0;
            pending_valid_r <= 0;
            buffer_valid_r <= 1'b0;
            early_valid_r <= 1'b0;
            early_grant_r <= 1'b0;
            bus_beat_r <= 2'd0;
            fill_error_r <= 1'b0;
            segment_dirty_r <= 32'd0;
            fence_done_r <= 1'b0;
            wb_err_r <= 1'b0;
            done_valid_r <= 1'b0;
            device_aw_r <= 1'b0;
            device_w_r <= 1'b0;
            device_canceled_r <= 1'b0;
            lru_valid_r <= 1'b0;
        end else begin
            fence_done_r <= 1'b0;
            wb_err_r <= 1'b0;
            lru_valid_r <= 1'b0;
            pipe_valid_r <= query_w;
            early_valid_r <= dc_early_valid_i && !(dc_cancel_valid_i &&
                ((dc_early_tag_i - dc_age_head_i) >= cancel_age_w));
            early_grant_r <= early_read_w && !(|early_conflict_w) &&
                !(buffer_valid_r && buffer_addr_r[31:2] == dc_early_addr_i[31:2]);
            if (scan_r) begin
                scan_idx_r <= scan_idx_r + 9'd1;
                if (scan_idx_r == 511) scan_r <= 1'b0;
            end
            if (done_valid_r && dc_done_ready_i) done_valid_r <= 1'b0;
            // The preceding buffer entry drains on this edge; a new entry may replace it.
            buffer_valid_r <= commit_cached_w;
            if (buffer_valid_r) segment_dirty_r[buffer_addr_r[13:9]] <= 1'b1;
            if (release_w) begin
                valid_r[head_r] <= 1'b0;
                head_r <= !head_r;
            end
            if (accept_w) begin
                valid_r[tail_r] <= 1'b1;
                resolved_r[tail_r] <= 1'b0;
                canceled_r[tail_r] <= dc_cancel_valid_i &&
                    ((dc_req_tag_i - dc_age_head_i) >= cancel_age_w);
                tail_r <= !tail_r;
            end
            if (pipe_use_w && pipe_resolved_w) begin
                resolved_r[pipe_slot_r] <= 1'b1;
                if (!pipe_canceled_w && !pipe_error_r && (pipe_store_r || pipe_device_r))
                    pending_valid_r[pipe_index_w] <= 1'b1;
                lru_valid_r <= pipe_cached_r && |hit_w;
            end
            if (fill_last_w) begin
                resolved_r[miss_slot_r] <= 1'b1;
                if (!canceled_r[miss_slot_r] && store_r[miss_slot_r] &&
                    !(fill_error_r || |axi_rresp_i))
                    pending_valid_r[{tag_r[miss_slot_r], beat_r[miss_slot_r]}] <= 1'b1;
                lru_valid_r <= tag_fill_w;
            end
            if (commit_fire_w) pending_valid_r[commit_index_w] <= 1'b0;
            if (commit_cached_w) begin
                done_valid_r <= 1'b1;
                done_error_r <= 1'b0;
            end
            if (dc_cancel_valid_i) begin
                if (valid_r[0] && ((tag_r[0] - dc_age_head_i) >= cancel_age_w))
                    canceled_r[0] <= 1'b1;
                if (valid_r[1] && ((tag_r[1] - dc_age_head_i) >= cancel_age_w))
                    canceled_r[1] <= 1'b1;
                for (entry = 0; entry < 2*N; entry = entry + 1) begin
                    if (((entry[T:1] - dc_age_head_i) >= cancel_age_w))
                        pending_valid_r[entry] <= 1'b0;
                end
                if (done_valid_r && ((done_tag_r - dc_age_head_i) >= cancel_age_w))
                    done_valid_r <= 1'b0;
                if (device_state_r != D_IDLE && device_age_w >= cancel_age_w)
                    device_canceled_r <= 1'b1;
            end
            case ({accept_w, release_w})
                2'b10: count_r <= count_r + 2'd1;
                2'b01: count_r <= count_r - 2'd1;
                default: begin end
            endcase
            begin
                case (state_r)
                    S_IDLE: begin
                        if (pipe_miss_w && device_state_r == D_IDLE && !commit_device_w &&
                            !pipe_canceled_w) begin
                            state_r <= victim_dirty_w ? S_WB_AR : S_FILL_AR;
                            bus_beat_r <= 2'd0;
                            fill_error_r <= 1'b0;
                            wb_maint_r <= 1'b0;
                        end
                    end
                    S_WB_AR: if (axi_awready_i) state_r <= S_WB_READ;
                    S_WB_READ: state_r <= S_WB_DATA;
                    S_WB_DATA: begin
                        if (axi_wready_i) begin
                            bus_beat_r <= bus_beat_r + 2'd1;
                            state_r <= bus_beat_r == 3 ? S_WB_B : S_WB_READ;
                        end
                    end
                    S_WB_B: begin
                        if (axi_bvalid_i) begin
                            if (|axi_bresp_i) wb_err_r <= 1'b1;
                            if (wb_maint_r) begin
                                state_r <= S_IDLE;
                                maint_state_r <= maint_way_r ? M_NEXT : M_WAY1;
                            end else begin
                                state_r <= S_FILL_AR;
                                bus_beat_r <= 2'd0;
                            end
                        end
                    end
                    S_FILL_AR: if (axi_arready_i) state_r <= S_FILL;
                    S_FILL: begin
                        if (axi_rvalid_i) begin
                            fill_error_r <= fill_error_r || |axi_rresp_i;
                            bus_beat_r <= bus_beat_r + 2'd1;
                            if (axi_rlast_i) state_r <= S_IDLE;
                        end
                    end
                    default: begin end
                endcase
            end
            if (maint_accept_w || fence_accept_w) begin
                maint_state_r <= maint_accept_w && maint_cmd_i != 4 && maint_size_i == 0 ?
                    M_IDLE : M_START;
            end else begin
                case (maint_state_r)
                    M_START: begin
                        if (!buffer_valid_r && state_r == S_IDLE && !pipe_valid_r) begin
                            if (maint_cmd_r == 0 || maint_left_r == 0) begin
                                maint_state_r <= M_IDLE;
                                fence_done_r <= maint_fence_r;
                            end else maint_state_r <= M_READ;
                        end
                    end
                    M_READ: begin
                        if (maint_read_w && !commit_device_w) begin
                            if (maint_cmd_r == 4 && maint_idx_r[3:0] == 0 &&
                                !segment_dirty_r[maint_idx_r[8:4]]) begin
                                if (maint_left_r <= 16) begin
                                    maint_state_r <= M_IDLE;
                                    fence_done_r <= maint_fence_r;
                                end
                            end else maint_state_r <= M_CHECK;
                        end
                    end
                    M_CHECK: begin
                        if (state_r == S_IDLE && device_state_r == D_IDLE && !commit_device_w) begin
                            if (maint_match0_w && maint_clean_w && tag0_w[18]) begin
                                state_r <= S_WB_AR;
                                bus_beat_r <= 2'd0;
                                wb_maint_r <= 1'b1;
                                maint_way_r <= 1'b0;
                                maint_state_r <= M_WAIT;
                            end else if (maint_match1_w && maint_clean_w && tag1_w[18]) begin
                                state_r <= S_WB_AR;
                                bus_beat_r <= 2'd0;
                                wb_maint_r <= 1'b1;
                                maint_way_r <= 1'b1;
                                maint_state_r <= M_WAIT;
                            end else maint_state_r <= M_NEXT;
                        end
                    end
                    M_WAY1: begin
                        if (device_state_r == D_IDLE && !commit_device_w) begin
                            if (maint_tag1_r[19:18] == 2'b11 && maint_clean_w &&
                                (maint_cmd_r == 4 ||
                                ({1'b0, maint_tag1_r[17:0], maint_idx_r, 5'd0} < maint_end_r &&
                                {1'b0, maint_tag1_r[17:0], maint_idx_r, 5'd0} + 33'd32 >
                                maint_start_r))) begin
                                state_r <= S_WB_AR;
                                bus_beat_r <= 2'd0;
                                wb_maint_r <= 1'b1;
                                maint_way_r <= 1'b1;
                                maint_state_r <= M_WAIT;
                            end else maint_state_r <= M_NEXT;
                        end
                    end
                    M_NEXT: begin
                        if (maint_cmd_r == 4 && maint_idx_r[3:0] == 15)
                            segment_dirty_r[maint_idx_r[8:4]] <= 1'b0;
                        if (maint_left_r == 1) begin
                            maint_state_r <= M_IDLE;
                            fence_done_r <= maint_fence_r;
                        end else maint_state_r <= M_READ;
                    end
                    default: begin end
                endcase
            end
            if (commit_device_w) begin
                device_state_r <= pending_store_r[commit_index_w] ? D_WRITE : D_READ_AR;
                device_aw_r <= 1'b0;
                device_w_r <= 1'b0;
                device_canceled_r <= 1'b0;
            end else begin
                case (device_state_r)
                    D_READ_AR: if (axi_arready_i) device_state_r <= D_READ;
                    D_READ: begin
                        if (axi_rvalid_i && done_space_w) begin
                            done_valid_r <= !device_cancel_w;
                            done_error_r <= |axi_rresp_i;
                            device_state_r <= D_IDLE;
                        end
                    end
                    D_WRITE: begin
                        if (axi_awready_i) device_aw_r <= 1'b1;
                        if (axi_wready_i) device_w_r <= 1'b1;
                        if ((device_aw_r || axi_awready_i) && (device_w_r || axi_wready_i))
                            device_state_r <= D_B;
                    end
                    D_B: begin
                        if (axi_bvalid_i && done_space_w) begin
                            done_valid_r <= !device_cancel_w;
                            done_error_r <= |axi_bresp_i;
                            device_state_r <= D_IDLE;
                        end
                    end
                    default: begin end
                endcase
            end
        end
    end
    always @(posedge clk_i) begin
        if (accept_w) begin
            addr_r[tail_r] <= dc_req_addr_i;
            tag_r[tail_r] <= dc_req_tag_i;
            beat_r[tail_r] <= dc_req_beat_i;
            store_r[tail_r] <= dc_req_store_i;
            size_r[tail_r] <= dc_req_size_i;
        end
        if (query_w) begin
            pipe_slot_r <= replay_w ? head_r : tail_r;
            pipe_addr_r <= query_addr_w;
            pipe_tag_r <= replay_w ? tag_r[head_r] : dc_req_tag_i;
            pipe_beat_r <= replay_w ? beat_r[head_r] : dc_req_beat_i;
            pipe_store_r <= query_store_w;
            pipe_size_r <= query_size_w;
            pipe_array_r <= array_free_w;
            pipe_early_r <= promote_w;
            pipe_cached_r <= query_cached_w;
            pipe_device_r <= query_device_w;
            pipe_error_r <= query_error_w;
            pipe_buffer_valid_r <= buffer_valid_r;
            pipe_buffer_addr_r <= buffer_addr_r;
            pipe_buffer_way_r <= buffer_way_r;
            pipe_buffer_data_r <= buffer_data_r;
            pipe_buffer_mask_r <= buffer_mask_r;
            pipe_early0_r <= dc_early_way0_data_o;
            pipe_early1_r <= dc_early_way1_data_o;
            pipe_early_hit_r <= dc_early_hit_o;
        end
        early_addr_r <= dc_early_addr_i;
        early_tag_r <= dc_early_tag_i;
        early_cached_r <=
            dc_early_addr_i[31:SRAM_BITS] == EDRV32_SRAM_BASE[31:SRAM_BITS] ||
            dc_early_addr_i[31:DDR_BITS] == EDRV32_DDR_BASE[31:DDR_BITS];
        if (pipe_use_w && pipe_resolved_w) begin
            result0_r[pipe_slot_r] <= response0_w;
            result1_r[pipe_slot_r] <= response1_w;
            result_hit_r[pipe_slot_r] <= pipe_device_r || pipe_error_r ? 2'b01 : hit_w;
            result_error_r[pipe_slot_r] <= pipe_error_r;
            result_device_r[pipe_slot_r] <= pipe_device_r;
            if (pipe_store_r || pipe_device_r) begin
                pending_addr_r[pipe_index_w] <= pipe_addr_r;
                pending_store_r[pipe_index_w] <= pipe_store_r;
                pending_device_r[pipe_index_w] <= pipe_device_r;
                pending_size_r[pipe_index_w] <= pipe_size_r;
            pending_way_r[pipe_index_w] <= hit_w[1];
            end
            lru_set_r <= pipe_addr_r[13:5];
            lru_data_r <= !hit_w[1];
        end
        if (pipe_miss_w) begin
            miss_addr_r <= pipe_addr_r;
            miss_slot_r <= pipe_slot_r;
            victim_r <= replacement_w;
            wb_addr_r <= {replacement_w ? tag1_w[17:0] : tag0_w[17:0],
                        pipe_addr_r[13:5], 5'd0};
        end
        if (state_r == S_FILL && axi_rvalid_i && bus_beat_r == miss_addr_r[4:3])
            result0_r[miss_slot_r] <= fill_word_w >> {miss_addr_r[1:0], 3'd0};
        if (fill_last_w) begin
            result_hit_r[miss_slot_r] <= 2'b01;
            result_error_r[miss_slot_r] <= fill_error_r || |axi_rresp_i;
            result_device_r[miss_slot_r] <= 1'b0;
            if (store_r[miss_slot_r]) begin
                pending_addr_r[{tag_r[miss_slot_r], beat_r[miss_slot_r]}] <=
                    addr_r[miss_slot_r];
                pending_store_r[{tag_r[miss_slot_r], beat_r[miss_slot_r]}] <= 1'b1;
                pending_device_r[{tag_r[miss_slot_r], beat_r[miss_slot_r]}] <= 1'b0;
                pending_size_r[{tag_r[miss_slot_r], beat_r[miss_slot_r]}] <= size_r[miss_slot_r];
            pending_way_r[{tag_r[miss_slot_r], beat_r[miss_slot_r]}] <= victim_r;
            end
            lru_set_r <= miss_addr_r[13:5];
            lru_data_r <= !victim_r;
        end
        if (commit_cached_w) begin
            buffer_addr_r <= pending_addr_r[commit_index_w];
            buffer_way_r <= pending_way_r[commit_index_w];
            buffer_data_r <= dc_commit_data_i << {pending_addr_r[commit_index_w][1:0], 3'd0};
            buffer_mask_r <= dc_commit_mask_i << pending_addr_r[commit_index_w][1:0];
            done_tag_r <= dc_commit_tag_i;
            done_beat_r <= dc_commit_beat_i;
        end
        if (commit_device_w) begin
            device_index_r <= commit_index_w;
            device_addr_r <= pending_addr_r[commit_index_w];
            device_size_r <= pending_size_r[commit_index_w];
            device_data_r <= dc_commit_data_i;
            device_mask_r <= dc_commit_mask_i;
        end
        if ((device_state_r == D_READ && axi_rvalid_i && done_space_w) ||
            (device_state_r == D_B && axi_bvalid_i && done_space_w)) begin
            done_tag_r <= device_index_r[T:1];
            done_beat_r <= device_index_r[0];
            done_data_r <= device_shift_w[31:0];
        end
        if (maint_accept_w || fence_accept_w) begin
            maint_cmd_r <= fence_accept_w ? (dc_fence_clean_all_i ? 3'd4 : 3'd0) :
                maint_cmd_i;
            maint_start_r <= {1'b0, maint_addr_i};
            maint_end_r <= range_end_w;
            maint_idx_r <= (fence_accept_w || maint_cmd_i == 4) ? 9'd0 : maint_addr_i[13:5];
            maint_left_r <= (fence_accept_w || maint_cmd_i == 4) ? 10'd512 :
                maint_size_i == 0 ? 10'd0 : range_count_w >= 512 ? 10'd512 :
                range_count_w[9:0];
            maint_fence_r <= fence_accept_w;
        end else if (maint_state_r == M_READ && maint_read_w && !commit_device_w &&
            maint_cmd_r == 4 && maint_idx_r[3:0] == 0 &&
            !segment_dirty_r[maint_idx_r[8:4]]) begin
            maint_idx_r <= maint_idx_r + 9'd16;
            maint_left_r <= maint_left_r - 10'd16;
        end else if (maint_state_r == M_NEXT) begin
            maint_idx_r <= maint_idx_r + 9'd1;
            maint_left_r <= maint_left_r - 10'd1;
        end
        if (maint_state_r == M_CHECK && state_r == S_IDLE &&
            device_state_r == D_IDLE && !commit_device_w) begin
            maint_tag1_r <= tag1_w;
            if (maint_match0_w && maint_clean_w && tag0_w[18]) begin
                wb_addr_r <= maint_line0_w;
                victim_r <= 1'b0;
            end else if (maint_match1_w && maint_clean_w && tag1_w[18]) begin
                wb_addr_r <= maint_line1_w;
                victim_r <= 1'b1;
            end
        end
        if (maint_state_r == M_WAY1 && device_state_r == D_IDLE && !commit_device_w) begin
            wb_addr_r <= {maint_tag1_r[17:0], maint_idx_r, 5'd0};
            victim_r <= 1'b1;
        end
        if (wb_finish_w && |axi_bresp_i) wb_err_addr_r <= wb_addr_r;
    end
    wire trace_device_write_w;
    assign trace_device_write_w = device_state_r == D_WRITE && !device_w_r && axi_wready_i;
    assign trace_mem_effect_valid_o = commit_cached_w || trace_device_write_w;
    assign trace_mem_effect_tag_o = trace_device_write_w ?
        device_index_r[T:1] : dc_commit_tag_i;
    assign trace_mem_effect_addr_o = trace_device_write_w ?
        device_addr_r : pending_addr_r[commit_index_w];
    assign trace_mem_effect_data_o = trace_device_write_w ? device_data_r : dc_commit_data_i;
    assign trace_mem_effect_mask_o = trace_device_write_w ? device_mask_r : dc_commit_mask_i;
    assign debug_miss_o = state_r != S_IDLE;
endmodule
