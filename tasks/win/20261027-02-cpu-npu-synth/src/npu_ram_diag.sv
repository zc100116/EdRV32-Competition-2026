// File: npu_ram_diag.sv
// Spec: task 20261027-02-cpu-npu-synth step B4 (diagnosis of the npu_ip_check failure).
// Description: Same stimulus and seeds as npu_ip_check.sv, but each RAM output is compared
// with four candidate models at once and mismatches are counted instead of stopping:
// m0 spec (read-first, output register free-running), m1 write-first on same address,
// m2 read enable also gates the output register, m3 both. Prints the first m0 mismatch
// with the last four cycles of port activity. Diagnostic only; not a pass/fail check.
// Clock domain: clk_npu (test clock).

module npu_ram_diag #(
    parameter NAME = "ram",
    parameter AW = 9,
    parameter DW = 256,
    parameter LAT = 2,
    parameter OPS = 6000,
    parameter SEED = 1
) (
    input wire clk,
    output reg wr_en,
    output reg [AW-1:0] wr_addr,
    output reg [DW-1:0] wr_data,
    output reg rd_en,
    output reg [AW-1:0] rd_addr,
    input wire [DW-1:0] rd_data,
    output reg done
);
    localparam DEPTH = 1 << AW;
    reg [DW-1:0] mem [0:DEPTH-1];
    reg [DW-1:0] arr [0:3];
    reg [DW-1:0] out [0:3];
    reg [DW-1:0] exp [0:3];
    reg [DW-1:0] rf;
    reg [DW-1:0] wf;
    integer miss [0:3];
    integer checks = 0;
    integer collisions = 0;
    integer first_m0 = -1;
    integer seed = SEED;
    integer i;
    integer k;
    integer m;
    // Port history: index 0 is the current edge.
    reg h_we [0:3];
    reg h_re [0:3];
    reg [AW-1:0] h_wa [0:3];
    reg [AW-1:0] h_ra [0:3];

    function automatic [DW-1:0] rand_data(input integer dummy);
        reg [DW+31:0] v;
        integer j;
        begin
            v = 0;
            for (j = 0; j < DW; j = j + 32) begin
                v = (v << 32) | $unsigned($random(seed));
            end
            rand_data = v[DW-1:0];
        end
    endfunction

    initial begin
        for (m = 0; m < 4; m = m + 1) begin
            miss[m] = 0;
            h_we[m] = 0;
            h_re[m] = 0;
            h_wa[m] = 0;
            h_ra[m] = 0;
        end
    end

    always @(posedge clk) begin
        for (m = 3; m > 0; m = m - 1) begin
            h_we[m] = h_we[m-1];
            h_re[m] = h_re[m-1];
            h_wa[m] = h_wa[m-1];
            h_ra[m] = h_ra[m-1];
        end
        h_we[0] = wr_en;
        h_re[0] = rd_en;
        h_wa[0] = wr_addr;
        h_ra[0] = rd_addr;
        rf = mem[rd_addr];
        wf = (wr_en && wr_addr == rd_addr) ? wr_data : rf;
        if (rd_en && wr_en && wr_addr == rd_addr) begin
            collisions = collisions + 1;
        end
        // m0/m1: output register always advances; m2/m3: gated by rd_en.
        out[0] = arr[0];
        out[1] = arr[1];
        if (rd_en) begin
            out[2] = arr[2];
            out[3] = arr[3];
            arr[0] = rf;
            arr[1] = wf;
            arr[2] = rf;
            arr[3] = wf;
        end
        if (wr_en) begin
            mem[wr_addr] = wr_data;
        end
        for (m = 0; m < 4; m = m + 1) begin
            exp[m] = (LAT == 2) ? out[m] : arr[m];
        end
        #1;
        if (!$isunknown(exp[0])) begin
            checks = checks + 1;
            for (m = 0; m < 4; m = m + 1) begin
                if (rd_data !== exp[m]) begin
                    miss[m] = miss[m] + 1;
                end
            end
            if (rd_data !== exp[0] && first_m0 < 0) begin
                first_m0 = $time;
                $display("diag %0s first m0 mismatch time=%0t expected=%h actual=%h",
                    NAME, $time, exp[0], rd_data);
                for (m = 0; m < 4; m = m + 1) begin
                    $display("diag %0s   edge-%0d we=%b wa=%0d re=%b ra=%0d", NAME, m,
                        h_we[m], h_wa[m], h_re[m], h_ra[m]);
                end
                $display("diag %0s   actual matches m1=%0d m2=%0d m3=%0d", NAME,
                    rd_data === exp[1], rd_data === exp[2], rd_data === exp[3]);
            end
        end
    end

    initial begin
        done = 0;
        wr_en = 0;
        rd_en = 0;
        wr_addr = 0;
        rd_addr = 0;
        wr_data = 0;
        for (i = 0; i < DEPTH; i = i + 1) begin
            @(negedge clk);
            wr_en = 1;
            wr_addr = i;
            wr_data = rand_data(0);
        end
        for (i = 0; i < OPS; i = i + 1) begin
            @(negedge clk);
            k = $unsigned($random(seed)) % 8;
            wr_en = ($unsigned($random(seed)) % 2) == 0;
            rd_en = ($unsigned($random(seed)) % 10) < 7;
            wr_addr = $random(seed);
            wr_data = rand_data(0);
            rd_addr = $random(seed);
            if (k < 2) begin
                rd_addr = wr_addr;
            end else if (k == 2) begin
                rd_addr = 0;
                wr_addr = DEPTH - 1;
            end else if (k == 3) begin
                rd_addr = DEPTH - 1;
            end
        end
        for (i = 0; i < 4; i = i + 1) begin
            @(negedge clk);
            wr_en = 0;
            rd_en = 0;
        end
        $display("diag %0s AW=%0d DW=%0d LAT=%0d checks=%0d collisions=%0d m0_spec=%0d m1_write_first=%0d m2_oce_gated=%0d m3_both=%0d",
            NAME, AW, DW, LAT, checks, collisions, miss[0], miss[1], miss[2], miss[3]);
        done = 1;
    end
endmodule

module npu_ram_diag_top;
    GTP_GRS GRS_INST (.GRS_N(1'b1));
    reg clk = 0;
    always #5 clk = ~clk;

    wire line_wr_en;
    wire [9:0] line_wr_addr;
    wire [255:0] line_wr_data;
    wire line_rd_en;
    wire [9:0] line_rd_addr;
    wire [255:0] line_rd_data;
    wire done_line;
    edrv32_ram_npu_line u_line (
        .clk_i(clk),
        .wr_en_i(line_wr_en),
        .wr_addr_i(line_wr_addr),
        .wr_data_i(line_wr_data),
        .rd_en_i(line_rd_en),
        .rd_addr_i(line_rd_addr),
        .rd_data_o(line_rd_data)
    );
    npu_ram_diag #(.NAME("line"), .AW(10), .DW(256), .LAT(2), .SEED(11)) u_diag_line (
        .clk(clk),
        .wr_en(line_wr_en),
        .wr_addr(line_wr_addr),
        .wr_data(line_wr_data),
        .rd_en(line_rd_en),
        .rd_addr(line_rd_addr),
        .rd_data(line_rd_data),
        .done(done_line)
    );

    wire weight_wr_en;
    wire [8:0] weight_wr_addr;
    wire [255:0] weight_wr_data;
    wire weight_rd_en;
    wire [8:0] weight_rd_addr;
    wire [255:0] weight_rd_data;
    wire done_weight;
    edrv32_ram_npu_weight u_weight (
        .clk_i(clk),
        .wr_en_i(weight_wr_en),
        .wr_addr_i(weight_wr_addr),
        .wr_data_i(weight_wr_data),
        .rd_en_i(weight_rd_en),
        .rd_addr_i(weight_rd_addr),
        .rd_data_o(weight_rd_data)
    );
    npu_ram_diag #(.NAME("weight"), .AW(9), .DW(256), .LAT(2), .SEED(12)) u_diag_weight (
        .clk(clk),
        .wr_en(weight_wr_en),
        .wr_addr(weight_wr_addr),
        .wr_data(weight_wr_data),
        .rd_en(weight_rd_en),
        .rd_addr(weight_rd_addr),
        .rd_data(weight_rd_data),
        .done(done_weight)
    );

    wire quant_wr_en;
    wire [8:0] quant_wr_addr;
    wire [63:0] quant_wr_data;
    wire quant_rd_en;
    wire [8:0] quant_rd_addr;
    wire [63:0] quant_rd_data;
    wire done_quant;
    edrv32_ram_npu_quant u_quant (
        .clk_i(clk),
        .wr_en_i(quant_wr_en),
        .wr_addr_i(quant_wr_addr),
        .wr_data_i(quant_wr_data),
        .rd_en_i(quant_rd_en),
        .rd_addr_i(quant_rd_addr),
        .rd_data_o(quant_rd_data)
    );
    npu_ram_diag #(.NAME("quant"), .AW(9), .DW(64), .LAT(2), .SEED(13)) u_diag_quant (
        .clk(clk),
        .wr_en(quant_wr_en),
        .wr_addr(quant_wr_addr),
        .wr_data(quant_wr_data),
        .rd_en(quant_rd_en),
        .rd_addr(quant_rd_addr),
        .rd_data(quant_rd_data),
        .done(done_quant)
    );

    wire lut_wr_en;
    wire [11:0] lut_wr_addr;
    wire [7:0] lut_wr_data;
    wire lut_rd_en;
    wire [11:0] lut_rd_addr;
    wire [7:0] lut_rd_data;
    wire done_lut;
    edrv32_ram_npu_lut u_lut (
        .clk_i(clk),
        .wr_en_i(lut_wr_en),
        .wr_addr_i(lut_wr_addr),
        .wr_data_i(lut_wr_data),
        .rd_en_i(lut_rd_en),
        .rd_addr_i(lut_rd_addr),
        .rd_data_o(lut_rd_data)
    );
    npu_ram_diag #(.NAME("lut"), .AW(12), .DW(8), .LAT(2), .SEED(14)) u_diag_lut (
        .clk(clk),
        .wr_en(lut_wr_en),
        .wr_addr(lut_wr_addr),
        .wr_data(lut_wr_data),
        .rd_en(lut_rd_en),
        .rd_addr(lut_rd_addr),
        .rd_data(lut_rd_data),
        .done(done_lut)
    );

    wire residual_wr_en;
    wire [8:0] residual_wr_addr;
    wire [255:0] residual_wr_data;
    wire residual_rd_en;
    wire [8:0] residual_rd_addr;
    wire [255:0] residual_rd_data;
    wire done_residual;
    edrv32_ram_npu_residual u_residual (
        .clk_i(clk),
        .wr_en_i(residual_wr_en),
        .wr_addr_i(residual_wr_addr),
        .wr_data_i(residual_wr_data),
        .rd_en_i(residual_rd_en),
        .rd_addr_i(residual_rd_addr),
        .rd_data_o(residual_rd_data)
    );
    npu_ram_diag #(.NAME("residual"), .AW(9), .DW(256), .LAT(2), .SEED(15)) u_diag_residual (
        .clk(clk),
        .wr_en(residual_wr_en),
        .wr_addr(residual_wr_addr),
        .wr_data(residual_wr_data),
        .rd_en(residual_rd_en),
        .rd_addr(residual_rd_addr),
        .rd_data(residual_rd_data),
        .done(done_residual)
    );

    wire result_wr_en;
    wire [8:0] result_wr_addr;
    wire [511:0] result_wr_data;
    wire result_rd_en;
    wire [8:0] result_rd_addr;
    wire [511:0] result_rd_data;
    wire done_result;
    edrv32_ram_npu_result u_result (
        .clk_i(clk),
        .wr_en_i(result_wr_en),
        .wr_addr_i(result_wr_addr),
        .wr_data_i(result_wr_data),
        .rd_en_i(result_rd_en),
        .rd_addr_i(result_rd_addr),
        .rd_data_o(result_rd_data)
    );
    npu_ram_diag #(.NAME("result"), .AW(9), .DW(512), .LAT(2), .SEED(16)) u_diag_result (
        .clk(clk),
        .wr_en(result_wr_en),
        .wr_addr(result_wr_addr),
        .wr_data(result_wr_data),
        .rd_en(result_rd_en),
        .rd_addr(result_rd_addr),
        .rd_data(result_rd_data),
        .done(done_result)
    );

    wire scratch_wr_en;
    wire [8:0] scratch_wr_addr;
    wire [255:0] scratch_wr_data;
    wire scratch_rd_en;
    wire [8:0] scratch_rd_addr;
    wire [255:0] scratch_rd_data;
    wire done_scratch;
    edrv32_ram_npu_scratch u_scratch (
        .clk_i(clk),
        .wr_en_i(scratch_wr_en),
        .wr_addr_i(scratch_wr_addr),
        .wr_data_i(scratch_wr_data),
        .rd_en_i(scratch_rd_en),
        .rd_addr_i(scratch_rd_addr),
        .rd_data_o(scratch_rd_data)
    );
    npu_ram_diag #(.NAME("scratch"), .AW(9), .DW(256), .LAT(1), .SEED(17)) u_diag_scratch (
        .clk(clk),
        .wr_en(scratch_wr_en),
        .wr_addr(scratch_wr_addr),
        .wr_data(scratch_wr_data),
        .rd_en(scratch_rd_en),
        .rd_addr(scratch_rd_addr),
        .rd_data(scratch_rd_data),
        .done(done_scratch)
    );

    initial begin
        wait (done_line && done_weight && done_quant && done_lut && done_residual &&
              done_result && done_scratch);
        $display("DIAG DONE");
        $finish;
    end
endmodule

// Multiplier-only top: the npu_ip_check multiplier checkers without the RAMs.
module npu_mul_only_top;
    GTP_GRS GRS_INST (.GRS_N(1'b1));
    reg clk = 0;
    always #5 clk = ~clk;
    bit test_passed = 0;
    wire [7:0] pair_a0;
    wire [7:0] pair_b0;
    wire [7:0] pair_a1;
    wire [7:0] pair_b1;
    wire [15:0] pair_p0;
    wire [15:0] pair_p1;
    wire done_pair0;
    wire done_pair1;
    edrv32_mul_npu_int8_pair u_pair (
        .clk_i(clk),
        .a0_i(pair_a0),
        .b0_i(pair_b0),
        .a1_i(pair_a1),
        .b1_i(pair_b1),
        .p0_o(pair_p0),
        .p1_o(pair_p1)
    );
    npu_mul_check #(.AW(8), .BW(8), .PW(16), .SEED(21), .REV(0)) u_chk_pair0 (
        .clk(clk),
        .a(pair_a0),
        .b(pair_b0),
        .p(pair_p0),
        .done(done_pair0)
    );
    npu_mul_check #(.AW(8), .BW(8), .PW(16), .SEED(22), .REV(1)) u_chk_pair1 (
        .clk(clk),
        .a(pair_a1),
        .b(pair_b1),
        .p(pair_p1),
        .done(done_pair1)
    );
    wire [17:0] low_a;
    wire [15:0] low_b;
    wire [33:0] low_p;
    wire done_low;
    edrv32_mul_npu_quant_low u_low (
        .clk_i(clk),
        .operand_a_i(low_a),
        .operand_b_i(low_b),
        .product_o(low_p)
    );
    npu_mul_check #(.AW(18), .BW(16), .PW(34), .SEED(23)) u_chk_low (
        .clk(clk),
        .a(low_a),
        .b(low_b),
        .p(low_p),
        .done(done_low)
    );
    wire [15:0] high_a;
    wire [15:0] high_b;
    wire [31:0] high_p;
    wire done_high;
    edrv32_mul_npu_quant_high u_high (
        .clk_i(clk),
        .operand_a_i(high_a),
        .operand_b_i(high_b),
        .product_o(high_p)
    );
    npu_mul_check #(.AW(16), .BW(16), .PW(32), .SEED(24)) u_chk_high (
        .clk(clk),
        .a(high_a),
        .b(high_b),
        .p(high_p),
        .done(done_high)
    );
    initial begin
        wait (done_pair0 && done_pair1 && done_low && done_high);
        test_passed = 1;
        $display("PASS npu_mul_only");
        $finish;
    end
endmodule
