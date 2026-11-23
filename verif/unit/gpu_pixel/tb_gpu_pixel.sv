// File: tb_gpu_pixel.sv
// Spec: gpu-spec 2.1, 2.3, 2.7; R-4b unit verification.
// Description: Self-checking directed and ordered stream tests.
// Clock: simulated clk_gpu.
module tb_gpu_pixel;
    reg clk_i;
    reg rst_n_i;
    reg render_state_valid_i;
    wire render_state_ready_o;
    reg [255:0] render_state_tex_i;
    reg [255:0] render_state_pixel_i;
    reg [255:0] render_state_target_i;
    reg render_state_wide_i;
    reg shaded_valid_i;
    wire shaded_ready_o;
    reg [15:0] shaded_x_i;
    reg [15:0] shaded_y_i;
    reg [3:0] shaded_mask_i;
    reg [63:0] shaded_depth_i;
    reg [95:0] shaded_color_i;
    reg [31:0] shaded_alpha_i;
    wire target_read_valid_o;
    reg target_read_ready_i;
    wire [15:0] target_read_addr_o;
    reg target_old_valid_i;
    wire target_old_ready_o;
    reg [159:0] target_old_data_i;
    wire target_write_valid_o;
    reg target_write_ready_i;
    wire [15:0] target_write_addr_o;
    wire [159:0] target_write_data_o;
    reg finish_i;
    reg stop_i;
    wire unit_done_o;
    wire [2:0] perf_pixel_count_o;
    initial clk_i = 0;
    always #5 clk_i = ~clk_i;
    edrv32_gpu_pixel u_dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .render_state_valid_i(render_state_valid_i),
        .render_state_ready_o(render_state_ready_o),
        .render_state_tex_i(render_state_tex_i),
        .render_state_pixel_i(render_state_pixel_i),
        .render_state_target_i(render_state_target_i),
        .render_state_wide_i(render_state_wide_i),
        .shaded_valid_i(shaded_valid_i),
        .shaded_ready_o(shaded_ready_o),
        .shaded_x_i(shaded_x_i),
        .shaded_y_i(shaded_y_i),
        .shaded_mask_i(shaded_mask_i),
        .shaded_depth_i(shaded_depth_i),
        .shaded_color_i(shaded_color_i),
        .shaded_alpha_i(shaded_alpha_i),
        .target_read_valid_o(target_read_valid_o),
        .target_read_ready_i(target_read_ready_i),
        .target_read_addr_o(target_read_addr_o),
        .target_old_valid_i(target_old_valid_i),
        .target_old_ready_o(target_old_ready_o),
        .target_old_data_i(target_old_data_i),
        .target_write_valid_o(target_write_valid_o),
        .target_write_ready_i(target_write_ready_i),
        .target_write_addr_o(target_write_addr_o),
        .target_write_data_o(target_write_data_o),
        .finish_i(finish_i),
        .stop_i(stop_i),
        .unit_done_o(unit_done_o),
        .perf_pixel_count_o(perf_pixel_count_o)
    );
    task automatic defaults;
        begin
            rst_n_i = '0;
            render_state_valid_i = '0;
            render_state_tex_i = '0;
            render_state_pixel_i = '0;
            render_state_target_i = '0;
            render_state_wide_i = '0;
            shaded_valid_i = '0;
            shaded_x_i = '0;
            shaded_y_i = '0;
            shaded_mask_i = '0;
            shaded_depth_i = '0;
            shaded_color_i = '0;
            shaded_alpha_i = '0;
            target_read_ready_i = '0;
            target_old_valid_i = '0;
            target_old_data_i = '0;
            target_write_ready_i = '0;
            finish_i = '0;
            stop_i = '0;
        end
    endtask
    reg [159:0] memory [0:28799];
    reg [159:0] expected [0:28799];
    reg [159:0] expected_data [0:32767];
    reg [15:0] expected_addr [0:32767];
    reg [159:0] response_data [0:31];
    integer response_due [0:31];
    integer cycle;
    integer sent;
    integer received;
    integer read_sent;
    integer read_received;
    integer perf_expected;
    integer perf_received;
    integer blocked_cycles;
    integer current_addr;
    reg stall_writes;
    reg no_stalls;
    integer streak;
    integer max_streak;
    reg [40:0] lane_result;
    reg [159:0] word_result;
    reg [255:0] cfg;
    integer cases;
    integer f;
    integer op;
    integer path;
    integer masks;
    integer refcode;
    integer fs;
    integer fd;
    integer variant;
    integer index;
    integer boundary;
    integer shape;

    function automatic [40:0] reference_pixel(
        input [39:0] old_pixel,
        input [15:0] new_depth,
        input [23:0] source_color,
        input [7:0] alpha,
        input covered,
        input [255:0] state_bits
    );
        integer ref_value;
        integer st_value;
        integer st;
        integer next_st;
        integer operation;
        integer source;
        integer dest;
        integer factors [0:9];
        integer a;
        integer b;
        integer value;
        integer rgb [0:2];
        integer c;
        reg stencil_ok;
        reg depth_ok;
        reg [39:0] result;
        begin
            result = old_pixel;
            st = int'(old_pixel[39:32]);
            ref_value = (int'(state_bits[83:76]) & int'(state_bits[91:84]));
            st_value = st & int'(state_bits[91:84]);
            case (state_bits[66:64])
                0: stencil_ok = 0;
                1: stencil_ok = ref_value < st_value;
                2: stencil_ok = ref_value == st_value;
                3: stencil_ok = ref_value <= st_value;
                4: stencil_ok = ref_value > st_value;
                5: stencil_ok = ref_value != st_value;
                6: stencil_ok = ref_value >= st_value;
                default: stencil_ok = 1;
            endcase
            depth_ok = state_bits[32] || new_depth <= old_pixel[31:16];
            operation = !stencil_ok ? int'(state_bits[69:67]) :
                (!depth_ok ? int'(state_bits[72:70]) : int'(state_bits[75:73]));
            case (operation)
                0: next_st = st;
                1: next_st = 0;
                2: next_st = int'(state_bits[83:76]);
                3: next_st = st == 255 ? 255 : st + 1;
                4: next_st = st == 0 ? 0 : st - 1;
                default: next_st = 255 ^ st;
            endcase
            if (covered) begin
                result[39:32] = 8'((st & (255 ^ int'(state_bits[103:96]))) |
                    (next_st & int'(state_bits[103:96])));
            end
            if (covered && stencil_ok && depth_ok) begin
                if (state_bits[33]) result[31:16] = new_depth;
                for (c = 0; c < 3; c = c + 1) begin
                    source = int'(source_color[c*8 +: 8]);
                    case (c)
                        0: dest = int'({old_pixel[15:11], old_pixel[15:13]});
                        1: dest = int'({old_pixel[10:5], old_pixel[10:9]});
                        default: dest = int'({old_pixel[4:0], old_pixel[4:2]});
                    endcase
                    factors[0] = 0;
                    factors[1] = 255;
                    factors[2] = int'(alpha);
                    factors[3] = 255 - int'(alpha);
                    factors[4] = source;
                    factors[5] = 255-source;
                    factors[6] = dest;
                    factors[7] = 255-dest;
                    factors[8] = int'(state_bits[151:144]);
                    factors[9] = 255-int'(state_bits[151:144]);
                    a = source*factors[state_bits[131:128]] + 128;
                    a = (a + (a >> 8)) >> 8;
                    b = dest*factors[state_bits[135:132]] + 128;
                    b = (b + (b >> 8)) >> 8;
                    case (state_bits[138:136])
                        0: value = a+b;
                        1: value = a-b;
                        2: value = b-a;
                        3: value = a < b ? a : b;
                        default: value = a > b ? a : b;
                    endcase
                    rgb[c] = value < 0 ? 0 : (value > 255 ? 255 : value);
                end
                if (state_bits[34]) begin
                    result[15:0] = {5'(rgb[0] >> 3), 6'(rgb[1] >> 2), 5'(rgb[2] >> 3)};
                end
            end
            reference_pixel = {covered && stencil_ok && depth_ok, result};
        end
    endfunction

    // A five-cycle ordered RAM responder, with independent request/write stalls.
    always @(posedge clk_i) begin
        if (rst_n_i) begin
            cycle = cycle + 1;
            perf_received = perf_received + int'(perf_pixel_count_o);
            if (shaded_valid_i && shaded_ready_o) begin
                current_addr = (int'($signed(shaded_y_i)) -
                    int'($signed(render_state_target_i[63:48]))) *
                    (render_state_wide_i ? 320 : 160) +
                    ((int'($signed(shaded_x_i)) -
                    int'($signed(render_state_target_i[47:32]))) / 4);
                word_result = expected[current_addr];
                for (integer k = 0; k < 4; k = k + 1) begin
                    lane_result = reference_pixel(word_result[k*40 +: 40],
                        shaded_depth_i[k*16 +: 16], shaded_color_i[k*24 +: 24],
                        shaded_alpha_i[k*8 +: 8], shaded_mask_i[k], cfg);
                    word_result[k*40 +: 40] = lane_result[39:0];
                    perf_expected = perf_expected + int'(lane_result[40]);
                end
                expected[current_addr] = word_result;
                expected_data[sent] = word_result;
                expected_addr[sent] = 16'(current_addr);
                sent = sent + 1;
            end
            if (no_stalls && target_write_valid_o && target_write_ready_i) begin
                streak = streak + 1;
                if (streak > max_streak) max_streak = streak;
            end else begin
                streak = 0;
            end
            if (target_write_valid_o && target_write_ready_i) begin
                if (received == sent || target_write_addr_o !== expected_addr[received] ||
                    target_write_data_o !== expected_data[received]) begin
                    $fatal(1, "FAIL pixel result %0d cfg=%h addr=%0d/%0d expected=%h got=%h t=%t",
                        received, cfg, expected_addr[received], target_write_addr_o,
                        expected_data[received], target_write_data_o, $time);
                end
                memory[int'(target_write_addr_o)] = target_write_data_o;
                received = received + 1;
            end
            if (target_read_valid_o && target_read_ready_i) begin
                response_data[read_sent%32] = memory[int'(target_read_addr_o)];
                response_due[read_sent%32] = cycle + 5;
                read_sent = read_sent + 1;
            end
            if (target_old_valid_i && target_old_ready_o) begin
                read_received = read_received + 1;
            end
            if (shaded_valid_i && !shaded_ready_o) blocked_cycles = blocked_cycles + 1;
        end
    end
    always @(negedge clk_i) begin
        target_read_ready_i = rst_n_i && (no_stalls || cycle%11 != 0) && read_sent-read_received < 28;
        target_write_ready_i = rst_n_i && !stall_writes && (no_stalls || cycle%13 > 2);
        target_old_valid_i = read_sent != read_received &&
            response_due[read_received%32] <= cycle;
        target_old_data_i = response_data[read_received%32];
    end
    task automatic drain;
        begin
            while (received != sent) @(negedge clk_i);
            repeat (3) @(negedge clk_i);
            if (perf_received != perf_expected) begin
                $fatal(1, "FAIL PERF expected=%0d got=%0d", perf_expected, perf_received);
            end
        end
    endtask
    task automatic configure(input [255:0] value);
        begin
            drain();
            cfg = value;
            render_state_pixel_i = value;
            render_state_valid_i = 1;
            do @(posedge clk_i); while (!render_state_ready_o);
            @(negedge clk_i);
            render_state_valid_i = 0;
            cases = cases + 1;
        end
    endtask
    task automatic initialize_word(input integer addr, input integer seed);
        reg [39:0] pixel;
        begin
            for (integer k = 0; k < 4; k = k + 1) begin
                case (k)
                    0: pixel = {8'h00, 16'd99, 16'h0000};
                    1: pixel = {8'hff, 16'd100, 16'hffff};
                    2: pixel = {8'h7f, 16'd101, 16'h39e7};
                    default: pixel = {8'h80, 16'd65535, 16'hc618};
                endcase
                memory[addr][k*40 +: 40] = pixel ^ (40'(seed) << 2);
            end
            expected[addr] = memory[addr];
        end
    endtask
    task automatic send_word(input integer addr, input [3:0] mask, input integer seed);
        begin
            shaded_x_i = 16'((addr % (render_state_wide_i ? 320 : 160))*4 +
                int'($signed(render_state_target_i[47:32])));
            shaded_y_i = 16'((addr / (render_state_wide_i ? 320 : 160)) +
                int'($signed(render_state_target_i[63:48])));
            shaded_mask_i = mask;
            shaded_color_i = {24'hffffff, 24'h00ff80, 24'hff0080, 24'h010203} ^ 96'(seed);
            shaded_alpha_i = {8'd255, 8'd128, 8'd1, 8'd0} ^ 32'(seed);
            shaded_depth_i = {16'd65535, 16'd102, 16'd100, 16'd0};
            shaded_valid_i = 1;
            do @(posedge clk_i); while (!shaded_ready_o);
            @(negedge clk_i);
            shaded_valid_i = 0;
        end
    endtask
    initial begin
        defaults();
        cycle = 0;
        sent = 0;
        received = 0;
        read_sent = 0;
        read_received = 0;
        perf_expected = 0;
        perf_received = 0;
        blocked_cycles = 0;
        stall_writes = 0;
        no_stalls = 0;
        streak = 0;
        max_streak = 0;
        cases = 0;

        cfg = 0;
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

        render_state_target_i[47:32] = -16'sd12;
        render_state_target_i[63:48] = 16'd91;
        // Every function, operation path, mask and comparison boundary.
        for (f = 0; f < 8; f = f + 1)
        for (op = 0; op < 6; op = op + 1)
        for (path = 0; path < 3; path = path + 1)
        for (masks = 0; masks < 9; masks = masks + 1)
        for (refcode = 0; refcode < 3; refcode = refcode + 1) begin
            cfg = 0;
            cfg[34:32] = 3'b110;
            cfg[66:64] = 3'(f);
            cfg[67+3*path +: 3] = 3'(op);
            cfg[83:76] = refcode == 0 ? 0 : (refcode == 1 ? 127 : 255);
            cfg[91:84] = masks%3 == 0 ? 0 : (masks%3 == 1 ? 8'h55 : 8'hff);
            cfg[103:96] = masks/3 == 0 ? 0 : (masks/3 == 1 ? 8'ha5 : 8'hff);
            cfg[131:128] = 1;
            configure(cfg);
            initialize_word(0, 0);
            send_word(0, 4'hf, 0);
        end
        // All factor pairs and equations with boundary and interior alpha/constant values.
        for (fs = 0; fs < 10; fs = fs + 1)
        for (fd = 0; fd < 10; fd = fd + 1)
        for (op = 0; op < 5; op = op + 1)
        for (variant = 0; variant < 3; variant = variant + 1) begin
            cfg = 0;
            cfg[34:32] = 7;
            cfg[66:64] = 7;
            cfg[131:128] = 4'(fs);
            cfg[135:132] = 4'(fd);
            cfg[138:136] = 3'(op);
            cfg[151:144] = variant == 0 ? 0 : (variant == 1 ? 128 : 255);
            configure(cfg);
            initialize_word(1, 0);
            send_word(1, 4'hf, variant*37);
        end
        // Depth comparisons, writes and color switch; zero masks and alpha remain distinct.
        for (index = 0; index < 16; index = index + 1) begin
            cfg = 0;
            cfg[34:32] = index[2:0];
            cfg[66:64] = 7;
            cfg[75:73] = 3;
            cfg[103:96] = index[3] ? 0 : 255;
            cfg[131:128] = 1;
            configure(cfg);
            initialize_word(28799, 0);
            send_word(28799, 4'b0101, 0);
            send_word(28799, 4'b0000, 0);
        end
        // Consecutive same-word operations require waiting for an unresolved predecessor.
        cfg = 0;
        cfg[34:32] = 7;
        cfg[66:64] = 7;
        cfg[75:73] = 3;
        cfg[103:96] = 255;
        cfg[131:128] = 2;
        cfg[135:132] = 3;
        configure(cfg);
        initialize_word(7, 0);
        index = read_sent;
        for (variant = 0; variant < 48; variant = variant + 1) send_word(7, 15, variant);
        drain();
        if (read_sent-index != 1) $fatal(1, "FAIL unresolved/ready predecessor RAM reads");
        // The last predecessor is committed; the next operation must use RAM.
        index = read_sent;
        send_word(7, 15, 91);
        drain();
        if (read_sent-index != 1) $fatal(1, "FAIL committed predecessor RAM reads");
        // Hold commits to keep ready predecessors in the scoreboard while other words issue.
        initialize_word(8, 0);
        stall_writes = 1;
        send_word(8, 15, 17);
        repeat (40) @(negedge clk_i);
        index = read_sent;
        send_word(8, 15, 33);
        repeat (25) @(negedge clk_i);
        if (read_sent != index) $fatal(1, "FAIL ready predecessor was not forwarded");
        stall_writes = 0;
        drain();
        // Mapping includes both row widths, all segment boundaries and the tail.
        for (shape = 0; shape < 2; shape = shape + 1) begin
            render_state_wide_i = shape[0];
            configure(cfg);
            for (index = 0; index < 18; index = index + 1) begin
                case (index)
                    0: boundary = 159;
                    1: boundary = 160;
                    2: boundary = 319;
                    3: boundary = 320;
                    4: boundary = 28671;
                    5: boundary = 28672;
                    6: boundary = 28799;
                    default: boundary = (index-6)*2048;
                endcase
                initialize_word(boundary, index);
                send_word(boundary, 15, index);
            end
            drain();
        end
        // Distinct words exercise full throughput, queue wrap and output backpressure.
        no_stalls = 1;
        render_state_wide_i = 1;
        configure(cfg);
        for (index = 0; index < 160; index = index + 1) initialize_word(index, index);
        for (index = 0; index < 160; index = index + 1) send_word(index, 15, index);
        drain();
        if (max_streak < 100) $fatal(1, "FAIL four pixels/cycle streak=%0d", max_streak);
        finish_i = 1;
        while (!unit_done_o) @(negedge clk_i);
        $display("PASS gpu_pixel cases=%0d words=%0d pixels=%0d stalled=%0d steady_words=%0d",
            cases, received, perf_received, blocked_cycles, max_streak);
        $finish;
    end
    initial begin
        #20000000;
        $fatal(1, "FAIL gpu_pixel timeout sent=%0d received=%0d", sent, received);
    end
endmodule
