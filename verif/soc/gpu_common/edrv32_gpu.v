// File: edrv32_gpu.v
// Spec: T-1a placeholder; gpu-spec 3.
// Description: Idle placeholder for lint, ST-08 and ST-09 non-GPU checks.
//              Never use for GPU register, interrupt or rendering validation.
// Clock domain: clk_gpu.
module edrv32_gpu (
    input wire clk_gpu_i,
    input wire rst_gpu_n_i,
    output wire [0:0] m_axi_awid_o,
    output wire [31:0] m_axi_awaddr_o,
    output wire [3:0] m_axi_awlen_o,
    output wire m_axi_awvalid_o,
    input wire m_axi_awready_i,
    output wire [255:0] m_axi_wdata_o,
    output wire [31:0] m_axi_wstrb_o,
    output wire m_axi_wlast_o,
    output wire m_axi_wvalid_o,
    input wire m_axi_wready_i,
    input wire [0:0] m_axi_bid_i,
    input wire [1:0] m_axi_bresp_i,
    input wire m_axi_bvalid_i,
    output wire m_axi_bready_o,
    output wire [0:0] m_axi_arid_o,
    output wire [31:0] m_axi_araddr_o,
    output wire [3:0] m_axi_arlen_o,
    output wire m_axi_arvalid_o,
    input wire m_axi_arready_i,
    input wire [0:0] m_axi_rid_i,
    input wire [255:0] m_axi_rdata_i,
    input wire [1:0] m_axi_rresp_i,
    input wire m_axi_rlast_i,
    input wire m_axi_rvalid_i,
    output wire m_axi_rready_o,
    input wire [11:0] s_apb_paddr_i,
    input wire s_apb_psel_i,
    input wire s_apb_penable_i,
    input wire s_apb_pwrite_i,
    input wire [31:0] s_apb_pwdata_i,
    input wire [3:0] s_apb_pstrb_i,
    output wire [31:0] s_apb_prdata_o,
    output wire s_apb_pready_o,
    output wire s_apb_pslverr_o,
    output wire irq_o
);
    assign m_axi_awid_o = 'b0;
    assign m_axi_awaddr_o = 'b0;
    assign m_axi_awlen_o = 'b0;
    assign m_axi_awvalid_o = 'b0;
    assign m_axi_wdata_o = 'b0;
    assign m_axi_wstrb_o = 'b0;
    assign m_axi_wlast_o = 'b0;
    assign m_axi_wvalid_o = 'b0;
    assign m_axi_bready_o = 1'b1;
    assign m_axi_arid_o = 'b0;
    assign m_axi_araddr_o = 'b0;
    assign m_axi_arlen_o = 'b0;
    assign m_axi_arvalid_o = 'b0;
    assign m_axi_rready_o = 1'b1;
    assign s_apb_prdata_o = 'b0;
    assign s_apb_pready_o = 1'b1;
    assign s_apb_pslverr_o = 1'b1;
    assign irq_o = 'b0;
    wire unused_w;
    assign unused_w = &{1'b0, clk_gpu_i,
        rst_gpu_n_i,
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
        m_axi_rvalid_i,
        s_apb_paddr_i,
        s_apb_psel_i,
        s_apb_penable_i,
        s_apb_pwrite_i,
        s_apb_pwdata_i,
        s_apb_pstrb_i};
endmodule
