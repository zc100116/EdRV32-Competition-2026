// ============================================================================
// File        : edrv32_yolo_c16_residual_add.v
// Description : Saturating INT8 add for one packed C16 feature-map beat.
// Notes       : Both operands and the output use the same quantization scale
//               and zero point. The paired input and registered output can
//               transfer one 256-bit beat every clock without APMs.
// ============================================================================

module edrv32_yolo_c16_residual_add (
    input  wire         clk_i,
    input  wire         rst_n_i,

    input  wire         in_valid_i,
    output wire         in_ready_o,
    input  wire [255:0] in_a_data_i,
    input  wire [255:0] in_b_data_i,
    input  wire [7:0]   zero_point_i,

    output wire         out_valid_o,
    input  wire         out_ready_i,
    output wire [255:0] out_data_o
);

    reg out_valid_r;
    reg [255:0] out_data_r;
    wire [255:0] result_w;

    assign in_ready_o = !out_valid_r || out_ready_i;
    assign out_valid_o = out_valid_r;
    assign out_data_o = out_data_r;

    genvar lane;
    generate
        for (lane = 0; lane < 32; lane = lane + 1) begin : g_lane
            wire [7:0] a_byte_w = in_a_data_i[lane*8 +: 8];
            wire [7:0] b_byte_w = in_b_data_i[lane*8 +: 8];
            wire signed [9:0] a_ext_w = {{2{a_byte_w[7]}}, a_byte_w};
            wire signed [9:0] b_ext_w = {{2{b_byte_w[7]}}, b_byte_w};
            wire signed [9:0] zero_ext_w =
                {{2{zero_point_i[7]}}, zero_point_i};
            wire signed [9:0] sum_w = a_ext_w + b_ext_w - zero_ext_w;
            assign result_w[lane*8 +: 8] =
                sum_w > 10'sd127 ? 8'h7f :
                sum_w < -10'sd128 ? 8'h80 : sum_w[7:0];
        end
    endgenerate

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            out_valid_r <= 1'b0;
        else if (in_ready_o) begin
            out_valid_r <= in_valid_i;
            if (in_valid_i)
                out_data_r <= result_w;
        end
    end
endmodule
