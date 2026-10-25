// ============================================================================
// File        : edrv32_pipe_ex_to_mem1.v
// Description : Register bank for the EX-to-MEM1 boundary.
// Notes       : EX owns all transaction and elastic-slot decisions.  This
//               module only stores the selected validity and payload values.
// ============================================================================
`include "edrv32_uop.vh"
`include "edrv32_pair.vh"
`include "edrv32_bus.vh"
`include "edrv32_exception.vh"

module edrv32_pipe_ex_to_mem1 #(
    parameter integer SECOND_ENABLE = 0
)(
    input  wire                           clk_i,
    input  wire                           rst_n_i,

    input  wire [`EDRV32_PAIR_RESULT_W-1:0] second_i,
    output wire [`EDRV32_PAIR_RESULT_W-1:0] second_o,


    input  wire                           valid_we_i,
    input  wire                           valid_d_i,
    input  wire                           payload_we_i,

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

    output wire                           valid_o,
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

    reg                            valid_r;
    reg [31:0]                     pc_r;
    reg [31:0]                     instr_r;
    reg                            is_compressed_r;
    reg [`EDRV32_EPOCH_W-1:0]      epoch_r;
    reg [4:0]                      rd_r;
    reg                            rd_write_r;
    reg [`EDRV32_OP_CLASS_W-1:0]   op_class_r;
    reg [31:0]                     result_r;
    reg                            result_ready_r;
    reg [31:0]                     mem_addr_r;
    reg [`BUS_SZ_W-1:0]            mem_size_r;
    reg                            mem_unsigned_r;
    reg [31:0]                     store_data_r;
    reg                            mdu_token_r;
    reg [`EDRV32_CSR_OP_W-1:0]     csr_op_r;
    reg [11:0]                     csr_addr_r;
    reg [31:0]                     csr_src_r;
    reg                            fence_r;
    reg                            fencei_r;
    reg                            mret_r;
    reg                            wfi_r;
    reg                            exception_valid_r;
    reg [`EDRV32_EXC_CAUSE_W-1:0]  exception_cause_r;
    reg [31:0]                     exception_tval_r;

    reg [`EDRV32_PAIR_RESULT_W-1:0] second_r;
    assign second_o = second_r;

    assign valid_o            = valid_r;
    assign pc_o               = pc_r;
    assign instr_o            = instr_r;
    assign is_compressed_o    = is_compressed_r;
    assign epoch_o            = epoch_r;
    assign rd_o               = rd_r;
    assign rd_write_o         = rd_write_r;
    assign op_class_o         = op_class_r;
    assign result_o           = result_r;
    assign result_ready_o     = result_ready_r;
    assign mem_addr_o         = mem_addr_r;
    assign mem_size_o         = mem_size_r;
    assign mem_unsigned_o     = mem_unsigned_r;
    assign store_data_o       = store_data_r;
    assign mdu_token_o        = mdu_token_r;
    assign csr_op_o           = csr_op_r;
    assign csr_addr_o         = csr_addr_r;
    assign csr_src_o          = csr_src_r;
    assign fence_o            = fence_r;
    assign fencei_o           = fencei_r;
    assign mret_o             = mret_r;
    assign wfi_o              = wfi_r;
    assign exception_valid_o  = exception_valid_r;
    assign exception_cause_o  = exception_cause_r;
    assign exception_tval_o   = exception_tval_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            valid_r <= 1'b0;
        else if (valid_we_i)
            valid_r <= valid_d_i;
    end

    always @(posedge clk_i) begin
        if (payload_we_i) begin
            second_r <= SECOND_ENABLE != 0 ? second_i : {`EDRV32_PAIR_RESULT_W{1'b0}};
            pc_r               <= pc_i;
            instr_r            <= instr_i;
            is_compressed_r    <= is_compressed_i;
            epoch_r            <= epoch_i;
            rd_r               <= rd_i;
            rd_write_r         <= rd_write_i;
            op_class_r         <= op_class_i;
            result_r           <= result_i;
            result_ready_r     <= result_ready_i;
            mem_addr_r         <= mem_addr_i;
            mem_size_r         <= mem_size_i;
            mem_unsigned_r     <= mem_unsigned_i;
            store_data_r       <= store_data_i;
            mdu_token_r        <= mdu_token_i;
            csr_op_r           <= csr_op_i;
            csr_addr_r         <= csr_addr_i;
            csr_src_r          <= csr_src_i;
            fence_r            <= fence_i;
            fencei_r           <= fencei_i;
            mret_r             <= mret_i;
            wfi_r              <= wfi_i;
            exception_valid_r  <= exception_valid_i;
            exception_cause_r  <= exception_cause_i;
            exception_tval_r   <= exception_tval_i;
        end
    end

endmodule
