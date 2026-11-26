// File: tb.sv
// Spec: mem-subsys-testplan MX-01 through MX-11 (MX-12 belongs to M-V1).
// Description: Directed scheduler and crossbar checks with an unthrottled DDR return model.
// Clock: clk_mem; Icarus also checks control validity over uninitialized DRM payloads.
`timescale 1ns/1ps
module tb;
    parameter FULL = 0;
    parameter ST = 0;
    reg clk = 0;
    always #4 clk = ~clk;
    reg rst_n = 0;
    reg [4:0] awid;
    reg [159:0] awaddr;
    reg [19:0] awlen;
    reg [4:0] awvalid;
    wire [4:0] awready;
    reg [1279:0] wdata;
    reg [159:0] wstrb;
    reg [4:0] wlast;
    reg [4:0] wvalid;
    wire [4:0] wready;
    wire [4:0] bid;
    wire [9:0] bresp;
    wire [4:0] bvalid;
    reg [4:0] bready;
    reg [4:0] arid;
    reg [159:0] araddr;
    reg [19:0] arlen;
    reg [4:0] arvalid;
    wire [4:0] arready;
    wire [4:0] rid;
    wire [1279:0] rdata;
    wire [9:0] rresp;
    wire [4:0] rlast;
    wire [4:0] rvalid;
    reg [4:0] rready;
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

    assign {awready[1:0], wready[1:0], bid[1:0], bresp[3:0], bvalid[1:0]} = 0;

    edrv32_mem_xbar_gpu dut (
        .clk_i(clk),
        .rst_n_i({4{rst_n}}),
        .rst_mem_regs_n_i({3{rst_n}}),
        .rst_mem_stat_n_i({15{rst_n}}),
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
    reg reverse_reads = 0;
    reg [1:0] injected_resp = 0;
    reg return_reads = 0;
    reg return_writes = 0;
    reg [3:0] read_id [0:255];
    reg [31:0] read_addr [0:255];
    reg [3:0] read_len [0:255];
    integer read_head = 0;
    wire [7:0] read_slot = reverse_reads ? 8'(read_head ^ 1) : 8'(read_head);
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
    reg [255:0] expected_data [0:9][0:4095];
    reg [1:0] expected_resp [0:9][0:4095];
    reg expected_data_valid [0:9][0:4095];
    reg expected_last [0:9][0:4095];
    integer expected_head [0:9];
    integer expected_tail [0:9];
    reg [1:0] expected_bresp [0:9][0:255];
    integer expected_bhead [0:9];
    integer expected_btail [0:9];
    bit expected_port_id [0:4][0:255];
    integer expected_port_head [0:4];
    integer expected_port_tail [0:4];
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
    integer live_reads [0:4];
    integer live_writes [0:4];
    integer cfg_total = 8;
    integer cfg_rd [0:4];
    integer cfg_wr [0:4];
    reg w_contiguous = 0;
    reg [288:0] held_w;
    reg held_w_valid = 0;
    reg [39:0] held_cmd;
    reg held_cmd_valid = 0;
    reg held_cmd_write = 0;

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
            for (monitor_i = 0; monitor_i < 10; monitor_i = monitor_i + 1) begin
                expected_head[monitor_i] = 0;
                expected_tail[monitor_i] = 0;
                expected_bhead[monitor_i] = 0;
                expected_btail[monitor_i] = 0;
            end
            for (monitor_i = 0; monitor_i < 5; monitor_i = monitor_i + 1) begin
                expected_port_head[monitor_i] = 0;
                expected_port_tail[monitor_i] = 0;
                live_reads[monitor_i] = 0;
                live_writes[monitor_i] = 0;
                cfg_rd[monitor_i] = monitor_i == 1 || monitor_i == 2 ? 1 :
                                   monitor_i == 0 || monitor_i == 3 ? 4 : 2;
                cfg_wr[monitor_i] = monitor_i < 2 ? 0 : monitor_i == 2 ? 1 : 2;
            end
            cfg_total = 8;
        end else begin
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
            for (monitor_p = 0; monitor_p < 5; monitor_p = monitor_p + 1) begin
                if (rvalid[monitor_p] && rready[monitor_p]) begin
                    if (rid[monitor_p] !==
                        expected_port_id[monitor_p][expected_port_head[monitor_p] % 256])
                        $fatal(1,"FAIL per-port read grant ordering p%0d",monitor_p);
                    if (rlast[monitor_p]) expected_port_head[monitor_p]++;
                    monitor_q = monitor_p*2 + int'(rid[monitor_p]);
                    monitor_i = expected_head[monitor_q] % 4096;
                    if (expected_head[monitor_q] >= expected_tail[monitor_q])
                        $fatal(1, "FAIL unexpected R p%0d", monitor_p);
                    if ((expected_data_valid[monitor_q][monitor_i] &&
                        rdata[monitor_p*256 +: 256] !== expected_data[monitor_q][monitor_i]) ||
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
        if ({ddr_awvalid_o,ddr_arvalid_o,ddr_wvalid_o,rvalid,bvalid} !== 13'b0)
            $fatal(1, "FAIL reset control/X");
        rst_n = 1;
        tick(2);
        if ({ddr_awvalid_o,ddr_arvalid_o,ddr_wvalid_o,rvalid,bvalid} !== 13'b0)
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
            expected_data_valid[q][e] = !error;
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
            for (integer q = 0; q < 10; q = q + 1)
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
        apb_check('h474,0);
        apb_check('h478,0);
        apb_write('h010,2);
        if (irq_o) $fatal(1,"FAIL IRQ clear after delayed capture at %0t",$time);
        apb_check('h128,0);
        send_read(1,0,'h2000,3,0);
        send_write(3,0,'h3000,1,0);
        drain;
        apb_write('h110,3);
        apb_check('h420,0);
        apb_check('h424,0);
        apb_check('h474,0);
        apb_check('h478,0);
        apb_write('h110,1);
        apb_check('h420,0);
        apb_check('h424,0);
        apb_check('h474,0);
        apb_check('h478,0);
    endtask

    // ST-02 isolates port arbitration from FIFO traffic and response latency.
    reg s_rst_n = 0;
    reg s_enable = 0;
    reg [9:0] s_eligible = 0;
    reg [1:0] s_urgent = 0;
    wire s_prepare;
    wire s_grant;
    wire [2:0] s_port;
    wire s_write;
    edrv32_mem_xbar_sched_gpu scheduler (
        .clk_i(clk), .rst_n_i(s_rst_n), .enable_i(s_enable),
        .prepare_o(s_prepare), .candidates_i(s_eligible), .eligible_i(s_eligible),
        .urgent_i(s_urgent), .grant_o(s_grant), .port_o(s_port), .write_o(s_write)
    );
    task automatic scheduler_reset;
        @(negedge clk);
        s_rst_n = 0;
        s_enable = 0;
        s_eligible = 0;
        s_urgent = 0;
        tick(2);
        s_rst_n = 1;
        s_enable = 1;
    endtask
    task automatic expect_grant(input integer port, input bit write_dir);
        @(posedge clk);
        while (!s_grant) @(posedge clk);
        if (s_port !== 3'(port) || s_write !== write_dir)
            $fatal(1,"FAIL ST-02 got P%0d write=%b expected P%0d write=%b at %0t",
                s_port,s_write,port,write_dir,$time);
        @(negedge clk);
    endtask
    task automatic scheduler_smoke;
        scheduler_reset;
        s_eligible = 10'b0101010101;
        s_urgent = 3;
        repeat (12) expect_grant(0,0); // No URG_MAX throttling.
        s_eligible[0] = 0; // Capacity/credit-blocked P0 does not participate.
        repeat (3) expect_grant(1,0);
        s_urgent = 0;
        repeat (3) expect_grant(2,0);
        s_eligible[4] = 0;
        s_eligible[0] = 1;
        repeat (3) begin
            expect_grant(0,0);
            expect_grant(1,0);
            expect_grant(3,0);
            expect_grant(4,0);
        end
        // Urgent and CPU grants leave the rotating cursor unchanged.
        expect_grant(0,0);
        s_urgent = 1;
        expect_grant(0,0);
        s_urgent = 0;
        s_eligible[4] = 1;
        expect_grant(2,0);
        s_eligible[4] = 0;
        expect_grant(1,0);
        s_eligible[6] = 0;
        expect_grant(4,0);
        expect_grant(0,0);
        // Independent direction history per port; first contested choice is read.
        scheduler_reset;
        s_eligible = 10'b0011000000;
        repeat (3) begin expect_grant(3,0); expect_grant(3,1); end
        s_eligible = 10'b0000110000;
        repeat (3) begin expect_grant(2,0); expect_grant(2,1); end
        s_enable = 0;
        $display("PASS ST-02 urgent/CPU/rotation/blocked/direction sequences");
    endtask
    task automatic crossbar_smoke;
        integer before_count;
        $display("MX-11 common registers and fixed limits");
        reset;
        apb_check('h000, 'h0008_0001);
        apb_check('h004, 0);
        apb_check('h008, 2);
        for (integer p = 0; p < 5; p = p + 1) begin
            send_read(p, 1, 32'('h10000+p*'h1000), p+1, 0);
            if (p > 1) send_write(p, 1, 32'('h20000+p*'h1000), p, 0);
        end
        drain;

        $display("MX-08 late/intermittent W, W-before-AW, continuous output and W stalls");
        reset;
        send_aw(3,1,'h1000,15,0);
        tick(12);
        if (aw_seen != 0) $fatal(1,"FAIL AW granted before W");
        send_read(3,0,'h3000,3,0);
        tick(12);
        if (ar_seen != 1 || aw_seen != 0) $fatal(1,"FAIL late W blocked reads");
        ddr_wready_i = 0;
        send_w(3,'h1000,15,2);
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
        send_write(3,0,'h5000,15,0);
        send_write(4,1,'h6000,15,0);
        drain;

        $display("MX-06 fixed global outstanding limit");
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
        rready[3] = 1;
        drain;
        reset;
        bready[3] = 0;
        for (integer i = 0; i < 2; i = i + 1)
            send_write(3,1'(i%2),32'('h1000+i*32),0,0);
        send_write(3,0,'h1100,0,0);
        tick(12);
        if (aw_seen != 2 || dut.b_count_r[3] != 2)
            $fatal(1,"FAIL fixed write limit/B FIFO retention");
        bready[3] = 1;
        drain;
        // Distinct IDs return in reverse order; the model's indexed read selector
        // avoids changing a queue array from two procedural writers.
        reset;
        reverse_reads = 1;
        return_reads = 0;
        send_read(3,0,'h1000,3,0);
        send_read(3,1,'h2000,7,0);
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
        send_read(3,0,'h5fff,1,1);
        drain;
        apb_check('h128,5);
        send_write(3,1,'h1fe0,1,1);
        drain;
        apb_check('h128,1);
        send_read(0,1,'h2001,0,1);
        drain;
        apb_check('h128,4);
        send_write(4,1,'h6fff,1,1);
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
    // ST-02: all port/local IDs and every removed register word.
    task automatic gpu_mapping;
        reset;
        for (integer offset = 'h100; offset <= 'h110; offset += 4) begin
            apb_write(12'(offset),'1);
            apb_check(12'(offset),0);
        end
        for (integer offset = 'h200; offset <= 'h508; offset += 4) begin
            apb_write(12'(offset),'1);
            apb_check(12'(offset),0);
        end
        for (integer p = 0; p < 5; p++) begin
            for (integer id = 0; id < 2; id++) begin
                send_read(p,1'(id),32'('h10000+p*4096+id*32),0,0);
                if (p > 1) send_write(p,1'(id),32'('h20000+p*4096+id*32),0,0);
            end
        end
        drain;
        if (ar_seen != 10 || aw_seen != 6) $fatal(1,"FAIL ST-02 mapping counts");
        for (integer p = 0; p < 5; p++) begin
            send_read(p,1'b1,32'('h30001+p*4096),0,1);
            drain;
            apb_check('h120,32'(p));
        end
        scheduler_smoke;
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
        if (ST == 2) begin
            gpu_mapping;
        end else if (FULL != 0) begin
            reset;
            scheduler_smoke;
            crossbar_smoke;
            gpu_mapping;
        end else begin
            error_pipeline;
            scheduler_smoke;
            crossbar_smoke;
        end
        $display("PASS mem_xbar FULL=%0d",FULL);
        $finish;
    end
endmodule
