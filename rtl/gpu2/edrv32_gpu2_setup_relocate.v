// File: edrv32_gpu2_setup_relocate.v
// Spec: gpu-v2-spec 2.6.6-7; G2-02 initial 1280x720 viewport.
// Description: Exact signed60 relocation, unsigned tile offsets relative to source anchor.
//              Nine conditional shift terms plus S, nine adders in four II1 stages.
// Clock domain: clk_gpu.
module edrv32_gpu2_setup_relocate (
    // Clock and validity.
    input wire clk_i,
    input wire rst_n_i,
    input wire valid_i,

    // Common source48 integer coefficients; offsets count 64-pixel tiles.
    input wire [47:0] start_i,
    input wire [47:0] gx_i,
    input wire [47:0] gy_i,
    input wire [4:0] tile_x_i,
    input wire [3:0] tile_y_i,
    output wire valid_o,
    output wire [59:0] start_o
);
    reg [3:0] valid_r;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) valid_r <= 4'b0;
        else valid_r <= {valid_r[2:0], valid_i};
    end
    wire [59:0] terms_w [0:9];
    assign terms_w[0] = {{12{start_i[47]}}, start_i};
    assign terms_w[1] = tile_x_i[0] ?
        {{6{gx_i[47]}}, gx_i, 6'b0} : 60'b0;
    assign terms_w[2] = tile_x_i[1] ?
        {{5{gx_i[47]}}, gx_i, 7'b0} : 60'b0;
    assign terms_w[3] = tile_x_i[2] ?
        {{4{gx_i[47]}}, gx_i, 8'b0} : 60'b0;
    assign terms_w[4] = tile_x_i[3] ?
        {{3{gx_i[47]}}, gx_i, 9'b0} : 60'b0;
    assign terms_w[5] = tile_x_i[4] ?
        {{2{gx_i[47]}}, gx_i, 10'b0} : 60'b0;
    assign terms_w[6] = tile_y_i[0] ?
        {{6{gy_i[47]}}, gy_i, 6'b0} : 60'b0;
    assign terms_w[7] = tile_y_i[1] ?
        {{5{gy_i[47]}}, gy_i, 7'b0} : 60'b0;
    assign terms_w[8] = tile_y_i[2] ?
        {{4{gy_i[47]}}, gy_i, 8'b0} : 60'b0;
    assign terms_w[9] = tile_y_i[3] ?
        {{3{gy_i[47]}}, gy_i, 9'b0} : 60'b0;
    reg [59:0] s1_0_r;
    reg [59:0] s1_1_r;
    reg [59:0] s1_2_r;
    reg [59:0] s1_3_r;
    reg [59:0] s1_4_r;
    always @(posedge clk_i) begin
        s1_0_r <= terms_w[0] + terms_w[1];
        s1_1_r <= terms_w[2] + terms_w[3];
        s1_2_r <= terms_w[4] + terms_w[5];
        s1_3_r <= terms_w[6] + terms_w[7];
        s1_4_r <= terms_w[8] + terms_w[9];
    end
    reg [59:0] s2_0_r;
    reg [59:0] s2_1_r;
    reg [59:0] s2_2_r;
    always @(posedge clk_i) begin
        s2_0_r <= s1_0_r + s1_1_r;
        s2_1_r <= s1_2_r + s1_3_r;
        s2_2_r <= s1_4_r;
    end
    reg [59:0] s3_0_r;
    reg [59:0] s3_1_r;
    always @(posedge clk_i) begin
        s3_0_r <= s2_0_r + s2_1_r;
        s3_1_r <= s2_2_r;
    end
    reg [59:0] s4_0_r;
    always @(posedge clk_i) begin
        s4_0_r <= s3_0_r + s3_1_r;
    end
    assign start_o = s4_0_r;
    assign valid_o = valid_r[3];
endmodule
