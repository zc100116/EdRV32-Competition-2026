// File: edrv32_axi64_observer.sv
// Spec: sys-subsys-testplan 2.1.
// Description: Passive flattened-port adapter for the reusable AXI protocol checker.
// Clock domain: clk_sys.
module edrv32_axi64_observer (
    input logic clk_i,
    input logic rst_n_i,
    input logic [3:0] awid_i,
    input logic [31:0] awaddr_i,
    input logic [7:0] awlen_i,
    input logic [2:0] awsize_i,
    input logic [1:0] awburst_i,
    input logic awvalid_i,
    input logic awready_i,
    input logic [63:0] wdata_i,
    input logic [7:0] wstrb_i,
    input logic wlast_i,
    input logic wvalid_i,
    input logic wready_i,
    input logic [3:0] bid_i,
    input logic [1:0] bresp_i,
    input logic bvalid_i,
    input logic bready_i,
    input logic [3:0] arid_i,
    input logic [31:0] araddr_i,
    input logic [7:0] arlen_i,
    input logic [2:0] arsize_i,
    input logic [1:0] arburst_i,
    input logic arvalid_i,
    input logic arready_i,
    input logic [3:0] rid_i,
    input logic [63:0] rdata_i,
    input logic [1:0] rresp_i,
    input logic rlast_i,
    input logic rvalid_i,
    input logic rready_i
);
    edrv32_axi64_if bus();
    assign bus.awid = awid_i;
    assign bus.awaddr = awaddr_i;
    assign bus.awlen = awlen_i;
    assign bus.awsize = awsize_i;
    assign bus.awburst = awburst_i;
    assign bus.awvalid = awvalid_i;
    assign bus.awready = awready_i;
    assign bus.wdata = wdata_i;
    assign bus.wstrb = wstrb_i;
    assign bus.wlast = wlast_i;
    assign bus.wvalid = wvalid_i;
    assign bus.wready = wready_i;
    assign bus.bid = bid_i;
    assign bus.bresp = bresp_i;
    assign bus.bvalid = bvalid_i;
    assign bus.bready = bready_i;
    assign bus.arid = arid_i;
    assign bus.araddr = araddr_i;
    assign bus.arlen = arlen_i;
    assign bus.arsize = arsize_i;
    assign bus.arburst = arburst_i;
    assign bus.arvalid = arvalid_i;
    assign bus.arready = arready_i;
    assign bus.rid = rid_i;
    assign bus.rdata = rdata_i;
    assign bus.rresp = rresp_i;
    assign bus.rlast = rlast_i;
    assign bus.rvalid = rvalid_i;
    assign bus.rready = rready_i;
    edrv32_axi64_checker #(.CACHE_CONTRACT(0)) u_check (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .bus(bus)
    );
endmodule
