// File: GTP_ODDR_E1.sv
// Spec: fpga/rtl/edrv32_fpga_rgmii.v; Task B3-7.
// Description: SAME_EDGE output DDR model; capture both values at the rising edge.
// Clock domain: 125 MHz Ethernet.
module GTP_ODDR_E1 #(
    parameter GRS_EN = "TRUE",
    parameter ODDR_MODE = "SAME_EDGE",
    parameter RS_TYPE = "ASYNC_RESET"
) (
    input wire CLK,
    input wire CE,
    input wire RS,
    input wire D0,
    input wire D1,
    output wire Q
);
    reg rise_r;
    reg fall_r;
    always @(posedge CLK) begin
        if (CE) begin
            rise_r <= D0;
            fall_r <= D1;
        end
    end
    assign Q = CLK ? rise_r : fall_r;
    wire unused_configuration = &{1'b0, GRS_EN, ODDR_MODE, RS_TYPE, RS};
endmodule
