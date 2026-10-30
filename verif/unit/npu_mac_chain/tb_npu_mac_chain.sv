// File: tb_npu_mac_chain.sv
// Spec: npu-testplan 3.8 EQ-01; npu-spec 5.4 C1-C8.
// Description: Four-state cycle equivalence for a single cell and eight skewed cells.
// Independent sums check both 24-bit SIMD lanes, including single-cell wraparound.
// Clock: clk_npu, 10 ns period.
module npu_chain_grs_stub;
    wire GRSNET = 1'b1;
endmodule

module tb_npu_mac_chain;
    npu_chain_grs_stub GRS_INST();
    reg clk = 0;
    always #5 clk = ~clk;
    reg [31:0] operands [0:7];
    reg [31:0] skew [0:7][0:7];
    wire [31:0] input_w [0:7];
    wire [47:0] sim_chain [0:8];
    wire [47:0] fpga_chain [0:8];
    wire [47:0] sim_single;
    wire [47:0] fpga_single;
    reg [47:0] cpi = 0;
    reg [47:0] expected_single [0:2];
    reg [47:0] expected_chain [0:9];
    reg [23:0] sum0;
    reg [23:0] sum1;
    reg [23:0] product0;
    reg [23:0] product1;
    integer seed = 32'h326ace01;
    integer cycle;
    integer checks = 0;
    assign sim_chain[0] = 0;
    assign fpga_chain[0] = 0;

    edrv32_mac_npu_int8_chain u_single_sim (
        .clk_i(clk),
        .a0_i(operands[0][7:0]),
        .b0_i(operands[0][15:8]),
        .a1_i(operands[0][23:16]),
        .b1_i(operands[0][31:24]),
        .cpi_i(cpi),
        .cpo_o(sim_single)
    );
    edrv32_mac_npu_int8_chain_fpga u_single_fpga (
        .clk_i(clk),
        .a0_i(operands[0][7:0]),
        .b0_i(operands[0][15:8]),
        .a1_i(operands[0][23:16]),
        .b1_i(operands[0][31:24]),
        .cpi_i(cpi),
        .cpo_o(fpga_single)
    );
    genvar k;
    generate
        for (k = 0; k < 8; k = k + 1) begin : g_chain
            if (k == 0) begin : g_direct
                assign input_w[k] = operands[k];
            end else begin : g_skew
                assign input_w[k] = skew[k][k-1];
            end
            edrv32_mac_npu_int8_chain u_sim (
                .clk_i(clk),
                .a0_i(input_w[k][7:0]),
                .b0_i(input_w[k][15:8]),
                .a1_i(input_w[k][23:16]),
                .b1_i(input_w[k][31:24]),
                .cpi_i(sim_chain[k]),
                .cpo_o(sim_chain[k+1])
            );
            edrv32_mac_npu_int8_chain_fpga u_fpga (
                .clk_i(clk),
                .a0_i(input_w[k][7:0]),
                .b0_i(input_w[k][15:8]),
                .a1_i(input_w[k][23:16]),
                .b1_i(input_w[k][31:24]),
                .cpi_i(fpga_chain[k]),
                .cpo_o(fpga_chain[k+1])
            );
            always @(posedge clk) begin
                skew[k][0] <= operands[k];
                for (integer j = 1; j < 7; j = j + 1)
                    skew[k][j] <= skew[k][j-1];
            end
            always @(posedge clk) begin
                #2;
                if (sim_chain[k+1] !== fpga_chain[k+1] ||
                    sim_chain[k+1] !== u_fpga.u_apm.P)
                    $fatal(1, "FAIL EQ chain stage=%0d cycle=%0d SIM=%h CPO=%h P=%h",
                        k, cycle, sim_chain[k+1], fpga_chain[k+1], u_fpga.u_apm.P);
            end
        end
    endgenerate

    initial begin
        for (cycle = 0; cycle < 1012; cycle = cycle + 1) begin
            for (integer k = 0; k < 8; k = k + 1) begin
                operands[k] = $random(seed);
                case (cycle % 20)
                    0: operands[k] = 32'h80808080;
                    1: operands[k] = 32'h7f7f7f7f;
                    2: operands[k] = 32'h807f7f80;
                    3: operands[k] = 32'h7f80807f;
                    default: begin end
                endcase
            end
            cpi = {$random(seed), 16'($random(seed))};
            if (cycle % 20 == 0) cpi = 48'h7fffff7fffff;
            if (cycle % 20 == 2) cpi = 48'h800000800000;
            sum0 = 0;
            sum1 = 0;
            for (integer k = 0; k < 8; k = k + 1) begin
                product0 = $signed(operands[k][7:0]) * $signed(operands[k][15:8]);
                product1 = $signed(operands[k][23:16]) * $signed(operands[k][31:24]);
                sum0 = sum0 + product0;
                sum1 = sum1 + product1;
            end
            @(posedge clk);
            for (integer j = 9; j > 0; j = j - 1)
                expected_chain[j] = expected_chain[j-1];
            expected_chain[0] = {sum1, sum0};
            expected_single[2] = expected_single[1];
            expected_single[1] = expected_single[0];
            expected_single[0] = {
                24'($signed(operands[0][23:16]) * $signed(operands[0][31:24])),
                24'($signed(operands[0][7:0]) * $signed(operands[0][15:8]))};
            #1;
            if (sim_single !== fpga_single || sim_single !== u_single_fpga.u_apm.P)
                $fatal(1, "FAIL EQ single cycle=%0d SIM=%h CPO=%h P=%h",
                    cycle, sim_single, fpga_single, u_single_fpga.u_apm.P);
            if (cycle >= 2 && sim_single !== {
                    24'(expected_single[2][47:24]+cpi[47:24]),
                    24'(expected_single[2][23:0]+cpi[23:0])})
                $fatal(1, "FAIL EQ single cycle=%0d SIM=%h CPO=%h P=%h product=%h CPI=%h",
                    cycle, sim_single, fpga_single, u_single_fpga.u_apm.P,
                    expected_single[2], cpi);
            if (cycle >= 9) begin
                if (sim_chain[8] !== expected_chain[9])
                    $fatal(1, "FAIL EQ dot cycle=%0d expected=%h actual=%h",
                        cycle, expected_chain[9], sim_chain[8]);
                checks = checks + 1;
            end
            @(negedge clk);
            #1;
        end
        $display("PASS EQ-01: single + eight stages, %0d dots, 24-bit wrap, seed=326ace01",
            checks);
        $finish;
    end
endmodule
