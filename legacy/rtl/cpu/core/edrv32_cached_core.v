// ============================================================================
// File        : edrv32_cached_core.v
// Description : Eight-stage scalar core with blocking two-way I$/D$.
// Notes       : The core-facing lookup and COMMIT channels stay internal.
//               External ports are the caches' single-outstanding AXI4 master
//               interfaces; no native-to-AXI conversion layer is required.
// ============================================================================
`include "edrv32_axi4.vh"
`include "edrv32_bus.vh"
`include "edrv32_lsu.vh"
`include "edrv32_soc_map.vh"
`include "edrv32_pma.vh"

module edrv32_cached_core #(
    parameter [31:0] RESET_PC = 32'h8000_0000,
    parameter integer ICACHE_LINE_COUNT = 256,
    parameter integer DCACHE_LINE_COUNT = 256,
    parameter integer MUL_USE_PANGO_APM = 0,
    parameter integer CPU_HPM_ENABLE = 1,
    parameter integer FRONTEND_DUAL_WINDOW = 0,
    parameter integer DUAL_ISSUE = 1,
    parameter integer FETCH_WIDE = 1,
    parameter integer TCM_ENABLE  = 0,
    parameter integer ITCM_ENABLE = TCM_ENABLE,
    parameter integer DTCM_ENABLE = TCM_ENABLE,
    parameter [31:0] ITCM_BASE = `SOC_ITCM_BASE,
    parameter [31:0] ITCM_SIZE = `SOC_ITCM_SIZE,
    parameter [31:0] DTCM_BASE = `SOC_DTCM_BASE,
    parameter [31:0] DTCM_SIZE = `SOC_DTCM_SIZE,
    parameter [31:0] MVENDORID = 32'd0,
    parameter [31:0] MARCHID   = 32'd0,
    parameter [31:0] MIMPID    = 32'd0,
    parameter [31:0] MHARTID   = 32'd0
) (
    input  wire                         clk_i,
    input  wire                         rst_n_i,

    // Read-only AXI4 master owned by the instruction cache.
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

    // Read/write AXI4 master owned by the data cache.
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

    // Optional CPU-private TCM channels. They are physically absent from the
    // default profile but preserve the original configurable interface.
    output wire                         itcm_req_valid_o,
    input  wire                         itcm_req_ready_i,
    output wire [31:0]                  itcm_req_addr_o,
    input  wire                         itcm_resp_valid_i,
    output wire                         itcm_resp_ready_o,
    input  wire [31:0]                  itcm_resp_rdata_i,
    input  wire                         itcm_resp_error_i,

    output wire                         dtcm_req_valid_o,
    input  wire                         dtcm_req_ready_i,
    output wire [31:0]                  dtcm_req_addr_o,
    output wire                         dtcm_req_we_o,
    output wire [`BUS_SZ_W-1:0]         dtcm_req_size_o,
    output wire [3:0]                   dtcm_req_wstrb_o,
    output wire [31:0]                  dtcm_req_wdata_o,
    input  wire                         dtcm_resp_valid_i,
    output wire                         dtcm_resp_ready_o,
    input  wire [31:0]                  dtcm_resp_rdata_i,
    input  wire                         dtcm_resp_error_i,

    // Machine-mode interrupt/time inputs and architectural observations.
    input  wire                         irq_soft_i,
    input  wire                         irq_timer_i,
    input  wire                         irq_ext_i,
    input  wire [63:0]                  time_value_i,

    output wire                             second_retire_o,
    output wire [31:0]                      second_retire_pc_o,
    output wire [31:0]                      second_retire_instr_o,
    output wire [1:0]                       retire_count_o,
    output wire                         retire_o,
    output wire [31:0]                  retire_pc_o,
    output wire [31:0]                  retire_instr_o,
    output wire                         retire_exception_o,
    output wire [31:0]                  retire_cause_o,
    output wire                         core_sleep_o,
    output wire [31:0]                  debug_decode_pc_o,
    output wire [31:0]                  debug_decode_instr_o
);

    // ------------------------------------------------------------------------
    // Core-facing instruction channel and I-cache lookup response
    // ------------------------------------------------------------------------
    wire [31:0] icache_lookup_resp_upper_w;
    wire [31:0] icache_lookup_preview_upper_w;
    wire [1:0] core_imem_req_words_w;
    wire [31:0] core_imem_resp_upper_w;
    wire core_imem_req_valid_w;
    wire core_imem_req_ready_w;
    wire [31:0] core_imem_req_addr_w;
    wire core_imem_resp_valid_w;
    wire core_imem_resp_ready_w;
    wire [31:0] core_imem_resp_data_w;
    wire core_imem_resp_error_w;
    wire icache_lookup_resp_valid_w;
    wire icache_lookup_resp_ready_w;
    wire [31:0] icache_lookup_resp_data_w;
    wire icache_lookup_resp_error_w;
    wire icache_lookup_preview_valid_w;
    wire [31:0] icache_lookup_preview_addr_w;
    wire [31:0] icache_lookup_preview_data_w;
    reg imem_source_itcm_r;

    // Core-facing COMMIT data channel and D-cache commit response.
    wire core_dmem_req_valid_w;
    wire core_dmem_req_ready_w;
    wire [31:0] core_dmem_req_addr_w;
    wire core_dmem_req_write_w;
    wire [`BUS_SZ_W-1:0] core_dmem_req_size_w;
    wire [3:0] core_dmem_req_wstrb_w;
    wire [31:0] core_dmem_req_wdata_w;
    wire core_dmem_req_cacheable_w;
    wire core_dmem_resp_valid_w;
    wire core_dmem_resp_ready_w;
    wire [31:0] core_dmem_resp_data_w;
    wire core_dmem_resp_error_w;
    wire dcache_commit_req_ready_w;
    wire dcache_commit_resp_valid_w;
    wire dcache_commit_resp_ready_w;
    wire [31:0] dcache_commit_resp_data_w;
    wire dcache_commit_resp_error_w;

    // MEM2 side-effect-free D-cache lookup, ordering and maintenance channels.
    wire dcache_lookup_valid_w;
    wire dcache_lookup_ready_w;
    wire [31:0] dcache_lookup_addr_w;
    wire [`EDRV32_LSU_TOKEN_W-1:0] dcache_lookup_token_w;
    wire dcache_lookup_store_w;
    wire [`BUS_SZ_W-1:0] dcache_lookup_size_w;
    wire dcache_lookup_unsigned_w;
    wire dcache_lookup_resp_valid_w;
    wire dcache_lookup_resp_ready_w;
    wire [`EDRV32_LSU_TOKEN_W-1:0] dcache_lookup_resp_token_unused_w;
    wire dcache_lookup_resp_store_w;
    wire dcache_lookup_fast_valid_w;
    wire dcache_lookup_fast_ready_w;
    wire [`EDRV32_LSU_TOKEN_W-1:0] dcache_lookup_fast_token_w;
    wire dcache_lookup_fast_store_w;
    wire [31:0] dcache_lookup_fast_data_w;
    wire [31:0] dcache_lookup_resp_data_w;
    wire dcache_lookup_resp_error_w;
    wire dcache_lookup_cancel_w;
    wire [1:0] dcache_reservation_keep_count_w;
    wire fence_retire_w;
    wire fencei_retire_w;
    wire icache_lookup_req_ready_w;
    wire dcache_clean_busy_w;
    wire dcache_clean_done_w;
    wire icache_miss_w;
    wire icache_refill_busy_w;
    wire dcache_miss_w;
    wire dcache_writeback_w;
    wire dcache_refill_busy_w;
    wire cache_maint_request_ready_w;
    wire cache_maint_response_valid_w;
    wire cache_maint_response_ready_w;
    wire [31:0] cache_maint_response_data_w;
    wire cache_maint_response_error_w;
    wire cache_maint_dcache_invalidate_w;
    wire cache_maint_dcache_clean_w;
    wire cache_maint_dcache_clean_invalidate_w;
    wire [31:0] cache_maint_dcache_addr_w;
    wire [31:0] cache_maint_dcache_size_w;
    wire cache_maint_icache_invalidate_w;
    reg [1:0] dmem_source_r;
    reg dmem_source_valid_r;
    reg fence_maintenance_active_r;

    // ------------------------------------------------------------------------
    // Data-side route selection and response ownership
    // ------------------------------------------------------------------------
    localparam [31:0] CACHE_MAINT_BASE = `SOC_CACHE_MAINT_BASE;
    localparam [1:0] DMEM_SOURCE_DCACHE = 2'd0;
    localparam [1:0] DMEM_SOURCE_DTCM = 2'd1;
    localparam [1:0] DMEM_SOURCE_MAINT = 2'd2;

    wire core_dmem_is_cache_maint_w =
        (core_dmem_req_addr_w[31:5] == CACHE_MAINT_BASE[31:5]);
    wire core_dmem_is_dtcm_w;
    wire dmem_pma_mapped_unused_w;
    wire dmem_pma_permitted_unused_w;
    wire dmem_pma_fault_unused_w;
    wire dmem_pma_cacheable_unused_w;
    wire dmem_pma_device_unused_w;
    wire [`PMA_ATTR_WIDTH-1:0] dmem_pma_attributes_unused_w;
    // A single PMA decision selects D-cache, DTCM or the maintenance window.
    edrv32_pma_classifier #(
        .TCM_ENABLE (TCM_ENABLE),
        .ITCM_ENABLE(ITCM_ENABLE),
        .DTCM_ENABLE(DTCM_ENABLE)
    ) u_dmem_route_pma (
        // Access being classified.
        .address_i(core_dmem_req_addr_w),
        .instruction_i(1'b0),
        .load_i(!core_dmem_req_write_w),
        .store_i(core_dmem_req_write_w),

        // Region properties used by the data-side router.
        .mapped_o(dmem_pma_mapped_unused_w),
        .permitted_o(dmem_pma_permitted_unused_w),
        .access_fault_o(dmem_pma_fault_unused_w),
        .cacheable_o(dmem_pma_cacheable_unused_w),
        .tcm_o(core_dmem_is_dtcm_w),
        .device_o(dmem_pma_device_unused_w),
        .attributes_o(dmem_pma_attributes_unused_w)
    );
    wire [1:0] core_dmem_request_source_w = core_dmem_is_cache_maint_w
        ? DMEM_SOURCE_MAINT : core_dmem_is_dtcm_w
        ? DMEM_SOURCE_DTCM : DMEM_SOURCE_DCACHE;

    assign core_dmem_req_ready_w =
        (core_dmem_request_source_w == DMEM_SOURCE_MAINT)
            ? cache_maint_request_ready_w :
        (core_dmem_request_source_w == DMEM_SOURCE_DTCM)
            ? dtcm_req_ready_i : dcache_commit_req_ready_w;
    wire core_dmem_request_fire_w = core_dmem_req_valid_w &&
                                    core_dmem_req_ready_w;
    wire [1:0] dmem_response_source_w = dmem_source_valid_r
        ? dmem_source_r : core_dmem_request_source_w;
    wire dmem_response_source_valid_w = dmem_source_valid_r ||
                                        core_dmem_request_fire_w;

    assign core_dmem_resp_valid_w = dmem_response_source_valid_w &&
        ((dmem_response_source_w == DMEM_SOURCE_MAINT)
            ? cache_maint_response_valid_w :
         (dmem_response_source_w == DMEM_SOURCE_DTCM)
            ? dtcm_resp_valid_i : dcache_commit_resp_valid_w);
    assign core_dmem_resp_data_w =
        (dmem_response_source_w == DMEM_SOURCE_MAINT)
            ? cache_maint_response_data_w :
        (dmem_response_source_w == DMEM_SOURCE_DTCM)
            ? dtcm_resp_rdata_i : dcache_commit_resp_data_w;
    assign core_dmem_resp_error_w =
        (dmem_response_source_w == DMEM_SOURCE_MAINT)
            ? cache_maint_response_error_w :
        (dmem_response_source_w == DMEM_SOURCE_DTCM)
            ? dtcm_resp_error_i : dcache_commit_resp_error_w;
    wire core_dmem_response_fire_w = core_dmem_resp_valid_w &&
                                     core_dmem_resp_ready_w;
    assign cache_maint_response_ready_w = core_dmem_resp_ready_w &&
        dmem_response_source_valid_w &&
        (dmem_response_source_w == DMEM_SOURCE_MAINT);
    assign dtcm_resp_ready_o = core_dmem_resp_ready_w &&
        dmem_response_source_valid_w &&
        (dmem_response_source_w == DMEM_SOURCE_DTCM);
    assign dcache_commit_resp_ready_w = core_dmem_resp_ready_w &&
        dmem_response_source_valid_w &&
        (dmem_response_source_w == DMEM_SOURCE_DCACHE);

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            dmem_source_valid_r <= 1'b0;
            dmem_source_r <= DMEM_SOURCE_DCACHE;
        end else if (core_dmem_request_fire_w) begin
            dmem_source_r <= core_dmem_request_source_w;
            dmem_source_valid_r <= !core_dmem_response_fire_w;
        end else if (core_dmem_response_fire_w) begin
            dmem_source_valid_r <= 1'b0;
        end
    end

    assign dtcm_req_valid_o = core_dmem_req_valid_w && core_dmem_is_dtcm_w;
    assign dtcm_req_addr_o = core_dmem_req_addr_w;
    assign dtcm_req_we_o = core_dmem_req_write_w;
    assign dtcm_req_size_o = core_dmem_req_size_w;
    assign dtcm_req_wstrb_o = core_dmem_req_wstrb_w;
    assign dtcm_req_wdata_o = core_dmem_req_wdata_w;

    // ------------------------------------------------------------------------
    // Instruction-side route selection and FENCE ordering
    // ------------------------------------------------------------------------
    wire cache_ordering_retire_w = fence_retire_w || fencei_retire_w;
    wire frontend_memory_enabled_w = !fence_maintenance_active_r &&
                                     !cache_ordering_retire_w;
    wire core_imem_is_itcm_w;
    wire imem_request_cacheable_w;
    wire imem_request_executable_w;
    wire imem_pma_mapped_unused_w;
    wire imem_pma_fault_unused_w;
    wire imem_pma_device_unused_w;
    wire [`PMA_ATTR_WIDTH-1:0] imem_pma_attributes_unused_w;
    edrv32_pma_classifier #(
        .TCM_ENABLE (TCM_ENABLE),
        .ITCM_ENABLE(ITCM_ENABLE),
        .DTCM_ENABLE(DTCM_ENABLE)
    ) u_imem_pma (
        // Fetch address being classified.
        .address_i(core_imem_req_addr_w),
        .instruction_i(1'b1),
        .load_i(1'b0),
        .store_i(1'b0),

        // Region properties used by the instruction-side router.
        .mapped_o(imem_pma_mapped_unused_w),
        .permitted_o(imem_request_executable_w),
        .access_fault_o(imem_pma_fault_unused_w),
        .cacheable_o(imem_request_cacheable_w),
        .tcm_o(core_imem_is_itcm_w),
        .device_o(imem_pma_device_unused_w),
        .attributes_o(imem_pma_attributes_unused_w)
    );

    // Two adjacent words stay within one 16-byte line. ITCM and bypass paths
    // preserve their single-word contract; each accepted IF1 tag owns this stride.
    assign core_imem_req_words_w = (FETCH_WIDE != 0) && imem_request_cacheable_w &&
        imem_request_executable_w && !core_imem_is_itcm_w &&
        (core_imem_req_addr_w[3:2] != 2'd3) ? 2'd2 : 2'd1;
    assign core_imem_resp_upper_w = imem_source_itcm_r ? 32'd0 : icache_lookup_resp_upper_w;

    // FENCE and FENCE.I both make older dirty data visible before younger work
    // is refetched.  Only FENCE.I invalidates I$.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            fence_maintenance_active_r <= 1'b0;
        else if (cache_ordering_retire_w)
            fence_maintenance_active_r <= 1'b1;
        else if (fence_maintenance_active_r && !dcache_clean_busy_w)
            fence_maintenance_active_r <= 1'b0;
    end

    assign core_imem_req_ready_w = frontend_memory_enabled_w &&
        (core_imem_is_itcm_w ? itcm_req_ready_i :
                               icache_lookup_req_ready_w);
    assign itcm_req_valid_o = frontend_memory_enabled_w &&
                              core_imem_req_valid_w &&
                              core_imem_is_itcm_w;
    assign itcm_req_addr_o = core_imem_req_addr_w;
    wire core_imem_request_fire_w = core_imem_req_valid_w &&
                                    core_imem_req_ready_w;
    wire core_imem_response_fire_w = core_imem_resp_valid_w &&
                                     core_imem_resp_ready_w;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            imem_source_itcm_r <= 1'b0;
        else if (core_imem_request_fire_w)
            imem_source_itcm_r <= core_imem_is_itcm_w;
        else if (core_imem_response_fire_w)
            imem_source_itcm_r <= 1'b0;
    end

    assign core_imem_resp_valid_w = imem_source_itcm_r
        ? itcm_resp_valid_i : icache_lookup_resp_valid_w;
    assign core_imem_resp_data_w = imem_source_itcm_r
        ? itcm_resp_rdata_i : icache_lookup_resp_data_w;
    assign core_imem_resp_error_w = imem_source_itcm_r
        ? itcm_resp_error_i : icache_lookup_resp_error_w;
    assign itcm_resp_ready_o = core_imem_resp_ready_w && imem_source_itcm_r;
    assign icache_lookup_resp_ready_w = core_imem_resp_ready_w &&
                                        !imem_source_itcm_r;

    // ========================================================================
    // Scalar CPU and cache hierarchy
    // ========================================================================
    edrv32_core #(
        .RESET_PC(RESET_PC),
        .CACHE_ENABLE(1),
        .TCM_ENABLE (TCM_ENABLE),
        .ITCM_ENABLE(ITCM_ENABLE),
        .DTCM_ENABLE(DTCM_ENABLE),
        .MUL_USE_PANGO_APM(MUL_USE_PANGO_APM),
        .CPU_HPM_ENABLE(CPU_HPM_ENABLE),
        .FRONTEND_DUAL_WINDOW(FRONTEND_DUAL_WINDOW),
        .DUAL_ISSUE(DUAL_ISSUE),
        .FETCH_WIDE(FETCH_WIDE),
        .MVENDORID(MVENDORID),
        .MARCHID(MARCHID),
        .MIMPID(MIMPID),
        .MHARTID(MHARTID)
    ) u_core (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),

        // Instruction-memory channel seen by the scalar core.
        .imem_req_words_i(core_imem_req_words_w),
        .imem_resp_upper_i(core_imem_resp_upper_w),
        .imem_preview_upper_i(icache_lookup_preview_upper_w),
        .imem_req_valid_o(core_imem_req_valid_w),
        .imem_req_ready_i(core_imem_req_ready_w),
        .imem_req_addr_o(core_imem_req_addr_w),
        .imem_resp_valid_i(core_imem_resp_valid_w),
        .imem_resp_ready_o(core_imem_resp_ready_w),
        .imem_resp_rdata_i(core_imem_resp_data_w),
        .imem_resp_error_i(core_imem_resp_error_w),
        .imem_preview_valid_i(icache_lookup_preview_valid_w &&
                              !imem_source_itcm_r),
        .imem_preview_addr_i(icache_lookup_preview_addr_w),
        .imem_preview_data_i(icache_lookup_preview_data_w),

        // Precise data-memory channel owned by COMMIT.
        .dmem_req_valid_o(core_dmem_req_valid_w),
        .dmem_req_ready_i(core_dmem_req_ready_w),
        .dmem_req_addr_o(core_dmem_req_addr_w),
        .dmem_req_we_o(core_dmem_req_write_w),
        .dmem_req_size_o(core_dmem_req_size_w),
        .dmem_req_wstrb_o(core_dmem_req_wstrb_w),
        .dmem_req_wdata_o(core_dmem_req_wdata_w),
        .dmem_req_cacheable_o(core_dmem_req_cacheable_w),
        .dmem_resp_valid_i(core_dmem_resp_valid_w),
        .dmem_resp_ready_o(core_dmem_resp_ready_w),
        .dmem_resp_rdata_i(core_dmem_resp_data_w),
        .dmem_resp_error_i(core_dmem_resp_error_w),

        // Speculative load lookup owned by MEM2.
        .dcache_lookup_valid_o(dcache_lookup_valid_w),
        .dcache_lookup_ready_i(dcache_lookup_ready_w),
        .dcache_lookup_addr_o(dcache_lookup_addr_w),
        .dcache_lookup_token_o(dcache_lookup_token_w),
        .dcache_lookup_store_o(dcache_lookup_store_w),
        .dcache_lookup_size_o(dcache_lookup_size_w),
        .dcache_lookup_unsigned_o(dcache_lookup_unsigned_w),
        .dcache_lookup_resp_valid_i(dcache_lookup_resp_valid_w),
        .dcache_lookup_resp_ready_o(dcache_lookup_resp_ready_w),
        .dcache_lookup_resp_data_i(dcache_lookup_resp_data_w),
        .dcache_lookup_resp_error_i(dcache_lookup_resp_error_w),
        .dcache_lookup_resp_token_i(dcache_lookup_resp_token_unused_w),
        .dcache_lookup_resp_store_i(dcache_lookup_resp_store_w),
        .dcache_lookup_fast_valid_i(dcache_lookup_fast_valid_w),
        .dcache_lookup_fast_ready_o(dcache_lookup_fast_ready_w),
        .dcache_lookup_fast_token_i(dcache_lookup_fast_token_w),
        .dcache_lookup_fast_store_i(dcache_lookup_fast_store_w),
        .dcache_lookup_fast_data_i(dcache_lookup_fast_data_w),
        .dcache_lookup_cancel_o(dcache_lookup_cancel_w),
        .dcache_reservation_keep_count_o(
            dcache_reservation_keep_count_w),

        // Cache-generated performance events.
        .cache_perf_events_i({dcache_refill_busy_w,
                              icache_refill_busy_w,
                              dcache_writeback_w,
                              dcache_miss_w,
                              icache_miss_w}),

        // Machine interrupt and time sources.
        .irq_soft_i(irq_soft_i),
        .irq_timer_i(irq_timer_i),
        .irq_ext_i(irq_ext_i),
        .time_value_i(time_value_i),

        // Retirement, ordering and debug observation.
        .second_retire_o(second_retire_o),
        .second_retire_pc_o(second_retire_pc_o),
        .second_retire_instr_o(second_retire_instr_o),
        .retire_count_o(retire_count_o),
        .retire_o(retire_o),
        .retire_pc_o(retire_pc_o),
        .retire_instr_o(retire_instr_o),
        .retire_exception_o(retire_exception_o),
        .retire_cause_o(retire_cause_o),
        .fence_retire_o(fence_retire_w),
        .fencei_retire_o(fencei_retire_w),
        .core_sleep_o(core_sleep_o),
        .debug_decode_pc_o(debug_decode_pc_o),
        .debug_decode_instr_o(debug_decode_instr_o)
    );

    // Blocking two-way instruction cache.
    edrv32_icache #(
        .FETCH_WIDE(FETCH_WIDE),
        .LINE_COUNT(ICACHE_LINE_COUNT)
    ) u_icache (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),

        // Core lookup interface.
        .lookup_req_valid_i(core_imem_req_valid_w &&
                            frontend_memory_enabled_w &&
                            !core_imem_is_itcm_w),
        .lookup_req_ready_o(icache_lookup_req_ready_w),
        .lookup_req_addr_i(core_imem_req_addr_w),
        .lookup_req_cacheable_i(imem_request_cacheable_w),
        .lookup_req_executable_i(imem_request_executable_w),
        .lookup_resp_valid_o(icache_lookup_resp_valid_w),
        .lookup_resp_ready_i(icache_lookup_resp_ready_w),
        .lookup_resp_data_o(icache_lookup_resp_data_w),
        .lookup_resp_upper_o(icache_lookup_resp_upper_w),
        .lookup_resp_error_o(icache_lookup_resp_error_w),
        .lookup_preview_valid_o(icache_lookup_preview_valid_w),
        .lookup_preview_addr_o(icache_lookup_preview_addr_w),
        .lookup_preview_data_o(icache_lookup_preview_data_w),
        .lookup_preview_upper_o(icache_lookup_preview_upper_w),

        // Architectural and software-directed invalidation.
        .invalidate_i(fencei_retire_w || cache_maint_icache_invalidate_w),

        // Direct AXI refill/bypass traffic.
        .axi_arid_o(icache_axi_arid_o),
        .axi_araddr_o(icache_axi_araddr_o),
        .axi_arlen_o(icache_axi_arlen_o),
        .axi_arsize_o(icache_axi_arsize_o),
        .axi_arburst_o(icache_axi_arburst_o),
        .axi_arvalid_o(icache_axi_arvalid_o),
        .axi_arready_i(icache_axi_arready_i),
        .axi_rid_i(icache_axi_rid_i),
        .axi_rdata_i(icache_axi_rdata_i),
        .axi_rresp_i(icache_axi_rresp_i),
        .axi_rlast_i(icache_axi_rlast_i),
        .axi_rvalid_i(icache_axi_rvalid_i),
        .axi_rready_o(icache_axi_rready_o),

        // Performance-event observation.
        .miss_o(icache_miss_w),
        .refill_busy_o(icache_refill_busy_w)
    );

    // Blocking two-way write-back data cache.
    edrv32_dcache #(
        .LINE_COUNT(DCACHE_LINE_COUNT)
    ) u_dcache (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),

        // Speculative lookup interface from MEM2.
        .lookup_req_valid_i(dcache_lookup_valid_w),
        .lookup_req_ready_o(dcache_lookup_ready_w),
        .lookup_req_token_i(dcache_lookup_token_w),
        .lookup_req_addr_i(dcache_lookup_addr_w),
        .lookup_req_store_i(dcache_lookup_store_w),
        .lookup_req_size_i(dcache_lookup_size_w),
        .lookup_req_unsigned_i(dcache_lookup_unsigned_w),
        .lookup_resp_valid_o(dcache_lookup_resp_valid_w),
        .lookup_resp_ready_i(dcache_lookup_resp_ready_w),
        .lookup_resp_token_o(dcache_lookup_resp_token_unused_w),
        .lookup_resp_store_o(dcache_lookup_resp_store_w),
        .lookup_fast_valid_o(dcache_lookup_fast_valid_w),
        .lookup_fast_ready_i(dcache_lookup_fast_ready_w),
        .lookup_fast_token_o(dcache_lookup_fast_token_w),
        .lookup_fast_store_o(dcache_lookup_fast_store_w),
        .lookup_fast_data_o(dcache_lookup_fast_data_w),
        .lookup_resp_data_o(dcache_lookup_resp_data_w),
        .lookup_resp_error_o(dcache_lookup_resp_error_w),
        .lookup_cancel_i(dcache_lookup_cancel_w),
        .lookup_cancel_keep_count_i(dcache_reservation_keep_count_w),

        // Precise load/store interface from COMMIT.
        .commit_req_valid_i(core_dmem_req_valid_w &&
            (core_dmem_request_source_w == DMEM_SOURCE_DCACHE)),
        .commit_req_ready_o(dcache_commit_req_ready_w),
        .commit_req_addr_i(core_dmem_req_addr_w),
        .commit_req_write_i(core_dmem_req_write_w),
        .commit_req_size_i(core_dmem_req_size_w),
        .commit_req_wstrb_i(core_dmem_req_wstrb_w),
        .commit_req_wdata_i(core_dmem_req_wdata_w),
        .commit_req_cacheable_i(core_dmem_req_cacheable_w),
        .commit_resp_valid_o(dcache_commit_resp_valid_w),
        .commit_resp_ready_i(dcache_commit_resp_ready_w),
        .commit_resp_data_o(dcache_commit_resp_data_w),
        .commit_resp_error_o(dcache_commit_resp_error_w),

        // Whole-cache ordering operation used by FENCE/FENCE.I.
        .clean_all_i(cache_ordering_retire_w),
        .clean_busy_o(dcache_clean_busy_w),
        .clean_done_o(dcache_clean_done_w),

        // Addressed software maintenance operation.
        .maint_invalidate_i(cache_maint_dcache_invalidate_w),
        .maint_clean_i(cache_maint_dcache_clean_w),
        .maint_clean_invalidate_i(cache_maint_dcache_clean_invalidate_w),
        .maint_addr_i(cache_maint_dcache_addr_w),
        .maint_size_i(cache_maint_dcache_size_w),
        .maint_busy_o(),
        .maint_done_o(),

        // Direct AXI refill, writeback and uncached traffic.
        .axi_awid_o(dcache_axi_awid_o),
        .axi_awaddr_o(dcache_axi_awaddr_o),
        .axi_awlen_o(dcache_axi_awlen_o),
        .axi_awsize_o(dcache_axi_awsize_o),
        .axi_awburst_o(dcache_axi_awburst_o),
        .axi_awvalid_o(dcache_axi_awvalid_o),
        .axi_awready_i(dcache_axi_awready_i),
        .axi_wdata_o(dcache_axi_wdata_o),
        .axi_wstrb_o(dcache_axi_wstrb_o),
        .axi_wlast_o(dcache_axi_wlast_o),
        .axi_wvalid_o(dcache_axi_wvalid_o),
        .axi_wready_i(dcache_axi_wready_i),
        .axi_bid_i(dcache_axi_bid_i),
        .axi_bresp_i(dcache_axi_bresp_i),
        .axi_bvalid_i(dcache_axi_bvalid_i),
        .axi_bready_o(dcache_axi_bready_o),
        .axi_arid_o(dcache_axi_arid_o),
        .axi_araddr_o(dcache_axi_araddr_o),
        .axi_arlen_o(dcache_axi_arlen_o),
        .axi_arsize_o(dcache_axi_arsize_o),
        .axi_arburst_o(dcache_axi_arburst_o),
        .axi_arvalid_o(dcache_axi_arvalid_o),
        .axi_arready_i(dcache_axi_arready_i),
        .axi_rid_i(dcache_axi_rid_i),
        .axi_rdata_i(dcache_axi_rdata_i),
        .axi_rresp_i(dcache_axi_rresp_i),
        .axi_rlast_i(dcache_axi_rlast_i),
        .axi_rvalid_i(dcache_axi_rvalid_i),
        .axi_rready_o(dcache_axi_rready_o),

        // Performance-event observation.
        .miss_o(dcache_miss_w),
        .writeback_o(dcache_writeback_w),
        .refill_busy_o(dcache_refill_busy_w)
    );

    // CPU-local cache-maintenance MMIO slave.
    edrv32_cache_maint u_cache_maint (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),

        // CPU-local MMIO request and response.
        .request_valid_i(core_dmem_req_valid_w &&
                         core_dmem_is_cache_maint_w),
        .request_ready_o(cache_maint_request_ready_w),
        .request_addr_i(core_dmem_req_addr_w),
        .request_write_i(core_dmem_req_write_w),
        .request_size_i(core_dmem_req_size_w),
        .request_wstrb_i(core_dmem_req_wstrb_w),
        .request_wdata_i(core_dmem_req_wdata_w),
        .response_valid_o(cache_maint_response_valid_w),
        .response_ready_i(cache_maint_response_ready_w),
        .response_data_o(cache_maint_response_data_w),
        .response_error_o(cache_maint_response_error_w),

        // D-cache maintenance command and completion.
        .dcache_invalidate_o(cache_maint_dcache_invalidate_w),
        .dcache_clean_o(cache_maint_dcache_clean_w),
        .dcache_clean_invalidate_o(
            cache_maint_dcache_clean_invalidate_w),
        .dcache_addr_o(cache_maint_dcache_addr_w),
        .dcache_size_o(cache_maint_dcache_size_w),
        .dcache_busy_i(dcache_clean_busy_w),
        .dcache_done_i(dcache_clean_done_w),

        // I-cache invalidation pulse.
        .icache_invalidate_o(cache_maint_icache_invalidate_w)
    );

    wire unused_dcache_clean_busy_w = dcache_clean_busy_w;

endmodule
