// File: ip_ddr3.sv
// Spec: fpga/ip/ip_ddr3.md; edrv32-soc-spec 3.2, 5.3; Task B3-6.
// Description: Board IP shell around the existing DDR user-port behavioral model.
//              PHY and diagnostic pins are idle; no physical DDR signaling is checked.
// Clock domain: 125 MHz reference and core_clk.
module ip_ddr3 (
    input wire ref_clk,
    input wire resetn,
    output wire core_clk,
    output wire pll_lock,
    output wire phy_pll_lock,
    output wire gpll_lock,
    output wire rst_gpll_lock,
    output wire ddrphy_cpd_lock,
    output wire ddr_init_done,
    input wire [27:0] axi_awaddr,
    input wire axi_awuser_ap,
    input wire [3:0] axi_awuser_id,
    input wire [3:0] axi_awlen,
    output wire axi_awready,
    input wire axi_awvalid,
    input wire [255:0] axi_wdata,
    input wire [31:0] axi_wstrb,
    output wire axi_wready,
    output wire [3:0] axi_wusero_id,
    output wire axi_wusero_last,
    input wire [27:0] axi_araddr,
    input wire axi_aruser_ap,
    input wire [3:0] axi_aruser_id,
    input wire [3:0] axi_arlen,
    output wire axi_arready,
    input wire axi_arvalid,
    output wire [255:0] axi_rdata,
    output wire [3:0] axi_rid,
    output wire axi_rlast,
    output wire axi_rvalid,
    input wire apb_clk,
    input wire apb_rst_n,
    input wire apb_sel,
    input wire apb_enable,
    input wire [7:0] apb_addr,
    input wire apb_write,
    output wire apb_ready,
    input wire [15:0] apb_wdata,
    output wire [15:0] apb_rdata,
    output wire mem_cs_n,
    output wire mem_rst_n,
    output wire mem_ck,
    output wire mem_ck_n,
    output wire mem_cke,
    output wire mem_ras_n,
    output wire mem_cas_n,
    output wire mem_we_n,
    output wire mem_odt,
    output wire [14:0] mem_a,
    output wire [2:0] mem_ba,
    inout wire [3:0] mem_dqs,
    inout wire [3:0] mem_dqs_n,
    inout wire [31:0] mem_dq,
    output wire [3:0] mem_dm,
    input wire dbg_gate_start,
    input wire dbg_cpd_start,
    input wire dbg_ddrphy_rst_n,
    input wire dbg_gpll_scan_rst,
    input wire samp_position_dyn_adj,
    input wire [31:0] init_samp_position_even,
    input wire [31:0] init_samp_position_odd,
    input wire wrcal_position_dyn_adj,
    input wire [31:0] init_wrcal_position,
    input wire force_read_clk_ctrl,
    input wire [15:0] init_slip_step,
    input wire [11:0] init_read_clk_ctrl,
    output wire [33:0] debug_calib_ctrl,
    output wire [67:0] dbg_slice_status,
    output wire [87:0] dbg_slice_state,
    output wire [275:0] debug_data,
    output wire [1:0] dbg_dll_upd_state,
    output wire [8:0] debug_gpll_dps_phase,
    output wire [2:0] dbg_rst_dps_state,
    output wire [5:0] dbg_tran_err_rst_cnt,
    output wire dbg_ddrphy_init_fail,
    input wire debug_cpd_offset_adj,
    input wire debug_cpd_offset_dir,
    input wire [9:0] debug_cpd_offset,
    output wire [9:0] debug_dps_cnt_dir0,
    output wire [9:0] debug_dps_cnt_dir1,
    input wire ck_dly_en,
    input wire [7:0] init_ck_dly_step,
    output wire [7:0] ck_dly_set_bin,
    output wire align_error,
    output wire [3:0] debug_rst_state,
    output wire [3:0] debug_cpd_state
);
    timeunit 1ns;
    timeprecision 1ps;
    assign core_clk = ref_clk;
    showcase_ddr u_user (
        .core_clk_i(core_clk),
        .resetn_i(resetn),
        .ddr_init_done_o(ddr_init_done),
        .axi_awaddr_i(axi_awaddr),
        .axi_awuser_ap_i(axi_awuser_ap),
        .axi_awuser_id_i(axi_awuser_id),
        .axi_awlen_i(axi_awlen),
        .axi_awvalid_i(axi_awvalid),
        .axi_awready_o(axi_awready),
        .axi_wdata_i(axi_wdata),
        .axi_wstrb_i(axi_wstrb),
        .axi_wready_o(axi_wready),
        .axi_wusero_id_o(axi_wusero_id),
        .axi_wusero_last_o(axi_wusero_last),
        .axi_araddr_i(axi_araddr),
        .axi_aruser_ap_i(axi_aruser_ap),
        .axi_aruser_id_i(axi_aruser_id),
        .axi_arlen_i(axi_arlen),
        .axi_arvalid_i(axi_arvalid),
        .axi_arready_o(axi_arready),
        .axi_rid_o(axi_rid),
        .axi_rdata_o(axi_rdata),
        .axi_rlast_o(axi_rlast),
        .axi_rvalid_o(axi_rvalid)
    );
    assign pll_lock = '0;
    assign phy_pll_lock = '0;
    assign gpll_lock = '0;
    assign rst_gpll_lock = '0;
    assign ddrphy_cpd_lock = '0;
    assign apb_ready = '0;
    assign apb_rdata = '0;
    assign mem_cs_n = 1'b1;
    assign mem_rst_n = resetn;
    assign mem_ck = ref_clk;
    assign mem_ck_n = ~ref_clk;
    assign mem_cke = '0;
    assign mem_ras_n = 1'b1;
    assign mem_cas_n = 1'b1;
    assign mem_we_n = 1'b1;
    assign mem_odt = '0;
    assign mem_a = '0;
    assign mem_ba = '0;
    assign mem_dqs = 'z;
    assign mem_dqs_n = 'z;
    assign mem_dq = 'z;
    assign mem_dm = '0;
    assign debug_calib_ctrl = '0;
    assign dbg_slice_status = '0;
    assign dbg_slice_state = '0;
    assign debug_data = '0;
    assign dbg_dll_upd_state = '0;
    assign debug_gpll_dps_phase = '0;
    assign dbg_rst_dps_state = '0;
    assign dbg_tran_err_rst_cnt = '0;
    assign dbg_ddrphy_init_fail = '0;
    assign debug_dps_cnt_dir0 = '0;
    assign debug_dps_cnt_dir1 = '0;
    assign ck_dly_set_bin = '0;
    assign align_error = '0;
    assign debug_rst_state = '0;
    assign debug_cpd_state = '0;
    wire unused_diagnostics = &{1'b0, apb_clk, apb_rst_n, apb_sel, apb_enable, apb_addr,
        apb_write, apb_wdata, dbg_gate_start, dbg_cpd_start, dbg_ddrphy_rst_n,
        dbg_gpll_scan_rst, samp_position_dyn_adj, init_samp_position_even,
        init_samp_position_odd, wrcal_position_dyn_adj, init_wrcal_position,
        force_read_clk_ctrl, init_slip_step, init_read_clk_ctrl, debug_cpd_offset_adj,
        debug_cpd_offset_dir, debug_cpd_offset, ck_dly_en, init_ck_dly_step};
endmodule
