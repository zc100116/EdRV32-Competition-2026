// File: edrv32_mem_subsys.sv
// Spec: mem-subsys 3.1.
// Description: Empty-response compilation stub; deliberately does not implement the DUT.
// Clock domains: clk_sys and clk_mem.
`timescale 1ns/1ps
module edrv32_mem_subsys (
    input logic clk_sys_i,
    input logic clk_mem_i,
    input logic rst_sys_n_i,
    input logic rst_mem_core_n_i,
    input logic [3:0] gw_awid_i,
    input logic [31:0] gw_awaddr_i,
    input logic [7:0] gw_awlen_i,
    input logic gw_awvalid_i,
    output logic gw_awready_o,
    input logic [63:0] gw_wdata_i,
    input logic [7:0] gw_wstrb_i,
    input logic gw_wlast_i,
    input logic gw_wvalid_i,
    output logic gw_wready_o,
    output logic [3:0] gw_bid_o,
    output logic [1:0] gw_bresp_o,
    output logic gw_bvalid_o,
    input logic gw_bready_i,
    input logic [3:0] gw_arid_i,
    input logic [31:0] gw_araddr_i,
    input logic [7:0] gw_arlen_i,
    input logic gw_arvalid_i,
    output logic gw_arready_o,
    output logic [3:0] gw_rid_o,
    output logic [63:0] gw_rdata_o,
    output logic [1:0] gw_rresp_o,
    output logic gw_rlast_o,
    output logic gw_rvalid_o,
    input logic gw_rready_i,
    input logic [2:0] gw_awsize_i,
    input logic [1:0] gw_awburst_i,
    input logic [2:0] gw_arsize_i,
    input logic [1:0] gw_arburst_i,
    input logic p0_arid_i,
    input logic [31:0] p0_araddr_i,
    input logic [3:0] p0_arlen_i,
    input logic p0_arvalid_i,
    output logic p0_arready_o,
    output logic p0_rid_o,
    output logic [255:0] p0_rdata_o,
    output logic [1:0] p0_rresp_o,
    output logic p0_rlast_o,
    output logic p0_rvalid_o,
    input logic p0_rready_i,
    input logic p0_urgent_i,
    input logic p1_awid_i,
    input logic [31:0] p1_awaddr_i,
    input logic [3:0] p1_awlen_i,
    input logic p1_awvalid_i,
    output logic p1_awready_o,
    input logic [255:0] p1_wdata_i,
    input logic [31:0] p1_wstrb_i,
    input logic p1_wlast_i,
    input logic p1_wvalid_i,
    output logic p1_wready_o,
    output logic p1_bid_o,
    output logic [1:0] p1_bresp_o,
    output logic p1_bvalid_o,
    input logic p1_bready_i,
    input logic p1_urgent_i,
    input logic p3_awid_i,
    input logic [31:0] p3_awaddr_i,
    input logic [3:0] p3_awlen_i,
    input logic p3_awvalid_i,
    output logic p3_awready_o,
    input logic [255:0] p3_wdata_i,
    input logic [31:0] p3_wstrb_i,
    input logic p3_wlast_i,
    input logic p3_wvalid_i,
    output logic p3_wready_o,
    output logic p3_bid_o,
    output logic [1:0] p3_bresp_o,
    output logic p3_bvalid_o,
    input logic p3_bready_i,
    input logic p3_arid_i,
    input logic [31:0] p3_araddr_i,
    input logic [3:0] p3_arlen_i,
    input logic p3_arvalid_i,
    output logic p3_arready_o,
    output logic p3_rid_o,
    output logic [255:0] p3_rdata_o,
    output logic [1:0] p3_rresp_o,
    output logic p3_rlast_o,
    output logic p3_rvalid_o,
    input logic p3_rready_i,
    input logic p4_awid_i,
    input logic [31:0] p4_awaddr_i,
    input logic [3:0] p4_awlen_i,
    input logic p4_awvalid_i,
    output logic p4_awready_o,
    input logic [255:0] p4_wdata_i,
    input logic [31:0] p4_wstrb_i,
    input logic p4_wlast_i,
    input logic p4_wvalid_i,
    output logic p4_wready_o,
    output logic p4_bid_o,
    output logic [1:0] p4_bresp_o,
    output logic p4_bvalid_o,
    input logic p4_bready_i,
    input logic p4_arid_i,
    input logic [31:0] p4_araddr_i,
    input logic [3:0] p4_arlen_i,
    input logic p4_arvalid_i,
    output logic p4_arready_o,
    output logic p4_rid_o,
    output logic [255:0] p4_rdata_o,
    output logic [1:0] p4_rresp_o,
    output logic p4_rlast_o,
    output logic p4_rvalid_o,
    input logic p4_rready_i,
    input logic p5_awid_i,
    input logic [31:0] p5_awaddr_i,
    input logic [3:0] p5_awlen_i,
    input logic p5_awvalid_i,
    output logic p5_awready_o,
    input logic [255:0] p5_wdata_i,
    input logic [31:0] p5_wstrb_i,
    input logic p5_wlast_i,
    input logic p5_wvalid_i,
    output logic p5_wready_o,
    output logic p5_bid_o,
    output logic [1:0] p5_bresp_o,
    output logic p5_bvalid_o,
    input logic p5_bready_i,
    input logic p5_arid_i,
    input logic [31:0] p5_araddr_i,
    input logic [3:0] p5_arlen_i,
    input logic p5_arvalid_i,
    output logic p5_arready_o,
    output logic p5_rid_o,
    output logic [255:0] p5_rdata_o,
    output logic [1:0] p5_rresp_o,
    output logic p5_rlast_o,
    output logic p5_rvalid_o,
    input logic p5_rready_i,
    input logic eth_awid_i,
    input logic [31:0] eth_awaddr_i,
    input logic [3:0] eth_awlen_i,
    input logic eth_awvalid_i,
    output logic eth_awready_o,
    input logic [255:0] eth_wdata_i,
    input logic [31:0] eth_wstrb_i,
    input logic eth_wlast_i,
    input logic eth_wvalid_i,
    output logic eth_wready_o,
    output logic eth_bid_o,
    output logic [1:0] eth_bresp_o,
    output logic eth_bvalid_o,
    input logic eth_bready_i,
    input logic eth_arid_i,
    input logic [31:0] eth_araddr_i,
    input logic [3:0] eth_arlen_i,
    input logic eth_arvalid_i,
    output logic eth_arready_o,
    output logic eth_rid_o,
    output logic [255:0] eth_rdata_o,
    output logic [1:0] eth_rresp_o,
    output logic eth_rlast_o,
    output logic eth_rvalid_o,
    input logic eth_rready_i,
    output logic [3:0] ddr_awid_o,
    output logic [31:0] ddr_awaddr_o,
    output logic [3:0] ddr_awlen_o,
    output logic ddr_awvalid_o,
    input logic ddr_awready_i,
    output logic [255:0] ddr_wdata_o,
    output logic [31:0] ddr_wstrb_o,
    output logic ddr_wlast_o,
    output logic ddr_wvalid_o,
    input logic ddr_wready_i,
    input logic [3:0] ddr_bid_i,
    input logic [1:0] ddr_bresp_i,
    input logic ddr_bvalid_i,
    output logic [3:0] ddr_arid_o,
    output logic [31:0] ddr_araddr_o,
    output logic [3:0] ddr_arlen_o,
    output logic ddr_arvalid_o,
    input logic ddr_arready_i,
    input logic [3:0] ddr_rid_i,
    input logic [255:0] ddr_rdata_i,
    input logic [1:0] ddr_rresp_i,
    input logic ddr_rlast_i,
    input logic ddr_rvalid_i,
    input logic [11:0] xbar_apb_paddr_i,
    input logic xbar_apb_psel_i,
    input logic xbar_apb_penable_i,
    input logic xbar_apb_pwrite_i,
    input logic [31:0] xbar_apb_pwdata_i,
    input logic [3:0] xbar_apb_pstrb_i,
    output logic xbar_apb_pready_o,
    output logic [31:0] xbar_apb_prdata_o,
    output logic xbar_apb_pslverr_o,
    input logic [11:0] pmon_apb_paddr_i,
    input logic pmon_apb_psel_i,
    input logic pmon_apb_penable_i,
    input logic pmon_apb_pwrite_i,
    input logic [31:0] pmon_apb_pwdata_i,
    input logic [3:0] pmon_apb_pstrb_i,
    output logic pmon_apb_pready_o,
    output logic [31:0] pmon_apb_prdata_o,
    output logic pmon_apb_pslverr_o,
    output logic irq_mem_xbar_o
);
    int gw_remaining;
    assign gw_arready_o = rst_sys_n_i && !gw_rvalid_o;
    always @(posedge clk_sys_i) begin
        if (!rst_sys_n_i) begin
            gw_rvalid_o <= 0;
            gw_remaining <= 0;
            gw_rid_o <= 0;
            gw_rdata_o <= 0;
            gw_rresp_o <= 0;
            gw_rlast_o <= 0;
        end else begin
            if (gw_arvalid_i && gw_arready_o) begin
                gw_rvalid_o <= 1;
                gw_remaining <= int'(gw_arlen_i);
                gw_rid_o <= gw_arid_i;
                gw_rlast_o <= gw_arlen_i == 0;
            end else if (gw_rvalid_o && gw_rready_i) begin
                gw_remaining <= gw_remaining - 1;
                gw_rlast_o <= gw_remaining == 1;
                if (gw_remaining == 0) gw_rvalid_o <= 0;
            end
        end
    end
    logic gw_write_pending;
    assign gw_awready_o = rst_sys_n_i && !gw_write_pending && !gw_bvalid_o;
    assign gw_wready_o = rst_sys_n_i && gw_write_pending && !gw_bvalid_o;
    always @(posedge clk_sys_i) begin
        if (!rst_sys_n_i) begin
            gw_bvalid_o <= 0;
            gw_write_pending <= 0;
            gw_bid_o <= 0;
            gw_bresp_o <= 0;
        end else begin
            if (gw_awvalid_i && gw_awready_o) begin
                gw_bid_o <= gw_awid_i;
                gw_write_pending <= 1;
            end
            if (gw_wvalid_i && gw_wready_o && gw_wlast_i) begin
                gw_bvalid_o <= 1;
                gw_write_pending <= 0;
            end
            else if (gw_bready_i) gw_bvalid_o <= 0;
        end
    end
    int p0_remaining;
    assign p0_arready_o = rst_mem_core_n_i && !p0_rvalid_o;
    always @(posedge clk_mem_i) begin
        if (!rst_mem_core_n_i) begin
            p0_rvalid_o <= 0;
            p0_remaining <= 0;
            p0_rid_o <= 0;
            p0_rdata_o <= 0;
            p0_rresp_o <= 0;
            p0_rlast_o <= 0;
        end else begin
            if (p0_arvalid_i && p0_arready_o) begin
                p0_rvalid_o <= 1;
                p0_remaining <= int'(p0_arlen_i);
                p0_rid_o <= p0_arid_i;
                p0_rlast_o <= p0_arlen_i == 0;
            end else if (p0_rvalid_o && p0_rready_i) begin
                p0_remaining <= p0_remaining - 1;
                p0_rlast_o <= p0_remaining == 1;
                if (p0_remaining == 0) p0_rvalid_o <= 0;
            end
        end
    end
    logic p1_write_pending;
    assign p1_awready_o = rst_mem_core_n_i && !p1_write_pending && !p1_bvalid_o;
    assign p1_wready_o = rst_mem_core_n_i && p1_write_pending && !p1_bvalid_o;
    always @(posedge clk_mem_i) begin
        if (!rst_mem_core_n_i) begin
            p1_bvalid_o <= 0;
            p1_write_pending <= 0;
            p1_bid_o <= 0;
            p1_bresp_o <= 0;
        end else begin
            if (p1_awvalid_i && p1_awready_o) begin
                p1_bid_o <= p1_awid_i;
                p1_write_pending <= 1;
            end
            if (p1_wvalid_i && p1_wready_o && p1_wlast_i) begin
                p1_bvalid_o <= 1;
                p1_write_pending <= 0;
            end
            else if (p1_bready_i) p1_bvalid_o <= 0;
        end
    end
    int p3_remaining;
    assign p3_arready_o = rst_mem_core_n_i && !p3_rvalid_o;
    always @(posedge clk_mem_i) begin
        if (!rst_mem_core_n_i) begin
            p3_rvalid_o <= 0;
            p3_remaining <= 0;
            p3_rid_o <= 0;
            p3_rdata_o <= 0;
            p3_rresp_o <= 0;
            p3_rlast_o <= 0;
        end else begin
            if (p3_arvalid_i && p3_arready_o) begin
                p3_rvalid_o <= 1;
                p3_remaining <= int'(p3_arlen_i);
                p3_rid_o <= p3_arid_i;
                p3_rlast_o <= p3_arlen_i == 0;
            end else if (p3_rvalid_o && p3_rready_i) begin
                p3_remaining <= p3_remaining - 1;
                p3_rlast_o <= p3_remaining == 1;
                if (p3_remaining == 0) p3_rvalid_o <= 0;
            end
        end
    end
    logic p3_write_pending;
    assign p3_awready_o = rst_mem_core_n_i && !p3_write_pending && !p3_bvalid_o;
    assign p3_wready_o = rst_mem_core_n_i && p3_write_pending && !p3_bvalid_o;
    always @(posedge clk_mem_i) begin
        if (!rst_mem_core_n_i) begin
            p3_bvalid_o <= 0;
            p3_write_pending <= 0;
            p3_bid_o <= 0;
            p3_bresp_o <= 0;
        end else begin
            if (p3_awvalid_i && p3_awready_o) begin
                p3_bid_o <= p3_awid_i;
                p3_write_pending <= 1;
            end
            if (p3_wvalid_i && p3_wready_o && p3_wlast_i) begin
                p3_bvalid_o <= 1;
                p3_write_pending <= 0;
            end
            else if (p3_bready_i) p3_bvalid_o <= 0;
        end
    end
    int p4_remaining;
    assign p4_arready_o = rst_mem_core_n_i && !p4_rvalid_o;
    always @(posedge clk_mem_i) begin
        if (!rst_mem_core_n_i) begin
            p4_rvalid_o <= 0;
            p4_remaining <= 0;
            p4_rid_o <= 0;
            p4_rdata_o <= 0;
            p4_rresp_o <= 0;
            p4_rlast_o <= 0;
        end else begin
            if (p4_arvalid_i && p4_arready_o) begin
                p4_rvalid_o <= 1;
                p4_remaining <= int'(p4_arlen_i);
                p4_rid_o <= p4_arid_i;
                p4_rlast_o <= p4_arlen_i == 0;
            end else if (p4_rvalid_o && p4_rready_i) begin
                p4_remaining <= p4_remaining - 1;
                p4_rlast_o <= p4_remaining == 1;
                if (p4_remaining == 0) p4_rvalid_o <= 0;
            end
        end
    end
    logic p4_write_pending;
    assign p4_awready_o = rst_mem_core_n_i && !p4_write_pending && !p4_bvalid_o;
    assign p4_wready_o = rst_mem_core_n_i && p4_write_pending && !p4_bvalid_o;
    always @(posedge clk_mem_i) begin
        if (!rst_mem_core_n_i) begin
            p4_bvalid_o <= 0;
            p4_write_pending <= 0;
            p4_bid_o <= 0;
            p4_bresp_o <= 0;
        end else begin
            if (p4_awvalid_i && p4_awready_o) begin
                p4_bid_o <= p4_awid_i;
                p4_write_pending <= 1;
            end
            if (p4_wvalid_i && p4_wready_o && p4_wlast_i) begin
                p4_bvalid_o <= 1;
                p4_write_pending <= 0;
            end
            else if (p4_bready_i) p4_bvalid_o <= 0;
        end
    end
    int p5_remaining;
    assign p5_arready_o = rst_mem_core_n_i && !p5_rvalid_o;
    always @(posedge clk_mem_i) begin
        if (!rst_mem_core_n_i) begin
            p5_rvalid_o <= 0;
            p5_remaining <= 0;
            p5_rid_o <= 0;
            p5_rdata_o <= 0;
            p5_rresp_o <= 0;
            p5_rlast_o <= 0;
        end else begin
            if (p5_arvalid_i && p5_arready_o) begin
                p5_rvalid_o <= 1;
                p5_remaining <= int'(p5_arlen_i);
                p5_rid_o <= p5_arid_i;
                p5_rlast_o <= p5_arlen_i == 0;
            end else if (p5_rvalid_o && p5_rready_i) begin
                p5_remaining <= p5_remaining - 1;
                p5_rlast_o <= p5_remaining == 1;
                if (p5_remaining == 0) p5_rvalid_o <= 0;
            end
        end
    end
    logic p5_write_pending;
    assign p5_awready_o = rst_mem_core_n_i && !p5_write_pending && !p5_bvalid_o;
    assign p5_wready_o = rst_mem_core_n_i && p5_write_pending && !p5_bvalid_o;
    always @(posedge clk_mem_i) begin
        if (!rst_mem_core_n_i) begin
            p5_bvalid_o <= 0;
            p5_write_pending <= 0;
            p5_bid_o <= 0;
            p5_bresp_o <= 0;
        end else begin
            if (p5_awvalid_i && p5_awready_o) begin
                p5_bid_o <= p5_awid_i;
                p5_write_pending <= 1;
            end
            if (p5_wvalid_i && p5_wready_o && p5_wlast_i) begin
                p5_bvalid_o <= 1;
                p5_write_pending <= 0;
            end
            else if (p5_bready_i) p5_bvalid_o <= 0;
        end
    end
    int eth_remaining;
    assign eth_arready_o = rst_mem_core_n_i && !eth_rvalid_o;
    always @(posedge clk_mem_i) begin
        if (!rst_mem_core_n_i) begin
            eth_rvalid_o <= 0;
            eth_remaining <= 0;
            eth_rid_o <= 0;
            eth_rdata_o <= 0;
            eth_rresp_o <= 0;
            eth_rlast_o <= 0;
        end else begin
            if (eth_arvalid_i && eth_arready_o) begin
                eth_rvalid_o <= 1;
                eth_remaining <= int'(eth_arlen_i);
                eth_rid_o <= eth_arid_i;
                eth_rlast_o <= eth_arlen_i == 0;
            end else if (eth_rvalid_o && eth_rready_i) begin
                eth_remaining <= eth_remaining - 1;
                eth_rlast_o <= eth_remaining == 1;
                if (eth_remaining == 0) eth_rvalid_o <= 0;
            end
        end
    end
    logic eth_write_pending;
    assign eth_awready_o = rst_mem_core_n_i && !eth_write_pending && !eth_bvalid_o;
    assign eth_wready_o = rst_mem_core_n_i && eth_write_pending && !eth_bvalid_o;
    always @(posedge clk_mem_i) begin
        if (!rst_mem_core_n_i) begin
            eth_bvalid_o <= 0;
            eth_write_pending <= 0;
            eth_bid_o <= 0;
            eth_bresp_o <= 0;
        end else begin
            if (eth_awvalid_i && eth_awready_o) begin
                eth_bid_o <= eth_awid_i;
                eth_write_pending <= 1;
            end
            if (eth_wvalid_i && eth_wready_o && eth_wlast_i) begin
                eth_bvalid_o <= 1;
                eth_write_pending <= 0;
            end
            else if (eth_bready_i) eth_bvalid_o <= 0;
        end
    end
    assign ddr_awid_o = '0;
    assign ddr_awaddr_o = '0;
    assign ddr_awlen_o = '0;
    assign ddr_awvalid_o = '0;
    assign ddr_wdata_o = '0;
    assign ddr_wstrb_o = '0;
    assign ddr_wlast_o = '0;
    assign ddr_wvalid_o = '0;
    assign ddr_arid_o = '0;
    assign ddr_araddr_o = '0;
    assign ddr_arlen_o = '0;
    assign ddr_arvalid_o = '0;
    assign xbar_apb_pready_o = 1;
    assign xbar_apb_prdata_o = '0;
    assign xbar_apb_pslverr_o = '0;
    assign pmon_apb_pready_o = 1;
    assign pmon_apb_prdata_o = '0;
    assign pmon_apb_pslverr_o = '0;
    assign irq_mem_xbar_o = '0;
    edrv32_mem_pmon_stub u_perf_mon (
        .axi_arvalid_o(),
        .axi_arready_i(1'b0),
        .axi_araddr_o(),
        .axi_arlen_o(),
        .axi_arid_o(),
        .axi_rvalid_i(1'b0),
        .axi_rready_o(),
        .axi_rlast_i(1'b0),
        .axi_rdata_i(256'b0),
        .axi_rresp_i(2'b0),
        .axi_rid_i(1'b0),
        .axi_awvalid_o(),
        .axi_awready_i(1'b0),
        .axi_awaddr_o(),
        .axi_awlen_o(),
        .axi_awid_o(),
        .axi_wvalid_o(),
        .axi_wready_i(1'b0),
        .axi_wlast_o(),
        .axi_wdata_o(),
        .axi_wstrb_o(),
        .axi_bvalid_i(1'b0),
        .axi_bready_o(),
        .axi_bid_i(1'b0),
        .axi_bresp_i(2'b0)
    );
    edrv32_mem_xbar_stub u_xbar (
        .p0_arid_i(1'b0),
        .p0_araddr_i(32'b0),
        .p0_arlen_i(4'b0),
        .p0_arvalid_i(1'b0),
        .p0_arready_o(),
        .p0_rid_o(),
        .p0_rdata_o(),
        .p0_rresp_o(),
        .p0_rlast_o(),
        .p0_rvalid_o(),
        .p0_rready_i(1'b0),
        .p0_urgent_i(1'b0),
        .p1_awid_i(1'b0),
        .p1_awaddr_i(32'b0),
        .p1_awlen_i(4'b0),
        .p1_awvalid_i(1'b0),
        .p1_awready_o(),
        .p1_wdata_i(256'b0),
        .p1_wstrb_i(32'b0),
        .p1_wlast_i(1'b0),
        .p1_wvalid_i(1'b0),
        .p1_wready_o(),
        .p1_bid_o(),
        .p1_bresp_o(),
        .p1_bvalid_o(),
        .p1_bready_i(1'b0),
        .p1_urgent_i(1'b0),
        .p2_arid_i(1'b0),
        .p2_araddr_i(32'b0),
        .p2_arlen_i(4'b0),
        .p2_arvalid_i(1'b0),
        .p2_arready_o(),
        .p2_rid_o(),
        .p2_rdata_o(),
        .p2_rresp_o(),
        .p2_rlast_o(),
        .p2_rvalid_o(),
        .p2_rready_i(1'b0),
        .p2_awid_i(1'b0),
        .p2_awaddr_i(32'b0),
        .p2_awlen_i(4'b0),
        .p2_awvalid_i(1'b0),
        .p2_awready_o(),
        .p2_wdata_i(256'b0),
        .p2_wstrb_i(32'b0),
        .p2_wlast_i(1'b0),
        .p2_wvalid_i(1'b0),
        .p2_wready_o(),
        .p2_bid_o(),
        .p2_bresp_o(),
        .p2_bvalid_o(),
        .p2_bready_i(1'b0),
        .p3_arid_i(1'b0),
        .p3_araddr_i(32'b0),
        .p3_arlen_i(4'b0),
        .p3_arvalid_i(1'b0),
        .p3_arready_o(),
        .p3_rid_o(),
        .p3_rdata_o(),
        .p3_rresp_o(),
        .p3_rlast_o(),
        .p3_rvalid_o(),
        .p3_rready_i(1'b0),
        .p3_awid_i(1'b0),
        .p3_awaddr_i(32'b0),
        .p3_awlen_i(4'b0),
        .p3_awvalid_i(1'b0),
        .p3_awready_o(),
        .p3_wdata_i(256'b0),
        .p3_wstrb_i(32'b0),
        .p3_wlast_i(1'b0),
        .p3_wvalid_i(1'b0),
        .p3_wready_o(),
        .p3_bid_o(),
        .p3_bresp_o(),
        .p3_bvalid_o(),
        .p3_bready_i(1'b0),
        .p4_arid_i(1'b0),
        .p4_araddr_i(32'b0),
        .p4_arlen_i(4'b0),
        .p4_arvalid_i(1'b0),
        .p4_arready_o(),
        .p4_rid_o(),
        .p4_rdata_o(),
        .p4_rresp_o(),
        .p4_rlast_o(),
        .p4_rvalid_o(),
        .p4_rready_i(1'b0),
        .p4_awid_i(1'b0),
        .p4_awaddr_i(32'b0),
        .p4_awlen_i(4'b0),
        .p4_awvalid_i(1'b0),
        .p4_awready_o(),
        .p4_wdata_i(256'b0),
        .p4_wstrb_i(32'b0),
        .p4_wlast_i(1'b0),
        .p4_wvalid_i(1'b0),
        .p4_wready_o(),
        .p4_bid_o(),
        .p4_bresp_o(),
        .p4_bvalid_o(),
        .p4_bready_i(1'b0),
        .p5_arid_i(1'b0),
        .p5_araddr_i(32'b0),
        .p5_arlen_i(4'b0),
        .p5_arvalid_i(1'b0),
        .p5_arready_o(),
        .p5_rid_o(),
        .p5_rdata_o(),
        .p5_rresp_o(),
        .p5_rlast_o(),
        .p5_rvalid_o(),
        .p5_rready_i(1'b0),
        .p5_awid_i(1'b0),
        .p5_awaddr_i(32'b0),
        .p5_awlen_i(4'b0),
        .p5_awvalid_i(1'b0),
        .p5_awready_o(),
        .p5_wdata_i(256'b0),
        .p5_wstrb_i(32'b0),
        .p5_wlast_i(1'b0),
        .p5_wvalid_i(1'b0),
        .p5_wready_o(),
        .p5_bid_o(),
        .p5_bresp_o(),
        .p5_bvalid_o(),
        .p5_bready_i(1'b0),
        .p6_arid_i(1'b0),
        .p6_araddr_i(32'b0),
        .p6_arlen_i(4'b0),
        .p6_arvalid_i(1'b0),
        .p6_arready_o(),
        .p6_rid_o(),
        .p6_rdata_o(),
        .p6_rresp_o(),
        .p6_rlast_o(),
        .p6_rvalid_o(),
        .p6_rready_i(1'b0),
        .p6_awid_i(1'b0),
        .p6_awaddr_i(32'b0),
        .p6_awlen_i(4'b0),
        .p6_awvalid_i(1'b0),
        .p6_awready_o(),
        .p6_wdata_i(256'b0),
        .p6_wstrb_i(32'b0),
        .p6_wlast_i(1'b0),
        .p6_wvalid_i(1'b0),
        .p6_wready_o(),
        .p6_bid_o(),
        .p6_bresp_o(),
        .p6_bvalid_o(),
        .p6_bready_i(1'b0),
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_core_n_i)
    );
endmodule
