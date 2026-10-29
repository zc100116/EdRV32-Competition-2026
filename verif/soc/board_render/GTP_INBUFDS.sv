// File: GTP_INBUFDS.sv
// Spec: fpga/ip/ip_ddr3.md; Task B3-6.
// Description: Differential reference-clock input model.
// Clock domain: reference clock.
module GTP_INBUFDS (
    input wire I,
    input wire IB,
    output wire O
);
    assign O = I;
    wire unused_negative = IB;
endmodule
