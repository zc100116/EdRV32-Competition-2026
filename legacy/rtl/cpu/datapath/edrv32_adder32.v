// ============================================================================
// File        : edrv32_adder32.v
// Description : 32-bit adder written in canonical arithmetic form so FPGA
//               synthesis can map it onto the device carry chain.
// ============================================================================
module edrv32_adder32 (
    input  wire [31:0] lhs_i,
    input  wire [31:0] rhs_i,
    input  wire        carry_i,
    output wire [31:0] sum_o,
    output wire        carry_o
);

    // The former hand-expanded four-bit CLA mapped to LUT routing on PGL50H.
    // A single 33-bit arithmetic expression is the vendor-recognized form and
    // preserves the exact modulo-2^32 sum and carry-out interface.
    wire [32:0] extended_sum_w = {1'b0, lhs_i} +
                                 {1'b0, rhs_i} +
                                 {{32{1'b0}}, carry_i};

    assign sum_o   = extended_sum_w[31:0];
    assign carry_o = extended_sum_w[32];

endmodule
