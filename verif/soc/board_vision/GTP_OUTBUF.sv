// File: GTP_OUTBUF.sv
// Spec: fpga/rtl/edrv32_fpga_rgmii.v; Task B3-7.
// Description: Combinational device buffer model.
// Clock domain: 125 MHz Ethernet.
module GTP_OUTBUF #(
    parameter IOSTANDARD = "LVCMOS33",
    parameter SLEW_RATE = "FAST",
    parameter DRIVE_STRENGTH = "4"
) (
    input wire I,
    output wire O
);
    assign O = I;
    wire unused_configuration = &{1'b0, IOSTANDARD, SLEW_RATE, DRIVE_STRENGTH};
endmodule
