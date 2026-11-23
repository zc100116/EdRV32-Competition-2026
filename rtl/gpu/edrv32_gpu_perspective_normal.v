// File: edrv32_gpu_perspective_normal.v
// Spec: gpu-spec 2.13; microarch 4.6, 4.10.
// Description: Fixed-width registered arithmetic; global enable preserves pipeline alignment.
// Clock domain: clk_gpu.
module edrv32_gpu_perspective_normal (
    // Clock and common pipeline enable.
    input wire clk_i,
    input wire en_i,

    // Arithmetic payload.
    input wire [69:0] magnitude_i,
    input wire sign_i,
    input wire [9:0] exponent_i,
    output wire [28:0] normal_o
);
    reg [69:0] magnitude_r [0:7];
    reg [9:0] exponent_r [0:8];
    reg sign_r [0:8];
    reg high_zero_r;
    reg [18:0] rounded_r;
    reg zero_r;
    reg [28:0] result_r;
    assign normal_o = result_r;
    always @(posedge clk_i) begin
        if (en_i) begin
            magnitude_r[0] <= magnitude_i;
            exponent_r[0] <= exponent_i + 10'd52;
            sign_r[0] <= sign_i;
            high_zero_r <= magnitude_i[69:6] == 0;
            magnitude_r[1] <= high_zero_r ? magnitude_r[0] << 64 : magnitude_r[0];
            exponent_r[1] <= high_zero_r ? exponent_r[0] - 10'd64 : exponent_r[0];
            sign_r[1] <= sign_r[0];
            magnitude_r[2] <= magnitude_r[1][69:38] == 0 ?
                magnitude_r[1] << 32 : magnitude_r[1];
            exponent_r[2] <= magnitude_r[1][69:38] == 0 ?
                exponent_r[1] - 10'd32 : exponent_r[1];
            sign_r[2] <= sign_r[1];
            magnitude_r[3] <= magnitude_r[2][69:54] == 0 ?
                magnitude_r[2] << 16 : magnitude_r[2];
            exponent_r[3] <= magnitude_r[2][69:54] == 0 ?
                exponent_r[2] - 10'd16 : exponent_r[2];
            sign_r[3] <= sign_r[2];
            magnitude_r[4] <= magnitude_r[3][69:62] == 0 ?
                magnitude_r[3] << 8 : magnitude_r[3];
            exponent_r[4] <= magnitude_r[3][69:62] == 0 ?
                exponent_r[3] - 10'd8 : exponent_r[3];
            sign_r[4] <= sign_r[3];
            magnitude_r[5] <= magnitude_r[4][69:66] == 0 ?
                magnitude_r[4] << 4 : magnitude_r[4];
            exponent_r[5] <= magnitude_r[4][69:66] == 0 ?
                exponent_r[4] - 10'd4 : exponent_r[4];
            sign_r[5] <= sign_r[4];
            magnitude_r[6] <= magnitude_r[5][69:68] == 0 ?
                magnitude_r[5] << 2 : magnitude_r[5];
            exponent_r[6] <= magnitude_r[5][69:68] == 0 ?
                exponent_r[5] - 10'd2 : exponent_r[5];
            sign_r[6] <= sign_r[5];
            magnitude_r[7] <= magnitude_r[6][69:69] == 0 ?
                magnitude_r[6] << 1 : magnitude_r[6];
            exponent_r[7] <= magnitude_r[6][69:69] == 0 ?
                exponent_r[6] - 10'd1 : exponent_r[6];
            sign_r[7] <= sign_r[6];
            rounded_r <= {1'b0, magnitude_r[7][69:52]} + {18'b0, magnitude_r[7][51]};
            exponent_r[8] <= exponent_r[7];
            sign_r[8] <= sign_r[7];
            zero_r <= magnitude_r[7][69:52] == 0;
            result_r <= zero_r ? 29'b0 : {exponent_r[8] + {9'b0, rounded_r[18]},
                sign_r[8], rounded_r[18] ? rounded_r[18:1] : rounded_r[17:0]};
        end
    end
endmodule
