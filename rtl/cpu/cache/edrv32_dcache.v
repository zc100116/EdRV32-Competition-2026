// ============================================================================
// File        : edrv32_dcache.v
// Description : Blocking two-way write-back, write-allocate data cache.
// Notes       : Cacheable hits perform a pipelined synchronous all-way lookup.
//               Store preparations enter an ordered reservation FIFO; only
//               COMMIT may authorize the one-entry array-write buffer.
//               Dirty-line
//               cleaning is explicit so FENCE.I can order data writes before
//               the instruction cache is allowed to refill.  The memory-side
//               interface is AXI4 directly: line refill/writeback uses two
//               64-bit beats and uncached accesses use one narrow beat.
// ============================================================================
`include "edrv32_axi4.vh"
`include "edrv32_bus.vh"
`include "edrv32_lsu.vh"

module edrv32_dcache #(
    parameter integer LINE_COUNT = 256,
    parameter integer LINE_BYTES = 16,
    parameter integer WAYS = 2,
    parameter integer SET_COUNT = LINE_COUNT / WAYS,
    parameter integer INDEX_W = $clog2(SET_COUNT),
    parameter integer WORD_COUNT = LINE_BYTES / 4,
    parameter integer WORD_W = $clog2(WORD_COUNT),
    parameter integer OFFSET_W = $clog2(LINE_BYTES),
    parameter integer TAG_W = 32 - INDEX_W - OFFSET_W
) (
    input  wire                 clk_i,
    input  wire                 rst_n_i,

    // Side-effect-free lookup owned by MEM2.
    input  wire                 lookup_req_valid_i,
    output wire                 lookup_req_ready_o,
    input  wire [`EDRV32_LSU_TOKEN_W-1:0] lookup_req_token_i,
    input  wire [31:0]          lookup_req_addr_i,
    input  wire                 lookup_req_store_i,
    input  wire [`BUS_SZ_W-1:0] lookup_req_size_i,
    input  wire                 lookup_req_unsigned_i,
    output wire                 lookup_resp_valid_o,
    input  wire                 lookup_resp_ready_i,
    output wire [`EDRV32_LSU_TOKEN_W-1:0] lookup_resp_token_o,
    output wire                 lookup_resp_store_o,
    output wire [31:0]          lookup_resp_data_o,
    output wire                 lookup_resp_error_o,
    output wire                 lookup_fast_valid_o,
    input  wire                 lookup_fast_ready_i,
    output wire [`EDRV32_LSU_TOKEN_W-1:0] lookup_fast_token_o,
    output wire                 lookup_fast_store_o,
    output wire [31:0]          lookup_fast_data_o,
    input  wire                 lookup_cancel_i,
    input  wire [1:0]           lookup_cancel_keep_count_i,

    // COMMIT-owned request.  A cacheable store must match its reservation;
    // uncached/MMIO loads and stores use one narrow AXI transfer.
    input  wire                 commit_req_valid_i,
    output wire                 commit_req_ready_o,
    input  wire [31:0]          commit_req_addr_i,
    input  wire                 commit_req_write_i,
    input  wire [`BUS_SZ_W-1:0] commit_req_size_i,
    input  wire [3:0]           commit_req_wstrb_i,
    input  wire [31:0]          commit_req_wdata_i,
    input  wire                 commit_req_cacheable_i,
    output wire                 commit_resp_valid_o,
    input  wire                 commit_resp_ready_i,
    output wire [31:0]          commit_resp_data_o,
    output wire                 commit_resp_error_o,

    // Clean every dirty resident line; used by FENCE/FENCE.I ordering.
    input  wire                 clean_all_i,
    output wire                 clean_busy_o,
    output wire                 clean_done_o,

    // Software cache-maintenance command. size==0 selects the whole cache;
    // otherwise every resident line intersecting [addr, addr+size) is acted on.
    input  wire                 maint_invalidate_i,
    input  wire                 maint_clean_i,
    input  wire                 maint_clean_invalidate_i,
    input  wire [31:0]          maint_addr_i,
    input  wire [31:0]          maint_size_i,
    output wire                 maint_busy_o,
    output wire                 maint_done_o,

    // Single-outstanding AXI4 master port.
    output wire [`AXI_ID_W-1:0]    axi_awid_o,
    output wire [31:0]             axi_awaddr_o,
    output wire [`AXI_LEN_W-1:0]   axi_awlen_o,
    output wire [`AXI_SIZE_W-1:0]  axi_awsize_o,
    output wire [`AXI_BURST_W-1:0] axi_awburst_o,
    output wire                    axi_awvalid_o,
    input  wire                    axi_awready_i,
    output wire [`AXI_DATA_W-1:0]  axi_wdata_o,
    output wire [`AXI_STRB_W-1:0]  axi_wstrb_o,
    output wire                    axi_wlast_o,
    output wire                    axi_wvalid_o,
    input  wire                    axi_wready_i,
    input  wire [`AXI_ID_W-1:0]    axi_bid_i,
    input  wire [`AXI_RESP_W-1:0]  axi_bresp_i,
    input  wire                    axi_bvalid_i,
    output wire                    axi_bready_o,
    output wire [`AXI_ID_W-1:0]    axi_arid_o,
    output wire [31:0]             axi_araddr_o,
    output wire [`AXI_LEN_W-1:0]   axi_arlen_o,
    output wire [`AXI_SIZE_W-1:0]  axi_arsize_o,
    output wire [`AXI_BURST_W-1:0] axi_arburst_o,
    output wire                    axi_arvalid_o,
    input  wire                    axi_arready_i,
    input  wire [`AXI_ID_W-1:0]    axi_rid_i,
    input  wire [`AXI_DATA_W-1:0]  axi_rdata_i,
    input  wire [`AXI_RESP_W-1:0]  axi_rresp_i,
    input  wire                    axi_rlast_i,
    input  wire                    axi_rvalid_i,
    output wire                    axi_rready_o,

    output wire                 miss_o,
    output wire                 writeback_o,
    output wire                 refill_busy_o
);

    localparam [4:0] STATE_IDLE           = 5'd0;
    localparam [4:0] STATE_LOOKUP         = 5'd1;
    localparam [4:0] STATE_LOOKUP_RESP    = 5'd2;
    localparam [4:0] STATE_EVICT_REQ      = 5'd4;
    localparam [4:0] STATE_EVICT_WAIT     = 5'd5;
    localparam [4:0] STATE_REFILL_REQ     = 5'd6;
    localparam [4:0] STATE_REFILL_WAIT    = 5'd7;
    localparam [4:0] STATE_COMMIT_REQ     = 5'd8;
    localparam [4:0] STATE_COMMIT_WAIT    = 5'd9;
    localparam [4:0] STATE_COMMIT_RESP    = 5'd10;
    localparam [4:0] STATE_CLEAN_READ     = 5'd11;
    localparam [4:0] STATE_CLEAN_CHECK0   = 5'd12;
    localparam [4:0] STATE_CLEAN_CHECK1   = 5'd13;
    localparam [4:0] STATE_CLEAN_WB_REQ   = 5'd14;
    localparam [4:0] STATE_CLEAN_WB_WAIT  = 5'd15;
    localparam [4:0] STATE_CLEAN_CLASSIFY = 5'd16;
    localparam [4:0] STATE_MISS_WAIT_STORES = 5'd17;
    localparam integer AXI_BEAT_BYTES = `AXI_DATA_W / 8;
    localparam integer AXI_BEAT_COUNT = LINE_BYTES / AXI_BEAT_BYTES;
    localparam integer AXI_BEAT_W = $clog2(AXI_BEAT_COUNT);
    localparam [AXI_BEAT_W-1:0] LAST_AXI_BEAT = AXI_BEAT_COUNT - 1;
    localparam [`AXI_LEN_W-1:0] LINE_AXLEN = AXI_BEAT_COUNT - 1;

    generate
        if ((WAYS != 2) || (LINE_BYTES != 16) || (`AXI_DATA_W != 64) ||
            ((LINE_COUNT % WAYS) != 0)) begin : gen_bad_geometry
            edrv32_dcache_requires_two_way_16byte_lines_and_64bit_axi
                u_static_assert ();
        end
    endgenerate

    reg [4:0] state_r;
    reg [4:0] state_next_w;
    reg miss_wait_retry_r;

    reg [SET_COUNT-1:0] valid_way0_r;
    reg [SET_COUNT-1:0] valid_way1_r;
    reg [SET_COUNT-1:0] dirty_way0_r;
    reg [SET_COUNT-1:0] dirty_way1_r;
    // One bit per set names the next victim when both ways are valid.
    reg [SET_COUNT-1:0] replacement_way_r;

    reg [31:0] lookup_addr_r;
    reg lookup_way0_valid_r;
    reg lookup_way1_valid_r;
    reg [`EDRV32_LSU_TOKEN_W-1:0] lookup_token_r;
    reg lookup_store_r;
    reg [`BUS_SZ_W-1:0] lookup_size_r;
    reg lookup_unsigned_r;
    reg [31:0] lookup_response_data_r;
    reg lookup_response_error_r;

    // A two-entry request skid cuts the Cache hit/COMMIT cone from the
    // upstream queue's ready signal.  The empty path falls through to D0 so
    // steady hit traffic still launches one synchronous read each cycle.
    reg [1:0] request_fifo_count_r;
    reg request_fifo_head_r;
    reg request_fifo_tail_r;
    reg [`EDRV32_LSU_TOKEN_W-1:0] request_fifo_token_r [0:1];
    reg [31:0] request_fifo_addr_r [0:1];
    reg request_fifo_store_r [0:1];
    reg [`BUS_SZ_W-1:0] request_fifo_size_r [0:1];
    reg request_fifo_unsigned_r [0:1];

    reg miss_way_r;
    reg [TAG_W-1:0] victim_tag_r;
    reg [127:0] victim_line_r;
    reg victim_dirty_r;
    reg [AXI_BEAT_W-1:0] refill_beat_r;
    reg refill_error_r;
    reg lookup_cancel_pending_r;
    reg [127:0] refill_line_r;

    // AW and W are independent AXI channels.  These registers keep both
    // payloads stable until accepted and permit one W beat per cycle.
    reg write_aw_pending_r;
    reg write_w_done_r;
    reg [AXI_BEAT_W-1:0] write_beat_r;

    // Hit lookups reserve independently of COMMIT.  The ordered FIFO lets
    // later lookups use the synchronous read port while older stores wait to
    // retire.  A miss remains blocking and cannot replace a reserved line.
    reg [2:0] reservation_count_r;
    reg [1:0] reservation_head_r;
    reg [1:0] reservation_tail_r;
    reg [31:0] reservation_addr_r [0:3];
    reg reservation_way_r [0:3];
    reg prepared_way_r;
    // Expose the oldest reservation for commit matching and diagnostics.
    wire store_reservation_valid_w = reservation_count_r != 3'd0;
    wire [31:0] store_reservation_addr_w =
        reservation_addr_r[reservation_head_r];
    wire store_reservation_way_w = reservation_way_r[reservation_head_r];
    wire [2:0] cancel_keep_count_w =
        (reservation_count_r < {1'b0, lookup_cancel_keep_count_i})
            ? reservation_count_r
            : {1'b0, lookup_cancel_keep_count_i};

    // One entry is sufficient for this in-order, single-retire core: the
    // accepted word data and byte mask are authorized by COMMIT, then drain
    // through the cache array's independent byte-write port on the following
    // edge.  The narrow registered payload lets the lookup FSM turn over
    // independently without duplicating a full cache line in flip-flops.
    reg store_buffer_valid_r;
    reg [31:0] store_buffer_addr_r;
    reg store_buffer_way_r;
    reg [31:0] store_buffer_data_r;
    reg [3:0] store_buffer_wstrb_r;
    reg store_drain_shadow_valid_r;
    reg [31:0] store_drain_shadow_addr_r;
    reg store_drain_shadow_way_r;
    reg [31:0] store_drain_shadow_data_r;
    reg [3:0] store_drain_shadow_wstrb_r;
    wire store_buffer_drain_w;
    wire reservation_dequeue_w;

    reg [31:0] commit_addr_r;
    reg commit_write_r;
    reg [`BUS_SZ_W-1:0] commit_size_r;
    reg [3:0] commit_wstrb_r;
    reg [31:0] commit_wdata_r;
    reg [31:0] commit_response_data_r;
    reg commit_response_error_r;
    reg store_response_pending_r;

    reg clean_pending_r;
    reg clean_pending_clean_r;
    reg clean_pending_invalidate_r;
    reg [31:0] clean_pending_addr_r;
    reg [31:0] clean_pending_size_r;
    reg clean_operation_clean_r;
    reg clean_operation_invalidate_r;
    reg [31:0] clean_operation_addr_r;
    reg [31:0] clean_operation_size_r;
    reg [INDEX_W-1:0] clean_set_r;
    reg clean_way_r;
    reg [TAG_W-1:0] clean_tag_r;
    reg [127:0] clean_line_r;
    reg clean_done_r;
    reg clean_way0_range_hit_r;
    reg clean_way1_range_hit_r;

    function [31:0] merge_store_data;
        input [31:0] old_data_i;
        input [31:0] data_i;
        input [3:0] wstrb_i;
        reg [31:0] byte_mask;
        begin
            byte_mask = {
                {8{wstrb_i[3]}}, {8{wstrb_i[2]}},
                {8{wstrb_i[1]}}, {8{wstrb_i[0]}}
            };
            merge_store_data = (old_data_i & ~byte_mask) |
                               (data_i & byte_mask);
        end
    endfunction

    wire use_request_fifo_w = lookup_fast_ready_i;
    wire request_fifo_nonempty_w = request_fifo_count_r != 2'd0;
    wire lookup_request_fire_w;
    wire lookup_input_accept_w = lookup_req_valid_i && lookup_req_ready_o;
    wire [31:0] lookup_issue_addr_w =
        (use_request_fifo_w && request_fifo_nonempty_w)
            ? request_fifo_addr_r[request_fifo_head_r] : lookup_req_addr_i;
    wire [`EDRV32_LSU_TOKEN_W-1:0] lookup_issue_token_w =
        (use_request_fifo_w && request_fifo_nonempty_w)
            ? request_fifo_token_r[request_fifo_head_r] : lookup_req_token_i;
    wire lookup_issue_store_w =
        (use_request_fifo_w && request_fifo_nonempty_w)
            ? request_fifo_store_r[request_fifo_head_r] : lookup_req_store_i;
    wire [`BUS_SZ_W-1:0] lookup_issue_size_w =
        (use_request_fifo_w && request_fifo_nonempty_w)
            ? request_fifo_size_r[request_fifo_head_r] : lookup_req_size_i;
    wire lookup_issue_unsigned_w =
        (use_request_fifo_w && request_fifo_nonempty_w)
            ? request_fifo_unsigned_r[request_fifo_head_r]
            : lookup_req_unsigned_i;
    wire lookup_issue_valid_w = use_request_fifo_w
        ? (request_fifo_nonempty_w || lookup_input_accept_w)
        : lookup_req_valid_i;
    wire [INDEX_W-1:0] request_index_w =
        lookup_issue_addr_w[OFFSET_W + INDEX_W - 1:OFFSET_W];
    wire [INDEX_W-1:0] resident_index_w =
        lookup_addr_r[OFFSET_W + INDEX_W - 1:OFFSET_W];
    wire [WORD_W-1:0] resident_word_w = lookup_addr_r[OFFSET_W-1:2];
    wire [TAG_W-1:0] resident_tag_w =
        lookup_addr_r[31:OFFSET_W + INDEX_W];

    wire [TAG_W-1:0] way0_tag_w;
    wire [TAG_W-1:0] way1_tag_w;
    wire [127:0] way0_line_w;
    wire [127:0] way1_line_w;
    wire store_buffer_resident_set_w = store_buffer_valid_r &&
        (store_buffer_addr_r[OFFSET_W + INDEX_W - 1:OFFSET_W] ==
         resident_index_w);
    wire store_buffer_way0_w = store_buffer_resident_set_w &&
                               !store_buffer_way_r;
    wire store_buffer_way1_w = store_buffer_resident_set_w &&
                               store_buffer_way_r;
    // Valid bits are sampled with the synchronous tag/data read.  Their
    // dynamic set selection then ends at this local register rather than
    // extending the hit-data bypass path into EX.
    wire resident_way0_valid_w = lookup_way0_valid_r;
    wire resident_way1_valid_w = lookup_way1_valid_r;
    wire resident_way0_dirty_w = dirty_way0_r[resident_index_w];
    wire resident_way1_dirty_w = dirty_way1_r[resident_index_w];
    wire way0_hit_w = resident_way0_valid_w &&
                      (way0_tag_w == resident_tag_w);
    wire way1_hit_w = resident_way1_valid_w &&
                      (way1_tag_w == resident_tag_w);
    wire lookup_hit_w = way0_hit_w || way1_hit_w;
    wire lookup_hit_way_w = way1_hit_w;
    wire [127:0] lookup_hit_line_w = way0_hit_w ? way0_line_w : way1_line_w;
    wire miss_victim_way_w = !resident_way0_valid_w ? 1'b0 :
                             !resident_way1_valid_w ? 1'b1 :
                             store_buffer_resident_set_w
                                 ? ~store_buffer_way_r
                                 : replacement_way_r[resident_index_w];
    wire miss_victim_valid_w = miss_victim_way_w
        ? resident_way1_valid_w : resident_way0_valid_w;
    wire miss_victim_dirty_w = miss_victim_way_w
        ? (resident_way1_dirty_w || store_buffer_way1_w)
        : (resident_way0_dirty_w || store_buffer_way0_w);
    wire [TAG_W-1:0] miss_victim_tag_w = miss_victim_way_w
        ? way1_tag_w : way0_tag_w;
    wire [127:0] miss_victim_line_w = miss_victim_way_w
        ? way1_line_w : way0_line_w;

    function [31:0] select_word;
        input [127:0] line_i;
        input [WORD_W-1:0] word_i;
        begin
            case (word_i)
                2'd0: select_word = line_i[31:0];
                2'd1: select_word = line_i[63:32];
                2'd2: select_word = line_i[95:64];
                default: select_word = line_i[127:96];
            endcase
        end
    endfunction

    // The lookup response is the CPU-facing load value, not an untyped cache
    // word.  Formatting before the response register prevents a registered
    // cache hit from traversing byte selection/sign extension and the full EX
    // datapath in one cycle.  Stores ignore this value.
    function [31:0] format_load_word;
        input [31:0]          word_i;
        input [1:0]           addr_lsb_i;
        input [`BUS_SZ_W-1:0] size_i;
        input                 unsigned_i;
        reg [7:0]             selected_byte;
        reg [15:0]            selected_half;
        begin
            case (addr_lsb_i)
                2'd0: selected_byte = word_i[7:0];
                2'd1: selected_byte = word_i[15:8];
                2'd2: selected_byte = word_i[23:16];
                default: selected_byte = word_i[31:24];
            endcase
            selected_half = addr_lsb_i[1] ? word_i[31:16] : word_i[15:0];
            case (size_i)
                `BUS_SZ_BYTE: format_load_word = unsigned_i
                    ? {24'd0, selected_byte}
                    : {{24{selected_byte[7]}}, selected_byte};
                `BUS_SZ_HALF: format_load_word = unsigned_i
                    ? {16'd0, selected_half}
                    : {{16{selected_half[15]}}, selected_half};
                default: format_load_word = word_i;
            endcase
        end
    endfunction

    wire [31:0] lookup_hit_raw_word_w = select_word(
        lookup_hit_line_w, resident_word_w);
    wire store_shadow_hit_word_w = store_drain_shadow_valid_r &&
        (lookup_addr_r[31:2] == store_drain_shadow_addr_r[31:2]) &&
        (lookup_hit_way_w == store_drain_shadow_way_r) && lookup_hit_w;
    wire [31:0] lookup_shadow_word_w = store_shadow_hit_word_w
        ? merge_store_data(lookup_hit_raw_word_w,
                           store_drain_shadow_data_r,
                           store_drain_shadow_wstrb_r)
        : lookup_hit_raw_word_w;
    wire store_buffer_hit_word_w = store_buffer_valid_r &&
        (lookup_addr_r[31:2] == store_buffer_addr_r[31:2]) &&
        (lookup_hit_way_w == store_buffer_way_r) &&
        lookup_hit_w;
    wire [31:0] lookup_hit_word_w = store_buffer_hit_word_w
        ? merge_store_data(lookup_shadow_word_w, store_buffer_data_r,
                           store_buffer_wstrb_r)
        : lookup_shadow_word_w;
    wire reservation_room_w = reservation_count_r != 3'd4;
    assign lookup_fast_valid_o = (state_r == STATE_LOOKUP) && lookup_hit_w &&
                                 (!lookup_store_r || reservation_room_w);
    assign lookup_fast_token_o = lookup_token_r;
    assign lookup_fast_store_o = lookup_store_r;
    assign lookup_fast_data_o = format_load_word(
        lookup_hit_word_w, lookup_addr_r[1:0], lookup_size_r,
        lookup_unsigned_r);
    wire lookup_fast_fire_w = lookup_fast_valid_o &&
                              lookup_fast_ready_i;

    wire lookup_response_fire_w = lookup_resp_valid_o && lookup_resp_ready_i;
    // A completed load releases lookup ownership. If MEM2 also retires that
    // registered response on this edge, launch the next synchronous array read
    // without inserting an empty IDLE cycle. Successful store lookups retain
    // their reservation and therefore cannot recycle here.
    wire lookup_response_recycle_w =
        (state_r == STATE_LOOKUP_RESP) && lookup_response_fire_w;

    wire maintenance_live_request_w = clean_all_i || maint_invalidate_i ||
                                      maint_clean_i ||
                                      maint_clean_invalidate_i;
    wire maintenance_live_clean_w = clean_all_i || maint_clean_i ||
                                    maint_clean_invalidate_i;
    wire maintenance_live_invalidate_w = maint_invalidate_i ||
                                         maint_clean_invalidate_i;
    wire [31:0] maintenance_live_addr_w = clean_all_i ? 32'd0 : maint_addr_i;
    wire [31:0] maintenance_live_size_w = clean_all_i ? 32'd0 : maint_size_i;
    wire maintenance_state_active_w =
        (state_r == STATE_CLEAN_READ) ||
        (state_r == STATE_CLEAN_CLASSIFY) ||
        (state_r == STATE_CLEAN_CHECK0) ||
        (state_r == STATE_CLEAN_CHECK1) ||
        (state_r == STATE_CLEAN_WB_REQ) ||
        (state_r == STATE_CLEAN_WB_WAIT);

    wire local_store_window_w = store_reservation_valid_w &&
                                commit_req_cacheable_i &&
                                (!store_buffer_valid_r ||
                                 store_buffer_drain_w);
    wire uncached_commit_window_w = (state_r == STATE_IDLE) &&
                                    !clean_pending_r &&
                                    !maintenance_live_request_w &&
                                    !commit_req_cacheable_i;
    wire local_store_fire_w = commit_req_valid_i && local_store_window_w;
    wire reservation_match_w = store_reservation_valid_w &&
                               commit_req_write_i &&
                               commit_req_cacheable_i &&
                               (commit_req_addr_i[31:2] ==
                                store_reservation_addr_w[31:2]);
    assign reservation_dequeue_w = local_store_fire_w &&
                                   reservation_match_w;

    reg [127:0] completed_refill_line_w;
    always @* begin
        completed_refill_line_w = refill_line_r;
        if (refill_beat_r == {AXI_BEAT_W{1'b0}})
            completed_refill_line_w[63:0] = axi_rdata_i;
        else
            completed_refill_line_w[127:64] = axi_rdata_i;
    end

    wire evict_write_request_w = (state_r == STATE_EVICT_REQ);
    wire clean_write_request_w = (state_r == STATE_CLEAN_WB_REQ);
    wire uncached_write_request_w = (state_r == STATE_COMMIT_REQ) &&
                                    commit_write_r;
    wire line_write_request_w = evict_write_request_w ||
                                clean_write_request_w;
    wire any_write_request_w = line_write_request_w ||
                               uncached_write_request_w;
    // Once ARVALID is presented it remains asserted until ARREADY. A younger
    // pipeline cancellation only marks the accepted burst for discard; AXI
    // request and response beats are still drained to completion.
    wire refill_read_request_w = (state_r == STATE_REFILL_REQ);
    wire uncached_read_request_w = (state_r == STATE_COMMIT_REQ) &&
                                   !commit_write_r;

    wire axi_aw_fire_w = axi_awvalid_o && axi_awready_i;
    wire axi_w_fire_w = axi_wvalid_o && axi_wready_i;
    wire axi_b_fire_w = axi_bvalid_i && axi_bready_o;
    wire axi_ar_fire_w = axi_arvalid_o && axi_arready_i;
    wire axi_r_fire_w = axi_rvalid_i && axi_rready_o;
    wire write_last_beat_w = !line_write_request_w ||
                             (write_beat_r == LAST_AXI_BEAT);
    wire write_channels_done_w =
        (!write_aw_pending_r || axi_aw_fire_w) &&
        (write_w_done_r || (axi_w_fire_w && write_last_beat_w));

    wire [31:0] evict_line_addr_w = {
        victim_tag_r, resident_index_w, {OFFSET_W{1'b0}}
    };
    wire [31:0] clean_line_addr_w = {
        clean_tag_r, clean_set_r, {OFFSET_W{1'b0}}
    };
    wire [127:0] writeback_line_w = clean_write_request_w
        ? clean_line_r : victim_line_r;
    wire [`AXI_DATA_W-1:0] writeback_data_w =
        (write_beat_r == {AXI_BEAT_W{1'b0}})
        ? writeback_line_w[63:0] : writeback_line_w[127:64];

    assign axi_awid_o = {`AXI_ID_W{1'b0}};
    assign axi_awaddr_o = clean_write_request_w ? clean_line_addr_w :
                          evict_write_request_w ? evict_line_addr_w :
                          {commit_addr_r[31:2], 2'b00};
    assign axi_awlen_o = line_write_request_w
        ? LINE_AXLEN : {`AXI_LEN_W{1'b0}};
    assign axi_awsize_o = line_write_request_w
        ? `AXI_SIZE_8B : `AXI_SIZE_4B;
    assign axi_awburst_o = `AXI_BURST_INCR;
    assign axi_awvalid_o = any_write_request_w && write_aw_pending_r;

    assign axi_wdata_o = line_write_request_w ? writeback_data_w :
        (commit_addr_r[2] ? {commit_wdata_r, 32'd0}
                          : {32'd0, commit_wdata_r});
    assign axi_wstrb_o = line_write_request_w
        ? {`AXI_STRB_W{1'b1}}
        : (commit_addr_r[2] ? {commit_wstrb_r, 4'd0}
                            : {4'd0, commit_wstrb_r});
    assign axi_wlast_o = write_last_beat_w;
    assign axi_wvalid_o = any_write_request_w && !write_w_done_r;
    assign axi_bready_o = (state_r == STATE_EVICT_WAIT) ||
                          (state_r == STATE_CLEAN_WB_WAIT) ||
                          ((state_r == STATE_COMMIT_WAIT) && commit_write_r);

    assign axi_arid_o = {`AXI_ID_W{1'b0}};
    assign axi_araddr_o = refill_read_request_w
        ? {lookup_addr_r[31:OFFSET_W], {OFFSET_W{1'b0}}}
        : {commit_addr_r[31:2], 2'b00};
    assign axi_arlen_o = refill_read_request_w
        ? LINE_AXLEN : {`AXI_LEN_W{1'b0}};
    assign axi_arsize_o = refill_read_request_w
        ? `AXI_SIZE_8B : `AXI_SIZE_4B;
    assign axi_arburst_o = `AXI_BURST_INCR;
    assign axi_arvalid_o = refill_read_request_w || uncached_read_request_w;

    wire refill_response_window_w = (state_r == STATE_REFILL_WAIT) ||
        ((state_r == STATE_REFILL_REQ) && axi_ar_fire_w);
    wire uncached_read_response_window_w =
        ((state_r == STATE_COMMIT_WAIT) && !commit_write_r) ||
        (uncached_read_request_w && axi_ar_fire_w);
    assign axi_rready_o = refill_response_window_w ||
                          uncached_read_response_window_w;

    wire refill_expected_last_w = (refill_beat_r == LAST_AXI_BEAT);
    wire refill_response_fire_w = refill_response_window_w && axi_r_fire_w;
    wire refill_response_complete_w = refill_response_fire_w &&
                                      (refill_expected_last_w || axi_rlast_i);
    wire evict_response_fire_w = (state_r == STATE_EVICT_WAIT) &&
                                 axi_b_fire_w;
    wire clean_response_fire_w = (state_r == STATE_CLEAN_WB_WAIT) &&
                                 axi_b_fire_w;
    wire uncached_read_response_fire_w =
        uncached_read_response_window_w && axi_r_fire_w;
    wire uncached_write_response_fire_w =
        (state_r == STATE_COMMIT_WAIT) && commit_write_r && axi_b_fire_w;
    wire uncached_response_fire_w = uncached_read_response_fire_w ||
                                    uncached_write_response_fire_w;
    wire uncached_request_fire_w = commit_req_valid_i &&
                                   uncached_commit_window_w;

    wire axi_read_error_w = (axi_rresp_i != `AXI_RESP_OKAY) ||
                            (axi_rid_i != {`AXI_ID_W{1'b0}});
    wire axi_write_error_w = (axi_bresp_i != `AXI_RESP_OKAY) ||
                             (axi_bid_i != {`AXI_ID_W{1'b0}});
    wire refill_protocol_error_w = axi_rlast_i != refill_expected_last_w;
    wire [31:0] uncached_read_data_w = commit_addr_r[2]
        ? axi_rdata_i[63:32] : axi_rdata_i[31:0];

    wire clean_start_from_pending_w = (state_r == STATE_IDLE) &&
                                      clean_pending_r;
    wire clean_start_from_live_w = (state_r == STATE_IDLE) &&
                                   !clean_pending_r &&
                                   maintenance_live_request_w;
    wire clean_start_w = clean_start_from_pending_w || clean_start_from_live_w;
    wire clean_scan_way_w = (state_r == STATE_CLEAN_CHECK1);
    wire clean_scan_valid_w = clean_scan_way_w
        ? valid_way1_r[clean_set_r] : valid_way0_r[clean_set_r];
    wire clean_scan_dirty_w = clean_scan_way_w
        ? dirty_way1_r[clean_set_r] : dirty_way0_r[clean_set_r];
    wire [TAG_W-1:0] clean_scan_tag_w = clean_scan_way_w
        ? way1_tag_w : way0_tag_w;
    wire [127:0] clean_scan_line_w = clean_scan_way_w
        ? way1_line_w : way0_line_w;
    wire [31:0] clean_way0_line_addr_w = {
        way0_tag_w, clean_set_r, {OFFSET_W{1'b0}}
    };
    wire [31:0] clean_way1_line_addr_w = {
        way1_tag_w, clean_set_r, {OFFSET_W{1'b0}}
    };
    wire [31:0] clean_range_end_addr_w = clean_operation_addr_r +
                                         clean_operation_size_r - 32'd1;
    wire [31:0] clean_range_first_line_w = {
        clean_operation_addr_r[31:OFFSET_W], {OFFSET_W{1'b0}}
    };
    wire [31:0] clean_range_last_line_w = {
        clean_range_end_addr_w[31:OFFSET_W], {OFFSET_W{1'b0}}
    };
    wire clean_range_wrap_w = clean_range_end_addr_w <
                              clean_operation_addr_r;
    wire clean_way0_range_hit_w = (clean_operation_size_r == 32'd0) ||
        (!clean_range_wrap_w &&
         (clean_way0_line_addr_w >= clean_range_first_line_w) &&
         (clean_way0_line_addr_w <= clean_range_last_line_w)) ||
        (clean_range_wrap_w &&
         ((clean_way0_line_addr_w >= clean_range_first_line_w) ||
          (clean_way0_line_addr_w <= clean_range_last_line_w)));
    wire clean_way1_range_hit_w = (clean_operation_size_r == 32'd0) ||
        (!clean_range_wrap_w &&
         (clean_way1_line_addr_w >= clean_range_first_line_w) &&
         (clean_way1_line_addr_w <= clean_range_last_line_w)) ||
        (clean_range_wrap_w &&
         ((clean_way1_line_addr_w >= clean_range_first_line_w) ||
          (clean_way1_line_addr_w <= clean_range_last_line_w)));
    wire clean_range_hit_w = clean_scan_way_w
        ? clean_way1_range_hit_r : clean_way0_range_hit_r;
    wire clean_scan_match_w = clean_scan_valid_w && clean_range_hit_w;
    wire clean_scan_needs_writeback_w = clean_scan_match_w &&
        clean_operation_clean_r && clean_scan_dirty_w;
    wire clean_scan_apply_w =
        ((state_r == STATE_CLEAN_CHECK0) ||
         (state_r == STATE_CLEAN_CHECK1)) &&
        clean_scan_match_w && !clean_scan_needs_writeback_w;
    wire clean_last_set_w = (clean_set_r == SET_COUNT - 1);
    wire clean_line_success_w = clean_response_fire_w &&
                                !axi_write_error_w;
    wire clean_metadata_apply_w = clean_scan_apply_w || clean_line_success_w;
    wire clean_metadata_way_w = clean_line_success_w
        ? clean_way_r : clean_scan_way_w;
    assign miss_o = (state_r == STATE_LOOKUP) && !lookup_cancel_i &&
                    !lookup_hit_w && !miss_wait_retry_r;
    assign writeback_o = (evict_response_fire_w &&
                          !axi_write_error_w) ||
                         clean_line_success_w;
    assign refill_busy_o = (state_r == STATE_EVICT_REQ) ||
                           (state_r == STATE_EVICT_WAIT) ||
                           (state_r == STATE_REFILL_REQ) ||
                           (state_r == STATE_REFILL_WAIT);
    wire clean_finish_without_write_w =
        (state_r == STATE_CLEAN_CHECK1) &&
        !clean_scan_needs_writeback_w;
    wire clean_finish_w =
        (clean_finish_without_write_w && clean_last_set_w) ||
        (clean_response_fire_w && clean_way_r && clean_last_set_w);

    // The external ready path ends at a local two-entry FIFO.  Only the D0
    // launch decision depends on the current hit result and reservation room.
    wire lookup_hit_turnover_w = (state_r == STATE_LOOKUP) &&
                                 lookup_hit_w && lookup_fast_fire_w;
    wire lookup_launch_ready_w = ((state_r == STATE_IDLE) ||
                                  lookup_response_recycle_w ||
                                  lookup_hit_turnover_w) &&
                                 (!commit_req_valid_i ||
                                  commit_req_cacheable_i) &&
                                 (!store_reservation_valid_w ||
                                  use_request_fifo_w ||
                                  reservation_dequeue_w) &&
                                 (!lookup_issue_store_w ||
                                  reservation_room_w) &&
                                 !clean_pending_r &&
                                 !maintenance_live_request_w &&
                                 !lookup_cancel_i;
    assign lookup_req_ready_o = use_request_fifo_w
        ? (request_fifo_count_r != 2'd2) && !clean_pending_r &&
          !maintenance_live_request_w && !maintenance_state_active_w &&
          !lookup_cancel_i
        : lookup_launch_ready_w;
    assign lookup_request_fire_w = lookup_issue_valid_w &&
                                   lookup_launch_ready_w;
    wire request_fifo_push_w = use_request_fifo_w &&
        lookup_input_accept_w &&
        (request_fifo_nonempty_w || !lookup_request_fire_w);
    wire request_fifo_pop_w = use_request_fifo_w &&
                              request_fifo_nonempty_w &&
                              lookup_request_fire_w;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            request_fifo_count_r <= 2'd0;
            request_fifo_head_r <= 1'b0;
            request_fifo_tail_r <= 1'b0;
        end else if (lookup_cancel_i) begin
            request_fifo_count_r <= 2'd0;
            request_fifo_head_r <= 1'b0;
            request_fifo_tail_r <= 1'b0;
        end else begin
            if (request_fifo_pop_w)
                request_fifo_head_r <= ~request_fifo_head_r;
            if (request_fifo_push_w)
                request_fifo_tail_r <= ~request_fifo_tail_r;
            case ({request_fifo_push_w, request_fifo_pop_w})
                2'b10: request_fifo_count_r <= request_fifo_count_r + 2'd1;
                2'b01: request_fifo_count_r <= request_fifo_count_r - 2'd1;
                default: begin end
            endcase
        end
    end
    always @(posedge clk_i) begin
        if (request_fifo_push_w) begin
            request_fifo_token_r[request_fifo_tail_r] <= lookup_req_token_i;
            request_fifo_addr_r[request_fifo_tail_r] <= lookup_req_addr_i;
            request_fifo_store_r[request_fifo_tail_r] <= lookup_req_store_i;
            request_fifo_size_r[request_fifo_tail_r] <= lookup_req_size_i;
            request_fifo_unsigned_r[request_fifo_tail_r] <=
                lookup_req_unsigned_i;
        end
    end
    assign lookup_resp_valid_o = (state_r == STATE_LOOKUP_RESP) &&
        (!lookup_store_r || lookup_response_error_r || reservation_room_w);
    assign lookup_resp_token_o = lookup_token_r;
    assign lookup_resp_store_o = lookup_store_r;
    assign lookup_resp_data_o = lookup_response_data_r;
    assign lookup_resp_error_o = lookup_response_error_r;

    // A cacheable store is acknowledged directly when its registered
    // reservation is accepted into the committed-store buffer.  The existing
    // registered response state remains the fallback when the consumer is
    // backpressured and for uncached AXI transactions.
    assign commit_req_ready_o = local_store_window_w ? 1'b1 :
                                uncached_commit_window_w
                                    ? 1'b1 : 1'b0;
    // A cacheable store is acknowledged directly when its registered
    // reservation is accepted into the committed-store buffer.  The existing
    // registered response state remains the fallback when the consumer is
    // backpressured and for uncached fabric transactions.
    assign commit_resp_valid_o = local_store_fire_w ||
                                 store_response_pending_r ||
                                 (state_r == STATE_COMMIT_RESP);
    assign commit_resp_data_o = local_store_fire_w
        ? 32'd0 : commit_response_data_r;
    assign commit_resp_error_o = local_store_fire_w
        ? !reservation_match_w : commit_response_error_r;
    assign clean_busy_o = clean_pending_r || maintenance_live_request_w ||
                          maintenance_state_active_w;
    assign clean_done_o = clean_done_r;
    assign maint_busy_o = clean_busy_o;
    assign maint_done_o = clean_done_o;

    // Main transaction lifecycle. AXI address/data channels may handshake
    // independently; a response is consumed only after its request completes.
    always @* begin
        state_next_w = state_r;
        case (state_r)
            STATE_IDLE: begin
                if (clean_start_w)
                    state_next_w = STATE_CLEAN_READ;
                else if (lookup_request_fire_w)
                    state_next_w = STATE_LOOKUP;
                else if (uncached_request_fire_w)
                    state_next_w = STATE_COMMIT_REQ;
            end
            STATE_LOOKUP: begin
                if (lookup_cancel_i)
                    state_next_w = STATE_IDLE;
                else if (lookup_hit_w && lookup_store_r &&
                         !reservation_room_w)
                    state_next_w = STATE_LOOKUP;
                else if (lookup_hit_w)
                    state_next_w = lookup_fast_fire_w
                        ? (lookup_request_fire_w ? STATE_LOOKUP : STATE_IDLE)
                        : STATE_LOOKUP_RESP;
                else if (store_reservation_valid_w || store_buffer_valid_r)
                    state_next_w = STATE_MISS_WAIT_STORES;
                else if (miss_victim_valid_w && miss_victim_dirty_w)
                    state_next_w = STATE_EVICT_REQ;
                else
                    state_next_w = STATE_REFILL_REQ;
            end
            STATE_MISS_WAIT_STORES: begin
                if (lookup_cancel_i)
                    state_next_w = STATE_IDLE;
                else if (!store_reservation_valid_w && !store_buffer_valid_r)
                    state_next_w = STATE_LOOKUP;
            end
            STATE_LOOKUP_RESP: begin
                if (lookup_cancel_i)
                    state_next_w = STATE_IDLE;
                else if (lookup_response_fire_w)
                    state_next_w = lookup_request_fire_w ? STATE_LOOKUP :
                                                           STATE_IDLE;
            end
            STATE_EVICT_REQ: begin
                if (write_channels_done_w)
                    state_next_w = STATE_EVICT_WAIT;
            end
            STATE_REFILL_REQ: begin
                if (refill_response_complete_w)
                    state_next_w = (lookup_cancel_i ||
                                    lookup_cancel_pending_r)
                        ? STATE_IDLE : STATE_LOOKUP_RESP;
                else if (axi_ar_fire_w)
                    state_next_w = STATE_REFILL_WAIT;
            end
            STATE_REFILL_WAIT: begin
                if (refill_response_complete_w)
                    state_next_w = (lookup_cancel_i ||
                                    lookup_cancel_pending_r)
                        ? STATE_IDLE : STATE_LOOKUP_RESP;
            end
            STATE_COMMIT_REQ: begin
                if (commit_write_r) begin
                    if (write_channels_done_w)
                        state_next_w = STATE_COMMIT_WAIT;
                end else if (axi_ar_fire_w) begin
                    state_next_w = STATE_COMMIT_WAIT;
                end
            end
            STATE_COMMIT_WAIT: begin
                if (uncached_response_fire_w)
                    state_next_w = STATE_COMMIT_RESP;
            end
            STATE_COMMIT_RESP: begin
                if (commit_resp_ready_i)
                    state_next_w = STATE_IDLE;
            end
            // The tag memories are synchronous.  CLASSIFY gives their outputs
            // a full cycle to settle and snapshots both range comparisons
            // before either result fans out into the metadata bit vectors.
            STATE_CLEAN_READ: state_next_w = STATE_CLEAN_CLASSIFY;
            STATE_CLEAN_CLASSIFY: state_next_w = STATE_CLEAN_CHECK0;
            STATE_CLEAN_CHECK0: begin
                if (clean_scan_needs_writeback_w)
                    state_next_w = STATE_CLEAN_WB_REQ;
                else
                    state_next_w = STATE_CLEAN_CHECK1;
            end
            STATE_CLEAN_CHECK1: begin
                if (clean_scan_needs_writeback_w)
                    state_next_w = STATE_CLEAN_WB_REQ;
                else if (clean_last_set_w)
                    state_next_w = STATE_IDLE;
                else
                    state_next_w = STATE_CLEAN_READ;
            end
            STATE_CLEAN_WB_REQ: begin
                if (write_channels_done_w)
                    state_next_w = STATE_CLEAN_WB_WAIT;
            end
            default: begin end
        endcase

        if (evict_response_fire_w) begin
            if (lookup_cancel_i || lookup_cancel_pending_r)
                state_next_w = STATE_IDLE;
            else if (axi_write_error_w)
                state_next_w = STATE_LOOKUP_RESP;
            else
                state_next_w = STATE_REFILL_REQ;
        end

        if (clean_response_fire_w) begin
            if (!clean_way_r)
                state_next_w = STATE_CLEAN_CHECK1;
            else if (clean_last_set_w)
                state_next_w = STATE_IDLE;
            else
                state_next_w = STATE_CLEAN_READ;
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            state_r <= STATE_IDLE;
        else
            state_r <= state_next_w;
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            miss_wait_retry_r <= 1'b0;
        else if (lookup_request_fire_w || lookup_cancel_i ||
                 (state_next_w == STATE_IDLE))
            miss_wait_retry_r <= 1'b0;
        else if ((state_r == STATE_LOOKUP) && !lookup_hit_w &&
                 (store_reservation_valid_w || store_buffer_valid_r))
            miss_wait_retry_r <= 1'b1;
    end

    // Synchronous lookup request metadata. Refill installation and maintenance
    // invalidation cannot coincide with a new lookup launch, so the valid-bit
    // snapshot observes the same set state as the tag/data RAM read.
    always @(posedge clk_i) begin
        if (lookup_request_fire_w ||
            ((state_r == STATE_MISS_WAIT_STORES) &&
             !store_reservation_valid_w && !store_buffer_valid_r)) begin
            if (lookup_request_fire_w) begin
            lookup_addr_r <= lookup_issue_addr_w;
            lookup_way0_valid_r <= valid_way0_r[request_index_w];
            lookup_way1_valid_r <= valid_way1_r[request_index_w];
            lookup_token_r <= lookup_issue_token_w;
            lookup_store_r <= lookup_issue_store_w;
            lookup_size_r <= lookup_issue_size_w;
            lookup_unsigned_r <= lookup_issue_unsigned_w;
            end
        end
    end

    // Miss/victim context is captured only after the synchronous lookup.
    always @(posedge clk_i) begin
        if ((state_r == STATE_LOOKUP) && !lookup_cancel_i && !lookup_hit_w) begin
            miss_way_r <= miss_victim_way_w;
            victim_tag_r <= miss_victim_tag_w;
            victim_line_r <= miss_victim_line_w;
            victim_dirty_r <= miss_victim_valid_w && miss_victim_dirty_w;
        end
    end

    // Eviction/refill progress and cancellation ownership.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            refill_beat_r <= {AXI_BEAT_W{1'b0}};
            refill_error_r <= 1'b0;
            lookup_cancel_pending_r <= 1'b0;
        end else begin
            if (lookup_request_fire_w)
                lookup_cancel_pending_r <= 1'b0;

            if ((state_r == STATE_LOOKUP) && !lookup_cancel_i && !lookup_hit_w) begin
                refill_beat_r <= {AXI_BEAT_W{1'b0}};
                refill_error_r <= 1'b0;
            end

            if (lookup_cancel_i &&
                ((state_r == STATE_EVICT_REQ) ||
                 (state_r == STATE_EVICT_WAIT) ||
                 (state_r == STATE_REFILL_REQ) ||
                 (state_r == STATE_REFILL_WAIT)))
                lookup_cancel_pending_r <= 1'b1;

            if (refill_response_fire_w && !lookup_cancel_i &&
                !lookup_cancel_pending_r) begin
                if (axi_read_error_w || refill_protocol_error_w)
                    refill_error_r <= 1'b1;
                if (!refill_response_complete_w)
                    refill_beat_r <= refill_beat_r + 1'b1;
            end

            if (state_next_w == STATE_IDLE)
                lookup_cancel_pending_r <= 1'b0;
        end
    end

    // Start write-channel progress from the local transition causes. Using
    // the encoded global state_next_w here allowed an unrelated same-cycle
    // lookup request and upstream queue arbitration to reach these registers.
    wire evict_write_start_w = (state_r == STATE_LOOKUP) &&
        !lookup_cancel_i && !lookup_hit_w &&
        !store_reservation_valid_w && !store_buffer_valid_r &&
        miss_victim_valid_w && miss_victim_dirty_w;
    wire clean_write_start_w =
        ((state_r == STATE_CLEAN_CHECK0) ||
         (state_r == STATE_CLEAN_CHECK1)) &&
        clean_scan_needs_writeback_w;
    wire write_start_w = evict_write_start_w || clean_write_start_w ||
        (uncached_request_fire_w && commit_req_write_i);

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            write_aw_pending_r <= 1'b0;
            write_w_done_r <= 1'b0;
            write_beat_r <= {AXI_BEAT_W{1'b0}};
        end else if (write_start_w) begin
            write_aw_pending_r <= 1'b1;
            write_w_done_r <= 1'b0;
            write_beat_r <= {AXI_BEAT_W{1'b0}};
        end else begin
            if (axi_aw_fire_w)
                write_aw_pending_r <= 1'b0;
            if (axi_w_fire_w) begin
                if (write_last_beat_w)
                    write_w_done_r <= 1'b1;
                else
                    write_beat_r <= write_beat_r + 1'b1;
            end
        end
    end

    // A refill is assembled in registers and installed atomically on success.
    always @(posedge clk_i) begin
        if ((state_r == STATE_LOOKUP) && !lookup_cancel_i && !lookup_hit_w)
            refill_line_r <= 128'd0;
        if (refill_response_fire_w && !lookup_cancel_i &&
            !lookup_cancel_pending_r) begin
            if (refill_beat_r == {AXI_BEAT_W{1'b0}})
                refill_line_r[63:0] <= axi_rdata_i;
            else
                refill_line_r[127:64] <= axi_rdata_i;
        end
    end

    // Lookup response payload is separate from response occupancy.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            lookup_response_data_r <= 32'd0;
            lookup_response_error_r <= 1'b0;
        end else begin
            if ((state_r == STATE_LOOKUP) && !lookup_cancel_i &&
                !lookup_fast_fire_w) begin
                if (lookup_hit_w) begin
                    lookup_response_data_r <= lookup_store_r ? 32'd0 :
                        format_load_word(lookup_hit_word_w,
                                         lookup_addr_r[1:0],
                                         lookup_size_r,
                                         lookup_unsigned_r);
                    lookup_response_error_r <= 1'b0;
                end else begin
                    lookup_response_error_r <= 1'b0;
                end
            end
            if (evict_response_fire_w && !lookup_cancel_i &&
                !lookup_cancel_pending_r && axi_write_error_w) begin
                lookup_response_data_r <= 32'd0;
                lookup_response_error_r <= 1'b1;
            end
            if (refill_response_fire_w && !lookup_cancel_i &&
                !lookup_cancel_pending_r && refill_response_complete_w) begin
                lookup_response_data_r <= lookup_store_r ? 32'd0 :
                    format_load_word(
                        select_word(completed_refill_line_w, resident_word_w),
                        lookup_addr_r[1:0], lookup_size_r,
                        lookup_unsigned_r);
                lookup_response_error_r <= refill_error_r ||
                    axi_read_error_w || refill_protocol_error_w;
            end
        end
    end

    wire refill_install_w = refill_response_fire_w &&
                            !lookup_cancel_i && !lookup_cancel_pending_r &&
                            refill_response_complete_w &&
                            refill_expected_last_w && axi_rlast_i &&
                            !refill_error_r && !axi_read_error_w;

    wire reservation_enqueue_w = lookup_store_r &&
        ((lookup_fast_fire_w && lookup_hit_w) ||
         (lookup_response_fire_w && !lookup_response_error_r));
    wire reservation_enqueue_way_w = lookup_fast_fire_w
        ? lookup_hit_way_w : prepared_way_r;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            reservation_count_r <= 3'd0;
            reservation_head_r <= 2'd0;
            reservation_tail_r <= 2'd0;
        end else if (lookup_cancel_i) begin
            // Reservations are ordered like the Store Queue.  Keep the
            // oldest entries that already belong to committed stores and
            // discard only speculative younger reservations.
            reservation_count_r <= cancel_keep_count_w;
            reservation_tail_r <= reservation_head_r +
                                  cancel_keep_count_w[1:0];
        end else begin
            if (reservation_enqueue_w) begin
                reservation_addr_r[reservation_tail_r] <= lookup_addr_r;
                reservation_way_r[reservation_tail_r] <=
                    reservation_enqueue_way_w;
                reservation_tail_r <= reservation_tail_r + 2'd1;
            end
            if (reservation_dequeue_w)
                reservation_head_r <= reservation_head_r + 2'd1;
            case ({reservation_enqueue_w, reservation_dequeue_w})
                2'b10: reservation_count_r <= reservation_count_r + 3'd1;
                2'b01: reservation_count_r <= reservation_count_r - 3'd1;
                default: begin end
            endcase
        end
    end

    always @(posedge clk_i) begin
        if ((state_r == STATE_LOOKUP) && lookup_hit_w)
            prepared_way_r <= lookup_hit_way_w;
        if (refill_install_w)
            prepared_way_r <= miss_way_r;
    end

    // Cacheable stores enter this queue only after COMMIT has excluded every
    // older exception/interrupt and presented the precise store request.  The
    // entry therefore survives younger-pipeline cancellation.  It is drained
    // one cycle later, while the lookup side may already be classifying the
    // following request.  Same-set hit/miss logic above observes the buffered
    // line so the RAM's read-during-write mode is not architecturally visible.
    assign store_buffer_drain_w = store_buffer_valid_r && !refill_install_w;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            store_buffer_valid_r <= 1'b0;
            store_buffer_addr_r <= 32'd0;
            store_buffer_way_r <= 1'b0;
            store_buffer_data_r <= 32'd0;
            store_buffer_wstrb_r <= 4'd0;
        end else if (local_store_fire_w && reservation_match_w) begin
            store_buffer_valid_r <= 1'b1;
            store_buffer_addr_r <= store_reservation_addr_w;
            store_buffer_way_r <= store_reservation_way_w;
            store_buffer_data_r <= commit_req_wdata_i;
            store_buffer_wstrb_r <= commit_req_wstrb_i;
        end else if (store_buffer_drain_w) begin
            store_buffer_valid_r <= 1'b0;
        end
    end

    // The array is read-first.  When a lookup and a buffered Store write
    // touch the same word on one edge, the next-cycle lookup must see that
    // Store even if a newer committed Store has replaced the buffer entry.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            store_drain_shadow_valid_r <= 1'b0;
        else
            store_drain_shadow_valid_r <= store_buffer_drain_w &&
                                          lookup_request_fire_w;
    end
    always @(posedge clk_i) begin
        if (store_buffer_drain_w && lookup_request_fire_w) begin
            store_drain_shadow_addr_r <= store_buffer_addr_r;
            store_drain_shadow_way_r <= store_buffer_way_r;
            store_drain_shadow_data_r <= store_buffer_data_r;
            store_drain_shadow_wstrb_r <= store_buffer_wstrb_r;
        end
    end

    // Uncached COMMIT request context for non-zero-cycle responses.
    always @(posedge clk_i) begin
        if (uncached_request_fire_w) begin
            commit_addr_r <= commit_req_addr_i;
            commit_write_r <= commit_req_write_i;
            commit_size_r <= commit_req_size_i;
            commit_wstrb_r <= commit_req_wstrb_i;
            commit_wdata_r <= commit_req_wdata_i;
        end
    end

    // COMMIT response payload is separate from response occupancy.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            commit_response_data_r <= 32'd0;
            commit_response_error_r <= 1'b0;
        end else begin
            if (local_store_fire_w) begin
                commit_response_data_r <= 32'd0;
                commit_response_error_r <= !reservation_match_w;
            end
            if (uncached_response_fire_w) begin
                commit_response_data_r <= uncached_read_response_fire_w
                    ? uncached_read_data_w : 32'd0;
                commit_response_error_r <= uncached_read_response_fire_w
                    ? (axi_read_error_w || !axi_rlast_i)
                    : axi_write_error_w;
            end
        end
    end

    // Cache-hit store responses normally complete in their request cycle.
    // If the receiver is not ready, this local occupancy bit retains the
    // already-registered payload without forcing the cache FSM to wait in a
    // response state or feeding response-ready back into lookup turnover.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            store_response_pending_r <= 1'b0;
        end else if (local_store_fire_w) begin
            store_response_pending_r <= !commit_resp_ready_i;
        end else if (store_response_pending_r && commit_resp_ready_i) begin
            store_response_pending_r <= 1'b0;
        end
    end

    // One queued maintenance command prevents a FENCE request from being lost
    // behind an MMIO range operation (or vice versa).  The controller prevents
    // multiple software commands; a simultaneous/queued FENCE conservatively
    // expands the request to a whole-cache clean.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            clean_pending_r <= 1'b0;
            clean_pending_clean_r <= 1'b0;
            clean_pending_invalidate_r <= 1'b0;
            clean_pending_addr_r <= 32'd0;
            clean_pending_size_r <= 32'd0;
            clean_done_r <= 1'b0;
        end else begin
            clean_done_r <= clean_finish_w;

            if (clean_start_from_pending_w) begin
                clean_pending_r <= 1'b0;
            end

            if (maintenance_state_active_w && maintenance_live_request_w) begin
                if (!clean_pending_r) begin
                    clean_pending_r <= 1'b1;
                    clean_pending_clean_r <= maintenance_live_clean_w;
                    clean_pending_invalidate_r <=
                        maintenance_live_invalidate_w;
                    clean_pending_addr_r <= maintenance_live_addr_w;
                    clean_pending_size_r <= maintenance_live_size_w;
                end else begin
                    clean_pending_clean_r <= clean_pending_clean_r ||
                                             maintenance_live_clean_w;
                    clean_pending_invalidate_r <=
                        clean_pending_invalidate_r ||
                        maintenance_live_invalidate_w;
                    if ((clean_pending_size_r == 32'd0) ||
                        (maintenance_live_size_w == 32'd0)) begin
                        clean_pending_addr_r <= 32'd0;
                        clean_pending_size_r <= 32'd0;
                    end
                end
            end else if (clean_start_from_pending_w &&
                         maintenance_live_request_w) begin
                clean_pending_r <= 1'b1;
                clean_pending_clean_r <= maintenance_live_clean_w;
                clean_pending_invalidate_r <=
                    maintenance_live_invalidate_w;
                clean_pending_addr_r <= maintenance_live_addr_w;
                clean_pending_size_r <= maintenance_live_size_w;
            end
        end
    end

    // Active operation payload is distinct from queue occupancy and remains
    // stable throughout the serialized scan/writeback lifecycle.
    always @(posedge clk_i) begin
        if (clean_start_from_pending_w) begin
            clean_operation_clean_r <= clean_pending_clean_r;
            clean_operation_invalidate_r <= clean_pending_invalidate_r;
            clean_operation_addr_r <= clean_pending_addr_r;
            clean_operation_size_r <= clean_pending_size_r;
        end else if (clean_start_from_live_w) begin
            clean_operation_clean_r <= maintenance_live_clean_w;
            clean_operation_invalidate_r <= maintenance_live_invalidate_w;
            clean_operation_addr_r <= maintenance_live_addr_w;
            clean_operation_size_r <= maintenance_live_size_w;
        end
    end

    // Clean scan address/way/progress state.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            clean_set_r <= {INDEX_W{1'b0}};
            clean_way_r <= 1'b0;
        end else begin
            if (clean_start_w) begin
                clean_set_r <= {INDEX_W{1'b0}};
                clean_way_r <= 1'b0;
            end
            if ((state_r == STATE_CLEAN_CHECK0) &&
                clean_scan_needs_writeback_w) begin
                clean_way_r <= 1'b0;
            end
            if ((state_r == STATE_CLEAN_CHECK1) &&
                clean_scan_needs_writeback_w) begin
                clean_way_r <= 1'b1;
            end
            if (clean_response_fire_w) begin
                if (clean_way_r && !clean_last_set_w)
                    clean_set_r <= clean_set_r + 1'b1;
            end else if ((state_r == STATE_CLEAN_CHECK1) &&
                         !clean_scan_needs_writeback_w &&
                         !clean_last_set_w) begin
                clean_set_r <= clean_set_r + 1'b1;
            end
        end
    end

    // Range qualification is invariant while the two ways of one set are
    // processed.  Registering it separates tag-RAM Tco plus address compare
    // from the 128-way dynamic metadata update/decode cone.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            clean_way0_range_hit_r <= 1'b0;
            clean_way1_range_hit_r <= 1'b0;
        end else if (state_r == STATE_CLEAN_CLASSIFY) begin
            clean_way0_range_hit_r <= clean_way0_range_hit_w;
            clean_way1_range_hit_r <= clean_way1_range_hit_w;
        end
    end

    // Dirty line payload for the serialized clean writeback.
    always @(posedge clk_i) begin
        if (((state_r == STATE_CLEAN_CHECK0) ||
             (state_r == STATE_CLEAN_CHECK1)) &&
            clean_scan_needs_writeback_w) begin
            clean_tag_r <= clean_scan_tag_w;
            clean_line_r <= clean_scan_line_w;
        end
    end

    wire miss_retry_read_w = (state_r == STATE_MISS_WAIT_STORES) &&
                             !store_reservation_valid_w &&
                             !store_buffer_valid_r;
    wire array_read_en_w = lookup_request_fire_w || miss_retry_read_w ||
                           (state_r == STATE_CLEAN_READ);
    wire [INDEX_W-1:0] array_read_index_w =
        (state_r == STATE_CLEAN_READ) ? clean_set_r :
        miss_retry_read_w ? resident_index_w : request_index_w;
    wire array_write_way_w = store_buffer_drain_w
        ? store_buffer_way_r : miss_way_r;
    wire [INDEX_W-1:0] array_write_index_w = store_buffer_drain_w
        ? store_buffer_addr_r[OFFSET_W + INDEX_W - 1:OFFSET_W]
        : resident_index_w;
    reg [127:0] store_buffer_array_line_w;
    reg [15:0] store_buffer_array_byte_en_w;
    always @* begin
        store_buffer_array_line_w = 128'd0;
        store_buffer_array_byte_en_w = 16'd0;
        case (store_buffer_addr_r[OFFSET_W-1:2])
            2'd0: begin
                store_buffer_array_line_w[31:0] = store_buffer_data_r;
                store_buffer_array_byte_en_w[3:0] = store_buffer_wstrb_r;
            end
            2'd1: begin
                store_buffer_array_line_w[63:32] = store_buffer_data_r;
                store_buffer_array_byte_en_w[7:4] = store_buffer_wstrb_r;
            end
            2'd2: begin
                store_buffer_array_line_w[95:64] = store_buffer_data_r;
                store_buffer_array_byte_en_w[11:8] = store_buffer_wstrb_r;
            end
            default: begin
                store_buffer_array_line_w[127:96] = store_buffer_data_r;
                store_buffer_array_byte_en_w[15:12] = store_buffer_wstrb_r;
            end
        endcase
    end
    wire [127:0] array_write_line_w = store_buffer_drain_w
        ? store_buffer_array_line_w : completed_refill_line_w;
    wire [15:0] array_write_byte_en_w = store_buffer_drain_w
        ? store_buffer_array_byte_en_w : 16'hffff;
    wire array_data_write_w = store_buffer_drain_w || refill_install_w;

    edrv32_cache_array #(
        .SET_COUNT(SET_COUNT),
        .INDEX_W(INDEX_W),
        .TAG_W(TAG_W)
    ) u_way0_array (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),

        // Shared synchronous port for lookup and maintenance reads.
        .rd_en_i(array_read_en_w),
        .rd_index_i(array_read_index_w),
        .rd_tag_o(way0_tag_w),
        .rd_line_o(way0_line_w),

        // Refill tag write and refill/store data write ports.
        .tag_wr_en_i(refill_install_w && !miss_way_r),
        .tag_wr_index_i(resident_index_w),
        .tag_wr_data_i(resident_tag_w),
        .data_wr_en_i(array_data_write_w && !array_write_way_w),
        .data_wr_index_i(array_write_index_w),
        .data_wr_line_i(array_write_line_w),
        .data_wr_byte_en_i(array_write_byte_en_w)
    );

    edrv32_cache_array #(
        .SET_COUNT(SET_COUNT),
        .INDEX_W(INDEX_W),
        .TAG_W(TAG_W)
    ) u_way1_array (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),

        // Shared synchronous port for lookup and maintenance reads.
        .rd_en_i(array_read_en_w),
        .rd_index_i(array_read_index_w),
        .rd_tag_o(way1_tag_w),
        .rd_line_o(way1_line_w),

        // Refill tag write and refill/store data write ports.
        .tag_wr_en_i(refill_install_w && miss_way_r),
        .tag_wr_index_i(resident_index_w),
        .tag_wr_data_i(resident_tag_w),
        .data_wr_en_i(array_data_write_w && array_write_way_w),
        .data_wr_index_i(array_write_index_w),
        .data_wr_line_i(array_write_line_w),
        .data_wr_byte_en_i(array_write_byte_en_w)
    );

    // Valid bits own visibility. Maintenance invalidation is the only path
    // other than reset that clears a resident entry.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            valid_way0_r <= {SET_COUNT{1'b0}};
            valid_way1_r <= {SET_COUNT{1'b0}};
        end else begin
            if (refill_install_w) begin
                if (miss_way_r)
                    valid_way1_r[resident_index_w] <= 1'b1;
                else
                    valid_way0_r[resident_index_w] <= 1'b1;
            end
            if (clean_metadata_apply_w && clean_operation_invalidate_r) begin
                if (clean_metadata_way_w)
                    valid_way1_r[clean_set_r] <= 1'b0;
                else
                    valid_way0_r[clean_set_r] <= 1'b0;
            end
        end
    end

    // Dirty state is separate from valid state and changes at COMMIT, refill,
    // successful eviction replacement, or successful clean writeback.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            dirty_way0_r <= {SET_COUNT{1'b0}};
            dirty_way1_r <= {SET_COUNT{1'b0}};
        end else begin
            if (refill_install_w) begin
                if (miss_way_r)
                    dirty_way1_r[resident_index_w] <= 1'b0;
                else
                    dirty_way0_r[resident_index_w] <= 1'b0;
            end
            if (store_buffer_drain_w) begin
                if (store_buffer_way_r)
                    dirty_way1_r[array_write_index_w] <= 1'b1;
                else
                    dirty_way0_r[array_write_index_w] <= 1'b1;
            end
            if (clean_metadata_apply_w &&
                (clean_operation_clean_r ||
                 clean_operation_invalidate_r)) begin
                if (clean_metadata_way_w)
                    dirty_way1_r[clean_set_r] <= 1'b0;
                else
                    dirty_way0_r[clean_set_r] <= 1'b0;
            end
        end
    end

    // Exact LRU for two ways: touching one way names the other as victim.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            replacement_way_r <= {SET_COUNT{1'b0}};
        end else begin
            if (store_buffer_drain_w)
                replacement_way_r[array_write_index_w] <=
                    ~store_buffer_way_r;
            // A simultaneous lookup is younger than the draining store, so
            // its touch must be the final LRU update for this set.
            if ((state_r == STATE_LOOKUP) && lookup_hit_w && !lookup_cancel_i)
                replacement_way_r[resident_index_w] <= ~lookup_hit_way_w;
            if (refill_install_w)
                replacement_way_r[resident_index_w] <= ~miss_way_r;
        end
    end

    // Registered uncached fields are intentionally retained as visible
    // transaction context for waveform/debug inspection.
    wire unused_commit_context_w = ^{commit_addr_r, commit_write_r,
        commit_size_r, commit_wstrb_r, commit_wdata_r, victim_dirty_r,
        clean_scan_dirty_w};

endmodule
