// File: tb_mem_p6_arb.sv
// Spec: mem-subsys-testplan P6-01.
// Description: Concurrent requests, channel stalls, ownership and response routing.
// Clock: clk (clk_mem).
module tb_mem_p6_arb;
    reg clk = 0;
    always #4 clk = !clk;
    reg rst_n = 0;
    wire pmon_awid_i;
    wire [31:0] pmon_awaddr_i;
    wire [3:0] pmon_awlen_i;
    wire pmon_awvalid_i;
    wire pmon_awready_o;
    wire [255:0] pmon_wdata_i;
    wire [31:0] pmon_wstrb_i;
    wire pmon_wlast_i;
    wire pmon_wvalid_i;
    wire pmon_wready_o;
    wire pmon_bid_o;
    wire [1:0] pmon_bresp_o;
    wire pmon_bvalid_o;
    wire pmon_bready_i;
    wire pmon_arid_i;
    wire [31:0] pmon_araddr_i;
    wire [3:0] pmon_arlen_i;
    wire pmon_arvalid_i;
    wire pmon_arready_o;
    wire pmon_rid_o;
    wire [255:0] pmon_rdata_o;
    wire [1:0] pmon_rresp_o;
    wire pmon_rlast_o;
    wire pmon_rvalid_o;
    wire pmon_rready_i;
    wire eth_awid_i;
    wire [31:0] eth_awaddr_i;
    wire [3:0] eth_awlen_i;
    wire eth_awvalid_i;
    wire eth_awready_o;
    wire [255:0] eth_wdata_i;
    wire [31:0] eth_wstrb_i;
    wire eth_wlast_i;
    wire eth_wvalid_i;
    wire eth_wready_o;
    wire eth_bid_o;
    wire [1:0] eth_bresp_o;
    wire eth_bvalid_o;
    wire eth_bready_i;
    wire eth_arid_i;
    wire [31:0] eth_araddr_i;
    wire [3:0] eth_arlen_i;
    wire eth_arvalid_i;
    wire eth_arready_o;
    wire eth_rid_o;
    wire [255:0] eth_rdata_o;
    wire [1:0] eth_rresp_o;
    wire eth_rlast_o;
    wire eth_rvalid_o;
    wire eth_rready_i;
    wire p6_awid_o;
    wire [31:0] p6_awaddr_o;
    wire [3:0] p6_awlen_o;
    wire p6_awvalid_o;
    wire p6_awready_i;
    wire [255:0] p6_wdata_o;
    wire [31:0] p6_wstrb_o;
    wire p6_wlast_o;
    wire p6_wvalid_o;
    wire p6_wready_i;
    wire p6_bid_i;
    wire [1:0] p6_bresp_i;
    wire p6_bvalid_i;
    wire p6_bready_o;
    wire p6_arid_o;
    wire [31:0] p6_araddr_o;
    wire [3:0] p6_arlen_o;
    wire p6_arvalid_o;
    wire p6_arready_i;
    wire p6_rid_i;
    wire [255:0] p6_rdata_i;
    wire [1:0] p6_rresp_i;
    wire p6_rlast_i;
    wire p6_rvalid_i;
    wire p6_rready_o;
    integer tick = 0;
    integer ar_count [0:1];
    integer aw_count [0:1];
    integer w_count [0:1];
    integer w_beat [0:1];
    integer b_count [0:1];
    integer r_count [0:1];
    integer rd_head = 0;
    integer rd_tail = 0;
    integer rd_beat = 0;
    reg rd_owner [0:31];
    integer rd_len [0:31];
    integer wr_head = 0;
    integer wr_tail = 0;
    integer wr_beat = 0;
    reg wr_owner [0:31];
    integer wr_len [0:31];
    integer b_head = 0;
    integer b_tail = 0;
    reg b_owner [0:31];
    integer b_due [0:31];
    integer n;
    reg ar_stalled = 0;
    reg aw_stalled = 0;
    reg w_stalled = 0;
    reg [36:0] held_ar;
    reg [36:0] held_aw;
    reg [288:0] held_w;
    edrv32_mem_p6_arb dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .pmon_awid_i(pmon_awid_i),
        .pmon_awaddr_i(pmon_awaddr_i),
        .pmon_awlen_i(pmon_awlen_i),
        .pmon_awvalid_i(pmon_awvalid_i),
        .pmon_awready_o(pmon_awready_o),
        .pmon_wdata_i(pmon_wdata_i),
        .pmon_wstrb_i(pmon_wstrb_i),
        .pmon_wlast_i(pmon_wlast_i),
        .pmon_wvalid_i(pmon_wvalid_i),
        .pmon_wready_o(pmon_wready_o),
        .pmon_bid_o(pmon_bid_o),
        .pmon_bresp_o(pmon_bresp_o),
        .pmon_bvalid_o(pmon_bvalid_o),
        .pmon_bready_i(pmon_bready_i),
        .pmon_arid_i(pmon_arid_i),
        .pmon_araddr_i(pmon_araddr_i),
        .pmon_arlen_i(pmon_arlen_i),
        .pmon_arvalid_i(pmon_arvalid_i),
        .pmon_arready_o(pmon_arready_o),
        .pmon_rid_o(pmon_rid_o),
        .pmon_rdata_o(pmon_rdata_o),
        .pmon_rresp_o(pmon_rresp_o),
        .pmon_rlast_o(pmon_rlast_o),
        .pmon_rvalid_o(pmon_rvalid_o),
        .pmon_rready_i(pmon_rready_i),
        .eth_awid_i(eth_awid_i),
        .eth_awaddr_i(eth_awaddr_i),
        .eth_awlen_i(eth_awlen_i),
        .eth_awvalid_i(eth_awvalid_i),
        .eth_awready_o(eth_awready_o),
        .eth_wdata_i(eth_wdata_i),
        .eth_wstrb_i(eth_wstrb_i),
        .eth_wlast_i(eth_wlast_i),
        .eth_wvalid_i(eth_wvalid_i),
        .eth_wready_o(eth_wready_o),
        .eth_bid_o(eth_bid_o),
        .eth_bresp_o(eth_bresp_o),
        .eth_bvalid_o(eth_bvalid_o),
        .eth_bready_i(eth_bready_i),
        .eth_arid_i(eth_arid_i),
        .eth_araddr_i(eth_araddr_i),
        .eth_arlen_i(eth_arlen_i),
        .eth_arvalid_i(eth_arvalid_i),
        .eth_arready_o(eth_arready_o),
        .eth_rid_o(eth_rid_o),
        .eth_rdata_o(eth_rdata_o),
        .eth_rresp_o(eth_rresp_o),
        .eth_rlast_o(eth_rlast_o),
        .eth_rvalid_o(eth_rvalid_o),
        .eth_rready_i(eth_rready_i),
        .p6_awid_o(p6_awid_o),
        .p6_awaddr_o(p6_awaddr_o),
        .p6_awlen_o(p6_awlen_o),
        .p6_awvalid_o(p6_awvalid_o),
        .p6_awready_i(p6_awready_i),
        .p6_wdata_o(p6_wdata_o),
        .p6_wstrb_o(p6_wstrb_o),
        .p6_wlast_o(p6_wlast_o),
        .p6_wvalid_o(p6_wvalid_o),
        .p6_wready_i(p6_wready_i),
        .p6_bid_i(p6_bid_i),
        .p6_bresp_i(p6_bresp_i),
        .p6_bvalid_i(p6_bvalid_i),
        .p6_bready_o(p6_bready_o),
        .p6_arid_o(p6_arid_o),
        .p6_araddr_o(p6_araddr_o),
        .p6_arlen_o(p6_arlen_o),
        .p6_arvalid_o(p6_arvalid_o),
        .p6_arready_i(p6_arready_i),
        .p6_rid_i(p6_rid_i),
        .p6_rdata_i(p6_rdata_i),
        .p6_rresp_i(p6_rresp_i),
        .p6_rlast_i(p6_rlast_i),
        .p6_rvalid_i(p6_rvalid_i),
        .p6_rready_o(p6_rready_o)
    );
    assign pmon_arvalid_i = rst_n && ar_count[0] < 6;
    assign pmon_arid_i = 1'b1;
    assign pmon_araddr_i = 32'h00001000 + 32'(ar_count[0]*512);
    assign pmon_arlen_i = 4'd2;
    assign pmon_awvalid_i = rst_n && aw_count[0] < 6;
    assign pmon_awid_i = 1'b1;
    assign pmon_awaddr_i = 32'h00004000 + 32'(aw_count[0]*512);
    assign pmon_awlen_i = 4'd1;
    assign pmon_wvalid_i = rst_n && w_count[0] < 6;
    assign pmon_wdata_i = {8{32'habc00000 +
        32'(w_count[0]*16 + w_beat[0])}};
    assign pmon_wstrb_i = 32'hffff0000;
    assign pmon_wlast_i = w_beat[0] == 1;
    assign pmon_rready_i = tick%7 != 0;
    assign pmon_bready_i = tick%4 != 0;
    assign eth_arvalid_i = rst_n && ar_count[1] < 6;
    assign eth_arid_i = 1'b0;
    assign eth_araddr_i = 32'h00002000 + 32'(ar_count[1]*512);
    assign eth_arlen_i = 4'd0;
    assign eth_awvalid_i = rst_n && aw_count[1] < 6;
    assign eth_awid_i = 1'b0;
    assign eth_awaddr_i = 32'h00005000 + 32'(aw_count[1]*512);
    assign eth_awlen_i = 4'd2;
    assign eth_wvalid_i = rst_n && w_count[1] < 6;
    assign eth_wdata_i = {8{32'habc01000 +
        32'(w_count[1]*16 + w_beat[1])}};
    assign eth_wstrb_i = 32'hffffffff;
    assign eth_wlast_i = w_beat[1] == 2;
    assign eth_rready_i = tick%7 != 1;
    assign eth_bready_i = tick%4 != 1;
    assign p6_arready_i = tick%5 == 0 || tick%5 == 1;
    assign p6_awready_i = tick%7 == 0 || tick%7 == 1;
    assign p6_wready_i = tick%3 != 0;
    assign p6_bvalid_i = b_tail > b_head && tick >= b_due[b_head];
    assign p6_bid_i = b_owner[b_head];
    assign p6_bresp_i = b_owner[b_head] ? 2'b00 : 2'b10;
    assign p6_rvalid_i = rd_tail > rd_head;
    assign p6_rid_i = rd_owner[rd_head];
    assign p6_rresp_i = rd_owner[rd_head] ? 2'b10 : 2'b00;
    assign p6_rdata_i = {8{32'hc000_0000 + 32'(rd_head*16+rd_beat)}};
    assign p6_rlast_i = rd_beat == rd_len[rd_head];

    always @(posedge clk) begin
        if (!rst_n) begin
            if (p6_arvalid_o || p6_awvalid_o || p6_wvalid_o)
                $fatal(1, "FAIL reset downstream valid");
        end else begin
            if (ar_stalled && {p6_arid_o,p6_araddr_o,p6_arlen_o} !== held_ar)
                $fatal(1, "FAIL AR payload changed under stall");
            if (aw_stalled && {p6_awid_o,p6_awaddr_o,p6_awlen_o} !== held_aw)
                $fatal(1, "FAIL AW payload changed under stall");
            if (w_stalled && {p6_wdata_o,p6_wstrb_o,p6_wlast_o} !== held_w)
                $fatal(1, "FAIL W payload changed under stall");
            ar_stalled = p6_arvalid_o && !p6_arready_i;
            aw_stalled = p6_awvalid_o && !p6_awready_i;
            w_stalled = p6_wvalid_o && !p6_wready_i;
            held_ar = {p6_arid_o,p6_araddr_o,p6_arlen_o};
            held_aw = {p6_awid_o,p6_awaddr_o,p6_awlen_o};
            held_w = {p6_wdata_o,p6_wstrb_o,p6_wlast_o};
            if (p6_arvalid_o && p6_arready_i) begin
                if (p6_arid_o !== 1'(rd_tail%2)) $fatal(1, "FAIL AR round robin");
                if (p6_araddr_o !== (p6_arid_o ? eth_araddr_i : pmon_araddr_i))
                    $fatal(1, "FAIL AR address mux");
                rd_owner[rd_tail] <= p6_arid_o;
                rd_len[rd_tail] <= int'(p6_arlen_o);
                rd_tail <= rd_tail + 1;
            end
            if (p6_awvalid_o && p6_awready_i) begin
                if (p6_awid_o !== 1'(wr_tail%2)) $fatal(1, "FAIL AW round robin");
                if (p6_awaddr_o !== (p6_awid_o ? eth_awaddr_i : pmon_awaddr_i))
                    $fatal(1, "FAIL AW address mux");
                wr_owner[wr_tail] <= p6_awid_o;
                wr_len[wr_tail] <= int'(p6_awlen_o);
                wr_tail <= wr_tail + 1;
            end
            if (p6_wvalid_o && p6_wready_i) begin
                if (wr_head >= wr_tail) $fatal(1, "FAIL W without accepted AW");
                if (p6_wdata_o !== {8{32'habc0_0000 +
                    (wr_owner[wr_head] ? 32'h1000 : 32'h0) +
                    32'((wr_head/2)*16 + wr_beat)}})
                    $fatal(1, "FAIL W owner/order");
                if (p6_wstrb_o !== (wr_owner[wr_head] ? 32'hffff_ffff : 32'hffff_0000))
                    $fatal(1, "FAIL WSTRB mux");
                if (p6_wlast_o !== (wr_beat == wr_len[wr_head]))
                    $fatal(1, "FAIL WLAST mux");
                wr_beat <= wr_beat + 1;
                if (p6_wlast_o) begin
                    b_owner[b_tail] <= wr_owner[wr_head];
                    b_due[b_tail] <= tick + 12;
                    b_tail <= b_tail + 1;
                    wr_head <= wr_head + 1;
                    wr_beat <= 0;
                end
            end
            if (p6_bvalid_i) begin
                if (p6_bid_i) begin
                    if (!eth_bvalid_o || pmon_bvalid_o || eth_bid_o !== 1 ||
                        eth_bresp_o !== p6_bresp_i || p6_bready_o !== eth_bready_i)
                        $fatal(1, "FAIL ETH B routing");
                end else begin
                    if (!pmon_bvalid_o || eth_bvalid_o || pmon_bid_o !== 0 ||
                        pmon_bresp_o !== p6_bresp_i || p6_bready_o !== pmon_bready_i)
                        $fatal(1, "FAIL PERF_MON B routing");
                end
                if (p6_bready_o) b_head <= b_head + 1;
            end
            if (p6_rvalid_i) begin
                if (p6_rid_i) begin
                    if (!eth_rvalid_o || pmon_rvalid_o || eth_rid_o !== 1 ||
                        eth_rresp_o !== p6_rresp_i || eth_rdata_o !== p6_rdata_i ||
                        eth_rlast_o !== p6_rlast_i || p6_rready_o !== eth_rready_i)
                        $fatal(1, "FAIL ETH R routing");
                end else begin
                    if (!pmon_rvalid_o || eth_rvalid_o || pmon_rid_o !== 0 ||
                        pmon_rresp_o !== p6_rresp_i || pmon_rdata_o !== p6_rdata_i ||
                        pmon_rlast_o !== p6_rlast_i || p6_rready_o !== pmon_rready_i)
                        $fatal(1, "FAIL PERF_MON R routing");
                end
                if (p6_rready_o) begin
                    rd_beat <= rd_beat + 1;
                    if (p6_rlast_i) begin rd_head <= rd_head + 1; rd_beat <= 0; end
                end
            end
            if (pmon_arvalid_i && pmon_arready_o) ar_count[0] <= ar_count[0] + 1;
            if (pmon_awvalid_i && pmon_awready_o) aw_count[0] <= aw_count[0] + 1;
            if (pmon_wvalid_i && pmon_wready_o) begin
                w_beat[0] <= w_beat[0] + 1;
                if (pmon_wlast_i) begin
                    w_count[0] <= w_count[0] + 1; w_beat[0] <= 0;
                end
            end
            if (pmon_bvalid_o && pmon_bready_i) b_count[0] <= b_count[0] + 1;
            if (pmon_rvalid_o && pmon_rready_i && pmon_rlast_o)
                r_count[0] <= r_count[0] + 1;
            if (eth_arvalid_i && eth_arready_o) ar_count[1] <= ar_count[1] + 1;
            if (eth_awvalid_i && eth_awready_o) aw_count[1] <= aw_count[1] + 1;
            if (eth_wvalid_i && eth_wready_o) begin
                w_beat[1] <= w_beat[1] + 1;
                if (eth_wlast_i) begin
                    w_count[1] <= w_count[1] + 1; w_beat[1] <= 0;
                end
            end
            if (eth_bvalid_o && eth_bready_i) b_count[1] <= b_count[1] + 1;
            if (eth_rvalid_o && eth_rready_i && eth_rlast_o)
                r_count[1] <= r_count[1] + 1;
        end
    end
    always @(negedge clk) tick = tick + 1;
    initial begin
        for (n = 0; n < 2; n = n + 1) begin
            ar_count[n] = 0; aw_count[n] = 0; w_count[n] = 0;
            w_beat[n] = 0; b_count[n] = 0; r_count[n] = 0;
        end
        repeat (4) @(negedge clk);
        rst_n = 1;
        wait (b_count[0] == 6 && b_count[1] == 6 && r_count[0] == 6 && r_count[1] == 6);
        repeat (4) @(negedge clk);
        if (rd_tail != 12 || wr_tail != 12 || wr_head != 12 || rd_head != 12)
            $fatal(1, "FAIL missing requests or responses");
        $display("PASS P6-01 independent round robin, W ownership and B/R routing");
        $finish;
    end
    initial begin #50000; $fatal(1, "FAIL timeout"); end
endmodule
