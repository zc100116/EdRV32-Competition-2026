// ============================================================================
// File        : edrv32_hpm_attribution.v
// Description : Mutual-exclusion empty-retire attribution and auxiliary
//               performance events 41..98. Observation only: none of these
//               outputs feeds any functional path, so the extra comparison
//               logic stays out of every critical cone.
// Notes       : On each non-retire cycle exactly one of events 41..56 fires,
//               chosen by a fixed priority walk from COMMIT toward IF1. The
//               walk finds the deepest (most downstream) active stall and
//               falls through to event 56 when the retire stream is flowing
//               but a hole is in transit. Sum(41..56) therefore equals the
//               empty-retire count exactly. Events 57..61 form the retire-gap
//               histogram, 62..77 the RAW producer/consumer matrix counted on
//               decode dependency-stall cycles, 78..83 frontend fetch, and
//               84..98 branch-predictor diagnostics.
// ============================================================================
`include "edrv32_uop.vh"
`include "edrv32_hpm.vh"

module edrv32_hpm_attribution (
    input  wire                         clk_i,
    input  wire                         rst_n_i,

    // Retirement observation.
    input  wire                         retire_i,

    // COMMIT boundary and its blocking reasons.
    input  wire                         mem2_packet_valid_i,
    input  wire                         mem2_packet_accept_i,
    input  wire                         commit_busy_memory_i,
    input  wire                         commit_busy_other_i,

    // Exact queued-Load state: resident in MEM2 with its token still waiting
    // for data in the Load Queue.
    input  wire                         mem2_hazard_valid_i,
    input  wire                         mem2_cache_wait_i,

    // MEM1 and EX boundary occupancy.
    input  wire                         mem1_packet_valid_i,
    input  wire                         mem1_packet_accept_i,
    input  wire                         ex_valid_i,
    input  wire                         ex_accept_i,
    input  wire                         ex_late_load_stall_i,
    input  wire                         ex_late_mdu_stall_i,

    // DECODE boundary and stall classification.
    input  wire                         decode_valid_i,
    input  wire                         decode_accept_i,
    input  wire                         decode_dependency_stall_i,
    input  wire                         decode_structural_stall_i,
    input  wire                         decode_stall_resident_i,
    input  wire                         decode_stall_load_i,
    input  wire                         decode_stall_mdu_i,

    // ALIGN boundary and frontend supply state.
    input  wire                         align_valid_i,
    input  wire                         align_accept_i,
    input  wire                         redirect_pending_i,
    input  wire                         icache_refill_busy_i,
    input  wire                         if1_tag_nonempty_i,

    // RAW matrix: candidate identity and youngest-to-oldest producer records.
    input  wire [1:0]                   candidate_class_i,
    input  wire [4:0]                   candidate_rs1_i,
    input  wire                         candidate_uses_rs1_i,
    input  wire [4:0]                   candidate_rs2_i,
    input  wire                         candidate_uses_rs2_i,
    input  wire [`EDRV32_OP_CLASS_W-1:0] resident_op_class_i,
    input  wire                         mdu_waw_i,
    input  wire                         candidate_mdu_rs1_i,
    input  wire                         candidate_mdu_rs2_i,
    input  wire                         resident_write_i,
    input  wire [4:0]                   resident_rd_i,
    input  wire                         ex_write_i,
    input  wire [4:0]                   ex_rd_i,
    input  wire [`EDRV32_OP_CLASS_W-1:0] ex_op_class_i,
    input  wire                         mem1_write_i,
    input  wire [4:0]                   mem1_rd_i,
    input  wire [`EDRV32_OP_CLASS_W-1:0] mem1_op_class_i,
    input  wire                         mem2_write_i,
    input  wire [4:0]                   mem2_rd_i,
    input  wire [`EDRV32_OP_CLASS_W-1:0] mem2_op_class_i,
    input  wire                         commit_write_i,
    input  wire [4:0]                   commit_rd_i,

    // Frontend accounting events.
    input  wire                         fe_append_hw1_i,
    input  wire                         fe_append_hw2_i,
    input  wire                         fe_consume_hw1_i,
    input  wire                         fe_consume_hw2_i,
    input  wire                         fe_pred_redirect_i,
    input  wire                         fe_discard_block_i,
    input  wire [7:0]                   branch_diag_i,
    input  wire                         fe_pred_append_slot0_i,
    input  wire                         fe_pred_append_slot1_i,
    input  wire                         fe_pred_append_cross_i,
    input  wire                         fe_pred_candidate_i,
    input  wire                         fe_discard_stale_i,
    input  wire                         fe_discard_arch_redirect_i,
    input  wire                         fe_discard_pred_redirect_i,

    // Events 41..98 as a packed one-hot-compatible bit vector.  Events that
    // are mutually exclusive by construction share no cycle; the histogram
    // and fetch events may coincide with other categories on the same cycle.
    output wire [(`EDRV32_HPM_EVENT_W-40)-1:0] events_o
);

    localparam [1:0] PRODUCER_ALU   = 2'd0;
    localparam [1:0] PRODUCER_LOAD  = 2'd1;
    localparam [1:0] PRODUCER_MDU   = 2'd2;
    localparam [1:0] PRODUCER_OTHER = 2'd3;

    reg  [6:0] attribution_w;
    reg  [(`EDRV32_HPM_EVENT_W-40)-1:0] attribution_event_w;

    // ------------------------------------------------------------------------
    // Fixed-priority empty-retire attribution, COMMIT to IF1.
    // ------------------------------------------------------------------------
    always @* begin
        attribution_w = `EDRV32_HPM_ATTR_FE_OTHER;
        if (mem2_packet_valid_i && !mem2_packet_accept_i) begin
            attribution_w = commit_busy_memory_i
                ? `EDRV32_HPM_ATTR_COMMIT_MEM
                : `EDRV32_HPM_ATTR_COMMIT_OTHER;
        end else if (mem2_packet_valid_i) begin
            // Accepted but not retired: trap/mret/fence/interrupt handling.
            attribution_w = `EDRV32_HPM_ATTR_COMMIT_TRAP;
        end else if (mem2_cache_wait_i) begin
            attribution_w = `EDRV32_HPM_ATTR_MEM2_CACHE_WAIT;
        end else if (mem1_packet_valid_i && !mem1_packet_accept_i) begin
            attribution_w = `EDRV32_HPM_ATTR_MEM1_BLOCKED;
        end else if (ex_late_mdu_stall_i) begin
            // A short MDU consumer may wait in EX instead of DECODE. Keep
            // that dependency in the MDU bucket rather than Load attribution.
            attribution_w = `EDRV32_HPM_ATTR_RAW_MDU;
        end else if (ex_late_load_stall_i) begin
            attribution_w = `EDRV32_HPM_ATTR_EX_LATE_LOAD;
        end else if (ex_valid_i && !ex_accept_i) begin
            attribution_w = `EDRV32_HPM_ATTR_MEM1_FIFO_FULL2;
        end else if (decode_valid_i && !decode_accept_i) begin
            attribution_w = `EDRV32_HPM_ATTR_EX_SIDE_EFFECTS;
        end else if (redirect_pending_i) begin
            // A registered or in-flight stream change wins over any residual
            // ALIGN stall, because that stall is a redirect artifact.
            attribution_w = `EDRV32_HPM_ATTR_FE_REDIRECT;
        end else if (align_valid_i && !align_accept_i) begin
            if (decode_stall_resident_i)
                attribution_w = `EDRV32_HPM_ATTR_RAW_RESIDENT;
            else if (decode_stall_load_i)
                attribution_w = `EDRV32_HPM_ATTR_RAW_LOAD;
            else if (decode_stall_mdu_i)
                attribution_w = `EDRV32_HPM_ATTR_RAW_MDU;
            else
                attribution_w = `EDRV32_HPM_ATTR_STRUCTURAL;
        end else if (!align_valid_i) begin
            if (icache_refill_busy_i)
                attribution_w = `EDRV32_HPM_ATTR_FE_IMISS;
            else if (if1_tag_nonempty_i)
                attribution_w = `EDRV32_HPM_ATTR_FE_WAIT_BLOCK;
            else
                attribution_w = `EDRV32_HPM_ATTR_FE_OTHER;
        end
    end

    // The attribution fires only on empty-retire cycles; the retire gap
    // register below shares the same cycle edge.
    reg [2:0] retire_gap_r;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            retire_gap_r <= 3'd0;
        end else if (retire_i) begin
            retire_gap_r <= 3'd0;
        end else if (retire_gap_r != 3'd4) begin
            retire_gap_r <= retire_gap_r + 3'd1;
        end
    end

    integer event_index;
    always @* begin
        attribution_event_w = {(`EDRV32_HPM_EVENT_W-40){1'b0}};
        if (!retire_i) begin
            attribution_event_w[attribution_w - 7'd41] = 1'b1;
        end
        if (retire_i) begin
            case (retire_gap_r)
                3'd0: attribution_event_w[`EDRV32_HPM_GAP_0 - 7'd41]  = 1'b1;
                3'd1: attribution_event_w[`EDRV32_HPM_GAP_1 - 7'd41]  = 1'b1;
                3'd2: attribution_event_w[`EDRV32_HPM_GAP_2 - 7'd41]  = 1'b1;
                3'd3: attribution_event_w[`EDRV32_HPM_GAP_3 - 7'd41]  = 1'b1;
                default: attribution_event_w[`EDRV32_HPM_GAP_4P - 7'd41] = 1'b1;
            endcase
        end
        for (event_index = `EDRV32_HPM_RAW_MATRIX_FIRST;
             event_index <= `EDRV32_HPM_RAW_MATRIX_LAST;
             event_index = event_index + 1) begin
            attribution_event_w[event_index - 7'd41] = 1'b0;
        end
        attribution_event_w[`EDRV32_HPM_FE_APPEND_HW1 - 7'd41]    = fe_append_hw1_i;
        attribution_event_w[`EDRV32_HPM_FE_APPEND_HW2 - 7'd41]    = fe_append_hw2_i;
        attribution_event_w[`EDRV32_HPM_FE_CONSUME_HW1 - 7'd41]   = fe_consume_hw1_i;
        attribution_event_w[`EDRV32_HPM_FE_CONSUME_HW2 - 7'd41]   = fe_consume_hw2_i;
        attribution_event_w[`EDRV32_HPM_FE_PRED_REDIRECT - 7'd41] = fe_pred_redirect_i;
        attribution_event_w[`EDRV32_HPM_FE_DISCARD_BLOCK - 7'd41] = fe_discard_block_i;
        attribution_event_w[`EDRV32_HPM_BR_MISS_DIR_T_ACT_T - 7'd41] = branch_diag_i[0];
        attribution_event_w[`EDRV32_HPM_BR_MISS_DIR_T_ACT_N - 7'd41] = branch_diag_i[1];
        attribution_event_w[`EDRV32_HPM_BR_MISS_DIR_N_ACT_T - 7'd41] = branch_diag_i[2];
        attribution_event_w[`EDRV32_HPM_BR_MISS_DIR_N_ACT_N - 7'd41] = branch_diag_i[3];
        attribution_event_w[`EDRV32_HPM_BR_HIT_DIR_WRONG - 7'd41] = branch_diag_i[4];
        attribution_event_w[`EDRV32_HPM_BR_HIT_DIR_CORRECT - 7'd41] = branch_diag_i[5];
        attribution_event_w[`EDRV32_HPM_JAL_BTB_MISS - 7'd41] = branch_diag_i[6];
        attribution_event_w[`EDRV32_HPM_JALR_BTB_MISS - 7'd41] = branch_diag_i[7];
        attribution_event_w[`EDRV32_HPM_PRED_APPEND_SLOT0 - 7'd41] = fe_pred_append_slot0_i;
        attribution_event_w[`EDRV32_HPM_PRED_APPEND_SLOT1 - 7'd41] = fe_pred_append_slot1_i;
        attribution_event_w[`EDRV32_HPM_PRED_APPEND_CROSS - 7'd41] = fe_pred_append_cross_i;
        attribution_event_w[`EDRV32_HPM_PRED_CANDIDATE - 7'd41] = fe_pred_candidate_i;
        attribution_event_w[`EDRV32_HPM_DISCARD_STALE - 7'd41] = fe_discard_stale_i;
        attribution_event_w[`EDRV32_HPM_DISCARD_ARCH_REDIR - 7'd41] = fe_discard_arch_redirect_i;
        attribution_event_w[`EDRV32_HPM_DISCARD_PRED_REDIR - 7'd41] = fe_discard_pred_redirect_i;
    end

    // ------------------------------------------------------------------------
    // RAW producer/consumer matrix.  The classification replays the DECODE
    // operand-resolve priority (youngest matching producer wins) but only
    // feeds counters, so it never gates functional behaviour.
    // ------------------------------------------------------------------------
    function [1:0] classify_op;
        input [`EDRV32_OP_CLASS_W-1:0] op_i;
        begin
            case (op_i)
                `EDRV32_OP_LOAD:  classify_op = PRODUCER_LOAD;
                `EDRV32_OP_MDU:   classify_op = PRODUCER_MDU;
                `EDRV32_OP_ALU,
                `EDRV32_OP_JUMP:  classify_op = PRODUCER_ALU;
                default:          classify_op = PRODUCER_OTHER;
            endcase
        end
    endfunction

    function [1:0] resolve_operand_producer;
        input [4:0] addr_i;
        input       uses_i;
        input       mdu_selected_i;
        begin
            resolve_operand_producer = PRODUCER_ALU;
            if (uses_i && (addr_i != 5'd0) && decode_valid_i &&
                resident_write_i && (resident_rd_i == addr_i)) begin
                resolve_operand_producer = classify_op(resident_op_class_i);
            end else if (mdu_selected_i) begin
                resolve_operand_producer = PRODUCER_MDU;
            end else if (uses_i && (addr_i != 5'd0) &&
                         ex_valid_i && ex_write_i && (ex_rd_i != 5'd0) &&
                         (ex_rd_i == addr_i)) begin
                resolve_operand_producer = classify_op(ex_op_class_i);
            end else if (uses_i && (addr_i != 5'd0) &&
                         mem1_packet_valid_i && mem1_write_i &&
                         (mem1_rd_i != 5'd0) && (mem1_rd_i == addr_i)) begin
                resolve_operand_producer = classify_op(mem1_op_class_i);
            end else if (uses_i && (addr_i != 5'd0) &&
                         mem2_hazard_valid_i && mem2_write_i &&
                         (mem2_rd_i != 5'd0) && (mem2_rd_i == addr_i)) begin
                resolve_operand_producer = classify_op(mem2_op_class_i);
            end else if (uses_i && (addr_i != 5'd0) &&
                         commit_write_i && (commit_rd_i != 5'd0) &&
                         (commit_rd_i == addr_i)) begin
                resolve_operand_producer = PRODUCER_OTHER;
            end
        end
    endfunction

    function [1:0] select_matrix_producer;
        input [4:0] rs1_i;
        input       uses_rs1_i;
        input [4:0] rs2_i;
        input       uses_rs2_i;
        reg [1:0]   p1;
        reg [1:0]   p2;
        begin
            p1 = resolve_operand_producer(rs1_i, uses_rs1_i, candidate_mdu_rs1_i);
            p2 = resolve_operand_producer(rs2_i, uses_rs2_i, candidate_mdu_rs2_i);
            // Resident RAW first: the DECODE-to-EX pipe content is the
            // youngest external invisible producer and always wins.
            if (decode_stall_resident_i)
                select_matrix_producer = classify_op(resident_op_class_i);
            else if (mdu_waw_i)
                select_matrix_producer = PRODUCER_MDU;
            else if (p1 == PRODUCER_LOAD || p1 == PRODUCER_MDU)
                select_matrix_producer = p1;
            else
                select_matrix_producer = p2;
        end
    endfunction

    reg [1:0] matrix_producer_w;
    reg [6:0] matrix_event_w;
    always @* begin
        matrix_producer_w = select_matrix_producer(
            candidate_rs1_i, candidate_uses_rs1_i,
            candidate_rs2_i, candidate_uses_rs2_i);
        matrix_event_w = 7'd62 +
            {5'd0, matrix_producer_w} * 7'd4 +
            {5'd0, candidate_class_i};
    end

    reg [(`EDRV32_HPM_EVENT_W-40)-1:0] events_w;
    always @* begin
        events_w = attribution_event_w;
        // The RAW matrix fires on dependency-stall cycles only; on those
        // cycles the producer/consumer pair is a single unique index.
        if (decode_dependency_stall_i)
            events_w[matrix_event_w - 7'd41] = 1'b1;
    end

    assign events_o = events_w;

endmodule
