// File: edrv32_gpu_setup_plane.v
// Spec: gpu-spec 2.13.3-6, 13; GPU microarchitecture 4.4, 4.10.
// Description: One attribute per enabled clock, with complete products and explicit rounding.
//              Difference form removes one vertex product per numerator without changing its sum.
// Clock domain: clk_gpu.
module edrv32_gpu_setup_plane (
    // Clock and pipeline control.
    input wire clk_i,
    input wire rst_n_i,
    input wire enable_i,
    input wire stop_i,

    // Reciprocal metadata shares this unit's enabled nine-cycle RAM.
    input wire [5:0] recip_delay_wr_data_i,
    output wire [5:0] recip_delay_rd_data_o,

    // Attribute and triangle context.
    input wire plane_valid_i,
    input wire [6:0] plane_tag_i,
    input wire [152:0] plane_value_i,
    input wire [71:0] plane_delta_i,
    input wire [35:0] plane_offset_i,
    input wire [30:0] plane_reciprocal_i,
    input wire [5:0] plane_exponent_i,

    // Complete coefficient for the tagged attribute.
    output wire plane_valid_o,
    output wire [6:0] plane_tag_o,
    output wire [69:0] plane_start_o,
    output wire [111:0] plane_gradient_o,
    output wire [9:0] plane_h_o,
    output wire [57:0] plane_normal_o
);
    reg signed [9:0] h_first_r;
    reg signed [9:0] h_last_r;
    reg [35:0] offset_first_r;
    reg [8:0] metadata_write_r;
    wire [8:0] metadata_read_13_w;
    wire [8:0] metadata_read_9_w;
    wire [71:0] unused_metadata_13_w;
    wire [71:0] unused_metadata_9_w;
    wire signed [9:0] normal_h_w;
    wire [32:0] first_w;
    wire [5:0] exponent_w;
    wire [35:0] offset_w;
    reg [14:0] valid_r;
    wire [6:0] tag_w [0:14];
    wire [30:0] reciprocal_w [0:5];
    wire signed [33:0] difference_w [0:1];
    reg [71:0] delta_r;
    wire signed [51:0] product_w [0:3];
    wire signed [73:0] origin_product_w [0:1];
    wire [28:0] normal_w [0:1];
    wire [32:0] scaled_w [0:2];
    wire [50:0] maximum_01_w;
    wire [50:0] maximum_w;
    wire signed [9:0] h_w;
    assign maximum_01_w = plane_value_i[101:51] > plane_value_i[50:0]
        ? plane_value_i[101:51] : plane_value_i[50:0];
    assign maximum_w = plane_value_i[152:102] > maximum_01_w
        ? plane_value_i[152:102] : maximum_01_w;
    // Input stage: two maximum comparators, one six-level leading-one tree.
    wire [63:0] leading_data64_w;
    wire [5:0] leading_w;
    wire leading_bit0_w;
    wire leading_bit1_w;
    wire leading_bit2_w;
    wire leading_bit3_w;
    wire leading_bit4_w;
    wire leading_bit5_w;
    assign leading_w = {leading_bit5_w, leading_bit4_w, leading_bit3_w,
        leading_bit2_w, leading_bit1_w, leading_bit0_w};
    assign leading_data64_w = {13'd0, maximum_w};
    wire [31:0] leading_data32_w;
    assign leading_bit5_w = |leading_data64_w[63:32];
    assign leading_data32_w = leading_bit5_w
        ? leading_data64_w[63:32] : leading_data64_w[31:0];
    wire [15:0] leading_data16_w;
    assign leading_bit4_w = |leading_data32_w[31:16];
    assign leading_data16_w = leading_bit4_w
        ? leading_data32_w[31:16] : leading_data32_w[15:0];
    wire [7:0] leading_data8_w;
    assign leading_bit3_w = |leading_data16_w[15:8];
    assign leading_data8_w = leading_bit3_w
        ? leading_data16_w[15:8] : leading_data16_w[7:0];
    wire [3:0] leading_data4_w;
    assign leading_bit2_w = |leading_data8_w[7:4];
    assign leading_data4_w = leading_bit2_w
        ? leading_data8_w[7:4] : leading_data8_w[3:0];
    wire [1:0] unused_leading_data2_w;
    assign leading_bit1_w = |leading_data4_w[3:2];
    assign unused_leading_data2_w = leading_bit1_w
        ? leading_data4_w[3:2] : leading_data4_w[1:0];
    assign leading_bit0_w = unused_leading_data2_w[1];
    assign h_w = plane_tag_i[2:0] == 0 ? -10'sd16 :
        plane_tag_i[2:0] < 4 ? (maximum_w == 0 ? -10'sd32 :
        $signed({4'd0, leading_w}) - 10'sd31) : -10'sd8;
    assign plane_valid_o = valid_r[14];
    assign plane_tag_o = tag_w[14];
    assign plane_h_o = h_last_r;
    assign plane_normal_o = {normal_w[1], normal_w[0]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) valid_r <= 15'd0;
        else if (stop_i) valid_r <= 15'd0;
        else if (enable_i) valid_r <= {valid_r[13:0], plane_valid_i};
    end
    always @(posedge clk_i) begin
        if (enable_i) delta_r <= plane_delta_i;
    end
    assign metadata_read_13_w = metadata_write_r - 9'd12;
    assign metadata_read_9_w = metadata_write_r - 9'd8;
    assign first_w = unused_metadata_13_w[32:0];
    assign normal_h_w = unused_metadata_13_w[42:33];
    assign exponent_w = unused_metadata_9_w[5:0];
    assign offset_w = unused_metadata_9_w[41:6];
    assign recip_delay_rd_data_o = unused_metadata_9_w[47:42];
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) metadata_write_r <= 0;
        else if (enable_i) metadata_write_r <= metadata_write_r + 1'b1;
    end
    always @(posedge clk_i) begin
        if (enable_i) begin
            h_first_r <= h_w;
            h_last_r <= normal_h_w;
            offset_first_r <= plane_offset_i;
        end
    end
    edrv32_ram_gpu_delay u_metadata_13 (
        .clk_i(clk_i),
        .wr_en_i(enable_i),
        .wr_addr_i(metadata_write_r),
        .wr_data_i({29'b0, h_first_r, scaled_w[0]}),
        .rd_en_i(enable_i),
        .rd_addr_i(metadata_read_13_w),
        .rd_data_o(unused_metadata_13_w)
    );
    edrv32_ram_gpu_delay u_metadata_9 (
        .clk_i(clk_i),
        .wr_en_i(enable_i),
        .wr_addr_i(metadata_write_r),
        .wr_data_i({24'b0, recip_delay_wr_data_i, offset_first_r, plane_exponent_i}),
        .rd_en_i(enable_i),
        .rd_addr_i(metadata_read_9_w),
        .rd_data_o(unused_metadata_9_w)
    );
    genvar vertex;
    generate
        // Three independent 52-bit rounding adders and shifters before stage 0.
        for (vertex = 0; vertex < 3; vertex = vertex + 1) begin : g_scale
            wire [50:0] value_w;
            wire [51:0] unused_shifted_w;
            assign value_w = plane_value_i[vertex*51 +: 51];
            assign unused_shifted_w = h_w > 0
                ? ({1'b0, value_w} + (52'd1 << (h_w - 10'sd1))) >> h_w
                : {1'b0, value_w} << -h_w;
            assign scaled_w[vertex] = unused_shifted_w[32:0];
        end
    endgenerate
    genvar stage;
    generate
        // Metadata delay: each stage owns its scalar registers and one write per register.
        for (stage = 0; stage < 15; stage = stage + 1) begin : g_metadata
            reg [6:0] tag_r;
            assign tag_w[stage] = tag_r;
            always @(posedge clk_i) begin
                if (enable_i) begin
                    tag_r <= stage == 0 ? plane_tag_i : tag_w[stage == 0 ? 0 : stage-1];
                end
            end
            if (stage < 6) begin : g_reciprocal
                reg [30:0] value_r;
                assign reciprocal_w[stage] = value_r;
                always @(posedge clk_i) begin
                    if (enable_i) value_r <= stage == 0 ? plane_reciprocal_i
                        : reciprocal_w[stage == 0 ? 0 : stage-1];
                end
            end
        end
    endgenerate
    genvar product;
    generate
        // Four 34x18 multipliers, registered at stages 1, 2 and 3.
        for (product = 0; product < 4; product = product + 1) begin : g_product
            reg signed [51:0] product_1_r;
            reg signed [51:0] product_2_r;
            reg signed [51:0] product_3_r;
            assign product_w[product] = product_3_r;
            always @(posedge clk_i) begin
                if (enable_i) begin
                    product_1_r <= difference_w[product % 2]
                        * $signed(delta_r[product*18 +: 18]);
                    product_2_r <= product_1_r;
                    product_3_r <= product_2_r;
                end
            end
        end
    endgenerate
    genvar axis;
    generate
        // Two channels: stage 0 difference, stage 4 numerator, stages 6-8 56x31 product,
        // stage 9 rounded gradient, stages 10-12 56x18 origin product, stage 14 normal.
        for (axis = 0; axis < 2; axis = axis + 1) begin : g_axis
            reg signed [33:0] difference_r;
            reg signed [55:0] numerator_4_r;
            reg signed [55:0] numerator_5_r;
            reg signed [86:0] inverse_6_r;
            reg signed [86:0] inverse_7_r;
            reg signed [86:0] inverse_8_r;
            wire [86:0] magnitude_w;
            wire [87:0] unused_rounded_w;
            wire signed [55:0] rounded_w;
            wire [6:0] rounding_bit_w;
            wire [6:0] rounding_shift_w;
            wire [56*6-1:0] gradient_pipe_w;
            reg signed [73:0] origin_10_r;
            reg signed [73:0] origin_11_r;
            reg signed [73:0] origin_12_r;
            assign difference_w[axis] = difference_r;
            assign magnitude_w = inverse_8_r[86] ? -inverse_8_r : inverse_8_r;
            assign rounding_bit_w = 7'd29 + {1'b0, exponent_w};
            assign rounding_shift_w = 7'd30 + {1'b0, exponent_w};
            assign unused_rounded_w = ({1'b0, magnitude_w} + (88'd1 << rounding_bit_w))
                >> rounding_shift_w;
            assign rounded_w = inverse_8_r[86]
                ? -unused_rounded_w[55:0] : unused_rounded_w[55:0];
            assign origin_product_w[axis] = origin_12_r;
            assign plane_gradient_o[axis*56 +: 56] = $signed(gradient_pipe_w[280 +: 56]);
            always @(posedge clk_i) begin
                if (enable_i) begin
                    difference_r <= $signed({1'b0, scaled_w[axis+1]})
                        - $signed({1'b0, scaled_w[0]});
                    numerator_4_r <=
                        ($signed({{4{product_w[axis*2][51]}}, product_w[axis*2]})
                        + $signed({{4{product_w[axis*2+1][51]}}, product_w[axis*2+1]})) <<< 4;
                    numerator_5_r <= numerator_4_r;
                    inverse_6_r <= numerator_5_r * $signed({1'b0, reciprocal_w[5]});
                    inverse_7_r <= inverse_6_r;
                    inverse_8_r <= inverse_7_r;
                    origin_10_r <= $signed(gradient_pipe_w[0 +: 56])
                        * $signed(offset_w[axis*18 +: 18]);
                    origin_11_r <= origin_10_r;
                    origin_12_r <= origin_11_r;
                end
            end
            for (stage = 9; stage < 15; stage = stage + 1) begin : g_gradient
                reg signed [55:0] value_r;
                assign gradient_pipe_w[56*(stage-9) +: 56] = value_r;
                always @(posedge clk_i) begin
                    if (enable_i) value_r <= stage == 9 ? rounded_w
                        : $signed(gradient_pipe_w[56*((stage == 9 ? 9 : stage-1)-9) +: 56]);
                end
            end
            wire [55:0] normal_magnitude_w;
            assign normal_magnitude_w = gradient_pipe_w[279]
                ? -$signed(gradient_pipe_w[224 +: 56]) : $signed(gradient_pipe_w[224 +: 56]);
            wire [63:0] normal_leading_data64_w;
            wire [5:0] normal_leading_w;
            wire normal_leading_bit0_w;
            wire normal_leading_bit1_w;
            wire normal_leading_bit2_w;
            wire normal_leading_bit3_w;
            wire normal_leading_bit4_w;
            wire normal_leading_bit5_w;
            assign normal_leading_w = {normal_leading_bit5_w, normal_leading_bit4_w,
                normal_leading_bit3_w, normal_leading_bit2_w,
                normal_leading_bit1_w, normal_leading_bit0_w};
            assign normal_leading_data64_w = {8'd0, normal_magnitude_w};
            wire [31:0] normal_leading_data32_w;
            assign normal_leading_bit5_w = |normal_leading_data64_w[63:32];
            assign normal_leading_data32_w = normal_leading_bit5_w
                ? normal_leading_data64_w[63:32] : normal_leading_data64_w[31:0];
            wire [15:0] normal_leading_data16_w;
            assign normal_leading_bit4_w = |normal_leading_data32_w[31:16];
            assign normal_leading_data16_w = normal_leading_bit4_w
                ? normal_leading_data32_w[31:16] : normal_leading_data32_w[15:0];
            wire [7:0] normal_leading_data8_w;
            assign normal_leading_bit3_w = |normal_leading_data16_w[15:8];
            assign normal_leading_data8_w = normal_leading_bit3_w
                ? normal_leading_data16_w[15:8] : normal_leading_data16_w[7:0];
            wire [3:0] normal_leading_data4_w;
            assign normal_leading_bit2_w = |normal_leading_data8_w[7:4];
            assign normal_leading_data4_w = normal_leading_bit2_w
                ? normal_leading_data8_w[7:4] : normal_leading_data8_w[3:0];
            wire [1:0] unused_normal_leading_data2_w;
            assign normal_leading_bit1_w = |normal_leading_data4_w[3:2];
            assign unused_normal_leading_data2_w = normal_leading_bit1_w
                ? normal_leading_data4_w[3:2] : normal_leading_data4_w[1:0];
            assign normal_leading_bit0_w = unused_normal_leading_data2_w[1];
            wire signed [9:0] amount_w;
            wire [56:0] rounded_normal_w;
            wire [56:0] unused_adjusted_normal_w;
            wire signed [9:0] normal_exponent_w;
            reg [28:0] normal_r;
            assign amount_w = $signed({4'd0, normal_leading_w}) - 10'sd17;
            assign rounded_normal_w = amount_w > 0
                ? ({1'b0, normal_magnitude_w} + (57'd1 << (amount_w - 10'sd1))) >> amount_w
                : {1'b0, normal_magnitude_w} << -amount_w;
            assign unused_adjusted_normal_w = rounded_normal_w[18]
                ? rounded_normal_w >> 1 : rounded_normal_w;
            assign normal_exponent_w = normal_h_w
                - (tag_w[13][2:0] == 1 ? 10'sd30 : 10'sd38)
                + amount_w + (rounded_normal_w[18] ? 10'sd1 : 10'sd0);
            assign normal_w[axis] = normal_r;
            always @(posedge clk_i) begin
                if (enable_i) normal_r <= normal_magnitude_w == 0 ? 29'd0
                    : {normal_exponent_w, gradient_pipe_w[279], unused_adjusted_normal_w[17:0]};
            end
        end
    endgenerate
    // Stage 13: one 75-bit origin sum and rounding adder; stage 14 delays the start.
    wire signed [74:0] origin_sum_w;
    wire signed [74:0] origin_magnitude_w;
    wire signed [74:0] origin_rounded_w;
    wire signed [74:0] unused_origin_signed_w;
    reg [69:0] start_13_r;
    reg [69:0] start_14_r;
    assign origin_sum_w = {origin_product_w[0][73], origin_product_w[0]}
        + {origin_product_w[1][73], origin_product_w[1]};
    assign origin_magnitude_w = origin_sum_w[74] ? -origin_sum_w : origin_sum_w;
    assign origin_rounded_w = (origin_magnitude_w + 75'sd8) >>> 4;
    assign unused_origin_signed_w = origin_sum_w[74] ? -origin_rounded_w : origin_rounded_w;
    assign plane_start_o = start_14_r;
    always @(posedge clk_i) begin
        if (enable_i) begin
            start_13_r <= {37'd0, first_w} + unused_origin_signed_w[69:0];
            start_14_r <= start_13_r;
        end
    end
endmodule
