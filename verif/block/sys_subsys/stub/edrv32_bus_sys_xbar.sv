// File: edrv32_bus_sys_xbar.sv
// Spec: sys-subsys 3.1/3.2; sys-subsys-testplan 2.1.
// Description: Port-only fixture for compiling passive binds without reading DUT RTL.
// Clock domain: the observed interface clock.
module edrv32_bus_sys_xbar (
    input logic clk_i,
    input logic rst_n_i,
    output logic [3:0] s0_awid_o,
    output logic [31:0] s0_awaddr_o,
    output logic [7:0] s0_awlen_o,
    output logic [2:0] s0_awsize_o,
    output logic [1:0] s0_awburst_o,
    output logic s0_awvalid_o,
    input logic s0_awready_i,
    output logic [63:0] s0_wdata_o,
    output logic [7:0] s0_wstrb_o,
    output logic s0_wlast_o,
    output logic s0_wvalid_o,
    input logic s0_wready_i,
    input logic [3:0] s0_bid_i,
    input logic [1:0] s0_bresp_i,
    input logic s0_bvalid_i,
    output logic s0_bready_o,
    output logic [3:0] s0_arid_o,
    output logic [31:0] s0_araddr_o,
    output logic [7:0] s0_arlen_o,
    output logic [2:0] s0_arsize_o,
    output logic [1:0] s0_arburst_o,
    output logic s0_arvalid_o,
    input logic s0_arready_i,
    input logic [3:0] s0_rid_i,
    input logic [63:0] s0_rdata_i,
    input logic [1:0] s0_rresp_i,
    input logic s0_rlast_i,
    input logic s0_rvalid_i,
    output logic s0_rready_o,
    output logic [3:0] s1_awid_o,
    output logic [31:0] s1_awaddr_o,
    output logic [7:0] s1_awlen_o,
    output logic [2:0] s1_awsize_o,
    output logic [1:0] s1_awburst_o,
    output logic s1_awvalid_o,
    input logic s1_awready_i,
    output logic [63:0] s1_wdata_o,
    output logic [7:0] s1_wstrb_o,
    output logic s1_wlast_o,
    output logic s1_wvalid_o,
    input logic s1_wready_i,
    input logic [3:0] s1_bid_i,
    input logic [1:0] s1_bresp_i,
    input logic s1_bvalid_i,
    output logic s1_bready_o,
    output logic [3:0] s1_arid_o,
    output logic [31:0] s1_araddr_o,
    output logic [7:0] s1_arlen_o,
    output logic [2:0] s1_arsize_o,
    output logic [1:0] s1_arburst_o,
    output logic s1_arvalid_o,
    input logic s1_arready_i,
    input logic [3:0] s1_rid_i,
    input logic [63:0] s1_rdata_i,
    input logic [1:0] s1_rresp_i,
    input logic s1_rlast_i,
    input logic s1_rvalid_i,
    output logic s1_rready_o,
    output logic [3:0] s2_awid_o,
    output logic [31:0] s2_awaddr_o,
    output logic [7:0] s2_awlen_o,
    output logic [2:0] s2_awsize_o,
    output logic [1:0] s2_awburst_o,
    output logic s2_awvalid_o,
    input logic s2_awready_i,
    output logic [63:0] s2_wdata_o,
    output logic [7:0] s2_wstrb_o,
    output logic s2_wlast_o,
    output logic s2_wvalid_o,
    input logic s2_wready_i,
    input logic [3:0] s2_bid_i,
    input logic [1:0] s2_bresp_i,
    input logic s2_bvalid_i,
    output logic s2_bready_o,
    output logic [3:0] s2_arid_o,
    output logic [31:0] s2_araddr_o,
    output logic [7:0] s2_arlen_o,
    output logic [2:0] s2_arsize_o,
    output logic [1:0] s2_arburst_o,
    output logic s2_arvalid_o,
    input logic s2_arready_i,
    input logic [3:0] s2_rid_i,
    input logic [63:0] s2_rdata_i,
    input logic [1:0] s2_rresp_i,
    input logic s2_rlast_i,
    input logic s2_rvalid_i,
    output logic s2_rready_o,
    output logic [3:0] s3_awid_o,
    output logic [31:0] s3_awaddr_o,
    output logic [7:0] s3_awlen_o,
    output logic [2:0] s3_awsize_o,
    output logic [1:0] s3_awburst_o,
    output logic s3_awvalid_o,
    input logic s3_awready_i,
    output logic [63:0] s3_wdata_o,
    output logic [7:0] s3_wstrb_o,
    output logic s3_wlast_o,
    output logic s3_wvalid_o,
    input logic s3_wready_i,
    input logic [3:0] s3_bid_i,
    input logic [1:0] s3_bresp_i,
    input logic s3_bvalid_i,
    output logic s3_bready_o,
    output logic [3:0] s3_arid_o,
    output logic [31:0] s3_araddr_o,
    output logic [7:0] s3_arlen_o,
    output logic [2:0] s3_arsize_o,
    output logic [1:0] s3_arburst_o,
    output logic s3_arvalid_o,
    input logic s3_arready_i,
    input logic [3:0] s3_rid_i,
    input logic [63:0] s3_rdata_i,
    input logic [1:0] s3_rresp_i,
    input logic s3_rlast_i,
    input logic s3_rvalid_i,
    output logic s3_rready_o,
    output logic [3:0] s4_awid_o,
    output logic [31:0] s4_awaddr_o,
    output logic [7:0] s4_awlen_o,
    output logic [2:0] s4_awsize_o,
    output logic [1:0] s4_awburst_o,
    output logic s4_awvalid_o,
    input logic s4_awready_i,
    output logic [63:0] s4_wdata_o,
    output logic [7:0] s4_wstrb_o,
    output logic s4_wlast_o,
    output logic s4_wvalid_o,
    input logic s4_wready_i,
    input logic [3:0] s4_bid_i,
    input logic [1:0] s4_bresp_i,
    input logic s4_bvalid_i,
    output logic s4_bready_o,
    output logic [3:0] s4_arid_o,
    output logic [31:0] s4_araddr_o,
    output logic [7:0] s4_arlen_o,
    output logic [2:0] s4_arsize_o,
    output logic [1:0] s4_arburst_o,
    output logic s4_arvalid_o,
    input logic s4_arready_i,
    input logic [3:0] s4_rid_i,
    input logic [63:0] s4_rdata_i,
    input logic [1:0] s4_rresp_i,
    input logic s4_rlast_i,
    input logic s4_rvalid_i,
    output logic s4_rready_o,
    output logic [3:0] s5_awid_o,
    output logic [31:0] s5_awaddr_o,
    output logic [7:0] s5_awlen_o,
    output logic [2:0] s5_awsize_o,
    output logic [1:0] s5_awburst_o,
    output logic s5_awvalid_o,
    input logic s5_awready_i,
    output logic [63:0] s5_wdata_o,
    output logic [7:0] s5_wstrb_o,
    output logic s5_wlast_o,
    output logic s5_wvalid_o,
    input logic s5_wready_i,
    input logic [3:0] s5_bid_i,
    input logic [1:0] s5_bresp_i,
    input logic s5_bvalid_i,
    output logic s5_bready_o,
    output logic [3:0] s5_arid_o,
    output logic [31:0] s5_araddr_o,
    output logic [7:0] s5_arlen_o,
    output logic [2:0] s5_arsize_o,
    output logic [1:0] s5_arburst_o,
    output logic s5_arvalid_o,
    input logic s5_arready_i,
    input logic [3:0] s5_rid_i,
    input logic [63:0] s5_rdata_i,
    input logic [1:0] s5_rresp_i,
    input logic s5_rlast_i,
    input logic s5_rvalid_i,
    output logic s5_rready_o,
    output logic [3:0] s6_awid_o,
    output logic [31:0] s6_awaddr_o,
    output logic [7:0] s6_awlen_o,
    output logic [2:0] s6_awsize_o,
    output logic [1:0] s6_awburst_o,
    output logic s6_awvalid_o,
    input logic s6_awready_i,
    output logic [63:0] s6_wdata_o,
    output logic [7:0] s6_wstrb_o,
    output logic s6_wlast_o,
    output logic s6_wvalid_o,
    input logic s6_wready_i,
    input logic [3:0] s6_bid_i,
    input logic [1:0] s6_bresp_i,
    input logic s6_bvalid_i,
    output logic s6_bready_o,
    output logic [3:0] s6_arid_o,
    output logic [31:0] s6_araddr_o,
    output logic [7:0] s6_arlen_o,
    output logic [2:0] s6_arsize_o,
    output logic [1:0] s6_arburst_o,
    output logic s6_arvalid_o,
    input logic s6_arready_i,
    input logic [3:0] s6_rid_i,
    input logic [63:0] s6_rdata_i,
    input logic [1:0] s6_rresp_i,
    input logic s6_rlast_i,
    input logic s6_rvalid_i,
    output logic s6_rready_o
);
    assign s0_awid_o = 0;
    assign s0_awaddr_o = 0;
    assign s0_awlen_o = 0;
    assign s0_awsize_o = 0;
    assign s0_awburst_o = 0;
    assign s0_awvalid_o = 0;
    assign s0_wdata_o = 0;
    assign s0_wstrb_o = 0;
    assign s0_wlast_o = 0;
    assign s0_wvalid_o = 0;
    assign s0_bready_o = 0;
    assign s0_arid_o = 0;
    assign s0_araddr_o = 0;
    assign s0_arlen_o = 0;
    assign s0_arsize_o = 0;
    assign s0_arburst_o = 0;
    assign s0_arvalid_o = 0;
    assign s0_rready_o = 0;
    assign s1_awid_o = 0;
    assign s1_awaddr_o = 0;
    assign s1_awlen_o = 0;
    assign s1_awsize_o = 0;
    assign s1_awburst_o = 0;
    assign s1_awvalid_o = 0;
    assign s1_wdata_o = 0;
    assign s1_wstrb_o = 0;
    assign s1_wlast_o = 0;
    assign s1_wvalid_o = 0;
    assign s1_bready_o = 0;
    assign s1_arid_o = 0;
    assign s1_araddr_o = 0;
    assign s1_arlen_o = 0;
    assign s1_arsize_o = 0;
    assign s1_arburst_o = 0;
    assign s1_arvalid_o = 0;
    assign s1_rready_o = 0;
    assign s2_awid_o = 0;
    assign s2_awaddr_o = 0;
    assign s2_awlen_o = 0;
    assign s2_awsize_o = 0;
    assign s2_awburst_o = 0;
    assign s2_awvalid_o = 0;
    assign s2_wdata_o = 0;
    assign s2_wstrb_o = 0;
    assign s2_wlast_o = 0;
    assign s2_wvalid_o = 0;
    assign s2_bready_o = 0;
    assign s2_arid_o = 0;
    assign s2_araddr_o = 0;
    assign s2_arlen_o = 0;
    assign s2_arsize_o = 0;
    assign s2_arburst_o = 0;
    assign s2_arvalid_o = 0;
    assign s2_rready_o = 0;
    assign s3_awid_o = 0;
    assign s3_awaddr_o = 0;
    assign s3_awlen_o = 0;
    assign s3_awsize_o = 0;
    assign s3_awburst_o = 0;
    assign s3_awvalid_o = 0;
    assign s3_wdata_o = 0;
    assign s3_wstrb_o = 0;
    assign s3_wlast_o = 0;
    assign s3_wvalid_o = 0;
    assign s3_bready_o = 0;
    assign s3_arid_o = 0;
    assign s3_araddr_o = 0;
    assign s3_arlen_o = 0;
    assign s3_arsize_o = 0;
    assign s3_arburst_o = 0;
    assign s3_arvalid_o = 0;
    assign s3_rready_o = 0;
    assign s4_awid_o = 0;
    assign s4_awaddr_o = 0;
    assign s4_awlen_o = 0;
    assign s4_awsize_o = 0;
    assign s4_awburst_o = 0;
    assign s4_awvalid_o = 0;
    assign s4_wdata_o = 0;
    assign s4_wstrb_o = 0;
    assign s4_wlast_o = 0;
    assign s4_wvalid_o = 0;
    assign s4_bready_o = 0;
    assign s4_arid_o = 0;
    assign s4_araddr_o = 0;
    assign s4_arlen_o = 0;
    assign s4_arsize_o = 0;
    assign s4_arburst_o = 0;
    assign s4_arvalid_o = 0;
    assign s4_rready_o = 0;
    assign s5_awid_o = 0;
    assign s5_awaddr_o = 0;
    assign s5_awlen_o = 0;
    assign s5_awsize_o = 0;
    assign s5_awburst_o = 0;
    assign s5_awvalid_o = 0;
    assign s5_wdata_o = 0;
    assign s5_wstrb_o = 0;
    assign s5_wlast_o = 0;
    assign s5_wvalid_o = 0;
    assign s5_bready_o = 0;
    assign s5_arid_o = 0;
    assign s5_araddr_o = 0;
    assign s5_arlen_o = 0;
    assign s5_arsize_o = 0;
    assign s5_arburst_o = 0;
    assign s5_arvalid_o = 0;
    assign s5_rready_o = 0;
    assign s6_awid_o = 0;
    assign s6_awaddr_o = 0;
    assign s6_awlen_o = 0;
    assign s6_awsize_o = 0;
    assign s6_awburst_o = 0;
    assign s6_awvalid_o = 0;
    assign s6_wdata_o = 0;
    assign s6_wstrb_o = 0;
    assign s6_wlast_o = 0;
    assign s6_wvalid_o = 0;
    assign s6_bready_o = 0;
    assign s6_arid_o = 0;
    assign s6_araddr_o = 0;
    assign s6_arlen_o = 0;
    assign s6_arsize_o = 0;
    assign s6_arburst_o = 0;
    assign s6_arvalid_o = 0;
    assign s6_rready_o = 0;
    wire unused_inputs = &{
        clk_i,
        rst_n_i,
        s0_awready_i,
        s0_wready_i,
        s0_bid_i,
        s0_bresp_i,
        s0_bvalid_i,
        s0_arready_i,
        s0_rid_i,
        s0_rdata_i,
        s0_rresp_i,
        s0_rlast_i,
        s0_rvalid_i,
        s1_awready_i,
        s1_wready_i,
        s1_bid_i,
        s1_bresp_i,
        s1_bvalid_i,
        s1_arready_i,
        s1_rid_i,
        s1_rdata_i,
        s1_rresp_i,
        s1_rlast_i,
        s1_rvalid_i,
        s2_awready_i,
        s2_wready_i,
        s2_bid_i,
        s2_bresp_i,
        s2_bvalid_i,
        s2_arready_i,
        s2_rid_i,
        s2_rdata_i,
        s2_rresp_i,
        s2_rlast_i,
        s2_rvalid_i,
        s3_awready_i,
        s3_wready_i,
        s3_bid_i,
        s3_bresp_i,
        s3_bvalid_i,
        s3_arready_i,
        s3_rid_i,
        s3_rdata_i,
        s3_rresp_i,
        s3_rlast_i,
        s3_rvalid_i,
        s4_awready_i,
        s4_wready_i,
        s4_bid_i,
        s4_bresp_i,
        s4_bvalid_i,
        s4_arready_i,
        s4_rid_i,
        s4_rdata_i,
        s4_rresp_i,
        s4_rlast_i,
        s4_rvalid_i,
        s5_awready_i,
        s5_wready_i,
        s5_bid_i,
        s5_bresp_i,
        s5_bvalid_i,
        s5_arready_i,
        s5_rid_i,
        s5_rdata_i,
        s5_rresp_i,
        s5_rlast_i,
        s5_rvalid_i,
        s6_awready_i,
        s6_wready_i,
        s6_bid_i,
        s6_bresp_i,
        s6_bvalid_i,
        s6_arready_i,
        s6_rid_i,
        s6_rdata_i,
        s6_rresp_i,
        s6_rlast_i,
        s6_rvalid_i
    };
endmodule
