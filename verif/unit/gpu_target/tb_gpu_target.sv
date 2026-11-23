// File: tb_gpu_target.sv
// Spec: gpu-spec 2.1, 2.3, 2.7; R-4b unit verification.
// Description: Self-checking directed and ordered stream tests.
// Clock: simulated clk_gpu.
module tb_gpu_target;
    reg clk_i;
    reg rst_n_i;
    reg clear_valid_i;
    wire clear_ready_o;
    reg [255:0] clear_command_i;
    reg [255:0] clear_target_i;
    reg clear_wide_i;
    reg target_read_valid_i;
    wire target_read_ready_o;
    reg [15:0] target_read_addr_i;
    wire target_old_valid_o;
    reg target_old_ready_i;
    wire [159:0] target_old_data_o;
    reg target_write_valid_i;
    wire target_write_ready_o;
    reg [15:0] target_write_addr_i;
    reg [159:0] target_write_data_i;
    reg resolve_read_valid_i;
    wire resolve_read_ready_o;
    reg [15:0] resolve_read_addr_i;
    wire resolve_color_valid_o;
    reg resolve_color_ready_i;
    wire [63:0] resolve_color_data_o;
    reg finish_i;
    reg stop_i;
    wire unit_done_o;
    initial clk_i = 0;
    always #5 clk_i = ~clk_i;
    edrv32_gpu_target u_dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .clear_valid_i(clear_valid_i),
        .clear_ready_o(clear_ready_o),
        .clear_command_i(clear_command_i),
        .clear_target_i(clear_target_i),
        .clear_wide_i(clear_wide_i),
        .target_read_valid_i(target_read_valid_i),
        .target_read_ready_o(target_read_ready_o),
        .target_read_addr_i(target_read_addr_i),
        .target_old_valid_o(target_old_valid_o),
        .target_old_ready_i(target_old_ready_i),
        .target_old_data_o(target_old_data_o),
        .target_write_valid_i(target_write_valid_i),
        .target_write_ready_o(target_write_ready_o),
        .target_write_addr_i(target_write_addr_i),
        .target_write_data_i(target_write_data_i),
        .resolve_read_valid_i(resolve_read_valid_i),
        .resolve_read_ready_o(resolve_read_ready_o),
        .resolve_read_addr_i(resolve_read_addr_i),
        .resolve_color_valid_o(resolve_color_valid_o),
        .resolve_color_ready_i(resolve_color_ready_i),
        .resolve_color_data_o(resolve_color_data_o),
        .finish_i(finish_i),
        .stop_i(stop_i),
        .unit_done_o(unit_done_o)
    );
    task automatic defaults;
        begin
            rst_n_i = '0;
            clear_valid_i = '0;
            clear_command_i = '0;
            clear_target_i = '0;
            clear_wide_i = '0;
            target_read_valid_i = '0;
            target_read_addr_i = '0;
            target_old_ready_i = '0;
            target_write_valid_i = '0;
            target_write_addr_i = '0;
            target_write_data_i = '0;
            resolve_read_valid_i = '0;
            resolve_read_addr_i = '0;
            resolve_color_ready_i = '0;
            finish_i = '0;
            stop_i = '0;
        end
    endtask
    reg [159:0] expected [0:28799];
    reg [159:0] queued_data [0:31];
    reg queued_resolve [0:31];
    integer queued_cycle [0:31];
    integer sent;
    integer received;
    integer cycle;
    integer reads;
    integer clears;
    integer shape;
    integer flags;
    integer addr;
    integer xpos;
    integer ypos;
    integer width;
    integer previous_received;
    integer request_cycle;
    reg stalls;
    reg check_latency;
    reg [159:0] pattern;
    reg held_old;
    reg held_color;
    reg [159:0] held_old_data;
    reg [63:0] held_color_data;
    always @(posedge clk_i) begin
        if (rst_n_i) begin
            cycle = cycle + 1;
            if (target_write_valid_i && target_write_ready_o)
                expected[int'(target_write_addr_i)] = target_write_data_i;
            if (target_read_valid_i && target_read_ready_o) begin
                queued_data[sent%32] = expected[int'(target_read_addr_i)];
                queued_resolve[sent%32] = 0;
                queued_cycle[sent%32] = cycle;
                sent = sent + 1;
            end
            if (resolve_read_valid_i && resolve_read_ready_o) begin
                queued_data[sent%32] = expected[int'(resolve_read_addr_i)];
                queued_resolve[sent%32] = 1;
                queued_cycle[sent%32] = cycle;
                sent = sent + 1;
            end
            if (held_old && (!target_old_valid_o || target_old_data_o !== held_old_data))
                $fatal(1, "FAIL target_old changed while blocked t=%t", $time);
            if (held_color && (!resolve_color_valid_o || resolve_color_data_o !== held_color_data))
                $fatal(1, "FAIL resolve_color changed while blocked t=%t", $time);
            held_old = target_old_valid_o && !target_old_ready_i;
            held_color = resolve_color_valid_o && !resolve_color_ready_i;
            held_old_data = target_old_data_o;
            held_color_data = resolve_color_data_o;
            if (target_old_valid_o && target_old_ready_i) begin
                if (received == sent || queued_resolve[received%32] ||
                    target_old_data_o !== queued_data[received%32])
                    $fatal(1, "FAIL target read %0d expected=%h got=%h t=%t", received,
                        queued_data[received%32], target_old_data_o, $time);
                if (check_latency && cycle-queued_cycle[received%32] != 5)
                    $fatal(1, "FAIL target latency=%0d", cycle-queued_cycle[received%32]);
                received = received + 1;
                reads = reads + 1;
            end
            if (resolve_color_valid_o && resolve_color_ready_i) begin
                if (received == sent || !queued_resolve[received%32])
                    $fatal(1, "FAIL resolve order");
                for (integer k = 0; k < 4; k = k + 1) begin
                    if (resolve_color_data_o[k*16 +: 16] !== queued_data[received%32][k*40 +: 16])
                        $fatal(1, "FAIL resolve lane=%0d expected=%h got=%h t=%t", k,
                            queued_data[received%32][k*40 +: 16],
                            resolve_color_data_o[k*16 +: 16], $time);
                end
                if (check_latency && cycle-queued_cycle[received%32] != 5)
                    $fatal(1, "FAIL resolve latency=%0d", cycle-queued_cycle[received%32]);
                received = received + 1;
                reads = reads + 1;
            end
        end
    end
    always @(negedge clk_i) begin
        target_old_ready_i = !stalls || cycle%29 > 19;
        resolve_color_ready_i = !stalls || cycle%31 > 20;
    end
    task automatic drain;
        begin
            while (sent != received) @(negedge clk_i);
            repeat (3) @(negedge clk_i);
        end
    endtask
    task automatic write_word(input integer a, input [159:0] data);
        begin
            target_write_valid_i = 1;
            target_write_addr_i = 16'(a);
            target_write_data_i = data;
            do @(posedge clk_i); while (!target_write_ready_o);
            @(negedge clk_i);
            target_write_valid_i = 0;
        end
    endtask
    task automatic read_word(input integer a, input is_resolve);
        begin
            if (is_resolve) begin
                resolve_read_valid_i = 1;
                resolve_read_addr_i = 16'(a);
                do @(posedge clk_i); while (!resolve_read_ready_o);
                @(negedge clk_i);
                resolve_read_valid_i = 0;
            end else begin
                target_read_valid_i = 1;
                target_read_addr_i = 16'(a);
                do @(posedge clk_i); while (!target_read_ready_o);
                @(negedge clk_i);
                target_read_valid_i = 0;
            end
        end
    endtask
    task automatic clear_reference;
        integer x;
        integer y;
        begin
            for (integer a = 0; a < 28800; a = a + 1) begin
                for (integer k = 0; k < 4; k = k + 1) begin
                    x = (a%(clear_wide_i ? 320 : 160))*4 + k +
                        int'($signed(clear_target_i[47:32]));
                    y = a/(clear_wide_i ? 320 : 160) +
                        int'($signed(clear_target_i[63:48]));
                    if (x >= int'($signed(clear_target_i[79:64])) &&
                        y >= int'($signed(clear_target_i[95:80])) &&
                        x < int'($signed(clear_target_i[111:96])) &&
                        y < int'($signed(clear_target_i[127:112]))) begin
                        if (clear_command_i[72])
                            expected[a][k*40 +: 16] = clear_command_i[47:32];
                        if (clear_command_i[73])
                            expected[a][k*40+16 +: 16] = clear_command_i[63:48];
                        if (clear_command_i[74])
                            expected[a][k*40+32 +: 8] = clear_command_i[71:64];
                    end
                end
            end
        end
    endtask
    task automatic clear_words;
        begin
            drain();
            finish_i = 0;
            clear_valid_i = 1;
            do @(posedge clk_i); while (!clear_ready_o);
            @(negedge clk_i);
            clear_valid_i = 0;
            clear_reference();
            finish_i = 1;
            while (!unit_done_o) @(negedge clk_i);
            finish_i = 0;
            clears = clears + 1;
        end
    endtask
    integer clear_begin_cycle;
    integer small_clear_cycles;
    initial begin
        defaults();
        sent = 0;
        received = 0;
        cycle = 0;
        reads = 0;
        clears = 0;
        stalls = 0;
        check_latency = 0;
        held_old = 0;
        held_color = 0;

        repeat (3) @(negedge clk_i);
        rst_n_i = 1;
        // Complete an empty command, then leave the new command without input.
        // The old done level must clear before any draw/configuration reaches this unit.
        finish_i = 1;
        do @(negedge clk_i); while (!unit_done_o);
        finish_i = 0;
        repeat (8) begin
            @(negedge clk_i);
            if (unit_done_o) $fatal(1, "FAIL stale done while new command waits upstream");
        end

        // All addresses, including every segment transition and both tail endpoints.
        for (addr = 0; addr < 28800; addr = addr + 1) begin
            pattern = 0;
            for (integer k = 0; k < 4; k = k + 1)
                pattern[k*40 +: 40] = {8'(addr+k), 16'(addr*5+k), 16'(addr*7+k)};
            write_word(addr, pattern);
        end
        check_latency = 1;
        for (addr = 0; addr < 28800; addr = addr + 1) read_word(addr, 0);
        drain();
        for (addr = 0; addr < 28800; addr = addr + 1) read_word(addr, 1);
        drain();
        check_latency = 0;
        stalls = 1;
        for (addr = 28799; addr >= 0; addr = addr - 1) read_word(addr, 0);
        drain();
        for (addr = 0; addr < 128; addr = addr + 1) read_word(28672+addr, 1);
        drain();
        stalls = 0;
        // Capture a commit alongside predecode, then change the recent write before response.
        target_write_valid_i = 1;
        target_write_addr_i = 2048;
        target_write_data_i = {4{40'hfedcba9876}};
        target_read_valid_i = 1;
        target_read_addr_i = 2048;
        @(posedge clk_i);
        @(negedge clk_i);
        target_read_valid_i = 0;
        target_write_addr_i = 2049;
        target_write_data_i = {4{40'h123456789a}};
        @(posedge clk_i);
        @(negedge clk_i);
        target_write_valid_i = 0;
        drain();
        // Both shapes, signed offsets, all clear switch combinations, partial edge lanes.
        for (shape = 0; shape < 2; shape = shape + 1) begin
            clear_wide_i = shape[0];
            clear_target_i[47:32] = -16'sd16;
            clear_target_i[63:48] = 16'd123;
            width = shape == 0 ? 640 : 1280;
            clear_target_i[79:64] = -16'sd13;
            clear_target_i[95:80] = 16'd124;
            clear_target_i[111:96] = 16'(width-17);
            clear_target_i[127:112] = 16'(123+(shape == 0 ? 180 : 90)-1);
            for (flags = 0; flags < 8; flags = flags + 1) begin
                clear_command_i[47:32] = 16'(32'hc51a + flags);
                clear_command_i[63:48] = 16'(32'h1357 + flags);
                clear_command_i[71:64] = 8'(32'h96 + flags);
                clear_command_i[74:72] = flags[2:0];
                clear_words();
                for (addr = 0; addr < 28800; addr = addr + 1) read_word(addr, flags[0]);
                drain();
            end
            // Entire intersection and empty intersection.
            clear_target_i[79:64] = -16'sd32768;
            clear_target_i[95:80] = -16'sd32768;
            clear_target_i[111:96] = 16'd32767;
            clear_target_i[127:112] = 16'd32767;
            clear_words();
            read_word(0, 0);
            read_word(28799, 1);
            drain();
            clear_target_i[111:96] = -16'sd100;
            clear_words();
            read_word(0, 0);
            read_word(28799, 1);
            drain();
        end
        // Clipped traversal costs one cycle per covered word plus fixed RAM/drain latency.
        clear_wide_i = 0;
        clear_target_i[47:32] = -16'sd16;
        clear_target_i[63:48] = 16'd123;
        clear_target_i[79:64] = -16'sd12;
        clear_target_i[95:80] = 16'd124;
        clear_target_i[111:96] = 16'd4;
        clear_target_i[127:112] = 16'd140;
        clear_command_i[47:32] = 16'h8bad;
        clear_command_i[63:48] = 16'h89ab;
        clear_command_i[71:64] = 8'ha5;
        clear_command_i[74:72] = 3'b111;
        clear_begin_cycle = cycle;
        clear_words();
        small_clear_cycles = cycle - clear_begin_cycle;
        if (small_clear_cycles > 64+16)
            $fatal(1, "FAIL 16x16 CLEAR cycles=%0d words=64", small_clear_cycles);
        $display("PERF CLEAR 16x16 words=64 cycles=%0d", small_clear_cycles);
        read_word(160, 0);
        read_word(161, 0);
        read_word(2564, 1);
        drain();
        // The first and last words retain unselected lanes, including across row strides.
        clear_target_i[79:64] = -16'sd13;
        clear_target_i[111:96] = -16'sd9;
        clear_target_i[127:112] = 16'd128;
        clear_command_i[47:32] = 16'h24e7;
        clear_begin_cycle = cycle;
        clear_words();
        small_clear_cycles = cycle - clear_begin_cycle;
        if (small_clear_cycles > 8+16)
            $fatal(1, "FAIL partial CLEAR cycles=%0d words=8", small_clear_cycles);
        $display("PERF CLEAR partial 4x4 words=8 cycles=%0d", small_clear_cycles);
        read_word(160, 0);
        read_word(161, 0);
        read_word(640, 1);
        read_word(641, 1);
        drain();
        clear_target_i[111:96] = -16'sd100;
        clear_begin_cycle = cycle;
        clear_words();
        small_clear_cycles = cycle - clear_begin_cycle;
        if (small_clear_cycles > 16)
            $fatal(1, "FAIL empty CLEAR cycles=%0d", small_clear_cycles);
        $display("PERF CLEAR empty words=0 cycles=%0d", small_clear_cycles);
        finish_i = 1;
        while (!unit_done_o) @(negedge clk_i);
        $display("PASS gpu_target reads=%0d clears=%0d words=28800 shapes=2 latency=5", reads, clears);
        $finish;
    end
    initial begin
        #40000000;
        $fatal(1, "FAIL gpu_target timeout sent=%0d received=%0d", sent, received);
    end
endmodule
