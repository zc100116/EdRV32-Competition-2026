// edrv32_axi64_checker.sv
// SoC 4.1 and cache-testplan 2.1: channel stability and transaction contracts.
// Clock domain: clk_sys.
module edrv32_axi64_checker #(parameter bit INSTRUCTION = 0) (
    // Clock and reset
    input logic clk_i,
    input logic rst_n_i,

    // AXI memory interface
    edrv32_axi64_if bus
);
    bit read_active;
    bit write_active;
    int read_left;
    int write_left;
    bit [7:0] expected_strobe;
    task automatic check(input bit ok, input string what,
                         input logic [127:0] expected, input logic [127:0] actual);
        if (!ok) $fatal(1, "FAIL AXI %s expected=%h actual=%h time=%0t",
                        what, expected, actual, $time);
    endtask
    bit ar_stalled;
    logic [48:0] ar_saved;
    bit aw_stalled;
    logic [48:0] aw_saved;
    bit w_stalled;
    logic [72:0] w_saved;
    bit r_stalled;
    logic [70:0] r_saved;
    bit b_stalled;
    logic [5:0] b_saved;
    always @(posedge clk_i) begin
        if (!rst_n_i) begin
            read_active <= 0;
            write_active <= 0;
            ar_stalled <= 0;
            aw_stalled <= 0;
            w_stalled <= 0;
            r_stalled <= 0;
            b_stalled <= 0;
        end else begin
            if (ar_stalled) begin
                check(bus.arvalid, "AR VALID hold", 1, 128'(bus.arvalid));
                check(ar_saved == {bus.arid, bus.araddr, bus.arlen, bus.arsize, bus.arburst},
                      "AR payload hold",
                      128'(ar_saved),
                      128'({bus.arid, bus.araddr, bus.arlen, bus.arsize, bus.arburst}));
            end
            ar_stalled <= bus.arvalid && !bus.arready;
            ar_saved <= {bus.arid, bus.araddr, bus.arlen, bus.arsize, bus.arburst};
            if (aw_stalled) begin
                check(bus.awvalid, "AW VALID hold", 1, 128'(bus.awvalid));
                check(aw_saved == {bus.awid, bus.awaddr, bus.awlen, bus.awsize, bus.awburst},
                      "AW payload hold",
                      128'(aw_saved),
                      128'({bus.awid, bus.awaddr, bus.awlen, bus.awsize, bus.awburst}));
            end
            aw_stalled <= bus.awvalid && !bus.awready;
            aw_saved <= {bus.awid, bus.awaddr, bus.awlen, bus.awsize, bus.awburst};
            if (w_stalled) begin
                check(bus.wvalid, "W VALID hold", 1, 128'(bus.wvalid));
                check(w_saved == {bus.wdata, bus.wstrb, bus.wlast}, "W payload hold",
                      128'(w_saved), 128'({bus.wdata, bus.wstrb, bus.wlast}));
            end
            w_stalled <= bus.wvalid && !bus.wready;
            w_saved <= {bus.wdata, bus.wstrb, bus.wlast};
            if (r_stalled) begin
                check(bus.rvalid, "R VALID hold", 1, 128'(bus.rvalid));
                check(r_saved == {bus.rid, bus.rdata, bus.rresp, bus.rlast}, "R payload hold",
                      128'(r_saved), 128'({bus.rid, bus.rdata, bus.rresp, bus.rlast}));
            end
            r_stalled <= bus.rvalid && !bus.rready;
            r_saved <= {bus.rid, bus.rdata, bus.rresp, bus.rlast};
            if (b_stalled) begin
                check(bus.bvalid, "B VALID hold", 1, 128'(bus.bvalid));
                check(b_saved == {bus.bid, bus.bresp}, "B payload hold",
                      128'(b_saved), 128'({bus.bid, bus.bresp}));
            end
            b_stalled <= bus.bvalid && !bus.bready;
            b_saved <= {bus.bid, bus.bresp};
            if (bus.arvalid && bus.arready) begin
                check(!read_active, "read outstanding", 0, 128'(read_active));
                check(bus.arid == 0, "ARID", 0, 128'(bus.arid));
                check(bus.arburst == 1, "ARBURST", 1, 128'(bus.arburst));
                check(bus.arsize <= 3, "ARSIZE maximum", 3, 128'(bus.arsize));
                if (bus.arsize == 3 && !(INSTRUCTION && bus.araddr < 32'h4000)) begin
                    check(bus.arlen == 3, "line ARLEN", 3, 128'(bus.arlen));
                    check(bus.araddr[4:0] == 0, "line AR alignment", 0,
                          128'(bus.araddr[4:0]));
                end else begin
                    check(bus.arlen == 0, "single ARLEN", 0, 128'(bus.arlen));
                    check(bus.arsize <= 2 ||
                          (INSTRUCTION && bus.araddr < 32'h4000 && bus.arsize == 3),
                          "single ARSIZE", 2, 128'(bus.arsize));
                end
                read_active <= 1;
                read_left <= int'(bus.arlen) + 1;
            end
            if (bus.rvalid && bus.rready) begin
                check(read_active, "R has request", 1, 128'(read_active));
                check(bus.rid == 0, "RID", 0, 128'(bus.rid));
                check(bus.rlast == (read_left == 1), "RLAST", 128'(read_left == 1),
                      128'(bus.rlast));
                read_left <= read_left - 1;
                if (bus.rlast) read_active <= 0;
            end
            if (bus.awvalid && bus.awready) begin
                check(!write_active, "write outstanding", 0, 128'(write_active));
                check(bus.awid == 0, "AWID", 0, 128'(bus.awid));
                check(bus.awburst == 1, "AWBURST", 1, 128'(bus.awburst));
                check(bus.awsize <= 3, "AWSIZE maximum", 3, 128'(bus.awsize));
                if (bus.awsize == 3) begin
                    check(bus.awlen == 3, "line AWLEN", 3, 128'(bus.awlen));
                    check(bus.awaddr[4:0] == 0, "line AW alignment", 0,
                          128'(bus.awaddr[4:0]));
                    expected_strobe <= 8'hff;
                end else begin
                    check(bus.awlen == 0, "single AWLEN", 0, 128'(bus.awlen));
                    expected_strobe <= 8'(((1 << (1 << bus.awsize)) - 1) <<
                                         bus.awaddr[2:0]);
                end
                write_active <= 1;
                write_left <= int'(bus.awlen) + 1;
            end
            if (bus.wvalid && bus.wready) begin
                check(write_active, "W has AW", 1, 128'(write_active));
                check(bus.wstrb == expected_strobe, "WSTRB", 128'(expected_strobe),
                      128'(bus.wstrb));
                check(bus.wlast == (write_left == 1), "WLAST", 128'(write_left == 1),
                      128'(bus.wlast));
                write_left <= write_left - 1;
            end
            if (bus.bvalid && bus.bready) begin
                check(write_active && write_left == 0, "B after W", 0, 128'(write_left));
                check(bus.bid == 0, "BID", 0, 128'(bus.bid));
                write_active <= 0;
            end
        end
    end
endmodule
