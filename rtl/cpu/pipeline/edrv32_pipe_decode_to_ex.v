// ============================================================================
// File        : edrv32_pipe_decode_to_ex.v
// Description : Register bank for the DECODE-to-EX boundary.
// Notes       : Hazard, ready/valid, replacement, and squash policy is owned
//               by DECODE.  Every output is a register in this module.
// ============================================================================
`include "edrv32_uop.vh"
`include "edrv32_pair.vh"
`include "edrv32_bus.vh"
`include "edrv32_exception.vh"
`include "edrv32_lsu.vh"

module edrv32_pipe_decode_to_ex #(
    parameter integer SECOND_ENABLE = 0
)(
    input  wire                           clk_i,
    input  wire                           rst_n_i,

    input  wire [`EDRV32_PAIR_DECODE_W-1:0] second_i,
    output wire [`EDRV32_PAIR_DECODE_W-1:0] second_o,


    input wire resident_second_rs1_i,
    input wire resident_second_rs2_i,
    output wire resident_second_rs1_o,
    output wire resident_second_rs2_o,

    // Register controls computed by edrv32_decode_stage.
    input  wire                           valid_we_i,
    input  wire                           valid_d_i,
    input  wire                           payload_we_i,

    // Decoded uop at the register inputs.
    input  wire [31:0]                    pc_i,
    input  wire [31:0]                    instr_i,
    input  wire                           is_compressed_i,
    input  wire [`EDRV32_EPOCH_W-1:0]     epoch_i,
    input  wire                           predicted_taken_i,
    input  wire [31:0]                    predicted_target_i,
    input  wire [1:0]                     predictor_meta_i,
    input  wire [4:0]                     rd_i,
    input  wire                           rd_write_i,
    input  wire [`EDRV32_OP_CLASS_W-1:0]  op_class_i,
    input  wire [`EDRV32_ALU_OP_W-1:0]    alu_op_i,
    input  wire [`EDRV32_BRANCH_OP_W-1:0] branch_op_i,
    input  wire [`BUS_SZ_W-1:0]           mem_size_i,
    input  wire                           mem_unsigned_i,
    input  wire [`EDRV32_MDU_OP_W-1:0]    mdu_op_i,
    input  wire [`EDRV32_CSR_OP_W-1:0]    csr_op_i,
    input  wire [11:0]                    csr_addr_i,
    input  wire [31:0]                    csr_src_i,
    input  wire [31:0]                    lhs_i,
    input  wire [31:0]                    rhs_i,
    input  wire [31:0]                    rs2_value_i,
    input  wire                           resident_bypass_rs1_i,
    input  wire                           resident_bypass_rs2_i,
    input  wire [31:0]                    resident_bypass_pc_i,
    input  wire                           late_mdu_rs1_i,
    input  wire                           late_mdu_rs2_i,
    input  wire                           late_load_rs1_i,
    input  wire                           late_load_rs2_i,
    input  wire [31:0]                    late_load_rs1_pc_i,
    input  wire [31:0]                    late_load_rs2_pc_i,
    input  wire                           late_load_rs1_token_valid_i,
    input  wire [`EDRV32_LSU_TOKEN_W-1:0] late_load_rs1_token_i,
    input  wire                           late_load_rs2_token_valid_i,
    input  wire [`EDRV32_LSU_TOKEN_W-1:0] late_load_rs2_token_i,
    input  wire [31:0]                    imm_i,
    input  wire                           fence_i,
    input  wire                           fencei_i,
    input  wire                           mret_i,
    input  wire                           wfi_i,
    input  wire                           exception_valid_i,
    input  wire [`EDRV32_EXC_CAUSE_W-1:0] exception_cause_i,
    input  wire [31:0]                    exception_tval_i,

    // Registered boundary state.
    output wire                           valid_o,
    output wire [31:0]                    pc_o,
    output wire [31:0]                    instr_o,
    output wire                           is_compressed_o,
    output wire [`EDRV32_EPOCH_W-1:0]     epoch_o,
    output wire                           predicted_taken_o,
    output wire [31:0]                    predicted_target_o,
    output wire [1:0]                     predictor_meta_o,
    output wire [4:0]                     rd_o,
    output wire                           rd_write_o,
    output wire [`EDRV32_OP_CLASS_W-1:0]  op_class_o,
    output wire [`EDRV32_ALU_OP_W-1:0]    alu_op_o,
    output wire [`EDRV32_BRANCH_OP_W-1:0] branch_op_o,
    output wire [`BUS_SZ_W-1:0]           mem_size_o,
    output wire                           mem_unsigned_o,
    output wire [`EDRV32_MDU_OP_W-1:0]    mdu_op_o,
    output wire [`EDRV32_CSR_OP_W-1:0]    csr_op_o,
    output wire [11:0]                    csr_addr_o,
    output wire [31:0]                    csr_src_o,
    output wire [31:0]                    lhs_o,
    output wire [31:0]                    rhs_o,
    output wire [31:0]                    rs2_value_o,
    output wire                           resident_bypass_rs1_o,
    output wire                           resident_bypass_rs2_o,
    output wire [31:0]                    resident_bypass_pc_o,
    output wire                           late_mdu_rs1_o,
    output wire                           late_mdu_rs2_o,
    output wire                           late_load_rs1_o,
    output wire                           late_load_rs2_o,
    output wire [31:0]                    late_load_rs1_pc_o,
    output wire [31:0]                    late_load_rs2_pc_o,
    output wire                           late_load_rs1_token_valid_o,
    output wire [`EDRV32_LSU_TOKEN_W-1:0] late_load_rs1_token_o,
    output wire                           late_load_rs2_token_valid_o,
    output wire [`EDRV32_LSU_TOKEN_W-1:0] late_load_rs2_token_o,
    output wire [31:0]                    imm_o,
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
    reg                            predicted_taken_r;
    reg [31:0]                     predicted_target_r;
    reg [1:0]                      predictor_meta_r;
    reg [4:0]                      rd_r;
    reg                            rd_write_r;
    reg [`EDRV32_OP_CLASS_W-1:0]   op_class_r;
    reg [`EDRV32_ALU_OP_W-1:0]     alu_op_r;
    reg [`EDRV32_BRANCH_OP_W-1:0]  branch_op_r;
    reg [`BUS_SZ_W-1:0]            mem_size_r;
    reg                            mem_unsigned_r;
    reg [`EDRV32_MDU_OP_W-1:0]     mdu_op_r;
    reg [`EDRV32_CSR_OP_W-1:0]     csr_op_r;
    reg [11:0]                     csr_addr_r;
    reg [31:0]                     csr_src_r;
    reg [31:0]                     lhs_r;
    reg [31:0]                     rhs_r;
    reg [31:0]                     rs2_value_r;
    reg                            resident_bypass_rs1_r;
    reg                            resident_bypass_rs2_r;
    reg [31:0]                     resident_bypass_pc_r;
    reg                            late_mdu_rs1_r;
    reg                            late_mdu_rs2_r;
    reg                            late_load_rs1_r;
    reg                            late_load_rs2_r;
    reg [31:0]                     late_load_rs1_pc_r;
    reg [31:0]                     late_load_rs2_pc_r;
    reg                            late_load_rs1_token_valid_r;
    reg [`EDRV32_LSU_TOKEN_W-1:0] late_load_rs1_token_r;
    reg                            late_load_rs2_token_valid_r;
    reg [`EDRV32_LSU_TOKEN_W-1:0] late_load_rs2_token_r;
    reg [31:0]                     imm_r;
    reg                            fence_r;
    reg                            fencei_r;
    reg                            mret_r;
    reg                            wfi_r;
    reg                            exception_valid_r;
    reg [`EDRV32_EXC_CAUSE_W-1:0]  exception_cause_r;
    reg [31:0]                     exception_tval_r;

    reg resident_second_rs1_r;
    reg resident_second_rs2_r;
    assign resident_second_rs1_o = resident_second_rs1_r;
    assign resident_second_rs2_o = resident_second_rs2_r;
    reg [`EDRV32_PAIR_DECODE_W-1:0] second_r;
    assign second_o = second_r;

    assign valid_o             = valid_r;
    assign pc_o                = pc_r;
    assign instr_o             = instr_r;
    assign is_compressed_o     = is_compressed_r;
    assign epoch_o             = epoch_r;
    assign predicted_taken_o   = predicted_taken_r;
    assign predicted_target_o  = predicted_target_r;
    assign predictor_meta_o    = predictor_meta_r;
    assign rd_o                = rd_r;
    assign rd_write_o          = rd_write_r;
    assign op_class_o          = op_class_r;
    assign alu_op_o            = alu_op_r;
    assign branch_op_o         = branch_op_r;
    assign mem_size_o          = mem_size_r;
    assign mem_unsigned_o      = mem_unsigned_r;
    assign mdu_op_o            = mdu_op_r;
    assign csr_op_o            = csr_op_r;
    assign csr_addr_o          = csr_addr_r;
    assign csr_src_o           = csr_src_r;
    assign lhs_o               = lhs_r;
    assign rhs_o               = rhs_r;
    assign rs2_value_o         = rs2_value_r;
    assign resident_bypass_rs1_o = resident_bypass_rs1_r;
    assign resident_bypass_rs2_o = resident_bypass_rs2_r;
    assign resident_bypass_pc_o  = resident_bypass_pc_r;
    assign late_mdu_rs1_o       = late_mdu_rs1_r;
    assign late_mdu_rs2_o       = late_mdu_rs2_r;
    assign late_load_rs1_o     = late_load_rs1_r;
    assign late_load_rs2_o     = late_load_rs2_r;
    assign late_load_rs1_pc_o  = late_load_rs1_pc_r;
    assign late_load_rs2_pc_o  = late_load_rs2_pc_r;
    assign late_load_rs1_token_valid_o = late_load_rs1_token_valid_r;
    assign late_load_rs1_token_o = late_load_rs1_token_r;
    assign late_load_rs2_token_valid_o = late_load_rs2_token_valid_r;
    assign late_load_rs2_token_o = late_load_rs2_token_r;
    assign imm_o               = imm_r;
    assign fence_o             = fence_r;
    assign fencei_o            = fencei_r;
    assign mret_o              = mret_r;
    assign wfi_o               = wfi_r;
    assign exception_valid_o   = exception_valid_r;
    assign exception_cause_o   = exception_cause_r;
    assign exception_tval_o    = exception_tval_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            valid_r <= 1'b0;
        else if (valid_we_i)
            valid_r <= valid_d_i;
    end

    always @(posedge clk_i) begin
        if (payload_we_i) begin
            resident_second_rs1_r <= (SECOND_ENABLE != 0) && resident_second_rs1_i;
            resident_second_rs2_r <= (SECOND_ENABLE != 0) && resident_second_rs2_i;
            second_r <= SECOND_ENABLE != 0 ? second_i : {`EDRV32_PAIR_DECODE_W{1'b0}};
            pc_r               <= pc_i;
            instr_r            <= instr_i;
            is_compressed_r    <= is_compressed_i;
            epoch_r            <= epoch_i;
            predicted_taken_r  <= predicted_taken_i;
            predicted_target_r <= predicted_target_i;
            predictor_meta_r   <= predictor_meta_i;
            rd_r               <= rd_i;
            rd_write_r         <= rd_write_i;
            op_class_r         <= op_class_i;
            alu_op_r           <= alu_op_i;
            branch_op_r        <= branch_op_i;
            mem_size_r         <= mem_size_i;
            mem_unsigned_r     <= mem_unsigned_i;
            mdu_op_r           <= mdu_op_i;
            csr_op_r           <= csr_op_i;
            csr_addr_r         <= csr_addr_i;
            csr_src_r          <= csr_src_i;
            lhs_r              <= lhs_i;
            rhs_r              <= rhs_i;
            rs2_value_r        <= rs2_value_i;
            resident_bypass_rs1_r <= resident_bypass_rs1_i;
            resident_bypass_rs2_r <= resident_bypass_rs2_i;
            resident_bypass_pc_r  <= resident_bypass_pc_i;
            late_mdu_rs1_r     <= late_mdu_rs1_i;
            late_mdu_rs2_r     <= late_mdu_rs2_i;
            late_load_rs1_r    <= late_load_rs1_i;
            late_load_rs2_r    <= late_load_rs2_i;
            late_load_rs1_pc_r <= late_load_rs1_pc_i;
            late_load_rs2_pc_r <= late_load_rs2_pc_i;
            late_load_rs1_token_valid_r <= late_load_rs1_token_valid_i;
            late_load_rs1_token_r <= late_load_rs1_token_i;
            late_load_rs2_token_valid_r <= late_load_rs2_token_valid_i;
            late_load_rs2_token_r <= late_load_rs2_token_i;
            imm_r              <= imm_i;
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
