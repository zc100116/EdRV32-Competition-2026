// File: tb.sv
// Spec: fpu-spec 2.2, 3.1, 5.3-5.4; fpu-testplan FV08/FV11/FV15.
// Description: Bit-exact Fraction vectors plus boundary-age cancellation and backpressure.
// Clock domain: simulation clk_sys.
module tb #(parameter ISSUE_WIDTH=2,
    parameter [31:0] FPU_FORMAT = "F"
);
    localparam B = FPU_FORMAT == "FD" ? 64 : 32;
    localparam T = ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3;
    reg clk;
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    reg rst_n = 0;
    reg req_valid = 0;
    wire req_ready;
    reg [31:0] instr = 0;
    reg [T-1:0] tag = 0;
    reg [B-1:0] a = 0;
    reg [B-1:0] b = 0;
    reg [2:0] rm = 0;
    wire resp_valid;
    reg resp_ready = 0;
    wire [T-1:0] resp_tag;
    wire [B-1:0] result;
    wire [4:0] flags;
    wire int_dest;
    reg [T-1:0] head = 0;
    reg cancel = 0;
    reg [T-1:0] boundary = 0;
    edrv32_cpu2_fpu_divsqrt #(
        .ISSUE_WIDTH(ISSUE_WIDTH),
        .FPU_FORMAT(FPU_FORMAT)
    ) u_dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .unit_req_valid_i(req_valid),
        .unit_req_ready_o(req_ready),
        .unit_req_instr_i(instr),
        .unit_req_tag_i(tag),
        .unit_req_src1_i(a),
        .unit_req_src2_i(b),
        .unit_req_rm_i(rm),
        .unit_resp_valid_o(resp_valid),
        .unit_resp_ready_i(resp_ready),
        .unit_resp_tag_o(resp_tag),
        .unit_resp_data_o(result),
        .unit_resp_flags_o(flags),
        .unit_resp_int_dest_o(int_dest),
        .age_head_i(head),
        .cancel_valid_i(cancel),
        .cancel_tag_i(boundary)
    );
    task automatic tick;
        @(posedge clk);
        #1;
    endtask
    integer checked = 0;
    task automatic vectors(input string path, input bit is_double);
        integer fd;
        integer fields;
        integer latency;
        integer expected_latency;
        reg [B-1:0] next_a;
        reg [B-1:0] next_b;
        reg [B-1:0] expected;
        reg next_sqrt;
        reg [2:0] next_rm;
        reg [4:0] expected_flags;
        begin
            fd = $fopen(path, "r");
            if (fd == 0) $fatal(1, "Missing vectors %s", path);

            while (!$feof(fd)) begin
                fields = $fscanf(fd, "%h %h %h %h %h %h\n",
                    next_a, next_b, next_sqrt, next_rm, expected, expected_flags);
                if (fields != 6) $fatal(1, "Malformed reference vector %0d", checked);
                expected_latency = (is_double ? 36 : 22) + int'(next_sqrt);
                @(negedge clk);
                if (!req_ready) $fatal(1, "Idle must be ready");
                req_valid = 1;
                instr = (next_sqrt ? 32'h58000053 : 32'h18000053)
                    | (is_double ? 32'h02000000 : 0);
                a = next_a[B-1:0];
                b = next_b[B-1:0];
                rm = next_rm;
                tag = tag + 1'b1;
                head = tag - 1'b1;
                resp_ready = 0;
                tick();
                latency = 1;
                @(negedge clk);
                req_valid = 0;
                // The next unaccepted request may replace every input after the handshake.
                a = ~a;
                b = ~b;
                instr = ~instr;
                rm = 3'd4;
                while (!resp_valid && latency <= expected_latency) begin
                    if (req_ready) $fatal(1, "Busy must block request");
                    tick();
                    latency = latency + 1;
                end
                if (!resp_valid || latency != expected_latency)
                    $fatal(1, "Latency expected %0d actual %0d", expected_latency, latency);
                if (result !== expected[B-1:0] || flags !== expected_flags
                    || resp_tag !== tag || int_dest) begin
                    $display("FAIL width=%0d a=%h b=%h sqrt=%b rm=%d tag=%h time=%0t",
                        is_double ? 64 : 32, next_a, next_b, next_sqrt, next_rm, tag, $time);
                    $fatal(1, "vector=%0d expected=%h/%h actual=%h/%h", checked,
                        expected[B-1:0], expected_flags, result, flags);
                end
                // Hold completion while unrelated request inputs change.
                repeat (checked % 4) begin
                    @(negedge clk);
                    a = ~a;
                    tick();
                    if (!resp_valid || req_ready || result !== expected[B-1:0]
                        || flags !== expected_flags || resp_tag !== tag)
                        $fatal(1, "Backpressure lost completion");
                end
                @(negedge clk);
                resp_ready = 1;
                tick();
                if (resp_valid || !req_ready) $fatal(1, "Completion must release entry");
                checked = checked + 1;
            end
            $fclose(fd);
            $display("PASS %s width=%0d vectors=%0d latency=%0d prepare=3 DIV/SQRT iterate=%0d/%0d tail=6",
                FPU_FORMAT, is_double ? 64 : 32, checked, expected_latency,
                is_double ? 27 : 13, is_double ? 28 : 14);
        end
    endtask
    task automatic cancellation(input bit is_double, input bit square_root);
        integer length;
        begin
            length = (is_double ? 36 : 22) + int'(square_root);
            // Same-edge acceptance, every live phase, completion, and held result.
            for (integer phase = 0; phase <= length+2; phase = phase+1) begin
                for (integer kind = 0; kind < 3; kind = kind+1) begin
                    @(negedge clk);
                    req_valid = 1;
                    resp_ready = 0;
                    tag = T'(1);
                    head = {T{1'b1}} - 1'b1;
                    a = is_double ? B'(64'h3ff0000000000000) : B'(32'h3f800000);
                    b = a;
                    instr = (is_double ? 32'h1a000053 : 32'h18000053)
                        | (square_root ? 32'h40000000 : 0);
                    rm = 0;
                    // kind0 equality; kind1 older boundary; kind2 younger survives.
                    boundary = T'(kind == 0 ? 1 : kind == 1 ? 0 : 2);
                    cancel = phase == 0;
                    tick();
                    @(negedge clk);
                    req_valid = 0;
                    cancel = 0;
                    for (integer j = 1; j <= phase; j = j+1) begin
                        if (j == phase) cancel = 1;
                        tick();
                        @(negedge clk);
                        cancel = 0;
                    end
                    repeat (length+2) tick();
                    if (kind < 2) begin
                        if (resp_valid || !req_ready || flags != 0)
                            $fatal(1, "Cancelled tag survived phase=%0d kind=%0d", phase, kind);
                    end else begin
                        if (!resp_valid || req_ready || result !== b || flags !== 0)
                            $fatal(1, "Older tag lost phase=%0d", phase);
                        @(negedge clk);
                        resp_ready = 1;
                        tick();
                    end
                end
            end
        end
    endtask
    task automatic throughput(input bit is_double);
        integer accepted;
        integer cycles;
        integer first_cycle;
        integer expected_ii;
        begin
            accepted = 0;
            cycles = 0;
            first_cycle = 0;
            expected_ii = is_double ? 37 : 23;
            @(negedge clk);
            head = 0;
            tag = 1;
            cancel = 0;
            a = is_double ? B'(64'h3ff0000000000000) : B'(32'h3f800000);
            b = a;
            instr = is_double ? 32'h1a000053 : 32'h18000053;
            req_valid = 1;
            resp_ready = 1;
            while (accepted < 2) begin
                if (req_ready) begin
                    if (accepted == 0) first_cycle = cycles;
                    else if (cycles-first_cycle != expected_ii)
                        $fatal(1, "II expected=%0d actual=%0d", expected_ii, cycles-first_cycle);
                    accepted = accepted+1;
                end
                tick();
                cycles = cycles+1;
                @(negedge clk);
            end
            req_valid = 0;
            repeat (expected_ii+1) tick();
            if (!req_ready || resp_valid) $fatal(1, "Continuous request did not drain");
            $display("PASS width=%0d accept-to-accept II=%0d", is_double ? 64 : 32, expected_ii);
            // Reset must discard both an in-flight and a completed held operation.
            for (integer delay_cycles = 2; delay_cycles <= expected_ii; delay_cycles += expected_ii-2) begin
                @(negedge clk);
                req_valid = 1;
                resp_ready = 0;
                tick();
                @(negedge clk);
                req_valid = 0;
                repeat (delay_cycles) tick();
                @(negedge clk);
                rst_n = 0;
                #1;
                if (!req_ready || resp_valid || flags != 0) $fatal(1, "Reset did not clear owner");
                tick();
                @(negedge clk);
                rst_n = 1;
                repeat (expected_ii+1) tick();
                if (!req_ready || resp_valid) $fatal(1, "Reset produced stale completion");
            end
        end
    endtask
    string single_path;
    string double_path;
    initial begin
        if (!$value$plusargs("S=%s", single_path)) $fatal(1, "Missing S vectors");
        if (!$value$plusargs("D=%s", double_path)) $fatal(1, "Missing D vectors");
        repeat (2) tick();
        @(negedge clk);
        rst_n = 1;
        throughput(0);
        cancellation(0, 0);
        cancellation(0, 1);
        vectors(single_path, 0);
        if (FPU_FORMAT == "FD") begin
            throughput(1);
            cancellation(1, 0);
            cancellation(1, 1);
            vectors(double_path, 1);
        end
        $display("PASS FV08 %s %0d exact vectors and all cancellation phases", FPU_FORMAT, checked);
        $finish;
    end
endmodule
