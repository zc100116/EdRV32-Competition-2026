// ============================================================================
// File        : edrv32_compare32.v
// Description : Equality, signed less-than and unsigned less-than expressed
//               with canonical Verilog comparison operators.  Synthesis owns
//               the target-specific comparator implementation and sharing.
// ============================================================================
module edrv32_compare32 (
    input  wire [31:0] lhs_i,
    input  wire [31:0] rhs_i,
    output wire        equal_o,
    output wire        signed_less_o,
    output wire        unsigned_less_o
);

    assign equal_o         = (lhs_i == rhs_i);
    assign unsigned_less_o = (lhs_i < rhs_i);
    assign signed_less_o   = ($signed(lhs_i) < $signed(rhs_i));

endmodule
