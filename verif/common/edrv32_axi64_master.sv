// File: edrv32_axi64_master.sv
// Spec: sys-subsys-testplan 2.1; SoC 4.1.
// Description: Blocking AXI64 transactions, one outstanding per direction.
// Clock domain: clk_sys.
module edrv32_axi64_master (
    input logic clk_i,
    input logic rst_n_i,
    edrv32_axi64_if bus
);
    bit last_read_cancelled;
    bit last_write_cancelled;
    always @(negedge rst_n_i) idle();
    int gap = 0;
    int response_stall = 0;
    int first_latency;
    int beat_cycle[256];
    int cycle = 0;
    always @(posedge clk_i) cycle <= cycle + 1;

    // The peer driver resets its pins atomically when the emulated CPU resets.
    /* verilator lint_off BLKSEQ */
    task automatic idle(

    );
        bus.awid = 0;
        bus.awaddr = 0;
        bus.awlen = 0;
        bus.awsize = 2;
        bus.awburst = 1;
        bus.awvalid = 0;
        bus.wdata = 0;
        bus.wstrb = 0;
        bus.wlast = 0;
        bus.wvalid = 0;
        bus.bready = 0;
        bus.arid = 0;
        bus.araddr = 0;
        bus.arlen = 0;
        bus.arsize = 2;
        bus.arburst = 1;
        bus.arvalid = 0;
        bus.rready = 0;
    endtask
    /* verilator lint_on BLKSEQ */

    task automatic read(
        input bit [31:0] addr,
        input bit [2:0] size,
        input int len,
        output bit [63:0] data[256],
        output bit [1:0] resp[256]
    );
        int accepted;
        last_read_cancelled = 0;
        repeat (gap) @(negedge clk_i);
        @(negedge clk_i);
        bus.araddr = addr;
        bus.arsize = 3'(size);
        bus.arlen = 8'(len);
        bus.arvalid = 1;
        do @(posedge clk_i); while (!bus.arready && rst_n_i);
            if (!rst_n_i) begin
                last_read_cancelled = 1;
                idle();
                return;
            end
        accepted = cycle;
        @(negedge clk_i);
        bus.arvalid = 0;
        repeat (response_stall) @(negedge clk_i);
        bus.rready = 1;
        for (int n = 0; n <= len; n++) begin
            do @(posedge clk_i); while (!bus.rvalid && rst_n_i);
            if (!rst_n_i) begin
                last_read_cancelled = 1;
                idle();
                return;
            end
            data[n] = bus.rdata;
            resp[n] = bus.rresp;
            beat_cycle[n] = cycle;
            if (n == 0) first_latency = cycle - accepted;
            if (bus.rlast != (n == len))
                $fatal(1, "FAIL RLAST beat=%0d len=%0d time=%0t", n, len, $time);
            @(negedge clk_i);
        end
        bus.rready = 0;
    endtask

    task automatic write(
        input bit [31:0] addr,
        input bit [2:0] size,
        input int len,
        input bit [63:0] data[256],
        input bit [7:0] strb[256],
        output bit [1:0] resp
    );
        last_write_cancelled = 0;
        repeat (gap) @(negedge clk_i);
        @(negedge clk_i);
        bus.awaddr = addr;
        bus.awsize = 3'(size);
        bus.awlen = 8'(len);
        bus.awvalid = 1;
        do @(posedge clk_i); while (!bus.awready && rst_n_i);
            if (!rst_n_i) begin
                last_write_cancelled = 1;
                idle();
                return;
            end
        @(negedge clk_i);
        bus.awvalid = 0;
        for (int n = 0; n <= len; n++) begin
            bus.wdata = data[n];
            bus.wstrb = strb[n];
            bus.wlast = n == len;
            bus.wvalid = 1;
            do @(posedge clk_i); while (!bus.wready && rst_n_i);
            if (!rst_n_i) begin
                last_write_cancelled = 1;
                idle();
                return;
            end
            @(negedge clk_i);
        end
        bus.wvalid = 0;
        bus.wlast = 0;
        repeat (response_stall) @(negedge clk_i);
        bus.bready = 1;
        do @(posedge clk_i); while (!bus.bvalid && rst_n_i);
            if (!rst_n_i) begin
                last_write_cancelled = 1;
                idle();
                return;
            end
        resp = bus.bresp;
        @(negedge clk_i);
        bus.bready = 0;
    endtask
endmodule
