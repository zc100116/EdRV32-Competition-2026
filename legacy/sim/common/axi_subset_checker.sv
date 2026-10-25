// ============================================================================
// File        : axi_subset_checker.sv
// Author      : Edward ZC
// Description : Machine-checkable AXI4 subset checker for the competition
//               fabric (design §6.1/§6.3, implementation plan WP-A).  Watches
//               one full master interface and asserts, per handshake:
//               alignment to AxSIZE, INCR-only bursts, 16-beat maximum, no
//               4 KiB crossing, legal AxSIZE for the bus width, WLAST
//               position matching AWLEN, stable RID/beat-count inside a
//               burst, no EXOKAY (no exclusive support), and payload
//               stability while VALID is held under backpressure.
// Notes       : SystemVerilog immediate assertions; synthesizable-free (sim
//               only).  Instantiate once per master port under test.
// ============================================================================
module axi_subset_checker #(
    parameter ADDR_W = 32,
    parameter DATA_W = 64,
    parameter ID_W   = 4,
    parameter LEN_W  = 8,
    parameter SIZE_W = 3,
    parameter RESP_W = 2,
    parameter MAX_BEATS = 16,
    parameter MAX_READ_OUTSTANDING = 16,
    parameter MAX_WRITE_OUTSTANDING = 16,
    parameter NAME = "m0"
)(
    input wire clk,
    input wire rst_n,

    // read address channel
    input wire [ID_W-1:0]   arid_i,
    input wire [ADDR_W-1:0] araddr_i,
    input wire [LEN_W-1:0]  arlen_i,
    input wire [SIZE_W-1:0] arsize_i,
    input wire [1:0]        arburst_i,
    input wire              arvalid_i,
    input wire              arready_i,
    // read data channel
    input wire [ID_W-1:0]   rid_i,
    input wire [DATA_W-1:0] rdata_i,
    input wire [RESP_W-1:0] rresp_i,
    input wire              rlast_i,
    input wire              rvalid_i,
    input wire              rready_i,
    // write address channel
    input wire [ID_W-1:0]   awid_i,
    input wire [ADDR_W-1:0] awaddr_i,
    input wire [LEN_W-1:0]  awlen_i,
    input wire [SIZE_W-1:0] awsize_i,
    input wire [1:0]        awburst_i,
    input wire              awvalid_i,
    input wire              awready_i,
    // write data channel
    input wire [DATA_W-1:0] wdata_i,
    input wire [DATA_W/8-1:0] wstrb_i,
    input wire              wlast_i,
    input wire              wvalid_i,
    input wire              wready_i,
    // write response channel
    input wire [ID_W-1:0]   bid_i,
    input wire [RESP_W-1:0] bresp_i,
    input wire              bvalid_i,
    input wire              bready_i
);

    localparam BEAT_BYTES = DATA_W / 8;
    localparam SIZE_MAX   = $clog2(BEAT_BYTES);   // AxSIZE encoding of bus width
    localparam ID_COUNT   = (1 << ID_W);
    localparam AR_PTR_W   = (MAX_READ_OUTSTANDING <= 1) ? 1 :
                            $clog2(MAX_READ_OUTSTANDING);
    localparam AR_COUNT_W = $clog2(MAX_READ_OUTSTANDING + 1);
    localparam AW_PTR_W   = (MAX_WRITE_OUTSTANDING <= 1) ? 1 :
                            $clog2(MAX_WRITE_OUTSTANDING);
    localparam AW_COUNT_W = $clog2(MAX_WRITE_OUTSTANDING + 1);

    // ---- R burst tracking; responses may reorder across IDs, while requests
    //      carrying the same ID complete in AR acceptance order. ----
    reg [LEN_W-1:0] ar_len_fifo_r [0:ID_COUNT-1]
                                      [0:MAX_READ_OUTSTANDING-1];
    reg [AR_PTR_W-1:0] ar_wr_ptr_r [0:ID_COUNT-1];
    reg [AR_PTR_W-1:0] ar_rd_ptr_r [0:ID_COUNT-1];
    reg [AR_COUNT_W-1:0] ar_count_r [0:ID_COUNT-1];
    reg [LEN_W-1:0] r_cnt_by_id_r [0:ID_COUNT-1];
    // ---- W burst tracking; AXI4 W data follows accepted AW order ----
    reg [LEN_W-1:0] aw_len_fifo_r [0:MAX_WRITE_OUTSTANDING-1];
    reg [AW_PTR_W-1:0] aw_wr_ptr_r;
    reg [AW_PTR_W-1:0] aw_rd_ptr_r;
    reg [AW_COUNT_W-1:0] aw_count_r;
    // ---- payload stability (manual, Verilator-safe) ----
    reg               ar_hold_r, aw_hold_r;
    reg [ADDR_W-1:0]  ar_addr_prev_r, aw_addr_prev_r;
    reg [LEN_W-1:0]   ar_len_prev_r, aw_len_prev_r;
    reg [ID_W-1:0]    ar_id_prev_r, aw_id_prev_r;
    reg [DATA_W-1:0]  w_data_prev_r;
    reg [DATA_W/8-1:0] w_strb_prev_r;
    reg               w_last_prev_r;
    reg [LEN_W-1:0]   b_dummy_r;
    reg               w_stab_v_r;
    reg [LEN_W-1:0]   w_cnt_r;
    integer           reset_id_i;

    wire ar_fire_w = arvalid_i && arready_i;
    wire aw_fire_w = awvalid_i && awready_i;
    wire r_fire_w  = rvalid_i && rready_i;
    wire w_fire_w  = wvalid_i && wready_i;
    wire b_fire_w  = bvalid_i && bready_i;
    wire aw_queue_empty_w = (aw_count_r == 0);
    wire w_has_aw_w = !aw_queue_empty_w || aw_fire_w;
    wire [LEN_W-1:0] w_awlen_w = aw_queue_empty_w
        ? awlen_i : aw_len_fifo_r[aw_rd_ptr_r];
    wire w_pop_w = w_fire_w && wlast_i && w_has_aw_w;
    wire [AR_COUNT_W-1:0] rid_count_w = ar_count_r[rid_i];
    wire r_has_ar_w = (rid_count_w != 0) ||
                      (ar_fire_w && (arid_i == rid_i));
    wire [LEN_W-1:0] r_arlen_w = (rid_count_w == 0)
        ? arlen_i : ar_len_fifo_r[rid_i][ar_rd_ptr_r[rid_i]];
    wire r_pop_w = r_fire_w && rlast_i && r_has_ar_w;

    function automatic integer beat_bytes;
        input [SIZE_W-1:0] size;
        beat_bytes = (1 << size);
    endfunction

    function automatic [AW_PTR_W-1:0] aw_ptr_next;
        input [AW_PTR_W-1:0] ptr;
        begin
            if (ptr == MAX_WRITE_OUTSTANDING - 1)
                aw_ptr_next = {AW_PTR_W{1'b0}};
            else
                aw_ptr_next = ptr + 1'b1;
        end
    endfunction

    function automatic [AR_PTR_W-1:0] ar_ptr_next;
        input [AR_PTR_W-1:0] ptr;
        begin
            if (ptr == MAX_READ_OUTSTANDING - 1)
                ar_ptr_next = {AR_PTR_W{1'b0}};
            else
                ar_ptr_next = ptr + 1'b1;
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ar_hold_r <= 1'b0;
            aw_hold_r <= 1'b0;
            aw_wr_ptr_r <= {AW_PTR_W{1'b0}};
            aw_rd_ptr_r <= {AW_PTR_W{1'b0}};
            aw_count_r <= {AW_COUNT_W{1'b0}};
            w_cnt_r <= '0;
            b_dummy_r <= '0;
            w_stab_v_r <= 1'b0;
            for (reset_id_i = 0; reset_id_i < ID_COUNT;
                 reset_id_i = reset_id_i + 1) begin
                ar_wr_ptr_r[reset_id_i] <= {AR_PTR_W{1'b0}};
                ar_rd_ptr_r[reset_id_i] <= {AR_PTR_W{1'b0}};
                ar_count_r[reset_id_i] <= {AR_COUNT_W{1'b0}};
                r_cnt_by_id_r[reset_id_i] <= {LEN_W{1'b0}};
            end
        end else begin
            // ---------------- AR channel ----------------
            if (arvalid_i && !arready_i) begin
                if (ar_hold_r) begin
                    if (ar_addr_prev_r !== araddr_i || ar_len_prev_r !== arlen_i ||
                        ar_id_prev_r !== arid_i)
                        $fatal(1, "[%s] AR payload changed under backpressure", NAME);
                end
                ar_hold_r <= 1'b1;
                ar_addr_prev_r <= araddr_i;
                ar_len_prev_r <= arlen_i;
                ar_id_prev_r <= arid_i;
            end else begin
                ar_hold_r <= 1'b0;
            end
            if (ar_fire_w) begin
                if (araddr_i % (1 << arsize_i) != 0)
                    $fatal(1, "[%s] AR alignment violation addr=%08x size=%0d", NAME, araddr_i, arsize_i);
                if (arburst_i != 2'b01)
                    $fatal(1, "[%s] AR burst type must be INCR", NAME);
                if (arlen_i > MAX_BEATS - 1)
                    $fatal(1, "[%s] AR burst longer than %0d beats", NAME, MAX_BEATS);
                if (arsize_i > SIZE_MAX)
                    $fatal(1, "[%s] AR AxSIZE %0d exceeds bus width", NAME, arsize_i);
                if ((araddr_i[11:0] + arlen_i * beat_bytes(arsize_i) + beat_bytes(arsize_i)) > 13'd4096)
                    $fatal(1, "[%s] AR crosses 4 KiB boundary addr=%08x len=%0d", NAME, araddr_i, arlen_i);
                if ((ar_count_r[arid_i] == MAX_READ_OUTSTANDING) &&
                    !(r_pop_w && (rid_i == arid_i)))
                    $fatal(1, "[%s] AR tracking FIFO overflow for ID %0d",
                           NAME, arid_i);
                ar_len_fifo_r[arid_i][ar_wr_ptr_r[arid_i]] <= arlen_i;
                ar_wr_ptr_r[arid_i] <= ar_ptr_next(ar_wr_ptr_r[arid_i]);
            end

            // ---------------- R channel ----------------
            if (r_fire_w) begin
                if (rresp_i == 2'b01)
                    $fatal(1, "[%s] EXOKAY returned without exclusive support", NAME);
                if (!r_has_ar_w)
                    $fatal(1, "[%s] R beat without outstanding AR", NAME);
                if (r_cnt_by_id_r[rid_i] > r_arlen_w)
                    $fatal(1, "[%s] R burst exceeded ARLEN+1 beats", NAME);
                if (rlast_i != (r_cnt_by_id_r[rid_i] == r_arlen_w))
                    $fatal(1, "[%s] RLAST at wrong beat position (%0d/%0d)",
                           NAME, r_cnt_by_id_r[rid_i], r_arlen_w);
                if (rlast_i) begin
                    r_cnt_by_id_r[rid_i] <= {LEN_W{1'b0}};
                    ar_rd_ptr_r[rid_i] <= ar_ptr_next(ar_rd_ptr_r[rid_i]);
                end else begin
                    r_cnt_by_id_r[rid_i] <= r_cnt_by_id_r[rid_i] + 1'b1;
                end
            end

            if (ar_fire_w && r_pop_w && (arid_i == rid_i)) begin
                ar_count_r[arid_i] <= ar_count_r[arid_i];
            end else begin
                if (ar_fire_w)
                    ar_count_r[arid_i] <= ar_count_r[arid_i] + 1'b1;
                if (r_pop_w)
                    ar_count_r[rid_i] <= ar_count_r[rid_i] - 1'b1;
            end

            // ---------------- AW channel ----------------
            if (awvalid_i && !awready_i) begin
                if (aw_hold_r) begin
                    if (aw_addr_prev_r !== awaddr_i || aw_len_prev_r !== awlen_i ||
                        aw_id_prev_r !== awid_i)
                        $fatal(1, "[%s] AW payload changed under backpressure", NAME);
                end
                aw_hold_r <= 1'b1;
                aw_addr_prev_r <= awaddr_i;
                aw_len_prev_r <= awlen_i;
                aw_id_prev_r <= awid_i;
            end else begin
                aw_hold_r <= 1'b0;
            end
            if (aw_fire_w) begin
                if (awaddr_i % (1 << awsize_i) != 0)
                    $fatal(1, "[%s] AW alignment violation addr=%08x size=%0d", NAME, awaddr_i, awsize_i);
                if (awburst_i != 2'b01)
                    $fatal(1, "[%s] AW burst type must be INCR", NAME);
                if (awlen_i > MAX_BEATS - 1)
                    $fatal(1, "[%s] AW burst longer than %0d beats", NAME, MAX_BEATS);
                if (awsize_i > SIZE_MAX)
                    $fatal(1, "[%s] AW AxSIZE %0d exceeds bus width", NAME, awsize_i);
                if ((awaddr_i[11:0] + awlen_i * beat_bytes(awsize_i) + beat_bytes(awsize_i)) > 13'd4096)
                    $fatal(1, "[%s] AW crosses 4 KiB boundary addr=%08x len=%0d", NAME, awaddr_i, awlen_i);
                if ((aw_count_r == MAX_WRITE_OUTSTANDING) && !w_pop_w)
                    $fatal(1, "[%s] AW tracking FIFO overflow", NAME);
                aw_len_fifo_r[aw_wr_ptr_r] <= awlen_i;
                aw_wr_ptr_r <= aw_ptr_next(aw_wr_ptr_r);
            end

            if (w_pop_w)
                aw_rd_ptr_r <= aw_ptr_next(aw_rd_ptr_r);

            case ({aw_fire_w, w_pop_w})
                2'b10: aw_count_r <= aw_count_r + 1'b1;
                2'b01: aw_count_r <= aw_count_r - 1'b1;
                default: aw_count_r <= aw_count_r;
            endcase

            // ---------------- W channel ----------------
            if (w_fire_w) begin
                if (!w_has_aw_w) begin
                    $fatal(1, "[%s] W beat without a latched AW", NAME);
                end else begin
                    if (w_cnt_r > w_awlen_w)
                        $fatal(1, "[%s] W burst exceeded AWLEN+1 beats", NAME);
                    if (wlast_i != (w_cnt_r == w_awlen_w))
                        $fatal(1, "[%s] WLAST at wrong beat position (%0d/%0d)", NAME, w_cnt_r, w_awlen_w);
                    if (wstrb_i === '0)
                        $fatal(1, "[%s] W beat with zero WSTRB", NAME);
                    if (wlast_i)
                        w_cnt_r <= '0;
                    else
                        w_cnt_r <= w_cnt_r + 1'b1;
                end
            end
            // ---------------- B channel ----------------
            if (b_fire_w) begin
                if (bresp_i == 2'b01)
                    $fatal(1, "[%s] EXOKAY returned without exclusive support", NAME);
                b_dummy_r <= b_dummy_r;
            end

            // payload stability on W under backpressure
            if (wvalid_i && !wready_i) begin
                if (w_stab_v_r) begin
                    if (w_data_prev_r !== wdata_i || w_strb_prev_r !== wstrb_i ||
                        w_last_prev_r !== wlast_i)
                        $fatal(1, "[%s] W payload changed under backpressure", NAME);
                end
                w_data_prev_r <= wdata_i;
                w_strb_prev_r <= wstrb_i;
                w_last_prev_r <= wlast_i;
                w_stab_v_r <= 1'b1;
            end else begin
                w_stab_v_r <= 1'b0;
            end
        end
    end

endmodule
