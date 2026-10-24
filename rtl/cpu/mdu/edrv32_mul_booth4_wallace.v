// ============================================================================
// File        : edrv32_mul_booth4_wallace.v
// Description : Three-boundary radix-16 Booth / Wallace RV32 multiplier.
//               Runtime arithmetic is structural: partial-product muxing,
//               full-adder compressors and the shared block-CLA final adder.
// Reuse       : Adapted from pre-rewrite exec/mul/mul_booth4_wallace.v.
// Notes       : Generate-loop arithmetic is elaboration-only, not synthesized
//               operand datapath arithmetic.
// ============================================================================
`include "edrv32_uop.vh"

module edrv32_mul_booth4_wallace (
    input  wire                         clk_i,
    input  wire                         rst_n_i,
    input  wire                         flush_i,
    input  wire                         start_i,
    input  wire [`EDRV32_MDU_OP_W-1:0] operation_i,
    input  wire [31:0]                  lhs_i,
    input  wire [31:0]                  rhs_i,
    output wire                         result_valid_o,
    output wire [31:0]                  result_o
);

    localparam GROUP_COUNT = 9;
    localparam PARTIAL_PRODUCT_COUNT = 18;

    // MULH and MULHSU sign-extend the multiplicand; only MULH also
    // sign-extends the multiplier.
    wire lhs_signed_w = (operation_i == `EDRV32_MDU_MULH) ||
                        (operation_i == `EDRV32_MDU_MULHSU);
    wire rhs_signed_w = (operation_i == `EDRV32_MDU_MULH);

    wire [63:0] multiplicand_w = lhs_signed_w
        ? {{32{lhs_i[31]}}, lhs_i} : {32'd0, lhs_i};
    wire [63:0] multiplicand_x2_w = {multiplicand_w[62:0], 1'b0};
    wire [63:0] multiplicand_x4_w = {multiplicand_w[61:0], 2'b0};
    wire [63:0] multiplicand_x8_w = {multiplicand_w[60:0], 3'b0};

    // Precompute every positive and negative magnitude selected by a radix-16
    // Booth digit.  Negation remains structural through edrv32_adder64.
    wire [63:0] negative_multiplicand_w;
    wire [63:0] negative_multiplicand_x2_w;
    wire [63:0] negative_multiplicand_x4_w;
    wire [63:0] negative_multiplicand_x8_w;
    wire [3:0] unused_negate_carry_w;

    edrv32_adder64 u_negate_x1 (
        .lhs_i(~multiplicand_w),
        .rhs_i(64'd0),
        .carry_i(1'b1),
        .sum_o(negative_multiplicand_w),
        .carry_o(unused_negate_carry_w[0])
    );
    edrv32_adder64 u_negate_x2 (
        .lhs_i(~multiplicand_x2_w),
        .rhs_i(64'd0),
        .carry_i(1'b1),
        .sum_o(negative_multiplicand_x2_w),
        .carry_o(unused_negate_carry_w[1])
    );
    edrv32_adder64 u_negate_x4 (
        .lhs_i(~multiplicand_x4_w),
        .rhs_i(64'd0),
        .carry_i(1'b1),
        .sum_o(negative_multiplicand_x4_w),
        .carry_o(unused_negate_carry_w[2])
    );
    edrv32_adder64 u_negate_x8 (
        .lhs_i(~multiplicand_x8_w),
        .rhs_i(64'd0),
        .carry_i(1'b1),
        .sum_o(negative_multiplicand_x8_w),
        .carry_o(unused_negate_carry_w[3])
    );

    // Nine overlapping five-bit windows cover the 32-bit multiplier.
    wire [33:0] multiplier_extended_w = rhs_signed_w
        ? {{2{rhs_i[31]}}, rhs_i} : {2'b0, rhs_i};
    wire [4:0] booth_select_w [0:GROUP_COUNT-1];

    genvar group_index;
    generate
        for (group_index = 0;
             group_index < GROUP_COUNT;
             group_index = group_index + 1) begin : gen_booth_select
            localparam [5:0] BASE_BIT = group_index * 4;
            if (BASE_BIT == 0) begin : gen_first_group
                assign booth_select_w[group_index] =
                    {multiplier_extended_w[3:0], 1'b0};
            end else if (BASE_BIT + 3 < 34) begin : gen_middle_group
                assign booth_select_w[group_index] =
                    multiplier_extended_w[BASE_BIT+3:BASE_BIT-1];
            end else begin : gen_last_group
                // GROUP_COUNT is fixed at nine, so the final radix-16 window
                // is {b[35],b[34],b[33],b[32],b[31]}. The two absent bits
                // are explicit sign-extension copies; no out-of-range selects.
                assign booth_select_w[group_index] =
                    {{2{multiplier_extended_w[33]}}, multiplier_extended_w[33:31]};
            end
        end
    endgenerate

    wire [63:0] group_row_a_w [0:GROUP_COUNT-1];
    wire [63:0] group_row_b_w [0:GROUP_COUNT-1];
    wire        group_has_row_b_w [0:GROUP_COUNT-1];

    // Decode every Booth window into one or two shifted rows.  Two rows are
    // required for magnitudes such as 3, 5, 6 and 7.
    generate
        for (group_index = 0;
             group_index < GROUP_COUNT;
             group_index = group_index + 1) begin : gen_partial_product
            localparam [5:0] SHIFT_AMOUNT = group_index * 4;
            wire [63:0] positive_zero_w = 64'd0;
            wire [63:0] positive_x1_w = {
                multiplicand_w[63-SHIFT_AMOUNT:0],
                {SHIFT_AMOUNT{1'b0}}
            };
            wire [63:0] positive_x2_w = {
                multiplicand_x2_w[63-SHIFT_AMOUNT:0],
                {SHIFT_AMOUNT{1'b0}}
            };
            wire [63:0] positive_x4_w = {
                multiplicand_x4_w[63-SHIFT_AMOUNT:0],
                {SHIFT_AMOUNT{1'b0}}
            };
            wire [63:0] positive_x8_w = {
                multiplicand_x8_w[63-SHIFT_AMOUNT:0],
                {SHIFT_AMOUNT{1'b0}}
            };
            wire [63:0] negative_x1_w = {
                negative_multiplicand_w[63-SHIFT_AMOUNT:0],
                {SHIFT_AMOUNT{1'b0}}
            };
            wire [63:0] negative_x2_w = {
                negative_multiplicand_x2_w[63-SHIFT_AMOUNT:0],
                {SHIFT_AMOUNT{1'b0}}
            };
            wire [63:0] negative_x4_w = {
                negative_multiplicand_x4_w[63-SHIFT_AMOUNT:0],
                {SHIFT_AMOUNT{1'b0}}
            };
            wire [63:0] negative_x8_w = {
                negative_multiplicand_x8_w[63-SHIFT_AMOUNT:0],
                {SHIFT_AMOUNT{1'b0}}
            };

            reg [63:0] selected_row_a_r;
            reg [63:0] selected_row_b_r;
            reg        selected_has_row_b_r;

            always @* begin
                case (booth_select_w[group_index])
                    5'd0, 5'd31: begin
                        selected_row_a_r     = positive_zero_w;
                        selected_row_b_r     = positive_zero_w;
                        selected_has_row_b_r = 1'b0;
                    end
                    5'd1, 5'd2: begin
                        selected_row_a_r     = positive_x1_w;
                        selected_row_b_r     = positive_zero_w;
                        selected_has_row_b_r = 1'b0;
                    end
                    5'd3, 5'd4: begin
                        selected_row_a_r     = positive_x2_w;
                        selected_row_b_r     = positive_zero_w;
                        selected_has_row_b_r = 1'b0;
                    end
                    5'd7, 5'd8: begin
                        selected_row_a_r     = positive_x4_w;
                        selected_row_b_r     = positive_zero_w;
                        selected_has_row_b_r = 1'b0;
                    end
                    5'd15: begin
                        selected_row_a_r     = positive_x8_w;
                        selected_row_b_r     = positive_zero_w;
                        selected_has_row_b_r = 1'b0;
                    end
                    5'd29, 5'd30: begin
                        selected_row_a_r     = negative_x1_w;
                        selected_row_b_r     = positive_zero_w;
                        selected_has_row_b_r = 1'b0;
                    end
                    5'd27, 5'd28: begin
                        selected_row_a_r     = negative_x2_w;
                        selected_row_b_r     = positive_zero_w;
                        selected_has_row_b_r = 1'b0;
                    end
                    5'd23, 5'd24: begin
                        selected_row_a_r     = negative_x4_w;
                        selected_row_b_r     = positive_zero_w;
                        selected_has_row_b_r = 1'b0;
                    end
                    5'd16: begin
                        selected_row_a_r     = negative_x8_w;
                        selected_row_b_r     = positive_zero_w;
                        selected_has_row_b_r = 1'b0;
                    end
                    5'd5, 5'd6: begin
                        selected_row_a_r     = positive_x1_w;
                        selected_row_b_r     = positive_x2_w;
                        selected_has_row_b_r = 1'b1;
                    end
                    5'd9, 5'd10: begin
                        selected_row_a_r     = positive_x1_w;
                        selected_row_b_r     = positive_x4_w;
                        selected_has_row_b_r = 1'b1;
                    end
                    5'd11, 5'd12: begin
                        selected_row_a_r     = positive_x2_w;
                        selected_row_b_r     = positive_x4_w;
                        selected_has_row_b_r = 1'b1;
                    end
                    5'd13, 5'd14: begin
                        selected_row_a_r     = positive_x8_w;
                        selected_row_b_r     = negative_x1_w;
                        selected_has_row_b_r = 1'b1;
                    end
                    5'd17, 5'd18: begin
                        selected_row_a_r     = negative_x8_w;
                        selected_row_b_r     = positive_x1_w;
                        selected_has_row_b_r = 1'b1;
                    end
                    5'd19, 5'd20: begin
                        selected_row_a_r     = negative_x2_w;
                        selected_row_b_r     = negative_x4_w;
                        selected_has_row_b_r = 1'b1;
                    end
                    5'd21, 5'd22: begin
                        selected_row_a_r     = negative_x1_w;
                        selected_row_b_r     = negative_x4_w;
                        selected_has_row_b_r = 1'b1;
                    end
                    5'd25, 5'd26: begin
                        selected_row_a_r     = negative_x1_w;
                        selected_row_b_r     = negative_x2_w;
                        selected_has_row_b_r = 1'b1;
                    end
                    default: begin
                        selected_row_a_r     = positive_zero_w;
                        selected_row_b_r     = positive_zero_w;
                        selected_has_row_b_r = 1'b0;
                    end
                endcase
            end

            assign group_row_a_w[group_index] = selected_row_a_r;
            assign group_row_b_w[group_index] = selected_row_b_r;
            assign group_has_row_b_w[group_index] = selected_has_row_b_r;
        end
    endgenerate

    wire [63:0] partial_product_w [0:PARTIAL_PRODUCT_COUNT-1];
    generate
        for (group_index = 0;
             group_index < GROUP_COUNT;
             group_index = group_index + 1) begin : gen_flatten_partial_product
            assign partial_product_w[group_index] = group_row_a_w[group_index];
            assign partial_product_w[group_index + GROUP_COUNT] =
                group_has_row_b_w[group_index] ? group_row_b_w[group_index] : 64'd0;
        end
    endgenerate

    // Pipeline boundary 1: capture all selected partial-product rows and the
    // operation that determines which half of the final product is returned.
    reg [63:0] stage1_partial_product_r [0:PARTIAL_PRODUCT_COUNT-1];
    reg [`EDRV32_MDU_OP_W-1:0] stage1_operation_r;
    reg stage1_valid_r;

    generate
        for (group_index = 0;
             group_index < PARTIAL_PRODUCT_COUNT;
             group_index = group_index + 1) begin : gen_capture_partial_product
            always @(posedge clk_i) begin
                if (start_i)
                    stage1_partial_product_r[group_index] <= partial_product_w[group_index];
            end
        end
    endgenerate

    // Stage 1 operation metadata payload.
    always @(posedge clk_i) begin
        if (start_i)
            stage1_operation_r <= operation_i;
    end

    // Stage 1 occupancy tag.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            stage1_valid_r <= 1'b0;
        else if (flush_i)
            stage1_valid_r <= 1'b0;
        else
            stage1_valid_r <= start_i;
    end

    // Wallace reduction network: 18 rows become 12, 8, 6, 4, 3 and finally
    // two carry-save rows.  Every reduction element is a structural 3:2 tree.
    wire [63:0] reduce_level1_w [0:11];
    edrv32_wallace_compress_3to2 u_reduce_1_0 (
        .row_a_i(stage1_partial_product_r[0]),
        .row_b_i(stage1_partial_product_r[1]),
        .row_c_i(stage1_partial_product_r[2]),
        .sum_o(reduce_level1_w[0]),
        .carry_o(reduce_level1_w[1])
    );
    edrv32_wallace_compress_3to2 u_reduce_1_1 (
        .row_a_i(stage1_partial_product_r[3]),
        .row_b_i(stage1_partial_product_r[4]),
        .row_c_i(stage1_partial_product_r[5]),
        .sum_o(reduce_level1_w[2]),
        .carry_o(reduce_level1_w[3])
    );
    edrv32_wallace_compress_3to2 u_reduce_1_2 (
        .row_a_i(stage1_partial_product_r[6]),
        .row_b_i(stage1_partial_product_r[7]),
        .row_c_i(stage1_partial_product_r[8]),
        .sum_o(reduce_level1_w[4]),
        .carry_o(reduce_level1_w[5])
    );
    edrv32_wallace_compress_3to2 u_reduce_1_3 (
        .row_a_i(stage1_partial_product_r[9]),
        .row_b_i(stage1_partial_product_r[10]),
        .row_c_i(stage1_partial_product_r[11]),
        .sum_o(reduce_level1_w[6]),
        .carry_o(reduce_level1_w[7])
    );
    edrv32_wallace_compress_3to2 u_reduce_1_4 (
        .row_a_i(stage1_partial_product_r[12]),
        .row_b_i(stage1_partial_product_r[13]),
        .row_c_i(stage1_partial_product_r[14]),
        .sum_o(reduce_level1_w[8]),
        .carry_o(reduce_level1_w[9])
    );
    edrv32_wallace_compress_3to2 u_reduce_1_5 (
        .row_a_i(stage1_partial_product_r[15]),
        .row_b_i(stage1_partial_product_r[16]),
        .row_c_i(stage1_partial_product_r[17]),
        .sum_o(reduce_level1_w[10]),
        .carry_o(reduce_level1_w[11])
    );

    wire [63:0] reduce_level2_w [0:7];
    edrv32_wallace_compress_3to2 u_reduce_2_0 (
        .row_a_i(reduce_level1_w[0]),
        .row_b_i(reduce_level1_w[1]),
        .row_c_i(reduce_level1_w[2]),
        .sum_o(reduce_level2_w[0]),
        .carry_o(reduce_level2_w[1])
    );
    edrv32_wallace_compress_3to2 u_reduce_2_1 (
        .row_a_i(reduce_level1_w[3]),
        .row_b_i(reduce_level1_w[4]),
        .row_c_i(reduce_level1_w[5]),
        .sum_o(reduce_level2_w[2]),
        .carry_o(reduce_level2_w[3])
    );
    edrv32_wallace_compress_3to2 u_reduce_2_2 (
        .row_a_i(reduce_level1_w[6]),
        .row_b_i(reduce_level1_w[7]),
        .row_c_i(reduce_level1_w[8]),
        .sum_o(reduce_level2_w[4]),
        .carry_o(reduce_level2_w[5])
    );
    edrv32_wallace_compress_3to2 u_reduce_2_3 (
        .row_a_i(reduce_level1_w[9]),
        .row_b_i(reduce_level1_w[10]),
        .row_c_i(reduce_level1_w[11]),
        .sum_o(reduce_level2_w[6]),
        .carry_o(reduce_level2_w[7])
    );

    wire [63:0] reduce_level3_w [0:5];
    edrv32_wallace_compress_3to2 u_reduce_3_0 (
        .row_a_i(reduce_level2_w[0]),
        .row_b_i(reduce_level2_w[1]),
        .row_c_i(reduce_level2_w[2]),
        .sum_o(reduce_level3_w[0]),
        .carry_o(reduce_level3_w[1])
    );
    edrv32_wallace_compress_3to2 u_reduce_3_1 (
        .row_a_i(reduce_level2_w[3]),
        .row_b_i(reduce_level2_w[4]),
        .row_c_i(reduce_level2_w[5]),
        .sum_o(reduce_level3_w[2]),
        .carry_o(reduce_level3_w[3])
    );
    assign reduce_level3_w[4] = reduce_level2_w[6];
    assign reduce_level3_w[5] = reduce_level2_w[7];

    wire [63:0] reduce_level4_w [0:3];
    edrv32_wallace_compress_3to2 u_reduce_4_0 (
        .row_a_i(reduce_level3_w[0]),
        .row_b_i(reduce_level3_w[1]),
        .row_c_i(reduce_level3_w[2]),
        .sum_o(reduce_level4_w[0]),
        .carry_o(reduce_level4_w[1])
    );
    edrv32_wallace_compress_3to2 u_reduce_4_1 (
        .row_a_i(reduce_level3_w[3]),
        .row_b_i(reduce_level3_w[4]),
        .row_c_i(reduce_level3_w[5]),
        .sum_o(reduce_level4_w[2]),
        .carry_o(reduce_level4_w[3])
    );

    wire [63:0] reduce_level5_w [0:2];
    edrv32_wallace_compress_3to2 u_reduce_5_0 (
        .row_a_i(reduce_level4_w[0]),
        .row_b_i(reduce_level4_w[1]),
        .row_c_i(reduce_level4_w[2]),
        .sum_o(reduce_level5_w[0]),
        .carry_o(reduce_level5_w[1])
    );
    assign reduce_level5_w[2] = reduce_level4_w[3];

    wire [63:0] reduce_sum_w;
    wire [63:0] reduce_carry_w;
    edrv32_wallace_compress_3to2 u_reduce_6_0 (
        .row_a_i(reduce_level5_w[0]),
        .row_b_i(reduce_level5_w[1]),
        .row_c_i(reduce_level5_w[2]),
        .sum_o(reduce_sum_w),
        .carry_o(reduce_carry_w)
    );

    // Pipeline boundary 2: isolate the Wallace tree from the final carry-
    // propagate adder.
    reg [63:0] stage2_sum_r;
    reg [63:0] stage2_carry_r;
    reg [`EDRV32_MDU_OP_W-1:0] stage2_operation_r;
    reg stage2_valid_r;

    // Stage 2 Wallace-reduction payload.
    always @(posedge clk_i) begin
        if (stage1_valid_r) begin
            stage2_sum_r       <= reduce_sum_w;
            stage2_carry_r     <= reduce_carry_w;
            stage2_operation_r <= stage1_operation_r;
        end
    end

    // Stage 2 occupancy tag.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            stage2_valid_r <= 1'b0;
        else if (flush_i)
            stage2_valid_r <= 1'b0;
        else
            stage2_valid_r <= stage1_valid_r;
    end

    // Final structural addition converts the two carry-save rows to a product.
    wire [63:0] full_product_w;
    wire unused_final_carry_w;
    edrv32_adder64 u_final_product_adder (
        .lhs_i(stage2_sum_r),
        .rhs_i(stage2_carry_r),
        .carry_i(1'b0),
        .sum_o(full_product_w),
        .carry_o(unused_final_carry_w)
    );

    // Pipeline boundary 3: select and retain the architectural 32-bit result.
    reg [31:0] stage3_result_r;
    reg stage3_valid_r;

    // Stage 3 final-product payload.
    always @(posedge clk_i) begin
        if (stage2_valid_r)
            stage3_result_r <= (stage2_operation_r == `EDRV32_MDU_MUL)
                ? full_product_w[31:0] : full_product_w[63:32];
    end

    // Stage 3 occupancy tag / completion pulse.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            stage3_valid_r <= 1'b0;
        else if (flush_i)
            stage3_valid_r <= 1'b0;
        else
            stage3_valid_r <= stage2_valid_r;
    end

    assign result_valid_o = stage3_valid_r;
    assign result_o = stage3_result_r;

endmodule
