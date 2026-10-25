// ============================================================================
// File        : edrv32_core.v
// Description : Structural integration of the eight named scalar stages:
//               IF1/IF2/ALIGN/DECODE/EX/MEM1/MEM2/COMMIT.
// Notes       : Stage logic and architectural side effects stay in their
//               owner modules; this file contains only named wiring and
//               module instances.
// ============================================================================
`include "edrv32_uop.vh"
`include "edrv32_pair.vh"
`include "edrv32_bus.vh"
`include "edrv32_exception.vh"
`include "edrv32_hpm.vh"
`include "edrv32_lsu.vh"

module edrv32_core #(
    parameter [31:0] RESET_PC = 32'h8000_0000,
    parameter integer CACHE_ENABLE = 0,
    parameter integer TCM_ENABLE  = 0,
    parameter integer ITCM_ENABLE = TCM_ENABLE,
    parameter integer DTCM_ENABLE = TCM_ENABLE,
    parameter integer RAS_DEPTH = 8,
    parameter integer MUL_USE_PANGO_APM = 0,
    parameter integer MUL_LOW_PIPE_STAGES = 1,
    parameter integer CPU_HPM_ENABLE = 1,
    parameter integer FRONTEND_DUAL_WINDOW = 0,
    parameter integer DUAL_ISSUE = 0,
    parameter integer FETCH_WIDE = 0,
    parameter [31:0] MVENDORID = 32'd0,
    parameter [31:0] MARCHID   = 32'd0,
    parameter [31:0] MIMPID    = 32'd0,
    parameter [31:0] MHARTID   = 32'd0
)(
    input  wire                         clk_i,
    input  wire                         rst_n_i,

    input wire [1:0] imem_req_words_i,
    input wire [31:0] imem_resp_upper_i,
    input wire [31:0] imem_preview_upper_i,

    // Instruction request/response channel.
    output wire                         imem_req_valid_o,
    input  wire                         imem_req_ready_i,
    output wire [31:0]                  imem_req_addr_o,
    input  wire                         imem_resp_valid_i,
    output wire                         imem_resp_ready_o,
    input  wire [31:0]                  imem_resp_rdata_i,
    input  wire                         imem_resp_error_i,
    input  wire                         imem_preview_valid_i,
    input  wire [31:0]                  imem_preview_addr_i,
    input  wire [31:0]                  imem_preview_data_i,

    // Uncached or MMIO data request/response channel owned by COMMIT.
    output wire                         dmem_req_valid_o,
    input  wire                         dmem_req_ready_i,
    output wire [31:0]                  dmem_req_addr_o,
    output wire                         dmem_req_we_o,
    output wire [`BUS_SZ_W-1:0]         dmem_req_size_o,
    output wire [3:0]                   dmem_req_wstrb_o,
    output wire [31:0]                  dmem_req_wdata_o,
    output wire                         dmem_req_cacheable_o,
    input  wire                         dmem_resp_valid_i,
    output wire                         dmem_resp_ready_o,
    input  wire [31:0]                  dmem_resp_rdata_i,
    input  wire                         dmem_resp_error_i,

    // Cacheable lookup channel arbitrated by the Load and Store queues.
    output wire                         dcache_lookup_valid_o,
    input  wire                         dcache_lookup_ready_i,
    output wire [31:0]                  dcache_lookup_addr_o,
    output wire [`EDRV32_LSU_TOKEN_W-1:0] dcache_lookup_token_o,
    output wire                         dcache_lookup_store_o,
    output wire [`BUS_SZ_W-1:0]         dcache_lookup_size_o,
    output wire                         dcache_lookup_unsigned_o,
    input  wire                         dcache_lookup_resp_valid_i,
    output wire                         dcache_lookup_resp_ready_o,
    input  wire [31:0]                  dcache_lookup_resp_data_i,
    input  wire                         dcache_lookup_resp_error_i,
    input  wire [`EDRV32_LSU_TOKEN_W-1:0] dcache_lookup_resp_token_i,
    input  wire                         dcache_lookup_resp_store_i,
    input  wire                         dcache_lookup_fast_valid_i,
    output wire                         dcache_lookup_fast_ready_o,
    input  wire [`EDRV32_LSU_TOKEN_W-1:0] dcache_lookup_fast_token_i,
    input  wire                         dcache_lookup_fast_store_i,
    input  wire [31:0]                  dcache_lookup_fast_data_i,
    output wire                         dcache_lookup_cancel_o,
    output wire [1:0]                   dcache_reservation_keep_count_o,

    // {D$ refill wait, I$ refill wait, D$ writeback, D$ miss, I$ miss}.
    // Uncached/direct-memory integrations tie this observation-only port low.
    input  wire [4:0]                   cache_perf_events_i,

    // Machine-mode interrupt and time inputs.
    input  wire                         irq_soft_i,
    input  wire                         irq_timer_i,
    input  wire                         irq_ext_i,
    input  wire [63:0]                  time_value_i,

    // Retirement, ordering and debug observation outputs.
    output wire                             second_retire_o,
    output wire [31:0]                      second_retire_pc_o,
    output wire [31:0]                      second_retire_instr_o,
    output wire [1:0]                       retire_count_o,
    output wire                         retire_o,
    output wire [31:0]                  retire_pc_o,
    output wire [31:0]                  retire_instr_o,
    output wire                         retire_exception_o,
    output wire [31:0]                  retire_cause_o,
    output wire                         fence_retire_o,
    output wire                         fencei_retire_o,
    output wire                         core_sleep_o,
    output wire [31:0]                  debug_decode_pc_o,
    output wire [31:0]                  debug_decode_instr_o
);

    localparam integer PAIR_FRONTEND_ENABLE = (FRONTEND_DUAL_WINDOW != 0) ||
        (DUAL_ISSUE != 0) || (FETCH_WIDE != 0);
    wire [`EDRV32_PAIR_DECODE_W-1:0] decode_second_w;
    wire [`EDRV32_PAIR_RESULT_W-1:0] ex_second_w;
    wire [`EDRV32_PAIR_RESULT_W-1:0] mem1_second_w;
    wire [`EDRV32_PAIR_RESULT_W-1:0] mem2_second_w;
    wire [`EDRV32_PAIR_RESULT_W-1:0] commit_second_w;
    wire commit_second_write_w;
    wire [4:0] commit_second_rd_w;
    wire [31:0] commit_second_value_w;
    wire second_retire_compressed_w;
    wire if2_hpm_second_consume_hw1_w;
    wire if2_hpm_second_consume_hw2_w;
    wire [`EDRV32_HPM_EVENT_W-1:0] hpm_second_events_w;
    wire  align_second_valid_w;
    wire [31:0] align_second_pc_w;
    wire [31:0] align_second_instr_w;
    wire [31:0] align_second_raw_instr_w;
    wire  align_second_is_compressed_w;
    wire  align_second_fetch_fault_w;
    wire  align_second_compressed_illegal_w;
    wire [`EDRV32_EPOCH_W-1:0] align_second_epoch_w;
    wire  align_second_predicted_taken_w;
    wire [31:0] align_second_predicted_target_w;
    wire [1:0] align_second_predictor_meta_w;
    wire align_second_accept_w;

    wire [31:0] fetch_block_upper_w;
    wire [1:0] fetch_block_words_w;
    wire if2_hpm_second_append_hw2_w;
    wire [31:0] predictor_query_pc2_w;
    wire  if1_predicted_taken2_w;
    wire [31:0] if1_predicted_target2_w;
    wire [1:0] if1_predictor_meta2_w;
    wire  fetch_block_predicted_taken2_w;
    wire [31:0] fetch_block_predicted_target2_w;
    wire [1:0] fetch_block_predictor_meta2_w;
    wire [31:0] predictor_query_pc3_w;
    wire  if1_predicted_taken3_w;
    wire [31:0] if1_predicted_target3_w;
    wire [1:0] if1_predictor_meta3_w;
    wire  fetch_block_predicted_taken3_w;
    wire [31:0] fetch_block_predicted_target3_w;
    wire [1:0] fetch_block_predictor_meta3_w;

    // IF1->IF2 accepted-request/response packet.
    wire fetch_block_valid_w;
    wire fetch_block_ready_w;
    wire [31:0] fetch_block_addr_w;
    wire [31:0] fetch_block_data_w;
    wire fetch_block_error_w;
    wire [`EDRV32_EPOCH_W-1:0] fetch_block_epoch_w;
    wire fetch_block_predicted_taken0_w;
    wire [31:0] fetch_block_predicted_target0_w;
    wire fetch_block_predicted_taken1_w;
    wire [31:0] fetch_block_predicted_target1_w;
    wire [1:0] fetch_block_predictor_meta0_w;
    wire [1:0] fetch_block_predictor_meta1_w;
    wire fetch_preview_valid_w;
    wire [31:0] fetch_preview_addr_w;
    wire [`EDRV32_EPOCH_W-1:0] fetch_preview_epoch_w;
    wire [31:0] fetch_preview_target0_w;
    wire [31:0] fetch_preview_target1_w;
    wire prediction_redirect_fast_w;
    wire prediction_redirect_fast_slot1_w;

    // Registered IF2->ALIGN window.
    wire fetch_window_valid_w;
    wire [15:0] fetch_halfword0_w;
    wire [15:0] fetch_halfword1_w;
    wire fetch_halfword1_valid_w;
    wire [31:0] fetch_window_pc_w;
    wire fetch_halfword0_error_w;
    wire fetch_halfword1_error_w;
    wire [`EDRV32_EPOCH_W-1:0] fetch_window_epoch_w;
    wire fetch_window_predicted_taken_w;
    wire [31:0] fetch_window_predicted_target_w;
    wire [1:0] fetch_window_predictor_meta_w;
    wire fetch_window_pipe_accept_w;

    // Registered ALIGN->DECODE instruction packet.
    wire align_valid_w;
    wire align_accept_w;
    wire [31:0] align_pc_w;
    wire [31:0] align_instr_w;
    wire [31:0] align_raw_instr_w;
    wire align_is_compressed_w;
    wire align_fetch_fault_w;
    wire align_compressed_illegal_w;
    wire [`EDRV32_EPOCH_W-1:0] align_epoch_w;
    wire align_predicted_taken_w;
    wire [31:0] align_predicted_target_w;
    wire [1:0] align_predictor_meta_w;

    // Registered DECODE->EX uop and dependency-stall observations.
    wire decode_resident_second_rs1_w;
    wire decode_resident_second_rs2_w;
    wire decode_valid_w;
    wire decode_accept_w;
    wire [31:0] decode_pc_w;
    wire [31:0] decode_instr_w;
    wire decode_is_compressed_w;
    wire [`EDRV32_EPOCH_W-1:0] decode_epoch_w;
    wire decode_predicted_taken_w;
    wire [31:0] decode_predicted_target_w;
    wire [1:0] decode_predictor_meta_w;
    wire [4:0] decode_rd_w;
    wire decode_rd_write_w;
    wire [`EDRV32_OP_CLASS_W-1:0] decode_op_class_w;
    wire [`EDRV32_ALU_OP_W-1:0] decode_alu_op_w;
    wire [`EDRV32_BRANCH_OP_W-1:0] decode_branch_op_w;
    wire [`BUS_SZ_W-1:0] decode_mem_size_w;
    wire decode_mem_unsigned_w;
    wire [`EDRV32_MDU_OP_W-1:0] decode_mdu_op_w;
    wire [`EDRV32_CSR_OP_W-1:0] decode_csr_op_w;
    wire [11:0] decode_csr_addr_w;
    wire [31:0] decode_csr_src_w;
    wire [31:0] decode_lhs_w;
    wire [31:0] decode_rhs_w;
    wire [31:0] decode_rs2_value_w;
    wire decode_resident_bypass_rs1_w;
    wire decode_resident_bypass_rs2_w;
    wire [31:0] decode_resident_bypass_pc_w;
    wire decode_late_mdu_rs1_w;
    wire decode_late_mdu_rs2_w;
    wire decode_late_load_rs1_w;
    wire decode_late_load_rs2_w;
    wire [31:0] decode_late_load_rs1_pc_w;
    wire [31:0] decode_late_load_rs2_pc_w;
    wire decode_late_load_rs1_token_valid_w;
    wire [`EDRV32_LSU_TOKEN_W-1:0] decode_late_load_rs1_token_w;
    wire decode_late_load_rs2_token_valid_w;
    wire [`EDRV32_LSU_TOKEN_W-1:0] decode_late_load_rs2_token_w;
    wire [31:0] decode_imm_w;
    wire decode_fence_w;
    wire decode_fencei_w;
    wire decode_mret_w;
    wire decode_wfi_w;
    wire decode_exception_valid_w;
    wire [`EDRV32_EXC_CAUSE_W-1:0] decode_exception_cause_w;
    wire [31:0] decode_exception_tval_w;
    wire decode_dependency_stall_w;
    wire decode_structural_stall_w;
    wire ex_late_load_stall_w;
    wire ex_late_mdu_stall_w;

    // Registered EX->MEM1 executed uop.  These signals also form the youngest
    // registered bypass record observed by DECODE.
    wire ex_valid_w;
    wire ex_accept_w;
    wire [31:0] ex_pc_w;
    wire [31:0] ex_instr_w;
    wire ex_is_compressed_w;
    wire [`EDRV32_EPOCH_W-1:0] ex_epoch_w;
    wire [4:0] ex_rd_w;
    wire ex_rd_write_w;
    wire [`EDRV32_OP_CLASS_W-1:0] ex_op_class_w;
    wire [31:0] ex_result_w;
    wire ex_result_ready_w;
    wire [31:0] ex_mem_addr_w;
    wire [`BUS_SZ_W-1:0] ex_mem_size_w;
    wire ex_mem_unsigned_w;
    wire [31:0] ex_store_data_w;
    wire ex_mdu_token_w;
    wire [`EDRV32_CSR_OP_W-1:0] ex_csr_op_w;
    wire [11:0] ex_csr_addr_w;
    wire [31:0] ex_csr_src_w;
    wire ex_fence_w;
    wire ex_fencei_w;
    wire ex_mret_w;
    wire ex_wfi_w;
    wire ex_exception_valid_w;
    wire [`EDRV32_EXC_CAUSE_W-1:0] ex_exception_cause_w;
    wire [31:0] ex_exception_tval_w;

    // Registered MEM1->MEM2 packet.  The boundary is a two-entry FIFO, so its
    // head and tail also participate in dependency tracking.
    wire mem1_packet_valid_w;
    wire mem1_packet_accept_w;
    wire [31:0] mem1_packet_pc_w;
    wire [31:0] mem1_packet_instr_w;
    wire mem1_packet_is_compressed_w;
    wire [`EDRV32_EPOCH_W-1:0] mem1_packet_epoch_w;
    wire [4:0] mem1_packet_rd_w;
    wire mem1_packet_rd_write_w;
    wire [`EDRV32_OP_CLASS_W-1:0] mem1_packet_op_class_w;
    wire [31:0] mem1_packet_result_w;
    wire mem1_packet_result_ready_w;
    wire [31:0] mem1_packet_mem_addr_w;
    wire [`BUS_SZ_W-1:0] mem1_packet_mem_size_w;
    wire mem1_packet_mem_unsigned_w;
    wire [31:0] mem1_packet_store_data_w;
    wire mem1_packet_mem_cacheable_w;
    wire mem1_packet_mem_tcm_w;
    wire mem1_packet_mem_mmio_w;
    wire mem1_packet_lsu_token_valid_w;
    wire [`EDRV32_LSU_TOKEN_W-1:0] mem1_packet_lsu_token_w;
    wire mem1_packet_mdu_token_w;
    wire [`EDRV32_CSR_OP_W-1:0] mem1_packet_csr_op_w;
    wire [11:0] mem1_packet_csr_addr_w;
    wire [31:0] mem1_packet_csr_src_w;
    wire mem1_packet_fence_w;
    wire mem1_packet_fencei_w;
    wire mem1_packet_mret_w;
    wire mem1_packet_wfi_w;
    wire mem1_packet_exception_valid_w;
    wire [`EDRV32_EXC_CAUSE_W-1:0] mem1_packet_exception_cause_w;
    wire [31:0] mem1_packet_exception_tval_w;
    wire mem1_to_mem2_full_w;
    wire dcache_lookup_valid_w;
    wire [31:0] dcache_lookup_addr_w;
    wire dcache_lookup_store_w;
    wire [`BUS_SZ_W-1:0] dcache_lookup_size_w;
    wire dcache_lookup_unsigned_w;

    // Cacheable-load ownership queue.
    wire load_alloc_valid_w;
    wire load_alloc_ready_w;
    wire load_queue_alloc_ready_w;
    wire [`EDRV32_LSU_TOKEN_W-1:0] load_alloc_token_w;
    wire [31:0] load_alloc_pc_w;
    wire [4:0] load_alloc_rd_w;
    wire [31:0] load_alloc_addr_w;
    wire [`BUS_SZ_W-1:0] load_alloc_size_w;
    wire load_alloc_unsigned_w;
    wire [`EDRV32_EPOCH_W-1:0] load_alloc_epoch_w;
    wire load_request_valid_w;
    wire load_request_ready_w;
    wire [`EDRV32_LSU_TOKEN_W-1:0] load_request_token_w;
    wire [31:0] load_request_addr_w;
    wire [`BUS_SZ_W-1:0] load_request_size_w;
    wire load_request_unsigned_w;
    wire [`EDRV32_LSU_SEQUENCE_W-1:0] load_request_sequence_w;
    wire load_pending_valid_w;
    wire [`EDRV32_LSU_SEQUENCE_W-1:0] load_pending_sequence_w;
    wire load_completion_valid_w;
    wire [`EDRV32_LSU_TOKEN_W-1:0] load_completion_token_w;
    wire [31:0] load_completion_data_w;
    wire [31:0] load_completion_pc_w;
    wire load_commit_valid_w;
    wire [`EDRV32_LSU_TOKEN_W-1:0] load_commit_token_w;
    wire load_commit_ready_w;
    wire [31:0] load_commit_data_w;
    wire load_commit_error_w;
    wire load_commit_fire_w;
    wire load_queue_empty_w;
    wire load_queue_full_unused_w;
    wire load_probe_rs1_ready_w;
    wire [31:0] load_probe_rs1_value_w;
    wire load_probe_rs1_stored_ready_w;
    wire [31:0] load_probe_rs1_stored_value_w;
    wire load_probe_rs2_ready_w;
    wire [31:0] load_probe_rs2_value_w;
    wire load_probe_rs2_stored_ready_w;
    wire [31:0] load_probe_rs2_stored_value_w;
    wire load_mem2_observe_match_w;
    wire load_mem2_observe_ready_w;
    wire [31:0] load_mem2_observe_value_w;
    reg [`EDRV32_LSU_SEQUENCE_W-1:0] memory_sequence_r;

    wire store_alloc_valid_w;
    wire store_alloc_ready_w;
    wire [`EDRV32_LSU_TOKEN_W-1:0] store_alloc_token_w;
    wire [31:0] store_alloc_pc_w;
    wire [31:0] store_alloc_addr_w;
    wire [3:0] store_alloc_wstrb_w;
    wire [31:0] store_alloc_wdata_w;
    wire [`EDRV32_EPOCH_W-1:0] store_alloc_epoch_w;
    wire [`EDRV32_LSU_SEQUENCE_W-1:0] store_alloc_sequence_w;
    wire store_prepare_valid_w;
    wire store_prepare_ready_w;
    wire [`EDRV32_LSU_TOKEN_W-1:0] store_prepare_token_w;
    wire [31:0] store_prepare_addr_w;
    wire [`EDRV32_LSU_SEQUENCE_W-1:0] store_prepare_sequence_w;
    wire store_commit_valid_w;
    wire [`EDRV32_LSU_TOKEN_W-1:0] store_commit_token_w;
    wire store_commit_ready_w;
    wire store_commit_error_w;
    wire store_commit_fire_w;
    wire store_drain_valid_w;
    wire store_drain_ready_w;
    wire [`EDRV32_LSU_TOKEN_W-1:0] store_drain_token_w;
    wire [31:0] store_drain_addr_w;
    wire [3:0] store_drain_wstrb_w;
    wire [31:0] store_drain_wdata_w;
    wire store_queue_empty_w;
    wire store_queue_full_unused_w;
    wire store_committed_empty_w;
    wire [1:0] store_committed_reservation_count_w;
    wire store_load_match_w;
    wire store_load_forward_ready_w;
    wire [31:0] store_load_forward_data_w;
    wire [`EDRV32_LSU_TOKEN_W-1:0] store_load_match_token_w;
    wire store_release_valid_w;
    wire [`EDRV32_LSU_TOKEN_W-1:0] store_release_token_w;

    // MEM2 resident producer record.
    wire mem2_hazard_valid_w;
    wire mem2_hazard_write_w;
    wire mem2_hazard_ready_w;
    wire [4:0] mem2_hazard_rd_w;
    wire [31:0] mem2_hazard_value_w;
    wire [31:0] mem2_hazard_pc_w;
    wire [`EDRV32_OP_CLASS_W-1:0] mem2_hazard_op_class_w;
    wire mem2_hazard_late_load_w;
    wire mem2_hazard_lsu_token_valid_w;
    wire [`EDRV32_LSU_TOKEN_W-1:0] mem2_hazard_lsu_token_w;
    wire mem2_hazard_effective_ready_w = mem2_hazard_ready_w ||
        (mem2_hazard_late_load_w && load_mem2_observe_ready_w);
    wire [31:0] mem2_hazard_effective_value_w =
        (mem2_hazard_late_load_w && load_mem2_observe_ready_w)
            ? load_mem2_observe_value_w : mem2_hazard_value_w;
    wire mem2_cache_wait_w = mem2_hazard_valid_w &&
        mem2_hazard_late_load_w && mem2_hazard_lsu_token_valid_w &&
        load_mem2_observe_match_w && !load_mem2_observe_ready_w;
    // Producer-class observations for the late-load soft release in DECODE.
    // Every Load may soft-release into EX. Cacheable Loads are observed from
    // the tokenized Load Queue; uncached/MMIO Loads are observed when their
    // COMMIT packet completes. The consumer retains the selected producer PC,
    // so an older same-rd result cannot release it.
    wire ex_bypass_is_load_w =
        ex_op_class_w == `EDRV32_OP_LOAD;
    wire mem1_bypass_is_load_w =
        mem1_packet_op_class_w == `EDRV32_OP_LOAD;
    wire mem2_bypass_is_load_w =
        mem2_hazard_op_class_w == `EDRV32_OP_LOAD;
    // Registered MEM2->COMMIT completion packet.
    wire mem2_packet_valid_w;
    wire mem2_packet_accept_w;
    wire [31:0] mem2_packet_pc_w;
    wire [31:0] mem2_packet_instr_w;
    wire mem2_packet_is_compressed_w;
    wire [`EDRV32_EPOCH_W-1:0] mem2_packet_epoch_w;
    wire [4:0] mem2_packet_rd_w;
    wire mem2_packet_rd_write_w;
    wire [`EDRV32_OP_CLASS_W-1:0] mem2_packet_op_class_w;
    wire [31:0] mem2_packet_result_w;
    wire mem2_packet_result_ready_w;
    wire [31:0] mem2_packet_mem_addr_w;
    wire [`BUS_SZ_W-1:0] mem2_packet_mem_size_w;
    wire mem2_packet_mem_unsigned_w;
    wire [31:0] mem2_packet_store_data_w;
    wire mem2_packet_mem_cacheable_w;
    wire mem2_packet_mem_tcm_w;
    wire mem2_packet_mem_mmio_w;
    wire mem2_packet_lsu_token_valid_w;
    wire [`EDRV32_LSU_TOKEN_W-1:0] mem2_packet_lsu_token_w;
    wire mem2_packet_mdu_token_w;
    wire [`EDRV32_CSR_OP_W-1:0] mem2_packet_csr_op_w;
    wire [11:0] mem2_packet_csr_addr_w;
    wire [31:0] mem2_packet_csr_src_w;
    wire mem2_packet_fence_w;
    wire mem2_packet_fencei_w;
    wire mem2_packet_mret_w;
    wire mem2_packet_wfi_w;
    wire mem2_packet_exception_valid_w;
    wire [`EDRV32_EXC_CAUSE_W-1:0] mem2_packet_exception_cause_w;
    wire [31:0] mem2_packet_exception_tval_w;

    // COMMIT GPR writeback and oldest registered bypass record.
    wire commit_gpr_write_w;
    wire [4:0] commit_gpr_rd_w;
    wire [31:0] commit_gpr_value_w;
    wire commit_bypass_valid_w;
    wire commit_bypass_write_w;
    wire commit_bypass_ready_w;
    wire [4:0] commit_bypass_rd_w;
    wire [31:0] commit_bypass_value_w;
    wire commit_load_bypass_valid_w = commit_bypass_valid_w &&
        commit_bypass_write_w && commit_bypass_ready_w &&
        (mem2_packet_op_class_w == `EDRV32_OP_LOAD);
    wire commit_dmem_req_valid_w;
    wire commit_dmem_req_ready_w;
    wire [31:0] commit_dmem_req_addr_w;
    wire commit_dmem_req_we_w;
    wire [`BUS_SZ_W-1:0] commit_dmem_req_size_w;
    wire [3:0] commit_dmem_req_wstrb_w;
    wire [31:0] commit_dmem_req_wdata_w;
    wire commit_dmem_req_cacheable_w;
    wire commit_dmem_resp_valid_w;
    wire commit_dmem_resp_ready_w;
    wire [31:0] commit_dmem_resp_data_w;
    wire commit_dmem_resp_error_w;
    wire store_drain_response_valid_w;
    wire [`EDRV32_LSU_TOKEN_W-1:0] store_drain_response_token_w;
    wire store_drain_response_error_w;

    // Decoupled MDU request, result and single-slot scoreboard channels.
    wire [4:0] mdu_hazard_rs1_w;
    wire mdu_hazard_uses_rs1_w;
    wire [4:0] mdu_hazard_rs2_w;
    wire mdu_hazard_uses_rs2_w;
    wire [4:0] mdu_hazard_rd_w;
    wire mdu_hazard_rd_write_w;
    wire mdu_raw_hazard_w;
    wire decode_mdu_rs1_w;
    wire decode_mdu_rs2_w;
    wire decode_mdu_waw_stall_w;
    wire mdu_passed_mem1_w;
    wire mdu_passed_mem2_w;
    wire mem2_mdu_pass_w;
    wire mdu_mem1_pass_w = mem1_packet_valid_w && mem1_packet_accept_w &&
        mem1_packet_mdu_token_w;
    assign mdu_raw_hazard_w = decode_mdu_rs1_w || decode_mdu_rs2_w;
    wire mdu_waw_hazard_w;
    wire mdu_scoreboard_alloc_ready_w;
    wire mdu_pending_w;
    wire [4:0] mdu_pending_rd_w;
    wire mdu_authorized_w;
    wire mdu_req_valid_w;
    wire mdu_req_ready_w;
    wire [`EDRV32_MDU_OP_W-1:0] mdu_req_op_w;
    wire [31:0] mdu_req_lhs_w;
    wire [31:0] mdu_req_rhs_w;
    wire [31:0] mdu_req_mul_lhs_w;
    wire [31:0] mdu_req_mul_rhs_w;
    wire [31:0] mdu_req_div_lhs_w;
    wire [31:0] mdu_req_div_rhs_w;
    wire [4:0] mdu_req_rd_w;
    wire mdu_req_fire_w;
    wire mdu_engine_req_ready_w;
    wire mdu_result_valid_w;
    wire mdu_result_ready_w;
    wire [4:0] mdu_result_rd_w;
    wire [31:0] mdu_result_data_w;
    wire mdu_slot_valid_w;
    wire mdu_result_complete_w;
    wire mdu_authorize_w;
    wire mdu_cancel_w;
    wire mdu_writeback_fire_w;

    // Control-flow recovery, predictor query/update and performance events.
    wire ex_redirect_valid_w;
    wire ex_redirect_ready_w;
    wire [31:0] ex_redirect_target_w;
    wire ex_kill_younger_w;
    wire ex_direction_mispredict_w;
    wire ex_target_mispredict_w;
    wire commit_redirect_exception_valid_w;
    wire [31:0] commit_redirect_exception_target_w;
    wire commit_redirect_interrupt_valid_w;
    wire [31:0] commit_redirect_interrupt_target_w;
    wire commit_redirect_mret_valid_w;
    wire [31:0] commit_redirect_mret_target_w;
    wire commit_redirect_fencei_valid_w;
    wire [31:0] commit_redirect_fencei_target_w;
    wire commit_redirect_ready_w;
    wire commit_flush_younger_lsu_w;
    wire commit_kill_younger_w;
    wire redirect_valid_w;
    wire redirect_accept_w;
    wire redirect_fire_w;
    wire [31:0] redirect_target_w;
    wire [`EDRV32_REDIRECT_REASON_W-1:0] redirect_reason_w;
    wire [`EDRV32_EPOCH_W-1:0] redirect_epoch_w;
    wire if1_predicted_taken0_w;
    wire [31:0] if1_predicted_target0_w;
    wire if1_predicted_taken1_w;
    wire [31:0] if1_predicted_target1_w;
    wire [1:0] if1_predictor_meta0_w;
    wire [1:0] if1_predictor_meta1_w;
    wire [31:0] predictor_query_pc0_w;
    wire [31:0] predictor_query_pc1_w;
    wire prediction_redirect_valid_w;
    wire [31:0] prediction_redirect_target_w;
    wire prediction_redirect_fire_w;
    wire [`EDRV32_EPOCH_W-1:0] frontend_applied_epoch_w;
    wire predictor_update_valid_w;
    wire [31:0] predictor_update_pc_w;
    wire predictor_update_is_conditional_w;
    wire predictor_update_is_unconditional_w;
    wire predictor_update_taken_w;
    wire [31:0] predictor_update_target_w;
    wire predictor_update_ras_push_w;
    wire predictor_update_ras_pop_w;
    wire [31:0] predictor_update_link_addr_w;
    wire [`EDRV32_HPM_EVENT_W-1:0] hpm_events_w;
    // Capture EX-resolved control-flow observations next to their source.
    // These bits are diagnostic only; the local boundary prevents branch
    // compare and late-load operand logic from routing directly across the
    // core into the replicated HPM event-sample banks.
    reg hpm_control_flow_r;
    reg hpm_mispredict_r;
    reg hpm_direction_miss_r;
    reg hpm_target_miss_r;
    reg hpm_ras_push_r;
    reg hpm_ras_pop_r;
    reg [7:0] hpm_branch_diag_r;
    // Mutual-exclusion attribution observation inputs.
    wire commit_hpm_busy_memory_w;
    wire commit_hpm_busy_other_w;
    wire decode_hpm_stall_resident_w;
    wire decode_hpm_stall_load_w;
    wire decode_hpm_stall_mdu_w;
    wire [1:0] decode_hpm_candidate_class_w;
    wire if1_hpm_tag_nonempty_w;
    wire if2_hpm_append_hw1_w;
    wire if2_hpm_append_hw2_w;
    wire if2_hpm_consume_hw1_w;
    wire if2_hpm_consume_hw2_w;
    wire if2_hpm_discard_block_w;
    wire if2_hpm_pred_append_slot0_w;
    wire if2_hpm_pred_append_slot1_w;
    wire if2_hpm_pred_append_cross_w;
    wire if2_hpm_pred_candidate_w;
    wire if2_hpm_discard_stale_w;
    wire if2_hpm_discard_arch_redirect_w;
    wire if2_hpm_discard_pred_redirect_w;
    wire [(`EDRV32_HPM_EVENT_W-40)-1:0] hpm_attribution_events_w;
    // Age-qualified control domains and timing cut:
    // - an EX event immediately closes only DECODE->EX, the nearest boundary;
    //   no younger uop can enter EX on the redirecting instruction's edge;
    // - a COMMIT event immediately clears every younger backend boundary and
    //   also closes DECODE->EX;
    // - the registered redirect application clears the remaining frontend
    //   boundaries one cycle later.  Those entries are quarantined behind the
    //   already-closed DECODE->EX boundary and cannot create side effects.
    // This prevents the EX compare from becoming a multi-stage frontend
    // kill/ready/write-enable path while preserving age-correct squash.
    wire frontend_kill_w = redirect_fire_w;
    wire decode_to_ex_kill_w = ex_kill_younger_w ||
                               commit_kill_younger_w ||
                               redirect_fire_w;
    wire fetch_second_window_valid_w;
    wire fetch_second_window_accept_w;
    wire [15:0]                      fetch_second_halfword0_w;
    wire [15:0]                      fetch_second_halfword1_w;
    wire                             fetch_second_halfword1_valid_w;
    wire [31:0]                      fetch_second_pc_w;
    wire                             fetch_second_halfword0_error_w;
    wire                             fetch_second_halfword1_error_w;
    wire [`EDRV32_EPOCH_W-1:0]       fetch_second_epoch_w;
    wire                             fetch_second_predicted_taken_w;
    wire [31:0]                      fetch_second_predicted_target_w;
    wire [1:0]                       fetch_second_predictor_meta_w;

    // ========================================================================
    // Front end: prediction, IF1 request tracking, IF2 buffering and ALIGN
    // ========================================================================
    edrv32_branch_predictor #(
        .RAS_DEPTH(RAS_DEPTH),
        .FETCH_WIDE(FETCH_WIDE)
    ) u_branch_predictor (
        // Predictor state control.
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .invalidate_i(fencei_retire_o),

        // Two possible instruction starts in the current fetch block.
        .query_pc0_i(predictor_query_pc0_w),
        .predicted_taken0_o(if1_predicted_taken0_w),
        .predicted_target0_o(if1_predicted_target0_w),
        .query_meta0_o(if1_predictor_meta0_w),
        .query_pc1_i(predictor_query_pc1_w),
        .predicted_taken1_o(if1_predicted_taken1_w),
        .predicted_target1_o(if1_predicted_target1_w),
        .query_meta1_o(if1_predictor_meta1_w),

        .query_pc2_i(predictor_query_pc2_w),
        .predicted_taken2_o(if1_predicted_taken2_w),
        .predicted_target2_o(if1_predicted_target2_w),
        .query_meta2_o(if1_predictor_meta2_w),
        .query_pc3_i(predictor_query_pc3_w),
        .predicted_taken3_o(if1_predicted_taken3_w),
        .predicted_target3_o(if1_predicted_target3_w),
        .query_meta3_o(if1_predictor_meta3_w),

        // Resolved branch or jump from EX.
        .update_valid_i(predictor_update_valid_w),
        .update_pc_i(predictor_update_pc_w),
        .update_is_conditional_i(predictor_update_is_conditional_w),
        .update_is_unconditional_i(predictor_update_is_unconditional_w),
        .update_is_indirect_i(decode_instr_w[6:0] == 7'b1100111),
        .update_taken_i(predictor_update_taken_w),
        .update_target_i(predictor_update_target_w),
        .update_ras_push_i(predictor_update_ras_push_w),
        .update_ras_pop_i(predictor_update_ras_pop_w),
        .update_link_addr_i(predictor_update_link_addr_w)
    );

    edrv32_if1_stage #(
        .RESET_PC(RESET_PC),
        .FETCH_WIDE(FETCH_WIDE)
    ) u_if1_stage (
        .lookup_req_words_i(imem_req_words_i),
        .lookup_resp_upper_i(imem_resp_upper_i),
        .lookup_preview_upper_i(imem_preview_upper_i),
        .block_upper_o(fetch_block_upper_w),
        .block_words_o(fetch_block_words_w),
        .predictor_query_pc2_o(predictor_query_pc2_w),
        .predicted_taken2_i(if1_predicted_taken2_w),
        .predicted_target2_i(if1_predicted_target2_w),
        .predictor_meta2_i(if1_predictor_meta2_w),
        .block_predicted_taken2_o(fetch_block_predicted_taken2_w),
        .block_predicted_target2_o(fetch_block_predicted_target2_w),
        .block_predictor_meta2_o(fetch_block_predictor_meta2_w),
        .predictor_query_pc3_o(predictor_query_pc3_w),
        .predicted_taken3_i(if1_predicted_taken3_w),
        .predicted_target3_i(if1_predicted_target3_w),
        .predictor_meta3_i(if1_predictor_meta3_w),
        .block_predicted_taken3_o(fetch_block_predicted_taken3_w),
        .block_predicted_target3_o(fetch_block_predicted_target3_w),
        .block_predictor_meta3_o(fetch_block_predictor_meta3_w),

        .clk_i(clk_i),
        .rst_n_i(rst_n_i),

        // Predictor lookup for both possible starts in this fetch block.
        .predictor_query_pc0_o(predictor_query_pc0_w),
        .predictor_query_pc1_o(predictor_query_pc1_w),
        .predicted_taken0_i(if1_predicted_taken0_w),
        .predicted_target0_i(if1_predicted_target0_w),
        .predictor_meta0_i(if1_predictor_meta0_w),
        .predicted_taken1_i(if1_predicted_taken1_w),
        .predicted_target1_i(if1_predicted_target1_w),
        .predictor_meta1_i(if1_predictor_meta1_w),

        // Architectural recovery redirect.
        .redirect_valid_i(redirect_valid_w),
        .redirect_accept_o(redirect_accept_w),
        .redirect_fire_o(redirect_fire_w),
        .redirect_target_i(redirect_target_w),
        .redirect_epoch_i(redirect_epoch_w),

        // Early redirect from a predicted-taken instruction.
        .prediction_redirect_valid_i(prediction_redirect_valid_w),
        .prediction_redirect_target_i(prediction_redirect_target_w),
        .prediction_redirect_fast_i(prediction_redirect_fast_w),
        .prediction_redirect_fast_slot1_i(
            prediction_redirect_fast_slot1_w),
        .prediction_redirect_fire_o(prediction_redirect_fire_w),
        .applied_redirect_epoch_o(frontend_applied_epoch_w),

        // Instruction-memory lookup transaction.
        .lookup_req_valid_o(imem_req_valid_o),
        .lookup_req_ready_i(imem_req_ready_i),
        .lookup_req_addr_o(imem_req_addr_o),
        .lookup_resp_valid_i(imem_resp_valid_i),
        .lookup_resp_ready_o(imem_resp_ready_o),
        .lookup_resp_data_i(imem_resp_rdata_i),
        .lookup_resp_error_i(imem_resp_error_i),
        .lookup_preview_valid_i(imem_preview_valid_i &&
                                (CACHE_ENABLE != 0)),
        .lookup_preview_addr_i(imem_preview_addr_i),
        .lookup_preview_data_i(imem_preview_data_i),

        // Registered request identity paired with the returned block.
        .block_valid_o(fetch_block_valid_w),
        .block_ready_i(fetch_block_ready_w),
        .block_addr_o(fetch_block_addr_w),
        .block_data_o(fetch_block_data_w),
        .block_error_o(fetch_block_error_w),
        .block_epoch_o(fetch_block_epoch_w),
        .block_predicted_taken0_o(fetch_block_predicted_taken0_w),
        .block_predicted_target0_o(fetch_block_predicted_target0_w),
        .block_predictor_meta0_o(fetch_block_predictor_meta0_w),
        .block_predicted_taken1_o(fetch_block_predicted_taken1_w),
        .block_predicted_target1_o(fetch_block_predicted_target1_w),
        .block_predictor_meta1_o(fetch_block_predictor_meta1_w),
        .preview_valid_o(fetch_preview_valid_w),
        .preview_addr_o(fetch_preview_addr_w),
        .preview_epoch_o(fetch_preview_epoch_w),
        .preview_target0_o(fetch_preview_target0_w),
        .preview_target1_o(fetch_preview_target1_w),

        .hpm_tag_nonempty_o(if1_hpm_tag_nonempty_w)
    );

    edrv32_if2_stage #(
        .RESET_PC(RESET_PC),
        .DUAL_WINDOW(PAIR_FRONTEND_ENABLE),
        .FETCH_WIDE(FETCH_WIDE)
    ) u_if2_stage (
        .block_upper_i(fetch_block_upper_w),
        .block_words_i(fetch_block_words_w),
        .hpm_second_append_hw2_o(if2_hpm_second_append_hw2_w),
        .block_predicted_taken2_i(fetch_block_predicted_taken2_w),
        .block_predicted_target2_i(fetch_block_predicted_target2_w),
        .block_predictor_meta2_i(fetch_block_predictor_meta2_w),
        .block_predicted_taken3_i(fetch_block_predicted_taken3_w),
        .block_predicted_target3_i(fetch_block_predicted_target3_w),
        .block_predictor_meta3_i(fetch_block_predictor_meta3_w),

        .clk_i(clk_i),
        .rst_n_i(rst_n_i),

        // Returned fetch block.
        .block_valid_i(fetch_block_valid_w),
        .block_ready_o(fetch_block_ready_w),
        .block_addr_i(fetch_block_addr_w),
        .block_data_i(fetch_block_data_w),
        .block_error_i(fetch_block_error_w),
        .block_epoch_i(fetch_block_epoch_w),
        .block_predicted_taken0_i(fetch_block_predicted_taken0_w),
        .block_predicted_target0_i(fetch_block_predicted_target0_w),
        .block_predictor_meta0_i(fetch_block_predictor_meta0_w),
        .block_predicted_taken1_i(fetch_block_predicted_taken1_w),
        .block_predicted_target1_i(fetch_block_predicted_target1_w),
        .block_predictor_meta1_i(fetch_block_predictor_meta1_w),
        .preview_valid_i(fetch_preview_valid_w),
        .preview_addr_i(fetch_preview_addr_w),
        .preview_epoch_i(fetch_preview_epoch_w),
        .preview_target0_i(fetch_preview_target0_w),
        .preview_target1_i(fetch_preview_target1_w),

        // Registered halfword window presented to ALIGN.
        .window_valid_o(fetch_window_valid_w),
        .window_ready_i(fetch_window_pipe_accept_w),
        .halfword0_o(fetch_halfword0_w),
        .halfword1_o(fetch_halfword1_w),
        .halfword1_valid_o(fetch_halfword1_valid_w),
        .window_pc_o(fetch_window_pc_w),
        .halfword0_error_o(fetch_halfword0_error_w),
        .halfword1_error_o(fetch_halfword1_error_w),
        .window_epoch_o(fetch_window_epoch_w),
        .window_predicted_taken_o(fetch_window_predicted_taken_w),
        .window_predicted_target_o(fetch_window_predicted_target_w),
        .window_predictor_meta_o(fetch_window_predictor_meta_w),

        .second_window_valid_o(fetch_second_window_valid_w),
        .second_window_accept_i(fetch_second_window_accept_w),
        .second_halfword0_o(fetch_second_halfword0_w),
        .second_halfword1_o(fetch_second_halfword1_w),
        .second_halfword1_valid_o(fetch_second_halfword1_valid_w),
        .second_window_pc_o(fetch_second_pc_w),
        .second_halfword0_error_o(fetch_second_halfword0_error_w),
        .second_halfword1_error_o(fetch_second_halfword1_error_w),
        .second_window_epoch_o(fetch_second_epoch_w),
        .second_window_predicted_taken_o(fetch_second_predicted_taken_w),
        .second_window_predicted_target_o(fetch_second_predicted_target_w),
        .second_window_predictor_meta_o(fetch_second_predictor_meta_w),
        .hpm_consume_halfwords_o(),

        // Prediction redirect generated on the internal window capture.
        .prediction_redirect_valid_o(prediction_redirect_valid_w),
        .prediction_redirect_target_o(prediction_redirect_target_w),
        .prediction_redirect_fast_o(prediction_redirect_fast_w),
        .prediction_redirect_fast_slot1_o(
            prediction_redirect_fast_slot1_w),
        .prediction_redirect_fire_i(prediction_redirect_fire_w),
        .prediction_redirect_epoch_i(frontend_applied_epoch_w),

        // Fetch accounting for the useful/discarded-fetch HPM events.
        .hpm_append_hw1_o(if2_hpm_append_hw1_w),
        .hpm_append_hw2_o(if2_hpm_append_hw2_w),
        .hpm_consume_hw1_o(if2_hpm_consume_hw1_w),
        .hpm_consume_hw2_o(if2_hpm_consume_hw2_w),
        .hpm_second_consume_hw1_o(if2_hpm_second_consume_hw1_w),
        .hpm_second_consume_hw2_o(if2_hpm_second_consume_hw2_w),
        .hpm_discard_block_o(if2_hpm_discard_block_w),
        .hpm_pred_append_slot0_o(if2_hpm_pred_append_slot0_w),
        .hpm_pred_append_slot1_o(if2_hpm_pred_append_slot1_w),
        .hpm_pred_append_cross_o(if2_hpm_pred_append_cross_w),
        .hpm_pred_candidate_o(if2_hpm_pred_candidate_w),
        .hpm_discard_stale_o(if2_hpm_discard_stale_w),
        .hpm_discard_arch_redirect_o(if2_hpm_discard_arch_redirect_w),
        .hpm_discard_pred_redirect_o(if2_hpm_discard_pred_redirect_w),

        // Architectural and predicted stream changes.
        .redirect_fire_i(redirect_fire_w),
        .redirect_target_i(redirect_target_w),
        .redirect_epoch_i(frontend_applied_epoch_w),
        .kill_i(frontend_kill_w)
    );

    generate
        if (PAIR_FRONTEND_ENABLE != 0) begin : gen_pair_frontend
            edrv32_align_pair_stage u_align_stage (
                .clk_i(clk_i),
                .second_window_valid_i(fetch_second_window_valid_w),
                .second_window_accept_o(fetch_second_window_accept_w),
                .second_halfword0_i(fetch_second_halfword0_w),
                .second_halfword1_i(fetch_second_halfword1_w),
                .second_halfword1_valid_i(fetch_second_halfword1_valid_w),
                .second_pc_i(fetch_second_pc_w),
                .second_halfword0_error_i(fetch_second_halfword0_error_w),
                .second_halfword1_error_i(fetch_second_halfword1_error_w),
                .second_epoch_i(fetch_second_epoch_w),
                .second_predicted_taken_i(fetch_second_predicted_taken_w),
                .second_predicted_target_i(fetch_second_predicted_target_w),
                .second_predictor_meta_i(fetch_second_predictor_meta_w),
                .second_valid_o(align_second_valid_w),
                .second_ready_i(align_second_accept_w),
                .second_pc_o(align_second_pc_w),
                .second_instr_o(align_second_instr_w),
                .second_raw_instr_o(align_second_raw_instr_w),
                .second_is_compressed_o(align_second_is_compressed_w),
                .second_fetch_fault_o(align_second_fetch_fault_w),
                .second_compressed_illegal_o(align_second_compressed_illegal_w),
                .second_epoch_o(align_second_epoch_w),
                .second_predicted_taken_o(align_second_predicted_taken_w),
                .second_predicted_target_o(align_second_predicted_target_w),
                .second_predictor_meta_o(align_second_predictor_meta_w),
                .rst_n_i(rst_n_i),

                // Oldest registered halfword window.
                .window_valid_i(fetch_window_valid_w),
                .window_accept_o(fetch_window_pipe_accept_w),
                .halfword0_i(fetch_halfword0_w),
                .halfword1_i(fetch_halfword1_w),
                .halfword1_valid_i(fetch_halfword1_valid_w),
                .pc_i(fetch_window_pc_w),
                .halfword0_error_i(fetch_halfword0_error_w),
                .halfword1_error_i(fetch_halfword1_error_w),
                .epoch_i(fetch_window_epoch_w),
                .predicted_taken_i(fetch_window_predicted_taken_w),
                .predicted_target_i(fetch_window_predicted_target_w),
                .predictor_meta_i(fetch_window_predictor_meta_w),
                // Registered canonical instruction presented to DECODE.
                .valid_o(align_valid_w),
                .ready_i(align_accept_w),
                .pc_o(align_pc_w),
                .instr_o(align_instr_w),
                .raw_instr_o(align_raw_instr_w),
                .is_compressed_o(align_is_compressed_w),
                .fetch_fault_o(align_fetch_fault_w),
                .compressed_illegal_o(align_compressed_illegal_w),
                .epoch_o(align_epoch_w),
                .predicted_taken_o(align_predicted_taken_w),
                .predicted_target_o(align_predicted_target_w),
                .predictor_meta_o(align_predictor_meta_w),

                .kill_i(frontend_kill_w)
            );
        end else begin : gen_scalar_frontend
            assign fetch_second_window_accept_w = 1'b0;
            assign align_second_valid_w = 1'd0;
            assign align_second_pc_w = 32'd0;
            assign align_second_instr_w = 32'd0;
            assign align_second_raw_instr_w = 32'd0;
            assign align_second_is_compressed_w = 1'd0;
            assign align_second_fetch_fault_w = 1'd0;
            assign align_second_compressed_illegal_w = 1'd0;
            assign align_second_epoch_w = `EDRV32_EPOCH_W'd0;
            assign align_second_predicted_taken_w = 1'd0;
            assign align_second_predicted_target_w = 32'd0;
            assign align_second_predictor_meta_w = 2'd0;

            edrv32_align_stage u_align_stage (
                .clk_i(clk_i),
                .rst_n_i(rst_n_i),

                // Oldest registered halfword window.
                .window_valid_i(fetch_window_valid_w),
                .window_ready_o(),
                .window_accept_o(fetch_window_pipe_accept_w),
                .window_halfwords_o(),
                .halfword0_i(fetch_halfword0_w),
                .halfword1_i(fetch_halfword1_w),
                .halfword1_valid_i(fetch_halfword1_valid_w),
                .pc_i(fetch_window_pc_w),
                .halfword0_error_i(fetch_halfword0_error_w),
                .halfword1_error_i(fetch_halfword1_error_w),
                .epoch_i(fetch_window_epoch_w),
                .predicted_taken_i(fetch_window_predicted_taken_w),
                .predicted_target_i(fetch_window_predicted_target_w),
                .predictor_meta_i(fetch_window_predictor_meta_w),
                // Registered canonical instruction presented to DECODE.
                .valid_o(align_valid_w),
                .ready_i(align_accept_w),
                .pc_o(align_pc_w),
                .instr_o(align_instr_w),
                .raw_instr_o(align_raw_instr_w),
                .is_compressed_o(align_is_compressed_w),
                .fetch_fault_o(align_fetch_fault_w),
                .compressed_illegal_o(align_compressed_illegal_w),
                .epoch_o(align_epoch_w),
                .predicted_taken_o(align_predicted_taken_w),
                .predicted_target_o(align_predicted_target_w),
                .predictor_meta_o(align_predictor_meta_w),

                .kill_i(frontend_kill_w)
            );
        end
    endgenerate

    // ========================================================================
    // Decode: register-file access, bypass selection and dependency checks
    // ========================================================================
    edrv32_decode_stage #(.DUAL_ISSUE(DUAL_ISSUE)) u_decode_stage (
        .resident_second_rs1_o(decode_resident_second_rs1_w),
        .resident_second_rs2_o(decode_resident_second_rs2_w),
        .second_valid_i(align_second_valid_w),
        .second_pc_i(align_second_pc_w),
        .second_instr_i(align_second_instr_w),
        .second_raw_instr_i(align_second_raw_instr_w),
        .second_is_compressed_i(align_second_is_compressed_w),
        .second_fetch_fault_i(align_second_fetch_fault_w),
        .second_compressed_illegal_i(align_second_compressed_illegal_w),
        .second_epoch_i(align_second_epoch_w),
        .second_predicted_taken_i(align_second_predicted_taken_w),
        .second_predicted_target_i(align_second_predicted_target_w),
        .second_predictor_meta_i(align_second_predictor_meta_w),
        .second_ready_o(align_second_accept_w),
        .second_o(decode_second_w),
        .commit_second_write_i(commit_second_write_w),
        .commit_second_rd_i(commit_second_rd_w),
        .commit_second_value_i(commit_second_value_w),
        .ex_second_i(ex_second_w),
        .mem1_second_i(mem1_second_w),
        .mem2_second_i(mem2_second_w),
        .commit_second_i(commit_second_w),

        .clk_i(clk_i),
        .rst_n_i(rst_n_i),

        // Instruction waiting at the ALIGN/DECODE boundary.
        .valid_i(align_valid_w),
        .ready_o(align_accept_w),
        .pc_i(align_pc_w),
        .instr_i(align_instr_w),
        .raw_instr_i(align_raw_instr_w),
        .is_compressed_i(align_is_compressed_w),
        .fetch_fault_i(align_fetch_fault_w),
        .compressed_illegal_i(align_compressed_illegal_w),
        .epoch_i(align_epoch_w),
        .predicted_taken_i(align_predicted_taken_w),
        .predicted_target_i(align_predicted_target_w),
        .predictor_meta_i(align_predictor_meta_w),

        // Architectural register-file writeback.
        .commit_rd_write_i(commit_gpr_write_w),
        .commit_rd_i(commit_gpr_rd_w),
        .commit_rd_value_i(commit_gpr_value_w),

        // Youngest-to-oldest producer records used by operand bypassing.
        .ex_bypass_valid_i(ex_valid_w),
        .ex_bypass_write_i(ex_rd_write_w),
        .ex_bypass_ready_i(ex_result_ready_w),
        .ex_bypass_is_load_i(ex_bypass_is_load_w),
        .ex_bypass_mdu_token_i(ex_mdu_token_w),
        .ex_bypass_pc_i(ex_pc_w),
        .ex_bypass_rd_i(ex_rd_w),
        .ex_bypass_value_i(ex_result_w),
        .ex_bypass_lsu_token_valid_i(load_alloc_valid_w),
        .ex_bypass_lsu_token_i(load_alloc_token_w),

        .mem1_bypass_valid_i(mem1_packet_valid_w),
        .mem1_bypass_write_i(mem1_packet_rd_write_w),
        .mem1_bypass_ready_i(mem1_packet_result_ready_w),
        .mem1_bypass_is_load_i(mem1_bypass_is_load_w),
        .mem1_bypass_pc_i(mem1_packet_pc_w),
        .mem1_bypass_rd_i(mem1_packet_rd_w),
        .mem1_bypass_value_i(mem1_packet_result_w),
        .mem1_bypass_lsu_token_valid_i(
            mem1_packet_lsu_token_valid_w &&
            (mem1_packet_op_class_w == `EDRV32_OP_LOAD)),
        .mem1_bypass_lsu_token_i(mem1_packet_lsu_token_w),

        .mem2_bypass_valid_i(mem2_hazard_valid_w),
        .mem2_bypass_write_i(mem2_hazard_write_w),
        .mem2_bypass_ready_i(mem2_hazard_effective_ready_w),
        .mem2_bypass_is_load_i(mem2_bypass_is_load_w),
        .mem2_bypass_pc_i(mem2_hazard_pc_w),
        .mem2_bypass_rd_i(mem2_hazard_rd_w),
        .mem2_bypass_value_i(mem2_hazard_effective_value_w),
        .mem2_bypass_lsu_token_valid_i(
            mem2_hazard_lsu_token_valid_w && mem2_hazard_late_load_w),
        .mem2_bypass_lsu_token_i(mem2_hazard_lsu_token_w),

        .commit_bypass_valid_i(commit_bypass_valid_w),
        .commit_bypass_write_i(commit_bypass_write_w),
        .commit_bypass_ready_i(commit_bypass_ready_w),
        .commit_bypass_rd_i(commit_bypass_rd_w),
        .commit_bypass_value_i(commit_bypass_value_w),

        // The scoreboard remains the MDU producer identity until writeback;
        // the registered arithmetic-complete bit changes a RAW match from a
        // wait into an operand bypass without exposing COMMIT authorization.
        .mdu_bypass_valid_i(mdu_pending_w),
        .mdu_bypass_ready_i(mdu_slot_valid_w && mdu_result_complete_w),
        .mdu_bypass_rd_i(mdu_pending_rd_w),
        .mdu_bypass_value_i(mdu_result_data_w),
        .mdu_passed_mem1_i(mdu_passed_mem1_w),
        .mdu_passed_mem2_i(mdu_passed_mem2_w),
        .mdu_authorized_i(mdu_authorized_w),

        // Long-latency MDU and downstream capacity constraints.
        .mdu_waw_hazard_i(mdu_waw_hazard_w),
        .mdu_issue_ready_i(mdu_req_ready_w),
        .issue_block_i(mem1_to_mem2_full_w),

        // Register identities exported to the MDU scoreboard.
        .hazard_rs1_addr_o(mdu_hazard_rs1_w),
        .hazard_uses_rs1_o(mdu_hazard_uses_rs1_w),
        .hazard_rs2_addr_o(mdu_hazard_rs2_w),
        .hazard_uses_rs2_o(mdu_hazard_uses_rs2_w),
        .hazard_rd_addr_o(mdu_hazard_rd_w),
        .hazard_rd_write_o(mdu_hazard_rd_write_w),

        // Visible reasons why this instruction cannot advance.
        .dependency_stall_o(decode_dependency_stall_w),
        .structural_stall_o(decode_structural_stall_w),
        .hpm_stall_resident_o(decode_hpm_stall_resident_w),
        .hpm_stall_load_o(decode_hpm_stall_load_w),
        .hpm_stall_mdu_o(decode_hpm_stall_mdu_w),
        .hpm_stall_waw_o(decode_mdu_waw_stall_w),
        .hazard_mdu_rs1_o(decode_mdu_rs1_w),
        .hazard_mdu_rs2_o(decode_mdu_rs2_w),
        .hpm_candidate_class_o(decode_hpm_candidate_class_w),

        // Registered decoded uop presented to EX.
        .valid_o(decode_valid_w),
        .ready_i(decode_accept_w),
        .pc_o(decode_pc_w),
        .instr_o(decode_instr_w),
        .is_compressed_o(decode_is_compressed_w),
        .epoch_o(decode_epoch_w),
        .predicted_taken_o(decode_predicted_taken_w),
        .predicted_target_o(decode_predicted_target_w),
        .predictor_meta_o(decode_predictor_meta_w),
        .rd_o(decode_rd_w),
        .rd_write_o(decode_rd_write_w),
        .op_class_o(decode_op_class_w),
        .alu_op_o(decode_alu_op_w),
        .branch_op_o(decode_branch_op_w),
        .mem_size_o(decode_mem_size_w),
        .mem_unsigned_o(decode_mem_unsigned_w),
        .mdu_op_o(decode_mdu_op_w),
        .csr_op_o(decode_csr_op_w),
        .csr_addr_o(decode_csr_addr_w),
        .csr_src_o(decode_csr_src_w),
        .lhs_o(decode_lhs_w),
        .rhs_o(decode_rhs_w),
        .rs2_value_o(decode_rs2_value_w),
        .resident_bypass_rs1_o(decode_resident_bypass_rs1_w),
        .resident_bypass_rs2_o(decode_resident_bypass_rs2_w),
        .resident_bypass_pc_o(decode_resident_bypass_pc_w),
        .late_mdu_rs1_o(decode_late_mdu_rs1_w),
        .late_mdu_rs2_o(decode_late_mdu_rs2_w),
        .late_load_rs1_o(decode_late_load_rs1_w),
        .late_load_rs2_o(decode_late_load_rs2_w),
        .late_load_rs1_pc_o(decode_late_load_rs1_pc_w),
        .late_load_rs2_pc_o(decode_late_load_rs2_pc_w),
        .late_load_rs1_token_valid_o(
            decode_late_load_rs1_token_valid_w),
        .late_load_rs1_token_o(decode_late_load_rs1_token_w),
        .late_load_rs2_token_valid_o(
            decode_late_load_rs2_token_valid_w),
        .late_load_rs2_token_o(decode_late_load_rs2_token_w),
        .imm_o(decode_imm_w),
        .fence_o(decode_fence_w),
        .fencei_o(decode_fencei_w),
        .mret_o(decode_mret_w),
        .wfi_o(decode_wfi_w),
        .exception_valid_o(decode_exception_valid_w),
        .exception_cause_o(decode_exception_cause_w),
        .exception_tval_o(decode_exception_tval_w),

        .frontend_kill_i(frontend_kill_w),
        .boundary_kill_i(decode_to_ex_kill_w)
    );

    // ========================================================================
    // Execute: scalar ALU, control-flow resolution and MDU dispatch
    // ========================================================================
    edrv32_ex_stage #(
        .DUAL_ISSUE(DUAL_ISSUE),
        .MUL_CAPTURE_LIVE_LOAD(MUL_LOW_PIPE_STAGES == 1)
    ) u_ex_stage (
        .resident_second_rs1_i(decode_resident_second_rs1_w),
        .resident_second_rs2_i(decode_resident_second_rs2_w),
        .second_i(decode_second_w),
        .result_second_o(ex_second_w),
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),

        // Resident decoded packet.
        .valid_i(decode_valid_w),
        .ready_o(decode_accept_w),
        .pc_i(decode_pc_w),
        .instr_i(decode_instr_w),
        .is_compressed_i(decode_is_compressed_w),
        .epoch_i(decode_epoch_w),
        .predicted_taken_i(decode_predicted_taken_w),
        .predicted_target_i(decode_predicted_target_w),
        .rd_i(decode_rd_w),
        .rd_write_i(decode_rd_write_w),
        .op_class_i(decode_op_class_w),
        .alu_op_i(decode_alu_op_w),
        .branch_op_i(decode_branch_op_w),
        .mem_size_i(decode_mem_size_w),
        .mem_unsigned_i(decode_mem_unsigned_w),
        .mdu_op_i(decode_mdu_op_w),
        .csr_op_i(decode_csr_op_w),
        .csr_addr_i(decode_csr_addr_w),
        .csr_src_i(decode_csr_src_w),
        .lhs_i(decode_lhs_w),
        .rhs_i(decode_rhs_w),
        .rs2_value_i(decode_rs2_value_w),
        .resident_bypass_rs1_i(decode_resident_bypass_rs1_w),
        .resident_bypass_rs2_i(decode_resident_bypass_rs2_w),
        .resident_bypass_pc_i(decode_resident_bypass_pc_w),
        .late_mdu_rs1_i(decode_late_mdu_rs1_w),
        .late_mdu_rs2_i(decode_late_mdu_rs2_w),
        .late_load_rs1_i(decode_late_load_rs1_w),
        .late_load_rs2_i(decode_late_load_rs2_w),
        .late_load_rs1_pc_i(decode_late_load_rs1_pc_w),
        .late_load_rs2_pc_i(decode_late_load_rs2_pc_w),
        .late_load_rs1_token_valid_i(
            decode_late_load_rs1_token_valid_w),
        .late_load_rs2_token_valid_i(
            decode_late_load_rs2_token_valid_w),
        .imm_i(decode_imm_w),
        .fence_i(decode_fence_w),
        .fencei_i(decode_fencei_w),
        .mret_i(decode_mret_w),
        .wfi_i(decode_wfi_w),
        .exception_valid_i(decode_exception_valid_w),
        .exception_cause_i(decode_exception_cause_w),
        .exception_tval_i(decode_exception_tval_w),

        .load_bypass_valid_i(commit_load_bypass_valid_w),
        .load_bypass_pc_i(mem2_packet_pc_w),
        .load_bypass_value_i(commit_bypass_value_w),
        .load_queue_rs1_ready_i(load_probe_rs1_ready_w),
        .load_queue_rs1_value_i(load_probe_rs1_value_w),
        .load_queue_rs1_stored_ready_i(load_probe_rs1_stored_ready_w),
        .load_queue_rs1_stored_value_i(load_probe_rs1_stored_value_w),
        .load_queue_rs2_ready_i(load_probe_rs2_ready_w),
        .load_queue_rs2_value_i(load_probe_rs2_value_w),
        .load_queue_rs2_stored_ready_i(load_probe_rs2_stored_ready_w),
        .load_queue_rs2_stored_value_i(load_probe_rs2_stored_value_w),
        .result_bypass_valid_i(ex_valid_w),
        .result_bypass_ready_i(ex_result_ready_w),
        .result_bypass_pc_i(ex_pc_w),
        .result_bypass_value_i(ex_result_w),
        .late_load_stall_o(ex_late_load_stall_w),
        .mdu_bypass_valid_i(mdu_slot_valid_w && mdu_result_complete_w),
        .mdu_bypass_value_i(mdu_result_data_w),
        .late_mdu_stall_o(ex_late_mdu_stall_w),

        // Resolved control-flow redirect.
        .redirect_valid_o(ex_redirect_valid_w),
        .redirect_ready_i(ex_redirect_ready_w),
        .redirect_target_o(ex_redirect_target_w),
        .younger_kill_o(ex_kill_younger_w),
        .direction_mispredict_o(ex_direction_mispredict_w),
        .target_mispredict_o(ex_target_mispredict_w),

        // Predictor training from the resolved branch or jump.
        .predictor_update_valid_o(predictor_update_valid_w),
        .predictor_update_pc_o(predictor_update_pc_w),
        .predictor_update_is_conditional_o(predictor_update_is_conditional_w),
        .predictor_update_is_unconditional_o(predictor_update_is_unconditional_w),
        .predictor_update_taken_o(predictor_update_taken_w),
        .predictor_update_target_o(predictor_update_target_w),
        .predictor_update_ras_push_o(predictor_update_ras_push_w),
        .predictor_update_ras_pop_o(predictor_update_ras_pop_w),
        .predictor_update_link_addr_o(predictor_update_link_addr_w),

        // Long-latency multiply/divide request.
        .mdu_req_valid_o(mdu_req_valid_w),
        .mdu_req_ready_i(mdu_req_ready_w),
        .mdu_req_op_o(mdu_req_op_w),
        .mdu_req_lhs_o(mdu_req_lhs_w),
        .mdu_req_rhs_o(mdu_req_rhs_w),
        .mdu_req_mul_lhs_o(mdu_req_mul_lhs_w),
        .mdu_req_mul_rhs_o(mdu_req_mul_rhs_w),
        .mdu_req_div_lhs_o(mdu_req_div_lhs_w),
        .mdu_req_div_rhs_o(mdu_req_div_rhs_w),
        .mdu_req_rd_o(mdu_req_rd_w),
        .mdu_req_fire_o(mdu_req_fire_w),

        // Registered executed uop presented to MEM1.
        .result_valid_o(ex_valid_w),
        .result_ready_i(ex_accept_w),
        .result_pc_o(ex_pc_w),
        .result_instr_o(ex_instr_w),
        .result_is_compressed_o(ex_is_compressed_w),
        .result_epoch_o(ex_epoch_w),
        .result_rd_o(ex_rd_w),
        .result_rd_write_o(ex_rd_write_w),
        .result_op_class_o(ex_op_class_w),
        .result_value_o(ex_result_w),
        .result_value_ready_o(ex_result_ready_w),
        .result_mem_addr_o(ex_mem_addr_w),
        .result_mem_size_o(ex_mem_size_w),
        .result_mem_unsigned_o(ex_mem_unsigned_w),
        .result_store_data_o(ex_store_data_w),
        .result_mdu_token_o(ex_mdu_token_w),
        .result_csr_op_o(ex_csr_op_w),
        .result_csr_addr_o(ex_csr_addr_w),
        .result_csr_src_o(ex_csr_src_w),
        .result_fence_o(ex_fence_w),
        .result_fencei_o(ex_fencei_w),
        .result_mret_o(ex_mret_w),
        .result_wfi_o(ex_wfi_w),
        .result_exception_valid_o(ex_exception_valid_w),
        .result_exception_cause_o(ex_exception_cause_w),
        .result_exception_tval_o(ex_exception_tval_w),

        .kill_i(commit_kill_younger_w)
    );

    // ========================================================================
    // Memory pipeline: PMA classification, lookup ownership and completion
    // ========================================================================
    edrv32_load_queue u_load_queue (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .alloc_valid_i(load_alloc_valid_w),
        .alloc_ready_o(load_queue_alloc_ready_w),
        .alloc_token_o(load_alloc_token_w),
        .alloc_pc_i(load_alloc_pc_w),
        .alloc_rd_i(load_alloc_rd_w),
        .alloc_addr_i(load_alloc_addr_w),
        .alloc_size_i(load_alloc_size_w),
        .alloc_unsigned_i(load_alloc_unsigned_w),
        .alloc_epoch_i(load_alloc_epoch_w),
        .alloc_sequence_i(memory_sequence_r),
        .alloc_forward_valid_i(store_load_match_w &&
                               store_load_forward_ready_w),
        .alloc_forward_data_i(store_load_forward_data_w),
        .alloc_block_valid_i(store_load_match_w &&
                             !store_load_forward_ready_w),
        .alloc_block_token_i(store_load_match_token_w),
        .store_release_valid_i(store_release_valid_w),
        .store_release_token_i(store_release_token_w),
        .request_valid_o(load_request_valid_w),
        .request_ready_i(load_request_ready_w),
        .request_token_o(load_request_token_w),
        .request_addr_o(load_request_addr_w),
        .request_size_o(load_request_size_w),
        .request_unsigned_o(load_request_unsigned_w),
        .request_sequence_o(load_request_sequence_w),
        .pending_valid_o(load_pending_valid_w),
        .pending_sequence_o(load_pending_sequence_w),
        .response_valid_i(((dcache_lookup_fast_valid_i &&
                           !dcache_lookup_fast_store_i) ||
                         (dcache_lookup_resp_valid_i &&
                          !dcache_lookup_resp_store_i))),
        .response_ready_o(),
        .response_token_i(dcache_lookup_fast_valid_i
            ? dcache_lookup_fast_token_i : dcache_lookup_resp_token_i),
        .response_data_i(dcache_lookup_fast_valid_i
            ? dcache_lookup_fast_data_i : dcache_lookup_resp_data_i),
        .response_error_i(dcache_lookup_fast_valid_i
            ? 1'b0 : dcache_lookup_resp_error_i),
        .completion_valid_o(load_completion_valid_w),
        .completion_token_o(load_completion_token_w),
        .completion_data_o(load_completion_data_w),
        .completion_pc_o(load_completion_pc_w),
        .commit_valid_i(load_commit_valid_w),
        .commit_token_i(load_commit_token_w),
        .commit_ready_o(load_commit_ready_w),
        .commit_data_o(load_commit_data_w),
        .commit_error_o(load_commit_error_w),
        .commit_fire_i(load_commit_fire_w),
        .rs1_addr_i(5'd0), .uses_rs1_i(1'b0),
        .rs1_match_o(), .rs1_ready_o(), .rs1_token_o(),
        .rs1_pc_o(), .rs1_value_o(),
        .rs2_addr_i(5'd0), .uses_rs2_i(1'b0),
        .rs2_match_o(), .rs2_ready_o(), .rs2_token_o(),
        .rs2_pc_o(), .rs2_value_o(),
        .observe_token_valid_i(mem2_hazard_lsu_token_valid_w),
        .observe_token_i(mem2_hazard_lsu_token_w),
        .observe_match_o(load_mem2_observe_match_w),
        .observe_ready_o(load_mem2_observe_ready_w),
        .observe_value_o(load_mem2_observe_value_w),
        .operand0_token_valid_i(decode_late_load_rs1_token_valid_w),
        .operand0_token_i(decode_late_load_rs1_token_w),
        .operand0_match_o(),
        .operand0_ready_o(load_probe_rs1_ready_w),
        .operand0_value_o(load_probe_rs1_value_w),
        .operand0_stored_ready_o(load_probe_rs1_stored_ready_w),
        .operand0_stored_value_o(load_probe_rs1_stored_value_w),
        .operand1_token_valid_i(decode_late_load_rs2_token_valid_w),
        .operand1_token_i(decode_late_load_rs2_token_w),
        .operand1_match_o(),
        .operand1_ready_o(load_probe_rs2_ready_w),
        .operand1_value_o(load_probe_rs2_value_w),
        .operand1_stored_ready_o(load_probe_rs2_stored_ready_w),
        .operand1_stored_value_o(load_probe_rs2_stored_value_w),
        .probe0_pc_i(32'd0),
        .probe0_ready_o(),
        .probe0_value_o(),
        .probe1_pc_i(32'd0),
        .probe1_ready_o(),
        .probe1_value_o(),
        .flush_i(commit_kill_younger_w || commit_flush_younger_lsu_w),
        .empty_o(load_queue_empty_w),
        .full_o(load_queue_full_unused_w)
    );

    edrv32_store_queue u_store_queue (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .alloc_valid_i(store_alloc_valid_w),
        .alloc_ready_o(store_alloc_ready_w),
        .alloc_token_o(store_alloc_token_w),
        .alloc_pc_i(store_alloc_pc_w),
        .alloc_addr_i(store_alloc_addr_w),
        .alloc_wstrb_i(store_alloc_wstrb_w),
        .alloc_wdata_i(store_alloc_wdata_w),
        .alloc_epoch_i(store_alloc_epoch_w),
        .alloc_sequence_i(memory_sequence_r),
        .prepare_valid_o(store_prepare_valid_w),
        .prepare_ready_i(store_prepare_ready_w),
        .prepare_token_o(store_prepare_token_w),
        .prepare_addr_o(store_prepare_addr_w),
        .prepare_sequence_o(store_prepare_sequence_w),
        .prepare_response_valid_i(
            (dcache_lookup_fast_valid_i && dcache_lookup_fast_store_i) ||
            (dcache_lookup_resp_valid_i && dcache_lookup_resp_store_i)),
        .prepare_response_ready_o(),
        .prepare_response_token_i(dcache_lookup_fast_valid_i
            ? dcache_lookup_fast_token_i : dcache_lookup_resp_token_i),
        .prepare_response_error_i(dcache_lookup_fast_valid_i
            ? 1'b0 : dcache_lookup_resp_error_i),
        .prepare_cancel_valid_i(1'b0),
        .prepare_cancel_token_i({`EDRV32_LSU_TOKEN_W{1'b0}}),
        .commit_valid_i(store_commit_valid_w),
        .commit_token_i(store_commit_token_w),
        .commit_ready_o(store_commit_ready_w),
        .commit_error_o(store_commit_error_w),
        .commit_fire_i(store_commit_fire_w),
        .drain_valid_o(store_drain_valid_w),
        .drain_ready_i(store_drain_ready_w),
        .drain_token_o(store_drain_token_w),
        .drain_addr_o(store_drain_addr_w),
        .drain_wstrb_o(store_drain_wstrb_w),
        .drain_wdata_o(store_drain_wdata_w),
        .drain_response_valid_i(store_drain_response_valid_w),
        .drain_response_ready_o(),
        .drain_response_token_i(store_drain_response_token_w),
        .drain_response_error_i(store_drain_response_error_w),
        .async_error_o(),
        .load_query_valid_i(load_alloc_valid_w),
        .load_query_addr_i(load_alloc_addr_w),
        .load_query_size_i(load_alloc_size_w),
        .load_query_unsigned_i(load_alloc_unsigned_w),
        .load_match_o(store_load_match_w),
        .load_forward_ready_o(store_load_forward_ready_w),
        .load_forward_data_o(store_load_forward_data_w),
        .load_match_token_o(store_load_match_token_w),
        .release_valid_o(store_release_valid_w),
        .release_token_o(store_release_token_w),
        .flush_i(commit_kill_younger_w || commit_flush_younger_lsu_w),
        .empty_o(store_queue_empty_w),
        .full_o(store_queue_full_unused_w),
        .committed_empty_o(store_committed_empty_w),
        .committed_reservation_count_o(
            store_committed_reservation_count_w)
    );

    // MEM1 observes only registered queue capacity.  A partial store overlap
    // allocates a blocked Load Queue entry and is later released by the
    // matching committed-store drain token; address comparison never enters
    // the backward stage-ready cone.
    assign load_alloc_ready_w = load_queue_alloc_ready_w;

    wire load_alloc_fire_w = load_alloc_valid_w && load_alloc_ready_w;
    wire store_alloc_fire_w = store_alloc_valid_w && store_alloc_ready_w;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            memory_sequence_r <= {`EDRV32_LSU_SEQUENCE_W{1'b0}};
        else if (load_alloc_fire_w || store_alloc_fire_w)
            memory_sequence_r <= memory_sequence_r +
                {{(`EDRV32_LSU_SEQUENCE_W-1){1'b0}}, 1'b1};
    end

    edrv32_mem1_stage #(
        .DUAL_ISSUE(DUAL_ISSUE),
        .CACHE_ENABLE(CACHE_ENABLE),
        .TCM_ENABLE (TCM_ENABLE),
        .ITCM_ENABLE(ITCM_ENABLE),
        .DTCM_ENABLE(DTCM_ENABLE)
    ) u_mem1_stage (
        .second_i(ex_second_w),
        .packet_second_o(mem1_second_w),
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),

        // Resident packet from EX.
        .valid_i(ex_valid_w),
        .ready_o(ex_accept_w),
        .pc_i(ex_pc_w),
        .instr_i(ex_instr_w),
        .is_compressed_i(ex_is_compressed_w),
        .epoch_i(ex_epoch_w),
        .rd_i(ex_rd_w),
        .rd_write_i(ex_rd_write_w),
        .op_class_i(ex_op_class_w),
        .result_i(ex_result_w),
        .result_ready_i(ex_result_ready_w),
        .mem_addr_i(ex_mem_addr_w),
        .mem_size_i(ex_mem_size_w),
        .mem_unsigned_i(ex_mem_unsigned_w),
        .store_data_i(ex_store_data_w),
        .mdu_token_i(ex_mdu_token_w),
        .csr_op_i(ex_csr_op_w),
        .csr_addr_i(ex_csr_addr_w),
        .csr_src_i(ex_csr_src_w),
        .fence_i(ex_fence_w),
        .fencei_i(ex_fencei_w),
        .mret_i(ex_mret_w),
        .wfi_i(ex_wfi_w),
        .exception_valid_i(ex_exception_valid_w),
        .exception_cause_i(ex_exception_cause_w),
        .exception_tval_i(ex_exception_tval_w),
        .memory_sequence_i(memory_sequence_r),

        // Registered PMA-classified packet presented to MEM2.
        .packet_valid_o(mem1_packet_valid_w),
        .packet_ready_i(mem1_packet_accept_w),
        .packet_pc_o(mem1_packet_pc_w),
        .packet_instr_o(mem1_packet_instr_w),
        .packet_is_compressed_o(mem1_packet_is_compressed_w),
        .packet_epoch_o(mem1_packet_epoch_w),
        .packet_rd_o(mem1_packet_rd_w),
        .packet_rd_write_o(mem1_packet_rd_write_w),
        .packet_op_class_o(mem1_packet_op_class_w),
        .packet_result_o(mem1_packet_result_w),
        .packet_result_ready_o(mem1_packet_result_ready_w),
        .packet_mem_addr_o(mem1_packet_mem_addr_w),
        .packet_mem_size_o(mem1_packet_mem_size_w),
        .packet_mem_unsigned_o(mem1_packet_mem_unsigned_w),
        .packet_store_data_o(mem1_packet_store_data_w),
        .packet_mem_cacheable_o(mem1_packet_mem_cacheable_w),
        .packet_mem_tcm_o(mem1_packet_mem_tcm_w),
        .packet_mem_mmio_o(mem1_packet_mem_mmio_w),
        .packet_lsu_token_valid_o(mem1_packet_lsu_token_valid_w),
        .packet_lsu_token_o(mem1_packet_lsu_token_w),
        .packet_mdu_token_o(mem1_packet_mdu_token_w),
        .packet_csr_op_o(mem1_packet_csr_op_w),
        .packet_csr_addr_o(mem1_packet_csr_addr_w),
        .packet_csr_src_o(mem1_packet_csr_src_w),
        .packet_fence_o(mem1_packet_fence_w),
        .packet_fencei_o(mem1_packet_fencei_w),
        .packet_mret_o(mem1_packet_mret_w),
        .packet_wfi_o(mem1_packet_wfi_w),
        .packet_exception_valid_o(mem1_packet_exception_valid_w),
        .packet_exception_cause_o(mem1_packet_exception_cause_w),
        .packet_exception_tval_o(mem1_packet_exception_tval_w),

        .load_alloc_valid_o(load_alloc_valid_w),
        .load_alloc_ready_i(load_alloc_ready_w),
        .load_alloc_token_i(load_alloc_token_w),
        .load_alloc_pc_o(load_alloc_pc_w),
        .load_alloc_rd_o(load_alloc_rd_w),
        .load_alloc_addr_o(load_alloc_addr_w),
        .load_alloc_size_o(load_alloc_size_w),
        .load_alloc_unsigned_o(load_alloc_unsigned_w),
        .load_alloc_epoch_o(load_alloc_epoch_w),
        .load_alloc_sequence_o(),

        .store_alloc_valid_o(store_alloc_valid_w),
        .store_alloc_ready_i(store_alloc_ready_w),
        .store_alloc_token_i(store_alloc_token_w),
        .store_alloc_pc_o(store_alloc_pc_w),
        .store_alloc_addr_o(store_alloc_addr_w),
        .store_alloc_wstrb_o(store_alloc_wstrb_w),
        .store_alloc_wdata_o(store_alloc_wdata_w),
        .store_alloc_epoch_o(store_alloc_epoch_w),
        .store_alloc_sequence_o(store_alloc_sequence_w),

        // Early capacity feedback prevents overflow under backpressure.
        .full_o(mem1_to_mem2_full_w),

        .kill_i(commit_kill_younger_w)
    );

    edrv32_mem2_stage #(.DUAL_ISSUE(DUAL_ISSUE)) u_mem2_stage (
        .second_i(mem1_second_w),
        .hazard_second_o(mem2_second_w),
        .packet_second_o(commit_second_w),
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),

        // Resident packet from MEM1.
        .valid_i(mem1_packet_valid_w),
        .ready_o(mem1_packet_accept_w),
        .pc_i(mem1_packet_pc_w),
        .instr_i(mem1_packet_instr_w),
        .is_compressed_i(mem1_packet_is_compressed_w),
        .epoch_i(mem1_packet_epoch_w),
        .rd_i(mem1_packet_rd_w),
        .rd_write_i(mem1_packet_rd_write_w),
        .op_class_i(mem1_packet_op_class_w),
        .result_i(mem1_packet_result_w),
        .result_ready_i(mem1_packet_result_ready_w),
        .mem_addr_i(mem1_packet_mem_addr_w),
        .mem_size_i(mem1_packet_mem_size_w),
        .mem_unsigned_i(mem1_packet_mem_unsigned_w),
        .store_data_i(mem1_packet_store_data_w),
        .mem_cacheable_i(mem1_packet_mem_cacheable_w),
        .mem_tcm_i(mem1_packet_mem_tcm_w),
        .mem_mmio_i(mem1_packet_mem_mmio_w),
        .lsu_token_valid_i(mem1_packet_lsu_token_valid_w),
        .lsu_token_i(mem1_packet_lsu_token_w),
        .mdu_token_i(mem1_packet_mdu_token_w),
        .csr_op_i(mem1_packet_csr_op_w),
        .csr_addr_i(mem1_packet_csr_addr_w),
        .csr_src_i(mem1_packet_csr_src_w),
        .fence_i(mem1_packet_fence_w),
        .fencei_i(mem1_packet_fencei_w),
        .mret_i(mem1_packet_mret_w),
        .wfi_i(mem1_packet_wfi_w),
        .exception_valid_i(mem1_packet_exception_valid_w),
        .exception_cause_i(mem1_packet_exception_cause_w),
        .exception_tval_i(mem1_packet_exception_tval_w),

        // Bypass and dependency record for younger instructions.
        .hazard_valid_o(mem2_hazard_valid_w),
        .hazard_write_o(mem2_hazard_write_w),
        .hazard_ready_o(mem2_hazard_ready_w),
        .hazard_rd_o(mem2_hazard_rd_w),
        .hazard_value_o(mem2_hazard_value_w),
        .hazard_pc_o(mem2_hazard_pc_w),
        .hazard_op_class_o(mem2_hazard_op_class_w),
        .hazard_late_load_o(mem2_hazard_late_load_w),
        .hazard_lsu_token_valid_o(mem2_hazard_lsu_token_valid_w),
        .hazard_lsu_token_o(mem2_hazard_lsu_token_w),
        .mdu_pass_o(mem2_mdu_pass_w),
        // Registered completed packet presented to COMMIT.
        .packet_valid_o(mem2_packet_valid_w),
        .packet_ready_i(mem2_packet_accept_w),
        .packet_pc_o(mem2_packet_pc_w),
        .packet_instr_o(mem2_packet_instr_w),
        .packet_is_compressed_o(mem2_packet_is_compressed_w),
        .packet_epoch_o(mem2_packet_epoch_w),
        .packet_rd_o(mem2_packet_rd_w),
        .packet_rd_write_o(mem2_packet_rd_write_w),
        .packet_op_class_o(mem2_packet_op_class_w),
        .packet_result_o(mem2_packet_result_w),
        .packet_result_ready_o(mem2_packet_result_ready_w),
        .packet_mem_addr_o(mem2_packet_mem_addr_w),
        .packet_mem_size_o(mem2_packet_mem_size_w),
        .packet_mem_unsigned_o(mem2_packet_mem_unsigned_w),
        .packet_store_data_o(mem2_packet_store_data_w),
        .packet_mem_cacheable_o(mem2_packet_mem_cacheable_w),
        .packet_mem_tcm_o(mem2_packet_mem_tcm_w),
        .packet_mem_mmio_o(mem2_packet_mem_mmio_w),
        .packet_lsu_token_valid_o(mem2_packet_lsu_token_valid_w),
        .packet_lsu_token_o(mem2_packet_lsu_token_w),
        .packet_mdu_token_o(mem2_packet_mdu_token_w),
        .packet_csr_op_o(mem2_packet_csr_op_w),
        .packet_csr_addr_o(mem2_packet_csr_addr_w),
        .packet_csr_src_o(mem2_packet_csr_src_w),
        .packet_fence_o(mem2_packet_fence_w),
        .packet_fencei_o(mem2_packet_fencei_w),
        .packet_mret_o(mem2_packet_mret_w),
        .packet_wfi_o(mem2_packet_wfi_w),
        .packet_exception_valid_o(mem2_packet_exception_valid_w),
        .packet_exception_cause_o(mem2_packet_exception_cause_w),
        .packet_exception_tval_o(mem2_packet_exception_tval_w),

        .kill_i(commit_kill_younger_w)
    );

    // ========================================================================
    // Commit: sole architectural side-effect and precise-trap owner
    // ========================================================================
    edrv32_commit_stage #(
        .DUAL_ISSUE(DUAL_ISSUE),
        .MULTI_EVENT_ENABLE(PAIR_FRONTEND_ENABLE),
        .CPU_HPM_ENABLE(CPU_HPM_ENABLE),
        .MVENDORID(MVENDORID),
        .MARCHID(MARCHID),
        .MIMPID(MIMPID),
        .MHARTID(MHARTID)
    ) u_commit_stage (
        .second_i(commit_second_w),
        .hpm_second_events_i(hpm_second_events_w),
        .second_gpr_write_o(commit_second_write_w),
        .second_gpr_rd_o(commit_second_rd_w),
        .second_gpr_value_o(commit_second_value_w),
        .second_retire_o(second_retire_o),
        .second_retire_pc_o(second_retire_pc_o),
        .second_retire_instr_o(second_retire_instr_o),
        .second_retire_compressed_o(second_retire_compressed_w),
        .retire_count_o(retire_count_o),
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),

        // Oldest in-order packet from MEM2.
        .valid_i(mem2_packet_valid_w),
        .ready_o(mem2_packet_accept_w),
        .pc_i(mem2_packet_pc_w),
        .instr_i(mem2_packet_instr_w),
        .is_compressed_i(mem2_packet_is_compressed_w),
        .epoch_i(mem2_packet_epoch_w),
        .rd_i(mem2_packet_rd_w),
        .rd_write_i(mem2_packet_rd_write_w),
        .op_class_i(mem2_packet_op_class_w),
        .result_i(mem2_packet_result_w),
        .result_ready_i(mem2_packet_result_ready_w),
        .mem_addr_i(mem2_packet_mem_addr_w),
        .mem_size_i(mem2_packet_mem_size_w),
        .mem_unsigned_i(mem2_packet_mem_unsigned_w),
        .store_data_i(mem2_packet_store_data_w),
        .mem_cacheable_i(mem2_packet_mem_cacheable_w),
        .lsu_token_valid_i(mem2_packet_lsu_token_valid_w),
        .lsu_token_i(mem2_packet_lsu_token_w),
        .mdu_token_i(mem2_packet_mdu_token_w),
        .csr_op_i(mem2_packet_csr_op_w),
        .csr_addr_i(mem2_packet_csr_addr_w),
        .csr_src_i(mem2_packet_csr_src_w),
        .fence_i(mem2_packet_fence_w),
        .fencei_i(mem2_packet_fencei_w),
        .mret_i(mem2_packet_mret_w),
        .wfi_i(mem2_packet_wfi_w),
        .exception_valid_i(mem2_packet_exception_valid_w),
        .exception_cause_i(mem2_packet_exception_cause_w),
        .exception_tval_i(mem2_packet_exception_tval_w),

        // Completion and retirement authorization for the MDU slot.
        .mdu_pending_i(mdu_pending_w),
        .mdu_authorized_i(mdu_authorized_w),
        .mdu_result_valid_i(mdu_result_valid_w),
        .mdu_result_ready_o(mdu_result_ready_w),
        .mdu_result_rd_i(mdu_result_rd_w),
        .mdu_result_data_i(mdu_result_data_w),
        .mdu_authorize_o(mdu_authorize_w),
        .mdu_cancel_o(mdu_cancel_w),
        .mdu_writeback_fire_o(mdu_writeback_fire_w),

        .load_commit_valid_o(load_commit_valid_w),
        .load_commit_token_o(load_commit_token_w),
        .load_commit_ready_i(load_commit_ready_w),
        .load_commit_data_i(load_commit_data_w),
        .load_commit_error_i(load_commit_error_w),
        .load_commit_fire_o(load_commit_fire_w),
        .store_commit_valid_o(store_commit_valid_w),
        .store_commit_token_o(store_commit_token_w),
        .store_commit_ready_i(store_commit_ready_w),
        .store_commit_error_i(store_commit_error_w),
        .store_commit_fire_o(store_commit_fire_w),
        .lsu_queues_empty_i(load_queue_empty_w && store_queue_empty_w),

        // Precise load/store request issued only by COMMIT.
        .dmem_req_valid_o(commit_dmem_req_valid_w),
        .dmem_req_ready_i(commit_dmem_req_ready_w),
        .dmem_req_addr_o(commit_dmem_req_addr_w),
        .dmem_req_we_o(commit_dmem_req_we_w),
        .dmem_req_size_o(commit_dmem_req_size_w),
        .dmem_req_wstrb_o(commit_dmem_req_wstrb_w),
        .dmem_req_wdata_o(commit_dmem_req_wdata_w),
        .dmem_req_cacheable_o(commit_dmem_req_cacheable_w),
        .dmem_resp_valid_i(commit_dmem_resp_valid_w),
        .dmem_resp_ready_o(commit_dmem_resp_ready_w),
        .dmem_resp_rdata_i(commit_dmem_resp_data_w),
        .dmem_resp_error_i(commit_dmem_resp_error_w),

        // Machine interrupt, time and performance-event inputs.
        .irq_soft_i(irq_soft_i),
        .irq_timer_i(irq_timer_i),
        .irq_ext_i(irq_ext_i),
        .time_value_i(time_value_i),
        .hpm_events_i(hpm_events_w),

        // Precise redirects generated by retirement events.
        .redirect_exception_valid_o(commit_redirect_exception_valid_w),
        .redirect_exception_target_o(commit_redirect_exception_target_w),
        .redirect_interrupt_valid_o(commit_redirect_interrupt_valid_w),
        .redirect_interrupt_target_o(commit_redirect_interrupt_target_w),
        .redirect_mret_valid_o(commit_redirect_mret_valid_w),
        .redirect_mret_target_o(commit_redirect_mret_target_w),
        .redirect_fencei_valid_o(commit_redirect_fencei_valid_w),
        .redirect_fencei_target_o(commit_redirect_fencei_target_w),
        .redirect_event_ready_i(commit_redirect_ready_w),
        .flush_younger_lsu_o(commit_flush_younger_lsu_w),
        .kill_younger_o(commit_kill_younger_w),

        // Mutual-exclusion attribution: retirement-blocking reasons.
        .hpm_busy_memory_o(commit_hpm_busy_memory_w),
        .hpm_busy_other_o(commit_hpm_busy_other_w),



        // Architectural register-file writeback.
        .gpr_write_o(commit_gpr_write_w),
        .gpr_rd_o(commit_gpr_rd_w),
        .gpr_value_o(commit_gpr_value_w),

        // Same-cycle bypass record for younger instructions.
        .bypass_valid_o(commit_bypass_valid_w),
        .bypass_write_o(commit_bypass_write_w),
        .bypass_ready_o(commit_bypass_ready_w),
        .bypass_rd_o(commit_bypass_rd_w),
        .bypass_value_o(commit_bypass_value_w),

        // Architectural retirement trace and sleep state.
        .retire_o(retire_o),
        .retire_pc_o(retire_pc_o),
        .retire_instr_o(retire_instr_o),
        .retire_exception_o(retire_exception_o),
        .retire_cause_o(retire_cause_o),
        .core_sleep_o(core_sleep_o)
    );

    // A committed store drains independently of the instruction currently at
    // COMMIT. One registered owner bit routes a delayed response; the live
    // selection also covers the D-cache's legal same-cycle acknowledgement.
    wire store_drain_select_w = store_drain_valid_w;
    reg dmem_owner_valid_r;
    reg dmem_owner_store_r;
    reg [`EDRV32_LSU_TOKEN_W-1:0] dmem_owner_token_r;
    assign dmem_req_valid_o = !dmem_owner_valid_r &&
        (store_drain_select_w || commit_dmem_req_valid_w);
    assign dmem_req_addr_o = store_drain_select_w
        ? store_drain_addr_w : commit_dmem_req_addr_w;
    assign dmem_req_we_o = store_drain_select_w ? 1'b1 :
                                                      commit_dmem_req_we_w;
    assign dmem_req_size_o = store_drain_select_w ? `BUS_SZ_WORD :
                                                      commit_dmem_req_size_w;
    assign dmem_req_wstrb_o = store_drain_select_w ? store_drain_wstrb_w :
                                                       commit_dmem_req_wstrb_w;
    assign dmem_req_wdata_o = store_drain_select_w ? store_drain_wdata_w :
                                                       commit_dmem_req_wdata_w;
    assign dmem_req_cacheable_o = store_drain_select_w ? 1'b1 :
                                                commit_dmem_req_cacheable_w;
    assign store_drain_ready_w = !dmem_owner_valid_r &&
                                  store_drain_select_w && dmem_req_ready_i;
    assign commit_dmem_req_ready_w = !dmem_owner_valid_r &&
                                     !store_drain_select_w &&
                                     dmem_req_ready_i;
    wire dmem_request_fire_w = dmem_req_valid_o && dmem_req_ready_i;
    wire dmem_request_source_store_w = store_drain_select_w;
    wire dmem_response_source_store_w = dmem_owner_valid_r
        ? dmem_owner_store_r : dmem_request_source_store_w;
    assign dmem_resp_ready_o = dmem_response_source_store_w ? 1'b1 :
                                                        commit_dmem_resp_ready_w;
    wire dmem_response_fire_w = dmem_resp_valid_i && dmem_resp_ready_o;
    assign store_drain_response_valid_w = dmem_resp_valid_i &&
                                          dmem_response_source_store_w;
    assign store_drain_response_token_w = dmem_owner_valid_r
        ? dmem_owner_token_r : store_drain_token_w;
    assign store_drain_response_error_w = dmem_resp_error_i;
    assign commit_dmem_resp_valid_w = dmem_resp_valid_i &&
                                      !dmem_response_source_store_w;
    assign commit_dmem_resp_data_w = dmem_resp_rdata_i;
    assign commit_dmem_resp_error_w = dmem_resp_error_i;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            dmem_owner_valid_r <= 1'b0;
            dmem_owner_store_r <= 1'b0;
            dmem_owner_token_r <= {`EDRV32_LSU_TOKEN_W{1'b0}};
        end else if (dmem_request_fire_w) begin
            dmem_owner_valid_r <= !dmem_response_fire_w;
            dmem_owner_store_r <= dmem_request_source_store_w;
            if (dmem_request_source_store_w)
                dmem_owner_token_r <= store_drain_token_w;
        end else if (dmem_response_fire_w) begin
            dmem_owner_valid_r <= 1'b0;
        end
    end

    assign mdu_req_ready_w = mdu_engine_req_ready_w &&
                             mdu_scoreboard_alloc_ready_w;

    // ========================================================================
    // Mutual-exclusion empty-retire attribution and auxiliary events 41..98.
    // Observation only: the inputs are registered stage state and the outputs
    // feed nothing but the HPM event sample registers.
    // ========================================================================
    edrv32_hpm_attribution u_hpm_attribution (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),

        .retire_i(retire_o),

        .mem2_packet_valid_i(mem2_packet_valid_w),
        .mem2_packet_accept_i(mem2_packet_accept_w),
        .commit_busy_memory_i(commit_hpm_busy_memory_w),
        .commit_busy_other_i(commit_hpm_busy_other_w),

        .mem2_hazard_valid_i(mem2_hazard_valid_w),
        .mem2_cache_wait_i(mem2_cache_wait_w),

        .mem1_packet_valid_i(mem1_packet_valid_w),
        .mem1_packet_accept_i(mem1_packet_accept_w),
        .ex_valid_i(ex_valid_w),
        .ex_accept_i(ex_accept_w),
        .ex_late_load_stall_i(ex_late_load_stall_w),
        .ex_late_mdu_stall_i(ex_late_mdu_stall_w),

        .decode_valid_i(decode_valid_w),
        .decode_accept_i(decode_accept_w),
        .decode_dependency_stall_i(decode_dependency_stall_w),
        .decode_structural_stall_i(decode_structural_stall_w),
        .decode_stall_resident_i(decode_hpm_stall_resident_w),
        .decode_stall_load_i(decode_hpm_stall_load_w),
        .decode_stall_mdu_i(decode_hpm_stall_mdu_w),

        .align_valid_i(align_valid_w),
        .align_accept_i(align_accept_w),
        .redirect_pending_i(redirect_valid_w || prediction_redirect_valid_w),
        .icache_refill_busy_i(cache_perf_events_i[3]),
        .if1_tag_nonempty_i(if1_hpm_tag_nonempty_w),

        .candidate_class_i(decode_hpm_candidate_class_w),
        .candidate_rs1_i(mdu_hazard_rs1_w),
        .candidate_uses_rs1_i(mdu_hazard_uses_rs1_w),
        .candidate_rs2_i(mdu_hazard_rs2_w),
        .candidate_uses_rs2_i(mdu_hazard_uses_rs2_w),
        .resident_op_class_i(decode_op_class_w),
        .mdu_waw_i(decode_mdu_waw_stall_w),
        .candidate_mdu_rs1_i(decode_mdu_rs1_w),
        .candidate_mdu_rs2_i(decode_mdu_rs2_w),
        .resident_write_i(decode_rd_write_w),
        .resident_rd_i(decode_rd_w),
        .ex_write_i(ex_rd_write_w),
        .ex_rd_i(ex_rd_w),
        .ex_op_class_i(ex_op_class_w),
        .mem1_write_i(mem1_packet_rd_write_w),
        .mem1_rd_i(mem1_packet_rd_w),
        .mem1_op_class_i(mem1_packet_op_class_w),
        .mem2_write_i(mem2_hazard_write_w),
        .mem2_rd_i(mem2_hazard_rd_w),
        .mem2_op_class_i(mem2_hazard_op_class_w),
        .commit_write_i(commit_bypass_write_w),
        .commit_rd_i(commit_bypass_rd_w),

        .fe_append_hw1_i(if2_hpm_append_hw1_w),
        .fe_append_hw2_i(if2_hpm_append_hw2_w),
        .fe_consume_hw1_i(if2_hpm_consume_hw1_w),
        .fe_consume_hw2_i(if2_hpm_consume_hw2_w),
        .fe_pred_redirect_i(prediction_redirect_fire_w),
        .fe_discard_block_i(if2_hpm_discard_block_w),
        .branch_diag_i(hpm_branch_diag_r),
        .fe_pred_append_slot0_i(if2_hpm_pred_append_slot0_w),
        .fe_pred_append_slot1_i(if2_hpm_pred_append_slot1_w),
        .fe_pred_append_cross_i(if2_hpm_pred_append_cross_w),
        .fe_pred_candidate_i(if2_hpm_pred_candidate_w),
        .fe_discard_stale_i(if2_hpm_discard_stale_w),
        .fe_discard_arch_redirect_i(if2_hpm_discard_arch_redirect_w),
        .fe_discard_pred_redirect_i(if2_hpm_discard_pred_redirect_w),

        .events_o(hpm_attribution_events_w)
    );

    assign hpm_events_w[(`EDRV32_HPM_EVENT_W-1):40] = hpm_attribution_events_w;

    // ========================================================================
    // Long-latency integer MDU and its one-entry dependency scoreboard
    // ========================================================================
    edrv32_mdu_scoreboard u_mdu_scoreboard (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),

        // Allocate and release the single long-latency destination.
        .alloc_valid_i(mdu_req_fire_w),
        .alloc_ready_o(mdu_scoreboard_alloc_ready_w),
        .alloc_rd_i(mdu_req_rd_w),
        .alloc_rd_write_i(1'b1),
        .authorize_i(mdu_authorize_w),
        .cancel_i(mdu_cancel_w),
        .writeback_fire_i(mdu_writeback_fire_w),
        .pass_mem1_i(mdu_mem1_pass_w),
        .pass_mem2_i(mem2_mdu_pass_w),

        // Register identities of the instruction being considered by DECODE.
        .rs1_addr_i(mdu_hazard_rs1_w),
        .uses_rs1_i(mdu_hazard_uses_rs1_w),
        .rs2_addr_i(mdu_hazard_rs2_w),
        .uses_rs2_i(mdu_hazard_uses_rs2_w),
        .issue_rd_i(mdu_hazard_rd_w),
        .issue_rd_write_i(mdu_hazard_rd_write_w),

        // Slot state and dependency decisions.
        .pending_o(mdu_pending_w),
        .pending_rd_o(mdu_pending_rd_w),
        .authorized_o(mdu_authorized_w),
        .passed_mem1_o(mdu_passed_mem1_w),
        .passed_mem2_o(mdu_passed_mem2_w),
        .raw_hazard_o(),
        .waw_hazard_o(mdu_waw_hazard_w)
    );

    edrv32_mdu #(
        .MUL_USE_PANGO_APM(MUL_USE_PANGO_APM),
        .MUL_LOW_PIPE_STAGES(MUL_LOW_PIPE_STAGES)
    ) u_mdu (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),

        // Request accepted jointly by the engine and scoreboard.
        .req_valid_i(mdu_req_valid_w && mdu_scoreboard_alloc_ready_w),
        .req_ready_o(mdu_engine_req_ready_w),
        .req_op_i(mdu_req_op_w),
        .req_lhs_i(mdu_req_lhs_w),
        .req_rhs_i(mdu_req_rhs_w),
        .req_mul_lhs_i(mdu_req_mul_lhs_w),
        .req_mul_rhs_i(mdu_req_mul_rhs_w),
        .req_div_lhs_i(mdu_req_div_lhs_w),
        .req_div_rhs_i(mdu_req_div_rhs_w),
        .req_rd_i(mdu_req_rd_w),

        // COMMIT decides whether the completed operation may retire.
        .authorize_i(mdu_authorize_w),
        .cancel_i(mdu_cancel_w),

        // Completed result returned to COMMIT.
        .result_valid_o(mdu_result_valid_w),
        .result_ready_i(mdu_result_ready_w),
        .result_rd_o(mdu_result_rd_w),
        .result_data_o(mdu_result_data_w),

        // Registered completion observation used by DECODE and EX forwarding.
        .slot_valid_o(mdu_slot_valid_w),
        .result_complete_o(mdu_result_complete_w),
        .authorized_o()
    );

    // ========================================================================
    // Registered redirect arbitration: older COMMIT events override EX
    // ========================================================================
    edrv32_redirect_ctrl u_redirect_ctrl (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),

        // Older COMMIT redirects have priority in program order.
        .commit_exception_valid_i(commit_redirect_exception_valid_w),
        .commit_exception_target_i(commit_redirect_exception_target_w),
        .commit_interrupt_valid_i(commit_redirect_interrupt_valid_w),
        .commit_interrupt_target_i(commit_redirect_interrupt_target_w),
        .commit_mret_valid_i(commit_redirect_mret_valid_w),
        .commit_mret_target_i(commit_redirect_mret_target_w),
        .commit_fencei_valid_i(commit_redirect_fencei_valid_w),
        .commit_fencei_target_i(commit_redirect_fencei_target_w),
        .commit_event_ready_o(commit_redirect_ready_w),

        // Younger branch/jump correction from EX.
        .ex_redirect_valid_i(ex_redirect_valid_w),
        .ex_redirect_target_i(ex_redirect_target_w),
        .ex_event_ready_o(ex_redirect_ready_w),

        // Registered redirect consumed by IF1.
        .redirect_valid_o(redirect_valid_w),
        .redirect_accept_i(redirect_accept_w),
        .redirect_target_o(redirect_target_w),
        .redirect_reason_o(redirect_reason_w),
        .redirect_epoch_o(redirect_epoch_w)
    );

    // A kill can invalidate a store-hit reservation even after MEM2 has
    // consumed the lookup response and made the packet visible to COMMIT.
    // Fence serialization removes speculative queue entries immediately.
    // A D-cache lookup owned by one of those entries must be cancelled too,
    // but a reservation held by an older committed store must survive until
    // its drain completes.
    wire fence_lookup_cancel_w = commit_flush_younger_lsu_w &&
                                 store_committed_empty_w;
    assign dcache_lookup_cancel_o = (CACHE_ENABLE != 0) &&
        (commit_kill_younger_w || fence_lookup_cancel_w);
    assign dcache_reservation_keep_count_o =
        store_committed_reservation_count_w;

    // Select the oldest unresolved cacheable access for the single lookup
    // port.  A blocked older load suppresses younger Store preparation.
    wire [`EDRV32_LSU_SEQUENCE_W-1:0] pending_sequence_delta_w =
        load_pending_sequence_w - store_prepare_sequence_w;
    wire older_load_pending_w = load_pending_valid_w &&
        store_prepare_valid_w &&
        pending_sequence_delta_w[`EDRV32_LSU_SEQUENCE_W-1];
    wire store_prepare_issue_valid_w = store_prepare_valid_w &&
                                       !older_load_pending_w;
    wire [`EDRV32_LSU_SEQUENCE_W-1:0] queue_sequence_delta_w =
        load_request_sequence_w - store_prepare_sequence_w;
    wire store_prepare_older_w = store_prepare_issue_valid_w &&
        (!load_request_valid_w || !queue_sequence_delta_w[
            `EDRV32_LSU_SEQUENCE_W-1]);
    wire queue_request_valid_w = load_request_valid_w ||
                                 store_prepare_issue_valid_w;
    assign load_request_ready_w = dcache_lookup_ready_i &&
                                  !store_prepare_older_w;
    assign store_prepare_ready_w = dcache_lookup_ready_i &&
                                  store_prepare_older_w;
    assign dcache_lookup_valid_w = queue_request_valid_w;
    assign dcache_lookup_addr_w = store_prepare_older_w
        ? store_prepare_addr_w : load_request_addr_w;
    assign dcache_lookup_store_w = store_prepare_older_w;
    assign dcache_lookup_size_w = store_prepare_older_w
        ? `BUS_SZ_WORD : load_request_size_w;
    assign dcache_lookup_unsigned_w = store_prepare_older_w
        ? 1'b0 : load_request_unsigned_w;
    assign dcache_lookup_token_o = store_prepare_older_w
        ? store_prepare_token_w : load_request_token_w;
    assign dcache_lookup_valid_o = dcache_lookup_valid_w;
    assign dcache_lookup_addr_o  = dcache_lookup_addr_w;
    assign dcache_lookup_store_o = dcache_lookup_store_w;
    assign dcache_lookup_size_o = dcache_lookup_size_w;
    assign dcache_lookup_unsigned_o = dcache_lookup_unsigned_w;
    assign dcache_lookup_resp_ready_o = 1'b1;
    assign dcache_lookup_fast_ready_o = 1'b1;

    // The cached top uses these precise retirement pulses for memory ordering.
    // Only FENCE.I invalidates the instruction cache; both variants clean D$.
    assign fence_retire_o = retire_o && mem2_packet_fence_w &&
                            !retire_exception_o;
    assign fencei_retire_o = retire_o && mem2_packet_fencei_w &&
                              !retire_exception_o;

    // Platform-defined HPM event catalogue. mhpmevent3..31 select any of
    // these sources; the default reset profile selects events 1..29.
    wire decode_rs1_waits_for_load_w = mdu_hazard_uses_rs1_w &&
        (((ex_valid_w && ex_rd_write_w && (ex_rd_w != 5'd0) &&
           (ex_rd_w == mdu_hazard_rs1_w) && !ex_result_ready_w &&
           (ex_op_class_w == `EDRV32_OP_LOAD))) ||
         ((mem1_packet_valid_w && mem1_packet_rd_write_w && (mem1_packet_rd_w != 5'd0) &&
           (mem1_packet_rd_w == mdu_hazard_rs1_w) && !mem1_packet_result_ready_w &&
           (mem1_packet_op_class_w == `EDRV32_OP_LOAD))) ||
         ((mem2_hazard_valid_w && mem2_hazard_write_w &&
           (mem2_hazard_rd_w != 5'd0) && (mem2_hazard_rd_w == mdu_hazard_rs1_w) &&
           !mem2_hazard_effective_ready_w &&
           (mem2_hazard_op_class_w == `EDRV32_OP_LOAD))));
    wire decode_rs2_waits_for_load_w = mdu_hazard_uses_rs2_w &&
        (((ex_valid_w && ex_rd_write_w && (ex_rd_w != 5'd0) &&
           (ex_rd_w == mdu_hazard_rs2_w) && !ex_result_ready_w &&
           (ex_op_class_w == `EDRV32_OP_LOAD))) ||
         ((mem1_packet_valid_w && mem1_packet_rd_write_w && (mem1_packet_rd_w != 5'd0) &&
           (mem1_packet_rd_w == mdu_hazard_rs2_w) && !mem1_packet_result_ready_w &&
           (mem1_packet_op_class_w == `EDRV32_OP_LOAD))) ||
         ((mem2_hazard_valid_w && mem2_hazard_write_w &&
           (mem2_hazard_rd_w != 5'd0) && (mem2_hazard_rd_w == mdu_hazard_rs2_w) &&
           !mem2_hazard_effective_ready_w &&
           (mem2_hazard_op_class_w == `EDRV32_OP_LOAD))));
    wire hpm_decode_load_use_stall_w = decode_dependency_stall_w &&
                                       (decode_rs1_waits_for_load_w ||
                                        decode_rs2_waits_for_load_w);
    wire hpm_load_use_stall_w = hpm_decode_load_use_stall_w ||
                                ex_late_load_stall_w;
    wire hpm_exception_w = retire_exception_o && !retire_cause_o[31];
    wire hpm_interrupt_w = retire_exception_o && retire_cause_o[31];
    wire hpm_ecall_w = hpm_exception_w && (retire_cause_o[4:0] == 5'd11);
    wire hpm_retired_load_w = retire_o &&
        (mem2_packet_op_class_w == `EDRV32_OP_LOAD);
    wire hpm_retired_store_w = retire_o &&
        (mem2_packet_op_class_w == `EDRV32_OP_STORE);
    wire hpm_retired_branch_w = retire_o &&
        (mem2_packet_op_class_w == `EDRV32_OP_BRANCH);
    wire hpm_retired_jump_w = retire_o &&
        (mem2_packet_op_class_w == `EDRV32_OP_JUMP);
    wire hpm_retired_mdu_w = retire_o &&
        (mem2_packet_op_class_w == `EDRV32_OP_MDU);
    wire hpm_retired_alu_w = retire_o &&
        (mem2_packet_op_class_w == `EDRV32_OP_ALU);
    wire hpm_retired_csr_w = retire_o &&
        (mem2_packet_op_class_w == `EDRV32_OP_CSR);

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            hpm_control_flow_r  <= 1'b0;
            hpm_mispredict_r    <= 1'b0;
            hpm_direction_miss_r <= 1'b0;
            hpm_target_miss_r   <= 1'b0;
            hpm_ras_push_r      <= 1'b0;
            hpm_ras_pop_r       <= 1'b0;
            hpm_branch_diag_r   <= 8'b0;
        end else begin
            hpm_control_flow_r  <= predictor_update_valid_w;
            hpm_mispredict_r    <= ex_kill_younger_w;
            hpm_direction_miss_r <= ex_direction_mispredict_w;
            hpm_target_miss_r   <= ex_target_mispredict_w;
            hpm_ras_push_r      <= predictor_update_valid_w &&
                                   predictor_update_ras_push_w;
            hpm_ras_pop_r       <= predictor_update_valid_w &&
                                   predictor_update_ras_pop_w;
            hpm_branch_diag_r[0] <= predictor_update_valid_w &&
                predictor_update_is_conditional_w && !decode_predictor_meta_w[0] &&
                decode_predictor_meta_w[1] && predictor_update_taken_w;
            hpm_branch_diag_r[1] <= predictor_update_valid_w &&
                predictor_update_is_conditional_w && !decode_predictor_meta_w[0] &&
                decode_predictor_meta_w[1] && !predictor_update_taken_w;
            hpm_branch_diag_r[2] <= predictor_update_valid_w &&
                predictor_update_is_conditional_w && !decode_predictor_meta_w[0] &&
                !decode_predictor_meta_w[1] && predictor_update_taken_w;
            hpm_branch_diag_r[3] <= predictor_update_valid_w &&
                predictor_update_is_conditional_w && !decode_predictor_meta_w[0] &&
                !decode_predictor_meta_w[1] && !predictor_update_taken_w;
            hpm_branch_diag_r[4] <= predictor_update_valid_w &&
                predictor_update_is_conditional_w && decode_predictor_meta_w[0] &&
                (decode_predictor_meta_w[1] != predictor_update_taken_w);
            hpm_branch_diag_r[5] <= predictor_update_valid_w &&
                predictor_update_is_conditional_w && decode_predictor_meta_w[0] &&
                (decode_predictor_meta_w[1] == predictor_update_taken_w);
            hpm_branch_diag_r[6] <= predictor_update_valid_w &&
                !decode_predictor_meta_w[0] && (decode_instr_w[6:0] == 7'b1101111);
            hpm_branch_diag_r[7] <= predictor_update_valid_w &&
                !decode_predictor_meta_w[0] && (decode_instr_w[6:0] == 7'b1100111);
        end
    end

    // The second event vector adds occurrence counts, while cycle events stay
    // exclusively in the primary vector. HPM applies the same registered sample.
    reg [`EDRV32_HPM_EVENT_W-1:0] second_events_w;
    always @(*) begin
        second_events_w = {`EDRV32_HPM_EVENT_W{1'b0}};
        second_events_w[`EDRV32_HPM_FE_APPEND_HW2-1] = if2_hpm_second_append_hw2_w;
        second_events_w[`EDRV32_HPM_RETIRED_ALU-1] = second_retire_o;
        second_events_w[`EDRV32_HPM_RETIRED_COMPRESSED-1] =
            second_retire_o && second_retire_compressed_w;
        second_events_w[`EDRV32_HPM_FE_CONSUME_HW1-1] = if2_hpm_second_consume_hw1_w;
        second_events_w[`EDRV32_HPM_FE_CONSUME_HW2-1] = if2_hpm_second_consume_hw2_w;
    end
    assign hpm_second_events_w = second_events_w;

    assign hpm_events_w[`EDRV32_HPM_CONTROL_FLOW-1] = hpm_control_flow_r;
    assign hpm_events_w[`EDRV32_HPM_MISPREDICT-1] = hpm_mispredict_r;
    assign hpm_events_w[`EDRV32_HPM_DIRECTION_MISS-1] = hpm_direction_miss_r;
    assign hpm_events_w[`EDRV32_HPM_TARGET_MISS-1] = hpm_target_miss_r;
    assign hpm_events_w[`EDRV32_HPM_PREDICTED_TAKEN-1] =
        decode_valid_w && decode_accept_w && decode_predicted_taken_w;
    assign hpm_events_w[`EDRV32_HPM_RAS_PUSH-1] = hpm_ras_push_r;
    assign hpm_events_w[`EDRV32_HPM_RAS_POP-1] = hpm_ras_pop_r;
    assign hpm_events_w[`EDRV32_HPM_DEPENDENCY_STALL-1] =
        decode_dependency_stall_w || ex_late_load_stall_w || ex_late_mdu_stall_w;
    assign hpm_events_w[`EDRV32_HPM_LOAD_USE_STALL-1] = hpm_load_use_stall_w;
    assign hpm_events_w[`EDRV32_HPM_STRUCTURAL_STALL-1] =
        decode_structural_stall_w;
    assign hpm_events_w[`EDRV32_HPM_MEM1_FIFO_FULL-1] = mem1_to_mem2_full_w;
    // Scoreboard compare inputs retain the last decoded register fields while
    // the ALIGN/DECODE boundary is empty. Count only hazards that actually
    // participate in a valid, non-exception dependency stall.
    assign hpm_events_w[`EDRV32_HPM_MDU_RAW_HAZARD-1] =
        (decode_dependency_stall_w && mdu_raw_hazard_w) || ex_late_mdu_stall_w;
    assign hpm_events_w[`EDRV32_HPM_MDU_WAW_HAZARD-1] =
        decode_mdu_waw_stall_w;
    assign hpm_events_w[`EDRV32_HPM_MDU_ISSUE_WAIT-1] =
        mdu_req_valid_w && !mdu_req_ready_w;
    assign hpm_events_w[`EDRV32_HPM_IF_REQ_BACKPRESSURE-1] =
        imem_req_valid_o && !imem_req_ready_i;
    assign hpm_events_w[`EDRV32_HPM_IF_RESP_BACKPRESSURE-1] =
        imem_resp_valid_i && !imem_resp_ready_o;
    assign hpm_events_w[`EDRV32_HPM_FRONTEND_EMPTY-1] =
        !align_valid_w && !decode_valid_w;
    assign hpm_events_w[`EDRV32_HPM_DMEM_BACKPRESSURE-1] =
        dmem_req_valid_o && !dmem_req_ready_i;
    assign hpm_events_w[`EDRV32_HPM_DCACHE_REQ_WAIT-1] =
        dcache_lookup_valid_o && !dcache_lookup_ready_i;
    assign hpm_events_w[`EDRV32_HPM_COMMIT_BACKPRESSURE-1] =
        mem2_packet_valid_w && !mem2_packet_accept_w;
    assign hpm_events_w[`EDRV32_HPM_ICACHE_MISS-1] = cache_perf_events_i[0];
    assign hpm_events_w[`EDRV32_HPM_DCACHE_MISS-1] = cache_perf_events_i[1];
    assign hpm_events_w[`EDRV32_HPM_DCACHE_WRITEBACK-1] = cache_perf_events_i[2];
    assign hpm_events_w[`EDRV32_HPM_ICACHE_REFILL_WAIT-1] = cache_perf_events_i[3];
    assign hpm_events_w[`EDRV32_HPM_DCACHE_REFILL_WAIT-1] = cache_perf_events_i[4];
    assign hpm_events_w[`EDRV32_HPM_RETIRED_LOAD-1] = hpm_retired_load_w;
    assign hpm_events_w[`EDRV32_HPM_RETIRED_STORE-1] = hpm_retired_store_w;
    assign hpm_events_w[`EDRV32_HPM_RETIRED_BRANCH-1] = hpm_retired_branch_w;
    assign hpm_events_w[`EDRV32_HPM_RETIRED_JUMP-1] = hpm_retired_jump_w;
    assign hpm_events_w[`EDRV32_HPM_RETIRED_MDU-1] = hpm_retired_mdu_w;
    assign hpm_events_w[`EDRV32_HPM_RETIRED_ALU-1] = hpm_retired_alu_w;
    assign hpm_events_w[`EDRV32_HPM_RETIRED_CSR-1] = hpm_retired_csr_w;
    assign hpm_events_w[`EDRV32_HPM_RETIRED_COMPRESSED-1] =
        retire_o && mem2_packet_is_compressed_w;
    assign hpm_events_w[`EDRV32_HPM_EXCEPTION-1] = hpm_exception_w;
    assign hpm_events_w[`EDRV32_HPM_INTERRUPT-1] = hpm_interrupt_w;
    assign hpm_events_w[`EDRV32_HPM_ECALL-1] = hpm_ecall_w;
    assign hpm_events_w[`EDRV32_HPM_IMEM_REQUEST-1] =
        imem_req_valid_o && imem_req_ready_i;
    assign hpm_events_w[`EDRV32_HPM_IMEM_RESPONSE-1] =
        imem_resp_valid_i && imem_resp_ready_o;
    assign hpm_events_w[`EDRV32_HPM_DCACHE_REQUEST-1] =
        dcache_lookup_valid_o && dcache_lookup_ready_i;
    assign hpm_events_w[`EDRV32_HPM_EMPTY_RETIRE_SLOT-1] = !retire_o;
    assign debug_decode_pc_o = decode_valid_w ? decode_pc_w : 32'd0;
    assign debug_decode_instr_o = decode_valid_w ? decode_instr_w : 32'd0;

endmodule
