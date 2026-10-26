// File: fpga_ddr_adapter/tb.sv
// Spec: mem-subsys-testplan AD-01; mem-subsys-spec Appendix A.
// Description: Directed wiring probes and randomized byte-reference transactions.
// Clock domain: DDR IP core_clk / clk_mem.
module tb #(
    parameter integer WUSER_DELAY = 0
);
    reg clk = 0;
    // Testbench clock and reference state deliberately use blocking assignments.
    /* verilator lint_off BLKSEQ */
    always #4 clk = !clk;
    /* verilator lint_on BLKSEQ */
    reg rst_n = 0;
    reg probe = 1;
    reg active = 0;
    reg probe_init = 0;
    wire model_init;
    wire mem_ready;
    reg [3:0] ddr_awid = 0;
    reg [31:0] ddr_awaddr = 0;
    reg [3:0] ddr_awlen = 0;
    reg ddr_awvalid = 0;
    wire ddr_awready;
    reg [255:0] ddr_wdata = 0;
    reg [31:0] ddr_wstrb = 0;
    reg ddr_wlast = 0;
    reg ddr_wvalid = 0;
    wire ddr_wready;
    wire [3:0] ddr_bid;
    wire [1:0] ddr_bresp;
    wire ddr_bvalid;
    reg [3:0] ddr_arid = 0;
    reg [31:0] ddr_araddr = 0;
    reg [3:0] ddr_arlen = 0;
    reg ddr_arvalid = 0;
    wire ddr_arready;
    wire [3:0] ddr_rid;
    wire [255:0] ddr_rdata;
    wire [1:0] ddr_rresp;
    wire ddr_rlast;
    wire ddr_rvalid;
    wire [27:0] axi_awaddr;
    wire axi_awuser_ap;
    wire [3:0] axi_awuser_id;
    wire [3:0] axi_awlen;
    wire axi_awvalid;
    wire axi_awready;
    wire model_awready;
    reg probe_awready = 0;
    assign axi_awready = probe ? probe_awready : model_awready;
    wire [255:0] axi_wdata;
    wire [31:0] axi_wstrb;
    wire axi_wready;
    wire model_wready;
    reg probe_wready = 0;
    assign axi_wready = probe ? probe_wready : model_wready;
    wire [3:0] axi_wusero_id;
    wire [3:0] model_wusero_id;
    reg [3:0] probe_wusero_id = 0;
    assign axi_wusero_id = probe ? probe_wusero_id : model_wusero_id;
    wire axi_wusero_last;
    wire model_wusero_last;
    reg probe_wusero_last = 0;
    assign axi_wusero_last = probe ? probe_wusero_last : model_wusero_last;
    wire [27:0] axi_araddr;
    wire axi_aruser_ap;
    wire [3:0] axi_aruser_id;
    wire [3:0] axi_arlen;
    wire axi_arvalid;
    wire axi_arready;
    wire model_arready;
    reg probe_arready = 0;
    assign axi_arready = probe ? probe_arready : model_arready;
    wire [3:0] axi_rid;
    wire [3:0] model_rid;
    reg [3:0] probe_rid = 0;
    assign axi_rid = probe ? probe_rid : model_rid;
    wire [255:0] axi_rdata;
    wire [255:0] model_rdata;
    reg [255:0] probe_rdata = 0;
    assign axi_rdata = probe ? probe_rdata : model_rdata;
    wire axi_rlast;
    wire model_rlast;
    reg probe_rlast = 0;
    assign axi_rlast = probe ? probe_rlast : model_rlast;
    wire axi_rvalid;
    wire model_rvalid;
    reg probe_rvalid = 0;
    assign axi_rvalid = probe ? probe_rvalid : model_rvalid;

    edrv32_fpga_ddr_adapter u_adapter (
        .ddr_awid_i(ddr_awid),
        .ddr_awaddr_i(ddr_awaddr),
        .ddr_awlen_i(ddr_awlen),
        .ddr_awvalid_i(ddr_awvalid),
        .ddr_awready_o(ddr_awready),
        .ddr_wdata_i(ddr_wdata),
        .ddr_wstrb_i(ddr_wstrb),
        .ddr_wlast_i(ddr_wlast),
        .ddr_wvalid_i(ddr_wvalid),
        .ddr_wready_o(ddr_wready),
        .ddr_bid_o(ddr_bid),
        .ddr_bresp_o(ddr_bresp),
        .ddr_bvalid_o(ddr_bvalid),
        .ddr_arid_i(ddr_arid),
        .ddr_araddr_i(ddr_araddr),
        .ddr_arlen_i(ddr_arlen),
        .ddr_arvalid_i(ddr_arvalid),
        .ddr_arready_o(ddr_arready),
        .ddr_rid_o(ddr_rid),
        .ddr_rdata_o(ddr_rdata),
        .ddr_rresp_o(ddr_rresp),
        .ddr_rlast_o(ddr_rlast),
        .ddr_rvalid_o(ddr_rvalid),
        .axi_awaddr_o(axi_awaddr),
        .axi_awuser_ap_o(axi_awuser_ap),
        .axi_awuser_id_o(axi_awuser_id),
        .axi_awlen_o(axi_awlen),
        .axi_awvalid_o(axi_awvalid),
        .axi_awready_i(axi_awready),
        .axi_wdata_o(axi_wdata),
        .axi_wstrb_o(axi_wstrb),
        .axi_wready_i(axi_wready),
        .axi_wusero_id_i(axi_wusero_id),
        .axi_wusero_last_i(axi_wusero_last),
        .axi_araddr_o(axi_araddr),
        .axi_aruser_ap_o(axi_aruser_ap),
        .axi_aruser_id_o(axi_aruser_id),
        .axi_arlen_o(axi_arlen),
        .axi_arvalid_o(axi_arvalid),
        .axi_arready_i(axi_arready),
        .axi_rid_i(axi_rid),
        .axi_rdata_i(axi_rdata),
        .axi_rlast_i(axi_rlast),
        .axi_rvalid_i(axi_rvalid),
        .ddr_init_done_i(probe ? probe_init : model_init),
        .mem_ready_o(mem_ready)
    );

    pango_ddr3_ip_model #(
        .MEMORY_BYTES(8192),
        .WUSER_DELAY(WUSER_DELAY)
    ) u_ip (
        .core_clk_i(clk),
        .resetn_i(rst_n),
        .axi_awaddr_i(axi_awaddr),
        .axi_awuser_ap_i(axi_awuser_ap),
        .axi_awuser_id_i(axi_awuser_id),
        .axi_awlen_i(axi_awlen),
        .axi_awvalid_i(axi_awvalid),
        .axi_awready_o(model_awready),
        .axi_wdata_i(axi_wdata),
        .axi_wstrb_i(axi_wstrb),
        .axi_wready_o(model_wready),
        .axi_wusero_id_o(model_wusero_id),
        .axi_wusero_last_o(model_wusero_last),
        .axi_araddr_i(axi_araddr),
        .axi_aruser_ap_i(axi_aruser_ap),
        .axi_aruser_id_i(axi_aruser_id),
        .axi_arlen_i(axi_arlen),
        .axi_arvalid_i(axi_arvalid),
        .axi_arready_o(model_arready),
        .axi_rid_o(model_rid),
        .axi_rdata_o(model_rdata),
        .axi_rlast_o(model_rlast),
        .axi_rvalid_o(model_rvalid),
        .ddr_init_done_o(model_init)
    );

    reg [31:0] rng = 32'h1bad_2026;
    reg [7:0] reference_mem [0:8191];
    integer write_addr;
    integer write_left = 0;
    reg [3:0] write_id;
    integer read_addr;
    integer read_left = 0;
    reg [3:0] read_id;
    integer b_count = 0;
    integer r_count = 0;
    integer write_beats = 0;
    integer read_beats = 0;
    integer delayed_b = 0;
    integer stalled_w = 0;
    integer lane;
    integer i;
    integer address;
    integer beats;
    reg [19:0] choice;
    reg [15:0] seen_lengths = 0;
    reg [15:0] seen_ids = 0;
    reg [31:0] seen_lanes = 0;
    reg b_pending = 0;

    function automatic [31:0] random_word;
        begin
            rng = {rng[30:0], rng[31] ^ rng[21] ^ rng[1] ^ rng[0]};
            random_word = rng;
        end
    endfunction

    function automatic [255:0] random_beat;
        integer word_lane;
        reg [255:0] value;
        begin
            for (word_lane = 0; word_lane < 8; word_lane = word_lane + 1)
                value[word_lane*32 +: 32] = random_word();
            random_beat = value;
        end
    endfunction

    task automatic check_wiring;
        begin
            if (axi_awaddr !== ddr_awaddr[29:2] || axi_araddr !== ddr_araddr[29:2])
                $fatal(1, "FAIL address byte/4: AW=%h/%h AR=%h/%h t=%0t",
                    axi_awaddr, ddr_awaddr[29:2], axi_araddr, ddr_araddr[29:2], $time);
            if ({axi_awuser_id, axi_awlen, axi_awvalid, ddr_awready} !==
                {ddr_awid, ddr_awlen, ddr_awvalid, axi_awready})
                $fatal(1, "FAIL AW passthrough t=%0t", $time);
            if ({axi_aruser_id, axi_arlen, axi_arvalid, ddr_arready} !==
                {ddr_arid, ddr_arlen, ddr_arvalid, axi_arready})
                $fatal(1, "FAIL AR passthrough t=%0t", $time);
            if ({axi_wdata, axi_wstrb, ddr_wready} !== {ddr_wdata, ddr_wstrb, axi_wready})
                $fatal(1, "FAIL W data=%h/%h strb=%h/%h ready=%b/%b t=%0t",
                    axi_wdata, ddr_wdata, axi_wstrb, ddr_wstrb,
                    ddr_wready, axi_wready, $time);
            if ({ddr_bid, ddr_bresp, ddr_bvalid} !== {axi_wusero_id, 2'b00, axi_wusero_last})
                $fatal(1, "FAIL B synthesis t=%0t", $time);
            if ({ddr_rid, ddr_rdata, ddr_rresp, ddr_rlast, ddr_rvalid} !==
                {axi_rid, axi_rdata, 2'b00, axi_rlast, axi_rvalid})
                $fatal(1, "FAIL R passthrough t=%0t", $time);
            if ({axi_awuser_ap, axi_aruser_ap} !== 2'b00)
                $fatal(1, "FAIL auto-precharge t=%0t", $time);
            if (mem_ready !== (probe ? probe_init : model_init))
                $fatal(1, "FAIL mem_ready t=%0t", $time);
        end
    endtask

    // These checks enforce the confirmed continuous-W upstream contract.
    // The reference uses the SoC byte address, never the adapter/IP conversion.
    /* verilator lint_off BLKSEQ */
    always @(posedge clk) begin
        check_wiring();
        if (active) begin
            if (ddr_awvalid && ddr_awready) begin
                write_addr = int'(ddr_awaddr);
                write_left = int'(ddr_awlen) + 1;
                write_id = ddr_awid;
                b_pending = 1;
                seen_lengths[ddr_awlen] = 1;
                seen_ids[ddr_awid] = 1;
            end
            if (ddr_wvalid && !ddr_wready)
                stalled_w = stalled_w + 1;
            if (axi_wready) begin
                if (ddr_wvalid !== 1'b1 || write_left == 0)
                    $fatal(1, "FAIL WREADY requires valid W; left=%0d t=%0t", write_left, $time);
                if (ddr_wlast !== (write_left == 1))
                    $fatal(1, "FAIL WLAST: left=%0d actual=%b t=%0t",
                        write_left, ddr_wlast, $time);
                for (lane = 0; lane < 32; lane = lane + 1)
                    if (ddr_wstrb[lane]) begin
                        reference_mem[write_addr + lane] = ddr_wdata[lane*8 +: 8];
                        seen_lanes[lane] = 1;
                    end
                write_addr = write_addr + 32;
                write_left = write_left - 1;
                write_beats = write_beats + 1;
            end
            if (ddr_bvalid) begin
                if (!b_pending || write_left != 0 || ddr_bid !== write_id)
                    $fatal(1, "FAIL B expected id=%h got=%h left=%0d t=%0t",
                        write_id, ddr_bid, write_left, $time);
                b_pending = 0;
                b_count = b_count + 1;
                if (!axi_wready)
                    delayed_b = delayed_b + 1;
            end
            if (ddr_arvalid && ddr_arready) begin
                read_addr = int'(ddr_araddr);
                read_left = int'(ddr_arlen) + 1;
                read_id = ddr_arid;
            end
            if (ddr_rvalid) begin
                if (read_left == 0 || ddr_rid !== read_id ||
                    ddr_rlast !== (read_left == 1))
                    $fatal(1, "FAIL R control id=%h/%h left=%0d last=%b t=%0t",
                        ddr_rid, read_id, read_left, ddr_rlast, $time);
                for (lane = 0; lane < 32; lane = lane + 1)
                    if (ddr_rdata[lane*8 +: 8] !== reference_mem[read_addr + lane])
                        $fatal(1, "FAIL byte[%h] expected=%h actual=%h t=%0t",
                            read_addr + lane, reference_mem[read_addr + lane],
                            ddr_rdata[lane*8 +: 8], $time);
                read_addr = read_addr + 32;
                read_left = read_left - 1;
                read_beats = read_beats + 1;
                if (ddr_rlast)
                    r_count = r_count + 1;
            end
        end
    end

    /* verilator lint_on BLKSEQ */

    task automatic write_txn(input integer addr, input integer count,
                             input reg [3:0] id, input reg [31:0] mask);
        integer k;
        integer target;
        begin
            target = b_count + 1;
            @(negedge clk);
            ddr_awaddr = 32'(addr);
            ddr_awlen = 4'(count - 1);
            ddr_awid = id;
            ddr_awvalid = 1;
            // W is available before the IP can assert its first WREADY.
            ddr_wvalid = 1;
            ddr_wlast = count == 1;
            ddr_wdata = random_beat();
            ddr_wstrb = mask;
            do @(posedge clk); while (!ddr_awready);
            @(negedge clk);
            ddr_awvalid = 0;
            for (k = 0; k < count; k = k + 1) begin
                if (k != 0) begin
                    @(negedge clk);
                    ddr_wlast = k == count - 1;
                    ddr_wdata = random_beat();
                end
                do @(posedge clk); while (!ddr_wready);
            end
            @(negedge clk);
            ddr_wvalid = 0;
            ddr_wlast = 0;
            wait (b_count == target);
        end
    endtask

    task automatic read_txn(input integer addr, input integer count, input reg [3:0] id);
        integer target;
        begin
            target = r_count + 1;
            @(negedge clk);
            ddr_araddr = 32'(addr);
            ddr_arlen = 4'(count - 1);
            ddr_arid = id;
            ddr_arvalid = 1;
            do @(posedge clk); while (!ddr_arready);
            @(negedge clk);
            ddr_arvalid = 0;
            wait (r_count == target);
        end
    endtask

    initial begin
        // Isolated combinational probes cover high physical address bits and
        // arbitrary return payloads, including last pulses without WREADY.
        for (i = 0; i < 128; i = i + 1) begin
            @(negedge clk);
            ddr_awaddr = random_word() & 32'h3fff_ffe0;
            ddr_araddr = random_word() & 32'h3fff_ffe0;
            ddr_awid = 4'(i);
            ddr_arid = 4'(15 - i);
            ddr_awlen = 4'(i);
            ddr_arlen = 4'(15 - i);
            ddr_awvalid = 1'(i);
            ddr_arvalid = !ddr_awvalid;
            ddr_wstrb = random_word();
            ddr_wdata = random_beat();
            probe_rdata = random_beat();
            probe_wready = 1'(i >> 1);
            probe_awready = 1'(i >> 2);
            probe_arready = 1'(i >> 3);
            probe_wusero_last = 1'(i);
            probe_wusero_id = 4'(i);
            probe_rid = 4'(15 - i);
            probe_rlast = 1'(i >> 2);
            probe_rvalid = 1'(i >> 1);
            probe_init = 1'(i >> 3);
            #1;
            check_wiring();
        end
        @(negedge clk);
        ddr_awvalid = 0;
        ddr_arvalid = 0;
        probe = 0;
        repeat (3) @(negedge clk);
        rst_n = 1;
        wait (mem_ready);
        @(negedge clk);
        active = 1;
        // Initialize through the front door, then exercise every length and ID.
        for (i = 0; i < 16; i = i + 1)
            write_txn(i*512, 16, 4'(i), 32'hffff_ffff);
        for (i = 1; i <= 16; i = i + 1) begin
            write_txn(4096 - i*32, i, 4'(i - 1), 32'hffff_ffff);
            read_txn(4096 - i*32, i, 4'(15 - (i - 1)));
        end
        // Isolate each byte enable, including all-zero and all-one masks.
        for (i = 0; i < 32; i = i + 1) begin
            write_txn(4096, 1, 4'(i), 32'b1 << i);
            read_txn(4096, 1, 4'(i));
        end
        write_txn(4096, 1, 0, 0);
        read_txn(4096, 1, 0);
        // Each random write is followed by a read only after B has returned.
        for (i = 0; i < 256; i = i + 1) begin
            choice = 20'(random_word());
            beats = int'(choice[3:0]) + 1;
            address = int'(choice[11:4])*32;
            if ((address % 4096) + beats*32 > 4096)
                address = (address/4096 + 1)*4096 - beats*32;
            write_txn(address, beats, choice[15:12], random_word());
            read_txn(address, beats, choice[19:16]);
        end
        // Sweep both pages to check bytes retained by partial writes.
        for (i = 0; i < 16; i = i + 1)
            read_txn(i*512, 16, 4'(i));
        @(negedge clk);
        if (seen_lengths !== 16'hffff || seen_ids !== 16'hffff ||
            seen_lanes !== 32'hffff_ffff || stalled_w == 0 || b_pending || read_left != 0)
            $fatal(1, "FAIL coverage lengths=%h ids=%h lanes=%h stalls=%0d",
                seen_lengths, seen_ids, seen_lanes, stalled_w);
        if ((WUSER_DELAY > 0 && delayed_b != b_count) ||
            (WUSER_DELAY == 0 && delayed_b != 0))
            $fatal(1, "FAIL WUSER timing B=%0d delayed=%0d", b_count, delayed_b);
        $display("PASS AD-01 delay=%0d B=%0d R=%0d Wbeats=%0d Rbeats=%0d stalls=%0d",
            WUSER_DELAY, b_count, r_count, write_beats, read_beats, stalled_w);
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "FAIL AD-01 timeout t=%0t", $time);
    end
endmodule
