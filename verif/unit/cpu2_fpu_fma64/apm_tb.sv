// File: apm_tb.sv
// Spec: fpu-spec 5.2; FV16.
// Description: Full product and every registered partial sum, including same-weight terms.
// Clock domain: simulation.
module apm_tb;
    reg clk;
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    reg enable;
    reg [52:0] a;
    reg [52:0] b;
    wire [105:0] product;
    edrv32_apm_cpu2_u53xu53 u_dut (
        .clk_i(clk),
        .enable_i({124{enable}}),
        .a_i(a),
        .b_i(b),
        .product_o(product)
    );
    reg [105:0] expected [0:13];
    reg [105:0] partial [0:11][0:13];
    reg [105:0] sum;
    reg [105:0] term;
    reg [63:0] rng = 64'hf0412345678abcde;
    integer edges = 0;
    initial begin
        enable = 0;
        a = 0;
        b = 0;
        for (integer cycle=0; cycle<20000; cycle=cycle+1) begin
            @(negedge clk);
            rng = {rng[62:0],rng[63]^rng[62]^rng[60]^rng[59]};
            enable = cycle % 31 < 25;
            a = rng[52:0];
            b = {rng[31:0],rng[63:43]};
            if (cycle % 7 == 0) begin
                a = 53'h1fffffffffffff;
                b = 53'h1fffffffffffff;
            end
            @(posedge clk);
            if (enable) begin
                for (integer q=13;q>0;q=q-1) begin
                    expected[q] = expected[q-1];
                    for (integer k=0;k<12;k=k+1) partial[k][q] = partial[k][q-1];
                end
                expected[0] = 106'(a) * 106'(b);
                sum = 0;
                term = 106'(a[23:0]) * 106'(b[15:0]);
                sum = sum + (term << 0);
                partial[0][0] = sum >> 0;
                term = 106'(a[23:0]) * 106'(b[31:16]);
                sum = sum + (term << 16);
                partial[1][0] = sum >> 16;
                term = 106'(a[47:24]) * 106'(b[15:0]);
                sum = sum + (term << 24);
                partial[2][0] = sum >> 24;
                term = 106'(a[23:0]) * 106'(b[47:32]);
                sum = sum + (term << 32);
                partial[3][0] = sum >> 32;
                term = 106'(a[47:24]) * 106'(b[31:16]);
                sum = sum + (term << 40);
                partial[4][0] = sum >> 40;
                term = 106'(a[23:0]) * 106'(b[52:48]);
                sum = sum + (term << 48);
                partial[5][0] = sum >> 48;
                term = 106'(a[52:48]) * 106'(b[15:0]);
                sum = sum + (term << 48);
                partial[6][0] = sum >> 48;
                term = 106'(a[47:24]) * 106'(b[47:32]);
                sum = sum + (term << 56);
                partial[7][0] = sum >> 56;
                term = 106'(a[52:48]) * 106'(b[31:16]);
                sum = sum + (term << 64);
                partial[8][0] = sum >> 64;
                term = 106'(a[47:24]) * 106'(b[52:48]);
                sum = sum + (term << 72);
                partial[9][0] = sum >> 72;
                term = 106'(a[52:48]) * 106'(b[47:32]);
                sum = sum + (term << 80);
                partial[10][0] = sum >> 80;
                term = 106'(a[52:48]) * 106'(b[52:48]);
                sum = sum + (term << 96);
                partial[11][0] = sum >> 96;
                edges = edges+1;
                #1;
                if (edges >= 3 && u_dut.p0_w !== partial[0][2][47:0])
                    $fatal(1,"APM stage=0 edge=%0d expected=%h actual=%h",edges,
                        partial[0][2][47:0],u_dut.p0_w);
                if (edges >= 4 && u_dut.p1_w !== partial[1][3][47:0])
                    $fatal(1,"APM stage=1 edge=%0d expected=%h actual=%h",edges,
                        partial[1][3][47:0],u_dut.p1_w);
                if (edges >= 5 && u_dut.p2_w !== partial[2][4][47:0])
                    $fatal(1,"APM stage=2 edge=%0d expected=%h actual=%h",edges,
                        partial[2][4][47:0],u_dut.p2_w);
                if (edges >= 6 && u_dut.p3_w !== partial[3][5][47:0])
                    $fatal(1,"APM stage=3 edge=%0d expected=%h actual=%h",edges,
                        partial[3][5][47:0],u_dut.p3_w);
                if (edges >= 7 && u_dut.p4_w !== partial[4][6][47:0])
                    $fatal(1,"APM stage=4 edge=%0d expected=%h actual=%h",edges,
                        partial[4][6][47:0],u_dut.p4_w);
                if (edges >= 8 && u_dut.p5_w !== partial[5][7][47:0])
                    $fatal(1,"APM stage=5 edge=%0d expected=%h actual=%h",edges,
                        partial[5][7][47:0],u_dut.p5_w);
                if (edges >= 9 && u_dut.p6_w !== partial[6][8][47:0])
                    $fatal(1,"APM stage=6 edge=%0d expected=%h actual=%h",edges,
                        partial[6][8][47:0],u_dut.p6_w);
                if (edges >= 10 && u_dut.p7_w !== partial[7][9][47:0])
                    $fatal(1,"APM stage=7 edge=%0d expected=%h actual=%h",edges,
                        partial[7][9][47:0],u_dut.p7_w);
                if (edges >= 11 && u_dut.p8_w !== partial[8][10][47:0])
                    $fatal(1,"APM stage=8 edge=%0d expected=%h actual=%h",edges,
                        partial[8][10][47:0],u_dut.p8_w);
                if (edges >= 12 && u_dut.p9_w !== partial[9][11][47:0])
                    $fatal(1,"APM stage=9 edge=%0d expected=%h actual=%h",edges,
                        partial[9][11][47:0],u_dut.p9_w);
                if (edges >= 13 && u_dut.p10_w !== partial[10][12][47:0])
                    $fatal(1,"APM stage=10 edge=%0d expected=%h actual=%h",edges,
                        partial[10][12][47:0],u_dut.p10_w);
                if (edges >= 14 && u_dut.p11_w !== partial[11][13][47:0])
                    $fatal(1,"APM stage=11 edge=%0d expected=%h actual=%h",edges,
                        partial[11][13][47:0],u_dut.p11_w);
                if (edges >= 14 && product !== expected[13])
                    $fatal(1,"Product edge=%0d expected=%h actual=%h",edges,expected[13],product);
            end
        end
        $display("PASS APM twelve partial sums and full 106-bit product edges=%0d",edges);
        $finish;
    end
endmodule
