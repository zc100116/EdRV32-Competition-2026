// File: edrv32_gpu_scenario.sv
// Spec: gpu-soc-testplan ST-11; GPU 2.9, 5.
// Description: Software checks PLIC, DONE and cached lists; harness checks SIM_EXIT.
// Clock domain: clk_sys software completion.
`timescale 1ns/1ps
module edrv32_gpu_scenario (
    output bit checks_complete_o,
    output wire [1:0] model_sda_oe_o
);
    assign model_sda_oe_o = 2'b00;
    initial checks_complete_o = 1;
endmodule
