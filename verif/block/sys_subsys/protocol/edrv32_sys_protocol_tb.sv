// File: edrv32_sys_protocol_tb.sv
// Spec: sys-subsys-plan S-V1 checker selftest; sys-subsys 2.8.
// Description: Positive protocol examples and deliberate violations selected by plusarg.
// Clock domains: generated PCLK and asynchronous SCCB pins.
module edrv32_sys_protocol_tb;
    logic clk = 0;
    logic rst_n = 0;
    edrv32_axi64_if axi();
    edrv32_apb_if apb();
    edrv32_axi64_if ddr();
    edrv32_axi64_memory u_memory (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .bus(ddr)
    );
    edrv32_axi64_master u_master (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .bus(ddr)
    );
    edrv32_axi64_checker #(.CACHE_CONTRACT(0)) u_ddr_check (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .bus(ddr)
    );
    logic scl = 1;
    logic master_sda_oe = 0;
    wire slave_sda_oe;
    wire sda = !(master_sda_oe || slave_sda_oe);
    edrv32_axi64_checker #(.CACHE_CONTRACT(0)) u_axi_check (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .bus(axi)
    );
    edrv32_apb_checker u_apb_check (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .bus(apb)
    );
    sccb_model u_sccb (
        .scl_i(scl),
        .sda_i(sda),
        .sda_oe_o(slave_sda_oe)
    );
    // A simulation clock toggles immediately at its scheduled edge.
    /* verilator lint_off BLKSEQ */
    always #5 clk = ~clk;
    /* verilator lint_on BLKSEQ */
    initial begin
        bit [63:0] words[256];
        bit [63:0] readback[256];
        bit [7:0] strobes[256];
        bit [1:0] responses[256];
        bit [1:0] response;
        u_master.idle();
        axi.awid = 0;
        axi.awaddr = 0;
        axi.awlen = 0;
        axi.awsize = 2;
        axi.awburst = 1;
        axi.awvalid = 0;
        axi.awready = 0;
        axi.wdata = 0;
        axi.wstrb = 0;
        axi.wlast = 0;
        axi.wvalid = 0;
        axi.wready = 0;
        axi.bid = 0;
        axi.bresp = 0;
        axi.bvalid = 0;
        axi.bready = 1;
        axi.arid = 0;
        axi.araddr = 0;
        axi.arlen = 0;
        axi.arsize = 2;
        axi.arburst = 1;
        axi.arvalid = 0;
        axi.arready = 0;
        axi.rid = 0;
        axi.rdata = 0;
        axi.rresp = 0;
        axi.rlast = 0;
        axi.rvalid = 0;
        axi.rready = 1;
        apb.paddr = 0;
        apb.psel = 0;
        apb.penable = 0;
        apb.pwrite = 0;
        apb.pwdata = 0;
        apb.pstrb = 0;
        apb.prdata = 0;
        apb.pready = 0;
        apb.pslverr = 0;
        repeat (3) @(negedge clk);
        rst_n = 1;
        @(negedge clk);
        if ($test$plusargs("BAD_EARLY_B")) begin
            axi.awvalid = 1;
            axi.awready = 1;
            @(negedge clk);
            axi.awvalid = 0;
            axi.awready = 0;
            axi.bvalid = 1;
        end else if ($test$plusargs("BAD_AXI")) begin
            axi.arvalid = 1;
            repeat (2) @(negedge clk);
            axi.araddr = 4;
        end else if ($test$plusargs("BAD_APB_HOT")) begin
            apb.psel = 3;
        end else if ($test$plusargs("BAD_APB")) begin
            apb.psel = 1;
            @(negedge clk);
            apb.penable = 1;
            @(negedge clk);
            apb.paddr = 4;
        end else if ($test$plusargs("BAD_SCCB")) begin
            u_sccb.quarter_ns = 1000;
            #1000;
            master_sda_oe = 1;
            #100;
            scl = 0;
        end else begin
            // A slave's PSEL can stay low while another slave uses shared PENABLE.
            apb.penable = 1;
            repeat (2) @(negedge clk);
            apb.penable = 0;
            axi.arvalid = 1;
            repeat (2) @(negedge clk);
            axi.arready = 1;
            @(negedge clk);
            axi.arvalid = 0;
            axi.arready = 0;
            axi.rvalid = 1;
            axi.rlast = 1;
            @(negedge clk);
            axi.rvalid = 0;
            apb.psel = 1;
            @(negedge clk);
            apb.penable = 1;
            repeat (2) @(negedge clk);
            apb.pready = 1;
            @(negedge clk);
            apb.psel = 0;
            apb.penable = 0;
            if (apb.prdata != 0 || apb.pslverr != 0)
                $fatal(1, "FAIL protocol fixture APB response");
            for (int n = 0; n < 4; n++) begin
                words[n] = 64'h123456789abcdef0 + 64'(n);
                strobes[n] = '1;
            end
            u_master.write(32'h80000000, 3, 3, words, strobes, response);
            if (response != 0) $fatal(1, "FAIL common memory BRESP");
            u_master.read(32'hc0000000, 3, 3, readback, responses);
            for (int n = 0; n < 4; n++) begin
                if (responses[n] != 0 || readback[n] != words[n])
                    $fatal(1, "FAIL common memory alias beat=%0d expected=%h actual=%h",
                            n, words[n], readback[n]);
            end
            if (u_master.last_read_cancelled || u_master.last_write_cancelled ||
                u_master.first_latency < 1 || u_master.beat_cycle[3] <= u_master.beat_cycle[0])
                $fatal(1, "FAIL common memory transaction completion");
            $display("PASS protocol positive examples and shared memory alias");
            $finish;
        end
        repeat (5) @(negedge clk);
        $fatal(1, "FAIL injected violation was not detected");
    end
endmodule
