// ============================================================================
// File        : edrv32_full_adder.v
// Description : One-bit gate-level full-adder primitive.
// Reuse       : Adapted from the pre-rewrite datapath/full_adder.v.
// ============================================================================
module edrv32_full_adder (
    input  wire a_i,
    input  wire b_i,
    input  wire cin_i,
    output wire sum_o,
    output wire cout_o
);

    wire a_xor_b_w;
    wire a_and_b_w;
    wire a_and_cin_w;
    wire b_and_cin_w;

    xor u_xor_ab  (a_xor_b_w, a_i, b_i);
    xor u_xor_sum (sum_o, a_xor_b_w, cin_i);

    and u_and_ab   (a_and_b_w,   a_i, b_i);
    and u_and_acin (a_and_cin_w, a_i, cin_i);
    and u_and_bcin (b_and_cin_w, b_i, cin_i);
    or  u_or_cout  (cout_o, a_and_b_w, a_and_cin_w, b_and_cin_w);

endmodule
