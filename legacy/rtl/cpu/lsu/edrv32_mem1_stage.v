// ============================================================================
// File        : edrv32_mem1_stage.v
// Description : MEM1 combinational PMA classification and packet formation.
// Notes       : MEM1 never issues an externally visible request or changes
//               cache state.  The two-entry MEM1->MEM2 timing-cut FIFO lives
//               only in edrv32_pipe_mem1_to_mem2.  When that FIFO is empty and
//               the MEM2 owner slot is guaranteed to be free next cycle, MEM1
//               may fire the side-effect-free D-cache array read one cycle
//               early and record it in the FIFO entry; MEM2 then waits for the
//               in-flight response instead of issuing a second request.  The
//               early issue is fire-and-forget: if the cache port declines,
//               the entry proceeds and MEM2 issues its own fallback request.
// ============================================================================
`include "edrv32_uop.vh"
`include "edrv32_pair.vh"
`include "edrv32_bus.vh"
`include "edrv32_exception.vh"
`include "edrv32_pma.vh"
`include "edrv32_lsu.vh"

// The stage directly owns its execution logic and outgoing registered boundary.
module edrv32_mem1_stage #(
    parameter integer DUAL_ISSUE = 0,
    parameter integer CACHE_ENABLE = 0,
    parameter integer TCM_ENABLE  = 0,
    parameter integer ITCM_ENABLE = TCM_ENABLE,
    parameter integer DTCM_ENABLE = TCM_ENABLE
) (
    input  wire                          clk_i,
    input  wire                          rst_n_i,

    input  wire [`EDRV32_PAIR_RESULT_W-1:0] second_i,
    output wire [`EDRV32_PAIR_RESULT_W-1:0] packet_second_o,


    // Registered executed uop from EX.
    input  wire                          valid_i,
    output wire                          ready_o,
    input  wire [31:0]                   pc_i,
    input  wire [31:0]                   instr_i,
    input  wire                          is_compressed_i,
    input  wire [`EDRV32_EPOCH_W-1:0]    epoch_i,
    input  wire [4:0]                    rd_i,
    input  wire                          rd_write_i,
    input  wire [`EDRV32_OP_CLASS_W-1:0] op_class_i,
    input  wire [31:0]                   result_i,
    input  wire                          result_ready_i,
    input  wire [31:0]                   mem_addr_i,
    input  wire [`BUS_SZ_W-1:0]          mem_size_i,
    input  wire                          mem_unsigned_i,
    input  wire [31:0]                   store_data_i,
    input  wire                          mdu_token_i,
    input  wire [`EDRV32_CSR_OP_W-1:0]   csr_op_i,
    input  wire [11:0]                   csr_addr_i,
    input  wire [31:0]                   csr_src_i,
    input  wire                          fence_i,
    input  wire                          fencei_i,
    input  wire                          mret_i,
    input  wire                          wfi_i,
    input  wire                          exception_valid_i,
    input  wire [`EDRV32_EXC_CAUSE_W-1:0] exception_cause_i,
    input  wire [31:0]                   exception_tval_i,
    input  wire [`EDRV32_LSU_SEQUENCE_W-1:0] memory_sequence_i,

    // Registered classified uop presented to MEM2.
    output wire                          packet_valid_o,
    input  wire                          packet_ready_i,
    output wire [31:0]                   packet_pc_o,
    output wire [31:0]                   packet_instr_o,
    output wire                          packet_is_compressed_o,
    output wire [`EDRV32_EPOCH_W-1:0]    packet_epoch_o,
    output wire [4:0]                    packet_rd_o,
    output wire                          packet_rd_write_o,
    output wire [`EDRV32_OP_CLASS_W-1:0] packet_op_class_o,
    output wire [31:0]                   packet_result_o,
    output wire                          packet_result_ready_o,
    output wire [31:0]                   packet_mem_addr_o,
    output wire [`BUS_SZ_W-1:0]          packet_mem_size_o,
    output wire                          packet_mem_unsigned_o,
    output wire [31:0]                   packet_store_data_o,
    output wire                          packet_mem_cacheable_o,
    output wire                          packet_mem_tcm_o,
    output wire                          packet_mem_mmio_o,
    output wire                          packet_lsu_token_valid_o,
    output wire [`EDRV32_LSU_TOKEN_W-1:0] packet_lsu_token_o,
    output wire                          packet_mdu_token_o,
    output wire [`EDRV32_CSR_OP_W-1:0]   packet_csr_op_o,
    output wire [11:0]                   packet_csr_addr_o,
    output wire [31:0]                   packet_csr_src_o,
    output wire                          packet_fence_o,
    output wire                          packet_fencei_o,
    output wire                          packet_mret_o,
    output wire                          packet_wfi_o,
    output wire                          packet_exception_valid_o,
    output wire [`EDRV32_EXC_CAUSE_W-1:0] packet_exception_cause_o,
    output wire [31:0]                   packet_exception_tval_o,
    output wire                          full_o,

    // Cacheable load ownership allocation. The queue may issue the D-cache
    // request on this same cycle using its empty-queue bypass.
    output wire                          load_alloc_valid_o,
    input  wire                          load_alloc_ready_i,
    input  wire [`EDRV32_LSU_TOKEN_W-1:0] load_alloc_token_i,
    output wire [31:0]                   load_alloc_pc_o,
    output wire [4:0]                    load_alloc_rd_o,
    output wire [31:0]                   load_alloc_addr_o,
    output wire [`BUS_SZ_W-1:0]          load_alloc_size_o,
    output wire                          load_alloc_unsigned_o,
    output wire [`EDRV32_EPOCH_W-1:0]    load_alloc_epoch_o,
    output wire [`EDRV32_LSU_SEQUENCE_W-1:0] load_alloc_sequence_o,

    output wire                          store_alloc_valid_o,
    input  wire                          store_alloc_ready_i,
    input  wire [`EDRV32_LSU_TOKEN_W-1:0] store_alloc_token_i,
    output wire [31:0]                   store_alloc_pc_o,
    output wire [31:0]                   store_alloc_addr_o,
    output wire [3:0]                    store_alloc_wstrb_o,
    output wire [31:0]                   store_alloc_wdata_o,
    output wire [`EDRV32_EPOCH_W-1:0]    store_alloc_epoch_o,
    output wire [`EDRV32_LSU_SEQUENCE_W-1:0] store_alloc_sequence_o,

    input  wire                          kill_i
);

    wire                          candidate_valid_w;
    wire                          candidate_ready_w;
    wire [31:0]                   candidate_pc_w;
    wire [31:0]                   candidate_instr_w;
    wire                          candidate_is_compressed_w;
    wire [`EDRV32_EPOCH_W-1:0]    candidate_epoch_w;
    wire [4:0]                    candidate_rd_w;
    wire                          candidate_rd_write_w;
    wire [`EDRV32_OP_CLASS_W-1:0] candidate_op_class_w;
    wire [31:0]                   candidate_result_w;
    wire                          candidate_result_ready_w;
    wire [31:0]                   candidate_mem_addr_w;
    wire [`BUS_SZ_W-1:0]          candidate_mem_size_w;
    wire                          candidate_mem_unsigned_w;
    wire [31:0]                   candidate_store_data_w;
    wire                          candidate_mem_cacheable_w;
    wire                          candidate_mem_tcm_w;
    wire                          candidate_mem_mmio_w;
    wire                          candidate_lsu_token_valid_w;
    wire [`EDRV32_LSU_TOKEN_W-1:0] candidate_lsu_token_w;
    wire                          candidate_mdu_token_w;
    wire [`EDRV32_CSR_OP_W-1:0]   candidate_csr_op_w;
    wire [11:0]                   candidate_csr_addr_w;
    wire [31:0]                   candidate_csr_src_w;
    wire                          candidate_fence_w;
    wire                          candidate_fencei_w;
    wire                          candidate_mret_w;
    wire                          candidate_wfi_w;
    wire                          candidate_exception_valid_w;
    wire [`EDRV32_EXC_CAUSE_W-1:0] candidate_exception_cause_w;
    wire [31:0]                   candidate_exception_tval_w;
    reg  [1:0]                    pipe_count_r;
    wire                          pipe_empty_w;
    wire                          pipe_full_w;
    wire                          pipe_capture_w;
    wire                          pipe_transfer_w;
    wire                          pipe_head_we_w;
    wire                          pipe_head_from_tail_w;
    wire                          pipe_tail_we_w;


    // Stage-local execution logic is written directly in this module.


    // Only load/store uops ask the PMA classifier for data-access permissions.
    wire access_is_load_w = op_class_i == `EDRV32_OP_LOAD;
    wire access_is_store_w = op_class_i == `EDRV32_OP_STORE;
    wire pma_access_fault_w;
    wire pma_cacheable_w;
    wire pma_tcm_w;
    wire pma_device_w;
    wire pma_mapped_unused_w;
    wire pma_permitted_unused_w;
    wire [`PMA_ATTR_WIDTH-1:0] pma_attributes_unused_w;

    edrv32_pma_classifier #(
        .TCM_ENABLE (TCM_ENABLE),
        .ITCM_ENABLE(ITCM_ENABLE),
        .DTCM_ENABLE(DTCM_ENABLE)
    ) u_data_pma (
        // Data access being classified.
        .address_i(mem_addr_i),
        .instruction_i(1'b0),
        .load_i(access_is_load_w),
        .store_i(access_is_store_w),

        // Region properties carried into MEM2 and COMMIT.
        .mapped_o(pma_mapped_unused_w),
        .permitted_o(pma_permitted_unused_w),
        .access_fault_o(pma_access_fault_w),
        .cacheable_o(pma_cacheable_w),
        .tcm_o(pma_tcm_w),
        .device_o(pma_device_w),
        .attributes_o(pma_attributes_unused_w)
    );

    // MEM1 owns the two-entry boundary occupancy and handshake policy.  The
    // pipe module below contains only the two payload register banks.
    // Full-state pop+push is legal: the popped head content is replaced by the
    // promoted tail while the new entry lands in the tail slot, so the
    // boundary sustains one entry per cycle under back-to-back turnover.
    assign pipe_empty_w = (pipe_count_r == 2'd0);
    assign pipe_full_w  = (pipe_count_r == 2'd2);
    wire pipe_slot_ready_w = !pipe_full_w || pipe_transfer_w;
    wire cacheable_load_w = (CACHE_ENABLE != 0) &&
                            access_is_load_w &&
                            pma_cacheable_w &&
                            !exception_valid_i && !pma_access_fault_w;
    wire cacheable_store_w = (CACHE_ENABLE != 0) &&
                             access_is_store_w &&
                             pma_cacheable_w &&
                             !exception_valid_i && !pma_access_fault_w;
    assign candidate_ready_w = ~kill_i && pipe_slot_ready_w &&
                               (!cacheable_load_w || load_alloc_ready_i) &&
                               (!cacheable_store_w || store_alloc_ready_i);
    assign ready_o = ~kill_i && candidate_ready_w;
    assign candidate_valid_w = ~kill_i && valid_i;
    assign packet_valid_o = !pipe_empty_w;
    assign full_o = pipe_full_w;
    assign pipe_capture_w = candidate_valid_w && candidate_ready_w;
    assign pipe_transfer_w = packet_valid_o && packet_ready_i;

    // Occupancy pointer policy for the two-entry register bank:
    // - empty + capture:             head <= input          (0 -> 1)
    // - one   + capture + transfer:  head <= input          (stays 1)
    // - one   + capture:             tail <= input          (1 -> 2)
    // - full  + transfer:            head <= tail payload   (2 -> 1)
    // - full  + capture + transfer:  head <= tail payload
    //                                tail <= input          (stays 2)
    assign pipe_head_we_w = !kill_i &&
        ((pipe_capture_w && pipe_transfer_w) ||
         (pipe_capture_w && !pipe_transfer_w && pipe_empty_w) ||
         (pipe_transfer_w && pipe_full_w));
    assign pipe_head_from_tail_w = !kill_i && pipe_transfer_w && pipe_full_w;
    assign pipe_tail_we_w = !kill_i && pipe_capture_w &&
                            ((!pipe_transfer_w && (pipe_count_r == 2'd1)) ||
                             (pipe_transfer_w && pipe_full_w));

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            pipe_count_r <= 2'd0;
        end else if (kill_i) begin
            pipe_count_r <= 2'd0;
        end else begin
            case ({pipe_capture_w, pipe_transfer_w})
                2'b10: pipe_count_r <= pipe_count_r + 2'd1;
                2'b01: pipe_count_r <= pipe_count_r - 2'd1;
                default: begin end  // 2'b11 keeps occupancy; 2'b00 holds
            endcase
        end
    end

    assign load_alloc_valid_o = !kill_i && valid_i && pipe_slot_ready_w &&
                                cacheable_load_w;
    assign load_alloc_pc_o = pc_i;
    assign load_alloc_rd_o = rd_i;
    assign load_alloc_addr_o = mem_addr_i;
    assign load_alloc_size_o = mem_size_i;
    assign load_alloc_unsigned_o = mem_unsigned_i;
    assign load_alloc_epoch_o = epoch_i;
    assign load_alloc_sequence_o = memory_sequence_i;

    wire [31:0] formatted_store_data_w;
    wire [3:0] formatted_store_wstrb_w;
    wire [31:0] unused_formatted_load_w;
    edrv32_lsu_format u_store_format (
        .addr_lsb_i(mem_addr_i[1:0]),
        .size_i(mem_size_i),
        .mem_rdata_i(32'd0),
        .load_unsigned_i(1'b0),
        .load_data_o(unused_formatted_load_w),
        .store_wdata_i(store_data_i),
        .store_data_o(formatted_store_data_w),
        .store_wstrb_o(formatted_store_wstrb_w)
    );
    assign store_alloc_valid_o = !kill_i && valid_i && pipe_slot_ready_w &&
                                 cacheable_store_w;
    assign store_alloc_pc_o = pc_i;
    assign store_alloc_addr_o = mem_addr_i;
    assign store_alloc_wstrb_o = formatted_store_wstrb_w;
    assign store_alloc_wdata_o = formatted_store_data_w;
    assign store_alloc_epoch_o = epoch_i;
    assign store_alloc_sequence_o = memory_sequence_i;

    assign candidate_pc_w              = pc_i;
    assign candidate_instr_w           = instr_i;
    assign candidate_is_compressed_w   = is_compressed_i;
    assign candidate_epoch_w           = epoch_i;
    assign candidate_rd_w              = rd_i;
    assign candidate_rd_write_w        = rd_write_i;
    assign candidate_op_class_w        = op_class_i;
    assign candidate_result_w          = result_i;
    assign candidate_result_ready_w    = result_ready_i;
    assign candidate_mem_addr_w        = mem_addr_i;
    assign candidate_mem_size_w        = mem_size_i;
    assign candidate_mem_unsigned_w    = mem_unsigned_i;
    assign candidate_store_data_w      = store_data_i;
    assign candidate_mem_cacheable_w   = pma_cacheable_w;
    assign candidate_mem_tcm_w         = pma_tcm_w;
    assign candidate_mem_mmio_w        = pma_device_w;
    assign candidate_lsu_token_valid_w = cacheable_load_w ||
                                          cacheable_store_w;
    assign candidate_lsu_token_w = cacheable_load_w
        ? load_alloc_token_i : store_alloc_token_i;
    assign candidate_mdu_token_w       = mdu_token_i;
    assign candidate_csr_op_w          = csr_op_i;
    assign candidate_csr_addr_w        = csr_addr_i;
    assign candidate_csr_src_w         = csr_src_i;
    assign candidate_fence_w           = fence_i;
    assign candidate_fencei_w         = fencei_i;
    assign candidate_mret_w            = mret_i;
    assign candidate_wfi_w             = wfi_i;
    assign candidate_exception_valid_w = exception_valid_i ||
                                           pma_access_fault_w;
    assign candidate_exception_cause_w = exception_valid_i
        ? exception_cause_i
        : (access_is_load_w ? `EDRV32_EXC_LOAD_ACCESS
                            : `EDRV32_EXC_STORE_ACCESS);
    wire inherited_memory_misaligned_w = exception_valid_i &&
        ((exception_cause_i == `EDRV32_EXC_LOAD_MISALIGNED) ||
         (exception_cause_i == `EDRV32_EXC_STORE_MISALIGNED));
    assign candidate_exception_tval_w = inherited_memory_misaligned_w
        ? mem_addr_i : exception_valid_i ? exception_tval_i : mem_addr_i;


    edrv32_pipe_mem1_to_mem2 #(.SECOND_ENABLE(DUAL_ISSUE)) u_pipe (
        .second_i(second_i),
        .second_o(packet_second_o),
        .clk_i(clk_i),
        .head_we_i(pipe_head_we_w),
        .head_from_tail_i(pipe_head_from_tail_w),
        .tail_we_i(pipe_tail_we_w),
        .pc_i(candidate_pc_w),
        .instr_i(candidate_instr_w),
        .is_compressed_i(candidate_is_compressed_w),
        .epoch_i(candidate_epoch_w),
        .rd_i(candidate_rd_w),
        .rd_write_i(candidate_rd_write_w),
        .op_class_i(candidate_op_class_w),
        .result_i(candidate_result_w),
        .result_ready_i(candidate_result_ready_w),
        .mem_addr_i(candidate_mem_addr_w),
        .mem_size_i(candidate_mem_size_w),
        .mem_unsigned_i(candidate_mem_unsigned_w),
        .store_data_i(candidate_store_data_w),
        .mem_cacheable_i(candidate_mem_cacheable_w),
        .mem_tcm_i(candidate_mem_tcm_w),
        .mem_mmio_i(candidate_mem_mmio_w),
        .lsu_token_valid_i(candidate_lsu_token_valid_w),
        .lsu_token_i(candidate_lsu_token_w),
        .mdu_token_i(candidate_mdu_token_w),
        .csr_op_i(candidate_csr_op_w),
        .csr_addr_i(candidate_csr_addr_w),
        .csr_src_i(candidate_csr_src_w),
        .fence_i(candidate_fence_w),
        .fencei_i(candidate_fencei_w),
        .mret_i(candidate_mret_w),
        .wfi_i(candidate_wfi_w),
        .exception_valid_i(candidate_exception_valid_w),
        .exception_cause_i(candidate_exception_cause_w),
        .exception_tval_i(candidate_exception_tval_w),
        .pc_o(packet_pc_o),
        .instr_o(packet_instr_o),
        .is_compressed_o(packet_is_compressed_o),
        .epoch_o(packet_epoch_o),
        .rd_o(packet_rd_o),
        .rd_write_o(packet_rd_write_o),
        .op_class_o(packet_op_class_o),
        .result_o(packet_result_o),
        .result_ready_o(packet_result_ready_o),
        .mem_addr_o(packet_mem_addr_o),
        .mem_size_o(packet_mem_size_o),
        .mem_unsigned_o(packet_mem_unsigned_o),
        .store_data_o(packet_store_data_o),
        .mem_cacheable_o(packet_mem_cacheable_o),
        .mem_tcm_o(packet_mem_tcm_o),
        .mem_mmio_o(packet_mem_mmio_o),
        .lsu_token_valid_o(packet_lsu_token_valid_o),
        .lsu_token_o(packet_lsu_token_o),
        .mdu_token_o(packet_mdu_token_o),
        .csr_op_o(packet_csr_op_o),
        .csr_addr_o(packet_csr_addr_o),
        .csr_src_o(packet_csr_src_o),
        .fence_o(packet_fence_o),
        .fencei_o(packet_fencei_o),
        .mret_o(packet_mret_o),
        .wfi_o(packet_wfi_o),
        .exception_valid_o(packet_exception_valid_o),
        .exception_cause_o(packet_exception_cause_o),
        .exception_tval_o(packet_exception_tval_o)
    );

endmodule
