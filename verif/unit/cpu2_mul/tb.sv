// File: tb.sv
// Spec: CPU v2 CV06 / C05 / C07.
// Description: Independent arithmetic scoreboard, latency, backpressure and age cancellation.
// Clock: simulated clk_sys.
module tb;
    parameter ISSUE_WIDTH = 2;
    parameter [31:0] FPU_FORMAT = "NONE";
    localparam T = FPU_FORMAT == "NONE" ? 2 : FPU_FORMAT == "F" ? 3 : 4;
    localparam B = FPU_FORMAT == "FD" ? 64 : 32;
    localparam N = 1 << T;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg req_valid = 0;
    wire req_ready;
    reg [T-1:0] req_tag = 0;
    reg [31:0] instr = 0;
    reg [31:0] src1 = 0;
    reg [31:0] src2 = 0;
    wire complete_valid;
    reg complete_ready = 1;
    wire [T-1:0] complete_tag;
    wire [B-1:0] complete_data;
    wire [4:0] flags;
    wire exception;
    wire [3:0] cause;
    wire [31:0] tval;
    reg [T-1:0] age_head = 0;
    reg cancel_valid = 0;
    reg [T-1:0] cancel_tag = 0;
    edrv32_cpu2_mul #(
        .ISSUE_WIDTH(ISSUE_WIDTH),
        .FPU_FORMAT(FPU_FORMAT)
    ) u_dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .mul_req_valid_i(req_valid),
        .mul_req_ready_o(req_ready),
        .mul_req_tag_i(req_tag),
        .mul_req_instr_i(instr),
        .mul_req_src1_i(src1),
        .mul_req_src2_i(src2),
        .mul_complete_valid_o(complete_valid),
        .mul_complete_ready_i(complete_ready),
        .mul_complete_tag_o(complete_tag),
        .mul_complete_data_o(complete_data),
        .mul_complete_flags_o(flags),
        .mul_complete_exception_o(exception),
        .mul_complete_cause_o(cause),
        .mul_complete_tval_o(tval),
        .age_head_i(age_head),
        .cancel_valid_i(cancel_valid),
        .cancel_tag_i(cancel_tag)
    );
    reg live [0:N-1];
    reg [31:0] expected [0:N-1];
    integer accepted_cycle [0:N-1];
    integer latency [0:N-1];
    integer cycle = 0;
    integer delivered = 0;
    integer accepted = 0;
    reg exact_latency = 1;
    reg held = 0;
    reg [B-1:0] held_data;
    reg [T-1:0] held_tag;
    reg [31:0] rng = 32'h7294ace1;
    function automatic [31:0] random_word;
        input [31:0] old;
        reg [31:0] x;
        begin
            x = old ^ (old << 13);
            x = x ^ (x >> 17);
            random_word = x ^ (x << 5);
        end
    endfunction
    function automatic [31:0] reference_result;
        input [31:0] a;
        input [31:0] b;
        input [2:0] op;
        reg signed [63:0] sa;
        reg signed [63:0] sb;
        reg signed [63:0] product;
        reg [63:0] unsigned_product;
        begin
            sa = {{32{a[31]}}, a};
            sb = {{32{b[31]}}, b};
            product = 0;
            unsigned_product = 0;
            reference_result = 0;
            case (op)
                0: begin
                    unsigned_product = {32'b0, a} * {32'b0, b};
                    reference_result = unsigned_product[31:0];
                end
                1: begin
                    product = sa * sb;
                    reference_result = product[63:32];
                end
                2: begin
                    product = sa * $signed({32'b0, b});
                    reference_result = product[63:32];
                end
                3: begin
                    unsigned_product = {32'b0, a} * {32'b0, b};
                    reference_result = unsigned_product[63:32];
                end
                default: $fatal(1, "bad operation");
            endcase
        end
    endfunction
    function automatic integer expected_latency;
        input [31:0] a;
        input [31:0] b;
        input [2:0] op;
        reg [31:0] aa;
        reg [31:0] bb;
        integer la;
        integer lb;
        integer k;
        begin
            expected_latency = 4;
        end
    endfunction
    integer j;
    integer distance_item;
    integer distance_cancel;
    always @(posedge clk) begin
        cycle = cycle + 1;
        if (rst_n) begin
            if (held && (!complete_valid || complete_tag != held_tag || complete_data != held_data))
                $fatal(1, "FAIL held result changed cycle=%0d", cycle);
            if (complete_valid && complete_ready) begin
                live[complete_tag] = 0;
                delivered = delivered + 1;
            end
            if (cancel_valid) begin
                distance_cancel = (int'(cancel_tag) - int'(age_head)) & (N-1);
                for (j = 0; j < N; j = j+1) begin
                    distance_item = (j - int'(age_head)) & (N-1);
                    if (distance_item >= distance_cancel) live[j] = 0;
                end
            end
            if (req_valid && req_ready) begin
                distance_item = (int'(req_tag) - int'(age_head)) & (N-1);
                distance_cancel = (int'(cancel_tag) - int'(age_head)) & (N-1);
                if (!cancel_valid || distance_item < distance_cancel) begin
                    if (live[req_tag]) $fatal(1, "FAIL duplicate tag");
                    live[req_tag] = 1;
                    expected[req_tag] = reference_result(src1, src2, instr[14:12]);
                    accepted_cycle[req_tag] = cycle;
                    latency[req_tag] = expected_latency(src1, src2, instr[14:12]);
                    accepted = accepted + 1;
                end
            end
            #1;
            if (complete_valid) begin
                if (!live[complete_tag] || complete_data != B'(expected[complete_tag]))
                    $fatal(1, "FAIL result tag=%0d expected=%h actual=%h cycle=%0d",
                        complete_tag, expected[complete_tag], complete_data, cycle);
                if (exact_latency && cycle - accepted_cycle[complete_tag] != latency[complete_tag])
                    $fatal(1, "FAIL latency expected=%0d actual=%0d cycle=%0d",
                        latency[complete_tag], cycle-accepted_cycle[complete_tag], cycle);
                if (flags != 0 || exception || cause != 0 || tval != 0)
                    $fatal(1, "FAIL nonzero completion metadata");
            end
            held = complete_valid && !complete_ready && !cancel_valid;
            held_data = complete_data;
            held_tag = complete_tag;
        end
    end
    task automatic tick;
        begin @(posedge clk); #2; @(negedge clk); end
    endtask
    task automatic drain;
        integer any_live;
        begin
            req_valid = 0;
            complete_ready = 1;
            any_live = 1;
            while (any_live != 0) begin
                tick();
                any_live = 0;
                for (integer t = 0; t < N; t=t+1) any_live = any_live | int'(live[t]);
            end
            repeat (6) tick();
        end
    endtask
    task automatic send;
        input [31:0] a;
        input [31:0] b;
        input [2:0] op;
        input [T-1:0] tag_value;
        begin
            req_valid = 1;
            src1 = a;
            src2 = b;
            instr = 32'h02000033 | (32'(op) << 12);
            req_tag = tag_value;
            while (!req_ready) tick();
            tick();
            req_valid = 0;
        end
    endtask
    integer i;
    integer op;
    integer sign_a;
    integer sign_b;
    integer k;
    integer before_accept;
    reg [31:0] a;
    reg [31:0] b;
    initial begin
        for (i = 0; i < N; i=i+1) live[i] = 0;
        repeat (3) tick();
        rst_n = 1;
        for (op = 0; op < 4; op=op+1) begin
            for (sign_a = 0; sign_a < 4; sign_a=sign_a+1) begin
                a = sign_a == 0 ? 0 : sign_a == 1 ? 1 :
                    sign_a == 2 ? 32'h80000000 : 32'hffffffff;
                for (sign_b = 0; sign_b < 4; sign_b=sign_b+1) begin
                    b = sign_b == 0 ? 0 : sign_b == 1 ? 1 :
                        sign_b == 2 ? 32'h80000000 : 32'hffffffff;
                    send(a, b, 3'(op), 0);
                    drain();
                end
            end
        end
        // Four consecutive accepted requests establish II1 even at NONE's four-tag capacity.
        for (i = 0; i < 200; i=i+1) begin
            before_accept = cycle;
            for (k = 0; k < 4; k=k+1) begin
                rng = random_word(rng); a = rng;
                rng = random_word(rng); b = rng;
                send(a, b, 3'((i+k)%4), T'(k));
            end
            if (cycle - before_accept != 4) $fatal(1, "FAIL MUL II1");
            drain();
        end
        exact_latency = 0;
        // Fill the local pipeline under backpressure, preserving older tags across wrap.
        age_head = T'(N-2);
        complete_ready = 0;
        for (k = 0; k < 4; k=k+1)
            send(32'hffff1234 + 32'(k), 32'd17, 3'(k), T'(N-2+k));
        repeat (12) tick();
        if (req_ready) $fatal(1, "FAIL multiplier failed to apply local backpressure");
        cancel_tag = 0;
        cancel_valid = 1;
        held = 0;
        tick();
        cancel_valid = 0;
        drain();
        // Hold a completed result, cancel inclusively, then reuse its tag immediately.
        complete_ready = 0;
        send(32'h87654321, 32'd7, 3'd0, T'(N-1));
        repeat (42) tick();
        if (!complete_valid) $fatal(1, "FAIL missing held completion");
        cancel_tag = T'(N-1);
        age_head = T'(N-2);
        cancel_valid = 1;
        held = 0;
        tick();
        cancel_valid = 0;
        if (complete_valid) $fatal(1, "FAIL cancelled completion returned");
        complete_ready = 1;
        send(32'hfedcba98, 32'd3, 3'd1, T'(N-1)); drain();
        // Cancel on every in-flight phase, including the normal/special completion edge.
        for (i = 0; i < 5; i=i+1) begin
            age_head = T'(N-1);
            send(32'h80000000, 32'd1, 3'd3, 0);
            repeat (i) tick();
            cancel_valid = 1;
            cancel_tag = 0;
            held = 0;
            tick();
            cancel_valid = 0;
            drain();
        end
        // Cancellation also wins on E0, before any in-flight valid exists.
        age_head = 0;
        cancel_valid = 1;
        cancel_tag = 0;
        send(32'd15, 32'd3, 3'd0, 0);
        cancel_valid = 0;
        drain();
        $display("PASS mul ISSUE_WIDTH=%0d FPU_FORMAT=%s accepted=%0d delivered=%0d",
            ISSUE_WIDTH, FPU_FORMAT, accepted, delivered);
        $finish;
    end
    initial begin
        #2000000;
        $fatal(1, "FAIL timeout");
    end
endmodule
