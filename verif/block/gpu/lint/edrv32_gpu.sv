// File: edrv32_gpu.sv
// Spec: gpu-spec 3; SoC 4.2, 4.3.
// Description: Public port contract used exclusively for lint before RTL integration.
// Clock domain: clk_gpu. This module provides no GPU behavior.
`timescale 1ns/1ps
module edrv32_gpu (
    // Clock and reset.
    input wire clk_gpu_i,
    input wire rst_gpu_n_i,

    // APB control interface.
    input wire [11:0] s_apb_paddr_i,
    input wire s_apb_psel_i,
    input wire s_apb_penable_i,
    input wire s_apb_pwrite_i,
    input wire [31:0] s_apb_pwdata_i,
    input wire [3:0] s_apb_pstrb_i,
    output wire s_apb_pready_o,
    output wire [31:0] s_apb_prdata_o,
    output wire s_apb_pslverr_o,

    // AXI256 DDR interface.
    output wire m_axi_awid_o,
    output wire [31:0] m_axi_awaddr_o,
    output wire [3:0] m_axi_awlen_o,
    output wire m_axi_awvalid_o,
    input wire m_axi_awready_i,
    output wire [255:0] m_axi_wdata_o,
    output wire [31:0] m_axi_wstrb_o,
    output wire m_axi_wlast_o,
    output wire m_axi_wvalid_o,
    input wire m_axi_wready_i,
    input wire m_axi_bid_i,
    input wire [1:0] m_axi_bresp_i,
    input wire m_axi_bvalid_i,
    output wire m_axi_bready_o,
    output wire m_axi_arid_o,
    output wire [31:0] m_axi_araddr_o,
    output wire [3:0] m_axi_arlen_o,
    output wire m_axi_arvalid_o,
    input wire m_axi_arready_i,
    input wire m_axi_rid_i,
    input wire [255:0] m_axi_rdata_i,
    input wire [1:0] m_axi_rresp_i,
    input wire m_axi_rlast_i,
    input wire m_axi_rvalid_i,
    output wire m_axi_rready_o,

    // Completion and error interrupt.
    output wire irq_o
);
    assign s_apb_pready_o = '0;
    assign s_apb_prdata_o = '0;
    assign s_apb_pslverr_o = '0;
    assign m_axi_awid_o = '0;
    assign m_axi_awaddr_o = '0;
    assign m_axi_awlen_o = '0;
    assign m_axi_awvalid_o = '0;
    assign m_axi_wdata_o = '0;
    assign m_axi_wstrb_o = '0;
    assign m_axi_wlast_o = '0;
    assign m_axi_wvalid_o = '0;
    assign m_axi_bready_o = '0;
    assign m_axi_arid_o = '0;
    assign m_axi_araddr_o = '0;
    assign m_axi_arlen_o = '0;
    assign m_axi_arvalid_o = '0;
    assign m_axi_rready_o = '0;
    assign irq_o = '0;
    wire unused_contract_w = &{
        clk_gpu_i,
        rst_gpu_n_i,
        s_apb_paddr_i,
        s_apb_psel_i,
        s_apb_penable_i,
        s_apb_pwrite_i,
        s_apb_pwdata_i,
        s_apb_pstrb_i,
        m_axi_awready_i,
        m_axi_wready_i,
        m_axi_bid_i,
        m_axi_bresp_i,
        m_axi_bvalid_i,
        m_axi_arready_i,
        m_axi_rid_i,
        m_axi_rdata_i,
        m_axi_rresp_i,
        m_axi_rlast_i,
        m_axi_rvalid_i
    };
endmodule
