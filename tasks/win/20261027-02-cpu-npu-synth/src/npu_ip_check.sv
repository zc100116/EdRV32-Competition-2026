// File: npu_ip_check.sv
// Spec: npu-spec 5.2, 5.4; datapath design 4.5, 4.6, 4.9; fpga/ip/ip_*npu*.md.
// Description: Check the 10 NPU tech wrappers (FPGA branch with generated IP and the
// GTP_APM_E2 primitive) against the behaviour of their simulation models: RAM read
// latency, read-enable hold, old data on same-address collision, full physical depth;
// multiplier two-edge latency, signed extremes and independent SIMD lanes.
// Clock domain: clk_npu (test clock).

// RAM checker: fills every address, then random reads/writes with collisions.
module npu_ram_check #(
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
    reg [DW-1:0] arr_ref;
    reg [DW-1:0] out_ref;
    reg [DW-1:0] expected;
    integer checks = 0;
    integer seed = SEED;
    integer i;
    integer k;

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

    // Reference: enabled read captures old array data, output register follows.
    always @(posedge clk) begin
        if (LAT == 2) begin
            out_ref = arr_ref;
        end
        if (rd_en) begin
            arr_ref = mem[rd_addr];
        end
        if (wr_en) begin
            mem[wr_addr] = wr_data;
        end
        expected = (LAT == 2) ? out_ref : arr_ref;
        #1;
        if (!$isunknown(expected)) begin
            if (rd_data !== expected) begin
                $fatal(1, "FAIL ram AW=%0d DW=%0d expected=%h actual=%h time=%0t",
                    AW, DW, expected, rd_data, $time);
            end
            checks = checks + 1;
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
        $display("ram AW=%0d DW=%0d LAT=%0d checks=%0d", AW, DW, LAT, checks);
        done = 1;
    end
endmodule

// Multiplier checker: every pair of signed extremes, then random operands.
module npu_mul_check #(
    parameter AW = 8,
    parameter BW = 8,
    parameter PW = 16,
    parameter OPS = 4000,
    parameter SEED = 1,
    parameter REV = 0
) (
    input wire clk,
    output reg [AW-1:0] a,
    output reg [BW-1:0] b,
    input wire [PW-1:0] p,
    output reg done
);
    reg [PW-1:0] stage_ref;
    reg [PW-1:0] out_ref;
    reg [AW-1:0] a_edge [0:4];
    reg [BW-1:0] b_edge [0:4];
    integer checks = 0;
    integer seed = SEED;
    integer i;
    integer j;

    always @(posedge clk) begin
        out_ref = stage_ref;
        stage_ref = $signed(a) * $signed(b);
        #1;
        if (!$isunknown(out_ref)) begin
            if (p !== out_ref) begin
                $fatal(1, "FAIL mul %0dx%0d a/b path expected=%h actual=%h time=%0t",
                    AW, BW, out_ref, p, $time);
            end
            checks = checks + 1;
        end
    end

    initial begin
        a_edge[0] = {1'b1, {(AW-1){1'b0}}};
        a_edge[1] = {AW{1'b1}};
        a_edge[2] = 0;
        a_edge[3] = 1;
        a_edge[4] = {1'b0, {(AW-1){1'b1}}};
        b_edge[0] = {1'b1, {(BW-1){1'b0}}};
        b_edge[1] = {BW{1'b1}};
        b_edge[2] = 0;
        b_edge[3] = 1;
        b_edge[4] = {1'b0, {(BW-1){1'b1}}};
        done = 0;
        a = 0;
        b = 0;
        for (i = 0; i < 5; i = i + 1) begin
            for (j = 0; j < 5; j = j + 1) begin
                @(negedge clk);
                a = REV ? a_edge[4-i] : a_edge[i];
                b = REV ? b_edge[j] : b_edge[4-j];
            end
        end
        for (i = 0; i < OPS; i = i + 1) begin
            @(negedge clk);
            a = $random(seed);
            b = $random(seed);
        end
        for (i = 0; i < 3; i = i + 1) begin
            @(negedge clk);
        end
        $display("mul %0dx%0d checks=%0d", AW, BW, checks);
        done = 1;
    end
endmodule

module npu_ip_check;
    GTP_GRS GRS_INST (.GRS_N(1'b1));
    reg clk = 0;
    always #5 clk = ~clk;
    bit test_passed = 0;

    // line: 1024 x 256, read latency 2.
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
    npu_ram_check #(.AW(10), .DW(256), .LAT(2), .SEED(11)) u_chk_line (
        .clk(clk),
        .wr_en(line_wr_en),
        .wr_addr(line_wr_addr),
        .wr_data(line_wr_data),
        .rd_en(line_rd_en),
        .rd_addr(line_rd_addr),
        .rd_data(line_rd_data),
        .done(done_line)
    );

    // weight: 512 x 256, read latency 2.
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
    npu_ram_check #(.AW(9), .DW(256), .LAT(2), .SEED(12)) u_chk_weight (
        .clk(clk),
        .wr_en(weight_wr_en),
        .wr_addr(weight_wr_addr),
        .wr_data(weight_wr_data),
        .rd_en(weight_rd_en),
        .rd_addr(weight_rd_addr),
        .rd_data(weight_rd_data),
        .done(done_weight)
    );

    // quant: 512 x 64, read latency 2.
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
    npu_ram_check #(.AW(9), .DW(64), .LAT(2), .SEED(13)) u_chk_quant (
        .clk(clk),
        .wr_en(quant_wr_en),
        .wr_addr(quant_wr_addr),
        .wr_data(quant_wr_data),
        .rd_en(quant_rd_en),
        .rd_addr(quant_rd_addr),
        .rd_data(quant_rd_data),
        .done(done_quant)
    );

    // lut: 4096 x 8, read latency 2.
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
    npu_ram_check #(.AW(12), .DW(8), .LAT(2), .SEED(14)) u_chk_lut (
        .clk(clk),
        .wr_en(lut_wr_en),
        .wr_addr(lut_wr_addr),
        .wr_data(lut_wr_data),
        .rd_en(lut_rd_en),
        .rd_addr(lut_rd_addr),
        .rd_data(lut_rd_data),
        .done(done_lut)
    );

    // residual: 512 x 256, read latency 2.
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
    npu_ram_check #(.AW(9), .DW(256), .LAT(2), .SEED(15)) u_chk_residual (
        .clk(clk),
        .wr_en(residual_wr_en),
        .wr_addr(residual_wr_addr),
        .wr_data(residual_wr_data),
        .rd_en(residual_rd_en),
        .rd_addr(residual_rd_addr),
        .rd_data(residual_rd_data),
        .done(done_residual)
    );

    // result: 512 x 512, read latency 2.
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
    npu_ram_check #(.AW(9), .DW(512), .LAT(2), .SEED(16)) u_chk_result (
        .clk(clk),
        .wr_en(result_wr_en),
        .wr_addr(result_wr_addr),
        .wr_data(result_wr_data),
        .rd_en(result_rd_en),
        .rd_addr(result_rd_addr),
        .rd_data(result_rd_data),
        .done(done_result)
    );

    // scratch: 512 x 256, read latency 1.
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
    npu_ram_check #(.AW(9), .DW(256), .LAT(1), .SEED(17)) u_chk_scratch (
        .clk(clk),
        .wr_en(scratch_wr_en),
        .wr_addr(scratch_wr_addr),
        .wr_data(scratch_wr_data),
        .rd_en(scratch_rd_en),
        .rd_addr(scratch_rd_addr),
        .rd_data(scratch_rd_data),
        .done(done_scratch)
    );

    // INT8 SIMD pair: two independent lanes with different operand orders.
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

    // Quantization multiplier halves.
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
        wait (done_line && done_weight && done_quant && done_lut && done_residual &&
              done_result && done_scratch && done_pair0 && done_pair1 && done_low &&
              done_high);
        test_passed = 1;
        $display("PASS npu_ip_check");
        $finish;
    end
endmodule
