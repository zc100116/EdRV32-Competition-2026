`timescale 1ns/1ps
`include "edrv32_uop.vh"
`include "edrv32_bus.vh"
`include "edrv32_exception.vh"
`include "edrv32_lsu.vh"
`include "edrv32_csr.vh"
`include "edrv32_hpm.vh"
module tb_irq_store_commit;
reg clk=0; always #5 clk=~clk; reg rst_n=0;
reg  c_valid_i;
wire  c_ready_o;
reg [31:0] c_pc_i;
reg [31:0] c_instr_i;
reg  c_is_compressed_i;
reg [`EDRV32_EPOCH_W-1:0] c_epoch_i;
reg [4:0] c_rd_i;
reg  c_rd_write_i;
reg [`EDRV32_OP_CLASS_W-1:0] c_op_class_i;
reg [31:0] c_result_i;
reg  c_result_ready_i;
reg [31:0] c_mem_addr_i;
reg [`BUS_SZ_W-1:0] c_mem_size_i;
reg  c_mem_unsigned_i;
reg [31:0] c_store_data_i;
reg  c_mem_cacheable_i;
reg  c_lsu_token_valid_i;
reg [`EDRV32_LSU_TOKEN_W-1:0] c_lsu_token_i;
reg  c_mdu_token_i;
reg [`EDRV32_CSR_OP_W-1:0] c_csr_op_i;
reg [11:0] c_csr_addr_i;
reg [31:0] c_csr_src_i;
reg  c_fence_i;
reg  c_fencei_i;
reg  c_mret_i;
reg  c_wfi_i;
reg  c_exception_valid_i;
reg [`EDRV32_EXC_CAUSE_W-1:0] c_exception_cause_i;
reg [31:0] c_exception_tval_i;
reg  c_mdu_pending_i;
reg  c_mdu_authorized_i;
reg  c_mdu_result_valid_i;
wire  c_mdu_result_ready_o;
reg [4:0] c_mdu_result_rd_i;
reg [31:0] c_mdu_result_data_i;
wire  c_mdu_authorize_o;
wire  c_mdu_cancel_o;
wire  c_mdu_writeback_fire_o;
wire  c_load_commit_valid_o;
wire [`EDRV32_LSU_TOKEN_W-1:0] c_load_commit_token_o;
reg  c_load_commit_ready_i;
reg [31:0] c_load_commit_data_i;
reg  c_load_commit_error_i;
wire  c_load_commit_fire_o;
wire  c_store_commit_valid_o;
wire [`EDRV32_LSU_TOKEN_W-1:0] c_store_commit_token_o;
wire  c_store_commit_fire_o;
reg  c_lsu_queues_empty_i;
wire  c_dmem_req_valid_o;
reg  c_dmem_req_ready_i;
wire [31:0] c_dmem_req_addr_o;
wire  c_dmem_req_we_o;
wire [`BUS_SZ_W-1:0] c_dmem_req_size_o;
wire [3:0] c_dmem_req_wstrb_o;
wire [31:0] c_dmem_req_wdata_o;
wire  c_dmem_req_cacheable_o;
reg  c_dmem_resp_valid_i;
wire  c_dmem_resp_ready_o;
reg [31:0] c_dmem_resp_rdata_i;
reg  c_dmem_resp_error_i;
reg  c_irq_soft_i;
reg  c_irq_timer_i;
reg  c_irq_ext_i;
reg [63:0] c_time_value_i;
reg [`EDRV32_HPM_EVENT_W-1:0] c_hpm_events_i;
wire  c_redirect_exception_valid_o;
wire [31:0] c_redirect_exception_target_o;
wire  c_redirect_interrupt_valid_o;
wire [31:0] c_redirect_interrupt_target_o;
wire  c_redirect_mret_valid_o;
wire [31:0] c_redirect_mret_target_o;
wire  c_redirect_fencei_valid_o;
wire [31:0] c_redirect_fencei_target_o;
reg  c_redirect_event_ready_i;
wire  c_flush_younger_lsu_o;
wire  c_kill_younger_o;
wire  c_hpm_busy_memory_o;
wire  c_hpm_busy_other_o;
wire  c_gpr_write_o;
wire [4:0] c_gpr_rd_o;
wire [31:0] c_gpr_value_o;
wire  c_bypass_valid_o;
wire  c_bypass_write_o;
wire  c_bypass_ready_o;
wire [4:0] c_bypass_rd_o;
wire [31:0] c_bypass_value_o;
wire  c_retire_o;
wire [31:0] c_retire_pc_o;
wire [31:0] c_retire_instr_o;
wire  c_retire_exception_o;
wire [31:0] c_retire_cause_o;
wire  c_core_sleep_o;
reg  s_alloc_valid_i;
wire  s_alloc_ready_o;
wire [`EDRV32_LSU_TOKEN_W-1:0] s_alloc_token_o;
reg [31:0] s_alloc_pc_i;
reg [31:0] s_alloc_addr_i;
reg [3:0] s_alloc_wstrb_i;
reg [31:0] s_alloc_wdata_i;
reg [`EDRV32_EPOCH_W-1:0] s_alloc_epoch_i;
reg [`EDRV32_LSU_SEQUENCE_W-1:0] s_alloc_sequence_i;
wire  s_prepare_valid_o;
reg  s_prepare_ready_i;
wire [`EDRV32_LSU_TOKEN_W-1:0] s_prepare_token_o;
wire [31:0] s_prepare_addr_o;
wire [`EDRV32_LSU_SEQUENCE_W-1:0] s_prepare_sequence_o;
reg  s_prepare_response_valid_i;
wire  s_prepare_response_ready_o;
reg [`EDRV32_LSU_TOKEN_W-1:0] s_prepare_response_token_i;
reg  s_prepare_response_error_i;
reg  s_prepare_cancel_valid_i;
reg [`EDRV32_LSU_TOKEN_W-1:0] s_prepare_cancel_token_i;
wire  s_commit_ready_o;
wire  s_commit_error_o;
wire  s_drain_valid_o;
reg  s_drain_ready_i;
wire [`EDRV32_LSU_TOKEN_W-1:0] s_drain_token_o;
wire [31:0] s_drain_addr_o;
wire [3:0] s_drain_wstrb_o;
wire [31:0] s_drain_wdata_o;
reg  s_drain_response_valid_i;
wire  s_drain_response_ready_o;
reg [`EDRV32_LSU_TOKEN_W-1:0] s_drain_response_token_i;
reg  s_drain_response_error_i;
wire  s_async_error_o;
reg  s_load_query_valid_i;
reg [31:0] s_load_query_addr_i;
reg [`BUS_SZ_W-1:0] s_load_query_size_i;
reg  s_load_query_unsigned_i;
wire  s_load_match_o;
wire  s_load_forward_ready_o;
wire [31:0] s_load_forward_data_o;
wire [`EDRV32_LSU_TOKEN_W-1:0] s_load_match_token_o;
wire  s_release_valid_o;
wire [`EDRV32_LSU_TOKEN_W-1:0] s_release_token_o;
wire  s_empty_o;
wire  s_full_o;
wire  s_committed_empty_o;
wire [1:0] s_committed_reservation_count_o;
edrv32_commit_stage #(.CPU_HPM_ENABLE(0)) u_c (
.clk_i(clk),
.rst_n_i(rst_n),
.valid_i(c_valid_i),
.ready_o(c_ready_o),
.pc_i(c_pc_i),
.instr_i(c_instr_i),
.is_compressed_i(c_is_compressed_i),
.epoch_i(c_epoch_i),
.rd_i(c_rd_i),
.rd_write_i(c_rd_write_i),
.op_class_i(c_op_class_i),
.result_i(c_result_i),
.result_ready_i(c_result_ready_i),
.mem_addr_i(c_mem_addr_i),
.mem_size_i(c_mem_size_i),
.mem_unsigned_i(c_mem_unsigned_i),
.store_data_i(c_store_data_i),
.mem_cacheable_i(c_mem_cacheable_i),
.lsu_token_valid_i(c_lsu_token_valid_i),
.lsu_token_i(c_lsu_token_i),
.mdu_token_i(c_mdu_token_i),
.csr_op_i(c_csr_op_i),
.csr_addr_i(c_csr_addr_i),
.csr_src_i(c_csr_src_i),
.fence_i(c_fence_i),
.fencei_i(c_fencei_i),
.mret_i(c_mret_i),
.wfi_i(c_wfi_i),
.exception_valid_i(c_exception_valid_i),
.exception_cause_i(c_exception_cause_i),
.exception_tval_i(c_exception_tval_i),
.mdu_pending_i(c_mdu_pending_i),
.mdu_authorized_i(c_mdu_authorized_i),
.mdu_result_valid_i(c_mdu_result_valid_i),
.mdu_result_ready_o(c_mdu_result_ready_o),
.mdu_result_rd_i(c_mdu_result_rd_i),
.mdu_result_data_i(c_mdu_result_data_i),
.mdu_authorize_o(c_mdu_authorize_o),
.mdu_cancel_o(c_mdu_cancel_o),
.mdu_writeback_fire_o(c_mdu_writeback_fire_o),
.load_commit_valid_o(c_load_commit_valid_o),
.load_commit_token_o(c_load_commit_token_o),
.load_commit_ready_i(c_load_commit_ready_i),
.load_commit_data_i(c_load_commit_data_i),
.load_commit_error_i(c_load_commit_error_i),
.load_commit_fire_o(c_load_commit_fire_o),
.store_commit_valid_o(c_store_commit_valid_o),
.store_commit_token_o(c_store_commit_token_o),
.store_commit_ready_i(s_commit_ready_o),
.store_commit_error_i(s_commit_error_o),
.store_commit_fire_o(c_store_commit_fire_o),
.lsu_queues_empty_i(c_lsu_queues_empty_i),
.dmem_req_valid_o(c_dmem_req_valid_o),
.dmem_req_ready_i(c_dmem_req_ready_i),
.dmem_req_addr_o(c_dmem_req_addr_o),
.dmem_req_we_o(c_dmem_req_we_o),
.dmem_req_size_o(c_dmem_req_size_o),
.dmem_req_wstrb_o(c_dmem_req_wstrb_o),
.dmem_req_wdata_o(c_dmem_req_wdata_o),
.dmem_req_cacheable_o(c_dmem_req_cacheable_o),
.dmem_resp_valid_i(c_dmem_resp_valid_i),
.dmem_resp_ready_o(c_dmem_resp_ready_o),
.dmem_resp_rdata_i(c_dmem_resp_rdata_i),
.dmem_resp_error_i(c_dmem_resp_error_i),
.irq_soft_i(c_irq_soft_i),
.irq_timer_i(c_irq_timer_i),
.irq_ext_i(c_irq_ext_i),
.time_value_i(c_time_value_i),
.hpm_events_i(c_hpm_events_i),
.redirect_exception_valid_o(c_redirect_exception_valid_o),
.redirect_exception_target_o(c_redirect_exception_target_o),
.redirect_interrupt_valid_o(c_redirect_interrupt_valid_o),
.redirect_interrupt_target_o(c_redirect_interrupt_target_o),
.redirect_mret_valid_o(c_redirect_mret_valid_o),
.redirect_mret_target_o(c_redirect_mret_target_o),
.redirect_fencei_valid_o(c_redirect_fencei_valid_o),
.redirect_fencei_target_o(c_redirect_fencei_target_o),
.redirect_event_ready_i(c_redirect_event_ready_i),
.flush_younger_lsu_o(c_flush_younger_lsu_o),
.kill_younger_o(c_kill_younger_o),
.hpm_busy_memory_o(c_hpm_busy_memory_o),
.hpm_busy_other_o(c_hpm_busy_other_o),
.gpr_write_o(c_gpr_write_o),
.gpr_rd_o(c_gpr_rd_o),
.gpr_value_o(c_gpr_value_o),
.bypass_valid_o(c_bypass_valid_o),
.bypass_write_o(c_bypass_write_o),
.bypass_ready_o(c_bypass_ready_o),
.bypass_rd_o(c_bypass_rd_o),
.bypass_value_o(c_bypass_value_o),
.retire_o(c_retire_o),
.retire_pc_o(c_retire_pc_o),
.retire_instr_o(c_retire_instr_o),
.retire_exception_o(c_retire_exception_o),
.retire_cause_o(c_retire_cause_o),
.core_sleep_o(c_core_sleep_o)
);
edrv32_store_queue u_s (
.clk_i(clk),
.rst_n_i(rst_n),
.alloc_valid_i(s_alloc_valid_i),
.alloc_ready_o(s_alloc_ready_o),
.alloc_token_o(s_alloc_token_o),
.alloc_pc_i(s_alloc_pc_i),
.alloc_addr_i(s_alloc_addr_i),
.alloc_wstrb_i(s_alloc_wstrb_i),
.alloc_wdata_i(s_alloc_wdata_i),
.alloc_epoch_i(s_alloc_epoch_i),
.alloc_sequence_i(s_alloc_sequence_i),
.prepare_valid_o(s_prepare_valid_o),
.prepare_ready_i(s_prepare_ready_i),
.prepare_token_o(s_prepare_token_o),
.prepare_addr_o(s_prepare_addr_o),
.prepare_sequence_o(s_prepare_sequence_o),
.prepare_response_valid_i(s_prepare_response_valid_i),
.prepare_response_ready_o(s_prepare_response_ready_o),
.prepare_response_token_i(s_prepare_response_token_i),
.prepare_response_error_i(s_prepare_response_error_i),
.prepare_cancel_valid_i(s_prepare_cancel_valid_i),
.prepare_cancel_token_i(s_prepare_cancel_token_i),
.commit_valid_i(c_store_commit_valid_o),
.commit_token_i(c_store_commit_token_o),
.commit_ready_o(s_commit_ready_o),
.commit_error_o(s_commit_error_o),
.commit_fire_i(c_store_commit_fire_o),
.drain_valid_o(s_drain_valid_o),
.drain_ready_i(s_drain_ready_i),
.drain_token_o(s_drain_token_o),
.drain_addr_o(s_drain_addr_o),
.drain_wstrb_o(s_drain_wstrb_o),
.drain_wdata_o(s_drain_wdata_o),
.drain_response_valid_i(s_drain_response_valid_i),
.drain_response_ready_o(s_drain_response_ready_o),
.drain_response_token_i(s_drain_response_token_i),
.drain_response_error_i(s_drain_response_error_i),
.async_error_o(s_async_error_o),
.load_query_valid_i(s_load_query_valid_i),
.load_query_addr_i(s_load_query_addr_i),
.load_query_size_i(s_load_query_size_i),
.load_query_unsigned_i(s_load_query_unsigned_i),
.load_match_o(s_load_match_o),
.load_forward_ready_o(s_load_forward_ready_o),
.load_forward_data_o(s_load_forward_data_o),
.load_match_token_o(s_load_match_token_o),
.release_valid_o(s_release_valid_o),
.release_token_o(s_release_token_o),
.flush_i(c_kill_younger_o),
.empty_o(s_empty_o),
.full_o(s_full_o),
.committed_empty_o(s_committed_empty_o),
.committed_reservation_count_o(s_committed_reservation_count_o)
);
reg [`EDRV32_LSU_TOKEN_W-1:0] saved_token;
task csr_write;
input [11:0] addr; input [31:0] value;
begin
 @(negedge clk); c_valid_i=1; c_op_class_i=`EDRV32_OP_CSR; c_csr_op_i=`EDRV32_CSR_WRITE; c_csr_addr_i=addr; c_csr_src_i=value;
 #1; while(!c_ready_o) begin @(negedge clk); #1; end
 @(posedge clk); @(negedge clk); c_valid_i=0;
end endtask
initial begin
c_valid_i=0;
c_pc_i=0;
c_instr_i=0;
c_is_compressed_i=0;
c_epoch_i=0;
c_rd_i=0;
c_rd_write_i=0;
c_op_class_i=0;
c_result_i=0;
c_result_ready_i=0;
c_mem_addr_i=0;
c_mem_size_i=0;
c_mem_unsigned_i=0;
c_store_data_i=0;
c_mem_cacheable_i=0;
c_lsu_token_valid_i=0;
c_lsu_token_i=0;
c_mdu_token_i=0;
c_csr_op_i=0;
c_csr_addr_i=0;
c_csr_src_i=0;
c_fence_i=0;
c_fencei_i=0;
c_mret_i=0;
c_wfi_i=0;
c_exception_valid_i=0;
c_exception_cause_i=0;
c_exception_tval_i=0;
c_mdu_pending_i=0;
c_mdu_authorized_i=0;
c_mdu_result_valid_i=0;
c_mdu_result_rd_i=0;
c_mdu_result_data_i=0;
c_load_commit_ready_i=0;
c_load_commit_data_i=0;
c_load_commit_error_i=0;
c_lsu_queues_empty_i=0;
c_dmem_req_ready_i=0;
c_dmem_resp_valid_i=0;
c_dmem_resp_rdata_i=0;
c_dmem_resp_error_i=0;
c_irq_soft_i=0;
c_irq_timer_i=0;
c_irq_ext_i=0;
c_time_value_i=0;
c_hpm_events_i=0;
c_redirect_event_ready_i=0;
s_alloc_valid_i=0;
s_alloc_pc_i=0;
s_alloc_addr_i=0;
s_alloc_wstrb_i=0;
s_alloc_wdata_i=0;
s_alloc_epoch_i=0;
s_alloc_sequence_i=0;
s_prepare_ready_i=0;
s_prepare_response_valid_i=0;
s_prepare_response_token_i=0;
s_prepare_response_error_i=0;
s_prepare_cancel_valid_i=0;
s_prepare_cancel_token_i=0;
s_drain_ready_i=0;
s_drain_response_valid_i=0;
s_drain_response_token_i=0;
s_drain_response_error_i=0;
s_load_query_valid_i=0;
s_load_query_addr_i=0;
s_load_query_size_i=0;
s_load_query_unsigned_i=0;
c_redirect_event_ready_i=1; s_prepare_ready_i=1;
repeat(3) @(negedge clk); rst_n=1;
csr_write(`EDRV32_CSR_MTVEC,32'h100);
csr_write(`EDRV32_CSR_MIE,32'h800);
csr_write(`EDRV32_CSR_MSTATUS,32'h8);
@(negedge clk); s_alloc_valid_i=1; s_alloc_addr_i=32'h80000100; s_alloc_wstrb_i=15; s_alloc_wdata_i=32'hdeadbeef;
#1; saved_token=s_alloc_token_o;
@(negedge clk); s_alloc_valid_i=0;
@(negedge clk); s_prepare_response_valid_i=1; s_prepare_response_token_i=saved_token;
@(negedge clk); s_prepare_response_valid_i=0; c_irq_ext_i=1;
repeat(2) @(negedge clk);
c_valid_i=1; c_op_class_i=`EDRV32_OP_STORE; c_mem_cacheable_i=1; c_lsu_token_valid_i=1; c_lsu_token_i=saved_token; c_mem_addr_i=32'h80000100; c_pc_i=32'h80000080;
#1;
if(c_redirect_interrupt_valid_o!==1 || c_retire_o!==0 ||
   c_kill_younger_o!==1 || c_store_commit_fire_o!==0)
  $fatal(1,"interrupted Store must redirect without architectural commit");
@(posedge clk); #1;
if(u_s.count_r!==0 || u_s.committed_count_r!==0 ||
   s_drain_valid_o!==0 || s_committed_reservation_count_o!==0)
  $fatal(1,"interrupted Store survived the kill boundary");
$display("PASS: interrupted non-retired Store is removed before CSB commit");
$finish;
end
initial begin #10000; $fatal(1,"timeout"); end
endmodule

