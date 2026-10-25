// File: edrv32_cpu_b2_memory.sv
// Spec: cpu-testplan 2.2, 3.8; SoC spec 4.1.
// Description: Reuse the shared AXI memory with deterministic first-beat latency.
//              Subsequent read beats retain the memory model's SRAM throughput.
// Clock domain: clk_sys.
module edrv32_cpu_b2_memory (
    input logic clk_i,
    input logic rst_n_i,
    input int unsigned read_latency_i,
    edrv32_axi64_if bus
);
    edrv32_axi64_if model_bus();
    int unsigned wait_r;
    edrv32_axi64_memory u_memory (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .bus(model_bus)
    );
    always @(posedge clk_i) begin
        if (!rst_n_i) wait_r <= 0;
        else if (bus.arvalid && bus.arready) wait_r <= read_latency_i - 1;
        else if (wait_r != 0) wait_r <= wait_r - 1;
    end
    assign model_bus.awid = bus.awid;
    assign model_bus.awaddr = bus.awaddr;
    assign model_bus.awlen = bus.awlen;
    assign model_bus.awsize = bus.awsize;
    assign model_bus.awburst = bus.awburst;
    assign model_bus.awvalid = bus.awvalid;
    assign model_bus.wdata = bus.wdata;
    assign model_bus.wstrb = bus.wstrb;
    assign model_bus.wlast = bus.wlast;
    assign model_bus.wvalid = bus.wvalid;
    assign model_bus.bready = bus.bready;
    assign model_bus.arid = bus.arid;
    assign model_bus.araddr = bus.araddr;
    assign model_bus.arlen = bus.arlen;
    assign model_bus.arsize = bus.arsize;
    assign model_bus.arburst = bus.arburst;
    assign model_bus.arvalid = bus.arvalid;
    assign bus.awready = model_bus.awready;
    assign bus.wready = model_bus.wready;
    assign bus.bid = model_bus.bid;
    assign bus.bresp = model_bus.bresp;
    assign bus.bvalid = model_bus.bvalid;
    assign bus.arready = model_bus.arready;
    assign bus.rid = model_bus.rid;
    assign bus.rdata = model_bus.rdata;
    assign bus.rresp = model_bus.rresp;
    assign bus.rlast = model_bus.rlast;
    assign bus.rvalid = model_bus.rvalid && wait_r == 0;
    assign model_bus.rready = bus.rready && wait_r == 0;
endmodule
