// File: component_ddr_connection.svh
// Spec: testplan 2.3; no BREADY or RREADY ports.
// Description: Verification connections and observations.
// Clock domain: clk_mem (gateway parent observations also use clk_sys).
    ddr3_axi256_model u_ddr (
        .clk_i(clk_mem),
        .rst_n_i(rst_mem_n),
        .awid_i(raw.awid),
        .awaddr_i(raw.awaddr),
        .awlen_i(raw.awlen),
        .awvalid_i(raw.awvalid),
        .awready_o(raw.awready),
        .wdata_i(raw.wdata),
        .wstrb_i(raw.wstrb),
        .wlast_i(raw.wlast),
        .wvalid_i(raw.wvalid),
        .wready_o(raw.wready),
        .bid_o(raw.bid),
        .bresp_o(raw.bresp),
        .bvalid_o(raw.bvalid),
        .arid_i(raw.arid),
        .araddr_i(raw.araddr),
        .arlen_i(raw.arlen),
        .arvalid_i(raw.arvalid),
        .arready_o(raw.arready),
        .rid_o(raw.rid),
        .rdata_o(raw.rdata),
        .rresp_o(raw.rresp),
        .rlast_o(raw.rlast),
        .rvalid_o(raw.rvalid)
    );
