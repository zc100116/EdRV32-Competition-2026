// File: tb.sv
// Spec: fpu-spec 2.2, 5.2, 5.3; fpu-testplan FV06.
// Description: Streaming II=1 scoreboarding with an exact Fraction reference file.
// Clock domain: simulation clk_sys.
module tb;
    reg clk;
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    reg [31:0] a;
    reg [31:0] b;
    reg [31:0] c;
    reg [1:0] op;
    reg [2:0] rm;
    wire [31:0] result;
    wire [4:0] flags;
    edrv32_cpu2_fpu_fma32 u_dut (
        .clk_i(clk),
        .a_i(a),
        .b_i(b),
        .c_i(c),
        .op_i(op),
        .rm_i(rm),
        .result_o(result),
        .flags_o(flags)
    );
    reg [31:0] expected [0:7];
    reg [4:0] expected_flags [0:7];
    reg [31:0] source_a [0:7];
    reg [31:0] source_b [0:7];
    reg [31:0] source_c [0:7];
    reg [1:0] source_op [0:7];
    reg [2:0] source_rm [0:7];
    reg valid [0:7];
    string vector_path;
    integer fd;
    integer fields;
    integer total = 0;
    integer checked = 0;
    reg [31:0] next_expected;
    reg [4:0] next_flags;
    initial begin
        if (!$value$plusargs("VECTORS=%s", vector_path)) $fatal(1, "Missing VECTORS");
        fd = $fopen(vector_path, "r");
        if (fd == 0) $fatal(1, "Cannot open reference vectors");
        for (integer j = 0; j < 8; j = j + 1) valid[j] = 0;
        while (!$feof(fd) || (checked < total)) begin
            @(negedge clk);
            for (integer j = 7; j > 0; j = j - 1) begin
                expected[j] = expected[j-1];
                expected_flags[j] = expected_flags[j-1];
                source_a[j] = source_a[j-1];
                source_b[j] = source_b[j-1];
                source_c[j] = source_c[j-1];
                source_op[j] = source_op[j-1];
                source_rm[j] = source_rm[j-1];
                valid[j] = valid[j-1];
            end
            fields = $fscanf(fd, "%h %h %h %h %h %h %h\n",
                a, b, c, op, rm, next_expected, next_flags);
            valid[0] = fields == 7;
            if (valid[0]) begin
                total = total + 1;
                expected[0] = next_expected;
                expected_flags[0] = next_flags;
                source_a[0] = a;
                source_b[0] = b;
                source_c[0] = c;
                source_op[0] = op;
                source_rm[0] = rm;
            end else if (fields != -1 && fields != 0) $fatal(1, "Malformed vector");
            @(posedge clk);
            #1;
            if (valid[7]) begin
                if (result !== expected[7] || flags !== expected_flags[7]) begin
                    $display("FAIL a=%08h b=%08h c=%08h op=%h rm=%h time=%0t",
                        source_a[7], source_b[7], source_c[7], source_op[7], source_rm[7], $time);
                    $fatal(1, "expected=%08h flags=%02h actual=%08h flags=%02h vector=%0d",
                        expected[7], expected_flags[7], result, flags, checked);
                end
                checked = checked + 1;
            end
        end
        $fclose(fd);
        $display("PASS FP32 FMA: %0d vectors, 8 stages, II=1", checked);
        $finish;
    end
endmodule
