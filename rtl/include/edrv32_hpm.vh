// ============================================================================
// File        : edrv32_hpm.vh
// Description : EdRV32 platform-defined HPM event identifiers.
// Notes       : Event zero follows the RISC-V privileged specification and
//               means "no event". IDs 1..40 are the original platform ABI and
//               remain bit-identical. IDs 41..81 are the r47 mutual-exclusion
//               attribution bank: on every cycle without a retire, exactly
//               one of events 41..56 fires (fixed priority, COMMIT to IF1),
//               so their sum equals the empty-retire count. Events 57..61 are
//               the retire-gap histogram, 62..77 the RAW producer/consumer
//               matrix, and 78..81 the frontend useful/discarded fetch set.
//               IDs 82..98 include frontend and branch-prediction diagnostics.
//               The selector field is 7 bits; writes above 98 coerce to zero
//               (WARL), so existing 6-bit firmware selectors keep working.
// ============================================================================
`ifndef EDRV32_HPM_VH
`define EDRV32_HPM_VH

`define EDRV32_HPM_EVENT_W 98

`define EDRV32_HPM_CONTROL_FLOW          6'd1
`define EDRV32_HPM_MISPREDICT            6'd2
`define EDRV32_HPM_DIRECTION_MISS        6'd3
`define EDRV32_HPM_TARGET_MISS           6'd4
`define EDRV32_HPM_PREDICTED_TAKEN       6'd5
`define EDRV32_HPM_RAS_PUSH              6'd6
`define EDRV32_HPM_RAS_POP               6'd7
`define EDRV32_HPM_DEPENDENCY_STALL      6'd8
`define EDRV32_HPM_LOAD_USE_STALL        6'd9
`define EDRV32_HPM_STRUCTURAL_STALL      6'd10
`define EDRV32_HPM_MEM1_FIFO_FULL        6'd11
`define EDRV32_HPM_MDU_RAW_HAZARD        6'd12
`define EDRV32_HPM_MDU_WAW_HAZARD        6'd13
`define EDRV32_HPM_MDU_ISSUE_WAIT        6'd14
`define EDRV32_HPM_IF_REQ_BACKPRESSURE   6'd15
`define EDRV32_HPM_IF_RESP_BACKPRESSURE  6'd16
`define EDRV32_HPM_FRONTEND_EMPTY        6'd17
`define EDRV32_HPM_DMEM_BACKPRESSURE     6'd18
`define EDRV32_HPM_DCACHE_REQ_WAIT       6'd19
`define EDRV32_HPM_COMMIT_BACKPRESSURE   6'd20
`define EDRV32_HPM_ICACHE_MISS           6'd21
`define EDRV32_HPM_DCACHE_MISS           6'd22
`define EDRV32_HPM_DCACHE_WRITEBACK      6'd23
`define EDRV32_HPM_ICACHE_REFILL_WAIT    6'd24
`define EDRV32_HPM_DCACHE_REFILL_WAIT    6'd25
`define EDRV32_HPM_RETIRED_LOAD          6'd26
`define EDRV32_HPM_RETIRED_STORE         6'd27
`define EDRV32_HPM_RETIRED_BRANCH        6'd28
`define EDRV32_HPM_RETIRED_JUMP          6'd29
`define EDRV32_HPM_RETIRED_MDU           6'd30
`define EDRV32_HPM_RETIRED_ALU           6'd31
`define EDRV32_HPM_RETIRED_CSR           6'd32
`define EDRV32_HPM_RETIRED_COMPRESSED    6'd33
`define EDRV32_HPM_EXCEPTION             6'd34
`define EDRV32_HPM_INTERRUPT             6'd35
`define EDRV32_HPM_ECALL                 6'd36
`define EDRV32_HPM_IMEM_REQUEST          6'd37
`define EDRV32_HPM_IMEM_RESPONSE         6'd38
`define EDRV32_HPM_DCACHE_REQUEST        6'd39
`define EDRV32_HPM_EMPTY_RETIRE_SLOT      6'd40

// Mutual-exclusion empty-retire attribution.  Fixed priority from COMMIT
// toward IF1; exactly one of these fires on every non-retire cycle.
`define EDRV32_HPM_ATTR_COMMIT_MEM         7'd41
`define EDRV32_HPM_ATTR_COMMIT_OTHER       7'd42
`define EDRV32_HPM_ATTR_COMMIT_TRAP        7'd43
`define EDRV32_HPM_ATTR_MEM2_CACHE_WAIT    7'd44
`define EDRV32_HPM_ATTR_MEM1_BLOCKED       7'd45
`define EDRV32_HPM_ATTR_MEM1_FIFO_FULL2    7'd46
`define EDRV32_HPM_ATTR_EX_LATE_LOAD       7'd47
`define EDRV32_HPM_ATTR_EX_SIDE_EFFECTS    7'd48
`define EDRV32_HPM_ATTR_RAW_RESIDENT       7'd49
`define EDRV32_HPM_ATTR_RAW_LOAD           7'd50
`define EDRV32_HPM_ATTR_RAW_MDU            7'd51
`define EDRV32_HPM_ATTR_STRUCTURAL         7'd52
`define EDRV32_HPM_ATTR_FE_REDIRECT        7'd53
`define EDRV32_HPM_ATTR_FE_IMISS           7'd54
`define EDRV32_HPM_ATTR_FE_WAIT_BLOCK      7'd55
`define EDRV32_HPM_ATTR_FE_OTHER           7'd56

// Retire-gap histogram: gap value measured at the retire edge.
`define EDRV32_HPM_GAP_0                   7'd57
`define EDRV32_HPM_GAP_1                   7'd58
`define EDRV32_HPM_GAP_2                   7'd59
`define EDRV32_HPM_GAP_3                   7'd60
`define EDRV32_HPM_GAP_4P                  7'd61

// RAW producer/consumer matrix counted on decode dependency-stall cycles.
// Producer {0=ALU/JUMP, 1=LOAD, 2=MDU, 3=OTHER}, consumer
// {0=ALU/JUMP, 1=CONTROL, 2=MEMORY, 3=OTHER}; index 62 + producer*4 + consumer.
`define EDRV32_HPM_RAW_MATRIX_FIRST        7'd62
`define EDRV32_HPM_RAW_MATRIX_LAST         7'd77

// Frontend useful/discarded fetch and prediction-redirect accounting.
`define EDRV32_HPM_FE_APPEND_HW1            7'd78
`define EDRV32_HPM_FE_APPEND_HW2            7'd79
`define EDRV32_HPM_FE_CONSUME_HW1           7'd80
`define EDRV32_HPM_FE_CONSUME_HW2           7'd81
`define EDRV32_HPM_FE_PRED_REDIRECT         7'd82
`define EDRV32_HPM_FE_DISCARD_BLOCK         7'd83

// Fetch-time BTB and final direction metadata travels with the instruction
// to EX. Events 84..89 describe the selected BHT/loop direction.
`define EDRV32_HPM_BR_MISS_DIR_T_ACT_T       7'd84
`define EDRV32_HPM_BR_MISS_DIR_T_ACT_N       7'd85
`define EDRV32_HPM_BR_MISS_DIR_N_ACT_T       7'd86
`define EDRV32_HPM_BR_MISS_DIR_N_ACT_N       7'd87
`define EDRV32_HPM_BR_HIT_DIR_WRONG         7'd88
`define EDRV32_HPM_BR_HIT_DIR_CORRECT       7'd89
`define EDRV32_HPM_JAL_BTB_MISS             7'd90
`define EDRV32_HPM_JALR_BTB_MISS            7'd91

// IF2 redirect origin and returned-block discard causes.
`define EDRV32_HPM_PRED_APPEND_SLOT0        7'd92
`define EDRV32_HPM_PRED_APPEND_SLOT1        7'd93
`define EDRV32_HPM_PRED_APPEND_CROSS        7'd94
`define EDRV32_HPM_PRED_CANDIDATE           7'd95
`define EDRV32_HPM_DISCARD_STALE            7'd96
`define EDRV32_HPM_DISCARD_ARCH_REDIR       7'd97
`define EDRV32_HPM_DISCARD_PRED_REDIR       7'd98

`endif
