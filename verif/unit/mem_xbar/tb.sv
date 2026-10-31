// File: tb.sv
// Spec: mem-subsys-testplan MX-01 through MX-11 (MX-12 belongs to M-V1).
// Description: Directed scheduler and crossbar checks with an unthrottled DDR return model.
// Clock: clk_mem; Icarus also checks control validity over uninitialized DRM payloads.
`timescale 1ns/1ps
module tb;
    parameter FULL = 0;
    reg clk = 0;
    always #4 clk = ~clk;
    reg rst_n = 0;
    reg [6:0] awid;
    reg [223:0] awaddr;
    reg [27:0] awlen;
    reg [6:0] awvalid;
    wire [6:0] awready;
    reg [1791:0] wdata;
    reg [223:0] wstrb;
    reg [6:0] wlast;
    reg [6:0] wvalid;
    wire [6:0] wready;
    wire [6:0] bid;
    wire [13:0] bresp;
    wire [6:0] bvalid;
    reg [6:0] bready;
    reg [6:0] arid;
    reg [223:0] araddr;
    reg [27:0] arlen;
    reg [6:0] arvalid;
    wire [6:0] arready;
    wire [6:0] rid;
    wire [1791:0] rdata;
    wire [13:0] rresp;
    wire [6:0] rlast;
    wire [6:0] rvalid;
    reg [6:0] rready;
    reg [1:0] urgent;
    wire [3:0] ddr_awid_o;
    wire [31:0] ddr_awaddr_o;
    wire [3:0] ddr_awlen_o;
    wire ddr_awvalid_o;
    reg ddr_awready_i;
    wire [255:0] ddr_wdata_o;
    wire [31:0] ddr_wstrb_o;
    wire ddr_wlast_o;
    wire ddr_wvalid_o;
    reg ddr_wready_i;
    reg [3:0] ddr_bid_i;
    reg [1:0] ddr_bresp_i;
    reg ddr_bvalid_i;
    wire [3:0] ddr_arid_o;
    wire [31:0] ddr_araddr_o;
    wire [3:0] ddr_arlen_o;
    wire ddr_arvalid_o;
    reg ddr_arready_i;
    reg [3:0] ddr_rid_i;
    reg [255:0] ddr_rdata_i;
    reg [1:0] ddr_rresp_i;
    reg ddr_rlast_i;
    reg ddr_rvalid_i;
    reg [11:0] apb_paddr_i;
    reg apb_psel_i;
    reg apb_penable_i;
    reg apb_pwrite_i;
    reg [31:0] apb_pwdata_i;
    reg [3:0] apb_pstrb_i;
    wire apb_pready_o;
    wire [31:0] apb_prdata_o;
    wire apb_pslverr_o;
    wire irq_o;

    edrv32_mem_xbar dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .p0_arid_i(arid[0 +: 1]),
        .p0_araddr_i(araddr[0 +: 32]),
        .p0_arlen_i(arlen[0 +: 4]),
        .p0_arvalid_i(arvalid[0 +: 1]),
        .p0_arready_o(arready[0 +: 1]),
        .p0_rid_o(rid[0 +: 1]),
        .p0_rdata_o(rdata[0 +: 256]),
        .p0_rresp_o(rresp[0 +: 2]),
        .p0_rlast_o(rlast[0 +: 1]),
        .p0_rvalid_o(rvalid[0 +: 1]),
        .p0_rready_i(rready[0 +: 1]),
        .p0_urgent_i(urgent[0]),
        .p1_awid_i(awid[1 +: 1]),
        .p1_awaddr_i(awaddr[32 +: 32]),
        .p1_awlen_i(awlen[4 +: 4]),
        .p1_awvalid_i(awvalid[1 +: 1]),
        .p1_awready_o(awready[1 +: 1]),
        .p1_wdata_i(wdata[256 +: 256]),
        .p1_wstrb_i(wstrb[32 +: 32]),
        .p1_wlast_i(wlast[1 +: 1]),
        .p1_wvalid_i(wvalid[1 +: 1]),
        .p1_wready_o(wready[1 +: 1]),
        .p1_bid_o(bid[1 +: 1]),
        .p1_bresp_o(bresp[2 +: 2]),
        .p1_bvalid_o(bvalid[1 +: 1]),
        .p1_bready_i(bready[1 +: 1]),
        .p1_arid_i(arid[1 +: 1]),
        .p1_araddr_i(araddr[32 +: 32]),
        .p1_arlen_i(arlen[4 +: 4]),
        .p1_arvalid_i(arvalid[1 +: 1]),
        .p1_arready_o(arready[1 +: 1]),
        .p1_rid_o(rid[1 +: 1]),
        .p1_rdata_o(rdata[256 +: 256]),
        .p1_rresp_o(rresp[2 +: 2]),
        .p1_rlast_o(rlast[1 +: 1]),
        .p1_rvalid_o(rvalid[1 +: 1]),
        .p1_rready_i(rready[1 +: 1]),
        .p1_urgent_i(urgent[1]),
        .p2_awid_i(awid[2 +: 1]),
        .p2_awaddr_i(awaddr[64 +: 32]),
        .p2_awlen_i(awlen[8 +: 4]),
        .p2_awvalid_i(awvalid[2 +: 1]),
        .p2_awready_o(awready[2 +: 1]),
        .p2_wdata_i(wdata[512 +: 256]),
        .p2_wstrb_i(wstrb[64 +: 32]),
        .p2_wlast_i(wlast[2 +: 1]),
        .p2_wvalid_i(wvalid[2 +: 1]),
        .p2_wready_o(wready[2 +: 1]),
        .p2_bid_o(bid[2 +: 1]),
        .p2_bresp_o(bresp[4 +: 2]),
        .p2_bvalid_o(bvalid[2 +: 1]),
        .p2_bready_i(bready[2 +: 1]),
        .p2_arid_i(arid[2 +: 1]),
        .p2_araddr_i(araddr[64 +: 32]),
        .p2_arlen_i(arlen[8 +: 4]),
        .p2_arvalid_i(arvalid[2 +: 1]),
        .p2_arready_o(arready[2 +: 1]),
        .p2_rid_o(rid[2 +: 1]),
        .p2_rdata_o(rdata[512 +: 256]),
        .p2_rresp_o(rresp[4 +: 2]),
        .p2_rlast_o(rlast[2 +: 1]),
        .p2_rvalid_o(rvalid[2 +: 1]),
        .p2_rready_i(rready[2 +: 1]),
        .p3_awid_i(awid[3 +: 1]),
        .p3_awaddr_i(awaddr[96 +: 32]),
        .p3_awlen_i(awlen[12 +: 4]),
        .p3_awvalid_i(awvalid[3 +: 1]),
        .p3_awready_o(awready[3 +: 1]),
        .p3_wdata_i(wdata[768 +: 256]),
        .p3_wstrb_i(wstrb[96 +: 32]),
        .p3_wlast_i(wlast[3 +: 1]),
        .p3_wvalid_i(wvalid[3 +: 1]),
        .p3_wready_o(wready[3 +: 1]),
        .p3_bid_o(bid[3 +: 1]),
        .p3_bresp_o(bresp[6 +: 2]),
        .p3_bvalid_o(bvalid[3 +: 1]),
        .p3_bready_i(bready[3 +: 1]),
        .p3_arid_i(arid[3 +: 1]),
        .p3_araddr_i(araddr[96 +: 32]),
        .p3_arlen_i(arlen[12 +: 4]),
        .p3_arvalid_i(arvalid[3 +: 1]),
        .p3_arready_o(arready[3 +: 1]),
        .p3_rid_o(rid[3 +: 1]),
        .p3_rdata_o(rdata[768 +: 256]),
        .p3_rresp_o(rresp[6 +: 2]),
        .p3_rlast_o(rlast[3 +: 1]),
        .p3_rvalid_o(rvalid[3 +: 1]),
        .p3_rready_i(rready[3 +: 1]),
        .p4_awid_i(awid[4 +: 1]),
        .p4_awaddr_i(awaddr[128 +: 32]),
        .p4_awlen_i(awlen[16 +: 4]),
        .p4_awvalid_i(awvalid[4 +: 1]),
        .p4_awready_o(awready[4 +: 1]),
        .p4_wdata_i(wdata[1024 +: 256]),
        .p4_wstrb_i(wstrb[128 +: 32]),
        .p4_wlast_i(wlast[4 +: 1]),
        .p4_wvalid_i(wvalid[4 +: 1]),
        .p4_wready_o(wready[4 +: 1]),
        .p4_bid_o(bid[4 +: 1]),
        .p4_bresp_o(bresp[8 +: 2]),
        .p4_bvalid_o(bvalid[4 +: 1]),
        .p4_bready_i(bready[4 +: 1]),
        .p4_arid_i(arid[4 +: 1]),
        .p4_araddr_i(araddr[128 +: 32]),
        .p4_arlen_i(arlen[16 +: 4]),
        .p4_arvalid_i(arvalid[4 +: 1]),
        .p4_arready_o(arready[4 +: 1]),
        .p4_rid_o(rid[4 +: 1]),
        .p4_rdata_o(rdata[1024 +: 256]),
        .p4_rresp_o(rresp[8 +: 2]),
        .p4_rlast_o(rlast[4 +: 1]),
        .p4_rvalid_o(rvalid[4 +: 1]),
        .p4_rready_i(rready[4 +: 1]),
        .p5_awid_i(awid[5 +: 1]),
        .p5_awaddr_i(awaddr[160 +: 32]),
        .p5_awlen_i(awlen[20 +: 4]),
        .p5_awvalid_i(awvalid[5 +: 1]),
        .p5_awready_o(awready[5 +: 1]),
        .p5_wdata_i(wdata[1280 +: 256]),
        .p5_wstrb_i(wstrb[160 +: 32]),
        .p5_wlast_i(wlast[5 +: 1]),
        .p5_wvalid_i(wvalid[5 +: 1]),
        .p5_wready_o(wready[5 +: 1]),
        .p5_bid_o(bid[5 +: 1]),
        .p5_bresp_o(bresp[10 +: 2]),
        .p5_bvalid_o(bvalid[5 +: 1]),
        .p5_bready_i(bready[5 +: 1]),
        .p5_arid_i(arid[5 +: 1]),
        .p5_araddr_i(araddr[160 +: 32]),
        .p5_arlen_i(arlen[20 +: 4]),
        .p5_arvalid_i(arvalid[5 +: 1]),
        .p5_arready_o(arready[5 +: 1]),
        .p5_rid_o(rid[5 +: 1]),
        .p5_rdata_o(rdata[1280 +: 256]),
        .p5_rresp_o(rresp[10 +: 2]),
        .p5_rlast_o(rlast[5 +: 1]),
        .p5_rvalid_o(rvalid[5 +: 1]),
        .p5_rready_i(rready[5 +: 1]),
        .p6_awid_i(awid[6 +: 1]),
        .p6_awaddr_i(awaddr[192 +: 32]),
        .p6_awlen_i(awlen[24 +: 4]),
        .p6_awvalid_i(awvalid[6 +: 1]),
        .p6_awready_o(awready[6 +: 1]),
        .p6_wdata_i(wdata[1536 +: 256]),
        .p6_wstrb_i(wstrb[192 +: 32]),
        .p6_wlast_i(wlast[6 +: 1]),
        .p6_wvalid_i(wvalid[6 +: 1]),
        .p6_wready_o(wready[6 +: 1]),
        .p6_bid_o(bid[6 +: 1]),
        .p6_bresp_o(bresp[12 +: 2]),
        .p6_bvalid_o(bvalid[6 +: 1]),
        .p6_bready_i(bready[6 +: 1]),
        .p6_arid_i(arid[6 +: 1]),
        .p6_araddr_i(araddr[192 +: 32]),
        .p6_arlen_i(arlen[24 +: 4]),
        .p6_arvalid_i(arvalid[6 +: 1]),
        .p6_arready_o(arready[6 +: 1]),
        .p6_rid_o(rid[6 +: 1]),
        .p6_rdata_o(rdata[1536 +: 256]),
        .p6_rresp_o(rresp[12 +: 2]),
        .p6_rlast_o(rlast[6 +: 1]),
        .p6_rvalid_o(rvalid[6 +: 1]),
        .p6_rready_i(rready[6 +: 1]),
        .ddr_awid_o(ddr_awid_o),
        .ddr_awaddr_o(ddr_awaddr_o),
        .ddr_awlen_o(ddr_awlen_o),
        .ddr_awvalid_o(ddr_awvalid_o),
        .ddr_awready_i(ddr_awready_i),
        .ddr_wdata_o(ddr_wdata_o),
        .ddr_wstrb_o(ddr_wstrb_o),
        .ddr_wlast_o(ddr_wlast_o),
        .ddr_wvalid_o(ddr_wvalid_o),
        .ddr_wready_i(ddr_wready_i),
        .ddr_bid_i(ddr_bid_i),
        .ddr_bresp_i(ddr_bresp_i),
        .ddr_bvalid_i(ddr_bvalid_i),
        .ddr_arid_o(ddr_arid_o),
        .ddr_araddr_o(ddr_araddr_o),
        .ddr_arlen_o(ddr_arlen_o),
        .ddr_arvalid_o(ddr_arvalid_o),
        .ddr_arready_i(ddr_arready_i),
        .ddr_rid_i(ddr_rid_i),
        .ddr_rdata_i(ddr_rdata_i),
        .ddr_rresp_i(ddr_rresp_i),
        .ddr_rlast_i(ddr_rlast_i),
        .ddr_rvalid_i(ddr_rvalid_i),
        .apb_paddr_i(apb_paddr_i),
        .apb_psel_i(apb_psel_i),
        .apb_penable_i(apb_penable_i),
        .apb_pwrite_i(apb_pwrite_i),
        .apb_pwdata_i(apb_pwdata_i),
        .apb_pstrb_i(apb_pstrb_i),
        .apb_pready_o(apb_pready_o),
        .apb_prdata_o(apb_prdata_o),
        .apb_pslverr_o(apb_pslverr_o),
        .irq_o(irq_o)
    );
    assign bvalid[0] = 1'b0;
    reg reverse_reads = 0;
    wire [7:0] read_slot = reverse_reads ? 8'(read_head ^ 1) : 8'(read_head);
    reg [1:0] injected_resp = 0;
    reg return_reads = 0;
    reg return_writes = 0;
    reg [3:0] read_id [0:255];
    reg [31:0] read_addr [0:255];
    reg [3:0] read_len [0:255];
    integer read_head = 0;
    integer read_tail = 0;
    integer read_beat = 0;
    reg [3:0] write_id [0:255];
    reg [31:0] write_addr [0:255];
    reg [3:0] write_len [0:255];
    integer write_head = 0;
    integer write_tail = 0;
    integer write_beat = 0;
    reg [3:0] response_id [0:255];
    integer response_head = 0;
    integer response_tail = 0;
    reg [255:0] expected_data [0:13][0:4095];
    reg [1:0] expected_resp [0:13][0:4095];
    reg expected_last [0:13][0:4095];
    integer expected_head [0:13];
    integer expected_tail [0:13];
    reg [1:0] expected_bresp [0:13][0:255];
    integer expected_bhead [0:13];
    integer expected_btail [0:13];
    bit expected_port_id [0:6][0:255];
    integer expected_port_head [0:6];
    integer expected_port_tail [0:6];
    integer ar_seen = 0;
    integer aw_seen = 0;
    integer r_seen = 0;
    integer b_seen = 0;
    integer cycles = 0;
    integer monitor_p;
    integer monitor_q;
    integer monitor_i;
    reg check_limits = 1;
    integer live_downstream = 0;
    integer live_reads [0:6];
    integer live_writes [0:6];
    integer cfg_total = 8;
    integer cfg_rd [0:6];
    integer cfg_wr [0:6];
    reg w_contiguous = 0;
    reg [288:0] held_w;
    reg held_w_valid = 0;
    reg [39:0] held_cmd;
    reg held_cmd_valid = 0;
    reg held_cmd_write = 0;

    integer ar_start [0:6];
    integer aw_start [0:6];
    integer w_start [0:6];
    integer obs_rd_txn [0:6];
    integer obs_wr_txn [0:6];
    integer obs_rd_beats [0:6];
    integer obs_wr_beats [0:6];
    integer obs_wait_sum [0:6];
    integer obs_wait_max [0:6];
    integer obs_urgent [0:6];
    integer snap_rd_txn [0:6];
    integer snap_wr_txn [0:6];
    integer snap_rd_beats [0:6];
    integer snap_wr_beats [0:6];
    integer snap_wait_sum [0:6];
    integer snap_wait_max [0:6];
    integer snap_urgent [0:6];
    integer obs_window = 0;
    integer obs_busy = 0;
    integer obs_switch = 0;
    integer snap_window = 0;
    integer snap_busy = 0;
    integer snap_switch = 0;
    integer elapsed;
    bit obs_dir_valid = 0;
    bit obs_dir = 0;
    wire stat_clear = apb_psel_i && apb_penable_i && apb_pwrite_i &&
                      apb_paddr_i == 'h110 && apb_pwdata_i[1];
    wire stat_snapshot = apb_psel_i && apb_penable_i && apb_pwrite_i &&
                         apb_paddr_i == 'h110 && apb_pwdata_i[0];
    function automatic [255:0] pattern(input [31:0] addr);
        pattern = {8{addr ^ 32'h96a5_c33c}};
    endfunction
    function automatic [31:0] strobe(input integer beat);
        strobe = beat % 2 == 0 ? 32'hffff_ffff : 32'h9249_2492;
    endfunction

    always @(*) begin
        ddr_rvalid_i = return_reads && read_head < read_tail;
        ddr_rid_i = read_id[read_slot];
        ddr_rdata_i = pattern(read_addr[read_slot] + 32*read_beat);
        ddr_rresp_i = injected_resp;
        ddr_rlast_i = read_beat == int'(read_len[read_slot]);
        ddr_bvalid_i = return_writes && response_head < response_tail;
        ddr_bid_i = response_id[response_head % 256];
        ddr_bresp_i = injected_resp;
    end

    always @(posedge clk) begin
        cycles <= cycles + 1;
        if (cycles > 300000) $fatal(1, "FAIL timeout");
        if (!rst_n) begin
            read_head <= 0;
            read_tail <= 0;
            read_beat <= 0;
            write_head <= 0;
            write_tail <= 0;
            write_beat <= 0;
            response_head <= 0;
            response_tail <= 0;
            ar_seen <= 0;
            aw_seen <= 0;
            r_seen <= 0;
            b_seen <= 0;
            live_downstream = 0;
            w_contiguous <= 0;
            held_w_valid <= 0;
            held_cmd_valid <= 0;
            for (monitor_i = 0; monitor_i < 14; monitor_i = monitor_i + 1) begin
                expected_head[monitor_i] = 0;
                expected_tail[monitor_i] = 0;
                expected_bhead[monitor_i] = 0;
                expected_btail[monitor_i] = 0;
            end
            for (monitor_i = 0; monitor_i < 7; monitor_i = monitor_i + 1) begin
                expected_port_head[monitor_i] = 0;
                expected_port_tail[monitor_i] = 0;
                live_reads[monitor_i] = 0;
                live_writes[monitor_i] = 0;
                cfg_rd[monitor_i] = monitor_i == 1 ? 2 : monitor_i == 2 ? 1 :
                                   monitor_i == 0 || monitor_i == 3 ? 4 : 2;
                cfg_wr[monitor_i] = monitor_i == 0 ? 0 : monitor_i == 2 ? 1 :
                                   monitor_i == 1 ? 4 : 2;
            end
            cfg_total = 8;
            obs_window = 0;
            obs_busy = 0;
            obs_switch = 0;
            obs_dir_valid = 0;
            for (monitor_i = 0; monitor_i < 7; monitor_i = monitor_i + 1) begin
                obs_rd_txn[monitor_i] = 0;
                obs_wr_txn[monitor_i] = 0;
                obs_rd_beats[monitor_i] = 0;
                obs_wr_beats[monitor_i] = 0;
                obs_wait_sum[monitor_i] = 0;
                obs_wait_max[monitor_i] = 0;
                obs_urgent[monitor_i] = 0;
                ar_start[monitor_i] = 0;
                aw_start[monitor_i] = 0;
                w_start[monitor_i] = 0;
            end
        end else begin
            if (stat_snapshot) begin
                snap_window = obs_window;
                snap_busy = obs_busy;
                snap_switch = obs_switch;
                for (monitor_i = 0; monitor_i < 7; monitor_i = monitor_i + 1) begin
                    snap_rd_txn[monitor_i] = obs_rd_txn[monitor_i];
                    snap_wr_txn[monitor_i] = obs_wr_txn[monitor_i];
                    snap_rd_beats[monitor_i] = obs_rd_beats[monitor_i];
                    snap_wr_beats[monitor_i] = obs_wr_beats[monitor_i];
                    snap_wait_sum[monitor_i] = obs_wait_sum[monitor_i];
                    snap_wait_max[monitor_i] = obs_wait_max[monitor_i];
                    snap_urgent[monitor_i] = obs_urgent[monitor_i];
                end
            end
            if (stat_clear) begin
                obs_window = 0;
                obs_busy = 0;
                obs_switch = 0;
                for (monitor_i = 0; monitor_i < 7; monitor_i = monitor_i + 1) begin
                    obs_rd_txn[monitor_i] = 0;
                    obs_wr_txn[monitor_i] = 0;
                    obs_rd_beats[monitor_i] = 0;
                    obs_wr_beats[monitor_i] = 0;
                    obs_wait_sum[monitor_i] = 0;
                    obs_wait_max[monitor_i] = 0;
                    obs_urgent[monitor_i] = 0;
                end
            end else begin
                obs_window = obs_window+1;
                if (live_downstream != 0) obs_busy = obs_busy+1;
            end
            for (monitor_i = 0; monitor_i < 7; monitor_i = monitor_i + 1) begin
                if (arvalid[monitor_i] && arready[monitor_i]) ar_start[monitor_i] = cycles;
                if (awvalid[monitor_i] && awready[monitor_i]) aw_start[monitor_i] = cycles;
                if (wvalid[monitor_i] && wready[monitor_i] && wlast[monitor_i])
                    w_start[monitor_i] = cycles;
            end
            if (held_cmd_valid) begin
                if (held_cmd_write) begin
                    if (!ddr_awvalid_o || {ddr_awid_o,ddr_awaddr_o,ddr_awlen_o} !== held_cmd)
                        $fatal(1, "FAIL AW changed while stalled");
                end else if (!ddr_arvalid_o ||
                             {ddr_arid_o,ddr_araddr_o,ddr_arlen_o} !== held_cmd)
                    $fatal(1, "FAIL AR changed while stalled");
            end
            held_cmd_valid <= (ddr_awvalid_o && !ddr_awready_i) ||
                              (ddr_arvalid_o && !ddr_arready_i);
            held_cmd_write <= ddr_awvalid_o;
            held_cmd <= ddr_awvalid_o ? {ddr_awid_o,ddr_awaddr_o,ddr_awlen_o} :
                                        {ddr_arid_o,ddr_araddr_o,ddr_arlen_o};
            if (held_w_valid && (!ddr_wvalid_o ||
                {ddr_wlast_o,ddr_wstrb_o,ddr_wdata_o} !== held_w))
                $fatal(1, "FAIL W changed while stalled");
            held_w_valid <= ddr_wvalid_o && !ddr_wready_i;
            held_w <= {ddr_wlast_o,ddr_wstrb_o,ddr_wdata_o};
            if (w_contiguous && !ddr_wvalid_o) $fatal(1, "FAIL gap within W burst");
            if (ddr_arvalid_o && ddr_arready_i) begin
                monitor_p = int'(ddr_arid_o[3:1]);
                if (check_limits && (live_downstream >= cfg_total ||
                    live_reads[monitor_p] >= cfg_rd[monitor_p]))
                    $fatal(1, "FAIL read outstanding limit p%0d", monitor_p);
                if (!stat_clear) begin
                    elapsed = cycles-ar_start[monitor_p];
                    obs_rd_txn[monitor_p] = obs_rd_txn[monitor_p]+1;
                    obs_rd_beats[monitor_p] = obs_rd_beats[monitor_p]+int'(ddr_arlen_o)+1;
                    obs_wait_sum[monitor_p] = obs_wait_sum[monitor_p]+elapsed;
                    if (elapsed > obs_wait_max[monitor_p]) obs_wait_max[monitor_p] = elapsed;
                    if (obs_dir_valid && obs_dir) obs_switch = obs_switch+1;
                    // Tests only assert urgent on P0/P1; the selected command retains class.
                    if (monitor_p < 2 && dut.cmd_urgent_r) obs_urgent[monitor_p]++;
                end
                obs_dir_valid = 1;
                obs_dir = 0;
                read_id[read_tail % 256] <= ddr_arid_o;
                read_addr[read_tail % 256] <= ddr_araddr_o;
                read_len[read_tail % 256] <= ddr_arlen_o;
                read_tail <= read_tail + 1;
                live_downstream = live_downstream + 1;
                live_reads[monitor_p] = live_reads[monitor_p] + 1;
                ar_seen <= ar_seen + 1;
            end
            if (ddr_awvalid_o && ddr_awready_i) begin
                monitor_p = int'(ddr_awid_o[3:1]);
                if (check_limits && (live_downstream >= cfg_total ||
                    live_writes[monitor_p] >= cfg_wr[monitor_p]))
                    $fatal(1, "FAIL write outstanding limit p%0d", monitor_p);
                if (!stat_clear) begin
                    elapsed = cycles-(aw_start[monitor_p] > w_start[monitor_p] ?
                                      aw_start[monitor_p] : w_start[monitor_p]);
                    obs_wr_txn[monitor_p] = obs_wr_txn[monitor_p]+1;
                    obs_wr_beats[monitor_p] = obs_wr_beats[monitor_p]+int'(ddr_awlen_o)+1;
                    obs_wait_sum[monitor_p] = obs_wait_sum[monitor_p]+elapsed;
                    if (elapsed > obs_wait_max[monitor_p]) obs_wait_max[monitor_p] = elapsed;
                    if (obs_dir_valid && !obs_dir) obs_switch = obs_switch+1;
                    if (monitor_p == 1 && dut.cmd_urgent_r) obs_urgent[monitor_p]++;
                end
                obs_dir_valid = 1;
                obs_dir = 1;
                write_id[write_tail % 256] <= ddr_awid_o;
                write_addr[write_tail % 256] <= ddr_awaddr_o;
                write_len[write_tail % 256] <= ddr_awlen_o;
                write_tail <= write_tail + 1;
                live_downstream = live_downstream + 1;
                live_writes[monitor_p] = live_writes[monitor_p] + 1;
                aw_seen <= aw_seen + 1;
            end
            if (ddr_wvalid_o && ddr_wready_i) begin
                if (write_head >= write_tail) $fatal(1, "FAIL W before AW");
                if (ddr_wdata_o !== pattern(write_addr[write_head % 256]+32*write_beat) ||
                    ddr_wstrb_o !== strobe(write_beat) ||
                    ddr_wlast_o !== (write_beat == int'(write_len[write_head % 256])))
                    $fatal(1, "FAIL W payload beat=%0d at %0t", write_beat, $time);
                w_contiguous <= !ddr_wlast_o;
                if (ddr_wlast_o) begin
                    response_id[response_tail % 256] <= write_id[write_head % 256];
                    response_tail <= response_tail + 1;
                    write_head <= write_head + 1;
                    write_beat <= 0;
                end else write_beat <= write_beat + 1;
            end
            if (ddr_rvalid_i) begin
                if (ddr_rlast_i) begin
                    read_head <= read_head + 1;
                    read_beat <= 0;
                    live_downstream = live_downstream - 1;
                end else read_beat <= read_beat + 1;
            end
            if (ddr_bvalid_i) begin
                response_head <= response_head + 1;
                live_downstream = live_downstream - 1;
            end
            for (monitor_p = 0; monitor_p < 7; monitor_p = monitor_p + 1) begin
                if (rvalid[monitor_p] && rready[monitor_p]) begin
                    if (rid[monitor_p] !==
                        expected_port_id[monitor_p][expected_port_head[monitor_p] % 256])
                        $fatal(1,"FAIL per-port read grant ordering p%0d",monitor_p);
                    if (rlast[monitor_p]) expected_port_head[monitor_p]++;
                    monitor_q = monitor_p*2 + int'(rid[monitor_p]);
                    monitor_i = expected_head[monitor_q] % 4096;
                    if (expected_head[monitor_q] >= expected_tail[monitor_q])
                        $fatal(1, "FAIL unexpected R p%0d", monitor_p);
                    if (rdata[monitor_p*256 +: 256] !== expected_data[monitor_q][monitor_i] ||
                        rresp[monitor_p*2 +: 2] !== expected_resp[monitor_q][monitor_i] ||
                        rlast[monitor_p] !== expected_last[monitor_q][monitor_i])
                        $fatal(1, "FAIL R p%0d id%0d n%0d got %h/%b/%b want %h/%b/%b t%0t",
                               monitor_p,rid[monitor_p],monitor_i,
                               rdata[monitor_p*256 +: 32],rresp[monitor_p*2 +: 2],
                               rlast[monitor_p],expected_data[monitor_q][monitor_i][31:0],
                               expected_resp[monitor_q][monitor_i],
                               expected_last[monitor_q][monitor_i],$time);
                    if (rlast[monitor_p] && rresp[monitor_p*2 +: 2] == 0)
                        live_reads[monitor_p] = live_reads[monitor_p] - 1;
                    expected_head[monitor_q] = expected_head[monitor_q] + 1;
                    r_seen <= r_seen + 1;
                end
                if (bvalid[monitor_p] && bready[monitor_p]) begin
                    monitor_q = monitor_p*2 + int'(bid[monitor_p]);
                    if (expected_bhead[monitor_q] >= expected_btail[monitor_q] ||
                        bresp[monitor_p*2 +: 2] !==
                        expected_bresp[monitor_q][expected_bhead[monitor_q] % 256])
                        $fatal(1, "FAIL B p%0d id%0d resp%0d",monitor_p,bid[monitor_p],
                               bresp[monitor_p*2 +: 2]);
                    if (bresp[monitor_p*2 +: 2] == 0)
                        live_writes[monitor_p] = live_writes[monitor_p] - 1;
                    expected_bhead[monitor_q] = expected_bhead[monitor_q] + 1;
                    b_seen <= b_seen + 1;
                end
            end
            if (dut.free_cnt_w > 128) $fatal(1, "FAIL read credit overflow");
        end
    end

    task automatic tick(input integer n);
        repeat (n) @(negedge clk);
    endtask
    task automatic reset;
        @(negedge clk);
        rst_n = 0;
        awvalid = 0;
        arvalid = 0;
        wvalid = 0;
        rready = '1;
        bready = '1;
        urgent = 0;
        return_reads = 1;
        return_writes = 1;
        injected_resp = 0;
        reverse_reads = 0;
        check_limits = 1;
        ddr_awready_i = 1;
        ddr_arready_i = 1;
        ddr_wready_i = 1;
        apb_psel_i = 0;
        apb_penable_i = 0;
        tick(3);
        if ({ddr_awvalid_o,ddr_arvalid_o,ddr_wvalid_o,rvalid,bvalid} !== 17'b0)
            $fatal(1, "FAIL reset control/X");
        rst_n = 1;
        tick(2);
        if ({ddr_awvalid_o,ddr_arvalid_o,ddr_wvalid_o,rvalid,bvalid} !== 17'b0)
            $fatal(1, "FAIL idle control/X DDR=%b%b%b R=%b B=%b cmd=%b grant=%b eligible=%b",
                ddr_awvalid_o,ddr_arvalid_o,ddr_wvalid_o,rvalid,bvalid,dut.cmd_valid_r,
                dut.grant_w,dut.eligible_w);
    endtask
    task automatic apb_write(input [11:0] addr, input [31:0] value);
        @(negedge clk);
        apb_paddr_i = addr;
        apb_pwdata_i = value;
        apb_pstrb_i = 0; // The agreed register contract ignores PSTRB.
        apb_pwrite_i = 1;
        apb_psel_i = 1;
        apb_penable_i = 0;
        @(negedge clk);
        apb_penable_i = 1;
        @(posedge clk);
        if (!apb_pready_o || apb_pslverr_o) $fatal(1, "FAIL APB write");
        @(negedge clk);
        apb_psel_i = 0;
        apb_penable_i = 0;
        if (addr == 'h100) cfg_total = int'({28'b0,value[3:0]});
        for (integer p = 0; p < 7; p = p + 1) begin
            if (int'(addr) == 'h200+32*p) cfg_rd[p] = int'({28'b0,value[3:0]});
            if (int'(addr) == 'h204+32*p) cfg_wr[p] = int'({28'b0,value[3:0]});
        end
    endtask
    task automatic apb_check(input [11:0] addr, input [31:0] value);
        @(negedge clk);
        apb_paddr_i = addr;
        apb_pwrite_i = 0;
        apb_psel_i = 1;
        apb_penable_i = 0;
        @(negedge clk);
        apb_penable_i = 1;
        @(posedge clk);
        if (!apb_pready_o || apb_pslverr_o || apb_prdata_o !== value)
            $fatal(1,"FAIL APB[%h] expected=%h actual=%h at %0t",addr,value,apb_prdata_o,$time);
        @(negedge clk);
        apb_psel_i = 0;
        apb_penable_i = 0;
    endtask
    task automatic send_read(input integer p, input bit id, input [31:0] addr,
                             input integer len, input bit error);
        integer q;
        integer e;
        @(negedge clk);
        q = p*2+int'(id);
        expected_port_id[p][expected_port_tail[p] % 256] = id;
        expected_port_tail[p]++;
        for (integer i = 0; i <= len; i = i + 1) begin
            e = expected_tail[q] % 4096;
            expected_data[q][e] = error ? 256'b0 : pattern(addr+32*i);
            expected_resp[q][e] = error ? 2'b10 : 2'b00;
            expected_last[q][e] = i == len;
            expected_tail[q] = expected_tail[q] + 1;
        end
        arid[p] = id;
        araddr[p*32 +: 32] = addr;
        arlen[p*4 +: 4] = 4'(len);
        arvalid[p] = 1;
        do @(posedge clk); while (!arready[p]);
        @(negedge clk);
        arvalid[p] = 0;
    endtask
    task automatic send_aw(input integer p, input bit id, input [31:0] addr,
                           input integer len, input bit error);
        integer q;
        @(negedge clk);
        q = p*2+int'(id);
        expected_bresp[q][expected_btail[q] % 256] = error ? 2'b10 : 2'b00;
        expected_btail[q] = expected_btail[q]+1;
        awid[p] = id;
        awaddr[p*32 +: 32] = addr;
        awlen[p*4 +: 4] = 4'(len);
        awvalid[p] = 1;
        do @(posedge clk); while (!awready[p]);
        @(negedge clk);
        awvalid[p] = 0;
    endtask
    task automatic send_w(input integer p, input [31:0] addr,
                          input integer len, input integer gap);
        for (integer i = 0; i <= len; i = i + 1) begin
            tick(gap);
            @(negedge clk);
            wdata[p*256 +: 256] = pattern(addr+32*i);
            wstrb[p*32 +: 32] = strobe(i);
            wlast[p] = i == len;
            wvalid[p] = 1;
            do @(posedge clk); while (!wready[p]);
            @(negedge clk);
            wvalid[p] = 0;
        end
    endtask
    task automatic send_write(input integer p, input bit id, input [31:0] addr,
                              input integer len, input bit error);
        send_aw(p,id,addr,len,error);
        send_w(p,addr,len,0);
    endtask
    task automatic drain;
        integer remaining;
        integer timeout_count;
        timeout_count = 0;
        remaining = 1;
        while (remaining != 0 || dut.busy_w) begin
            tick(1);
            remaining = 0;
            for (integer q = 0; q < 14; q = q + 1)
                remaining = remaining + expected_tail[q]-expected_head[q] +
                            expected_btail[q]-expected_bhead[q];
            timeout_count = timeout_count + 1;
            if (timeout_count > 5000) $fatal(1,"FAIL drain remaining=%0d",remaining);
        end
    endtask
    task automatic error_pipeline;
        $display("MX-09 X-F1 delayed error capture wins over same-cycle IRQ clear");
        reset;
        apb_write('h00c,2);
        fork
            begin
                send_read(1,1,'h1fff,1,1);
                if (irq_o) $fatal(1,"FAIL ingress IRQ was not delayed at %0t",$time);
            end
            apb_write('h010,2);
        join
        if (!irq_o) $fatal(1,"FAIL new violation lost to IRQ clear at %0t",$time);
        apb_check('h120,1);
        apb_check('h124,'h1fff);
        apb_check('h128,5);
        drain; // The existing scoreboard verifies LEN+1 SLVERR beats and ID.
        apb_write('h110,3);
        apb_check('h420,0);
        apb_check('h424,0);
        apb_check('h434,0);
        apb_check('h438,0);
        apb_write('h010,2);
        if (irq_o) $fatal(1,"FAIL IRQ clear after delayed capture at %0t",$time);
        apb_check('h128,0);
        send_read(1,0,'h2000,3,0);
        send_write(1,0,'h3000,1,0);
        drain;
        apb_write('h110,3);
        apb_check('h420,1);
        apb_check('h424,4);
        apb_check('h434,1);
        apb_check('h438,2);
        apb_write('h110,1);
        apb_check('h420,0);
        apb_check('h424,0);
        apb_check('h434,0);
        apb_check('h438,0);
    endtask

    // Independent scheduler instance for five-rule directed tests without FIFO traffic effects.
    reg s_rst_n = 0;
    reg s_enable = 0;
    reg [13:0] s_eligible = 0;
    reg [13:0] s_blocked = 0;
    wire [13:0] s_queued = s_eligible | s_blocked;
    reg [69:0] s_beats = 0;
    reg [447:0] s_wait = 0;
    reg [1:0] s_urgent = 0;
    wire [13:0] s_starved;
    wire unused_s_prepare;
    for (genvar n = 0; n < 14; n++) begin : g_starved
        assign s_starved[n] = s_wait[n*32 +: 32] > {16'b0, s_starve};
    end
    wire s_grant;
    wire [2:0] s_port;
    wire s_write;
    wire s_is_urgent;
    wire s_switch;
    reg [7:0] s_urg_max = 8;
    reg [15:0] s_starve = 256;
    reg [7:0] s_batch = 4;
    reg [27:0] s_weight = 0;
    reg [62:0] s_rate = 0;
    edrv32_mem_xbar_sched scheduler (
        .clk_i(clk),
        .rst_n_i(s_rst_n),
        .enable_i(s_enable),
        .prepare_o(unused_s_prepare),
        .candidates_i(s_eligible),
        .queued_i(s_queued),
        .eligible_i(s_eligible),
        .beats_i(s_beats),
        .starved_i(s_starved),
        .urgent_i(s_urgent),
        .grant_o(s_grant),
        .port_o(s_port),
        .write_o(s_write),
        .urgent_o(s_is_urgent),
        .dir_switch_o(s_switch),
        .urg_max_i(s_urg_max),
        .dir_batch_i(s_batch),
        .weight_i(s_weight),
        .rate_i(s_rate)
    );
    task automatic scheduler_reset;
        @(negedge clk);
        s_rst_n = 0;
        s_enable = 0;
        s_eligible = 0;
        s_blocked = 0;
        s_wait = 0;
        s_urgent = 0;
        s_urg_max = 8;
        s_starve = '1;
        s_batch = 4;
        for (integer p = 0; p < 7; p = p + 1) begin
            s_weight[p*4 +: 4] = p < 2 ? 4 : p == 3 ? 3 : p == 6 ? 1 : 2;
            s_rate[p*9 +: 9] = p == 2 ? 26 : p == 6 ? 13 : 0;
            s_beats[(2*p)*5 +: 5] = 1;
            s_beats[(2*p+1)*5 +: 5] = 1;
        end
        tick(2);
        s_rst_n = 1;
        s_enable = 1;
    endtask
    task automatic scheduler_smoke;
        integer grants;
        integer consecutive;
        bit direction;
        bit saw_normal;
        bit saw_other;
        bit saw_resumed;
        integer urgent_streak;
        $display("MX-01 urgent priority, bounded consecutive grants, re-arm");
        scheduler_reset;
        s_urgent = 1;
        s_urg_max = 2;
        s_weight[0 +: 4] = 0;
        s_eligible[0] = 1;
        s_eligible[6] = 1;
        grants = 0;
        while (grants < 8) begin
            @(posedge clk);
            if (s_grant) begin
                if (s_port !== (grants % 3 == 2 ? 3'd3 : 3'd0))
                    $fatal(1,"FAIL urgent sequence grant=%0d port=%0d",grants,s_port);
                if (s_is_urgent !== (s_port == 0)) $fatal(1,"FAIL urgent accounting");
                grants = grants + 1;
            end
            @(negedge clk);
        end
        // Reaching URG_MAX removes only class-1 priority, not normal DRR eligibility.
        scheduler_reset;
        s_urgent = 1;
        s_urg_max = 2;
        s_eligible[0] = 1;
        s_eligible[6] = 1;
        saw_normal = 0;
        saw_other = 0;
        saw_resumed = 0;
        urgent_streak = 0;
        for (integer i = 0; i < 200; i = i + 1) begin
            @(posedge clk);
            if (s_grant) begin
                if (s_port != 0) begin
                    urgent_streak = 0;
                    saw_other = 1;
                end else if (s_is_urgent) begin
                    urgent_streak++;
                    if (urgent_streak > 2) $fatal(1,"FAIL urgent streak exceeded");
                    if (saw_other) saw_resumed = 1;
                end else saw_normal = 1;
            end
            @(negedge clk);
        end
        if (!saw_normal || !saw_other || !saw_resumed)
            $fatal(1,"FAIL urgent/DRR interaction not exercised");
        scheduler_reset;
        s_urgent = 3;
        s_eligible[0] = 1;
        s_eligible[2] = 1;
        s_eligible[3] = 1;
        grants = 0;
        while (grants < 8) begin
            @(posedge clk);
            if (s_grant) begin
                if (!s_is_urgent || s_port !== 3'(grants % 2))
                    $fatal(1,"FAIL urgent tie rotation");
                grants++;
            end
            @(negedge clk);
        end
        $display("MX-05 direction batching");
        scheduler_reset;
        s_batch = 3;
        s_weight[3*4 +: 4] = 15;
        s_weight[4*4 +: 4] = 15;
        s_eligible[6] = 1;
        s_eligible[9] = 1;
        grants = 0;
        consecutive = 0;
        direction = 1;
        while (grants < 30) begin
            @(posedge clk);
            if (s_grant) begin
                if (grants != 0 && s_write != direction) begin
                    if (consecutive != 3) $fatal(1,"FAIL short direction batch %0d",consecutive);
                    consecutive = 0;
                end
                direction = s_write;
                consecutive = consecutive + 1;
                if (consecutive > 3) $fatal(1,"FAIL direction batch exceeded");
                grants = grants + 1;
            end
            @(negedge clk);
        end
        scheduler_reset;
        s_starve = 8;
        s_eligible = 0;
        s_eligible[6] = 1;
        s_eligible[8] = 1;
        s_eligible[10] = 1;
        s_wait[6*32 +: 32] = 1000;
        s_wait[8*32 +: 32] = 100;
        s_wait[10*32 +: 32] = 10;
        grants = 0;
        while (grants < 9) begin
            @(posedge clk);
            if (s_grant) begin
                if (s_port !== 3'(3+grants%3))
                    $fatal(1,"FAIL rotating starvation grant=%0d p%0d",grants,s_port);
                grants++;
            end
            @(negedge clk);
        end
        s_enable = 0;
    endtask

    task automatic scheduler_full;
        integer grants;
        integer granted [0:6];
        integer cost;
        integer selected_queue;
        integer age;
        integer total;
        integer expected;
        integer delta;
        reg [31:0] lfsr;
        $display("MX-02 fixed-point token rate over 50000 cycles");
        scheduler_reset;
        s_eligible[4] = 1;
        s_eligible[6] = 1;
        s_eligible[12] = 1;
        for (integer p = 0; p < 7; p = p + 1) granted[p] = 0;
        for (integer cycle = 0; cycle < 50000; cycle = cycle + 1) begin
            @(posedge clk);
            if (s_grant) granted[s_port] = granted[s_port] + 1;
            @(negedge clk);
        end
        for (integer p = 2; p <= 6; p = p + 4) begin
            expected = 50000*(p == 2 ? 26 : 13)/256;
            delta = granted[p] > expected ? granted[p]-expected : expected-granted[p];
            if (100*delta > 2*expected) $fatal(1,"FAIL token rate p%0d %0d expected%0d",
                                             p,granted[p],expected);
        end
        $display("MX-03 starvation overrides zero DRR weight");
        scheduler_reset;
        s_starve = 8;
        s_weight[6*4 +: 4] = 0;
        s_rate[6*9 +: 9] = 0;
        s_eligible[6] = 1;
        s_eligible[12] = 1;
        age = 0;
        begin : wait_starve
            for (integer cycle = 0; cycle < 12; cycle = cycle + 1) begin
                @(posedge clk);
                if (s_grant && s_port == 6) begin
                    if (age <= 8 || age > 10) $fatal(1,"FAIL starvation age %0d",age);
                    disable wait_starve;
                end
                @(negedge clk);
                age = age + 1;
                s_wait[12*32 +: 32] = 32'(age);
            end
            $fatal(1,"FAIL starvation never granted");
        end
        $display("MX-04 global capacity full does not refill any deficit");
        scheduler_reset;
        s_eligible[0] = 1;
        @(posedge clk);
        @(negedge clk);
        // Capacity closes after prepare; queued heads remain, but none can grant.
        s_eligible = 0;
        s_blocked = 14'h3fff;
        repeat (8) begin
            @(posedge clk);
            @(negedge clk);
            for (integer p = 0; p < 7; p = p + 1)
                if (scheduler.deficit_r[p] != 0)
                    $fatal(1,"FAIL full global capacity changed deficit p%0d",p);
        end
        $display("MX-04 retain one round while a queued head is capacity blocked");
        scheduler_reset;
        s_eligible[6] = 1;
        s_blocked[0] = 1;
        grants = 0;
        // Four P3 rounds would wrap an unconditional 8-bit P0 accumulation to zero.
        while (grants < 145) begin
            @(posedge clk);
            if (s_grant) begin
                if (s_port != 3) $fatal(1,"FAIL blocked DRR port granted");
                grants++;
            end
        end
        @(negedge clk);
        s_eligible = 1;
        s_blocked = 0;
        @(posedge clk);
        @(negedge clk);
        if (!s_grant || s_port != 0)
            $fatal(1,"FAIL capacity-blocked DRR head lost its round credit");
        $display("MX-04 variable-length DRR weighted beat shares");
        scheduler_reset;
        s_eligible = 14'b01_01_01_01_00_10_01;
        s_rate[6*9 +: 9] = 256;
        lfsr = 32'h57c2_a913;
        for (integer p = 0; p < 7; p = p + 1) begin
            granted[p] = 0;
            s_beats[(p*2)*5 +: 5] = 5'(p+1);
            s_beats[(p*2+1)*5 +: 5] = 5'(p+1);
        end
        for (integer cycle = 0; cycle < 100000; cycle = cycle + 1) begin
            @(posedge clk);
            if (s_grant) begin
                selected_queue = int'(s_port)*2+int'(s_write);
                cost = int'(s_beats[selected_queue*5 +: 5]);
                granted[s_port] = granted[s_port]+cost;
                @(negedge clk);
                lfsr = {lfsr[30:0],lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0]};
                s_beats[selected_queue*5 +: 5] = {1'b0,lfsr[3:0]}+5'd1;
            end else @(negedge clk);
        end
        total = 0;
        for (integer p = 0; p < 7; p = p + 1) total = total + granted[p];
        for (integer p = 0; p < 7; p = p + 1) begin
            if (p != 2) begin
                expected = total*(p < 2 ? 4 : p == 3 ? 3 : p == 6 ? 1 : 2)/16;
                delta = granted[p] > expected ? granted[p]-expected : expected-granted[p];
                if (100*delta > 5*expected) $fatal(1,"FAIL DRR p%0d got%0d expected%0d",
                                                 p,granted[p],expected);
            end
        end
        s_enable = 0;
    endtask
    task automatic crossbar_smoke;
        integer before_count;
        $display("MX-11 all parameter reset values, public layout and runtime writes");
        reset;
        apb_check('h000, 'h0008_0001);
        apb_check('h004, 0);
        apb_check('h008, 2);
        apb_check('h100, 8);
        apb_write('h100,32'hffff_fff8);
        apb_check('h100,8);
        apb_write('h224,32'hffff_fff4);
        apb_check('h224,4);
        apb_check('h104, 8);
        apb_check('h108, 256);
        apb_check('h10c, 4);
        apb_check('h020, 0);
        apb_check('h040, 0);
        apb_check('h7fc, 0);
        for (integer p = 0; p < 7; p = p + 1) begin
            apb_check(12'('h200+32*p), 32'(cfg_rd[p]));
            apb_check(12'('h204+32*p), 32'(cfg_wr[p]));
            apb_check(12'('h208+32*p), p < 2 ? 4 : p == 2 ? 0 :
                      p == 3 ? 3 : p == 6 ? 1 : 2);
            apb_check(12'('h20c+32*p), p == 2 ? 26 : p == 6 ? 13 : 0);
            apb_check(12'('h400+32*p), 0);
        end
        apb_write('h108, 32'hffff_0400);
        apb_check('h108, 1024);
        apb_write('h104, 32'hffff_0003);
        apb_check('h104, 3);
        apb_write('h10c, 32'hffff_0002);
        apb_check('h10c, 2);
        apb_write('h288, 32'hffff_fff7);
        apb_check('h288, 7);
        apb_write('h2cc, 32'hffff_fe4d);
        apb_check('h2cc, 77);
        apb_write('h2cc, 13);
        apb_write('h2a0, 32'hffff_fff0); // P5 reads disabled while the queue is occupied.
        send_read(5, 1, 'h5000, 3, 0);
        tick(12);
        if (ar_seen != 0) $fatal(1,"FAIL disabled port granted");
        apb_write('h2a0, 2);
        drain;
        for (integer p = 0; p < 7; p = p + 1) begin
            send_read(p, 1, 32'('h10000+p*'h1000), p+1, 0);
            if (p != 0) send_write(p, 1, 32'('h20000+p*'h1000), p, 0);
        end
        drain;

        $display("MX-08 late/intermittent W, W-before-AW, continuous output and W stalls");
        reset;
        send_aw(1,1,'h1000,15,0);
        tick(12);
        if (aw_seen != 0) $fatal(1,"FAIL AW granted before W");
        send_read(3,0,'h3000,3,0);
        tick(12);
        if (ar_seen != 1 || aw_seen != 0) $fatal(1,"FAIL late W blocked reads");
        ddr_wready_i = 0;
        send_w(1,'h1000,15,2);
        while (aw_seen == 0) tick(1);
        tick(8);
        ddr_wready_i = 1;
        drain;
        send_w(4,'h4000,7,0);
        tick(4);
        before_count = aw_seen;
        send_aw(4,0,'h4000,7,0);
        drain;
        if (aw_seen != before_count+1) $fatal(1,"FAIL W-before-AW");
        send_write(5,0,'h5000,15,0);
        send_write(6,1,'h6000,15,0);
        drain;

        $display("MX-06 global outstanding limit and runtime shrink");
        reset;
        return_reads = 0;
        for (integer i = 0; i < 4; i = i + 1) begin
            send_read(0,1'((i%2)),32'('h1000+i*32),0,0);
            send_read(3,1'((i%2)),32'('h3000+i*32),0,0);
        end
        while (ar_seen < 8) tick(1);
        send_read(4,0,'h4000,0,0);
        tick(6);
        if (ar_seen != 8) $fatal(1,"FAIL global limit");
        apb_write('h100,2);
        tick(4);
        if (ar_seen != 8) $fatal(1,"FAIL shrink accepted extra work");
        return_reads = 1;
        drain;
        if (ar_seen != 9) $fatal(1,"FAIL global recovery");

        $display("MX-06 port read and write limits remain until upstream completion");
        reset;
        rready[3] = 0;
        for (integer i = 0; i < 4; i = i + 1)
            send_read(3,1'(i%2),32'('h3000+i*32),0,0);
        send_read(3,0,'h3100,0,0);
        tick(12);
        if (ar_seen != 4) $fatal(1,"FAIL port read limit");
        apb_write('h260,1);
        tick(8);
        if (ar_seen != 4) $fatal(1,"FAIL shrinking read limit");
        rready[3] = 1;
        drain;
        reset;
        bready[1] = 0;
        for (integer i = 0; i < 4; i = i + 1)
            send_write(1,1'(i%2),32'('h1000+i*32),0,0);
        send_write(1,0,'h1100,0,0);
        tick(12);
        if (aw_seen != 4) $fatal(1,"FAIL port write limit");
        apb_write('h224,1);
        tick(6);
        if (aw_seen != 4) $fatal(1,"FAIL shrinking write limit");
        bready[1] = 1;
        drain;

        reset;
        apb_write('h224,8);
        bready[1] = 0;
        for (integer i = 0; i < 8; i = i + 1)
            send_write(1,1'(i%2),32'('h1000+i*32),0,0);
        send_write(1,1,'h1200,0,0);
        tick(16);
        if (aw_seen != 8 || dut.b_count_r[1] != 8)
            $fatal(1,"FAIL full eight-entry B FIFO");
        bready[1] = 1;
        drain;

        // Distinct IDs return in reverse order; the model's indexed read selector
        // avoids changing a queue array from two procedural writers.
        reset;
        reverse_reads = 1;
        return_reads = 0;
        send_read(1,0,'h1000,3,0);
        send_read(1,1,'h2000,7,0);
        while (ar_seen != 2) tick(1);
        return_reads = 1;
        drain;
        reverse_reads = 0;

        $display("MX-07 exact 128-beat credit exhaustion under long R backpressure");
        reset;
        rready = 0;
        for (integer i = 0; i < 4; i = i + 1) begin
            send_read(0,1'(i%2),32'('h1000+i*512),15,0);
            send_read(3,1'(i%2),32'('h3000+i*512),15,0);
        end
        tick(150);
        if (ar_seen != 8 || live_downstream != 0 || dut.free_cnt_w != 0)
            $fatal(1,"FAIL credit exhaustion ar=%0d live=%0d free=%0d",ar_seen,
                   live_downstream,dut.free_cnt_w);
        send_read(4,1,'h4000,15,0);
        tick(20);
        if (ar_seen != 8) $fatal(1,"FAIL read granted without credit");
        rready[0] = 1;
        tick(40);
        if (ar_seen != 9) $fatal(1,"FAIL released credit unavailable");
        rready = '1;
        drain;
        if (dut.free_cnt_w != 128) $fatal(1,"FAIL credit leak");

        $display("MX-09 representable violations, SLVERR beat counts, IRQ and recovery");
        reset;
        apb_write('h00c,2);
        send_read(1,1,'hfe0,1,1);
        drain;
        apb_check('h120,1);
        apb_check('h124,'hfe0);
        apb_check('h128,1);
        apb_check('h014,1);
        apb_check('h010,2);
        if (!irq_o) $fatal(1,"FAIL error IRQ");
        send_write(4,0,'h4001,0,1);
        drain;
        apb_check('h128,4);
        send_read(5,0,'h5fff,1,1);
        drain;
        apb_check('h128,5);
        send_write(1,1,'h1fe0,1,1);
        drain;
        apb_check('h128,1);
        send_read(0,1,'h2001,0,1);
        drain;
        apb_check('h128,4);
        send_write(6,1,'h6fff,1,1);
        drain;
        apb_check('h128,5);
        if (ar_seen != 0 || aw_seen != 0) $fatal(1,"FAIL violation reached DDR");
        apb_write('h010,2);
        apb_check('h128,0);
        apb_check('h124,0);
        apb_check('h120,0);
        apb_check('h014,0);
        if (irq_o) $fatal(1,"FAIL IRQ clear");
        send_write(4,1,'h8000,15,0);
        send_read(4,1,'h8000,15,0);
        drain;
        apb_check('h008,2);
        for (integer resp = 2; resp < 4; resp = resp + 1) begin
            injected_resp = 2'(resp);
            rready[3] = 0;
            send_read(3,0,'ha000,1,0);
            expected_resp[6][expected_tail[6]-2] = 2'(resp);
            expected_resp[6][expected_tail[6]-1] = 2'(resp);
            rready[3] = 1;
            bready[4] = 0;
            send_write(4,0,'hb000,1,0);
            expected_bresp[8][expected_btail[8]-1] = 2'(resp);
            bready[4] = 1;
            drain;
            if (irq_o) $fatal(1,"FAIL downstream errors set local IRQ");
        end
        injected_resp = 0;
    endtask
    task automatic compare_snapshot;
        for (integer p = 0; p < 7; p = p + 1) begin
            apb_check(12'('h400+32*p),32'(snap_rd_txn[p]));
            apb_check(12'('h404+32*p),32'(snap_rd_beats[p]));
            apb_check(12'('h414+32*p),32'(snap_wr_txn[p]));
            apb_check(12'('h418+32*p),32'(snap_wr_beats[p]));
            apb_check(12'('h408+32*p),32'(snap_wait_max[p]));
            apb_check(12'('h40c+32*p),32'(snap_wait_sum[p]));
            apb_check(12'('h410+32*p),32'(snap_urgent[p]));
        end
        apb_check('h500,32'(snap_switch));
        apb_check('h504,32'(snap_busy));
        apb_check('h508,32'(snap_window));
    endtask
    task automatic statistics_carry;
        $display("MX-10 X-F1 upper-half carry preserves registered counters and snapshots");
        reset;
        @(negedge clk);
        dut.u_regs.rd_txn_r[0] = 32'h0000_fffe;
        dut.u_regs.rd_beat_r[0] = 32'h0000_fffe;
        dut.u_regs.wr_txn_r[1] = 32'h0000_fffe;
        dut.u_regs.wr_beat_r[1] = 32'h0000_fffe;
        dut.u_regs.wait_sum_r[0] = 32'h0000_fffe;
        dut.u_regs.urg_cnt_r[0] = 32'h0000_fffe;
        dut.u_regs.dir_switch_r = 32'h0000_fffe;
        dut.u_regs.ds_busy_r = 32'h0000_fffe;
        dut.u_regs.window_cyc_r = 32'h0000_fffe;
        obs_rd_txn[0] = 'hfffe;
        obs_rd_beats[0] = 'hfffe;
        obs_wr_txn[1] = 'hfffe;
        obs_wr_beats[1] = 'hfffe;
        obs_wait_sum[0] = 'hfffe;
        obs_urgent[0] = 'hfffe;
        obs_switch = 'hfffe;
        obs_busy = 'hfffe;
        // Injection sets the live counter; the reference remains one event ahead.
        obs_window = 'hffff;
        urgent[0] = 1;
        send_read(0,0,'h1000,3,0);
        drain;
        send_read(0,1,'h2000,3,0);
        drain;
        send_write(1,0,'h3000,0,0);
        drain;
        send_write(1,1,'h3800,1,0);
        drain;
        send_read(3,0,'h4000,0,0);
        drain;
        apb_write('h110,3);
        compare_snapshot;
        apb_write('h110,1);
        compare_snapshot;
    endtask

    task automatic statistics_full;
        $display("MX-10 handshake counters, wait timestamps, atomic snapshots and CLEAR");
        reset;
        apb_write('h110,2);
        urgent = 3;
        send_read(0,1,'h1000,15,0);
        send_read(1,1,'h1800,3,0);
        send_aw(1,0,'h2000,7,0);
        tick(12); // W-late time must not enter WAIT statistics.
        send_w(1,'h2000,7,2);
        ddr_arready_i = 0;
        send_read(3,0,'h3000,3,0);
        tick(10); // Downstream address backpressure must enter WAIT.
        ddr_arready_i = 1;
        drain;
        urgent = 0;
        send_read(3,0,'h8000,2,0);
        drain;
        send_write(3,0,'h9000,4,0);
        drain;
        send_read(3,1,'ha000,0,0);
        drain;
        send_write(3,1,'hb000,1,0);
        drain;
        for (integer p = 2; p < 7; p = p + 1) begin
            send_read(p,1,32'('h10000+p*'h1000),p,0);
            send_write(p,0,32'('h20000+p*'h1000),p+1,0);
        end
        drain;
        apb_write('h110,1);
        compare_snapshot;
        send_read(4,0,'h50000,0,0);
        drain;
        compare_snapshot; // Read registers remain stable until another SNAPSHOT.
        apb_write('h110,3);
        compare_snapshot;
        apb_write('h110,1);
        compare_snapshot;
        for (integer p = 0; p < 7; p = p + 1) begin
            if (snap_rd_txn[p] != 0 || snap_rd_beats[p] != 0 ||
                snap_wr_txn[p] != 0 || snap_wr_beats[p] != 0 || snap_wait_sum[p] != 0 ||
                snap_wait_max[p] != 0 || snap_urgent[p] != 0)
                $fatal(1,"FAIL clear p%0d",p);
        end
        reset;
        apb_write('h260,0);
        apb_write('h108,65535);
        send_read(3,0,'h3000,0,0);
        @(negedge clk);
        dut.ar_wait_r[3] = 16'hfffe;
        tick(4);
        if (dut.ar_wait_r[3] !== 16'hffff || dut.ar_starved_r[3])
            $fatal(1,"FAIL 16-bit wait saturation");
        apb_write('h108,0);
        tick(2);
        if (!dut.ar_starved_r[3]) $fatal(1,"FAIL saturated head starvation update");
        apb_write('h260,4);
        drain;
        apb_write('h110,1);
        apb_check('h468,65535);
        apb_check('h46c,65535);
        $display("MX-10 saturating counters via testbench initial-value injection");
        reset;
        // No RTL test parameters: inject real counter state while the clock is low.
        @(negedge clk);
        dut.u_regs.rd_txn_r[0] = 32'hffff_fffe;
        dut.u_regs.rd_beat_r[0] = 32'hffff_fffe;
        dut.u_regs.wr_txn_r[1] = 32'hffff_fffe;
        dut.u_regs.wr_beat_r[1] = 32'hffff_fffe;
        dut.u_regs.wait_sum_r[0] = 32'hffff_fffe;
        dut.u_regs.wait_max_r[0] = 16'hffff;
        dut.u_regs.urg_cnt_r[0] = 32'hffff_fffe;
        dut.u_regs.dir_switch_r = 32'hffff_fffe;
        dut.u_regs.ds_busy_r = 32'hffff_fffe;
        dut.u_regs.window_cyc_r = 32'hffff_fffe;
        urgent[0] = 1;
        send_read(0,0,'h1000,3,0);
        send_read(0,1,'h2000,3,0);
        send_write(1,0,'h3000,0,0);
        send_write(1,1,'h3800,1,0);
        send_read(3,0,'h4000,0,0);
        drain;
        apb_write('h110,1);
        apb_check('h400,32'hffff_ffff);
        apb_check('h404,32'hffff_ffff);
        apb_check('h434,32'hffff_ffff);
        apb_check('h438,32'hffff_ffff);
        apb_check('h408,32'h0000_ffff);
        apb_check('h40c,32'hffff_ffff);
        apb_check('h410,32'hffff_ffff);
        apb_check('h500,32'hffff_ffff);
        apb_check('h504,32'hffff_ffff);
        apb_check('h508,32'hffff_ffff);
        apb_write('h110,2);
        apb_write('h110,1);
        apb_check('h400,0);
        apb_check('h404,0);
        apb_check('h434,0);
        apb_check('h438,0);
        apb_check('h408,0);
        apb_check('h40c,0);
        apb_check('h410,0);
        apb_check('h500,0);
        apb_check('h504,0);
    endtask

    initial begin
        awid = 0;
        awaddr = 'x;
        awlen = 'x;
        awvalid = 0;
        wdata = 'x;
        wstrb = 'x;
        wlast = 'x;
        wvalid = 0;
        arid = 0;
        araddr = 'x;
        arlen = 'x;
        arvalid = 0;
        rready = '1;
        bready = '1;
        urgent = 0;
        apb_paddr_i = 0;
        apb_psel_i = 0;
        apb_penable_i = 0;
        apb_pwrite_i = 0;
        apb_pwdata_i = 0;
        apb_pstrb_i = 0;
        ddr_awready_i = 1;
        ddr_arready_i = 1;
        ddr_wready_i = 1;
        if (FULL != 0) begin
            reset;
            scheduler_full;
            statistics_carry;
            statistics_full;
        end else begin
            error_pipeline;
            scheduler_smoke;
            crossbar_smoke;
        end
        $display("PASS mem_xbar FULL=%0d",FULL);
        $finish;
    end
endmodule
