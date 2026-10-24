// ============================================================================
// File        : pango_ddr200h_model.sv
// Description : Simulation-only shell around the generated Pango DDR IP and
//               two Micron x16 DDR3 component models.
// Notes       : The shell exposes only the generated controller UI.  It keeps
//               the physical-memory wiring in one place for all DDR cases.
// ============================================================================

`timescale 1ps/1ps

module pango_ddr200h_model (
    input  wire          ref_clk_i,
    input  wire          resetn_i,

    output wire          core_clk_o,
    output wire          init_done_o,
    output wire          init_error_o,

    input  wire [27:0]   ui_awaddr_i,
    input  wire [3:0]    ui_awid_i,
    input  wire [3:0]    ui_awlen_i,
    input  wire          ui_awvalid_i,
    output wire          ui_awready_o,
    input  wire [255:0]  ui_wdata_i,
    input  wire [31:0]   ui_wstrb_i,
    output wire          ui_wready_o,
    output wire [3:0]    ui_wid_o,
    output wire          ui_wlast_o,

    input  wire [27:0]   ui_araddr_i,
    input  wire [3:0]    ui_arid_i,
    input  wire [3:0]    ui_arlen_i,
    input  wire          ui_arvalid_i,
    output wire          ui_arready_o,
    output wire [255:0]  ui_rdata_o,
    output wire [3:0]    ui_rid_o,
    output wire          ui_rlast_o,
    output wire          ui_rvalid_o
);

    localparam integer MEM_ROW_W = 15;
    localparam integer MEM_BANK_W = 3;
    localparam integer MEM_DQ_W = 32;
    localparam integer MEM_DQS_W = 4;
    localparam integer CTRL_ADDR_W = 28;
    localparam integer MODEL_ADDR_W = 15;

    wire mem_cs_n_w;
    wire mem_rst_n_w;
    wire mem_ck_w;
    wire mem_ck_n_w;
    wire mem_cke_w;
    wire mem_ras_n_w;
    wire mem_cas_n_w;
    wire mem_we_n_w;
    wire mem_odt_w;
    wire [MEM_ROW_W-1:0] mem_a_w;
    wire [MEM_BANK_W-1:0] mem_ba_w;
    wire [MEM_DQS_W-1:0] mem_dqs_w;
    wire [MEM_DQS_W-1:0] mem_dqs_n_w;
    wire [MEM_DQ_W-1:0] mem_dq_w;
    wire [MEM_DQS_W-1:0] mem_dm_w;

    wire [MODEL_ADDR_W-1:0] model_addr_w = mem_a_w;
    wire [1:0] model_rst_n_w;
    wire [1:0] model_ck_w;
    wire [1:0] model_ck_n_w;
    wire [1:0] model_cke_w;
    wire [1:0] model_cs_n_w;
    wire [1:0] model_ras_n_w;
    wire [1:0] model_cas_n_w;
    wire [1:0] model_we_n_w;
    wire [1:0] model_odt_w;
    wire [2*MEM_BANK_W-1:0] model_ba_w;
    wire [2*MODEL_ADDR_W-1:0] model_a_w;

    wire [33:0] unused_debug_calib_w;
    wire [67:0] unused_slice_status_w;
    wire [87:0] unused_slice_state_w;
    wire [275:0] unused_debug_data_w;
    wire [1:0] unused_dll_state_w;
    wire [8:0] unused_gpll_phase_w;
    wire [2:0] unused_rst_dps_state_w;
    wire [5:0] unused_tran_err_count_w;
    wire unused_init_fail_w;
    wire [9:0] unused_dps_dir0_w;
    wire [9:0] unused_dps_dir1_w;
    wire [7:0] unused_ck_delay_w;
    wire unused_align_error_w;
    wire [3:0] unused_reset_state_w;
    wire [3:0] unused_cpd_state_w;

    assign init_error_o = unused_init_fail_w | unused_align_error_w;

    ddr #(
        .MEM_ROW_WIDTH   (MEM_ROW_W),
        .MEM_COLUMN_WIDTH(10),
        .MEM_BANK_WIDTH  (MEM_BANK_W),
        .MEM_DQ_WIDTH    (MEM_DQ_W),
        .MEM_DM_WIDTH    (MEM_DQS_W),
        .MEM_DQS_WIDTH   (MEM_DQS_W),
        .CTRL_ADDR_WIDTH (CTRL_ADDR_W)
    ) u_ddr (
        .ref_clk                 (ref_clk_i),
        .resetn                  (resetn_i),
        .core_clk                (core_clk_o),
        .pll_lock                (),
        .phy_pll_lock            (),
        .gpll_lock               (),
        .rst_gpll_lock           (),
        .ddrphy_cpd_lock         (),
        .ddr_init_done           (init_done_o),

        .axi_awaddr              (ui_awaddr_i),
        .axi_awuser_ap           (1'b0),
        .axi_awuser_id           (ui_awid_i),
        .axi_awlen               (ui_awlen_i),
        .axi_awready             (ui_awready_o),
        .axi_awvalid             (ui_awvalid_i),
        .axi_wdata               (ui_wdata_i),
        .axi_wstrb               (ui_wstrb_i),
        .axi_wready              (ui_wready_o),
        .axi_wusero_id           (ui_wid_o),
        .axi_wusero_last         (ui_wlast_o),
        .axi_araddr              (ui_araddr_i),
        .axi_aruser_ap           (1'b0),
        .axi_aruser_id           (ui_arid_i),
        .axi_arlen               (ui_arlen_i),
        .axi_arready             (ui_arready_o),
        .axi_arvalid             (ui_arvalid_i),
        .axi_rdata               (ui_rdata_o),
        .axi_rid                 (ui_rid_o),
        .axi_rlast               (ui_rlast_o),
        .axi_rvalid              (ui_rvalid_o),

        .apb_clk                 (1'b0),
        .apb_rst_n               (1'b0),
        .apb_sel                 (1'b0),
        .apb_enable              (1'b0),
        .apb_addr                (8'b0),
        .apb_write               (1'b0),
        .apb_ready               (),
        .apb_wdata               (16'b0),
        .apb_rdata               (),

        .mem_cs_n                (mem_cs_n_w),
        .mem_rst_n               (mem_rst_n_w),
        .mem_ck                  (mem_ck_w),
        .mem_ck_n                (mem_ck_n_w),
        .mem_cke                 (mem_cke_w),
        .mem_ras_n               (mem_ras_n_w),
        .mem_cas_n               (mem_cas_n_w),
        .mem_we_n                (mem_we_n_w),
        .mem_odt                 (mem_odt_w),
        .mem_a                   (mem_a_w),
        .mem_ba                  (mem_ba_w),
        .mem_dqs                 (mem_dqs_w),
        .mem_dqs_n               (mem_dqs_n_w),
        .mem_dq                  (mem_dq_w),
        .mem_dm                  (mem_dm_w),

        .dbg_gate_start          (1'b0),
        .dbg_cpd_start           (1'b0),
        .dbg_ddrphy_rst_n        (1'b1),
        .dbg_gpll_scan_rst       (1'b0),
        .samp_position_dyn_adj   (1'b0),
        .init_samp_position_even (32'b0),
        .init_samp_position_odd  (32'b0),
        .wrcal_position_dyn_adj  (1'b0),
        .init_wrcal_position     (32'b0),
        .force_read_clk_ctrl     (1'b0),
        .init_slip_step          (16'b0),
        .init_read_clk_ctrl      (12'b0),
        .debug_calib_ctrl        (unused_debug_calib_w),
        .dbg_slice_status        (unused_slice_status_w),
        .dbg_slice_state         (unused_slice_state_w),
        .debug_data              (unused_debug_data_w),
        .dbg_dll_upd_state       (unused_dll_state_w),
        .debug_gpll_dps_phase    (unused_gpll_phase_w),
        .dbg_rst_dps_state       (unused_rst_dps_state_w),
        .dbg_tran_err_rst_cnt    (unused_tran_err_count_w),
        .dbg_ddrphy_init_fail    (unused_init_fail_w),
        .debug_cpd_offset_adj    (1'b0),
        .debug_cpd_offset_dir    (1'b0),
        .debug_cpd_offset        (10'b0),
        .debug_dps_cnt_dir0      (unused_dps_dir0_w),
        .debug_dps_cnt_dir1      (unused_dps_dir1_w),
        .ck_dly_en               (1'b1),
        .init_ck_dly_step        (8'b0),
        .ck_dly_set_bin          (unused_ck_delay_w),
        .align_error             (unused_align_error_w),
        .debug_rst_state         (unused_reset_state_w),
        .debug_cpd_state         (unused_cpd_state_w)
    );

    // The official bench applies a small command/address skew between the two
    // x16 components.  Keep that topology but use scalar connections so the
    // component-model ports are width-clean.
    assign #150 model_rst_n_w[0] = mem_rst_n_w;
    assign #150 model_ck_w[0] = mem_ck_w;
    assign #150 model_ck_n_w[0] = mem_ck_n_w;
    assign #150 model_cke_w[0] = mem_cke_w;
    assign #150 model_cs_n_w[0] = mem_cs_n_w;
    assign #150 model_ras_n_w[0] = mem_ras_n_w;
    assign #150 model_cas_n_w[0] = mem_cas_n_w;
    assign #150 model_we_n_w[0] = mem_we_n_w;
    assign #150 model_odt_w[0] = mem_odt_w;
    assign #150 model_ba_w[0 +: MEM_BANK_W] = mem_ba_w;
    assign #150 model_a_w[0 +: MODEL_ADDR_W] = model_addr_w;

    assign #50 model_rst_n_w[1] = model_rst_n_w[0];
    assign #50 model_ck_w[1] = model_ck_w[0];
    assign #50 model_ck_n_w[1] = model_ck_n_w[0];
    assign #50 model_cke_w[1] = model_cke_w[0];
    assign #50 model_cs_n_w[1] = model_cs_n_w[0];
    assign #50 model_ras_n_w[1] = model_ras_n_w[0];
    assign #50 model_cas_n_w[1] = model_cas_n_w[0];
    assign #50 model_we_n_w[1] = model_we_n_w[0];
    assign #50 model_odt_w[1] = model_odt_w[0];
    assign #50 model_ba_w[MEM_BANK_W +: MEM_BANK_W] =
        model_ba_w[0 +: MEM_BANK_W];
    assign #50 model_a_w[MODEL_ADDR_W +: MODEL_ADDR_W] =
        model_a_w[0 +: MODEL_ADDR_W];

    genvar model_i;
    generate
        for (model_i = 0; model_i < 2; model_i = model_i + 1) begin : gen_mem
            ddr3 #(
                .DEBUG(0),
                .check_strict_timing(0)
            ) u_mem (
                .rst_n  (model_rst_n_w[model_i]),
                .ck     (model_ck_w[model_i]),
                .ck_n   (model_ck_n_w[model_i]),
                .cke    (model_cke_w[model_i]),
                .cs_n   (model_cs_n_w[model_i]),
                .ras_n  (model_ras_n_w[model_i]),
                .cas_n  (model_cas_n_w[model_i]),
                .we_n   (model_we_n_w[model_i]),
                .dm_tdqs(mem_dm_w[2*model_i +: 2]),
                .ba     (model_ba_w[MEM_BANK_W*model_i +: MEM_BANK_W]),
                .addr   (model_a_w[MODEL_ADDR_W*model_i +: MODEL_ADDR_W]),
                .dq     (mem_dq_w[16*model_i +: 16]),
                .dqs    (mem_dqs_w[2*model_i +: 2]),
                .dqs_n  (mem_dqs_n_w[2*model_i +: 2]),
                .tdqs_n (),
                .odt    (model_odt_w[model_i])
            );
        end
    endgenerate

endmodule
