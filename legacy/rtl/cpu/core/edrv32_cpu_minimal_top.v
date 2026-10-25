// ============================================================================
// File        : edrv32_cpu_minimal_top.v
// Description : Pango CPU-only synthesis/STA top for the clean eight-stage
//               rewrite, including generated-RAM-backed I$ and D$.
// Notes       : Cache AXI channels remain top-level timing endpoints. Wide
//               retire/debug observation buses stay inside the hierarchy so
//               this measurement harness fits the target package I/O budget.
//               No interconnect, DDR controller, peripheral, TCM or PLL is
//               included.
// ============================================================================
`include "edrv32_axi4.vh"
`include "edrv32_bus.vh"

module edrv32_cpu_minimal_top #(
    parameter [31:0] RESET_PC = 32'h8000_0000,
    parameter integer ICACHE_LINE_COUNT = 256,
    parameter integer DCACHE_LINE_COUNT = 256,
    parameter integer MUL_USE_PANGO_APM = 1,
    // Preserve the original CPU-only PPA profile: the optional HPM bank is off.
    parameter integer CPU_HPM_ENABLE = 0,
    parameter [31:0] MVENDORID = 32'd0,
    parameter [31:0] MARCHID   = 32'd0,
    parameter [31:0] MIMPID    = 32'd0,
    parameter [31:0] MHARTID   = 32'd0
) (
    input  wire                         clk_i,
    input  wire                         rst_n_i,

    output wire [`AXI_ID_W-1:0]          icache_axi_arid_o,
    output wire [31:0]                   icache_axi_araddr_o,
    output wire [`AXI_LEN_W-1:0]         icache_axi_arlen_o,
    output wire [`AXI_SIZE_W-1:0]        icache_axi_arsize_o,
    output wire [`AXI_BURST_W-1:0]       icache_axi_arburst_o,
    output wire                          icache_axi_arvalid_o,
    input  wire                          icache_axi_arready_i,
    input  wire [`AXI_ID_W-1:0]          icache_axi_rid_i,
    input  wire [`AXI_DATA_W-1:0]        icache_axi_rdata_i,
    input  wire [`AXI_RESP_W-1:0]        icache_axi_rresp_i,
    input  wire                          icache_axi_rlast_i,
    input  wire                          icache_axi_rvalid_i,
    output wire                          icache_axi_rready_o,

    output wire [`AXI_ID_W-1:0]          dcache_axi_awid_o,
    output wire [31:0]                   dcache_axi_awaddr_o,
    output wire [`AXI_LEN_W-1:0]         dcache_axi_awlen_o,
    output wire [`AXI_SIZE_W-1:0]        dcache_axi_awsize_o,
    output wire [`AXI_BURST_W-1:0]       dcache_axi_awburst_o,
    output wire                          dcache_axi_awvalid_o,
    input  wire                          dcache_axi_awready_i,
    output wire [`AXI_DATA_W-1:0]        dcache_axi_wdata_o,
    output wire [`AXI_STRB_W-1:0]        dcache_axi_wstrb_o,
    output wire                          dcache_axi_wlast_o,
    output wire                          dcache_axi_wvalid_o,
    input  wire                          dcache_axi_wready_i,
    input  wire [`AXI_ID_W-1:0]          dcache_axi_bid_i,
    input  wire [`AXI_RESP_W-1:0]        dcache_axi_bresp_i,
    input  wire                          dcache_axi_bvalid_i,
    output wire                          dcache_axi_bready_o,
    output wire [`AXI_ID_W-1:0]          dcache_axi_arid_o,
    output wire [31:0]                   dcache_axi_araddr_o,
    output wire [`AXI_LEN_W-1:0]         dcache_axi_arlen_o,
    output wire [`AXI_SIZE_W-1:0]        dcache_axi_arsize_o,
    output wire [`AXI_BURST_W-1:0]       dcache_axi_arburst_o,
    output wire                          dcache_axi_arvalid_o,
    input  wire                          dcache_axi_arready_i,
    input  wire [`AXI_ID_W-1:0]          dcache_axi_rid_i,
    input  wire [`AXI_DATA_W-1:0]        dcache_axi_rdata_i,
    input  wire [`AXI_RESP_W-1:0]        dcache_axi_rresp_i,
    input  wire                          dcache_axi_rlast_i,
    input  wire                          dcache_axi_rvalid_i,
    output wire                          dcache_axi_rready_o,

    input  wire                         irq_soft_i,
    input  wire                         irq_timer_i,
    input  wire                         irq_ext_i,
    input  wire [63:0]                  time_value_i,

    output wire                         retire_o,
    output wire                         retire_exception_o,
    output wire                         core_sleep_o
);

    edrv32_cached_core #(
        .RESET_PC(RESET_PC),
        .ICACHE_LINE_COUNT(ICACHE_LINE_COUNT),
        .DCACHE_LINE_COUNT(DCACHE_LINE_COUNT),
        .MUL_USE_PANGO_APM(MUL_USE_PANGO_APM),
        .CPU_HPM_ENABLE(CPU_HPM_ENABLE),
        .TCM_ENABLE(0),
        .ITCM_BASE(32'd0),
        .ITCM_SIZE(32'd0),
        .DTCM_BASE(32'd0),
        .DTCM_SIZE(32'd0),
        .MVENDORID(MVENDORID),
        .MARCHID(MARCHID),
        .MIMPID(MIMPID),
        .MHARTID(MHARTID)
    ) u_cached_core (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),

        // External cache AXI masters.
        .icache_axi_arid_o(icache_axi_arid_o),
        .icache_axi_araddr_o(icache_axi_araddr_o),
        .icache_axi_arlen_o(icache_axi_arlen_o),
        .icache_axi_arsize_o(icache_axi_arsize_o),
        .icache_axi_arburst_o(icache_axi_arburst_o),
        .icache_axi_arvalid_o(icache_axi_arvalid_o),
        .icache_axi_arready_i(icache_axi_arready_i),
        .icache_axi_rid_i(icache_axi_rid_i),
        .icache_axi_rdata_i(icache_axi_rdata_i),
        .icache_axi_rresp_i(icache_axi_rresp_i),
        .icache_axi_rlast_i(icache_axi_rlast_i),
        .icache_axi_rvalid_i(icache_axi_rvalid_i),
        .icache_axi_rready_o(icache_axi_rready_o),
        .dcache_axi_awid_o(dcache_axi_awid_o),
        .dcache_axi_awaddr_o(dcache_axi_awaddr_o),
        .dcache_axi_awlen_o(dcache_axi_awlen_o),
        .dcache_axi_awsize_o(dcache_axi_awsize_o),
        .dcache_axi_awburst_o(dcache_axi_awburst_o),
        .dcache_axi_awvalid_o(dcache_axi_awvalid_o),
        .dcache_axi_awready_i(dcache_axi_awready_i),
        .dcache_axi_wdata_o(dcache_axi_wdata_o),
        .dcache_axi_wstrb_o(dcache_axi_wstrb_o),
        .dcache_axi_wlast_o(dcache_axi_wlast_o),
        .dcache_axi_wvalid_o(dcache_axi_wvalid_o),
        .dcache_axi_wready_i(dcache_axi_wready_i),
        .dcache_axi_bid_i(dcache_axi_bid_i),
        .dcache_axi_bresp_i(dcache_axi_bresp_i),
        .dcache_axi_bvalid_i(dcache_axi_bvalid_i),
        .dcache_axi_bready_o(dcache_axi_bready_o),
        .dcache_axi_arid_o(dcache_axi_arid_o),
        .dcache_axi_araddr_o(dcache_axi_araddr_o),
        .dcache_axi_arlen_o(dcache_axi_arlen_o),
        .dcache_axi_arsize_o(dcache_axi_arsize_o),
        .dcache_axi_arburst_o(dcache_axi_arburst_o),
        .dcache_axi_arvalid_o(dcache_axi_arvalid_o),
        .dcache_axi_arready_i(dcache_axi_arready_i),
        .dcache_axi_rid_i(dcache_axi_rid_i),
        .dcache_axi_rdata_i(dcache_axi_rdata_i),
        .dcache_axi_rresp_i(dcache_axi_rresp_i),
        .dcache_axi_rlast_i(dcache_axi_rlast_i),
        .dcache_axi_rvalid_i(dcache_axi_rvalid_i),
        .dcache_axi_rready_o(dcache_axi_rready_o),

        // This minimal wrapper does not provide local TCM memories.
        .itcm_req_valid_o(),
        .itcm_req_ready_i(1'b0),
        .itcm_req_addr_o(),
        .itcm_resp_valid_i(1'b0),
        .itcm_resp_ready_o(),
        .itcm_resp_rdata_i(32'd0),
        .itcm_resp_error_i(1'b0),
        .dtcm_req_valid_o(),
        .dtcm_req_ready_i(1'b0),
        .dtcm_req_addr_o(),
        .dtcm_req_we_o(),
        .dtcm_req_size_o(),
        .dtcm_req_wstrb_o(),
        .dtcm_req_wdata_o(),
        .dtcm_resp_valid_i(1'b0),
        .dtcm_resp_ready_o(),
        .dtcm_resp_rdata_i(32'd0),
        .dtcm_resp_error_i(1'b0),

        // Machine interrupt and time sources.
        .irq_soft_i(irq_soft_i),
        .irq_timer_i(irq_timer_i),
        .irq_ext_i(irq_ext_i),
        .time_value_i(time_value_i),

        // Retirement state; unused trace fields remain intentionally open.
        .retire_o(retire_o),
        .retire_pc_o(),
        .retire_instr_o(),
        .retire_exception_o(retire_exception_o),
        .retire_cause_o(),
        .core_sleep_o(core_sleep_o),
        .debug_decode_pc_o(),
        .debug_decode_instr_o()
    );

endmodule
