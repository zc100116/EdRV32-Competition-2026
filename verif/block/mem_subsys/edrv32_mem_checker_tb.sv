// File: edrv32_mem_checker_tb.sv
// Spec: SoC 4.2; M-V1 checker self-test acceptance.
// Description: Injects each checker violation and verifies exactly one alarm per scenario.
// Clock domain: clk_mem.
module edrv32_mem_checker_tb;
    timeunit 1ns;
    timeprecision 1ps;
    logic clk = 0;
    logic rst_n = 0;
    always #4ns clk = !clk;
    edrv32_axi256_if #(.ID_WIDTH(4)) bus();
    edrv32_axi256_if #(.ID_WIDTH(4)) raw();
    int raw_errors;
    edrv32_axi256_checker #(
        .FATAL(0),
        .DOWNSTREAM(1)
    ) u_raw_checker (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .bus(raw),
        .errors_o(raw_errors)
    );
    int errors;
    int scenarios;
    edrv32_axi256_checker #(.FATAL(0)) u_checker (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .bus(bus),
        .errors_o(errors)
    );

    task automatic tick();
        @(posedge clk);
        @(negedge clk);
    endtask

    task automatic reset_bus();
        rst_n = 0;
        bus.awid = 0;
        bus.awaddr = 0;
        bus.awlen = 0;
        bus.awvalid = 0;
        bus.awready = 0;
        bus.wdata = 0;
        bus.wstrb = 0;
        bus.wlast = 0;
        bus.wvalid = 0;
        bus.wready = 0;
        bus.bid = 0;
        bus.bresp = 0;
        bus.bvalid = 0;
        bus.bready = 0;
        bus.arid = 0;
        bus.araddr = 0;
        bus.arlen = 0;
        bus.arvalid = 0;
        bus.arready = 0;
        bus.rid = 0;
        bus.rdata = 0;
        bus.rresp = 0;
        bus.rlast = 0;
        bus.rvalid = 0;
        bus.rready = 0;
        raw.awid = 0;
        raw.awaddr = 0;
        raw.awlen = 0;
        raw.awvalid = 0;
        raw.awready = 0;
        raw.wdata = 0;
        raw.wstrb = 0;
        raw.wlast = 0;
        raw.wvalid = 0;
        raw.wready = 0;
        raw.bid = 0;
        raw.bresp = 0;
        raw.bvalid = 0;
        raw.bready = 0;
        raw.arid = 0;
        raw.araddr = 0;
        raw.arlen = 0;
        raw.arvalid = 0;
        raw.arready = 0;
        raw.rid = 0;
        raw.rdata = 0;
        raw.rresp = 0;
        raw.rlast = 0;
        raw.rvalid = 0;
        raw.rready = 0;
        tick();
        rst_n = 1;
    endtask

    task automatic expect_alarms(input string name,
        input int expected);
        if (errors != expected)
            $fatal(1, "FAIL checker %s expected=%0d actual=%0d time=%0t",
                   name, expected, errors, $time);
        scenarios++;
        $display("COVER checker rule=%s alarms=%0d", name, errors);
    endtask

    task automatic aw_w(input int len = 0);
        bus.awvalid = 1;
        bus.awready = 1;
        bus.awlen = 4'(len);
        bus.wvalid = 1;
        bus.wready = 1;
        bus.wlast = 1;
        tick();
        bus.awvalid = 0;
        bus.wvalid = 0;
    endtask

    task automatic ar(input int len = 0);
        bus.arvalid = 1;
        bus.arready = 1;
        bus.arlen = 4'(len);
        tick();
        bus.arvalid = 0;
    endtask

    initial begin
        @(negedge clk);
        reset_bus();
        bus.arvalid = 1;
        bus.arready = 1;
        bus.araddr = 1;
        tick();
        expect_alarms("alignment", 1);
        reset_bus();
        bus.awaddr = 'hfe0;
        bus.awlen = 1;
        bus.awvalid = 1;
        bus.awready = 1;
        tick();
        expect_alarms("4KiB", 1);
        reset_bus();
        bus.awvalid = 1;
        tick();
        bus.awaddr = 32;
        tick();
        expect_alarms("AW stability", 1);
        reset_bus();
        bus.arvalid = 1;
        tick();
        bus.araddr = 32;
        tick();
        expect_alarms("AR stability", 1);
        reset_bus();
        bus.wvalid = 1;
        tick();
        bus.wdata = 1;
        tick();
        expect_alarms("W stability", 1);
        reset_bus();
        aw_w();
        bus.bvalid = 1;
        tick();
        bus.bresp = 2;
        tick();
        expect_alarms("B stability", 1);
        reset_bus();
        ar();
        bus.rvalid = 1;
        bus.rlast = 1;
        tick();
        bus.rdata = 1;
        tick();
        expect_alarms("R stability", 1);
        reset_bus();
        aw_w(1);
        expect_alarms("WLAST length", 1);
        reset_bus();
        bus.bvalid = 1;
        bus.bready = 1;
        tick();
        expect_alarms("B without AW/W", 1);
        reset_bus();
        bus.rvalid = 1;
        bus.rready = 1;
        bus.rlast = 1;
        tick();
        expect_alarms("R without AR", 1);
        reset_bus();
        ar(1);
        bus.rvalid = 1;
        bus.rready = 1;
        bus.rlast = 1;
        tick();
        expect_alarms("RLAST length", 1);
        reset_bus();
        aw_w();
        bus.bid = 1;
        bus.bvalid = 1;
        bus.bready = 1;
        tick();
        expect_alarms("B ID routing", 1);
        reset_bus();
        ar();
        bus.rid = 1;
        bus.rvalid = 1;
        bus.rready = 1;
        bus.rlast = 1;
        tick();
        expect_alarms("R ID routing", 1);
        reset_bus();
        aw_w();
        bus.bvalid = 1;
        bus.bready = 1;
        bus.bresp = 1;
        tick();
        expect_alarms("BRESP EXOKAY forbidden", 1);
        reset_bus();
        ar();
        bus.rvalid = 1;
        bus.rready = 1;
        bus.rlast = 1;
        bus.rresp = 1;
        tick();
        expect_alarms("RRESP EXOKAY forbidden", 1);
        reset_bus();
        // VALID stays high through stalls; arbitrary WSTRB and error responses are legal.
        bus.awvalid = 1;
        repeat (3) tick();
        bus.awready = 1;
        tick();
        bus.awvalid = 0;
        bus.wvalid = 1;
        bus.wstrb = 'ha5a5a5a5;
        bus.wlast = 1;
        repeat (3) tick();
        bus.wready = 1;
        tick();
        bus.wvalid = 0;
        bus.bvalid = 1;
        bus.bresp = 2;
        repeat (3) tick();
        bus.bready = 1;
        tick();
        bus.bvalid = 0;
        ar();
        bus.rvalid = 1;
        bus.rlast = 1;
        bus.rresp = 3;
        repeat (3) tick();
        bus.rready = 1;
        tick();
        bus.rvalid = 0;
        expect_alarms("legal stalls and SLVERR/DECERR", 0);
        reset_bus();
        raw.arvalid = 1;
        raw.arready = 1;
        raw.arid = 2;
        raw.arlen = 1;
        tick();
        raw.arvalid = 0;
        raw.rvalid = 1;
        raw.rid = 2;
        raw.rlast = 0;
        tick();
        raw.rlast = 1;
        tick();
        raw.rvalid = 0;
        if (raw_errors != 0)
            $fatal(1, "FAIL implicit RREADY expected=0 actual=%0d time=%0t", raw_errors, $time);
        scenarios++;
        reset_bus();
        raw.awvalid = 1;
        raw.awready = 1;
        raw.awlen = 1;
        raw.wvalid = 1;
        raw.wready = 1;
        raw.wlast = 0;
        tick();
        raw.awvalid = 0;
        raw.wvalid = 0;
        tick();
        if (raw_errors != 1)
            $fatal(1, "FAIL DDR W gap expected=1 actual=%0d time=%0t", raw_errors, $time);
        scenarios++;
        $display("PASS checker selftest scenarios=%0d time=%0t", scenarios, $time);
        $finish;
    end
    initial begin
        #100us;
        $fatal(1, "FAIL checker selftest expected=completion actual=timeout time=%0t", $time);
    end
endmodule
