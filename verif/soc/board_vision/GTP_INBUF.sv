// File: GTP_INBUF.sv
// Spec: fpga/rtl/edrv32_fpga_rgmii.v; Task B3-7.
// Description: Combinational device buffer model.
// Clock domain: 125 MHz Ethernet.
module GTP_INBUF #(
    parameter IOSTANDARD = "LVCMOS33"
) (
    input wire I,
    output wire O
);
    assign O = I;
    wire unused_configuration = &{1'b0, IOSTANDARD};
endmodule
