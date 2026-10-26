// File: ddr_connection.svh
// Spec: testplan 2.3; no BREADY or RREADY ports.
// Description: Verification connections and observations.
// Clock domain: clk_mem (gateway parent observations also use clk_sys).
    ddr3_axi256_model u_ddr (
        .clk_i(clk_mem),
        .rst_n_i(rst_mem_n),
        .awid_i(ddr.awid),
        .awaddr_i(ddr.awaddr),
        .awlen_i(ddr.awlen),
        .awvalid_i(ddr.awvalid),
        .awready_o(ddr.awready),
        .wdata_i(ddr.wdata),
        .wstrb_i(ddr.wstrb),
        .wlast_i(ddr.wlast),
        .wvalid_i(ddr.wvalid),
        .wready_o(ddr.wready),
        .bid_o(ddr.bid),
        .bresp_o(ddr.bresp),
        .bvalid_o(ddr.bvalid),
        .arid_i(ddr.arid),
        .araddr_i(ddr.araddr),
        .arlen_i(ddr.arlen),
        .arvalid_i(ddr.arvalid),
        .arready_o(ddr.arready),
        .rid_o(ddr.rid),
        .rdata_o(ddr.rdata),
        .rresp_o(ddr.rresp),
        .rlast_o(ddr.rlast),
        .rvalid_o(ddr.rvalid)
    );
