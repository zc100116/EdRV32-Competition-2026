// File: tb_npu_window.sv
// Spec: npu-spec 5.1, 5.2, 5.4; datapath design 4.2-4.4; OP-01..04/07, CP-02.
// Description: Formula-based bank/address/activation/tag scoreboard with exact issue calendar.
//              Real two-stage line RAM and contract-driven two-stage weight return.
// Clock: clk_npu.
module tb_npu_window;
    reg clk_i = 0;
    reg rst_n_i = 0;
    reg cancel_i = 0;
    reg cfg_k3_i = 0;
    reg cfg_s2_i = 0;
    reg cfg_in_c4_i = 0;
    reg cfg_half_tail_i = 0;
    reg cfg_lut_en_i = 0;
    reg cfg_res_en_i = 0;
    reg [7:0] cfg_out_zp_i = 0;
    reg [11:0] cfg_in_w_i = 0;
    reg [11:0] cfg_out_w_i = 0;
    reg [5:0] cfg_cin_blocks_i = 0;
    reg [3:0] cfg_cout_blocks_i = 0;
    reg [10:0] cfg_k_count_i = 0;
    reg cmd_valid_i = 0;
    wire cmd_ready_o;
    reg [11:0] cmd_row_i = 0;
    reg [2:0] cmd_block_i = 0;
    reg [10:0] cmd_weight_base_i = 0;
    reg [9:0] cmd_row_base0_i = 0;
    reg [9:0] cmd_row_base1_i = 0;
    reg [9:0] cmd_row_base2_i = 0;
    reg [2:0] cmd_row_valid_i = 0;
    reg issue_enable_i = 0;
    reg pair_ready_i = 0;
    reg [4:0] pair_result_slot_i = 0;
    reg [4:0] pair_residual_addr_i = 0;
    wire pair_fire_o;
    wire pair_half_o;
    wire [1:0] cache_rd_en_o;
    wire [9:0] cache_rd_addr0_o;
    wire [9:0] cache_rd_addr1_o;
    wire weight_rd_en_o;
    wire [10:0] weight_rd_addr_o;
    wire term_valid_o;
    wire term_first_o;
    wire term_last_o;
    wire [48:0] term_tag_o;
    wire [1023:0] term_activation_o;
    wire [2047:0] term_weight_o;
    wire cmd_issued_o;
    wire [11:0] cmd_issued_row_o;
    wire [2:0] cmd_issued_block_o;
    wire cmd_read_done_o;
    wire [11:0] cmd_read_done_row_o;
    wire [2:0] cmd_read_done_block_o;
    wire idle_o;
    always #5 clk_i <= ~clk_i;
    reg cache_wr_valid = 0;
    reg cache_wr_bank = 0;
    reg [9:0] cache_wr_addr = 0;
    reg [255:0] cache_wr_data = 0;
    wire [255:0] cache_data0;
    wire [255:0] cache_data1;
    reg [2047:0] weight_array;
    reg [2047:0] weight_output;
    bit checking = 0;
    integer cycle = 0;
    integer terms = 0;
    integer pairs = 0;
    integer commands = 0;
    integer read_done_count = 0;
    integer command_end_cycle = -100;
    integer last_issue_cycle = -100;
    integer last_pair_cycle = -100;
    integer previous_groups = 0;
    integer expected_start;
    bit expected_issue;
    bit sampled_pair_fire;
    bit sampled_half;
    bit sampled_enable;
    bit sampled_ready;
    bit sampled_cancel;
    reg [4:0] sampled_slot;
    reg [4:0] sampled_residual;
    reg [48:0] pair_tag;

    typedef struct packed {
        bit valid;
        bit first_term;
        bit last_term;
        bit command_first;
        bit command_last;
        bit half;
        integer accepted_cycle;
        integer k_count;
        reg [48:0] tag;
        reg [255:0] activation;
        reg [1:0] read_en;
        reg [9:0] addr0;
        reg [9:0] addr1;
        reg [10:0] weight_addr;
    } expected_t;
    expected_t waiting_terms[$];
    expected_t pipeline [0:4];
    expected_t candidate;

    edrv32_npu_window dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .cancel_i(cancel_i),
        .cfg_k3_i(cfg_k3_i),
        .cfg_s2_i(cfg_s2_i),
        .cfg_in_c4_i(cfg_in_c4_i),
        .cfg_half_tail_i(cfg_half_tail_i),
        .cfg_lut_en_i(cfg_lut_en_i),
        .cfg_res_en_i(cfg_res_en_i),
        .cfg_out_zp_i(cfg_out_zp_i),
        .cfg_in_w_i(cfg_in_w_i),
        .cfg_out_w_i(cfg_out_w_i),
        .cfg_cin_blocks_i(cfg_cin_blocks_i),
        .cfg_cout_blocks_i(cfg_cout_blocks_i),
        .cfg_k_count_i(cfg_k_count_i),
        .cmd_valid_i(cmd_valid_i),
        .cmd_ready_o(cmd_ready_o),
        .cmd_row_i(cmd_row_i),
        .cmd_block_i(cmd_block_i),
        .cmd_weight_base_i(cmd_weight_base_i),
        .cmd_row_base0_i(cmd_row_base0_i),
        .cmd_row_base1_i(cmd_row_base1_i),
        .cmd_row_base2_i(cmd_row_base2_i),
        .cmd_row_valid_i(cmd_row_valid_i),
        .issue_enable_i(issue_enable_i),
        .pair_ready_i(pair_ready_i),
        .pair_result_slot_i(pair_result_slot_i),
        .pair_residual_addr_i(pair_residual_addr_i),
        .pair_fire_o(pair_fire_o),
        .pair_half_o(pair_half_o),
        .cache_rd_en_o(cache_rd_en_o),
        .cache_rd_addr0_o(cache_rd_addr0_o),
        .cache_rd_addr1_o(cache_rd_addr1_o),
        .cache_rd_data0_i(cache_data0),
        .cache_rd_data1_i(cache_data1),
        .weight_rd_en_o(weight_rd_en_o),
        .weight_rd_addr_o(weight_rd_addr_o),
        .weight_rd_data_i(weight_output),
        .term_valid_o(term_valid_o),
        .term_first_o(term_first_o),
        .term_last_o(term_last_o),
        .term_tag_o(term_tag_o),
        .term_activation_o(term_activation_o),
        .term_weight_o(term_weight_o),
        .cmd_issued_o(cmd_issued_o),
        .cmd_issued_row_o(cmd_issued_row_o),
        .cmd_issued_block_o(cmd_issued_block_o),
        .cmd_read_done_o(cmd_read_done_o),
        .cmd_read_done_row_o(cmd_read_done_row_o),
        .cmd_read_done_block_o(cmd_read_done_block_o),
        .idle_o(idle_o)
    );

    edrv32_npu_line_cache u_cache (
        .clk_i(clk_i),
        .cache_wr_valid_i(cache_wr_valid),
        .cache_wr_bank_i(cache_wr_bank),
        .cache_wr_addr_i(cache_wr_addr),
        .cache_wr_data_i(cache_wr_data),
        .cache_rd_en_i(cache_rd_en_o),
        .cache_rd_addr0_i(cache_rd_addr0_o),
        .cache_rd_addr1_i(cache_rd_addr1_o),
        .cache_rd_data0_o(cache_data0),
        .cache_rd_data1_o(cache_data1)
    );

    function automatic [255:0] cache_pattern(input integer bank, input integer addr,
        input bit c4);
        for (integer j = 0; j < 32; j++)
            cache_pattern[8*j+:8] = (c4 && j % 16 >= 3) ?
                8'd0 : 8'(bank*73+addr*11+j*7);
    endfunction

    function automatic [2047:0] weight_pattern(input integer addr);
        for (integer j = 0; j < 256; j++) weight_pattern[8*j+:8] = 8'(addr*19+j*13);
    endfunction

    always @(posedge clk_i) begin
        if (weight_rd_en_o) weight_array <= weight_pattern(int'(weight_rd_addr_o));
        weight_output <= weight_array;
    end

    // Independent nested mathematical loops; no DUT internal signals are read.
    task automatic queue_command;
        expected_t e;
        bit half;
        bit d2;
        integer kernel;
        integer stride;
        integer effective_k;
        integer k;
        integer x;
        integer address;
        integer bank;
        integer row_base;
        reg [255:0] beat;
        reg [127:0] pixel;
        half = cfg_half_tail_i && int'(cmd_block_i) == int'(cfg_cout_blocks_i)-1;
        d2 = half && !cfg_in_c4_i;
        kernel = cfg_k3_i ? 3 : 1;
        stride = cfg_s2_i ? 2 : 1;
        effective_k = int'(cfg_k_count_i) / (d2 ? 2 : 1);
        for (integer pair = 0; pair < int'(cfg_out_w_i)/2; pair++) begin
            k = 0;
            for (integer ky = 0; ky < kernel; ky++) begin
                for (integer kx = 0; kx < kernel; kx++) begin
                    for (integer c16 = 0; c16 < (cfg_in_c4_i ? 1 : int'(cfg_cin_blocks_i));
                        c16++) begin
                        for (integer h = 0; h < ((d2 || cfg_in_c4_i) ? 1 : 2); h++) begin
                            e = '0;
                            e.valid = 1;
                            e.first_term = k == 0;
                            e.last_term = k == effective_k-1;
                            e.command_first = e.first_term && pair == 0;
                            e.command_last = e.last_term && pair == int'(cfg_out_w_i)/2-1;
                            e.accepted_cycle = cycle;
                            e.k_count = effective_k;
                            e.half = half;
                            e.tag = {d2, 10'd0, (pair == int'(cfg_out_w_i)/2-1),
                                cfg_out_zp_i, cfg_res_en_i, cfg_lut_en_i,
                                half, 11'(pair), cmd_block_i, cmd_row_i};
                            e.weight_addr = cmd_weight_base_i + 11'(k);
                            case (ky)
                                0: row_base = int'(cmd_row_base0_i);
                                1: row_base = int'(cmd_row_base1_i);
                                2: row_base = int'(cmd_row_base2_i);
                                default: row_base = 0;
                            endcase
                            for (integer p = 0; p < 2; p++) begin
                                x = (2*pair+p)*stride+kx-(cfg_k3_i ? 1 : 0);
                                if (cmd_row_valid_i[ky] && x >= 0 && x < int'(cfg_in_w_i)) begin
                                    bank = (x/2) % 2;
                                    address = row_base+c16*(int'(cfg_in_w_i)/4)+x/4;
                                    e.read_en[bank] = 1;
                                    if (bank == 0) e.addr0 = 10'(address);
                                    else e.addr1 = 10'(address);
                                    beat = cache_pattern(bank, address, cfg_in_c4_i);
                                    pixel = beat[128*(x%2)+:128];
                                    if (cfg_in_c4_i) e.activation[128*p+:32] = pixel[31:0];
                                    else if (d2) e.activation[128*p+:128] = pixel;
                                    else e.activation[128*p+:64] = pixel[64*h+:64];
                                end
                            end
                            waiting_terms.push_back(e);
                            k++;
                        end
                    end
                end
            end
        end
    endtask

    initial forever begin
        @(posedge clk_i);
        cycle++;
        sampled_pair_fire = pair_fire_o;
        sampled_half = pair_half_o;
        sampled_enable = issue_enable_i;
        sampled_ready = pair_ready_i;
        sampled_cancel = cancel_i;
        sampled_slot = pair_result_slot_i;
        sampled_residual = pair_residual_addr_i;
        for (integer stage = 4; stage > 0; stage--) pipeline[stage] = pipeline[stage-1];
        pipeline[0] = '0;
        if (checking && !sampled_cancel && cmd_valid_i && cmd_ready_o) queue_command();
        expected_issue = 0;
        if (checking && !sampled_cancel && waiting_terms.size() != 0) begin
            candidate = waiting_terms[0];
            expected_start = last_issue_cycle + 1;
            if (candidate.command_first) begin
                if (candidate.accepted_cycle+2 > expected_start)
                    expected_start = candidate.accepted_cycle+2;
                if (command_end_cycle+1 > expected_start) expected_start = command_end_cycle+1;
            end
            if (candidate.first_term) begin
                if (last_pair_cycle+previous_groups-candidate.k_count+1 > expected_start)
                    expected_start = last_pair_cycle+previous_groups-candidate.k_count+1;
                expected_issue = sampled_enable && sampled_ready && cycle >= expected_start;
            end else expected_issue = 1;
        end
        if (sampled_cancel) begin
            waiting_terms.delete();
            for (integer stage = 0; stage < 5; stage++) pipeline[stage] = '0;
            last_issue_cycle = -100;
            last_pair_cycle = -100;
            command_end_cycle = -100;
            previous_groups = 0;
        end
        #1;
        if (checking) begin
            if (weight_rd_en_o !== expected_issue) begin
                $fatal(1, "FAIL A1 schedule cycle=%0d expected=%b got=%b queued=%0d start=%0d",
                    cycle, expected_issue, weight_rd_en_o, waiting_terms.size(), expected_start);
            end
            if (sampled_pair_fire !== (expected_issue && candidate.first_term))
                $fatal(1, "FAIL pair reservation cycle=%0d", cycle);
            if (expected_issue) begin
                candidate = waiting_terms.pop_front();
                if (candidate.first_term) begin
                    pair_tag = candidate.tag;
                    pair_tag[42:38] = sampled_slot;
                    pair_tag[47:43] = sampled_residual;
                    pairs++;
                end
                candidate.tag = pair_tag;
                pipeline[0] = candidate;
                if (cache_rd_en_o !== candidate.read_en ||
                    (candidate.read_en[0] && cache_rd_addr0_o !== candidate.addr0) ||
                    (candidate.read_en[1] && cache_rd_addr1_o !== candidate.addr1) ||
                    weight_rd_addr_o !== candidate.weight_addr) begin
                    $fatal(1, "FAIL A1 cycle=%0d bank=%b/%b addr=%0d,%0d/%0d,%0d weight=%0d/%0d",
                        cycle, cache_rd_en_o, candidate.read_en, cache_rd_addr0_o,
                        cache_rd_addr1_o, candidate.addr0, candidate.addr1,
                        weight_rd_addr_o, candidate.weight_addr);
                end
                if (candidate.first_term && sampled_half !== candidate.half)
                    $fatal(1, "FAIL candidate half cycle=%0d", cycle);
                last_issue_cycle = cycle;
                if (candidate.last_term) begin
                    last_pair_cycle = cycle;
                    previous_groups = candidate.half ? 2 : 4;
                end
                if (candidate.command_last) command_end_cycle = cycle;
                terms++;
            end else if (cache_rd_en_o !== 0) $fatal(1, "FAIL stray cache read cycle=%0d", cycle);
            if (cmd_issued_o !== (pipeline[0].valid && pipeline[0].command_last))
                $fatal(1, "FAIL issued latency cycle=%0d", cycle);
            if (cmd_issued_o) begin
                if ({cmd_issued_block_o, cmd_issued_row_o} !== pipeline[0].tag[14:0])
                    $fatal(1, "FAIL issued tag cycle=%0d", cycle);
                commands++;
            end
            if (cmd_read_done_o !== (pipeline[2].valid && pipeline[2].command_last))
                $fatal(1, "FAIL read_done must be A1+2 cycle=%0d", cycle);
            if (cmd_read_done_o) begin
                if ({cmd_read_done_block_o, cmd_read_done_row_o} !== pipeline[2].tag[14:0])
                    $fatal(1, "FAIL read_done tag cycle=%0d", cycle);
                read_done_count++;
            end
            if (term_valid_o !== pipeline[4].valid)
                $fatal(1, "FAIL term must be A1+4 cycle=%0d", cycle);
            if (term_valid_o) begin
                if ({term_first_o, term_last_o, term_tag_o} !==
                    {pipeline[4].first_term, pipeline[4].last_term, pipeline[4].tag})
                    $fatal(1, "FAIL A5 tag cycle=%0d expected=%h got=%h", cycle,
                        pipeline[4].tag, term_tag_o);
                if (term_activation_o !== {4{pipeline[4].activation}})
                    $fatal(1, "FAIL A5 activation cycle=%0d expected=%h got=%h", cycle,
                        pipeline[4].activation, term_activation_o[255:0]);
                if (term_weight_o !== weight_pattern(int'(pipeline[4].weight_addr)))
                    $fatal(1, "FAIL A5 weight alignment cycle=%0d", cycle);
            end
        end
    end

    // Vary reservation payload continuously; a pair must keep its first-edge addresses.
    always @(negedge clk_i) begin
        pair_result_slot_i <= pair_result_slot_i + 5'd1;
        pair_residual_addr_i <= pair_residual_addr_i + 5'd2;
    end

    task automatic load_cache(input bit c4);
        for (integer a = 0; a < 1024; a++) begin
            for (integer b = 0; b < 2; b++) begin
                @(negedge clk_i);
                cache_wr_valid = 1;
                cache_wr_bank = 1'(b);
                cache_wr_addr = 10'(a);
                cache_wr_data = cache_pattern(b, a, c4);
            end
        end
        @(negedge clk_i);
        cache_wr_valid = 0;
    endtask

    task automatic configure(input bit k3, input bit s2, input bit c4, input bit half,
        input integer width, input integer cin, input [3:0] cout);
        wait (idle_o);
        if (cfg_in_c4_i != c4) load_cache(c4);
        @(negedge clk_i);
        cfg_k3_i = k3;
        cfg_s2_i = s2;
        cfg_in_c4_i = c4;
        cfg_half_tail_i = half;
        cfg_lut_en_i = !cfg_lut_en_i;
        cfg_res_en_i = !cfg_res_en_i;
        cfg_out_zp_i = cfg_out_zp_i + 8'd47;
        cfg_in_w_i = 12'(width);
        cfg_out_w_i = 12'(width/(s2 ? 2 : 1));
        cfg_cin_blocks_i = 6'(cin);
        cfg_cout_blocks_i = 4'(cout);
        cfg_k_count_i = 11'((c4 ? 1 : 2*cin)*(k3 ? 9 : 1));
    endtask

    task automatic send_command(input integer row, input integer block);
        integer input_y;
        integer row_slot;
        integer row_beats;
        @(negedge clk_i);
        cmd_valid_i = 1;
        cmd_row_i = 12'(row);
        cmd_block_i = 3'(block);
        cmd_weight_base_i = 11'(block*int'(cfg_k_count_i));
        row_beats = int'(cfg_cin_blocks_i)*int'(cfg_in_w_i)/4;
        cmd_row_valid_i = 0;
        for (integer ky = 0; ky < (cfg_k3_i ? 3 : 1); ky++) begin
            input_y = row*(cfg_s2_i ? 2 : 1)+ky-(cfg_k3_i ? 1 : 0);
            row_slot = input_y < 0 ? 0 : input_y % (cfg_k3_i ? 5 : 2);
            cmd_row_valid_i[ky] = input_y >= 0 && input_y < 6;
            case (ky)
                0: cmd_row_base0_i = 10'(row_slot*row_beats);
                1: cmd_row_base1_i = 10'(row_slot*row_beats);
                2: cmd_row_base2_i = 10'(row_slot*row_beats);
                default: begin end
            endcase
        end
        do @(posedge clk_i); while (!cmd_ready_o);
        #2;
        cmd_valid_i = 0;
    endtask

    task automatic finish_layer;
        wait (idle_o);
        @(negedge clk_i);
        if (waiting_terms.size() != 0) $fatal(1, "FAIL leftover expected terms");
        if (commands != read_done_count) $fatal(1, "FAIL unfinished cache commands");
    endtask

    initial begin
        repeat (3) @(negedge clk_i);
        rst_n_i = 1;
        issue_enable_i = 1;
        pair_ready_i = 1;
        load_cache(0);
        checking = 1;
        // Both strides/kernels, non-power-of-two width and all four pad sides.
        for (integer k3 = 0; k3 < 2; k3++) begin
            for (integer s2 = 0; s2 < 2; s2++) begin
                configure(1'(k3), 1'(s2), 0, 0, 12, 3, 2);
                for (integer row = 0; row < (s2 != 0 ? 3 : 6); row++) begin
                    for (integer b = 0; b < 2; b++) send_command(row, b);
                end
                finish_layer();
            end
        end
        // K=2 -> D2 K=1 -> K=2 repeatedly tests the PREVIOUS pair's 4/2 groups.
        configure(0, 0, 0, 1, 4, 1, 2);
        for (integer row = 0; row < 3; row++) begin
            send_command(row, 0);
            send_command(row, 1);
        end
        finish_layer();
        // D2 retains both C8 halves and uses several C16 planes.
        configure(1, 1, 0, 1, 12, 3, 2);
        for (integer row = 0; row < 3; row++) begin
            send_command(row, 0);
            send_command(row, 1);
        end
        finish_layer();
        for (integer half = 0; half < 2; half++) begin
            configure(1, 1, 1, 1'(half), 16, 1, 2);
            for (integer row = 0; row < 3; row++) begin
                send_command(row, 0);
                send_command(row, 1);
            end
            finish_layer();
        end
        configure(0, 0, 0, 1, 8, 2, 8);
        for (integer row = 0; row < 2; row++) begin
            for (integer block = 0; block < 8; block++) send_command(row, block);
        end
        finish_layer();
        // CP-02: use all five 204-item slots and both 512-item slots.
        configure(1, 1, 0, 0, 816, 1, 1);
        for (integer row = 0; row < 3; row++) send_command(row, 0);
        finish_layer();
        configure(0, 0, 0, 0, 64, 32, 1);
        send_command(0, 0);
        send_command(1, 0);
        finish_layer();
        // An accepted pair finishes while credit and execution entry are withdrawn.
        configure(1, 0, 0, 0, 8, 1, 1);
        send_command(0, 0);
        do @(posedge clk_i); while (!pair_fire_o);
        @(negedge clk_i);
        issue_enable_i = 0;
        pair_ready_i = 0;
        repeat (25) @(negedge clk_i);
        issue_enable_i = 1;
        pair_ready_i = 1;
        finish_layer();
        // Cancel discards contexts and all valid stages without changing RAM contents.
        send_command(0, 0);
        do @(posedge clk_i); while (!pair_fire_o);
        repeat (4) @(negedge clk_i);
        cancel_i = 1;
        @(negedge clk_i);
        cancel_i = 0;
        if (!idle_o) $fatal(1, "FAIL cancel did not clear local state");
        send_command(1, 0);
        finish_layer();
        $display("PASS window: %0d terms, %0d pairs, %0d commands; A3=+2 A5=+4",
            terms, pairs, commands);
        $finish;
    end
endmodule
