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
    reg [14:0] valid_r;
    reg [6:0] tag_r [0:14];
    reg signed [9:0] h_r [0:14];
    reg [32:0] first_r [0:12];
    reg [30:0] reciprocal_r [0:5];
    reg [5:0] exponent_r [0:8];
    reg [35:0] offset_r [0:9];
    reg signed [33:0] difference_r [0:1];
    reg [71:0] delta_r;
    reg signed [51:0] product_r [0:3][1:3];
    reg signed [55:0] numerator_r [0:1][4:5];
    reg signed [86:0] inverse_product_r [0:1][6:8];
    reg signed [55:0] gradient_r [0:1][9:14];
    reg signed [73:0] origin_product_r [0:1][10:12];
    reg signed [69:0] start_r [13:14];
    reg [57:0] normal_r;
    reg [50:0] maximum_w;
    reg signed [9:0] h_w;
    reg [32:0] scaled_w [0:2];
    reg signed [74:0] origin_sum_w;
    reg signed [74:0] origin_magnitude_w;
    reg signed [74:0] origin_rounded_w;
    wire signed [55:0] rounded_gradient_w [0:1];
    wire [57:0] normal_w;
    integer index_w;
    integer stage_r;
    integer axis_r;

    function [32:0] scale_value;
        input [50:0] value_i;
        input signed [9:0] amount_i;
        reg [51:0] unused_shifted;
        begin
            if (amount_i > 0) begin
                unused_shifted = ({1'b0, value_i} + (52'd1 << (amount_i - 1))) >> amount_i;
            end else begin
                unused_shifted = {1'b0, value_i} << -amount_i;
            end
            scale_value = unused_shifted[32:0];
        end
    endfunction

    function signed [55:0] round_gradient;
        input signed [86:0] value_i;
        input [5:0] exponent_i;
        reg [86:0] magnitude;
        reg [87:0] unused_rounded;
        begin
            magnitude = value_i[86] ? -value_i : value_i;
            unused_rounded = ({1'b0, magnitude} + (88'd1 << (29 + exponent_i)))
                >> (30 + exponent_i);
            round_gradient = value_i[86] ? -unused_rounded[55:0] : unused_rounded[55:0];
        end
    endfunction

    function [28:0] normal_gradient;
        input signed [55:0] value_i;
        input signed [9:0] exponent_i;
        reg [55:0] magnitude;
        reg [56:0] rounded;
        reg signed [9:0] result_exponent;
        reg [17:0] mantissa;
        integer leading;
        integer amount;
        integer bit_index;
        begin
            magnitude = value_i[55] ? -value_i : value_i;
            leading = 0;
            for (bit_index = 0; bit_index < 56; bit_index = bit_index + 1) begin
                if (magnitude[bit_index]) begin
                    leading = bit_index;
                end
            end
            amount = leading - 17;
            if (amount > 0) begin
                rounded = ({1'b0, magnitude} + (57'd1 << (amount - 1))) >> amount;
            end else begin
                rounded = {1'b0, magnitude} << -amount;
            end
            if (rounded[18]) begin
                rounded = rounded >> 1;
                amount = amount + 1;
            end
            mantissa = rounded[17:0];
            result_exponent = exponent_i + amount[9:0];
            normal_gradient = magnitude == 0 ? 29'd0
                : {result_exponent, value_i[55], mantissa};
        end
    endfunction

    assign plane_valid_o = valid_r[14];
    assign plane_tag_o = tag_r[14];
    assign plane_start_o = start_r[14];
    assign plane_gradient_o = {gradient_r[1][14], gradient_r[0][14]};
    assign plane_h_o = h_r[14];
    assign plane_normal_o = normal_r;

    assign rounded_gradient_w[0] = round_gradient(inverse_product_r[0][8], exponent_r[8]);
    assign rounded_gradient_w[1] = round_gradient(inverse_product_r[1][8], exponent_r[8]);
    assign normal_w = {
        normal_gradient(gradient_r[1][13], h_r[13]
            - (tag_r[13][2:0] == 1 ? 10'sd30 : 10'sd38)),
        normal_gradient(gradient_r[0][13], h_r[13]
            - (tag_r[13][2:0] == 1 ? 10'sd30 : 10'sd38))};

    always @(*) begin
        maximum_w = plane_value_i[50:0];
        h_w = -10'sd8;
        for (index_w = 1; index_w < 3; index_w = index_w + 1) begin
            if (plane_value_i[index_w * 51 +: 51] > maximum_w) begin
                maximum_w = plane_value_i[index_w * 51 +: 51];
            end
        end
        if (plane_tag_i[2:0] == 0) begin
            h_w = -10'sd16;
        end else if (plane_tag_i[2:0] < 4) begin
            h_w = -10'sd32;
            for (index_w = 0; index_w < 51; index_w = index_w + 1) begin
                if (maximum_w[index_w]) begin
                    h_w = index_w[9:0] - 10'sd31;
                end
            end
        end
        for (index_w = 0; index_w < 3; index_w = index_w + 1) begin
            scaled_w[index_w] = scale_value(plane_value_i[index_w * 51 +: 51], h_w);
        end
        origin_sum_w = {origin_product_r[0][12][73], origin_product_r[0][12]}
            + {origin_product_r[1][12][73], origin_product_r[1][12]};
        origin_magnitude_w = origin_sum_w[74] ? -origin_sum_w : origin_sum_w;
        origin_rounded_w = (origin_magnitude_w + 75'sd8) >>> 4;
        if (origin_sum_w[74]) begin
            origin_rounded_w = -origin_rounded_w;
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            valid_r <= 15'd0;
        end else if (stop_i) begin
            valid_r <= 15'd0;
        end else if (enable_i) begin
            valid_r <= {valid_r[13:0], plane_valid_i};
        end
    end

    always @(posedge clk_i) begin
        if (enable_i) begin
            tag_r[0] <= plane_tag_i;
            h_r[0] <= h_w;
            first_r[0] <= scaled_w[0];
            reciprocal_r[0] <= plane_reciprocal_i;
            exponent_r[0] <= plane_exponent_i;
            offset_r[0] <= plane_offset_i;
            delta_r <= plane_delta_i;
            difference_r[0] <= $signed({1'b0, scaled_w[1]})
                - $signed({1'b0, scaled_w[0]});
            difference_r[1] <= $signed({1'b0, scaled_w[2]})
                - $signed({1'b0, scaled_w[0]});
            for (stage_r = 1; stage_r < 15; stage_r = stage_r + 1) begin
                tag_r[stage_r] <= tag_r[stage_r - 1];
                h_r[stage_r] <= h_r[stage_r - 1];
            end
            for (stage_r = 1; stage_r < 13; stage_r = stage_r + 1) begin
                first_r[stage_r] <= first_r[stage_r - 1];
            end
            for (stage_r = 1; stage_r < 6; stage_r = stage_r + 1) begin
                reciprocal_r[stage_r] <= reciprocal_r[stage_r - 1];
            end
            for (stage_r = 1; stage_r < 9; stage_r = stage_r + 1) begin
                exponent_r[stage_r] <= exponent_r[stage_r - 1];
            end
            for (stage_r = 1; stage_r < 10; stage_r = stage_r + 1) begin
                offset_r[stage_r] <= offset_r[stage_r - 1];
            end
            for (axis_r = 0; axis_r < 4; axis_r = axis_r + 1) begin
                product_r[axis_r][1] <= difference_r[axis_r % 2]
                    * $signed(delta_r[axis_r * 18 +: 18]);
                product_r[axis_r][2] <= product_r[axis_r][1];
                product_r[axis_r][3] <= product_r[axis_r][2];
            end
            for (axis_r = 0; axis_r < 2; axis_r = axis_r + 1) begin
                numerator_r[axis_r][4] <=
                    ($signed({{4{product_r[axis_r * 2][3][51]}},
                        product_r[axis_r * 2][3]})
                    + $signed({{4{product_r[axis_r * 2 + 1][3][51]}},
                        product_r[axis_r * 2 + 1][3]})) <<< 4;
                numerator_r[axis_r][5] <= numerator_r[axis_r][4];
                inverse_product_r[axis_r][6] <= numerator_r[axis_r][5]
                    * $signed({1'b0, reciprocal_r[5]});
                inverse_product_r[axis_r][7] <= inverse_product_r[axis_r][6];
                inverse_product_r[axis_r][8] <= inverse_product_r[axis_r][7];
                gradient_r[axis_r][9] <=
                    rounded_gradient_w[axis_r];
                for (stage_r = 10; stage_r < 15; stage_r = stage_r + 1) begin
                    gradient_r[axis_r][stage_r] <= gradient_r[axis_r][stage_r - 1];
                end
                origin_product_r[axis_r][10] <= gradient_r[axis_r][9]
                    * $signed(offset_r[9][axis_r * 18 +: 18]);
                origin_product_r[axis_r][11] <= origin_product_r[axis_r][10];
                origin_product_r[axis_r][12] <= origin_product_r[axis_r][11];
            end
            start_r[13] <= {37'd0, first_r[12]} + origin_rounded_w[69:0];
            start_r[14] <= start_r[13];
            normal_r <= normal_w;
        end
    end
endmodule
