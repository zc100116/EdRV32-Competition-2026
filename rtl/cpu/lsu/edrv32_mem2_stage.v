// ============================================================================
// File        : edrv32_mem2_stage.v
// Description : MEM2 packet ownership and registered COMMIT boundary.
// Notes       : Cacheable requests and completions belong to the LSU queues;
//               this stage transports their token in program order.
// ============================================================================
`include "edrv32_uop.vh"
`include "edrv32_pair.vh"
`include "edrv32_bus.vh"
`include "edrv32_exception.vh"
`include "edrv32_lsu.vh"

// The stage directly owns its execution logic and outgoing registered boundary.
module edrv32_mem2_stage #(
    parameter integer DUAL_ISSUE = 0
)(
    input  wire                          clk_i,
    input  wire                          rst_n_i,

    input  wire [`EDRV32_PAIR_RESULT_W-1:0] second_i,
    output wire [`EDRV32_PAIR_RESULT_W-1:0] packet_second_o,
    output wire [`EDRV32_PAIR_RESULT_W-1:0] hazard_second_o,


    // Registered classified uop from MEM1.
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
    input  wire                          mem_tcm_i,
    input  wire                          mem_mmio_i,
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

    // Resident MEM2 dependency record.
    output wire                          hazard_valid_o,
    output wire                          hazard_write_o,
    output wire                          hazard_ready_o,
    output wire [4:0]                    hazard_rd_o,
    output wire [31:0]                   hazard_value_o,
    output wire [31:0]                   hazard_pc_o,
    output wire [`EDRV32_OP_CLASS_W-1:0] hazard_op_class_o,
    output wire                          hazard_late_load_o,
    output wire                          hazard_lsu_token_valid_o,
    output wire [`EDRV32_LSU_TOKEN_W-1:0] hazard_lsu_token_o,
    output wire                          mdu_pass_o,

    // Registered completed uop presented to COMMIT.
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
    wire                          pipe_drain_w;
    wire                          pipe_valid_we_w;
    wire                          pipe_valid_d_w;


    // Stage-local execution logic is written directly in this module.


    // The local owner holds a packet until the registered output slot accepts it.
    reg valid_r;
    reg [31:0] pc_r;
    reg [31:0] instr_r;
    reg is_compressed_r;
    reg [`EDRV32_EPOCH_W-1:0] epoch_r;
    reg [4:0] rd_r;
    reg rd_write_r;
    reg [`EDRV32_OP_CLASS_W-1:0] op_class_r;
    reg [31:0] result_r;
    reg result_ready_r;
    reg [31:0] mem_addr_r;
    reg [`BUS_SZ_W-1:0] mem_size_r;
    reg mem_unsigned_r;
    reg [31:0] store_data_r;
    reg mem_cacheable_r;
    reg mem_tcm_r;
    reg mem_mmio_r;
    reg lsu_token_valid_r;
    reg [`EDRV32_LSU_TOKEN_W-1:0] lsu_token_r;
    reg mdu_token_r;
    reg [`EDRV32_CSR_OP_W-1:0] csr_op_r;
    reg [11:0] csr_addr_r;
    reg [31:0] csr_src_r;
    reg fence_r;
    reg fencei_r;
    reg mret_r;
    reg wfi_r;
    reg exception_valid_r;
    reg [`EDRV32_EXC_CAUSE_W-1:0] exception_cause_r;
    reg [31:0] exception_tval_r;
    // MEM2 owns the completed-packet slot.  u_pipe only stores the selected
    // validity and payload values.
    assign candidate_ready_w = ~kill_i &&
                               (~packet_valid_o || packet_ready_i);
    wire transfer_w = candidate_valid_w && candidate_ready_w;
    assign mdu_pass_o = transfer_w && mdu_token_r;
    assign pipe_drain_w    = packet_valid_o && packet_ready_i;
    assign pipe_valid_we_w = kill_i || transfer_w || pipe_drain_w;
    assign pipe_valid_d_w  = ~kill_i && transfer_w;
    wire owner_slot_ready_w = ~valid_r || transfer_w;
    wire capture_w = valid_i && ready_o;
    assign ready_o = ~kill_i && owner_slot_ready_w;

    reg [`EDRV32_PAIR_RESULT_W-1:0] second_r;
    assign hazard_second_o = second_r;

    assign hazard_valid_o = valid_r;
    assign hazard_write_o = rd_write_r;
    assign hazard_ready_o = !exception_valid_r && result_ready_r;
    assign hazard_rd_o    = rd_r;
    assign hazard_value_o = result_r;
    assign hazard_pc_o    = pc_r;
    assign hazard_op_class_o = op_class_r;
    assign hazard_late_load_o =
        (op_class_r == `EDRV32_OP_LOAD) && mem_cacheable_r &&
        lsu_token_valid_r;
    assign hazard_lsu_token_valid_o = lsu_token_valid_r;
    assign hazard_lsu_token_o = lsu_token_r;
    assign candidate_valid_w           = valid_r;
    assign candidate_pc_w              = pc_r;
    assign candidate_instr_w           = instr_r;
    assign candidate_is_compressed_w   = is_compressed_r;
    assign candidate_epoch_w           = epoch_r;
    assign candidate_rd_w              = rd_r;
    assign candidate_rd_write_w        = rd_write_r;
    assign candidate_op_class_w        = op_class_r;
    assign candidate_result_w          = result_r;
    assign candidate_result_ready_w    = result_ready_r;
    assign candidate_mem_addr_w        = mem_addr_r;
    assign candidate_mem_size_w        = mem_size_r;
    assign candidate_mem_unsigned_w    = mem_unsigned_r;
    assign candidate_store_data_w      = store_data_r;
    assign candidate_mem_cacheable_w   = mem_cacheable_r;
    assign candidate_mem_tcm_w         = mem_tcm_r;
    assign candidate_mem_mmio_w        = mem_mmio_r;
    assign candidate_lsu_token_valid_w = lsu_token_valid_r;
    assign candidate_lsu_token_w       = lsu_token_r;
    assign candidate_mdu_token_w       = mdu_token_r;
    assign candidate_csr_op_w          = csr_op_r;
    assign candidate_csr_addr_w        = csr_addr_r;
    assign candidate_csr_src_w         = csr_src_r;
    assign candidate_fence_w           = fence_r;
    assign candidate_fencei_w         = fencei_r;
    assign candidate_mret_w            = mret_r;
    assign candidate_wfi_w             = wfi_r;
    assign candidate_exception_valid_w = exception_valid_r;
    assign candidate_exception_cause_w = exception_cause_r;
    assign candidate_exception_tval_w  = exception_tval_r;

    // Local transaction-owner validity.  This is not a stage-to-stage valid.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            valid_r <= 1'b0;
        end else if (kill_i) begin
            valid_r <= 1'b0;
        end else if (capture_w) begin
            valid_r <= 1'b1;
        end else if (transfer_w) begin
            valid_r <= 1'b0;
        end
    end

    // Resident packet payload.
    always @(posedge clk_i) begin
        if (capture_w) begin
            second_r <= DUAL_ISSUE != 0 ? second_i : {`EDRV32_PAIR_RESULT_W{1'b0}};
            pc_r              <= pc_i;
            instr_r           <= instr_i;
            is_compressed_r   <= is_compressed_i;
            epoch_r           <= epoch_i;
            rd_r              <= rd_i;
            rd_write_r        <= rd_write_i;
            op_class_r        <= op_class_i;
            result_r          <= result_i;
            result_ready_r    <= result_ready_i;
            mem_addr_r        <= mem_addr_i;
            mem_size_r        <= mem_size_i;
            mem_unsigned_r    <= mem_unsigned_i;
            store_data_r      <= store_data_i;
            mem_cacheable_r   <= mem_cacheable_i;
            mem_tcm_r         <= mem_tcm_i;
            mem_mmio_r        <= mem_mmio_i;
            lsu_token_valid_r <= lsu_token_valid_i;
            lsu_token_r       <= lsu_token_i;
            mdu_token_r       <= mdu_token_i;
            csr_op_r          <= csr_op_i;
            csr_addr_r        <= csr_addr_i;
            csr_src_r         <= csr_src_i;
            fence_r           <= fence_i;
            fencei_r         <= fencei_i;
            mret_r            <= mret_i;
            wfi_r             <= wfi_i;
            exception_valid_r <= exception_valid_i;
            exception_cause_r <= exception_cause_i;
            exception_tval_r  <= exception_tval_i;
        end
    end


    edrv32_pipe_mem2_to_commit #(.SECOND_ENABLE(DUAL_ISSUE)) u_pipe (
        .second_i(second_r),
        .second_o(packet_second_o),
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .valid_we_i(pipe_valid_we_w),
        .valid_d_i(pipe_valid_d_w),
        .payload_we_i(transfer_w),
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
        .valid_o(packet_valid_o),
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
