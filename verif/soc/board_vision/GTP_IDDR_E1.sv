// File: GTP_IDDR_E1.sv
// Spec: fpga/rtl/edrv32_fpga_rgmii.v; Task B3-7.
// Description: SAME_PIPELINED input DDR model; present the previous rise/fall pair together.
// Clock domain: 125 MHz Ethernet.
module GTP_IDDR_E1 #(
    parameter GRS_EN = "TRUE",
    parameter IDDR_MODE = "SAME_PIPELINED",
    parameter RS_TYPE = "ASYNC_RESET"
) (
    input wire D,
    input wire CLK,
    input wire CE,
    input wire RS,
    output reg Q0,
    output reg Q1
);
    reg rise_r;
    reg fall_r;
    always @(negedge CLK) begin
        if (CE) fall_r <= D;
    end
    always @(posedge CLK) begin
        if (CE) begin
            rise_r <= D;
            Q0 <= rise_r;
            Q1 <= fall_r;
        end
    end
    wire unused_configuration = &{1'b0, GRS_EN, IDDR_MODE, RS_TYPE, RS};
endmodule
