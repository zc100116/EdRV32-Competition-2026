// ============================================================================
// File        : edrv32_uop.vh
// Description : Scalar micro-operation encodings shared by DECODE through COMMIT.
// Notes       : These are exact-width scalar fields, not future issue lanes.
// ============================================================================
`ifndef EDRV32_UOP_VH
`define EDRV32_UOP_VH

`define EDRV32_EPOCH_W            2

// Operation class.
`define EDRV32_OP_CLASS_W         4
`define EDRV32_OP_NONE         4'd0
`define EDRV32_OP_ALU          4'd1
`define EDRV32_OP_BRANCH       4'd2
`define EDRV32_OP_JUMP         4'd3
`define EDRV32_OP_LOAD         4'd4
`define EDRV32_OP_STORE        4'd5
`define EDRV32_OP_CSR          4'd6
`define EDRV32_OP_SYSTEM       4'd7
`define EDRV32_OP_MDU          4'd8
`define EDRV32_OP_FENCE        4'd9

// ALU operation.
`define EDRV32_ALU_OP_W           4
`define EDRV32_ALU_ADD          4'd0
`define EDRV32_ALU_SUB          4'd1
`define EDRV32_ALU_SLL          4'd2
`define EDRV32_ALU_SLT          4'd3
`define EDRV32_ALU_SLTU         4'd4
`define EDRV32_ALU_XOR          4'd5
`define EDRV32_ALU_SRL          4'd6
`define EDRV32_ALU_SRA          4'd7
`define EDRV32_ALU_OR           4'd8
`define EDRV32_ALU_AND          4'd9
`define EDRV32_ALU_COPY_B       4'd10

// Operand-A selection. Operand B is rs2 when op_b_imm is false.
`define EDRV32_OP_A_SEL_W         2
`define EDRV32_OP_A_RS1         2'd0
`define EDRV32_OP_A_PC          2'd1
`define EDRV32_OP_A_ZERO        2'd2

// Immediate format.
`define EDRV32_IMM_SEL_W          3
`define EDRV32_IMM_NONE         3'd0
`define EDRV32_IMM_I            3'd1
`define EDRV32_IMM_S            3'd2
`define EDRV32_IMM_B            3'd3
`define EDRV32_IMM_U            3'd4
`define EDRV32_IMM_J            3'd5
`define EDRV32_IMM_Z            3'd6

// Branch comparison.
`define EDRV32_BRANCH_OP_W        3
`define EDRV32_BRANCH_NONE      3'd0
`define EDRV32_BRANCH_EQ        3'd1
`define EDRV32_BRANCH_NE        3'd2
`define EDRV32_BRANCH_LT        3'd3
`define EDRV32_BRANCH_GE        3'd4
`define EDRV32_BRANCH_LTU       3'd5
`define EDRV32_BRANCH_GEU       3'd6

// Integer multiply/divide operation, matching M-extension funct3 order.
`define EDRV32_MDU_OP_W           3
`define EDRV32_MDU_MUL          3'd0
`define EDRV32_MDU_MULH         3'd1
`define EDRV32_MDU_MULHSU       3'd2
`define EDRV32_MDU_MULHU        3'd3
`define EDRV32_MDU_DIV          3'd4
`define EDRV32_MDU_DIVU         3'd5
`define EDRV32_MDU_REM          3'd6
`define EDRV32_MDU_REMU         3'd7

// CSR operation.
`define EDRV32_CSR_OP_W           2
`define EDRV32_CSR_NONE         2'd0
`define EDRV32_CSR_WRITE        2'd1
`define EDRV32_CSR_SET          2'd2
`define EDRV32_CSR_CLEAR        2'd3

// Registered redirect reason.
`define EDRV32_REDIRECT_REASON_W  3
`define EDRV32_REDIR_NONE       3'd0
`define EDRV32_REDIR_EX_BRANCH  3'd1
`define EDRV32_REDIR_EXCEPTION  3'd2
`define EDRV32_REDIR_INTERRUPT  3'd3
`define EDRV32_REDIR_MRET       3'd4
`define EDRV32_REDIR_FENCEI     3'd5

`endif // EDRV32_UOP_VH
