// ============================================================================
// File        : axi_mem_model.sv
// Author      : Edward ZC
// Description : AXI4 memory BFM for DMA-engine verification. Supports
//               multiple read/write bursts, interleaved R responses, reordered
//               B responses, deterministic backpressure and error injection.
// Notes       : Simulation only. Testbenches may prefill/inspect `store`
//               through hierarchical references. The data bus is the project
//               64-bit baseline; aligned 4-byte narrow and 8-byte INCR beats
//               are supported.
// ============================================================================
`include "edrv32_axi4.vh"

module axi_mem_model #(
    parameter ID_W = 4,
    parameter [31:0] BASE = 32'h0000_0000,
    parameter [31:0] SIZE_BYTES = 32'h0001_0000,
    parameter [31:0] SEED = 32'h1,
    parameter MAX_OUTSTANDING = 16
)(
    // --- Clock and reset ---
    input  wire                     clk,
    input  wire                     rst_n,

    // --- Runtime fault injection ---
    input  wire [31:0]              err_addr_i,

    // --- AXI write address channel ---
    input  wire [ID_W-1:0]          awid_i,
    input  wire [31:0]              awaddr_i,
    input  wire [`AXI_LEN_W-1:0]    awlen_i,
    input  wire [`AXI_SIZE_W-1:0]   awsize_i,
    input  wire [`AXI_BURST_W-1:0]  awburst_i,
    input  wire                     awvalid_i,
    output wire                     awready_o,

    // --- AXI write data channel ---
    input  wire [`AXI_DATA_W-1:0]   wdata_i,
    input  wire [`AXI_STRB_W-1:0]   wstrb_i,
    input  wire                     wlast_i,
    input  wire                     wvalid_i,
    output wire                     wready_o,

    // --- AXI write response channel ---
    output wire [ID_W-1:0]          bid_o,
    output wire [`AXI_RESP_W-1:0]   bresp_o,
    output wire                     bvalid_o,
    input  wire                     bready_i,

    // --- AXI read address channel ---
    input  wire [ID_W-1:0]          arid_i,
    input  wire [31:0]              araddr_i,
    input  wire [`AXI_LEN_W-1:0]    arlen_i,
    input  wire [`AXI_SIZE_W-1:0]   arsize_i,
    input  wire [`AXI_BURST_W-1:0]  arburst_i,
    input  wire                     arvalid_i,
    output wire                     arready_o,

    // --- AXI read data channel ---
    output wire [ID_W-1:0]          rid_o,
    output wire [`AXI_DATA_W-1:0]   rdata_o,
    output wire [`AXI_RESP_W-1:0]   rresp_o,
    output wire                     rlast_o,
    output wire                     rvalid_o,
    input  wire                     rready_i
);

    localparam WORDS = SIZE_BYTES / `AXI_STRB_W;
    localparam SLOT_W = (MAX_OUTSTANDING <= 1) ? 1 : $clog2(MAX_OUTSTANDING);
    localparam [SLOT_W-1:0] LAST_SLOT =
        MAX_OUTSTANDING[SLOT_W-1:0] - {{(SLOT_W-1){1'b0}}, 1'b1};

    reg [`AXI_DATA_W-1:0] store [0:WORDS-1];
    reg [31:0] lcg_r;
    integer pi;

    initial begin
        for (pi = 0; pi < WORDS; pi = pi + 1)
            store[pi] = {BASE, 32'h0} ^ {32'hC0DE_0000, pi[31:0]} ^
                        64'h0123_4567_89AB_CDEF;
    end

    function [31:0] lcg32;
        input [31:0] value;
        begin
            lcg32 = value * 32'h41C6_4E6D + 32'h0000_3039;
        end
    endfunction

    // ------------------------------------------------------------------
    // Read request slots and interleaved response scheduler
    // ------------------------------------------------------------------
    reg                    rd_valid_r [0:MAX_OUTSTANDING-1];
    reg [ID_W-1:0]         rd_id_r    [0:MAX_OUTSTANDING-1];
    reg [31:0]             rd_addr_r  [0:MAX_OUTSTANDING-1];
    reg [`AXI_LEN_W:0]     rd_beats_r [0:MAX_OUTSTANDING-1];
    reg [`AXI_SIZE_W-1:0]  rd_size_r  [0:MAX_OUTSTANDING-1];
    reg                    rd_cmd_err_r [0:MAX_OUTSTANDING-1];
    reg [SLOT_W-1:0]       rd_rr_r;

    reg                    rd_free_found_r;
    reg [SLOT_W-1:0]       rd_free_slot_r;
    reg                    rd_pick_found_r;
    reg [SLOT_W-1:0]       rd_pick_slot_r;
    integer                rd_active_count_r;
    integer                max_read_outstanding;
    integer                r_interleave_events;
    reg                    last_rid_valid_r;
    reg [ID_W-1:0]         last_rid_r;
    integer rd_scan;
    integer rd_candidate;

    always @* begin
        rd_free_found_r = 1'b0;
        rd_free_slot_r  = {SLOT_W{1'b0}};
        rd_active_count_r = 0;
        for (rd_scan = 0; rd_scan < MAX_OUTSTANDING; rd_scan = rd_scan + 1) begin
            if (rd_valid_r[rd_scan])
                rd_active_count_r = rd_active_count_r + 1;
            if (!rd_free_found_r && !rd_valid_r[rd_scan]) begin
                rd_free_found_r = 1'b1;
                rd_free_slot_r  = rd_scan[SLOT_W-1:0];
            end
        end
    end

    always @* begin
        rd_pick_found_r = 1'b0;
        rd_pick_slot_r  = rd_rr_r;
        for (rd_scan = 0; rd_scan < MAX_OUTSTANDING; rd_scan = rd_scan + 1) begin
            rd_candidate = {{(32-SLOT_W){1'b0}}, rd_rr_r} + rd_scan;
            if (rd_candidate >= MAX_OUTSTANDING)
                rd_candidate = rd_candidate - MAX_OUTSTANDING;
            if (!rd_pick_found_r && rd_valid_r[rd_candidate]) begin
                rd_pick_found_r = 1'b1;
                rd_pick_slot_r  = rd_candidate[SLOT_W-1:0];
            end
        end
    end

    wire [32:0] rd_beat_bytes_w = (arsize_i == `AXI_SIZE_4B)
                                  ? 33'd4 : 33'd8;
    wire [32:0] rd_end_w = {1'b0, araddr_i} +
                            (({25'b0, arlen_i} + 33'd1) * rd_beat_bytes_w)
                            - 33'd1;
    wire rd_range_bad_w = ({1'b0, araddr_i} < {1'b0, BASE}) ||
                          (rd_end_w >= ({1'b0, BASE} + {1'b0, SIZE_BYTES}));
    wire rd_size_bad_w = (arsize_i != `AXI_SIZE_4B) &&
                         (arsize_i != `AXI_SIZE_8B);
    wire rd_align_bad_w = (arsize_i == `AXI_SIZE_4B)
                          ? (araddr_i[1:0] != 2'b00)
                          : (araddr_i[2:0] != 3'b000);
    wire rd_attr_bad_w = rd_size_bad_w || rd_align_bad_w ||
                         (arburst_i != `AXI_BURST_INCR);

    reg [ID_W-1:0]        rid_r;
    reg [`AXI_DATA_W-1:0] rdata_r;
    reg [`AXI_RESP_W-1:0] rresp_r;
    reg                   rlast_r;
    reg                   rvalid_r;
    reg [SLOT_W-1:0]      rslot_r;

    assign arready_o = rd_free_found_r && (lcg_r[4:3] != 2'b00);
    wire ar_fire_w = arvalid_i && arready_o;
    wire r_fire_w  = rvalid_r && rready_i;

    assign rid_o    = rid_r;
    assign rdata_o  = rdata_r;
    assign rresp_o  = rresp_r;
    assign rlast_o  = rlast_r;
    assign rvalid_o = rvalid_r;

    // ------------------------------------------------------------------
    // Write request slots, AW-order W routing and reordered B scheduler
    // ------------------------------------------------------------------
    reg                    wr_valid_r [0:MAX_OUTSTANDING-1];
    reg                    wr_done_r  [0:MAX_OUTSTANDING-1];
    reg [ID_W-1:0]         wr_id_r    [0:MAX_OUTSTANDING-1];
    reg [31:0]             wr_addr_r  [0:MAX_OUTSTANDING-1];
    reg [`AXI_LEN_W:0]     wr_beats_r [0:MAX_OUTSTANDING-1];
    reg [`AXI_SIZE_W-1:0]  wr_size_r  [0:MAX_OUTSTANDING-1];
    reg                    wr_err_r   [0:MAX_OUTSTANDING-1];

    reg [SLOT_W-1:0] aw_order_r [0:MAX_OUTSTANDING-1];
    reg [SLOT_W-1:0] aw_head_r;
    reg [SLOT_W-1:0] aw_tail_r;
    reg [SLOT_W:0]   aw_count_r;

    reg                    wr_free_found_r;
    reg [SLOT_W-1:0]       wr_free_slot_r;
    reg                    b_pick_found_r;
    reg [SLOT_W-1:0]       b_pick_slot_r;
    reg [SLOT_W-1:0]       b_rr_r;
    reg [4:0]              b_wait_r;
    integer                wr_active_count_r;
    integer                b_pending_count_r;
    integer                max_write_outstanding;
    integer                b_reorder_events;
    integer wr_scan;
    integer b_candidate;

    always @* begin
        wr_free_found_r = 1'b0;
        wr_free_slot_r  = {SLOT_W{1'b0}};
        wr_active_count_r = 0;
        for (wr_scan = 0; wr_scan < MAX_OUTSTANDING; wr_scan = wr_scan + 1) begin
            if (wr_valid_r[wr_scan])
                wr_active_count_r = wr_active_count_r + 1;
            if (!wr_free_found_r && !wr_valid_r[wr_scan]) begin
                wr_free_found_r = 1'b1;
                wr_free_slot_r  = wr_scan[SLOT_W-1:0];
            end
        end
    end

    always @* begin
        b_pick_found_r = 1'b0;
        b_pick_slot_r  = b_rr_r;
        b_pending_count_r = 0;
        for (wr_scan = 0; wr_scan < MAX_OUTSTANDING; wr_scan = wr_scan + 1) begin
            b_candidate = {{(32-SLOT_W){1'b0}}, b_rr_r} + wr_scan;
            if (b_candidate >= MAX_OUTSTANDING)
                b_candidate = b_candidate - MAX_OUTSTANDING;
            if (wr_valid_r[wr_scan] && wr_done_r[wr_scan])
                b_pending_count_r = b_pending_count_r + 1;
            // Keep the last matching slot in circular scan order. When two
            // or more responses are pending this deliberately returns a later
            // ID first, exercising legal AXI B reordering.
            if (wr_valid_r[b_candidate] && wr_done_r[b_candidate]) begin
                b_pick_found_r = 1'b1;
                b_pick_slot_r  = b_candidate[SLOT_W-1:0];
            end
        end
    end

    wire [32:0] wr_beat_bytes_w = (awsize_i == `AXI_SIZE_4B)
                                  ? 33'd4 : 33'd8;
    wire [32:0] wr_end_w = {1'b0, awaddr_i} +
                            (({25'b0, awlen_i} + 33'd1) * wr_beat_bytes_w)
                            - 33'd1;
    wire wr_range_bad_w = ({1'b0, awaddr_i} < {1'b0, BASE}) ||
                          (wr_end_w >= ({1'b0, BASE} + {1'b0, SIZE_BYTES}));
    wire wr_size_bad_w = (awsize_i != `AXI_SIZE_4B) &&
                         (awsize_i != `AXI_SIZE_8B);
    wire wr_align_bad_w = (awsize_i == `AXI_SIZE_4B)
                          ? (awaddr_i[1:0] != 2'b00)
                          : (awaddr_i[2:0] != 3'b000);
    wire wr_attr_bad_w = wr_size_bad_w || wr_align_bad_w ||
                         (awburst_i != `AXI_BURST_INCR);

    wire [SLOT_W-1:0] wslot_w = aw_order_r[aw_head_r];
    assign awready_o = wr_free_found_r && (aw_count_r < MAX_OUTSTANDING) &&
                       (lcg_r[7:6] != 2'b11);
    assign wready_o = (aw_count_r != 0) && (lcg_r[10:9] != 2'b00);
    wire aw_fire_w = awvalid_i && awready_o;
    wire w_fire_w  = wvalid_i && wready_o;

    reg [ID_W-1:0]        bid_r;
    reg [`AXI_RESP_W-1:0] bresp_r;
    reg                   bvalid_r;
    reg [SLOT_W-1:0]      bslot_r;

    assign bid_o    = bid_r;
    assign bresp_o  = bresp_r;
    assign bvalid_o = bvalid_r;
    wire b_fire_w = bvalid_r && bready_i;

    integer si;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lcg_r     <= SEED;
            rd_rr_r   <= {SLOT_W{1'b0}};
            rid_r     <= {ID_W{1'b0}};
            rdata_r   <= {`AXI_DATA_W{1'b0}};
            rresp_r   <= `AXI_RESP_OKAY;
            rlast_r   <= 1'b0;
            rvalid_r  <= 1'b0;
            rslot_r   <= {SLOT_W{1'b0}};
            max_read_outstanding <= 0;
            r_interleave_events <= 0;
            last_rid_valid_r <= 1'b0;
            last_rid_r <= {ID_W{1'b0}};
            aw_head_r <= {SLOT_W{1'b0}};
            aw_tail_r <= {SLOT_W{1'b0}};
            aw_count_r <= {(SLOT_W+1){1'b0}};
            b_rr_r     <= {SLOT_W{1'b0}};
            bid_r      <= {ID_W{1'b0}};
            bresp_r    <= `AXI_RESP_OKAY;
            bvalid_r   <= 1'b0;
            bslot_r    <= {SLOT_W{1'b0}};
            b_wait_r   <= 5'h0;
            max_write_outstanding <= 0;
            b_reorder_events <= 0;
            for (si = 0; si < MAX_OUTSTANDING; si = si + 1) begin
                rd_valid_r[si]   <= 1'b0;
                rd_id_r[si]      <= {ID_W{1'b0}};
                rd_addr_r[si]    <= 32'h0;
                rd_beats_r[si]   <= {(`AXI_LEN_W+1){1'b0}};
                rd_size_r[si]    <= {`AXI_SIZE_W{1'b0}};
                rd_cmd_err_r[si] <= 1'b0;
                wr_valid_r[si]   <= 1'b0;
                wr_done_r[si]    <= 1'b0;
                wr_id_r[si]      <= {ID_W{1'b0}};
                wr_addr_r[si]    <= 32'h0;
                wr_beats_r[si]   <= {(`AXI_LEN_W+1){1'b0}};
                wr_size_r[si]    <= {`AXI_SIZE_W{1'b0}};
                wr_err_r[si]     <= 1'b0;
                aw_order_r[si]   <= {SLOT_W{1'b0}};
            end
        end else begin
            lcg_r <= lcg32(lcg_r);
            if (rd_active_count_r > max_read_outstanding)
                max_read_outstanding <= rd_active_count_r;
            if (wr_active_count_r > max_write_outstanding)
                max_write_outstanding <= wr_active_count_r;

            if (ar_fire_w) begin
                rd_valid_r[rd_free_slot_r]   <= 1'b1;
                rd_id_r[rd_free_slot_r]      <= arid_i;
                rd_addr_r[rd_free_slot_r]    <= araddr_i;
                rd_beats_r[rd_free_slot_r]   <= {1'b0, arlen_i} + 1'b1;
                rd_size_r[rd_free_slot_r]    <= arsize_i;
                rd_cmd_err_r[rd_free_slot_r] <= rd_range_bad_w || rd_attr_bad_w;
            end

            if (r_fire_w) begin
                rvalid_r <= 1'b0;
                if (rd_beats_r[rslot_r] == 1) begin
                    rd_valid_r[rslot_r] <= 1'b0;
                end else begin
                    rd_addr_r[rslot_r]  <= rd_addr_r[rslot_r]
                                                + (32'd1 << rd_size_r[rslot_r]);
                    rd_beats_r[rslot_r] <= rd_beats_r[rslot_r] - 1'b1;
                end
                if (rslot_r == LAST_SLOT)
                    rd_rr_r <= {SLOT_W{1'b0}};
                else
                    rd_rr_r <= rslot_r + 1'b1;
            end else if (!rvalid_r && rd_pick_found_r &&
                         (lcg_r[2:1] != 2'b11)) begin
                rslot_r  <= rd_pick_slot_r;
                rid_r    <= rd_id_r[rd_pick_slot_r];
                rdata_r  <= (rd_cmd_err_r[rd_pick_slot_r] ||
                             (rd_addr_r[rd_pick_slot_r] == err_addr_i))
                            ? {`AXI_DATA_W{1'b0}}
                            : store[(rd_addr_r[rd_pick_slot_r] - BASE) >> 3];
                rresp_r  <= (rd_cmd_err_r[rd_pick_slot_r] ||
                             (rd_addr_r[rd_pick_slot_r] == err_addr_i))
                            ? `AXI_RESP_SLVERR : `AXI_RESP_OKAY;
                rlast_r  <= (rd_beats_r[rd_pick_slot_r] == 1);
                rvalid_r <= 1'b1;
                if (last_rid_valid_r && (rd_active_count_r > 1) &&
                    (last_rid_r != rd_id_r[rd_pick_slot_r]))
                    r_interleave_events <= r_interleave_events + 1;
                last_rid_valid_r <= 1'b1;
                last_rid_r <= rd_id_r[rd_pick_slot_r];
            end

            if (aw_fire_w) begin
                wr_valid_r[wr_free_slot_r] <= 1'b1;
                wr_done_r[wr_free_slot_r]  <= 1'b0;
                wr_id_r[wr_free_slot_r]    <= awid_i;
                wr_addr_r[wr_free_slot_r]  <= awaddr_i;
                wr_beats_r[wr_free_slot_r] <= {1'b0, awlen_i} + 1'b1;
                wr_size_r[wr_free_slot_r]  <= awsize_i;
                wr_err_r[wr_free_slot_r]   <= wr_range_bad_w || wr_attr_bad_w;
                aw_order_r[aw_tail_r]      <= wr_free_slot_r;
                if (aw_tail_r == LAST_SLOT)
                    aw_tail_r <= {SLOT_W{1'b0}};
                else
                    aw_tail_r <= aw_tail_r + 1'b1;
            end

            if (w_fire_w) begin
                if (!wr_err_r[wslot_w]) begin
                    if (wstrb_i[0]) store[(wr_addr_r[wslot_w]-BASE)>>3][7:0]   <= wdata_i[7:0];
                    if (wstrb_i[1]) store[(wr_addr_r[wslot_w]-BASE)>>3][15:8]  <= wdata_i[15:8];
                    if (wstrb_i[2]) store[(wr_addr_r[wslot_w]-BASE)>>3][23:16] <= wdata_i[23:16];
                    if (wstrb_i[3]) store[(wr_addr_r[wslot_w]-BASE)>>3][31:24] <= wdata_i[31:24];
                    if (wstrb_i[4]) store[(wr_addr_r[wslot_w]-BASE)>>3][39:32] <= wdata_i[39:32];
                    if (wstrb_i[5]) store[(wr_addr_r[wslot_w]-BASE)>>3][47:40] <= wdata_i[47:40];
                    if (wstrb_i[6]) store[(wr_addr_r[wslot_w]-BASE)>>3][55:48] <= wdata_i[55:48];
                    if (wstrb_i[7]) store[(wr_addr_r[wslot_w]-BASE)>>3][63:56] <= wdata_i[63:56];
                end
                if (wlast_i != (wr_beats_r[wslot_w] == 1))
                    wr_err_r[wslot_w] <= 1'b1;
                if (wlast_i || (wr_beats_r[wslot_w] == 1)) begin
                    wr_done_r[wslot_w] <= 1'b1;
                    if (aw_head_r == LAST_SLOT)
                        aw_head_r <= {SLOT_W{1'b0}};
                    else
                        aw_head_r <= aw_head_r + 1'b1;
                end else begin
                    wr_addr_r[wslot_w]  <= wr_addr_r[wslot_w]
                                              + (32'd1 << wr_size_r[wslot_w]);
                    wr_beats_r[wslot_w] <= wr_beats_r[wslot_w] - 1'b1;
                end
            end

            case ({aw_fire_w, w_fire_w &&
                   (wlast_i || (wr_beats_r[wslot_w] == 1))})
                2'b10: aw_count_r <= aw_count_r + 1'b1;
                2'b01: aw_count_r <= aw_count_r - 1'b1;
                default: aw_count_r <= aw_count_r;
            endcase

            if (b_fire_w) begin
                bvalid_r <= 1'b0;
                b_wait_r <= 5'h0;
                wr_valid_r[bslot_r] <= 1'b0;
                wr_done_r[bslot_r]  <= 1'b0;
                if (bslot_r == LAST_SLOT)
                    b_rr_r <= {SLOT_W{1'b0}};
                else
                    b_rr_r <= bslot_r + 1'b1;
            end else if (!bvalid_r && b_pick_found_r &&
                         ((b_pending_count_r >= 2) || (b_wait_r == 5'd15)) &&
                         (lcg_r[12:11] != 2'b00)) begin
                bslot_r  <= b_pick_slot_r;
                bid_r    <= wr_id_r[b_pick_slot_r];
                bresp_r  <= wr_err_r[b_pick_slot_r]
                            ? `AXI_RESP_SLVERR : `AXI_RESP_OKAY;
                bvalid_r <= 1'b1;
                b_wait_r <= 5'h0;
                if (b_pending_count_r >= 2)
                    b_reorder_events <= b_reorder_events + 1;
            end else if (!bvalid_r && b_pick_found_r) begin
                if (b_wait_r != 5'd15)
                    b_wait_r <= b_wait_r + 1'b1;
            end else if (!bvalid_r) begin
                b_wait_r <= 5'h0;
            end
        end
    end

endmodule
