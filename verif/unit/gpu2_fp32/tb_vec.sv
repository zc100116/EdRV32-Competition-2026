// File: tb_vec.sv
// Spec: gpu-v2-spec 2.4; VT04 native vec4, staged DP and backpressure.
// Description: Independent vector reference queues; both result ports exercised together.
// Clock domain: clk_gpu.
module tb_vec;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg req_valid = 0;
    wire req_ready;
    reg [1:0] op;
    reg [127:0] a;
    reg [127:0] b;
    reg [127:0] c;
    wire vec_valid;
    reg vec_ready = 0;
    wire [127:0] vec_data;
    wire dp_valid;
    reg dp_ready = 0;
    wire [31:0] dp_data;
    edrv32_gpu2_fp32 u_dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .req_valid_i(req_valid),
        .req_ready_o(req_ready),
        .req_op_i(op),
        .req_a_i(a),
        .req_b_i(b),
        .req_c_i(c),
        .vec_valid_o(vec_valid),
        .vec_ready_i(vec_ready),
        .vec_data_o(vec_data),
        .dp_valid_o(dp_valid),
        .dp_ready_i(dp_ready),
        .dp_data_o(dp_data)
    );
    reg [127:0] expected_vec[$];
    reg [31:0] expected_dp[$];
    integer vec_due[$];
    integer dp_due[$];
    integer due;
    reg [127:0] next_vec;
    reg [31:0] next_dp;
    reg [127:0] expected_vec_word;
    reg [31:0] expected_dp_word;
    reg [31:0] random_state = 32'h19841128;
    reg [127:0] held_vec;
    reg [31:0] held_dp;
    reg holding_vec = 0;
    reg holding_dp = 0;
    integer stream;
    integer scan;
    integer count;
    integer sent = 0;
    integer received = 0;
    integer cycle = 0;
    reg pending = 0;
    string path;
    initial begin
        if (!$value$plusargs("VECTORS=%s", path)) $fatal(1, "missing VECTORS");
        stream = $fopen(path, "r");
        if (stream == 0) $fatal(1, "cannot open vectors");
        scan = $fscanf(stream, "%d\n", count);
        repeat (3) @(negedge clk);
        rst_n = 1;
        while (received < count) begin
            @(negedge clk);
            cycle++;
            random_state = {random_state[30:0], random_state[31] ^ random_state[21]
                            ^ random_state[1] ^ random_state[0]};
            if (!pending && sent < count) begin
                scan = $fscanf(stream, "%h %h %h %h %h %h\n", op, a, b, c,
                               next_vec, next_dp);
                if (scan != 6) $fatal(1, "bad vector %0d", sent);
                pending = 1;
            end
            req_valid = pending && (cycle < 256 || random_state[0]);
            vec_ready = cycle < 256 || random_state[1];
            dp_ready = cycle < 256 || random_state[2];
            @(posedge clk);
            if (cycle < 256 && !req_ready) $fatal(1, "native II1 acceptance gap");
            if (req_valid && req_ready) begin
                if (op[1]) begin
                    expected_dp.push_back(next_dp);
                    dp_due.push_back(cycle + 16);
                end else begin
                    expected_vec.push_back(next_vec);
                    vec_due.push_back(cycle + 12);
                end
                sent++;
                pending = 0;
            end
            if (holding_vec && (!vec_valid || vec_data !== held_vec))
                $fatal(1, "vector response changed under backpressure");
            if (holding_dp && (!dp_valid || dp_data !== held_dp))
                $fatal(1, "dot response changed under backpressure");
            if (vec_valid && vec_ready) begin
                if (expected_vec.size() == 0) $fatal(1, "unexpected vector completion");
                expected_vec_word = expected_vec.pop_front();
                due = vec_due.pop_front();
                if (cycle < 256 && cycle != due)
                    $fatal(1, "vec latency expected cycle %0d got %0d", due, cycle);
                if (vec_data !== expected_vec_word)
                    $fatal(1, "vec expected %h got %h time %t", expected_vec_word,
                           vec_data, $time);
                received++;
            end
            if (dp_valid && dp_ready) begin
                if (expected_dp.size() == 0) $fatal(1, "unexpected dot completion");
                expected_dp_word = expected_dp.pop_front();
                due = dp_due.pop_front();
                if (cycle < 256 && cycle != due)
                    $fatal(1, "DP latency expected cycle %0d got %0d", due, cycle);
                if (dp_data !== expected_dp_word)
                    $fatal(1, "dot expected %h got %h time %t", expected_dp_word,
                           dp_data, $time);
                received++;
            end
            holding_vec = vec_valid && !vec_ready;
            holding_dp = dp_valid && !dp_ready;
            held_vec = vec_data;
            held_dp = dp_data;
            if (cycle > count * 20 + 100) $fatal(1, "test did not drain");
        end
        $display("PASS vec4/staged DP %0d mixed requests in %0d clocks", received, cycle);
        $finish;
    end
endmodule
