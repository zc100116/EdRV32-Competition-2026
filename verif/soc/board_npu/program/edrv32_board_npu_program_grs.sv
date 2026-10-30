// File: edrv32_board_npu_program_grs.sv
// Spec: Task T-NPU4; npu-testplan EQ-01.
// Description: Supply the vendor APM model's hierarchical global reset reference.
//              GRS_EN is FALSE in the MAC wrapper, matching the existing EQ-01 stub.
// Clock domain: none (constant global reset release).
module edrv32_board_npu_program_grs;
    wire GRSNET = 1'b1;
endmodule
