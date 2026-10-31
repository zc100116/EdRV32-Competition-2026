// File: edrv32_cpu_subsys.v
// Spec: edrv32-soc-spec 8.1-8.2; cpu-spec 3.1-3.3; cache-spec 3.
// Description: Connect the CPU core, instruction/data caches and APB cache control.
//              Expose independent AXI64 masters and the PLIC source 6 interrupt.
// Clock domain: clk_sys.
module edrv32_cpu_subsys #(
    parameter RVC_EN = 0
) (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // I$ AXI64 read master.
    output wire [3:0] iaxi_arid_o,
    output wire [31:0] iaxi_araddr_o,
    output wire [7:0] iaxi_arlen_o,
    output wire [2:0] iaxi_arsize_o,
    output wire [1:0] iaxi_arburst_o,
    output wire iaxi_arvalid_o,
    input wire iaxi_arready_i,
    input wire [3:0] iaxi_rid_i,
    input wire [63:0] iaxi_rdata_i,
    input wire [1:0] iaxi_rresp_i,
    input wire iaxi_rlast_i,
    input wire iaxi_rvalid_i,
    output wire iaxi_rready_o,

    // D$ AXI64 read/write master.
    output wire [3:0] daxi_awid_o,
    output wire [31:0] daxi_awaddr_o,
    output wire [7:0] daxi_awlen_o,
    output wire [2:0] daxi_awsize_o,
    output wire [1:0] daxi_awburst_o,
    output wire daxi_awvalid_o,
    input wire daxi_awready_i,
    output wire [63:0] daxi_wdata_o,
    output wire [7:0] daxi_wstrb_o,
    output wire daxi_wlast_o,
    output wire daxi_wvalid_o,
    input wire daxi_wready_i,
    input wire [3:0] daxi_bid_i,
    input wire [1:0] daxi_bresp_i,
    input wire daxi_bvalid_i,
    output wire daxi_bready_o,
    output wire [3:0] daxi_arid_o,
    output wire [31:0] daxi_araddr_o,
    output wire [7:0] daxi_arlen_o,
    output wire [2:0] daxi_arsize_o,
    output wire [1:0] daxi_arburst_o,
    output wire daxi_arvalid_o,
    input wire daxi_arready_i,
    input wire [3:0] daxi_rid_i,
    input wire [63:0] daxi_rdata_i,
    input wire [1:0] daxi_rresp_i,
    input wire daxi_rlast_i,
    input wire daxi_rvalid_i,
    output wire daxi_rready_o,

    // APB cache control slave.
    input wire [11:0] apb_paddr_i,
    input wire apb_psel_i,
    input wire apb_penable_i,
    input wire apb_pwrite_i,
    input wire [31:0] apb_pwdata_i,
    input wire [3:0] apb_pstrb_i,
    output wire apb_pready_o,
    output wire [31:0] apb_prdata_o,
    output wire apb_pslverr_o,

    // Interrupts and debug.
    input wire irq_meip_i,
    input wire irq_msip_i,
    input wire irq_mtip_i,
    input wire [63:0] mtime_i,
    output wire [63:0] debug_o,
    output wire irq_o
);

    // SoC 5.3: one preserved reset copy per destination region.
    wire rst_sys_core_n_w;
    wire rst_sys_direction0_n_w;
    wire rst_sys_direction1_n_w;
    wire rst_sys_csr_n_w;
    wire rst_sys_icache_n_w;
    wire rst_sys_ivalid0_n_w;
    wire rst_sys_ivalid1_n_w;
    wire rst_sys_ilru_n_w;
    wire rst_sys_dcache_n_w;
    wire rst_sys_cache_ctrl_n_w;
    edrv32_reset_copy u_reset_sys_core_n (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .rst_n_o(rst_sys_core_n_w)
    );
    edrv32_reset_copy u_reset_sys_direction0_n (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .rst_n_o(rst_sys_direction0_n_w)
    );
    edrv32_reset_copy u_reset_sys_direction1_n (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .rst_n_o(rst_sys_direction1_n_w)
    );
    edrv32_reset_copy u_reset_sys_csr_n (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .rst_n_o(rst_sys_csr_n_w)
    );
    edrv32_reset_copy u_reset_sys_icache_n (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .rst_n_o(rst_sys_icache_n_w)
    );
    edrv32_reset_copy u_reset_sys_ivalid0_n (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .rst_n_o(rst_sys_ivalid0_n_w)
    );
    edrv32_reset_copy u_reset_sys_ivalid1_n (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .rst_n_o(rst_sys_ivalid1_n_w)
    );
    edrv32_reset_copy u_reset_sys_ilru_n (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .rst_n_o(rst_sys_ilru_n_w)
    );
    edrv32_reset_copy u_reset_sys_dcache_n (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .rst_n_o(rst_sys_dcache_n_w)
    );
    edrv32_reset_copy u_reset_sys_cache_ctrl_n (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .rst_n_o(rst_sys_cache_ctrl_n_w)
    );

    wire ic_req_valid_w;
    wire [31:0] ic_req_addr_w;
    wire ic_req_ready_w;
    wire ic_resp_valid_w;
    wire [63:0] ic_resp_data_w;
    wire ic_resp_err_w;
    wire ic_kill_w;
    wire ic_inv_w;
    wire ic_inv_done_w;
    wire dc_req_valid_w;
    wire [31:0] dc_req_addr_w;
    wire dc_req_store_w;
    wire [1:0] dc_req_size_w;
    wire dc_req_ready_w;
    wire dc_resp_valid_w;
    wire [31:0] dc_resp_data_w;
    wire dc_resp_err_w;
    wire dc_resp_device_w;
    wire dc_kill_w;
    wire dc_commit_w;
    wire [31:0] dc_store_data_w;
    wire dc_fence_w;
    wire dc_clean_all_w;
    wire dc_fence_done_w;
    wire dc_wb_event_w;
    wire maint_req_valid_w;
    wire maint_req_ready_w;
    wire [2:0] maint_cmd_w;
    wire [31:0] maint_addr_w;
    wire [31:0] maint_size_w;
    wire maint_busy_w;
    wire wb_err_w;
    wire [31:0] wb_err_addr_w;

    // core interface connections.
    edrv32_cpu_core #(
        .RVC_EN(RVC_EN)
    ) u_core (
        // Clock.
        .clk_i(clk_i),

        // Reset.
        .rst_n_i(rst_sys_core_n_w),
        .rst_sys_direction0_n_i(rst_sys_direction0_n_w),
        .rst_sys_direction1_n_i(rst_sys_direction1_n_w),
        .rst_sys_csr_n_i(rst_sys_csr_n_w),


        // Core instruction interface.
        .ic_req_valid_o(ic_req_valid_w),
        .ic_req_addr_o(ic_req_addr_w),
        .ic_req_ready_i(ic_req_ready_w),
        .ic_resp_valid_i(ic_resp_valid_w),
        .ic_resp_data_i(ic_resp_data_w),
        .ic_resp_err_i(ic_resp_err_w),
        .ic_kill_o(ic_kill_w),
        .ic_inv_o(ic_inv_w),
        .ic_inv_done_i(ic_inv_done_w),

        // Core data interface.
        .dc_req_valid_o(dc_req_valid_w),
        .dc_req_addr_o(dc_req_addr_w),
        .dc_req_store_o(dc_req_store_w),
        .dc_req_size_o(dc_req_size_w),
        .dc_req_ready_i(dc_req_ready_w),
        .dc_resp_valid_i(dc_resp_valid_w),
        .dc_resp_data_i(dc_resp_data_w),
        .dc_resp_err_i(dc_resp_err_w),
        .dc_resp_device_i(dc_resp_device_w),
        .dc_kill_o(dc_kill_w),
        .dc_commit_o(dc_commit_w),
        .dc_store_data_o(dc_store_data_w),
        .dc_fence_o(dc_fence_w),
        .dc_clean_all_o(dc_clean_all_w),
        .dc_fence_done_i(dc_fence_done_w),
        .dc_wb_event_i(dc_wb_event_w),

        // Interrupts.
        .irq_meip_i(irq_meip_i),
        .irq_msip_i(irq_msip_i),
        .irq_mtip_i(irq_mtip_i),

        // CLINT time.
        .mtime_i(mtime_i),

        // Debug observation.
        .debug_o(debug_o)
    );

    // icache interface connections.
    edrv32_icache u_icache (
        // Clock.
        .clk_i(clk_i),

        // Reset.
        .rst_n_i(rst_sys_icache_n_w),
        .rst_sys_ivalid0_n_i(rst_sys_ivalid0_n_w),
        .rst_sys_ivalid1_n_i(rst_sys_ivalid1_n_w),
        .rst_sys_ilru_n_i(rst_sys_ilru_n_w),


        // Core instruction interface.
        .ic_req_valid_i(ic_req_valid_w),
        .ic_req_addr_i(ic_req_addr_w),
        .ic_req_ready_o(ic_req_ready_w),
        .ic_resp_valid_o(ic_resp_valid_w),
        .ic_resp_data_o(ic_resp_data_w),
        .ic_resp_err_o(ic_resp_err_w),
        .ic_kill_i(ic_kill_w),
        .ic_inv_i(ic_inv_w),
        .ic_inv_done_o(ic_inv_done_w),

        // AXI64 master.
        .axi_arid_o(iaxi_arid_o),
        .axi_araddr_o(iaxi_araddr_o),
        .axi_arlen_o(iaxi_arlen_o),
        .axi_arsize_o(iaxi_arsize_o),
        .axi_arburst_o(iaxi_arburst_o),
        .axi_arvalid_o(iaxi_arvalid_o),
        .axi_arready_i(iaxi_arready_i),
        .axi_rid_i(iaxi_rid_i),
        .axi_rdata_i(iaxi_rdata_i),
        .axi_rresp_i(iaxi_rresp_i),
        .axi_rlast_i(iaxi_rlast_i),
        .axi_rvalid_i(iaxi_rvalid_i),
        .axi_rready_o(iaxi_rready_o)
    );

    // dcache interface connections.
    edrv32_dcache u_dcache (
        // Clock.
        .clk_i(clk_i),

        // Reset.
        .rst_n_i(rst_sys_dcache_n_w),

        // Core data interface.
        .dc_req_valid_i(dc_req_valid_w),
        .dc_req_addr_i(dc_req_addr_w),
        .dc_req_store_i(dc_req_store_w),
        .dc_req_size_i(dc_req_size_w),
        .dc_req_ready_o(dc_req_ready_w),
        .dc_resp_valid_o(dc_resp_valid_w),
        .dc_resp_data_o(dc_resp_data_w),
        .dc_resp_err_o(dc_resp_err_w),
        .dc_resp_device_o(dc_resp_device_w),
        .dc_kill_i(dc_kill_w),
        .dc_commit_i(dc_commit_w),
        .dc_store_data_i(dc_store_data_w),
        .dc_fence_i(dc_fence_w),
        .dc_clean_all_i(dc_clean_all_w),
        .dc_fence_done_o(dc_fence_done_w),
        .dc_wb_event_o(dc_wb_event_w),

        // AXI64 master.
        .axi_awid_o(daxi_awid_o),
        .axi_awaddr_o(daxi_awaddr_o),
        .axi_awlen_o(daxi_awlen_o),
        .axi_awsize_o(daxi_awsize_o),
        .axi_awburst_o(daxi_awburst_o),
        .axi_awvalid_o(daxi_awvalid_o),
        .axi_awready_i(daxi_awready_i),
        .axi_wdata_o(daxi_wdata_o),
        .axi_wstrb_o(daxi_wstrb_o),
        .axi_wlast_o(daxi_wlast_o),
        .axi_wvalid_o(daxi_wvalid_o),
        .axi_wready_i(daxi_wready_i),
        .axi_bid_i(daxi_bid_i),
        .axi_bresp_i(daxi_bresp_i),
        .axi_bvalid_i(daxi_bvalid_i),
        .axi_bready_o(daxi_bready_o),
        .axi_arid_o(daxi_arid_o),
        .axi_araddr_o(daxi_araddr_o),
        .axi_arlen_o(daxi_arlen_o),
        .axi_arsize_o(daxi_arsize_o),
        .axi_arburst_o(daxi_arburst_o),
        .axi_arvalid_o(daxi_arvalid_o),
        .axi_arready_i(daxi_arready_i),
        .axi_rid_i(daxi_rid_i),
        .axi_rdata_i(daxi_rdata_i),
        .axi_rresp_i(daxi_rresp_i),
        .axi_rlast_i(daxi_rlast_i),
        .axi_rvalid_i(daxi_rvalid_i),
        .axi_rready_o(daxi_rready_o),

        // D$ maintenance.
        .maint_req_valid_i(maint_req_valid_w),
        .maint_req_ready_o(maint_req_ready_w),
        .maint_cmd_i(maint_cmd_w),
        .maint_addr_i(maint_addr_w),
        .maint_size_i(maint_size_w),
        .maint_busy_o(maint_busy_w),

        // Writeback errors.
        .wb_err_o(wb_err_w),
        .wb_err_addr_o(wb_err_addr_w)
    );

    // cache ctrl interface connections.
    edrv32_cache_ctrl u_cache_ctrl (
        // Clock.
        .clk_i(clk_i),

        // Reset.
        .rst_n_i(rst_sys_cache_ctrl_n_w),

        // APB slave.
        .apb_paddr_i(apb_paddr_i),
        .apb_psel_i(apb_psel_i),
        .apb_penable_i(apb_penable_i),
        .apb_pwrite_i(apb_pwrite_i),
        .apb_pwdata_i(apb_pwdata_i),
        .apb_pstrb_i(apb_pstrb_i),
        .apb_pready_o(apb_pready_o),
        .apb_prdata_o(apb_prdata_o),
        .apb_pslverr_o(apb_pslverr_o),

        // D$ maintenance.
        .maint_req_valid_o(maint_req_valid_w),
        .maint_req_ready_i(maint_req_ready_w),
        .maint_cmd_o(maint_cmd_w),
        .maint_addr_o(maint_addr_w),
        .maint_size_o(maint_size_w),
        .maint_busy_i(maint_busy_w),

        // Writeback errors.
        .wb_err_i(wb_err_w),
        .wb_err_addr_i(wb_err_addr_w),

        // Interrupts.
        .irq_o(irq_o)
    );
endmodule
