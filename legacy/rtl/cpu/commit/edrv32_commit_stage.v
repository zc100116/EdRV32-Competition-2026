// ============================================================================
// File        : edrv32_commit_stage.v
// Ownership   : Final pipeline stage.  CSR state is a peer dependency, not the
//               directory owner of COMMIT.
// Description : COMMIT stage and sole irrevocable side-effect owner. It issues
//               the bring-up data-memory transaction, commits GPR/CSR state,
//               takes precise traps, and emits registered-controller events.
// ============================================================================
`include "edrv32_uop.vh"
`include "edrv32_pair.vh"
`include "edrv32_bus.vh"
`include "edrv32_exception.vh"
`include "edrv32_lsu.vh"
`include "edrv32_csr.vh"
`include "edrv32_hpm.vh"

module edrv32_commit_stage #(
    parameter integer DUAL_ISSUE = 0,
    parameter integer MULTI_EVENT_ENABLE = DUAL_ISSUE,
    parameter integer CPU_HPM_ENABLE = 1,
    parameter [31:0] MVENDORID = 32'd0,
    parameter [31:0] MARCHID   = 32'd0,
    parameter [31:0] MIMPID    = 32'd0,
    parameter [31:0] MHARTID   = 32'd0
)(
    input  wire                          clk_i,
    input  wire                          rst_n_i,

    input  wire [`EDRV32_PAIR_RESULT_W-1:0] second_i,
    input  wire [`EDRV32_HPM_EVENT_W-1:0]   hpm_second_events_i,
    output wire                             second_gpr_write_o,
    output wire [4:0]                       second_gpr_rd_o,
    output wire [31:0]                      second_gpr_value_o,
    output wire                             second_retire_o,
    output wire [31:0]                      second_retire_pc_o,
    output wire [31:0]                      second_retire_instr_o,
    output wire                             second_retire_compressed_o,
    output wire [1:0]                       retire_count_o,

    // Resident MEM2-to-COMMIT packet.
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
    input  wire                          mem_cacheable_i,
    input  wire                          lsu_token_valid_i,
    input  wire [`EDRV32_LSU_TOKEN_W-1:0] lsu_token_i,
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

    // Long-latency MDU completion and commit authorization.
    input  wire                          mdu_pending_i,
    input  wire                          mdu_authorized_i,
    input  wire                          mdu_result_valid_i,
    output wire                          mdu_result_ready_o,
    input  wire [4:0]                    mdu_result_rd_i,
    input  wire [31:0]                   mdu_result_data_i,
    output wire                          mdu_authorize_o,
    output wire                          mdu_cancel_o,
    output wire                          mdu_writeback_fire_o,

    // Cacheable load result owned by the decoupled Load Queue.
    output wire                          load_commit_valid_o,
    output wire [`EDRV32_LSU_TOKEN_W-1:0] load_commit_token_o,
    input  wire                          load_commit_ready_i,
    input  wire [31:0]                   load_commit_data_i,
    input  wire                          load_commit_error_i,
    output wire                          load_commit_fire_o,

    output wire                          store_commit_valid_o,
    output wire [`EDRV32_LSU_TOKEN_W-1:0] store_commit_token_o,
    input  wire                          store_commit_ready_i,
    input  wire                          store_commit_error_i,
    output wire                          store_commit_fire_o,
    input  wire                          lsu_queues_empty_i,

    // Blocking data-memory request/response channel.
    output wire                          dmem_req_valid_o,
    input  wire                          dmem_req_ready_i,
    output wire [31:0]                   dmem_req_addr_o,
    output wire                          dmem_req_we_o,
    output wire [`BUS_SZ_W-1:0]          dmem_req_size_o,
    output wire [3:0]                    dmem_req_wstrb_o,
    output wire [31:0]                   dmem_req_wdata_o,
    output wire                          dmem_req_cacheable_o,
    input  wire                          dmem_resp_valid_i,
    output wire                          dmem_resp_ready_o,
    input  wire [31:0]                   dmem_resp_rdata_i,
    input  wire                          dmem_resp_error_i,

    // Interrupt sources and architectural counters.
    input  wire                          irq_soft_i,
    input  wire                          irq_timer_i,
    input  wire                          irq_ext_i,
    input  wire [63:0]                   time_value_i,
    input  wire [`EDRV32_HPM_EVENT_W-1:0] hpm_events_i,

    // Precise redirects; the arbiter acknowledges exactly one event.
    output wire                          redirect_exception_valid_o,
    output wire [31:0]                   redirect_exception_target_o,
    output wire                          redirect_interrupt_valid_o,
    output wire [31:0]                   redirect_interrupt_target_o,
    output wire                          redirect_mret_valid_o,
    output wire [31:0]                   redirect_mret_target_o,
    output wire                          redirect_fencei_valid_o,
    output wire [31:0]                   redirect_fencei_target_o,
    input  wire                          redirect_event_ready_i,
    output wire                          flush_younger_lsu_o,
    output wire                          kill_younger_o,

    // Mutual-exclusion HPM attribution: why the resident packet cannot retire.
    output wire                          hpm_busy_memory_o,
    output wire                          hpm_busy_other_o,

    // Architectural GPR writeback.
    output wire                          gpr_write_o,
    output wire [4:0]                    gpr_rd_o,
    output wire [31:0]                   gpr_value_o,

    // Young-instruction bypass view of the resident COMMIT packet.
    output wire                          bypass_valid_o,
    output wire                          bypass_write_o,
    output wire                          bypass_ready_o,
    output wire [4:0]                    bypass_rd_o,
    output wire [31:0]                   bypass_value_o,

    // Retirement trace and sleep indication.
    output wire                          retire_o,
    output wire [31:0]                   retire_pc_o,
    output wire [31:0]                   retire_instr_o,
    output wire                          retire_exception_o,
    output wire [31:0]                   retire_cause_o,
    output wire                          core_sleep_o
);

    // --------------------------------------------------------------------
    // Blocking data-memory transaction state
    // --------------------------------------------------------------------
    localparam [1:0] MEM_IDLE = 2'd0,
                     MEM_WAIT = 2'd1,
                     MEM_DONE = 2'd2;
    reg [1:0] memory_state_r;
    reg [31:0] memory_rdata_r;
    reg memory_error_r;

    // Operation classes used by the completion rules below.
    wire is_load_w = (op_class_i == `EDRV32_OP_LOAD);
    wire is_store_w = (op_class_i == `EDRV32_OP_STORE);
    wire is_memory_w = is_load_w || is_store_w;
    wire is_csr_w = (op_class_i == `EDRV32_OP_CSR);
    wire queued_load_w = is_load_w && lsu_token_valid_i;
    wire queued_store_w = is_store_w && lsu_token_valid_i;
    assign load_commit_valid_o = valid_i && queued_load_w;
    assign load_commit_token_o = lsu_token_i;
    assign store_commit_valid_o = valid_i && queued_store_w;
    assign store_commit_token_o = lsu_token_i;

    // CSR read/modify/write intent is computed before precise exception
    // selection; csr_write_fire_w later gates the irreversible update.
    wire csr_write_intent_w = is_csr_w &&
        ((csr_op_i == `EDRV32_CSR_WRITE) ||
         (((csr_op_i == `EDRV32_CSR_SET) ||
           (csr_op_i == `EDRV32_CSR_CLEAR)) && (csr_src_i != 32'd0)));
    wire [31:0] csr_read_data_w;
    wire csr_access_illegal_w;
    reg csr_snapshot_valid_r;
    reg [31:0] csr_read_snapshot_r;
    reg csr_access_illegal_r;
    reg csr_write_intent_r;
    reg [`EDRV32_CSR_OP_W-1:0] csr_op_snapshot_r;
    reg [31:0] csr_src_snapshot_r;
    wire [31:0] csr_mtvec_w;
    wire [31:0] csr_mepc_w;
    wire [31:0] csr_mie_w;
    wire [31:0] csr_mip_w;
    wire csr_mstatus_mie_w;

    // Interrupts are sampled at the COMMIT boundary.  Taking an interrupt at
    // the following instruction boundary is architecturally legal and keeps
    // CLINT/PLIC combinational logic out of retirement, kill and CSR-write
    // cones.  The sampled values also back the architectural mip view.
    reg irq_soft_r;
    reg irq_timer_r;
    reg irq_ext_r;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            irq_soft_r <= 1'b0;
            irq_timer_r <= 1'b0;
            irq_ext_r <= 1'b0;
        end else begin
            irq_soft_r <= irq_soft_i;
            irq_timer_r <= irq_timer_i;
            irq_ext_r <= irq_ext_i;
        end
    end

    // CSR address decode used to feed exception, global kill and bypass-ready
    // control in the same cycle.  Snapshotting both read data and legality
    // gives CSR operations a short validation micro-stage while every common
    // instruction class retains its single-cycle COMMIT behavior.
    wire csr_control_ready_w = !is_csr_w || csr_snapshot_valid_r;
    wire [31:0] csr_commit_read_data_w = csr_snapshot_valid_r
        ? csr_read_snapshot_r : 32'd0;

    // Register only the compact CSR command at validation.  The following
    // local RMW uses the registered read/source/op values, keeping the MEM2
    // source bus out of write-enable/data cones without duplicating the large
    // live CSR read mux into a second 32-bit snapshot bank.
    reg [31:0] csr_write_data_w;
    always @* begin
        case (csr_op_snapshot_r)
            `EDRV32_CSR_WRITE: csr_write_data_w = csr_src_snapshot_r;
            `EDRV32_CSR_SET:
                csr_write_data_w = csr_commit_read_data_w | csr_src_snapshot_r;
            `EDRV32_CSR_CLEAR:
                csr_write_data_w = csr_commit_read_data_w & ~csr_src_snapshot_r;
            default: csr_write_data_w = csr_commit_read_data_w;
        endcase
    end

    // Byte-lane formatting remains combinational around the memory state.
    wire [31:0] formatted_load_data_w;
    wire [31:0] formatted_store_data_w;
    wire [3:0] formatted_store_wstrb_w;
    edrv32_lsu_format u_lsu_format (
        // Access attributes and returned load word.
        .addr_lsb_i(mem_addr_i[1:0]),
        .size_i(mem_size_i),
        .mem_rdata_i(memory_rdata_r),
        .load_unsigned_i(mem_unsigned_i),
        .load_data_o(formatted_load_data_w),

        // Store value expanded into bus lanes.
        .store_wdata_i(store_data_i),
        .store_data_o(formatted_store_data_w),
        .store_wstrb_o(formatted_store_wstrb_w)
    );

    // Synchronous faults take priority over interrupts and normal retirement.
    wire memory_needs_request_w = (is_store_w && !queued_store_w) ||
                                  (is_load_w && !result_ready_i &&
                                   !queued_load_w);
    // A non-idle memory state can only be owned by the resident load/store:
    // COMMIT cannot release that packet until the response is consumed.  Use
    // that registered ownership fact directly instead of decoding op_class_i
    // again in the exception/redirect cone.
    wire memory_access_error_w = (memory_state_r == MEM_DONE) &&
                                 memory_error_r;
    wire load_queue_error_w = queued_load_w && load_commit_ready_i &&
                              load_commit_error_i;
    wire store_queue_error_w = queued_store_w && store_commit_ready_i &&
                               store_commit_error_i;
    wire csr_illegal_exception_w = is_csr_w && csr_snapshot_valid_r &&
                                   csr_access_illegal_r;
    wire synchronous_exception_w = exception_valid_i ||
                                     csr_illegal_exception_w ||
                                     memory_access_error_w ||
                                     load_queue_error_w || store_queue_error_w;
    reg [`EDRV32_EXC_CAUSE_W-1:0] synchronous_cause_w;
    reg [31:0] synchronous_tval_w;
    always @* begin
        synchronous_cause_w = exception_cause_i;
        synchronous_tval_w  = exception_tval_i;
        if (csr_illegal_exception_w) begin
            synchronous_cause_w = `EDRV32_EXC_ILLEGAL_INSTR;
            synchronous_tval_w  = instr_i;
        end else if (store_queue_error_w) begin
            synchronous_cause_w = `EDRV32_EXC_STORE_ACCESS;
            synchronous_tval_w = mem_addr_i;
        end else if (load_queue_error_w) begin
            synchronous_cause_w = `EDRV32_EXC_LOAD_ACCESS;
            synchronous_tval_w = mem_addr_i;
        end else if (memory_access_error_w) begin
            synchronous_cause_w = is_load_w ? `EDRV32_EXC_LOAD_ACCESS
                                               : `EDRV32_EXC_STORE_ACCESS;
            synchronous_tval_w  = mem_addr_i;
        end
    end

    // Interrupt eligibility and WFI wakeup policy.
    wire [31:0] irq_active_w = csr_mie_w & csr_mip_w;
    wire irq_ext_active_w = irq_active_w[`EDRV32_IRQ_M_EXT_BIT];
    wire irq_soft_active_w = irq_active_w[`EDRV32_IRQ_M_SOFT_BIT];
    wire irq_timer_active_w = irq_active_w[`EDRV32_IRQ_M_TIMER_BIT];
    wire interrupt_pending_w = csr_mstatus_mie_w &&
                               (irq_ext_active_w || irq_soft_active_w ||
                                irq_timer_active_w);
    // WFI wake follows the frozen baseline: a locally enabled pending source
    // wakes the hart even when global MIE is zero.
    wire wfi_wake_w = irq_ext_active_w || irq_soft_active_w ||
                      irq_timer_active_w;
    wire authorized_mdu_wait_w = mdu_pending_i && mdu_authorized_i;
    // Non-memory packets always observe MEM_IDLE.  A memory packet may be
    // interrupted before its request is accepted, but never while an accepted
    // transaction is waiting or after a store may already have taken effect.
    // Expressing the rule from the registered transaction state is equivalent
    // and keeps op_class_i out of the global redirect/kill fanout cone.
    wire interrupt_can_preempt_w = (memory_state_r == MEM_IDLE);
    wire take_interrupt_w = valid_i && csr_control_ready_w &&
                            !synchronous_exception_w &&
                            interrupt_pending_w && interrupt_can_preempt_w &&
                            !authorized_mdu_wait_w;
    wire [31:0] interrupt_cause_w = irq_ext_active_w ? `EDRV32_CAUSE_INT_M_EXT :
                                          irq_soft_active_w ? `EDRV32_CAUSE_INT_M_SOFT :
                                                              `EDRV32_CAUSE_INT_M_TIMER;

    // Redirect targets and mutually exclusive architectural redirect causes.
    wire [31:0] mtvec_base_w = {csr_mtvec_w[31:2], 2'b00};
    wire [31:0] interrupt_target_w = (csr_mtvec_w[1:0] == 2'b01)
        ? mtvec_base_w + {interrupt_cause_w[29:0], 2'b00}
        : mtvec_base_w;
    wire [31:0] fallthrough_w = pc_i + (is_compressed_i ? 32'd2 : 32'd4);

    assign redirect_exception_valid_o = valid_i && synchronous_exception_w &&
                                        !authorized_mdu_wait_w;
    assign redirect_exception_target_o = mtvec_base_w;
    assign redirect_interrupt_valid_o = take_interrupt_w;
    assign redirect_interrupt_target_o = interrupt_target_w;
    assign redirect_mret_valid_o = valid_i && !synchronous_exception_w &&
                                   !take_interrupt_w && mret_i &&
                                   !authorized_mdu_wait_w;
    assign redirect_mret_target_o = csr_mepc_w;
    // Both FENCE variants serialize by flushing/refetching younger work.  The
    // cached integration distinguishes plain FENCE from FENCE.I when deciding
    // whether the instruction cache must also be invalidated.
    wire fence_serialize_w = valid_i && !synchronous_exception_w &&
                             !take_interrupt_w && !mret_i &&
                             (fence_i || fencei_i) &&
                             !authorized_mdu_wait_w;
    // Once a fence becomes the oldest instruction, every speculative LSU
    // entry is younger than it.  Discard those entries before waiting for
    // committed stores to drain; otherwise a younger load can make the fence
    // wait for work that cannot itself reach COMMIT.
    assign flush_younger_lsu_o = fence_serialize_w;
    assign redirect_fencei_valid_o = fence_serialize_w &&
                                     lsu_queues_empty_i;
    assign redirect_fencei_target_o = fallthrough_w;

    wire redirect_event_valid_w = redirect_exception_valid_o ||
                                  redirect_interrupt_valid_o ||
                                  redirect_mret_valid_o ||
                                  redirect_fencei_valid_o;
    wire redirect_event_fire_w = redirect_event_valid_w && redirect_event_ready_i;

    // The resident instruction exclusively owns a blocking memory transaction.
    wire memory_request_allowed_w = valid_i && memory_needs_request_w &&
                                    !exception_valid_i &&
                                    !take_interrupt_w &&
                                    (memory_state_r == MEM_IDLE);
    assign dmem_req_valid_o = memory_request_allowed_w;
    assign dmem_req_addr_o  = mem_addr_i;
    assign dmem_req_we_o    = is_store_w;
    assign dmem_req_size_o  = `BUS_SZ_WORD;
    assign dmem_req_wstrb_o = is_store_w ? formatted_store_wstrb_w : 4'b0000;
    assign dmem_req_wdata_o = formatted_store_data_w;
    assign dmem_req_cacheable_o = mem_cacheable_i;
    wire memory_request_fire_w = dmem_req_valid_o && dmem_req_ready_i;
    assign dmem_resp_ready_o = valid_i && memory_needs_request_w &&
        (((memory_state_r == MEM_IDLE) && memory_request_fire_w) ||
         (memory_state_r == MEM_WAIT));
    wire memory_response_fire_w = dmem_resp_valid_i && dmem_resp_ready_o;

    // COMMIT releases the packet only after its memory, redirect, WFI and MDU
    // obligations are complete.  The registered MEM_DONE state keeps the
    // completion decision free of the request/response combinational cone;
    // a same-cycle store completion would couple the dcache commit ack back
    // through the fabric arbitration into this ready path.
    wire memory_complete_w = !memory_needs_request_w ||
                             (memory_state_r == MEM_DONE);
    wire load_queue_complete_w = !queued_load_w || load_commit_ready_i;
    wire store_queue_complete_w = !queued_store_w || store_commit_ready_i;
    wire normal_complete_w = valid_i && csr_control_ready_w &&
                              !synchronous_exception_w &&
                              !take_interrupt_w && memory_complete_w &&
                              load_queue_complete_w &&
                              store_queue_complete_w &&
                             (!wfi_i || wfi_wake_w) &&
                             !authorized_mdu_wait_w;
    wire needs_redirect_w = synchronous_exception_w || take_interrupt_w ||
                            mret_i || fence_i || fencei_i;
    assign ready_o = valid_i &&
        (needs_redirect_w ? (redirect_event_valid_w && redirect_event_ready_i)
                          : normal_complete_w);
    assign kill_younger_o = redirect_event_fire_w;

    // One-hot retirement-blocking split for the empty-retire attribution.
    // A blocking memory transaction (store/uncached/MMIO in flight) wins;
    // every other block (MDU authorization, WFI, CSR validation, redirect
    // slot) is reported by the complementary term.
    assign hpm_busy_memory_o = valid_i &&
        ((memory_needs_request_w && (memory_state_r != MEM_DONE)) ||
         (queued_load_w && !load_commit_ready_i) ||
         (queued_store_w && !store_commit_ready_i));
    assign hpm_busy_other_o = valid_i && !ready_o && !hpm_busy_memory_o;

    // GPR writeback arbitrates a normal retire against an MDU result. A ready
    // MDU can write on its own token-retirement edge; that token excludes the
    // normal writer. An unfinished authorized MDU retains the old late-write
    // path. The two writers are never accepted in the same cycle.
    wire retire_fire_w = valid_i && ready_o &&
                         !synchronous_exception_w && !take_interrupt_w;
    wire second_valid_w;
    wire [31:0] second_pc_w;
    wire [31:0] second_instr_w;
    wire second_compressed_w;
    wire [`EDRV32_EPOCH_W-1:0] second_epoch_w;
    wire [4:0] second_rd_w;
    wire second_write_w;
    wire [31:0] second_value_w;
    assign {second_valid_w, second_pc_w, second_instr_w, second_compressed_w,
        second_epoch_w, second_rd_w, second_write_w, second_value_w} = second_i;
    // Interrupts and faults precede A, so neither member writes on that edge.
    // An authorized older MDU blocks the parent through the existing ready rule.
    // The parent completion includes queued/cached or blocking/MMIO memory
    // completion. A memory fault or an interrupt suppresses both members.
    wire second_parent_eligible_w = (op_class_i == `EDRV32_OP_ALU) ||
        (op_class_i == `EDRV32_OP_LOAD) || (op_class_i == `EDRV32_OP_STORE);
    wire second_retire_w = (DUAL_ISSUE != 0) && retire_fire_w && second_valid_w &&
        second_parent_eligible_w && (epoch_i == second_epoch_w);
    assign second_retire_o = second_retire_w;
    assign second_retire_pc_o = second_pc_w;
    assign second_retire_instr_o = second_instr_w;
    assign second_retire_compressed_o = second_compressed_w;
    assign retire_count_o = retire_fire_w ? (second_retire_w ? 2'd2 : 2'd1) : 2'd0;
    assign second_gpr_write_o = second_retire_w && second_write_w && second_rd_w != 5'd0;
    assign second_gpr_rd_o = second_rd_w;
    assign second_gpr_value_o = second_value_w;

    wire [31:0] architectural_result_w = queued_load_w
                                                ? load_commit_data_i :
                                            is_load_w ? (result_ready_i
                                                    ? result_i
                                                    : formatted_load_data_w) :
                                                is_csr_w ? csr_commit_read_data_w :
                                                           result_i;
    wire normal_gpr_write_w = retire_fire_w && rd_write_i &&
                              !mdu_token_i && (rd_i != 5'd0);
    assign mdu_result_ready_o = !normal_gpr_write_w;
    assign mdu_writeback_fire_o = mdu_result_valid_i && mdu_result_ready_o;
    assign gpr_write_o = normal_gpr_write_w || mdu_writeback_fire_o;
    assign gpr_rd_o    = normal_gpr_write_w ? rd_i : mdu_result_rd_i;
    assign gpr_value_o = normal_gpr_write_w ? architectural_result_w
                                             : mdu_result_data_i;

    assign bypass_valid_o = valid_i;
    assign bypass_write_o = rd_write_i && !mdu_token_i;
    assign bypass_ready_o = csr_control_ready_w && !synchronous_exception_w &&
        (queued_load_w ? load_commit_ready_i && !load_commit_error_i :
         is_load_w ? (result_ready_i || (memory_state_r == MEM_DONE)) :
         is_csr_w ? 1'b1 : result_ready_i);
    assign bypass_rd_o = rd_i;
    assign bypass_value_o = architectural_result_w;

    // Architectural retirement and externally visible trace information.
    assign retire_o = retire_fire_w;
    // Queue release/authorization is an architectural retirement side effect.
    // ready_o also accepts exception and interrupt redirects, so it cannot be
    // used here: an interrupted Store must remain speculative and be removed
    // by the younger-state flush rather than enter the committed buffer.
    assign load_commit_fire_o = retire_fire_w && queued_load_w &&
                                load_commit_ready_i;
    assign store_commit_fire_o = retire_fire_w && queued_store_w &&
                                 store_commit_ready_i;
    assign retire_pc_o = pc_i;
    assign retire_instr_o = instr_i;
    assign retire_exception_o = redirect_event_fire_w &&
                                (redirect_exception_valid_o ||
                                 redirect_interrupt_valid_o);
    assign retire_cause_o = take_interrupt_w ? interrupt_cause_w
                                             : {28'd0, synchronous_cause_w};
    assign core_sleep_o = valid_i && wfi_i &&
                          !synchronous_exception_w && !wfi_wake_w;

    // Irreversible CSR and MDU side effects are generated only from accepted
    // redirect events or a normal retirement handshake.
    // Once the CSR snapshot is valid, a CSR has no memory, WFI or MDU-token
    // completion obligation.  State the normal CSR retirement qualification
    // directly instead of feeding every CSR storage bit from the generic
    // ready_o -> retire_fire_w cone.  These terms are exactly the CSR subset
    // of retire_fire_w: synchronous faults and interrupts still win, while an
    // already-authorized older MDU still blocks architectural side effects.
    wire csr_normal_commit_w = valid_i && is_csr_w && csr_snapshot_valid_r &&
                               !exception_valid_i &&
                               !csr_access_illegal_r &&
                               !interrupt_pending_w &&
                               !authorized_mdu_wait_w;
    wire csr_write_fire_w = csr_normal_commit_w && csr_write_intent_r;
    wire trap_enter_fire_w = redirect_event_fire_w &&
                             (redirect_exception_valid_o ||
                              redirect_interrupt_valid_o);
    wire mret_fire_w = redirect_event_fire_w && redirect_mret_valid_o;
    assign mdu_authorize_o = retire_fire_w && mdu_token_i;
    assign mdu_cancel_o = redirect_event_fire_w && mdu_pending_i &&
                          !mdu_authorized_i;

    // CSR storage is a peer state owner; COMMIT supplies only qualified events.
    edrv32_csr_file #(
        .DUAL_ISSUE(DUAL_ISSUE),
        .MULTI_EVENT_ENABLE(MULTI_EVENT_ENABLE),
        .CPU_HPM_ENABLE(CPU_HPM_ENABLE),
        .MVENDORID(MVENDORID),
        .MARCHID(MARCHID),
        .MIMPID(MIMPID),
        .MHARTID(MHARTID)
    ) u_csr_file (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),

        // Combinational CSR read and legality check.
        .read_addr_i(csr_addr_i),
        .read_access_i(is_csr_w),
        .write_intent_i(csr_write_intent_w),
        .read_data_o(csr_read_data_w),
        .access_illegal_o(csr_access_illegal_w),

        // Qualified CSR write at normal retirement.
        .write_fire_i(csr_write_fire_w),
        .write_addr_i(csr_addr_i),
        .write_data_i(csr_write_data_w),
        .retire_i(retire_fire_w),
        .retire_second_i(second_retire_w),

        // Precise trap entry and return events.
        .trap_enter_i(trap_enter_fire_w),
        .trap_epc_i((take_interrupt_w && wfi_i)
                        ? fallthrough_w : pc_i),
        .trap_cause_i(redirect_interrupt_valid_o ? interrupt_cause_w
                         : {28'd0, synchronous_cause_w}),
        .trap_tval_i(redirect_interrupt_valid_o ? 32'd0 : synchronous_tval_w),
        .mret_fire_i(mret_fire_w),

        // Asynchronous machine state and performance events.
        .irq_soft_i(irq_soft_r),
        .irq_timer_i(irq_timer_r),
        .irq_ext_i(irq_ext_r),
        .time_value_i(time_value_i),
        .hpm_events_i(hpm_events_i),
        .hpm_second_events_i(hpm_second_events_i),

        // Privileged state consumed by COMMIT control logic.
        .mtvec_o(csr_mtvec_w),
        .mepc_o(csr_mepc_w),
        .mie_o(csr_mie_w),
        .mip_o(csr_mip_w),
        .mstatus_mie_o(csr_mstatus_mie_w)
    );

    // A CSR packet remains resident for one validation cycle.  The following
    // cycle consumes only registered CSR decode results, so address bits cannot
    // become same-cycle global control signals.  ready_o clears the snapshot
    // exactly when the owning packet leaves COMMIT.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            csr_snapshot_valid_r <= 1'b0;
            csr_read_snapshot_r <= 32'd0;
            csr_access_illegal_r <= 1'b0;
            csr_write_intent_r <= 1'b0;
            csr_op_snapshot_r <= `EDRV32_CSR_NONE;
            csr_src_snapshot_r <= 32'd0;
        end else if (!valid_i || ready_o) begin
            csr_snapshot_valid_r <= 1'b0;
            csr_write_intent_r <= 1'b0;
        end else if (is_csr_w && !csr_snapshot_valid_r) begin
            csr_snapshot_valid_r <= 1'b1;
            csr_read_snapshot_r <= csr_read_data_w;
            csr_access_illegal_r <= csr_access_illegal_w;
            csr_write_intent_r <= csr_write_intent_w;
            csr_op_snapshot_r <= csr_op_i;
            csr_src_snapshot_r <= csr_src_i;
        end else if (!is_csr_w) begin
            csr_snapshot_valid_r <= 1'b0;
            csr_write_intent_r <= 1'b0;
        end
    end

    // Blocking data-memory transaction ownership state.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            memory_state_r <= MEM_IDLE;
        end else begin
            case (memory_state_r)
                MEM_IDLE: begin
                    if (memory_request_fire_w) begin
                        if (memory_response_fire_w) begin
                            memory_state_r <= MEM_DONE;
                        end else begin
                            memory_state_r <= MEM_WAIT;
                        end
                    end
                end
                MEM_WAIT: begin
                    if (memory_response_fire_w)
                        memory_state_r <= MEM_DONE;
                end
                MEM_DONE: begin
                    if (valid_i && ready_o)
                        memory_state_r <= MEM_IDLE;
                end
                default: memory_state_r <= MEM_IDLE;
            endcase
        end
    end

    // Memory response payload/error context. These registers never own the
    // transaction lifecycle and therefore do not write memory_state_r.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            memory_rdata_r <= 32'd0;
            memory_error_r <= 1'b0;
        end else if (memory_request_fire_w) begin
            if (memory_response_fire_w) begin
                memory_rdata_r <= dmem_resp_rdata_i;
                memory_error_r <= dmem_resp_error_i;
            end else begin
                memory_error_r <= 1'b0;
            end
        end else if ((memory_state_r == MEM_WAIT) && memory_response_fire_w) begin
            memory_rdata_r <= dmem_resp_rdata_i;
            memory_error_r <= dmem_resp_error_i;
        end
    end

endmodule
