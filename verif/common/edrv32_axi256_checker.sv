// File: edrv32_axi256_checker.sv
// Spec: SoC 4.2; mem-subsys 2.2, 5.2; testplan 2.2.
// Description: Checks stability, alignment, burst boundaries, IDs and AW/W/B and AR/R ordering.
// Clock domain: clk_mem. DDR has implicit always-ready response channels.
`timescale 1ns/1ps
module edrv32_axi256_checker #(
    parameter bit DOWNSTREAM = 0,
    parameter bit FATAL = 1,
    parameter bit CHECK_ADDRESS = 1
) (
    input logic clk_i,
    input logic rst_n_i,
    edrv32_axi256_if bus,
    output int errors_o
);
    typedef struct packed {
        bit [3:0] id;
        int beats;
    } command_t;
    command_t aw_queue[$];
    int w_queue[$];
    int r_queue[16][$];
    int b_pending[16];
    int w_count;
    bit aw_stall;
    bit ar_stall;
    bit w_stall;
    bit b_stall;
    bit r_stall;
    bit [39:0] aw_saved;
    bit [39:0] ar_saved;
    bit [288:0] w_saved;
    bit [5:0] b_saved;
    bit [262:0] r_saved;

    task automatic violation(input string rule,
        input string expected,
                              input string actual);
        errors_o++;
        if (FATAL) $fatal(1, "FAIL AXI256 %s expected=%s actual=%s time=%0t",
                          rule, expected, actual, $time);
        else $display("CHECKER_ALARM %s expected=%s actual=%s time=%0t",
                      rule, expected, actual, $time);
    endtask

    task automatic address_check(input bit [31:0] addr,
        input int len);
        if (CHECK_ADDRESS) begin
            if (addr[4:0] != 0)
                violation("alignment", "addr[4:0]=0", $sformatf("%h", addr));
            if (int'(addr[11:0]) + (len+1)*32 > 4096)
                violation("4KiB", "last byte <= page end", $sformatf("%h/%0d", addr, len));
        end
    endtask

    always @(posedge clk_i) begin : monitor
        command_t cmd;
        int beats;
        int id;
        if (!rst_n_i) begin
            errors_o = 0;
            aw_queue.delete();
            w_queue.delete();
            for (int p = 0; p < 16; p++) begin
                r_queue[p].delete();
                b_pending[p] = 0;
            end
            w_count = 0;
            aw_stall = 0;
            ar_stall = 0;
            w_stall = 0;
            b_stall = 0;
            r_stall = 0;
        end else begin
            if (aw_stall && (!bus.awvalid ||
                {4'(bus.awid), bus.awaddr, bus.awlen} != aw_saved))
                violation("AW stability", $sformatf("%h", aw_saved),
                          $sformatf("%h", {4'(bus.awid), bus.awaddr, bus.awlen}));
            if (ar_stall && (!bus.arvalid ||
                {4'(bus.arid), bus.araddr, bus.arlen} != ar_saved))
                violation("AR stability", $sformatf("%h", ar_saved),
                          $sformatf("%h", {4'(bus.arid), bus.araddr, bus.arlen}));
            if (w_stall && (!bus.wvalid ||
                {bus.wdata, bus.wstrb, bus.wlast} != w_saved))
                violation("W stability", $sformatf("%h", w_saved),
                          $sformatf("%h", {bus.wdata, bus.wstrb, bus.wlast}));
            if (b_stall && (!bus.bvalid || {4'(bus.bid), bus.bresp} != b_saved))
                violation("B stability", $sformatf("%h", b_saved),
                          $sformatf("%h", {4'(bus.bid), bus.bresp}));
            if (r_stall && (!bus.rvalid ||
                {4'(bus.rid), bus.rdata, bus.rresp, bus.rlast} != r_saved))
                violation("R stability", $sformatf("%h", r_saved),
                          $sformatf("%h", {4'(bus.rid), bus.rdata, bus.rresp, bus.rlast}));
            aw_stall = bus.awvalid && !bus.awready;
            ar_stall = bus.arvalid && !bus.arready;
            w_stall = bus.wvalid && !bus.wready;
            b_stall = !DOWNSTREAM && bus.bvalid && !bus.bready;
            r_stall = !DOWNSTREAM && bus.rvalid && !bus.rready;
            aw_saved = {4'(bus.awid), bus.awaddr, bus.awlen};
            ar_saved = {4'(bus.arid), bus.araddr, bus.arlen};
            w_saved = {bus.wdata, bus.wstrb, bus.wlast};
            b_saved = {4'(bus.bid), bus.bresp};
            r_saved = {4'(bus.rid), bus.rdata, bus.rresp, bus.rlast};
            if (DOWNSTREAM && w_count != 0 && !bus.wvalid)
                violation("continuous W", "WVALID until WLAST", "gap");
            if (bus.awvalid && bus.awready) begin
                address_check(bus.awaddr, int'(bus.awlen));
                cmd.id = 4'(bus.awid);
                cmd.beats = int'(bus.awlen)+1;
                aw_queue.push_back(cmd);
            end
            if (bus.wvalid && bus.wready) begin
                w_count++;
                if (bus.wlast) begin
                    w_queue.push_back(w_count);
                    w_count = 0;
                end
            end
            while (aw_queue.size() != 0 && w_queue.size() != 0) begin
                cmd = aw_queue.pop_front();
                beats = w_queue.pop_front();
                if (beats != cmd.beats)
                    violation("WLAST/AW order", $sformatf("%0d", cmd.beats),
                              $sformatf("%0d", beats));
                b_pending[cmd.id]++;
            end
            if (bus.arvalid && bus.arready) begin
                address_check(bus.araddr, int'(bus.arlen));
                r_queue[int'(bus.arid)].push_back(int'(bus.arlen)+1);
            end
            if (bus.bvalid && (DOWNSTREAM || bus.bready)) begin
                id = int'(bus.bid);
                if (b_pending[id] == 0) violation("B ID/order", "completed W", "none");
                else b_pending[id]--;
                if (bus.bresp == 1) violation("BRESP", "OKAY/SLVERR/DECERR", "EXOKAY");
            end
            if (bus.rvalid && (DOWNSTREAM || bus.rready)) begin
                id = int'(bus.rid);
                if (r_queue[id].size() == 0) violation("R ID/order", "pending AR", "none");
                else begin
                    beats = r_queue[id][0];
                    if (bus.rlast != (beats == 1))
                        violation("RLAST", $sformatf("%0b", beats == 1),
                                  $sformatf("%0b", bus.rlast));
                    if (beats == 1) beats = r_queue[id].pop_front();
                    else r_queue[id][0] = beats-1;
                end
                if (bus.rresp == 1) violation("RRESP", "OKAY/SLVERR/DECERR", "EXOKAY");
            end
        end
    end
endmodule
