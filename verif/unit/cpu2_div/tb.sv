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
    edrv32_cpu2_div #(
        .ISSUE_WIDTH(ISSUE_WIDTH),
        .FPU_FORMAT(FPU_FORMAT)
    ) u_dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .div_req_valid_i(req_valid),
        .div_req_ready_o(req_ready),
        .div_req_tag_i(req_tag),
        .div_req_instr_i(instr),
        .div_req_src1_i(src1),
        .div_req_src2_i(src2),
        .div_complete_valid_o(complete_valid),
        .div_complete_ready_i(complete_ready),
        .div_complete_tag_o(complete_tag),
        .div_complete_data_o(complete_data),
        .div_complete_flags_o(flags),
        .div_complete_exception_o(exception),
        .div_complete_cause_o(cause),
        .div_complete_tval_o(tval),
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
                4: reference_result = b == 0 ? 32'hffffffff : 32'(sa / sb);
                5: reference_result = b == 0 ? 32'hffffffff : a / b;
                6: reference_result = b == 0 ? a : 32'(sa % sb);
                7: reference_result = b == 0 ? a : a % b;
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
            aa = !op[0] && a[31] ? -a : a;
            bb = !op[0] && b[31] ? -b : b;
            la = 0;
            lb = 0;
            while (aa != 0) begin la = la + 1; aa = aa >> 1; end
            while (bb != 0) begin lb = lb + 1; bb = bb >> 1; end
            k = la >= lb ? la - lb + 1 : 0;
            expected_latency = 3 + (ISSUE_WIDTH == 1 ? k : (k+1)/2);
            if (b == 0 || (!op[0] && a == 32'h80000000 && b == 32'hffffffff))
                expected_latency = 2;
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
        for (op = 4; op < 8; op=op+1) begin
            for (sign_a = 0; sign_a < 2; sign_a=sign_a+1) begin
                for (sign_b = 0; sign_b < 2; sign_b=sign_b+1) begin
                    for (k = 0; k <= 32; k=k+1) begin
                        a = k == 0 ? 0 : 32'h80000000 >> (32-k);
                        b = 1;
                        if (sign_a != 0) a = -a;
                        if (sign_b != 0) b = -b;
                        send(a, b, 3'(op), 0);
                        drain();
                    end
                    send(32'h80000000, 32'hffffffff, 3'(op), 0); drain();
                    send(32'hffffffff, 0, 3'(op), 0); drain();
                    send(0, 0, 3'(op), 0); drain();
                    send(1, 32'h80000000, 3'(op), 0); drain();
                end
            end
        end
        for (i = 0; i < 1600; i=i+1) begin
            rng = random_word(rng); a = rng;
            rng = random_word(rng); b = rng >> (i%32);
            send(a, b, 3'(4+i%4), T'(i));
            drain();
        end
        // A new E0 overlaps the old E(3+n), so II equals the full latency.
        send(32'hffffffff, 32'd1, 3'd5, 0);
        before_accept = accepted_cycle[0];
        send(32'd123, 32'd7, 3'd5, 1);
        if (accepted_cycle[1] - before_accept != (ISSUE_WIDTH == 1 ? 35 : 19))
            $fatal(1, "FAIL DIV initiation interval");
        drain();
        exact_latency = 0;
        // A blocked old result is retained while a younger special result waits locally.
        complete_ready = 0;
        age_head = T'(N-1);
        send(32'd99, 32'd7, 3'd4, T'(N-1));
        repeat (40) tick();
        send(32'd7, 0, 3'd7, 0);
        repeat (4) tick();
        cancel_tag = 0;
        cancel_valid = 1;
        held = 0;
        tick();
        cancel_valid = 0;
        drain();
        // Hold a completed result, cancel inclusively, then reuse its tag immediately.
        complete_ready = 0;
        send(32'h87654321, 32'd7, 3'd4, T'(N-1));
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
        send(32'hfedcba98, 32'd3, 3'd6, T'(N-1)); drain();
        // Cancel on every in-flight phase, including the normal/special completion edge.
        for (i = 0; i < 37; i=i+1) begin
            age_head = T'(N-1);
            send(32'h80000000, 32'd1, 3'd5, 0);
            repeat (i) tick();
            cancel_valid = 1;
            cancel_tag = 0;
            held = 0;
            tick();
            cancel_valid = 0;
            drain();
        end
        for (i = 0; i < 3; i=i+1) begin
            send(32'h80000000, 32'hffffffff, 3'd4, 0);
            repeat (i) tick();
            cancel_valid = 1;
            cancel_tag = 0;
            held = 0;
            tick();
            cancel_valid = 0;
            drain();
            send(32'hffffffff, 0, 3'd6, 0);
            repeat (i) tick();
            cancel_valid = 1;
            held = 0;
            tick();
            cancel_valid = 0;
            drain();
        end
        // Cancellation also wins on E0, before any in-flight valid exists.
        age_head = 0;
        cancel_valid = 1;
        cancel_tag = 0;
        send(32'd15, 32'd3, 3'd4, 0);
        cancel_valid = 0;
        drain();
        $display("PASS div ISSUE_WIDTH=%0d FPU_FORMAT=%s accepted=%0d delivered=%0d",
            ISSUE_WIDTH, FPU_FORMAT, accepted, delivered);
        $finish;
    end
    initial begin
        #2000000;
        $fatal(1, "FAIL timeout");
    end
endmodule
