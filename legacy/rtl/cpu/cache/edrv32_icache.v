// ============================================================================
// File        : edrv32_icache.v
// Description : Pipelined-hit, blocking-miss two-way instruction cache.
// Notes       : 4 KiB / 16-byte lines / two ways is the competition profile.
//               Tag/data storage is synchronous-read. A hit lookup may retire
//               into the response register while the next lookup is accepted,
//               giving an initiation interval of one cycle after warm-up.
//               Misses remain single-outstanding and strictly ordered.  The
//               memory-facing port is AXI4 directly: a 16-byte refill is one
//               two-beat 64-bit burst, while uncached fetches are one 32-bit
//               narrow transfer.
// ============================================================================
`include "edrv32_axi4.vh"

module edrv32_icache #(
    parameter integer FETCH_WIDE = 0,
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
    input  wire        clk_i,
    input  wire        rst_n_i,

    input  wire        lookup_req_valid_i,
    output wire        lookup_req_ready_o,
    input  wire [31:0] lookup_req_addr_i,
    input  wire        lookup_req_cacheable_i,
    input  wire        lookup_req_executable_i,
    output wire        lookup_resp_valid_o,
    input  wire        lookup_resp_ready_i,
    output wire [31:0] lookup_resp_data_o,
    output wire [31:0] lookup_resp_upper_o,
    output wire        lookup_resp_error_o,
    output wire        lookup_preview_valid_o,
    output wire [31:0] lookup_preview_addr_o,
    output wire [31:0] lookup_preview_data_o,
    output wire [31:0] lookup_preview_upper_o,

    input  wire        invalidate_i,

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

    output wire        miss_o,
    output wire        refill_busy_o
);

    localparam [2:0] STATE_IDLE        = 3'd0;
    localparam [2:0] STATE_REFILL_REQ  = 3'd1;
    localparam [2:0] STATE_REFILL_WAIT = 3'd2;
    localparam [2:0] STATE_BYPASS_REQ  = 3'd3;
    localparam [2:0] STATE_BYPASS_WAIT = 3'd4;
    localparam integer AXI_BEAT_BYTES = `AXI_DATA_W / 8;
    localparam integer AXI_BEAT_COUNT = LINE_BYTES / AXI_BEAT_BYTES;
    localparam integer AXI_BEAT_W = $clog2(AXI_BEAT_COUNT);
    localparam [AXI_BEAT_W-1:0] LAST_AXI_BEAT = AXI_BEAT_COUNT - 1;
    localparam [`AXI_LEN_W-1:0] REFILL_AXLEN = AXI_BEAT_COUNT - 1;

    generate
        if ((WAYS != 2) || (LINE_BYTES != 16) || (`AXI_DATA_W != 64) ||
            ((LINE_COUNT % WAYS) != 0)) begin : gen_bad_geometry
            edrv32_icache_requires_two_way_16byte_lines_and_64bit_axi
                u_static_assert ();
        end
    endgenerate

    // The lookup register is independent from the blocking miss engine.
    reg lookup_valid_r;
    reg [31:0] lookup_addr_r;
    reg lookup_cacheable_r;
    reg lookup_executable_r;
    reg [1:0] lookup_valid_snapshot_r;

    // These are the only externally visible response sources.
    reg response_valid_r;
    reg [31:0] response_data_r;
    reg [31:0] response_upper_r;
    reg response_error_r;

    reg [2:0] state_r;
    reg [SET_COUNT-1:0] valid_way0_r;
    reg [SET_COUNT-1:0] valid_way1_r;
    reg [SET_COUNT-1:0] replacement_way_r;

    reg [AXI_BEAT_W-1:0] refill_beat_r;
    reg refill_way_r;
    reg refill_error_r;
    reg refill_discard_r;
    reg [127:0] refill_line_r;

    wire [INDEX_W-1:0] request_index_w =
        lookup_req_addr_i[OFFSET_W + INDEX_W - 1:OFFSET_W];
    wire [INDEX_W-1:0] resident_index_w =
        lookup_addr_r[OFFSET_W + INDEX_W - 1:OFFSET_W];
    wire [WORD_W-1:0] resident_word_w = lookup_addr_r[OFFSET_W-1:2];
    wire [TAG_W-1:0] resident_tag_w =
        lookup_addr_r[31:OFFSET_W + INDEX_W];

    wire [TAG_W-1:0] way0_tag_w;
    wire [TAG_W-1:0] way1_tag_w;
    wire [127:0] way0_line_w;
    wire [127:0] way1_line_w;
    wire way0_hit_w = lookup_valid_snapshot_r[0] &&
                      (way0_tag_w == resident_tag_w);
    wire way1_hit_w = lookup_valid_snapshot_r[1] &&
                      (way1_tag_w == resident_tag_w);
    wire lookup_hit_w = way0_hit_w || way1_hit_w;
    wire lookup_hit_way_w = way1_hit_w;
    wire [127:0] lookup_hit_line_w = way0_hit_w ? way0_line_w : way1_line_w;

    reg [31:0] lookup_hit_word_w;
    always @* begin
        case (resident_word_w)
            2'd0: lookup_hit_word_w = lookup_hit_line_w[31:0];
            2'd1: lookup_hit_word_w = lookup_hit_line_w[63:32];
            2'd2: lookup_hit_word_w = lookup_hit_line_w[95:64];
            default: lookup_hit_word_w = lookup_hit_line_w[127:96];
        endcase
    end

    reg [31:0] lookup_hit_upper_w;
    reg [31:0] refill_upper_w;
    always @(*) begin
        lookup_hit_upper_w = 32'd0;
        refill_upper_w = 32'd0;
        if (FETCH_WIDE != 0) begin
            case (resident_word_w)
                2'd0: begin
                    lookup_hit_upper_w = lookup_hit_line_w[63:32];
                    refill_upper_w = completed_refill_line_w[63:32];
                end
                2'd1: begin
                    lookup_hit_upper_w = lookup_hit_line_w[95:64];
                    refill_upper_w = completed_refill_line_w[95:64];
                end
                2'd2: begin
                    lookup_hit_upper_w = lookup_hit_line_w[127:96];
                    refill_upper_w = completed_refill_line_w[127:96];
                end
                default: begin end
            endcase
        end
    end

    wire victim_way_w = !lookup_valid_snapshot_r[0] ? 1'b0 :
                        !lookup_valid_snapshot_r[1] ? 1'b1 :
                        replacement_way_r[resident_index_w];

    wire response_pop_w = response_valid_r && lookup_resp_ready_i;
    wire response_slot_ready_w = !response_valid_r || lookup_resp_ready_i;
    wire lookup_hit_complete_w = (state_r == STATE_IDLE) && lookup_valid_r &&
                                 lookup_executable_r && lookup_cacheable_r &&
                                 lookup_hit_w && !invalidate_i &&
                                 response_slot_ready_w;
    wire lookup_fault_complete_w = (state_r == STATE_IDLE) && lookup_valid_r &&
                                   !lookup_executable_r &&
                                   response_slot_ready_w;
    wire lookup_fast_complete_w = lookup_hit_complete_w ||
                                  lookup_fault_complete_w;
    wire lookup_miss_start_w = (state_r == STATE_IDLE) && lookup_valid_r &&
                               lookup_executable_r && lookup_cacheable_r &&
                               (!lookup_hit_w || invalidate_i);
    wire lookup_bypass_start_w = (state_r == STATE_IDLE) && lookup_valid_r &&
                                 lookup_executable_r && !lookup_cacheable_r;

    // A known hit/fault can leave on the same edge that starts the next RAM
    // read. A miss never accepts a younger request, preserving response order.
    assign lookup_req_ready_o = !invalidate_i && (state_r == STATE_IDLE) &&
        (!lookup_valid_r || lookup_fast_complete_w);
    wire lookup_request_fire_w = lookup_req_valid_i && lookup_req_ready_o;

    assign lookup_resp_valid_o = response_valid_r;
    assign lookup_resp_data_o = response_data_r;
    assign lookup_resp_upper_o = response_upper_r;
    assign lookup_resp_error_o = response_error_r;
    // A cache hit is known one register boundary before its normal response.
    // This preview cannot commit or replace the ordered response channel.
    assign lookup_preview_valid_o = lookup_hit_complete_w;
    assign lookup_preview_addr_o = lookup_addr_r;
    assign lookup_preview_data_o = lookup_hit_word_w;
    assign lookup_preview_upper_o = lookup_hit_upper_w;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            lookup_valid_r <= 1'b0;
        else if (lookup_request_fire_w)
            lookup_valid_r <= 1'b1;
        else if (lookup_fast_complete_w || lookup_miss_start_w ||
                 lookup_bypass_start_w)
            lookup_valid_r <= 1'b0;
    end

    always @(posedge clk_i) begin
        if (lookup_request_fire_w) begin
            lookup_addr_r <= lookup_req_addr_i;
            lookup_cacheable_r <= lookup_req_cacheable_i;
            lookup_executable_r <= lookup_req_executable_i;
            lookup_valid_snapshot_r <= {
                valid_way1_r[request_index_w],
                valid_way0_r[request_index_w]
            };
        end
    end

    // ------------------------------------------------------------------------
    // Blocking miss/bypass engine
    // ------------------------------------------------------------------------
    wire axi_ar_fire_w = axi_arvalid_o && axi_arready_i;
    wire refill_response_window_w = (state_r == STATE_REFILL_WAIT) ||
                                    ((state_r == STATE_REFILL_REQ) &&
                                     axi_ar_fire_w);
    wire refill_expected_last_w = (refill_beat_r == LAST_AXI_BEAT);
    wire refill_last_response_ready_w = !refill_expected_last_w ||
                                        response_slot_ready_w;
    wire refill_response_fire_w = refill_response_window_w &&
                                  axi_rvalid_i &&
                                  refill_last_response_ready_w;
    wire refill_response_complete_w = refill_response_fire_w &&
                                      (refill_expected_last_w || axi_rlast_i);
    wire bypass_request_w = (state_r == STATE_BYPASS_REQ);
    wire bypass_request_fire_w = bypass_request_w && axi_arready_i;
    wire bypass_response_window_w = (state_r == STATE_BYPASS_WAIT) ||
                                    ((state_r == STATE_BYPASS_REQ) &&
                                     bypass_request_fire_w);
    wire bypass_response_fire_w = bypass_response_window_w &&
                                  axi_rvalid_i &&
                                  response_slot_ready_w;

    wire axi_read_error_w = (axi_rresp_i != `AXI_RESP_OKAY) ||
                            (axi_rid_i != {`AXI_ID_W{1'b0}});
    wire refill_protocol_error_w = axi_rlast_i != refill_expected_last_w;
    wire bypass_lane_high_w = lookup_addr_r[2];
    wire [31:0] bypass_rdata_w = bypass_lane_high_w
        ? axi_rdata_i[63:32] : axi_rdata_i[31:0];

    assign axi_arid_o = {`AXI_ID_W{1'b0}};
    assign axi_araddr_o = bypass_request_w
        ? {lookup_addr_r[31:2], 2'b00}
        : {lookup_addr_r[31:OFFSET_W], {OFFSET_W{1'b0}}};
    assign axi_arlen_o = bypass_request_w
        ? {`AXI_LEN_W{1'b0}} : REFILL_AXLEN;
    assign axi_arsize_o = bypass_request_w ? `AXI_SIZE_4B : `AXI_SIZE_8B;
    assign axi_arburst_o = `AXI_BURST_INCR;
    assign axi_arvalid_o = (state_r == STATE_REFILL_REQ) || bypass_request_w;
    assign axi_rready_o =
        (refill_response_window_w && refill_last_response_ready_w) ||
        (bypass_response_window_w && response_slot_ready_w);

    assign miss_o = lookup_miss_start_w && !invalidate_i;
    assign refill_busy_o = (state_r == STATE_REFILL_REQ) ||
                           (state_r == STATE_REFILL_WAIT);

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= STATE_IDLE;
        end else begin
            case (state_r)
                STATE_IDLE: begin
                    if (lookup_miss_start_w)
                        state_r <= STATE_REFILL_REQ;
                    else if (lookup_bypass_start_w)
                        state_r <= STATE_BYPASS_REQ;
                end
                STATE_REFILL_REQ: begin
                    if (refill_response_complete_w)
                        state_r <= STATE_IDLE;
                    else if (axi_ar_fire_w)
                        state_r <= STATE_REFILL_WAIT;
                end
                STATE_REFILL_WAIT: begin
                    if (refill_response_complete_w)
                        state_r <= STATE_IDLE;
                end
                STATE_BYPASS_REQ: begin
                    if (bypass_response_fire_w)
                        state_r <= STATE_IDLE;
                    else if (bypass_request_fire_w)
                        state_r <= STATE_BYPASS_WAIT;
                end
                STATE_BYPASS_WAIT: begin
                    if (bypass_response_fire_w)
                        state_r <= STATE_IDLE;
                end
                default: state_r <= STATE_IDLE;
            endcase
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            refill_beat_r <= {AXI_BEAT_W{1'b0}};
            refill_way_r <= 1'b0;
            refill_error_r <= 1'b0;
            refill_discard_r <= 1'b0;
        end else begin
            if (lookup_request_fire_w)
                refill_discard_r <= 1'b0;
            if (lookup_miss_start_w) begin
                refill_beat_r <= {AXI_BEAT_W{1'b0}};
                refill_way_r <= victim_way_w;
                refill_error_r <= 1'b0;
            end
            if (refill_response_fire_w) begin
                if (axi_read_error_w || refill_protocol_error_w)
                    refill_error_r <= 1'b1;
                if (!refill_response_complete_w)
                    refill_beat_r <= refill_beat_r + 1'b1;
            end
            if (invalidate_i && (state_r != STATE_IDLE))
                refill_discard_r <= 1'b1;
        end
    end

    always @(posedge clk_i) begin
        if (refill_response_fire_w) begin
            if (refill_beat_r == {AXI_BEAT_W{1'b0}})
                refill_line_r[63:0] <= axi_rdata_i;
            else
                refill_line_r[127:64] <= axi_rdata_i;
        end
    end

    reg [127:0] completed_refill_line_w;
    always @* begin
        completed_refill_line_w = refill_line_r;
        if (refill_beat_r == {AXI_BEAT_W{1'b0}})
            completed_refill_line_w[63:0] = axi_rdata_i;
        else
            completed_refill_line_w[127:64] = axi_rdata_i;
    end

    wire refill_response_push_w = refill_response_complete_w;
    wire response_push_w = lookup_fast_complete_w ||
                           refill_response_push_w ||
                           bypass_response_fire_w;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            response_valid_r <= 1'b0;
        else if (response_push_w)
            response_valid_r <= 1'b1;
        else if (response_pop_w)
            response_valid_r <= 1'b0;
    end

    always @(posedge clk_i) begin
        if (lookup_hit_complete_w) begin
            response_data_r <= lookup_hit_word_w;
            response_upper_r <= lookup_hit_upper_w;
            response_error_r <= 1'b0;
        end else if (lookup_fault_complete_w) begin
            response_data_r <= 32'd0;
            response_upper_r <= 32'd0;
            response_error_r <= 1'b1;
        end else if (bypass_response_fire_w) begin
            response_data_r <= ((FETCH_WIDE != 0) && (axi_read_error_w || !axi_rlast_i))
                ? 32'd0 : bypass_rdata_w;
            response_upper_r <= 32'd0;
            response_error_r <= axi_read_error_w || !axi_rlast_i;
        end else if (refill_response_push_w) begin
            response_upper_r <= refill_upper_w;
            case (resident_word_w)
                2'd0: response_data_r <= completed_refill_line_w[31:0];
                2'd1: response_data_r <= completed_refill_line_w[63:32];
                2'd2: response_data_r <= completed_refill_line_w[95:64];
                default: response_data_r <= completed_refill_line_w[127:96];
            endcase
            response_error_r <= refill_error_r || axi_read_error_w ||
                                refill_protocol_error_w;
            // A short/error refill can leave the upper line payload unwritten.
            // Its fault must be visible without an unknown instruction length.
            if ((FETCH_WIDE != 0) &&
                (refill_error_r || axi_read_error_w || refill_protocol_error_w)) begin
                response_data_r <= 32'd0;
                response_upper_r <= 32'd0;
            end
        end
    end

    wire refill_install_w = refill_response_push_w &&
                            refill_expected_last_w && axi_rlast_i &&
                            !refill_error_r && !axi_read_error_w &&
                            !refill_discard_r && !invalidate_i;

    edrv32_cache_array #(
        .SET_COUNT(SET_COUNT), .INDEX_W(INDEX_W), .TAG_W(TAG_W)
    ) u_way0_array (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .rd_en_i(lookup_request_fire_w), .rd_index_i(request_index_w),
        .rd_tag_o(way0_tag_w), .rd_line_o(way0_line_w),
        .tag_wr_en_i(refill_install_w && !refill_way_r),
        .tag_wr_index_i(resident_index_w), .tag_wr_data_i(resident_tag_w),
        .data_wr_en_i(refill_install_w && !refill_way_r),
        .data_wr_index_i(resident_index_w),
        .data_wr_line_i(completed_refill_line_w),
        .data_wr_byte_en_i(16'hffff)
    );

    edrv32_cache_array #(
        .SET_COUNT(SET_COUNT), .INDEX_W(INDEX_W), .TAG_W(TAG_W)
    ) u_way1_array (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .rd_en_i(lookup_request_fire_w), .rd_index_i(request_index_w),
        .rd_tag_o(way1_tag_w), .rd_line_o(way1_line_w),
        .tag_wr_en_i(refill_install_w && refill_way_r),
        .tag_wr_index_i(resident_index_w), .tag_wr_data_i(resident_tag_w),
        .data_wr_en_i(refill_install_w && refill_way_r),
        .data_wr_index_i(resident_index_w),
        .data_wr_line_i(completed_refill_line_w),
        .data_wr_byte_en_i(16'hffff)
    );

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            valid_way0_r <= {SET_COUNT{1'b0}};
            valid_way1_r <= {SET_COUNT{1'b0}};
        end else if (invalidate_i) begin
            valid_way0_r <= {SET_COUNT{1'b0}};
            valid_way1_r <= {SET_COUNT{1'b0}};
        end else if (refill_install_w) begin
            if (refill_way_r)
                valid_way1_r[resident_index_w] <= 1'b1;
            else
                valid_way0_r[resident_index_w] <= 1'b1;
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            replacement_way_r <= {SET_COUNT{1'b0}};
        else if (invalidate_i)
            replacement_way_r <= {SET_COUNT{1'b0}};
        else begin
            if (lookup_hit_complete_w)
                replacement_way_r[resident_index_w] <= ~lookup_hit_way_w;
            if (refill_install_w)
                replacement_way_r[resident_index_w] <= ~refill_way_r;
        end
    end

endmodule
