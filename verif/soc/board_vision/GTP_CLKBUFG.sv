// File: GTP_CLKBUFG.sv
// Spec: fpga/rtl/edrv32_fpga_rgmii.v; Task B3-7.
// Description: Combinational device buffer model.
// Clock domain: 125 MHz Ethernet.
module GTP_CLKBUFG (
    input wire CLKIN,
    output wire CLKOUT
);
    assign CLKOUT = CLKIN;
endmodule
