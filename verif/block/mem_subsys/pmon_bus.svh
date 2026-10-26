// File: pmon_bus.svh
// Spec: SoC 4.2; coordinator-approved PERF_MON module port observations.
// Description: Verification connections and observations.
// Clock domain: clk_mem (gateway parent observations also use clk_sys).
    edrv32_axi256_if pmon_bus();
    assign pmon_bus.awid = u_dut.u_perf_mon.axi_awid_o;
    assign pmon_bus.awaddr = u_dut.u_perf_mon.axi_awaddr_o;
    assign pmon_bus.awlen = u_dut.u_perf_mon.axi_awlen_o;
    assign pmon_bus.awvalid = u_dut.u_perf_mon.axi_awvalid_o;
    assign pmon_bus.awready = u_dut.u_perf_mon.axi_awready_i;
    assign pmon_bus.wdata = u_dut.u_perf_mon.axi_wdata_o;
    assign pmon_bus.wstrb = u_dut.u_perf_mon.axi_wstrb_o;
    assign pmon_bus.wlast = u_dut.u_perf_mon.axi_wlast_o;
    assign pmon_bus.wvalid = u_dut.u_perf_mon.axi_wvalid_o;
    assign pmon_bus.wready = u_dut.u_perf_mon.axi_wready_i;
    assign pmon_bus.bid = u_dut.u_perf_mon.axi_bid_i;
    assign pmon_bus.bresp = u_dut.u_perf_mon.axi_bresp_i;
    assign pmon_bus.bvalid = u_dut.u_perf_mon.axi_bvalid_i;
    assign pmon_bus.bready = u_dut.u_perf_mon.axi_bready_o;
    assign pmon_bus.arid = u_dut.u_perf_mon.axi_arid_o;
    assign pmon_bus.araddr = u_dut.u_perf_mon.axi_araddr_o;
    assign pmon_bus.arlen = u_dut.u_perf_mon.axi_arlen_o;
    assign pmon_bus.arvalid = u_dut.u_perf_mon.axi_arvalid_o;
    assign pmon_bus.arready = u_dut.u_perf_mon.axi_arready_i;
    assign pmon_bus.rid = u_dut.u_perf_mon.axi_rid_i;
    assign pmon_bus.rdata = u_dut.u_perf_mon.axi_rdata_i;
    assign pmon_bus.rresp = u_dut.u_perf_mon.axi_rresp_i;
    assign pmon_bus.rlast = u_dut.u_perf_mon.axi_rlast_i;
    assign pmon_bus.rvalid = u_dut.u_perf_mon.axi_rvalid_i;
    assign pmon_bus.rready = u_dut.u_perf_mon.axi_rready_o;
