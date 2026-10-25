// ============================================================================
// File        : edrv32_pipe_mem1_to_mem2.v
// Description : Two-entry register bank for the MEM1-to-MEM2 boundary.
// Notes       : MEM1 owns occupancy, ready/valid, flush, and queue movement.
//               The externally visible head fields are direct registers.
// ============================================================================
`include "edrv32_uop.vh"
`include "edrv32_pair.vh"
`include "edrv32_bus.vh"
`include "edrv32_exception.vh"
`include "edrv32_lsu.vh"

module edrv32_pipe_mem1_to_mem2 #(
    parameter integer SECOND_ENABLE = 0
)(
    input  wire                           clk_i,

    input  wire [`EDRV32_PAIR_RESULT_W-1:0] second_i,
    output wire [`EDRV32_PAIR_RESULT_W-1:0] second_o,


    input  wire                           head_we_i,
    input  wire                           head_from_tail_i,
    input  wire                           tail_we_i,

    input  wire [31:0]                    pc_i,
    input  wire [31:0]                    instr_i,
    input  wire                           is_compressed_i,
    input  wire [`EDRV32_EPOCH_W-1:0]     epoch_i,
    input  wire [4:0]                     rd_i,
    input  wire                           rd_write_i,
    input  wire [`EDRV32_OP_CLASS_W-1:0]  op_class_i,
    input  wire [31:0]                    result_i,
    input  wire                           result_ready_i,
    input  wire [31:0]                    mem_addr_i,
    input  wire [`BUS_SZ_W-1:0]           mem_size_i,
    input  wire                           mem_unsigned_i,
    input  wire [31:0]                    store_data_i,
    input  wire                           mem_cacheable_i,
    input  wire                           mem_tcm_i,
    input  wire                           mem_mmio_i,
    input  wire                           lsu_token_valid_i,
    input  wire [`EDRV32_LSU_TOKEN_W-1:0] lsu_token_i,
    input  wire                           mdu_token_i,
    input  wire [`EDRV32_CSR_OP_W-1:0]    csr_op_i,
    input  wire [11:0]                    csr_addr_i,
    input  wire [31:0]                    csr_src_i,
    input  wire                           fence_i,
    input  wire                           fencei_i,
    input  wire                           mret_i,
    input  wire                           wfi_i,
    input  wire                           exception_valid_i,
    input  wire [`EDRV32_EXC_CAUSE_W-1:0] exception_cause_i,
    input  wire [31:0]                    exception_tval_i,

    output wire [31:0]                    pc_o,
    output wire [31:0]                    instr_o,
    output wire                           is_compressed_o,
    output wire [`EDRV32_EPOCH_W-1:0]     epoch_o,
    output wire [4:0]                     rd_o,
    output wire                           rd_write_o,
    output wire [`EDRV32_OP_CLASS_W-1:0]  op_class_o,
    output wire [31:0]                    result_o,
    output wire                           result_ready_o,
    output wire [31:0]                    mem_addr_o,
    output wire [`BUS_SZ_W-1:0]           mem_size_o,
    output wire                           mem_unsigned_o,
    output wire [31:0]                    store_data_o,
    output wire                           mem_cacheable_o,
    output wire                           mem_tcm_o,
    output wire                           mem_mmio_o,
    output wire                           lsu_token_valid_o,
    output wire [`EDRV32_LSU_TOKEN_W-1:0] lsu_token_o,
    output wire                           mdu_token_o,
    output wire [`EDRV32_CSR_OP_W-1:0]    csr_op_o,
    output wire [11:0]                    csr_addr_o,
    output wire [31:0]                    csr_src_o,
    output wire                           fence_o,
    output wire                           fencei_o,
    output wire                           mret_o,
    output wire                           wfi_o,
    output wire                           exception_valid_o,
    output wire [`EDRV32_EXC_CAUSE_W-1:0] exception_cause_o,
    output wire [31:0]                    exception_tval_o
);

    reg [31:0]                    head_pc_r;
    reg [31:0]                    head_instr_r;
    reg                           head_is_compressed_r;
    reg [`EDRV32_EPOCH_W-1:0]     head_epoch_r;
    reg [4:0]                     head_rd_r;
    reg                           head_rd_write_r;
    reg [`EDRV32_OP_CLASS_W-1:0]  head_op_class_r;
    reg [31:0]                    head_result_r;
    reg                           head_result_ready_r;
    reg [31:0]                    head_mem_addr_r;
    reg [`BUS_SZ_W-1:0]           head_mem_size_r;
    reg                           head_mem_unsigned_r;
    reg [31:0]                    head_store_data_r;
    reg                           head_mem_cacheable_r;
    reg                           head_mem_tcm_r;
    reg                           head_mem_mmio_r;
    reg                           head_lsu_token_valid_r;
    reg [`EDRV32_LSU_TOKEN_W-1:0] head_lsu_token_r;
    reg                           head_mdu_token_r;
    reg [`EDRV32_CSR_OP_W-1:0]    head_csr_op_r;
    reg [11:0]                    head_csr_addr_r;
    reg [31:0]                    head_csr_src_r;
    reg                           head_fence_r;
    reg                           head_fencei_r;
    reg                           head_mret_r;
    reg                           head_wfi_r;
    reg                           head_exception_valid_r;
    reg [`EDRV32_EXC_CAUSE_W-1:0] head_exception_cause_r;
    reg [31:0]                    head_exception_tval_r;

    reg [31:0]                    tail_pc_r;
    reg [31:0]                    tail_instr_r;
    reg                           tail_is_compressed_r;
    reg [`EDRV32_EPOCH_W-1:0]     tail_epoch_r;
    reg [4:0]                     tail_rd_r;
    reg                           tail_rd_write_r;
    reg [`EDRV32_OP_CLASS_W-1:0]  tail_op_class_r;
    reg [31:0]                    tail_result_r;
    reg                           tail_result_ready_r;
    reg [31:0]                    tail_mem_addr_r;
    reg [`BUS_SZ_W-1:0]           tail_mem_size_r;
    reg                           tail_mem_unsigned_r;
    reg [31:0]                    tail_store_data_r;
    reg                           tail_mem_cacheable_r;
    reg                           tail_mem_tcm_r;
    reg                           tail_mem_mmio_r;
    reg                           tail_lsu_token_valid_r;
    reg [`EDRV32_LSU_TOKEN_W-1:0] tail_lsu_token_r;
    reg                           tail_mdu_token_r;
    reg [`EDRV32_CSR_OP_W-1:0]    tail_csr_op_r;
    reg [11:0]                    tail_csr_addr_r;
    reg [31:0]                    tail_csr_src_r;
    reg                           tail_fence_r;
    reg                           tail_fencei_r;
    reg                           tail_mret_r;
    reg                           tail_wfi_r;
    reg                           tail_exception_valid_r;
    reg [`EDRV32_EXC_CAUSE_W-1:0] tail_exception_cause_r;
    reg [31:0]                    tail_exception_tval_r;

    reg [`EDRV32_PAIR_RESULT_W-1:0] head_second_r;
    reg [`EDRV32_PAIR_RESULT_W-1:0] tail_second_r;
    assign second_o = head_second_r;

    assign pc_o               = head_pc_r;
    assign instr_o            = head_instr_r;
    assign is_compressed_o    = head_is_compressed_r;
    assign epoch_o            = head_epoch_r;
    assign rd_o               = head_rd_r;
    assign rd_write_o         = head_rd_write_r;
    assign op_class_o         = head_op_class_r;
    assign result_o           = head_result_r;
    assign result_ready_o     = head_result_ready_r;
    assign mem_addr_o         = head_mem_addr_r;
    assign mem_size_o         = head_mem_size_r;
    assign mem_unsigned_o     = head_mem_unsigned_r;
    assign store_data_o       = head_store_data_r;
    assign mem_cacheable_o    = head_mem_cacheable_r;
    assign mem_tcm_o          = head_mem_tcm_r;
    assign mem_mmio_o         = head_mem_mmio_r;
    assign lsu_token_valid_o  = head_lsu_token_valid_r;
    assign lsu_token_o        = head_lsu_token_r;
    assign mdu_token_o        = head_mdu_token_r;
    assign csr_op_o           = head_csr_op_r;
    assign csr_addr_o         = head_csr_addr_r;
    assign csr_src_o          = head_csr_src_r;
    assign fence_o            = head_fence_r;
    assign fencei_o           = head_fencei_r;
    assign mret_o             = head_mret_r;
    assign wfi_o              = head_wfi_r;
    assign exception_valid_o  = head_exception_valid_r;
    assign exception_cause_o  = head_exception_cause_r;
    assign exception_tval_o   = head_exception_tval_r;

    always @(posedge clk_i) begin
        if (head_we_i) begin
            if (head_from_tail_i) begin
                head_second_r <= tail_second_r;
                head_pc_r               <= tail_pc_r;
                head_instr_r            <= tail_instr_r;
                head_is_compressed_r    <= tail_is_compressed_r;
                head_epoch_r            <= tail_epoch_r;
                head_rd_r               <= tail_rd_r;
                head_rd_write_r         <= tail_rd_write_r;
                head_op_class_r         <= tail_op_class_r;
                head_result_r           <= tail_result_r;
                head_result_ready_r     <= tail_result_ready_r;
                head_mem_addr_r         <= tail_mem_addr_r;
                head_mem_size_r         <= tail_mem_size_r;
                head_mem_unsigned_r     <= tail_mem_unsigned_r;
                head_store_data_r       <= tail_store_data_r;
                head_mem_cacheable_r    <= tail_mem_cacheable_r;
                head_mem_tcm_r          <= tail_mem_tcm_r;
                head_mem_mmio_r         <= tail_mem_mmio_r;
                head_lsu_token_valid_r  <= tail_lsu_token_valid_r;
                head_lsu_token_r        <= tail_lsu_token_r;
                head_mdu_token_r        <= tail_mdu_token_r;
                head_csr_op_r           <= tail_csr_op_r;
                head_csr_addr_r         <= tail_csr_addr_r;
                head_csr_src_r          <= tail_csr_src_r;
                head_fence_r            <= tail_fence_r;
                head_fencei_r           <= tail_fencei_r;
                head_mret_r             <= tail_mret_r;
                head_wfi_r              <= tail_wfi_r;
                head_exception_valid_r  <= tail_exception_valid_r;
                head_exception_cause_r  <= tail_exception_cause_r;
                head_exception_tval_r   <= tail_exception_tval_r;
            end else begin
                head_second_r <= SECOND_ENABLE != 0 ? second_i : {`EDRV32_PAIR_RESULT_W{1'b0}};
                head_pc_r               <= pc_i;
                head_instr_r            <= instr_i;
                head_is_compressed_r    <= is_compressed_i;
                head_epoch_r            <= epoch_i;
                head_rd_r               <= rd_i;
                head_rd_write_r         <= rd_write_i;
                head_op_class_r         <= op_class_i;
                head_result_r           <= result_i;
                head_result_ready_r     <= result_ready_i;
                head_mem_addr_r         <= mem_addr_i;
                head_mem_size_r         <= mem_size_i;
                head_mem_unsigned_r     <= mem_unsigned_i;
                head_store_data_r       <= store_data_i;
                head_mem_cacheable_r    <= mem_cacheable_i;
                head_mem_tcm_r          <= mem_tcm_i;
                head_mem_mmio_r         <= mem_mmio_i;
                head_lsu_token_valid_r  <= lsu_token_valid_i;
                head_lsu_token_r        <= lsu_token_i;
                head_mdu_token_r        <= mdu_token_i;
                head_csr_op_r           <= csr_op_i;
                head_csr_addr_r         <= csr_addr_i;
                head_csr_src_r          <= csr_src_i;
                head_fence_r            <= fence_i;
                head_fencei_r           <= fencei_i;
                head_mret_r             <= mret_i;
                head_wfi_r              <= wfi_i;
                head_exception_valid_r  <= exception_valid_i;
                head_exception_cause_r  <= exception_cause_i;
                head_exception_tval_r   <= exception_tval_i;
            end
        end
    end

    always @(posedge clk_i) begin
        if (tail_we_i) begin
            tail_second_r <= SECOND_ENABLE != 0 ? second_i : {`EDRV32_PAIR_RESULT_W{1'b0}};
            tail_pc_r               <= pc_i;
            tail_instr_r            <= instr_i;
            tail_is_compressed_r    <= is_compressed_i;
            tail_epoch_r            <= epoch_i;
            tail_rd_r               <= rd_i;
            tail_rd_write_r         <= rd_write_i;
            tail_op_class_r         <= op_class_i;
            tail_result_r           <= result_i;
            tail_result_ready_r     <= result_ready_i;
            tail_mem_addr_r         <= mem_addr_i;
            tail_mem_size_r         <= mem_size_i;
            tail_mem_unsigned_r     <= mem_unsigned_i;
            tail_store_data_r       <= store_data_i;
            tail_mem_cacheable_r    <= mem_cacheable_i;
            tail_mem_tcm_r          <= mem_tcm_i;
            tail_mem_mmio_r         <= mem_mmio_i;
            tail_lsu_token_valid_r  <= lsu_token_valid_i;
            tail_lsu_token_r        <= lsu_token_i;
            tail_mdu_token_r        <= mdu_token_i;
            tail_csr_op_r           <= csr_op_i;
            tail_csr_addr_r         <= csr_addr_i;
            tail_csr_src_r          <= csr_src_i;
            tail_fence_r            <= fence_i;
            tail_fencei_r           <= fencei_i;
            tail_mret_r             <= mret_i;
            tail_wfi_r              <= wfi_i;
            tail_exception_valid_r  <= exception_valid_i;
            tail_exception_cause_r  <= exception_cause_i;
            tail_exception_tval_r   <= exception_tval_i;
        end
    end

endmodule
