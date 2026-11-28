// CV07: independent current-row TAGE update model; no internal DUT observations.
module tb;
    reg [63:0] rows;
    reg [39:0] tags;
    reg [2:0] provider;
    reg prediction;
    reg alternate;
    reg taken;
    reg [1:0] base;
    wire [1:0] next_base;
    wire [63:0] next_rows;
    wire [3:0] write_mask;
    edrv32_cpu2_tage_update dut (
        .rows_i(rows),
        .tags_i(tags),
        .provider_i(provider),
        .prediction_i(prediction),
        .alternate_i(alternate),
        .taken_i(taken),
        .base_i(base),
        .base_o(next_base),
        .rows_o(next_rows),
        .write_o(write_mask)
    );
    function automatic integer saturate(input integer value, input bit up,
                                       input integer maximum);
        if (up) saturate = value < maximum ? value + 1 : maximum;
        else saturate = value > 0 ? value - 1 : 0;
    endfunction
    reg [63:0] expected_rows;
    reg [3:0] expected_mask;
    reg [1:0] expected_base;
    reg [15:0] row_value;
    bit allocated;
    integer count;
    integer useful;
    integer seed;
    integer random_value;
    task compare;
        begin
            expected_rows = rows;
            expected_mask = 0;
            expected_base = 2'(saturate(int'(base), taken, 3));
            allocated = 0;
            for (integer table_number = 0; table_number < 4; table_number++) begin
                row_value = rows[table_number*16 +: 16];
                count = int'(row_value[4:2]);
                useful = int'(row_value[1:0]);
                if (table_number + 1 == int'(provider) && row_value[15] &&
                    row_value[14:5] == tags[table_number*10 +: 10]) begin
                    count = saturate(count, taken, 7);
                    if (prediction != alternate)
                        useful = saturate(useful, prediction == taken, 3);
                    expected_rows[table_number*16 +: 16] =
                        {row_value[15:5], 3'(count), 2'(useful)};
                    expected_mask[table_number] = 1;
                end
                if (prediction != taken && table_number + 1 > int'(provider) &&
                    !allocated) begin
                    expected_mask[table_number] = 1;
                    if (!row_value[15] || useful == 0) begin
                        expected_rows[table_number*16 +: 16] =
                            {1'b1, tags[table_number*10 +: 10], taken ? 3'd4 : 3'd3, 2'd0};
                        allocated = 1;
                    end else begin
                        expected_rows[table_number*16 +: 16] =
                            {row_value[15:2], 2'(useful - 1)};
                    end
                end
            end
            #1;
            if (next_rows !== expected_rows || write_mask !== expected_mask ||
                next_base !== expected_base)
                $fatal(1, "CV07 time=%0t provider=%0d rows=%h expected=%h got=%h mask=%h/%h base=%h/%h",
                       $time, provider, rows, expected_rows, next_rows,
                       expected_mask, write_mask, expected_base, next_base);
        end
    endtask
    initial begin
        seed = 7108;
        // Each provider, initial/base saturation, tag match/mismatch, row validity,
        // all counter/usefulness values, and both outcomes/alternate directions.
        for (integer p = 0; p < 5; p++) begin
            for (integer state_value = 0; state_value < 128; state_value++) begin
                for (integer controls = 0; controls < 64; controls++) begin
                    provider = 3'(p);
                    prediction = 1'(controls);
                    alternate = 1'(controls >> 1);
                    taken = 1'(controls >> 2);
                    base = 2'(controls >> 3);
                    for (integer j = 0; j < 4; j++) begin
                        tags[j*10 +: 10] = 10'(37+j);
                        rows[j*16 +: 16] = {1'(state_value >> 5),
                            10'(37+j+((controls >> 5)&1)),
                            3'(state_value), 2'(state_value >> 3)};
                    end
                    compare();
                end
            end
        end
        // Mixed table pressure must stop at the first free longer table.
        for (integer n = 0; n < 20000; n++) begin
            for (integer j = 0; j < 4; j++) begin
                seed = seed * 1664525 + 1013904223;
                random_value = seed;
                rows[j*16 +: 16] = 16'(random_value);
                tags[j*10 +: 10] = (n%2 != 0) ? 10'(random_value >> 5) : 10'(random_value >> 17);
            end
            seed = seed * 1664525 + 1013904223;
            random_value = seed;
            provider = 3'((random_value & 'h7fffffff)%5);
            prediction = 1'(random_value >> 3);
            alternate = 1'(random_value >> 4);
            taken = 1'(random_value >> 5);
            base = 2'(random_value >> 6);
            compare();
        end
        $display("PASS CV07 TAGE update: 60960 independent state comparisons seed=7108");
        $finish;
    end
endmodule
