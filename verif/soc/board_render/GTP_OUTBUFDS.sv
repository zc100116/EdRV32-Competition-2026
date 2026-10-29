// File: GTP_OUTBUFDS.sv
// Spec: fpga/rtl/edrv32_fpga_tmds.v; Task B3-6.
// Description: Differential TMDS output buffer model.
// Clock domain: serializer clock.
module GTP_OUTBUFDS #(
    parameter IOSTANDARD = "TMDS"
) (
    input wire I,
    output wire O,
    output wire OB
);
    assign O = I;
    assign OB = ~I;
    wire unused_standard = IOSTANDARD == "TMDS";
endmodule
