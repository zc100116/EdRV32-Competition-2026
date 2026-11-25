// File: edrv32_gpu_perspective_subtract.v
// Spec: gpu-spec 2.13; microarch 4.13.
// Description: Fixed-width registered arithmetic; global enable preserves pipeline alignment.
// Clock domain: clk_gpu.
module edrv32_gpu_perspective_subtract (
    // Clock and common pipeline enable.
    input wire clk_i,
    input wire en_i,

    // Arithmetic payload.
    input wire [28:0] a_i,
    input wire [28:0] b_i,
    output wire [28:0] normal_o,

    // Shared delay RAM: ten-cycle bypass storage.
    output wire [28:0] delay_bypass_wr_data_o,
    input wire [28:0] delay_bypass_rd_data_i
);
    reg [28:0] a_r;
    reg [28:0] b_r;
    reg [9:0] maximum_r;
    reg [59:0] exponent_r;
    reg [9:0] bypass_valid_r;
    wire [28:0] normalized_w;
    reg [22:0] difference_r;
    reg [22:0] absolute_r;
    reg sign_r;
    wire [22:0] signed_w [0:1];
    assign delay_bypass_wr_data_o = b_i[17:0] == 0 ? a_i :
        {b_i[28:19], !b_i[18], b_i[17:0]};
    assign normal_o = bypass_valid_r[9] ? delay_bypass_rd_data_i : normalized_w;
    edrv32_gpu_perspective_normal #(
        .WIDTH(23)
    ) u_normal (
        .clk_i(clk_i),
        .en_i(en_i),
        .magnitude_i(absolute_r),
        .sign_i(sign_r),
        .exponent_i(exponent_r[50 +: 10]),
        .normal_o(normalized_w)
    );
    genvar operand;
    generate
        // Two 22-bit aligners, rounding adders and signed converters.
        for (operand = 0; operand < 2; operand = operand + 1) begin : g_operand
            wire [28:0] value_w;
            reg [9:0] alignment_r;
            reg [21:0] magnitude_r;
            reg [21:0] aligned_r;
            wire [21:0] shift_1_w;
            wire [21:0] shift_4_w;
            reg [21:0] rounded_r;
            reg [22:0] signed_r;
            reg [2:0] negative_r;
            assign value_w = operand == 0 ? a_r : b_r;
            assign signed_w[operand] = signed_r;
            assign shift_1_w = alignment_r[1] ?
                (alignment_r[0] ? {3'b0, magnitude_r[21:3]} :
                {2'b0, magnitude_r[21:2]}) :
                (alignment_r[0] ? {1'b0, magnitude_r[21:1]} : magnitude_r);
            assign shift_4_w = alignment_r[3] ?
                (alignment_r[2] ? {12'b0, shift_1_w[21:12]} :
                {8'b0, shift_1_w[21:8]}) :
                (alignment_r[2] ? {4'b0, shift_1_w[21:4]} : shift_1_w);
            always @(posedge clk_i) begin
                if (en_i) begin
                    alignment_r <= maximum_r - value_w[28:19];
                    magnitude_r <= {value_w[17:0], 4'b0};
                    negative_r <= {negative_r[1:0], value_w[18]};
                    aligned_r <= alignment_r[9:5] != 0 ? 22'b0 :
                        alignment_r[4] ? {16'b0, shift_4_w[21:16]} : shift_4_w;
                    rounded_r <= {1'b0, aligned_r[21:1]} + {21'b0, aligned_r[0]};
                    signed_r <= ({1'b0, rounded_r} ^ {23{negative_r[2]}})
                        + {22'b0, negative_r[2]};
                end
            end
        end
    endgenerate
    always @(posedge clk_i) begin
        if (en_i) begin
            a_r <= a_i;
            b_r <= b_i;
            maximum_r <= $signed(a_i[28:19]) > $signed(b_i[28:19]) ?
                a_i[28:19] : b_i[28:19];
            bypass_valid_r <= {bypass_valid_r[8:0], a_i[17:0] == 0 || b_i[17:0] == 0};
            exponent_r <= {exponent_r[49:0], maximum_r - 10'd3};
            difference_r <= signed_w[0] - signed_w[1];
            absolute_r <= difference_r[22] ? -difference_r : difference_r;
            sign_r <= difference_r[22];
        end
    end
endmodule
