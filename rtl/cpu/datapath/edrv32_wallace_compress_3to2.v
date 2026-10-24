// ============================================================================
// File        : edrv32_wallace_compress_3to2.v
// Description : Parameterized structural three-row to two-row compressor.
// Reuse       : Adapted from pre-rewrite datapath/wallace_compress_3to2.v.
// ============================================================================
module edrv32_wallace_compress_3to2 #(
    parameter WIDTH = 64
) (
    input  wire [WIDTH-1:0] row_a_i,
    input  wire [WIDTH-1:0] row_b_i,
    input  wire [WIDTH-1:0] row_c_i,
    output wire [WIDTH-1:0] sum_o,
    output wire [WIDTH-1:0] carry_o
);

    wire [WIDTH-1:0] cell_carry_w;
    genvar bit_index;
    generate
        // Every column is an independent full adder.  The carry row is shifted
        // once after the array so all output rows retain the original width.
        for (bit_index = 0;
             bit_index < WIDTH;
             bit_index = bit_index + 1) begin : gen_compressor_cell
            edrv32_full_adder u_cell (
                .a_i(row_a_i[bit_index]),
                .b_i(row_b_i[bit_index]),
                .cin_i(row_c_i[bit_index]),
                .sum_o(sum_o[bit_index]),
                .cout_o(cell_carry_w[bit_index])
            );
        end
    endgenerate

    assign carry_o = {cell_carry_w[WIDTH-2:0], 1'b0};

endmodule
