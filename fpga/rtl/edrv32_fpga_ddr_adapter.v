// File: edrv32_fpga_ddr_adapter.v
// Spec: mem-subsys-spec v0.1 Appendix A; edrv32-soc-spec v0.5 3.2, 4.2, 5.3.
// Description: Combinational SoC AXI256 to DDR3 IP user-port wiring and B synthesis.
//              IP addresses count 4-byte words: byte address [29:2] maps to [27:0].
// Clock domain: core_clk / clk_mem (125 MHz); no state or CDC.
// Address evidence: legacy/rtl/soc/ddr/edrv32_pango_ddr_axi_adapter.v:257, :156
// use [UI_ADDR_W+1:2]; legacy/sim/models/pango_ddr_ui_model.sv:7 explicitly
// describes 32-bit word addresses, and :185 advances a 256-bit beat by 8 words.
// Coordinator confirmation (M-R4): retain the 32-bit SoC address ports; upstream
// supplies physical addresses below 1 GiB, aligned to 32 bytes. No local checks.
// IP has no WVALID/WLAST. mem_xbar buffers each complete write before AW and
// supplies W continuously once AW is accepted, including the first WREADY cycle.
// WVALID/WLAST are therefore intentionally unused (lint waivers on those ports).
// Assume IP executes accepted reads/writes in order: after wusero_last, a newly
// issued read observes that write. This hardware assumption needs board/IP proof.
// BVALID follows wusero_last independently of WREADY; the IP owns pulse timing.
module edrv32_fpga_ddr_adapter (
    // SoC DDR master port.
    input wire [3:0] ddr_awid_i,
    /* verilator lint_off UNUSEDSIGNAL */
    input wire [31:0] ddr_awaddr_i,
    /* verilator lint_on UNUSEDSIGNAL */
    input wire [3:0] ddr_awlen_i,
    input wire ddr_awvalid_i,
    output wire ddr_awready_o,
    input wire [255:0] ddr_wdata_i,
    input wire [31:0] ddr_wstrb_i,
    /* verilator lint_off UNUSEDSIGNAL */
    input wire ddr_wlast_i,
    /* verilator lint_on UNUSEDSIGNAL */
    /* verilator lint_off UNUSEDSIGNAL */
    input wire ddr_wvalid_i,
    /* verilator lint_on UNUSEDSIGNAL */
    output wire ddr_wready_o,
    output wire [3:0] ddr_bid_o,
    output wire [1:0] ddr_bresp_o,
    output wire ddr_bvalid_o,
    input wire [3:0] ddr_arid_i,
    /* verilator lint_off UNUSEDSIGNAL */
    input wire [31:0] ddr_araddr_i,
    /* verilator lint_on UNUSEDSIGNAL */
    input wire [3:0] ddr_arlen_i,
    input wire ddr_arvalid_i,
    output wire ddr_arready_o,
    output wire [3:0] ddr_rid_o,
    output wire [255:0] ddr_rdata_o,
    output wire [1:0] ddr_rresp_o,
    output wire ddr_rlast_o,
    output wire ddr_rvalid_o,

    // DDR3 IP user port (template stems preserved).
    output wire [27:0] axi_awaddr_o,
    output wire axi_awuser_ap_o,
    output wire [3:0] axi_awuser_id_o,
    output wire [3:0] axi_awlen_o,
    output wire axi_awvalid_o,
    input wire axi_awready_i,
    output wire [255:0] axi_wdata_o,
    output wire [31:0] axi_wstrb_o,
    input wire axi_wready_i,
    input wire [3:0] axi_wusero_id_i,
    input wire axi_wusero_last_i,
    output wire [27:0] axi_araddr_o,
    output wire axi_aruser_ap_o,
    output wire [3:0] axi_aruser_id_o,
    output wire [3:0] axi_arlen_o,
    output wire axi_arvalid_o,
    input wire axi_arready_i,
    input wire [3:0] axi_rid_i,
    input wire [255:0] axi_rdata_i,
    input wire axi_rlast_i,
    input wire axi_rvalid_i,

    // Initialization status; SoC reset_ctrl owns reset sequencing.
    input wire ddr_init_done_i,
    output wire mem_ready_o
);

    assign axi_awaddr_o = ddr_awaddr_i[29:2];
    assign axi_awuser_ap_o = 1'b0;
    assign axi_awuser_id_o = ddr_awid_i;
    assign axi_awlen_o = ddr_awlen_i;
    assign axi_awvalid_o = ddr_awvalid_i;
    assign ddr_awready_o = axi_awready_i;
    assign axi_wdata_o = ddr_wdata_i;
    assign axi_wstrb_o = ddr_wstrb_i;
    assign ddr_wready_o = axi_wready_i;
    assign ddr_bid_o = axi_wusero_id_i;
    assign ddr_bresp_o = 2'b00;
    assign ddr_bvalid_o = axi_wusero_last_i;
    assign axi_araddr_o = ddr_araddr_i[29:2];
    assign axi_aruser_ap_o = 1'b0;
    assign axi_aruser_id_o = ddr_arid_i;
    assign axi_arlen_o = ddr_arlen_i;
    assign axi_arvalid_o = ddr_arvalid_i;
    assign ddr_arready_o = axi_arready_i;
    assign ddr_rid_o = axi_rid_i;
    assign ddr_rdata_o = axi_rdata_i;
    assign ddr_rresp_o = 2'b00;
    assign ddr_rlast_o = axi_rlast_i;
    assign ddr_rvalid_o = axi_rvalid_i;
    assign mem_ready_o = ddr_init_done_i;

endmodule
