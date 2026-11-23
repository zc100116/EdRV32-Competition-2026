// File: edrv32_soc_gpu_boundary_gpu.v
// Spec: gpu-soc-spec 5.2 X9/X10, 5.3; gpu-spec 3.
// Description: GPU core with common AXI256 and APB asynchronous bridges.
//              The PLIC synchronizes the GPU interrupt (X3).
// Clock domains: clk_gpu and clk_mem.
module edrv32_soc_gpu_boundary_gpu (
    // Domain clocks and synchronous-release resets.
    input wire clk_gpu_i,
    input wire rst_gpu_n_i,
    input wire clk_mem_i,
    input wire rst_mem_n_i,

    // Media APB slave in clk_mem.
    input wire [11:0] apb_paddr_i,
    input wire apb_psel_i,
    input wire apb_penable_i,
    input wire apb_pwrite_i,
    input wire [31:0] apb_pwdata_i,
    input wire [3:0] apb_pstrb_i,
    output wire [31:0] apb_prdata_o,
    output wire apb_pready_o,
    output wire apb_pslverr_o,

    // AXI256 master toward P3 in clk_mem.
    output wire [0:0] axi_awid_o,
    output wire [31:0] axi_awaddr_o,
    output wire [3:0] axi_awlen_o,
    output wire axi_awvalid_o,
    input wire axi_awready_i,
    output wire [255:0] axi_wdata_o,
    output wire [31:0] axi_wstrb_o,
    output wire axi_wlast_o,
    output wire axi_wvalid_o,
    input wire axi_wready_i,
    input wire [0:0] axi_bid_i,
    input wire [1:0] axi_bresp_i,
    input wire axi_bvalid_i,
    output wire axi_bready_o,
    output wire [0:0] axi_arid_o,
    output wire [31:0] axi_araddr_o,
    output wire [3:0] axi_arlen_o,
    output wire axi_arvalid_o,
    input wire axi_arready_i,
    input wire [0:0] axi_rid_i,
    input wire [255:0] axi_rdata_i,
    input wire [1:0] axi_rresp_i,
    input wire axi_rlast_i,
    input wire axi_rvalid_i,
    output wire axi_rready_o,

    // GPU-domain level, synchronized once by the PLIC (X3).
    output wire irq_o
);
    wire [0:0] m_axi_awid_w;
    wire [31:0] m_axi_awaddr_w;
    wire [3:0] m_axi_awlen_w;
    wire m_axi_awvalid_w;
    wire m_axi_awready_w;
    wire [255:0] m_axi_wdata_w;
    wire [31:0] m_axi_wstrb_w;
    wire m_axi_wlast_w;
    wire m_axi_wvalid_w;
    wire m_axi_wready_w;
    wire [0:0] m_axi_bid_w;
    wire [1:0] m_axi_bresp_w;
    wire m_axi_bvalid_w;
    wire m_axi_bready_w;
    wire [0:0] m_axi_arid_w;
    wire [31:0] m_axi_araddr_w;
    wire [3:0] m_axi_arlen_w;
    wire m_axi_arvalid_w;
    wire m_axi_arready_w;
    wire [0:0] m_axi_rid_w;
    wire [255:0] m_axi_rdata_w;
    wire [1:0] m_axi_rresp_w;
    wire m_axi_rlast_w;
    wire m_axi_rvalid_w;
    wire m_axi_rready_w;
    wire [15:0] s_apb_paddr_w;
    wire s_apb_psel_w;
    wire s_apb_penable_w;
    wire s_apb_pwrite_w;
    wire [31:0] s_apb_pwdata_w;
    wire [3:0] s_apb_pstrb_w;
    wire [31:0] s_apb_prdata_w;
    wire s_apb_pready_w;
    wire s_apb_pslverr_w;
    wire rst_gpu_n_w;
    wire rst_mem_n_w;
    edrv32_reset_copy u_reset_gpu (
        .clk_i(clk_gpu_i),
        .rst_n_i(rst_gpu_n_i),
        .rst_n_o(rst_gpu_n_w)
    );
    edrv32_reset_copy u_reset_mem (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_n_i),
        .rst_n_o(rst_mem_n_w)
    );

    edrv32_gpu u_core (
        .clk_gpu_i(clk_gpu_i),
        .rst_gpu_n_i(rst_gpu_n_w),
        .m_axi_awid_o(m_axi_awid_w),
        .m_axi_awaddr_o(m_axi_awaddr_w),
        .m_axi_awlen_o(m_axi_awlen_w),
        .m_axi_awvalid_o(m_axi_awvalid_w),
        .m_axi_awready_i(m_axi_awready_w),
        .m_axi_wdata_o(m_axi_wdata_w),
        .m_axi_wstrb_o(m_axi_wstrb_w),
        .m_axi_wlast_o(m_axi_wlast_w),
        .m_axi_wvalid_o(m_axi_wvalid_w),
        .m_axi_wready_i(m_axi_wready_w),
        .m_axi_bid_i(m_axi_bid_w),
        .m_axi_bresp_i(m_axi_bresp_w),
        .m_axi_bvalid_i(m_axi_bvalid_w),
        .m_axi_bready_o(m_axi_bready_w),
        .m_axi_arid_o(m_axi_arid_w),
        .m_axi_araddr_o(m_axi_araddr_w),
        .m_axi_arlen_o(m_axi_arlen_w),
        .m_axi_arvalid_o(m_axi_arvalid_w),
        .m_axi_arready_i(m_axi_arready_w),
        .m_axi_rid_i(m_axi_rid_w),
        .m_axi_rdata_i(m_axi_rdata_w),
        .m_axi_rresp_i(m_axi_rresp_w),
        .m_axi_rlast_i(m_axi_rlast_w),
        .m_axi_rvalid_i(m_axi_rvalid_w),
        .m_axi_rready_o(m_axi_rready_w),
        .s_apb_paddr_i(s_apb_paddr_w[11:0]),
        .s_apb_psel_i(s_apb_psel_w),
        .s_apb_penable_i(s_apb_penable_w),
        .s_apb_pwrite_i(s_apb_pwrite_w),
        .s_apb_pwdata_i(s_apb_pwdata_w),
        .s_apb_pstrb_i(s_apb_pstrb_w),
        .s_apb_prdata_o(s_apb_prdata_w),
        .s_apb_pready_o(s_apb_pready_w),
        .s_apb_pslverr_o(s_apb_pslverr_w),
        .irq_o(irq_o)
    );

    edrv32_axi256_async_bridge u_axi_async (
        .clk_npu_i(clk_gpu_i),
        .rst_npu_n_i(rst_gpu_n_w),
        .clk_mem_i(clk_mem_i),
        .rst_mem_n_i(rst_mem_n_w),
        .s_axi_awid_i(m_axi_awid_w),
        .s_axi_awaddr_i(m_axi_awaddr_w),
        .s_axi_awlen_i(m_axi_awlen_w),
        .s_axi_awvalid_i(m_axi_awvalid_w),
        .s_axi_awready_o(m_axi_awready_w),
        .s_axi_wdata_i(m_axi_wdata_w),
        .s_axi_wstrb_i(m_axi_wstrb_w),
        .s_axi_wlast_i(m_axi_wlast_w),
        .s_axi_wvalid_i(m_axi_wvalid_w),
        .s_axi_wready_o(m_axi_wready_w),
        .s_axi_bid_o(m_axi_bid_w),
        .s_axi_bresp_o(m_axi_bresp_w),
        .s_axi_bvalid_o(m_axi_bvalid_w),
        .s_axi_bready_i(m_axi_bready_w),
        .s_axi_arid_i(m_axi_arid_w),
        .s_axi_araddr_i(m_axi_araddr_w),
        .s_axi_arlen_i(m_axi_arlen_w),
        .s_axi_arvalid_i(m_axi_arvalid_w),
        .s_axi_arready_o(m_axi_arready_w),
        .s_axi_rid_o(m_axi_rid_w),
        .s_axi_rdata_o(m_axi_rdata_w),
        .s_axi_rresp_o(m_axi_rresp_w),
        .s_axi_rlast_o(m_axi_rlast_w),
        .s_axi_rvalid_o(m_axi_rvalid_w),
        .s_axi_rready_i(m_axi_rready_w),
        .m_axi_awid_o(axi_awid_o),
        .m_axi_awaddr_o(axi_awaddr_o),
        .m_axi_awlen_o(axi_awlen_o),
        .m_axi_awvalid_o(axi_awvalid_o),
        .m_axi_awready_i(axi_awready_i),
        .m_axi_wdata_o(axi_wdata_o),
        .m_axi_wstrb_o(axi_wstrb_o),
        .m_axi_wlast_o(axi_wlast_o),
        .m_axi_wvalid_o(axi_wvalid_o),
        .m_axi_wready_i(axi_wready_i),
        .m_axi_bid_i(axi_bid_i),
        .m_axi_bresp_i(axi_bresp_i),
        .m_axi_bvalid_i(axi_bvalid_i),
        .m_axi_bready_o(axi_bready_o),
        .m_axi_arid_o(axi_arid_o),
        .m_axi_araddr_o(axi_araddr_o),
        .m_axi_arlen_o(axi_arlen_o),
        .m_axi_arvalid_o(axi_arvalid_o),
        .m_axi_arready_i(axi_arready_i),
        .m_axi_rid_i(axi_rid_i),
        .m_axi_rdata_i(axi_rdata_i),
        .m_axi_rresp_i(axi_rresp_i),
        .m_axi_rlast_i(axi_rlast_i),
        .m_axi_rvalid_i(axi_rvalid_i),
        .m_axi_rready_o(axi_rready_o)
    );

    edrv32_apb_async_bridge u_apb_async (
        .clk_s_i(clk_mem_i),
        .rst_s_n_i(rst_mem_n_w),
        .clk_m_i(clk_gpu_i),
        .rst_m_n_i(rst_gpu_n_w),
        .s_apb_paddr_i({4'b0, apb_paddr_i}),
        .s_apb_psel_i(apb_psel_i),
        .s_apb_penable_i(apb_penable_i),
        .s_apb_pwrite_i(apb_pwrite_i),
        .s_apb_pwdata_i(apb_pwdata_i),
        .s_apb_pstrb_i(apb_pstrb_i),
        .s_apb_prdata_o(apb_prdata_o),
        .s_apb_pready_o(apb_pready_o),
        .s_apb_pslverr_o(apb_pslverr_o),
        .m_apb_paddr_o(s_apb_paddr_w),
        .m_apb_psel_o(s_apb_psel_w),
        .m_apb_penable_o(s_apb_penable_w),
        .m_apb_pwrite_o(s_apb_pwrite_w),
        .m_apb_pwdata_o(s_apb_pwdata_w),
        .m_apb_pstrb_o(s_apb_pstrb_w),
        .m_apb_prdata_i(s_apb_prdata_w),
        .m_apb_pready_i(s_apb_pready_w),
        .m_apb_pslverr_i(s_apb_pslverr_w)
    );
    wire unused_apb_addr_w;
    assign unused_apb_addr_w = |s_apb_paddr_w[15:12];
endmodule
