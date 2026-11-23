// File: edrv32_gpu_pixel_lane.v
// Spec: gpu-spec 2.7, 2.11, 2.12; GPU microarchitecture 4.6.
// Description: One lane of the fixed fifteen-stage compare/stencil/blend pipeline.
// Products retain full precision through d(); saturation precedes P565 truncation.
// Clock: clk_gpu.
module edrv32_gpu_pixel_lane (
    // Clock; datapath registers have no reset.
    input wire clk_i,

    // Ordered operation input and output.
    input wire mask_i,
    input wire [39:0] old_i,
    input wire [15:0] depth_i,
    input wire [23:0] color_i,
    input wire [7:0] alpha_i,
    output wire [39:0] result_o,
    output wire passed_o,

    // Stable command snapshot, drained before any change.
    input wire [255:0] state_i
);
    wire [7:0] reference_w;
    wire [7:0] stencil_w;
    reg stencil_pass_w;
    wire depth_pass_w;
    reg [14:0] pass_r;
    reg [2:0] mask_r;
    reg [39:0] base_r [0:14];
    reg [23:0] source_r [0:5];
    reg [7:0] alpha_r [0:3];
    reg [15:0] depth_r [0:2];
    reg [2:0] operation_r [0:1];
    reg [7:0] stencil_r;
    reg [7:0] stencil_value_w;
    reg [23:0] destination_r [0:2];
    reg [23:0] factor_source_r [0:1];
    reg [23:0] factor_dest_r [0:1];
    reg [47:0] product_source_r [0:2];
    reg [47:0] product_dest_r [0:2];
    reg [50:0] rounded_source_r;
    reg [50:0] rounded_dest_r;
    reg [23:0] term_source_r;
    reg [23:0] term_dest_r;
    reg [29:0] blended_r;
    reg [23:0] saturated_r;
    reg [15:0] packed_r;
    reg [39:0] result_r;
    integer stage;
    integer channel;
    assign reference_w = state_i[83:76] & state_i[91:84];
    assign stencil_w = old_i[39:32] & state_i[91:84];
    assign depth_pass_w = state_i[32] || depth_i <= old_i[31:16];
    assign result_o = result_r;
    assign passed_o = pass_r[14];
    always @(*) begin
        stencil_pass_w = 0;
        case (state_i[66:64])
            3'd0: stencil_pass_w = 0;
            3'd1: stencil_pass_w = reference_w < stencil_w;
            3'd2: stencil_pass_w = reference_w == stencil_w;
            3'd3: stencil_pass_w = reference_w <= stencil_w;
            3'd4: stencil_pass_w = reference_w > stencil_w;
            3'd5: stencil_pass_w = reference_w != stencil_w;
            3'd6: stencil_pass_w = reference_w >= stencil_w;
            default: stencil_pass_w = 1;
        endcase
    end
    always @(*) begin
        stencil_value_w = base_r[1][39:32];
        case (operation_r[1])
            3'd1: stencil_value_w = 0;
            3'd2: stencil_value_w = state_i[83:76];
            3'd3: stencil_value_w = base_r[1][39:32] == 8'hff ?
                8'hff : base_r[1][39:32] + 1'b1;
            3'd4: stencil_value_w = base_r[1][39:32] == 0 ?
                8'b0 : base_r[1][39:32] - 1'b1;
            3'd5: stencil_value_w = ~base_r[1][39:32];
            default: stencil_value_w = base_r[1][39:32];
        endcase
    end
    function [7:0] factor;
        input [3:0] code_i;
        input [7:0] source_i;
        input [7:0] dest_i;
        input [7:0] pixel_alpha_i;
        input [7:0] constant_alpha_i;
        begin
            factor = 0;
            case (code_i)
                4'd1: factor = 255;
                4'd2: factor = pixel_alpha_i;
                4'd3: factor = 255 - pixel_alpha_i;
                4'd4: factor = source_i;
                4'd5: factor = 255 - source_i;
                4'd6: factor = dest_i;
                4'd7: factor = 255 - dest_i;
                4'd8: factor = constant_alpha_i;
                4'd9: factor = 255 - constant_alpha_i;
                default: factor = 0;
            endcase
        end
    endfunction
    wire [23:0] quotient_source_w;
    wire [23:0] quotient_dest_w;
    genvar component;
    generate
        for (component = 0; component < 3; component = component + 1) begin : g_divide
            wire [16:0] source_sum_w;
            wire [16:0] dest_sum_w;
            wire [17:0] unused_remainder_w;
            assign source_sum_w = rounded_source_r[component*17 +: 17] +
                {8'b0, rounded_source_r[component*17+8 +: 9]};
            assign dest_sum_w = rounded_dest_r[component*17 +: 17] +
                {8'b0, rounded_dest_r[component*17+8 +: 9]};
            assign quotient_source_w[component*8 +: 8] = source_sum_w[15:8];
            assign quotient_dest_w[component*8 +: 8] = dest_sum_w[15:8];
            assign unused_remainder_w = {source_sum_w[16], source_sum_w[7:0],
                dest_sum_w[16], dest_sum_w[7:0]};
        end
    endgenerate
    always @(posedge clk_i) begin
        pass_r <= {pass_r[13:0], mask_i && stencil_pass_w && depth_pass_w};
        mask_r <= {mask_r[1:0], mask_i};
        base_r[0] <= old_i;
        source_r[0] <= color_i;
        alpha_r[0] <= alpha_i;
        depth_r[0] <= depth_i;
        operation_r[0] <= !stencil_pass_w ? state_i[69:67] :
            (!depth_pass_w ? state_i[72:70] : state_i[75:73]);
        operation_r[1] <= operation_r[0];
        for (stage = 1; stage < 15; stage = stage + 1) begin
            base_r[stage] <= base_r[stage-1];
        end
        for (stage = 1; stage < 6; stage = stage + 1) begin
            source_r[stage] <= source_r[stage-1];
        end
        for (stage = 1; stage < 4; stage = stage + 1) begin
            alpha_r[stage] <= alpha_r[stage-1];
        end
        depth_r[1] <= depth_r[0];
        depth_r[2] <= depth_r[1];
        stencil_r <= stencil_value_w;
        if (mask_r[2]) begin
            base_r[3][39:32] <= (base_r[2][39:32] & ~state_i[103:96]) |
                (stencil_r & state_i[103:96]);
        end
        if (pass_r[2] && state_i[33]) begin
            base_r[3][31:16] <= depth_r[2];
        end
        destination_r[0] <= {
            base_r[2][4:0], base_r[2][4:2],
            base_r[2][10:5], base_r[2][10:9],
            base_r[2][15:11], base_r[2][15:13]};
        for (channel = 0; channel < 3; channel = channel + 1) begin
            factor_source_r[0][channel*8 +: 8] <= factor(state_i[131:128],
                source_r[3][channel*8 +: 8], destination_r[0][channel*8 +: 8],
                alpha_r[3], state_i[151:144]);
            factor_dest_r[0][channel*8 +: 8] <= factor(state_i[135:132],
                source_r[3][channel*8 +: 8], destination_r[0][channel*8 +: 8],
                alpha_r[3], state_i[151:144]);
            product_source_r[0][channel*16 +: 16] <= source_r[5][channel*8 +: 8] *
                factor_source_r[1][channel*8 +: 8];
            product_dest_r[0][channel*16 +: 16] <= destination_r[2][channel*8 +: 8] *
                factor_dest_r[1][channel*8 +: 8];
        end
        destination_r[1] <= destination_r[0];
        destination_r[2] <= destination_r[1];
        factor_source_r[1] <= factor_source_r[0];
        factor_dest_r[1] <= factor_dest_r[0];
        for (stage = 1; stage < 3; stage = stage + 1) begin
            product_source_r[stage] <= product_source_r[stage-1];
            product_dest_r[stage] <= product_dest_r[stage-1];
        end
        for (channel = 0; channel < 3; channel = channel + 1) begin
            rounded_source_r[channel*17 +: 17] <=
                {1'b0, product_source_r[2][channel*16 +: 16]} + 17'd128;
            rounded_dest_r[channel*17 +: 17] <=
                {1'b0, product_dest_r[2][channel*16 +: 16]} + 17'd128;
            term_source_r[channel*8 +: 8] <= quotient_source_w[channel*8 +: 8];
            term_dest_r[channel*8 +: 8] <= quotient_dest_w[channel*8 +: 8];
            case (state_i[138:136])
                3'd1: blended_r[channel*10 +: 10] <=
                    {2'b0, term_source_r[channel*8 +: 8]} -
                    {2'b0, term_dest_r[channel*8 +: 8]};
                3'd2: blended_r[channel*10 +: 10] <=
                    {2'b0, term_dest_r[channel*8 +: 8]} -
                    {2'b0, term_source_r[channel*8 +: 8]};
                3'd3: blended_r[channel*10 +: 10] <=
                    {2'b0, term_source_r[channel*8 +: 8] < term_dest_r[channel*8 +: 8] ?
                    term_source_r[channel*8 +: 8] : term_dest_r[channel*8 +: 8]};
                3'd4: blended_r[channel*10 +: 10] <=
                    {2'b0, term_source_r[channel*8 +: 8] > term_dest_r[channel*8 +: 8] ?
                    term_source_r[channel*8 +: 8] : term_dest_r[channel*8 +: 8]};
                default: blended_r[channel*10 +: 10] <=
                    {2'b0, term_source_r[channel*8 +: 8]} +
                    {2'b0, term_dest_r[channel*8 +: 8]};
            endcase
            saturated_r[channel*8 +: 8] <= blended_r[channel*10+9] ? 8'b0 :
                (blended_r[channel*10+8] ? 8'hff : blended_r[channel*10 +: 8]);
        end
        packed_r <= {saturated_r[7:3], saturated_r[15:10], saturated_r[23:19]};
        result_r <= base_r[13];
        if (pass_r[13] && state_i[34]) begin
            result_r[15:0] <= packed_r;
        end
    end
    wire [7:0] unused_color_w;
    assign unused_color_w = {saturated_r[18:16], saturated_r[9:8], saturated_r[2:0]};
    wire [197:0] unused_state_w;
    assign unused_state_w = {state_i[255:152], state_i[143:139], state_i[127:104],
        state_i[95:92], state_i[63:35], state_i[31:0]};
endmodule
