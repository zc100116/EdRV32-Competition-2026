// File: edrv32_apm_cpu2_u53xu53.v
// Spec: fpu-spec 5.2.
// Description: Twelve APM terms, shared operand delays, full unsigned 106-bit product.
// Clock domain: clk_sys.
module edrv32_apm_cpu2_u53xu53 (
    input wire clk_i,
    input wire [123:0] enable_i,
    input wire [52:0] a_i,
    input wire [52:0] b_i,
    output wire [105:0] product_o
);
    reg [23:0] a0_delay0_r;
    always @(posedge clk_i) begin
        if (enable_i[12]) a0_delay0_r[15:0] <= a_i[15:0];
        if (enable_i[13]) a0_delay0_r[23:16] <= a_i[23:16];
    end
    reg [23:0] a0_delay1_r;
    always @(posedge clk_i) begin
        if (enable_i[14]) a0_delay1_r[15:0] <= a0_delay0_r[15:0];
        if (enable_i[15]) a0_delay1_r[23:16] <= a0_delay0_r[23:16];
    end
    reg [23:0] a0_delay2_r;
    always @(posedge clk_i) begin
        if (enable_i[16]) a0_delay2_r[15:0] <= a0_delay1_r[15:0];
        if (enable_i[17]) a0_delay2_r[23:16] <= a0_delay1_r[23:16];
    end
    reg [23:0] a0_delay3_r;
    always @(posedge clk_i) begin
        if (enable_i[18]) a0_delay3_r[15:0] <= a0_delay2_r[15:0];
        if (enable_i[19]) a0_delay3_r[23:16] <= a0_delay2_r[23:16];
    end
    reg [23:0] a0_delay4_r;
    always @(posedge clk_i) begin
        if (enable_i[20]) a0_delay4_r[15:0] <= a0_delay3_r[15:0];
        if (enable_i[21]) a0_delay4_r[23:16] <= a0_delay3_r[23:16];
    end
    reg [23:0] a1_delay0_r;
    always @(posedge clk_i) begin
        if (enable_i[22]) a1_delay0_r[15:0] <= a_i[39:24];
        if (enable_i[23]) a1_delay0_r[23:16] <= a_i[47:40];
    end
    reg [23:0] a1_delay1_r;
    always @(posedge clk_i) begin
        if (enable_i[24]) a1_delay1_r[15:0] <= a1_delay0_r[15:0];
        if (enable_i[25]) a1_delay1_r[23:16] <= a1_delay0_r[23:16];
    end
    reg [23:0] a1_delay2_r;
    always @(posedge clk_i) begin
        if (enable_i[26]) a1_delay2_r[15:0] <= a1_delay1_r[15:0];
        if (enable_i[27]) a1_delay2_r[23:16] <= a1_delay1_r[23:16];
    end
    reg [23:0] a1_delay3_r;
    always @(posedge clk_i) begin
        if (enable_i[28]) a1_delay3_r[15:0] <= a1_delay2_r[15:0];
        if (enable_i[29]) a1_delay3_r[23:16] <= a1_delay2_r[23:16];
    end
    reg [23:0] a1_delay4_r;
    always @(posedge clk_i) begin
        if (enable_i[30]) a1_delay4_r[15:0] <= a1_delay3_r[15:0];
        if (enable_i[31]) a1_delay4_r[23:16] <= a1_delay3_r[23:16];
    end
    reg [23:0] a1_delay5_r;
    always @(posedge clk_i) begin
        if (enable_i[32]) a1_delay5_r[15:0] <= a1_delay4_r[15:0];
        if (enable_i[33]) a1_delay5_r[23:16] <= a1_delay4_r[23:16];
    end
    reg [23:0] a1_delay6_r;
    always @(posedge clk_i) begin
        if (enable_i[34]) a1_delay6_r[15:0] <= a1_delay5_r[15:0];
        if (enable_i[35]) a1_delay6_r[23:16] <= a1_delay5_r[23:16];
    end
    reg [23:0] a1_delay7_r;
    always @(posedge clk_i) begin
        if (enable_i[36]) a1_delay7_r[15:0] <= a1_delay6_r[15:0];
        if (enable_i[37]) a1_delay7_r[23:16] <= a1_delay6_r[23:16];
    end
    reg [23:0] a1_delay8_r;
    always @(posedge clk_i) begin
        if (enable_i[38]) a1_delay8_r[15:0] <= a1_delay7_r[15:0];
        if (enable_i[39]) a1_delay8_r[23:16] <= a1_delay7_r[23:16];
    end
    reg [4:0] a2_delay0_r;
    always @(posedge clk_i) begin
        if (enable_i[40]) a2_delay0_r[4:0] <= a_i[52:48];
    end
    reg [4:0] a2_delay1_r;
    always @(posedge clk_i) begin
        if (enable_i[41]) a2_delay1_r[4:0] <= a2_delay0_r[4:0];
    end
    reg [4:0] a2_delay2_r;
    always @(posedge clk_i) begin
        if (enable_i[42]) a2_delay2_r[4:0] <= a2_delay1_r[4:0];
    end
    reg [4:0] a2_delay3_r;
    always @(posedge clk_i) begin
        if (enable_i[43]) a2_delay3_r[4:0] <= a2_delay2_r[4:0];
    end
    reg [4:0] a2_delay4_r;
    always @(posedge clk_i) begin
        if (enable_i[44]) a2_delay4_r[4:0] <= a2_delay3_r[4:0];
    end
    reg [4:0] a2_delay5_r;
    always @(posedge clk_i) begin
        if (enable_i[45]) a2_delay5_r[4:0] <= a2_delay4_r[4:0];
    end
    reg [4:0] a2_delay6_r;
    always @(posedge clk_i) begin
        if (enable_i[46]) a2_delay6_r[4:0] <= a2_delay5_r[4:0];
    end
    reg [4:0] a2_delay7_r;
    always @(posedge clk_i) begin
        if (enable_i[47]) a2_delay7_r[4:0] <= a2_delay6_r[4:0];
    end
    reg [4:0] a2_delay8_r;
    always @(posedge clk_i) begin
        if (enable_i[48]) a2_delay8_r[4:0] <= a2_delay7_r[4:0];
    end
    reg [4:0] a2_delay9_r;
    always @(posedge clk_i) begin
        if (enable_i[49]) a2_delay9_r[4:0] <= a2_delay8_r[4:0];
    end
    reg [4:0] a2_delay10_r;
    always @(posedge clk_i) begin
        if (enable_i[50]) a2_delay10_r[4:0] <= a2_delay9_r[4:0];
    end
    reg [15:0] b0_delay0_r;
    always @(posedge clk_i) begin
        if (enable_i[51]) b0_delay0_r[15:0] <= b_i[15:0];
    end
    reg [15:0] b0_delay1_r;
    always @(posedge clk_i) begin
        if (enable_i[52]) b0_delay1_r[15:0] <= b0_delay0_r[15:0];
    end
    reg [15:0] b0_delay2_r;
    always @(posedge clk_i) begin
        if (enable_i[53]) b0_delay2_r[15:0] <= b0_delay1_r[15:0];
    end
    reg [15:0] b0_delay3_r;
    always @(posedge clk_i) begin
        if (enable_i[54]) b0_delay3_r[15:0] <= b0_delay2_r[15:0];
    end
    reg [15:0] b0_delay4_r;
    always @(posedge clk_i) begin
        if (enable_i[55]) b0_delay4_r[15:0] <= b0_delay3_r[15:0];
    end
    reg [15:0] b0_delay5_r;
    always @(posedge clk_i) begin
        if (enable_i[56]) b0_delay5_r[15:0] <= b0_delay4_r[15:0];
    end
    reg [15:0] b1_delay0_r;
    always @(posedge clk_i) begin
        if (enable_i[57]) b1_delay0_r[15:0] <= b_i[31:16];
    end
    reg [15:0] b1_delay1_r;
    always @(posedge clk_i) begin
        if (enable_i[58]) b1_delay1_r[15:0] <= b1_delay0_r[15:0];
    end
    reg [15:0] b1_delay2_r;
    always @(posedge clk_i) begin
        if (enable_i[59]) b1_delay2_r[15:0] <= b1_delay1_r[15:0];
    end
    reg [15:0] b1_delay3_r;
    always @(posedge clk_i) begin
        if (enable_i[60]) b1_delay3_r[15:0] <= b1_delay2_r[15:0];
    end
    reg [15:0] b1_delay4_r;
    always @(posedge clk_i) begin
        if (enable_i[61]) b1_delay4_r[15:0] <= b1_delay3_r[15:0];
    end
    reg [15:0] b1_delay5_r;
    always @(posedge clk_i) begin
        if (enable_i[62]) b1_delay5_r[15:0] <= b1_delay4_r[15:0];
    end
    reg [15:0] b1_delay6_r;
    always @(posedge clk_i) begin
        if (enable_i[63]) b1_delay6_r[15:0] <= b1_delay5_r[15:0];
    end
    reg [15:0] b1_delay7_r;
    always @(posedge clk_i) begin
        if (enable_i[64]) b1_delay7_r[15:0] <= b1_delay6_r[15:0];
    end
    reg [15:0] b2_delay0_r;
    always @(posedge clk_i) begin
        if (enable_i[65]) b2_delay0_r[15:0] <= b_i[47:32];
    end
    reg [15:0] b2_delay1_r;
    always @(posedge clk_i) begin
        if (enable_i[66]) b2_delay1_r[15:0] <= b2_delay0_r[15:0];
    end
    reg [15:0] b2_delay2_r;
    always @(posedge clk_i) begin
        if (enable_i[67]) b2_delay2_r[15:0] <= b2_delay1_r[15:0];
    end
    reg [15:0] b2_delay3_r;
    always @(posedge clk_i) begin
        if (enable_i[68]) b2_delay3_r[15:0] <= b2_delay2_r[15:0];
    end
    reg [15:0] b2_delay4_r;
    always @(posedge clk_i) begin
        if (enable_i[69]) b2_delay4_r[15:0] <= b2_delay3_r[15:0];
    end
    reg [15:0] b2_delay5_r;
    always @(posedge clk_i) begin
        if (enable_i[70]) b2_delay5_r[15:0] <= b2_delay4_r[15:0];
    end
    reg [15:0] b2_delay6_r;
    always @(posedge clk_i) begin
        if (enable_i[71]) b2_delay6_r[15:0] <= b2_delay5_r[15:0];
    end
    reg [15:0] b2_delay7_r;
    always @(posedge clk_i) begin
        if (enable_i[72]) b2_delay7_r[15:0] <= b2_delay6_r[15:0];
    end
    reg [15:0] b2_delay8_r;
    always @(posedge clk_i) begin
        if (enable_i[73]) b2_delay8_r[15:0] <= b2_delay7_r[15:0];
    end
    reg [15:0] b2_delay9_r;
    always @(posedge clk_i) begin
        if (enable_i[74]) b2_delay9_r[15:0] <= b2_delay8_r[15:0];
    end
    reg [4:0] b3_delay0_r;
    always @(posedge clk_i) begin
        if (enable_i[75]) b3_delay0_r[4:0] <= b_i[52:48];
    end
    reg [4:0] b3_delay1_r;
    always @(posedge clk_i) begin
        if (enable_i[76]) b3_delay1_r[4:0] <= b3_delay0_r[4:0];
    end
    reg [4:0] b3_delay2_r;
    always @(posedge clk_i) begin
        if (enable_i[77]) b3_delay2_r[4:0] <= b3_delay1_r[4:0];
    end
    reg [4:0] b3_delay3_r;
    always @(posedge clk_i) begin
        if (enable_i[78]) b3_delay3_r[4:0] <= b3_delay2_r[4:0];
    end
    reg [4:0] b3_delay4_r;
    always @(posedge clk_i) begin
        if (enable_i[79]) b3_delay4_r[4:0] <= b3_delay3_r[4:0];
    end
    reg [4:0] b3_delay5_r;
    always @(posedge clk_i) begin
        if (enable_i[80]) b3_delay5_r[4:0] <= b3_delay4_r[4:0];
    end
    reg [4:0] b3_delay6_r;
    always @(posedge clk_i) begin
        if (enable_i[81]) b3_delay6_r[4:0] <= b3_delay5_r[4:0];
    end
    reg [4:0] b3_delay7_r;
    always @(posedge clk_i) begin
        if (enable_i[82]) b3_delay7_r[4:0] <= b3_delay6_r[4:0];
    end
    reg [4:0] b3_delay8_r;
    always @(posedge clk_i) begin
        if (enable_i[83]) b3_delay8_r[4:0] <= b3_delay7_r[4:0];
    end
    reg [4:0] b3_delay9_r;
    always @(posedge clk_i) begin
        if (enable_i[84]) b3_delay9_r[4:0] <= b3_delay8_r[4:0];
    end
    reg [4:0] b3_delay10_r;
    always @(posedge clk_i) begin
        if (enable_i[85]) b3_delay10_r[4:0] <= b3_delay9_r[4:0];
    end
    wire [47:0] p0_w;
    wire [47:0] cpo0_w;
    edrv32_apm_cpu2_head u_term0 (
        .clk_i(clk_i),
        .enable_i(enable_i[0]),
        .x_i({1'b0, a_i[23:0]}),
        .y_i({2'b0, b_i[15:0]}),
        .unused_cpi_i(48'b0),
        .cpo_o(cpo0_w),
        .p_o(p0_w)
    );
    wire [47:0] p1_w;
    wire [47:0] cpo1_w;
    edrv32_apm_cpu2_shift16 u_term1 (
        .clk_i(clk_i),
        .enable_i(enable_i[1]),
        .x_i({1'b0, a0_delay0_r}),
        .y_i({2'b0, b1_delay0_r}),
        .cpi_i(cpo0_w),
        .cpo_o(cpo1_w),
        .p_o(p1_w)
    );
    reg [15:0] residue1_r;
    wire [15:0] residue1_next_w;
    assign residue1_next_w = p0_w[15:0];
    always @(posedge clk_i) begin
        if (enable_i[86]) residue1_r[15:0] <= residue1_next_w[15:0];
    end
    wire [47:0] p2_w;
    wire [47:0] cpo2_w;
    edrv32_apm_cpu2_shift8 u_term2 (
        .clk_i(clk_i),
        .enable_i(enable_i[2]),
        .x_i({1'b0, a1_delay1_r}),
        .y_i({2'b0, b0_delay1_r}),
        .cpi_i(cpo1_w),
        .cpo_o(cpo2_w),
        .p_o(p2_w)
    );
    reg [23:0] residue2_r;
    wire [23:0] residue2_next_w;
    assign residue2_next_w = {p1_w[7:0], residue1_r};
    always @(posedge clk_i) begin
        if (enable_i[87]) residue2_r[15:0] <= residue2_next_w[15:0];
        if (enable_i[88]) residue2_r[23:16] <= residue2_next_w[23:16];
    end
    wire [47:0] p3_w;
    wire [47:0] cpo3_w;
    edrv32_apm_cpu2_shift8 u_term3 (
        .clk_i(clk_i),
        .enable_i(enable_i[3]),
        .x_i({1'b0, a0_delay2_r}),
        .y_i({2'b0, b2_delay2_r}),
        .cpi_i(cpo2_w),
        .cpo_o(cpo3_w),
        .p_o(p3_w)
    );
    reg [31:0] residue3_r;
    wire [31:0] residue3_next_w;
    assign residue3_next_w = {p2_w[7:0], residue2_r};
    always @(posedge clk_i) begin
        if (enable_i[89]) residue3_r[15:0] <= residue3_next_w[15:0];
        if (enable_i[90]) residue3_r[31:16] <= residue3_next_w[31:16];
    end
    wire [47:0] p4_w;
    wire [47:0] cpo4_w;
    edrv32_apm_cpu2_shift8 u_term4 (
        .clk_i(clk_i),
        .enable_i(enable_i[4]),
        .x_i({1'b0, a1_delay3_r}),
        .y_i({2'b0, b1_delay3_r}),
        .cpi_i(cpo3_w),
        .cpo_o(cpo4_w),
        .p_o(p4_w)
    );
    reg [39:0] residue4_r;
    wire [39:0] residue4_next_w;
    assign residue4_next_w = {p3_w[7:0], residue3_r};
    always @(posedge clk_i) begin
        if (enable_i[91]) residue4_r[15:0] <= residue4_next_w[15:0];
        if (enable_i[92]) residue4_r[31:16] <= residue4_next_w[31:16];
        if (enable_i[93]) residue4_r[39:32] <= residue4_next_w[39:32];
    end
    wire [47:0] p5_w;
    wire [47:0] cpo5_w;
    edrv32_apm_cpu2_shift8 u_term5 (
        .clk_i(clk_i),
        .enable_i(enable_i[5]),
        .x_i({1'b0, a0_delay4_r}),
        .y_i({13'b0, b3_delay4_r}),
        .cpi_i(cpo4_w),
        .cpo_o(cpo5_w),
        .p_o(p5_w)
    );
    reg [47:0] residue5_r;
    wire [47:0] residue5_next_w;
    assign residue5_next_w = {p4_w[7:0], residue4_r};
    always @(posedge clk_i) begin
        if (enable_i[94]) residue5_r[15:0] <= residue5_next_w[15:0];
        if (enable_i[95]) residue5_r[31:16] <= residue5_next_w[31:16];
        if (enable_i[96]) residue5_r[47:32] <= residue5_next_w[47:32];
    end
    wire [47:0] p6_w;
    wire [47:0] cpo6_w;
    edrv32_apm_cpu2_direct u_term6 (
        .clk_i(clk_i),
        .enable_i(enable_i[6]),
        .x_i({20'b0, a2_delay5_r}),
        .y_i({2'b0, b0_delay5_r}),
        .cpi_i(cpo5_w),
        .cpo_o(cpo6_w),
        .p_o(p6_w)
    );
    reg [47:0] residue6_r;
    wire [47:0] residue6_next_w;
    assign residue6_next_w = residue5_r;
    always @(posedge clk_i) begin
        if (enable_i[97]) residue6_r[15:0] <= residue6_next_w[15:0];
        if (enable_i[98]) residue6_r[31:16] <= residue6_next_w[31:16];
        if (enable_i[99]) residue6_r[47:32] <= residue6_next_w[47:32];
    end
    wire [47:0] p7_w;
    wire [47:0] cpo7_w;
    edrv32_apm_cpu2_shift8 u_term7 (
        .clk_i(clk_i),
        .enable_i(enable_i[7]),
        .x_i({1'b0, a1_delay6_r}),
        .y_i({2'b0, b2_delay6_r}),
        .cpi_i(cpo6_w),
        .cpo_o(cpo7_w),
        .p_o(p7_w)
    );
    reg [55:0] residue7_r;
    wire [55:0] residue7_next_w;
    assign residue7_next_w = {p6_w[7:0], residue6_r};
    always @(posedge clk_i) begin
        if (enable_i[100]) residue7_r[15:0] <= residue7_next_w[15:0];
        if (enable_i[101]) residue7_r[31:16] <= residue7_next_w[31:16];
        if (enable_i[102]) residue7_r[47:32] <= residue7_next_w[47:32];
        if (enable_i[103]) residue7_r[55:48] <= residue7_next_w[55:48];
    end
    wire [47:0] p8_w;
    wire [47:0] cpo8_w;
    edrv32_apm_cpu2_shift8 u_term8 (
        .clk_i(clk_i),
        .enable_i(enable_i[8]),
        .x_i({20'b0, a2_delay7_r}),
        .y_i({2'b0, b1_delay7_r}),
        .cpi_i(cpo7_w),
        .cpo_o(cpo8_w),
        .p_o(p8_w)
    );
    reg [63:0] residue8_r;
    wire [63:0] residue8_next_w;
    assign residue8_next_w = {p7_w[7:0], residue7_r};
    always @(posedge clk_i) begin
        if (enable_i[104]) residue8_r[15:0] <= residue8_next_w[15:0];
        if (enable_i[105]) residue8_r[31:16] <= residue8_next_w[31:16];
        if (enable_i[106]) residue8_r[47:32] <= residue8_next_w[47:32];
        if (enable_i[107]) residue8_r[63:48] <= residue8_next_w[63:48];
    end
    wire [47:0] p9_w;
    wire [47:0] cpo9_w;
    edrv32_apm_cpu2_shift8 u_term9 (
        .clk_i(clk_i),
        .enable_i(enable_i[9]),
        .x_i({1'b0, a1_delay8_r}),
        .y_i({13'b0, b3_delay8_r}),
        .cpi_i(cpo8_w),
        .cpo_o(cpo9_w),
        .p_o(p9_w)
    );
    reg [71:0] residue9_r;
    wire [71:0] residue9_next_w;
    assign residue9_next_w = {p8_w[7:0], residue8_r};
    always @(posedge clk_i) begin
        if (enable_i[108]) residue9_r[15:0] <= residue9_next_w[15:0];
        if (enable_i[109]) residue9_r[31:16] <= residue9_next_w[31:16];
        if (enable_i[110]) residue9_r[47:32] <= residue9_next_w[47:32];
        if (enable_i[111]) residue9_r[63:48] <= residue9_next_w[63:48];
        if (enable_i[112]) residue9_r[71:64] <= residue9_next_w[71:64];
    end
    wire [47:0] p10_w;
    wire [47:0] cpo10_w;
    edrv32_apm_cpu2_shift8 u_term10 (
        .clk_i(clk_i),
        .enable_i(enable_i[10]),
        .x_i({20'b0, a2_delay9_r}),
        .y_i({2'b0, b2_delay9_r}),
        .cpi_i(cpo9_w),
        .cpo_o(cpo10_w),
        .p_o(p10_w)
    );
    reg [79:0] residue10_r;
    wire [79:0] residue10_next_w;
    assign residue10_next_w = {p9_w[7:0], residue9_r};
    always @(posedge clk_i) begin
        if (enable_i[113]) residue10_r[15:0] <= residue10_next_w[15:0];
        if (enable_i[114]) residue10_r[31:16] <= residue10_next_w[31:16];
        if (enable_i[115]) residue10_r[47:32] <= residue10_next_w[47:32];
        if (enable_i[116]) residue10_r[63:48] <= residue10_next_w[63:48];
        if (enable_i[117]) residue10_r[79:64] <= residue10_next_w[79:64];
    end
    wire [47:0] p11_w;
    wire [47:0] cpo11_w;
    edrv32_apm_cpu2_shift16 u_term11 (
        .clk_i(clk_i),
        .enable_i(enable_i[11]),
        .x_i({20'b0, a2_delay10_r}),
        .y_i({13'b0, b3_delay10_r}),
        .cpi_i(cpo10_w),
        .cpo_o(cpo11_w),
        .p_o(p11_w)
    );
    reg [95:0] residue11_r;
    wire [95:0] residue11_next_w;
    assign residue11_next_w = {p10_w[15:0], residue10_r};
    always @(posedge clk_i) begin
        if (enable_i[118]) residue11_r[15:0] <= residue11_next_w[15:0];
        if (enable_i[119]) residue11_r[31:16] <= residue11_next_w[31:16];
        if (enable_i[120]) residue11_r[47:32] <= residue11_next_w[47:32];
        if (enable_i[121]) residue11_r[63:48] <= residue11_next_w[63:48];
        if (enable_i[122]) residue11_r[79:64] <= residue11_next_w[79:64];
        if (enable_i[123]) residue11_r[95:80] <= residue11_next_w[95:80];
    end
    assign product_o = {p11_w[9:0],residue11_r};
    wire unused_w;
    assign unused_w = ^{p0_w[47:16], p1_w[47:8], p2_w[47:8], p3_w[47:8], p4_w[47:8], p5_w,
        p6_w[47:8], p7_w[47:8], p8_w[47:8], p9_w[47:8], p10_w[47:16], p11_w[47:10],cpo11_w};
endmodule
