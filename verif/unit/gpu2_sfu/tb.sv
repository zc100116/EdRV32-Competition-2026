// File: tb.sv
// Spec: gpu-v2-spec 2.4; VT06 and G-P02 complete mixed reservation probe.
// Description: Independent due-cycle scoreboard; concurrent setup ROM reads and return stalls.
// Clock domain: clk_gpu.
module tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg req_valid = 0;
    wire req_ready;
    reg [1:0] op;
    reg [31:0] x;
    reg [4:0] tag;
    wire valid0;
    wire valid1;
    reg ready0 = 0;
    reg ready1 = 0;
    wire [31:0] data0;
    wire [31:0] data1;
    wire [4:0] tag0;
    wire [4:0] tag1;
    reg setup_en = 0;
    reg [5:0] setup_index;
    wire [31:0] setup_seed;
    edrv32_gpu2_sfu u_dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .req_valid_i(req_valid),
        .req_ready_o(req_ready),
        .req_op_i(op),
        .req_data_i(x),
        .req_tag_i(tag),
        .resp0_valid_o(valid0),
        .resp0_ready_i(ready0),
        .resp0_data_o(data0),
        .resp0_tag_o(tag0),
        .resp1_valid_o(valid1),
        .resp1_ready_i(ready1),
        .resp1_data_o(data1),
        .resp1_tag_o(tag1),
        .setup_en_i(setup_en),
        .setup_index_i(setup_index),
        .setup_seed_o(setup_seed)
    );
    reg [36:0] calendar0 [int];
    reg [36:0] calendar1 [int];
    reg [36:0] expected0 [$];
    reg [36:0] expected1 [$];
    reg [36:0] expected_word;
    reg [31:0] setup_table [0:63];
    reg [31:0] expected_seed;
    reg seed_valid = 0;
    reg [31:0] random_state = 32'h19381128;
    reg [36:0] held0;
    reg [36:0] held1;
    reg holding0 = 0;
    reg holding1 = 0;
    reg [31:0] next_expected;
    reg pending = 0;
    integer count;
    integer stream;
    integer scan;
    integer cycle = 0;
    integer sent = 0;
    integer received = 0;
    integer due;
    integer last_accept = 0;
    integer expected_issues = 0;
    integer actual_issues = 0;
    string path;
    string setup_path;
    initial begin
        if (!$value$plusargs("VECTORS=%s", path)) $fatal(1, "missing VECTORS");
        if (!$value$plusargs("SETUP=%s", setup_path)) $fatal(1, "missing SETUP");
        $readmemh(setup_path, setup_table);
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
                scan = $fscanf(stream, "%h %h %h\n", op, x, next_expected);
                if (scan != 3) $fatal(1, "bad SFU vector %0d", sent);
                tag = 5'(sent);
                pending = 1;
            end
            req_valid = pending;
            ready0 = cycle < 2200 || (cycle > 2320 && random_state[0]);
            ready1 = cycle < 2200 || (cycle > 2320 && random_state[1]);
            setup_en = random_state[2];
            setup_index = random_state[8:3];
            @(posedge clk);
            if (req_valid && req_ready) begin
                if (sent > 0 && sent < 512 && cycle != last_accept+4) $fatal(1, "II4 gap at %0d", cycle);
                last_accept = cycle;
                case (op)
                    0: begin due = cycle+56; expected_issues += 4; end
                    1: begin due = cycle+79; expected_issues += 6; end
                    2: begin due = cycle+102; expected_issues += 8; end
                    3: begin due = cycle+91; expected_issues += 7; end
                    default: $fatal(1, "bad opcode");
                endcase
                if (op == 1) begin
                    if (calendar0.exists(due) != 0) $fatal(1, "model return collision");
                    calendar0[due] = {tag, next_expected};
                end else begin
                    if (calendar1.exists(due) != 0) $fatal(1, "model return collision");
                    calendar1[due] = {tag, next_expected};
                end
                pending = 0;
                sent++;
            end
            if (calendar0.exists(cycle) != 0) begin
                expected0.push_back(calendar0[cycle]);
                calendar0.delete(cycle);
            end
            if (calendar1.exists(cycle) != 0) begin
                expected1.push_back(calendar1[cycle]);
                calendar1.delete(cycle);
            end
            if ((u_dut.engine0_events_w & (u_dut.engine0_events_w-4'd1)) != 0
                    || (u_dut.engine1_events_w & (u_dut.engine1_events_w-4'd1)) != 0)
                $fatal(1, "RTL reservation conflict at %0d", cycle);
            if ((u_dut.field1_update0_w && u_dut.field1_update1_w)
                    || (u_dut.front_commit_r[0] && (u_dut.field1_update0_w
                        || u_dut.field1_update1_w || u_dut.field3_update_w)))
                $fatal(1, "scratch write collision at %0d", cycle);
            actual_issues += int'(u_dut.unused_issue_valid_w[0])
                + int'(u_dut.unused_issue_valid_w[1]);
            if (holding0 && (!valid0 || {tag0, data0} !== held0))
                $fatal(1, "return0 changed under backpressure");
            if (holding1 && (!valid1 || {tag1, data1} !== held1))
                $fatal(1, "return1 changed under backpressure");
            if (cycle < 2200 && ((expected0.size() != 0 && !valid0)
                    || (expected1.size() != 0 && !valid1)))
                $fatal(1, "late SFU return at %0d", cycle);
            if (valid0 && ready0) begin
                if (expected0.size() == 0) $fatal(1, "early return0 at %0d", cycle);
                expected_word = expected0.pop_front();
                if ({tag0, data0} !== expected_word)
                    $fatal(1, "SFU0 cycle %0d expected %h got %h", cycle,
                           expected_word, {tag0, data0});
                received++;
            end
            if (valid1 && ready1) begin
                if (expected1.size() == 0) $fatal(1, "early return1 at %0d", cycle);
                expected_word = expected1.pop_front();
                if ({tag1, data1} !== expected_word)
                    $fatal(1, "SFU1 cycle %0d expected %h got %h", cycle,
                           expected_word, {tag1, data1});
                received++;
            end
            holding0 = valid0 && !ready0;
            holding1 = valid1 && !ready1;
            held0 = {tag0, data0};
            held1 = {tag1, data1};
            if (setup_en) begin
                expected_seed = setup_table[setup_index];
                seed_valid = 1;
            end
            #1;
            if (seed_valid && setup_seed !== expected_seed)
                $fatal(1, "setup seed expected %h got %h at %0d", expected_seed, setup_seed, cycle);
            if (cycle > count*12+2048) $fatal(1, "SFU did not drain");
        end
        if (actual_issues != expected_issues)
            $fatal(1, "arithmetic issues expected %0d got %0d", expected_issues, actual_issues);
        $display("PASS SFU %0d requests, %0d RTL reservations, first512 dense II4, latency56/79/102/91, setup concurrent",
                 received, actual_issues);
        $finish;
    end
endmodule
