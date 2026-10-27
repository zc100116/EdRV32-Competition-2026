// File: tb_npu_datapath.sv
// Spec: npu-spec 2.1-2.3, 5.1, 5.4, 5.5; datapath design 4.2.
// Description: N-C1 port driver compares every output beat with npu_ref.py images.
// Includes command overlap, reservation stalls, residual batches and cancellation.
// Clock: clk_npu.
module tb_npu_datapath;
    logic clk_i = 0;
    logic rst_n_i = 0;
    logic cancel_i = 0;
    logic cfg_k3_i = 0;
    logic cfg_s2_i = 0;
    logic cfg_in_c4_i = 0;
    logic cfg_half_tail_i = 0;
    logic cfg_lut_en_i = 0;
    logic cfg_res_en_i = 0;
    logic [7:0] cfg_out_zp_i = 0;
    logic [11:0] cfg_in_w_i = 0;
    logic [11:0] cfg_out_w_i = 0;
    logic [5:0] cfg_cin_blocks_i = 0;
    logic [3:0] cfg_cout_blocks_i = 0;
    logic [10:0] cfg_k_count_i = 0;
    logic cmd_valid_i = 0;
    logic cmd_ready_o;
    logic [11:0] cmd_row_i = 0;
    logic [2:0] cmd_block_i = 0;
    logic [10:0] cmd_weight_base_i = 0;
    logic [9:0] cmd_row_base0_i = 0;
    logic [9:0] cmd_row_base1_i = 0;
    logic [9:0] cmd_row_base2_i = 0;
    logic [2:0] cmd_row_valid_i = 0;
    logic issue_enable_i = 0;
    logic cmd_issued_o;
    logic [11:0] cmd_issued_row_o;
    logic [2:0] cmd_issued_block_o;
    logic cmd_read_done_o;
    logic [11:0] cmd_read_done_row_o;
    logic [2:0] cmd_read_done_block_o;
    logic idle_o;
    logic cfg_valid_i = 0;
    logic cfg_ready_o;
    logic line_wr_valid_i = 0;
    logic line_wr_ready_o;
    logic line_wr_bank_i = 0;
    logic [9:0] line_wr_addr_i = 0;
    logic [255:0] line_wr_data_i = 0;
    logic line_wr_row_last_i = 0;
    logic line_wr_row_done_o;
    logic line_wr_idle_o;
    logic weight_wr_valid_i = 0;
    logic [13:0] weight_wr_addr_i = 0;
    logic [255:0] weight_wr_data_i = 0;
    logic quant_wr_valid_i = 0;
    logic [2:0] quant_wr_block_i = 0;
    logic [4:0] quant_wr_channel_i = 0;
    logic [31:0] quant_wr_bias_i = 0;
    logic [15:0] quant_wr_mult_i = 0;
    logic [5:0] quant_wr_shift_i = 0;
    logic lut_wr_valid_i = 0;
    logic [2:0] lut_wr_block_i = 0;
    logic [7:0] lut_wr_addr_i = 0;
    logic [7:0] lut_wr_data_i = 0;
    logic residual_begin_valid_i = 0;
    logic residual_begin_ready_o;
    logic residual_begin_bank_i = 0;
    logic [4:0] residual_begin_pairs_i = 0;
    logic residual_begin_half_i = 0;
    logic residual_wr_valid_i = 0;
    logic residual_wr_bank_i = 0;
    logic [3:0] residual_wr_index_i = 0;
    logic [255:0] residual_wr_data_i = 0;
    logic residual_commit_i = 0;
    logic [5:0] result_credit_o;
    logic result_chunk_valid_o;
    logic result_chunk_ready_i = 0;
    logic [4:0] result_chunk_base_o;
    logic [4:0] result_chunk_pairs_o;
    logic [11:0] result_chunk_row_o;
    logic [2:0] result_chunk_block_o;
    logic [10:0] result_chunk_pair_o;
    logic result_chunk_half_o;
    logic result_chunk_last_o;
    logic result_release_i = 0;
    logic result_rd_en_i = 0;
    logic [4:0] result_rd_index_i = 0;
    logic result_rd_plane_i = 0;
    logic result_rd_valid_o;
    logic [255:0] result_rd_data_o;
    logic cmd_done_o;
    logic [11:0] cmd_done_row_o;
    logic [2:0] cmd_done_block_o;
    logic mac_beat_o;

    edrv32_npu_datapath dut (
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
        .cmd_issued_o(cmd_issued_o),
        .cmd_issued_row_o(cmd_issued_row_o),
        .cmd_issued_block_o(cmd_issued_block_o),
        .cmd_read_done_o(cmd_read_done_o),
        .cmd_read_done_row_o(cmd_read_done_row_o),
        .cmd_read_done_block_o(cmd_read_done_block_o),
        .idle_o(idle_o),
        .cfg_valid_i(cfg_valid_i),
        .cfg_ready_o(cfg_ready_o),
        .line_wr_valid_i(line_wr_valid_i),
        .line_wr_ready_o(line_wr_ready_o),
        .line_wr_bank_i(line_wr_bank_i),
        .line_wr_addr_i(line_wr_addr_i),
        .line_wr_data_i(line_wr_data_i),
        .line_wr_row_last_i(line_wr_row_last_i),
        .line_wr_row_done_o(line_wr_row_done_o),
        .line_wr_idle_o(line_wr_idle_o),
        .weight_wr_valid_i(weight_wr_valid_i),
        .weight_wr_addr_i(weight_wr_addr_i),
        .weight_wr_data_i(weight_wr_data_i),
        .quant_wr_valid_i(quant_wr_valid_i),
        .quant_wr_block_i(quant_wr_block_i),
        .quant_wr_channel_i(quant_wr_channel_i),
        .quant_wr_bias_i(quant_wr_bias_i),
        .quant_wr_mult_i(quant_wr_mult_i),
        .quant_wr_shift_i(quant_wr_shift_i),
        .lut_wr_valid_i(lut_wr_valid_i),
        .lut_wr_block_i(lut_wr_block_i),
        .lut_wr_addr_i(lut_wr_addr_i),
        .lut_wr_data_i(lut_wr_data_i),
        .residual_begin_valid_i(residual_begin_valid_i),
        .residual_begin_ready_o(residual_begin_ready_o),
        .residual_begin_bank_i(residual_begin_bank_i),
        .residual_begin_pairs_i(residual_begin_pairs_i),
        .residual_begin_half_i(residual_begin_half_i),
        .residual_wr_valid_i(residual_wr_valid_i),
        .residual_wr_bank_i(residual_wr_bank_i),
        .residual_wr_index_i(residual_wr_index_i),
        .residual_wr_data_i(residual_wr_data_i),
        .residual_commit_i(residual_commit_i),
        .result_credit_o(result_credit_o),
        .result_chunk_valid_o(result_chunk_valid_o),
        .result_chunk_ready_i(result_chunk_ready_i),
        .result_chunk_base_o(result_chunk_base_o),
        .result_chunk_pairs_o(result_chunk_pairs_o),
        .result_chunk_row_o(result_chunk_row_o),
        .result_chunk_block_o(result_chunk_block_o),
        .result_chunk_pair_o(result_chunk_pair_o),
        .result_chunk_half_o(result_chunk_half_o),
        .result_chunk_last_o(result_chunk_last_o),
        .result_release_i(result_release_i),
        .result_rd_en_i(result_rd_en_i),
        .result_rd_index_i(result_rd_index_i),
        .result_rd_plane_i(result_rd_plane_i),
        .result_rd_valid_o(result_rd_valid_o),
        .result_rd_data_o(result_rd_data_o),
        .cmd_done_o(cmd_done_o),
        .cmd_done_row_o(cmd_done_row_o),
        .cmd_done_block_o(cmd_done_block_o),
        .mac_beat_o(mac_beat_o)
    );
    initial forever #5 clk_i = ~clk_i;
    logic [31:0] meta [0:19];
    logic [255:0] weights [0:9215];
    logic [63:0] params [0:255];
    logic [7:0] lut [0:2047];
    logic [255:0] inputs [0:8191];
    logic [255:0] residual [0:8191];
    logic [255:0] expected [0:8191];
    string case_path;
    int iw;
    int ih;
    int ow;
    int oh;
    int cin_blocks;
    int cout_blocks;
    int slot;
    int k_count;
    int output_planes;
    int command_count;
    int cycle = 0;
    int issued_count = 0;
    int read_count = 0;
    int done_count = 0;
    int pair_count = 0;
    int output_count = 0;
    int mac_count = 0;
    int full_cycles = 0;
    int overlap_count = 0;
    int row_overlap_count = 0;
    int block_overlap_count = 0;
    int previous_row = -1;
    int previous_block = -1;
    int issued_cycle [0:255];
    int last_cycle [0:31];
    int previous_last = -1;
    bit check_run = 0;
    logic [255:0] read_expected [0:1];
    logic [1:0] read_valid = 0;
    logic [12:0] read_expected_index = 0;
    int issued_row;
    int issued_block;
    int read_row;
    int read_block;
    int done_row;
    int done_block;

    // Observe the exact A1 acceptance edge and the WB2 RAM write edge.
    // Functional expected data comes exclusively from the independent Python model.
    initial forever begin
        @(posedge clk_i);
        cycle = cycle + 1;
        if (!cancel_i && check_run) begin
            if (dut.u_window.issue_w && dut.u_window.last_w) begin
                last_cycle[dut.u_window.tag_w[42:38]] = cycle;
                pair_count = pair_count + 1;
                if (dut.u_window.command_last_w) begin
                    previous_last = cycle;
                    previous_row = int'(dut.u_window.tag_w[11:0]);
                    previous_block = int'(dut.u_window.tag_w[14:12]);
                end
            end
            if (dut.pair_fire_w && dut.u_window.pair_r == 0 && previous_last >= 0) begin
                if (cycle - previous_last < 27) begin
                    overlap_count = overlap_count + 1;
                    if (int'(dut.u_window.tag_w[11:0]) != previous_row)
                        row_overlap_count = row_overlap_count + 1;
                    if (int'(dut.u_window.tag_w[14:12]) != previous_block)
                        block_overlap_count = block_overlap_count + 1;
                end
                previous_last = -1;
            end
            if (dut.writeback_valid_w) begin
                if (cycle - last_cycle[dut.writeback_tag_w[42:38]] !=
                    (dut.writeback_tag_w[26] ? 27 : 29)) begin
                    $fatal(1, "FAIL WB2 latency at %0d: actual=%0d expected=%0d", cycle,
                        cycle-last_cycle[dut.writeback_tag_w[42:38]],
                        dut.writeback_tag_w[26] ? 27 : 29);
                end
            end
            if (result_credit_o == 0) full_cycles = full_cycles + 1;
        end
        read_expected[1] = read_expected[0];
        if (result_rd_en_i) read_expected[0] = expected[read_expected_index];
        read_valid = {read_valid[0], result_rd_en_i && !cancel_i};
        #1;
        if (!cancel_i && check_run) begin
            if (cmd_issued_o) begin
                issued_row = issued_count / cout_blocks;
                issued_block = issued_count % cout_blocks;
                if (int'(cmd_issued_row_o) != issued_row ||
                    int'(cmd_issued_block_o) != issued_block)
                    $fatal(1, "FAIL issued tag actual=%0d/%0d expected=%0d/%0d at %0t",
                        cmd_issued_row_o, cmd_issued_block_o, issued_row, issued_block, $time);
                issued_cycle[issued_count] = cycle;
                issued_count = issued_count + 1;
            end
            if (cmd_read_done_o) begin
                read_row = read_count / cout_blocks;
                read_block = read_count % cout_blocks;
                if (int'(cmd_read_done_row_o) != read_row ||
                    int'(cmd_read_done_block_o) != read_block ||
                    cycle-issued_cycle[read_count] != 2)
                    $fatal(1, "FAIL read_done tag/latency at %0t", $time);
                read_count = read_count + 1;
            end
            if (cmd_done_o) begin
                done_row = done_count / cout_blocks;
                done_block = done_count % cout_blocks;
                if (int'(cmd_done_row_o) != done_row || int'(cmd_done_block_o) != done_block)
                    $fatal(1, "FAIL done tag actual=%0d/%0d expected=%0d/%0d at %0t",
                        cmd_done_row_o, cmd_done_block_o, done_row, done_block, $time);
                if (cycle-issued_cycle[done_count] !=
                    ((cfg_half_tail_i && done_block == cout_blocks-1) ? 27 : 29))
                    $fatal(1, "FAIL done latency at %0t", $time);
                done_count = done_count + 1;
            end
            if (mac_beat_o) mac_count = mac_count + 1;
            if (result_rd_valid_o !== read_valid[1])
                $fatal(1, "FAIL result read latency at %0t", $time);
            if (result_rd_valid_o) begin
                if (result_rd_data_o !== read_expected[1])
                    $fatal(1, "FAIL result at %0t expected=%064h actual=%064h",
                        $time, read_expected[1], result_rd_data_o);
                output_count = output_count + 1;
            end
        end
    end

    task automatic configure;
        @(negedge clk_i);
        cfg_valid_i = 1;
        cfg_k3_i = meta[0][4];
        cfg_s2_i = meta[0][5];
        cfg_lut_en_i = meta[0][6];
        cfg_res_en_i = meta[0][7];
        cfg_in_c4_i = meta[0][8];
        cfg_half_tail_i = meta[0][9];
        cfg_in_w_i = 12'(iw);
        cfg_out_w_i = 12'(ow);
        cfg_cin_blocks_i = 6'(cin_blocks);
        cfg_cout_blocks_i = 4'(cout_blocks);
        cfg_k_count_i = 11'(k_count);
        cfg_out_zp_i = meta[10][23:16];
        do @(posedge clk_i); while (!cfg_ready_o);
        @(negedge clk_i);
        cfg_valid_i = 0;
    endtask

    task automatic load_layer;
        logic [12:0] index;
        for (int i = 0; i < int'(meta[16]); i++) begin
            @(negedge clk_i);
            weight_wr_valid_i = 1;
            weight_wr_addr_i = 14'(i);
            weight_wr_data_i = weights[i];
        end
        @(negedge clk_i);
        weight_wr_valid_i = 0;
        for (int b = 0; b < cout_blocks; b++) begin
            for (int c = 0; c < 32; c++) begin
                @(negedge clk_i);
                quant_wr_valid_i = 1;
                quant_wr_block_i = 3'(b);
                quant_wr_channel_i = 5'(c);
                quant_wr_bias_i = params[b*32+c][31:0];
                quant_wr_mult_i = params[b*32+c][47:32];
                quant_wr_shift_i = params[b*32+c][53:48];
            end
        end
        @(negedge clk_i);
        quant_wr_valid_i = 0;
        for (int b = 0; b < cout_blocks; b++) begin
            for (int i = 0; i < 256; i++) begin
                @(negedge clk_i);
                lut_wr_valid_i = 1;
                lut_wr_block_i = 3'(b);
                lut_wr_addr_i = 8'(i);
                lut_wr_data_i = lut[b*256+i];
            end
        end
        @(negedge clk_i);
        lut_wr_valid_i = 0;
        // All rows here fit the specified five/two slots; each row is marked by row_done.
        for (int y = 0; y < ih; y++) begin
            for (int p = 0; p < (cfg_in_c4_i ? 1 : cin_blocks); p++) begin
                for (int j = 0; j < iw / (cfg_in_c4_i ? 8 : 2); j++) begin
                    @(negedge clk_i);
                    line_wr_valid_i = 1;
                    line_wr_bank_i = cfg_in_c4_i ? 1'b0 : 1'(j);
                    line_wr_addr_i = 10'(y*slot + (cfg_in_c4_i ? 2*j : p*(iw/4)+j/2));
                    index = 13'((p*ih+y)*(iw/(cfg_in_c4_i ? 8 : 2))+j);
                    line_wr_data_i = inputs[index];
                    line_wr_row_last_i = (p == (cfg_in_c4_i ? 0 : cin_blocks-1)) &&
                        (j == iw/(cfg_in_c4_i ? 8 : 2)-1);
                    do @(posedge clk_i); while (!line_wr_ready_o);
                end
            end
            @(negedge clk_i);
            line_wr_valid_i = 0;
            wait (line_wr_row_done_o);
        end
        @(negedge clk_i);
        line_wr_row_last_i = 0;
    endtask

    task automatic command(input int row, input int block);
        int source_row;
        @(negedge clk_i);
        cmd_valid_i = 1;
        cmd_row_i = 12'(row);
        cmd_block_i = 3'(block);
        cmd_weight_base_i = 11'(block*k_count);
        cmd_row_valid_i = 0;
        cmd_row_base0_i = 0;
        cmd_row_base1_i = 0;
        cmd_row_base2_i = 0;
        for (int ky = 0; ky < (cfg_k3_i ? 3 : 1); ky++) begin
            source_row = row*(cfg_s2_i ? 2 : 1)+ky-(cfg_k3_i ? 1 : 0);
            if (source_row >= 0 && source_row < ih) begin
                cmd_row_valid_i[ky] = 1;
                case (ky)
                    0: cmd_row_base0_i = 10'(source_row*slot);
                    1: cmd_row_base1_i = 10'(source_row*slot);
                    2: cmd_row_base2_i = 10'(source_row*slot);
                    default: $fatal(1, "FAIL TB ky");
                endcase
            end
        end
        do @(posedge clk_i); while (!cmd_ready_o);
        @(negedge clk_i);
        cmd_valid_i = 0;
    endtask

    task automatic commands;
        for (int y = 0; y < oh; y++) begin
            for (int b = 0; b < cout_blocks; b++) command(y, b);
        end
    endtask

    task automatic residual_loader;
        int bank;
        int count;
        int planes;
        logic [12:0] index;
        bank = 1;
        if (cfg_res_en_i) begin
            for (int y = 0; y < oh; y++) begin
                for (int b = 0; b < cout_blocks; b++) begin
                    planes = (cfg_half_tail_i && b == cout_blocks-1) ? 1 : 2;
                    for (int start = 0; start < ow/2; start += count) begin
                        count = ((ow/2-start) > (16/planes)) ? 16/planes : ow/2-start;
                        @(negedge clk_i);
                        residual_begin_valid_i = 1;
                        residual_begin_bank_i = 1'(bank);
                        residual_begin_pairs_i = 5'(count);
                        residual_begin_half_i = planes == 1;
                        do @(posedge clk_i); while (!residual_begin_ready_o);
                        @(negedge clk_i);
                        residual_begin_valid_i = 0;
                        // Plane-contiguous DDR returns scatter into pair/plane positions.
                        for (int p = 0; p < planes; p++) begin
                            for (int j = 0; j < count; j++) begin
                                @(negedge clk_i);
                                residual_wr_valid_i = 1;
                                residual_wr_bank_i = 1'(bank);
                                residual_wr_index_i = 4'(j*planes+p);
                                index = 13'(((2*b+p)*oh+y)*(ow/2)+start+j);
                                residual_wr_data_i = residual[index];
                                residual_commit_i = p == planes-1 && j == count-1;
                            end
                        end
                        @(negedge clk_i);
                        residual_wr_valid_i = 0;
                        residual_commit_i = 0;
                        bank = 1-bank;
                    end
                end
            end
        end
    endtask

    task automatic consume_results;
        int consumed;
        int expected_row;
        int expected_block;
        int expected_pair;
        int row;
        int block;
        int pair_index;
        int count;
        int base;
        int planes;
        bit last_chunk;
        logic [37:0] stalled_chunk;
        consumed = 0;
        expected_row = 0;
        expected_block = 0;
        expected_pair = 0;
        if (meta[18] != 0) begin
            wait (result_chunk_valid_o);
            stalled_chunk = {result_chunk_base_o, result_chunk_pairs_o, result_chunk_row_o,
                result_chunk_block_o, result_chunk_pair_o, result_chunk_half_o,
                result_chunk_last_o};
            repeat (meta[18]) begin
                @(negedge clk_i);
                if (!result_chunk_valid_o || stalled_chunk !==
                    {result_chunk_base_o, result_chunk_pairs_o, result_chunk_row_o,
                    result_chunk_block_o, result_chunk_pair_o, result_chunk_half_o,
                    result_chunk_last_o}) $fatal(1, "FAIL stalled chunk changed at %0t", $time);
            end
        end
        while (consumed < output_planes*oh*(ow/2)) begin
            @(negedge clk_i);
            result_chunk_ready_i = 1;
            do @(posedge clk_i); while (!result_chunk_valid_o);
            row = int'(result_chunk_row_o);
            block = int'(result_chunk_block_o);
            pair_index = int'(result_chunk_pair_o);
            count = int'(result_chunk_pairs_o);
            base = int'(result_chunk_base_o);
            planes = result_chunk_half_o ? 1 : 2;
            last_chunk = result_chunk_last_o;
            if (row != expected_row || block != expected_block || pair_index != expected_pair)
                $fatal(1, "FAIL chunk order: actual=%0d/%0d/%0d expected=%0d/%0d/%0d at %0t",
                    row, block, pair_index, expected_row, expected_block, expected_pair, $time);
            if (count != ((ow/2-pair_index > 16) ? 16 : ow/2-pair_index) ||
                (planes == 1) != (cfg_half_tail_i && block == cout_blocks-1))
                $fatal(1, "FAIL chunk shape at %0t", $time);
            if (last_chunk != (pair_index+count == ow/2))
                $fatal(1, "FAIL chunk last at %0t", $time);
            @(negedge clk_i);
            result_chunk_ready_i = 0;
            // A W holding register may wait arbitrarily before asking the RAM for more.
            for (int p = 0; p < planes; p++) begin
                for (int j = 0; j < count; j++) begin
                    @(negedge clk_i);
                    result_rd_en_i = 1;
                    result_rd_index_i = 5'(base+j);
                    result_rd_plane_i = 1'(p);
                    read_expected_index = 13'(((2*block+p)*oh+row)*(ow/2)+pair_index+j);
                end
            end
            @(negedge clk_i);
            result_rd_en_i = 0;
            repeat (2) @(negedge clk_i);
            result_release_i = 1;
            @(negedge clk_i);
            result_release_i = 0;
            consumed += count*planes;
            expected_pair += count;
            if (expected_pair == ow/2) begin
                expected_pair = 0;
                expected_block++;
                if (expected_block == cout_blocks) begin
                    expected_block = 0;
                    expected_row++;
                end
            end
        end
    endtask

    initial begin
        if (!$value$plusargs("CASE=%s", case_path)) $fatal(1, "FAIL missing +CASE");
        $readmemh({case_path, "/meta.hex"}, meta);
        $readmemh({case_path, "/weights.hex"}, weights);
        $readmemh({case_path, "/params.hex"}, params);
        $readmemh({case_path, "/lut.hex"}, lut);
        $readmemh({case_path, "/inputs.hex"}, inputs);
        $readmemh({case_path, "/residual.hex"}, residual);
        $readmemh({case_path, "/expected.hex"}, expected);
        iw = int'(meta[8][11:0]);
        ih = int'(meta[8][27:16]);
        ow = int'(meta[9][11:0]);
        oh = int'(meta[9][27:16]);
        cin_blocks = int'(meta[10][5:0]);
        cout_blocks = int'(meta[10][11:8]);
        slot = int'(meta[11][10:0]);
        k_count = int'(meta[11][26:16]);
        output_planes = int'(meta[17]);
        command_count = oh*cout_blocks;
        repeat (3) @(negedge clk_i);
        rst_n_i = 1;
        configure();
        load_layer();
        issue_enable_i = 1;
        if (meta[19] != 0) begin
            command(0, 0);
            repeat (18) @(negedge clk_i);
            cancel_i = 1;
            @(negedge clk_i);
            cancel_i = 0;
            if (!idle_o || result_credit_o != 32) $fatal(1, "FAIL cancel idle at %0t", $time);
            repeat (35) begin
                @(negedge clk_i);
                if (!idle_o || cmd_done_o || result_chunk_valid_o)
                    $fatal(1, "FAIL cancelled work returned at %0t", $time);
            end
            configure();
        end
        check_run = 1;
        fork
            commands();
            residual_loader();
            consume_results();
        join
        wait (idle_o);
        @(negedge clk_i);
        if (issued_count != command_count || read_count != command_count ||
            done_count != command_count || output_count != output_planes*oh*(ow/2))
            $fatal(1, "FAIL totals issued/read/done=%0d/%0d/%0d beats=%0d",
                issued_count, read_count, done_count, output_count);
        if (pair_count != command_count*(ow/2)) $fatal(1, "FAIL pair count");
        if (mac_count != oh*(ow/2)*(cout_blocks*k_count -
            ((cfg_half_tail_i && !cfg_in_c4_i) ? k_count/2 : 0)))
            $fatal(1, "FAIL mac beat count %0d", mac_count);
        if (meta[18] != 0 && full_cycles < 100) $fatal(1, "FAIL ring did not fill");
        if (!cfg_res_en_i && command_count > 1 && overlap_count == 0)
            $fatal(1, "FAIL no command overlap");
        if (!cfg_res_en_i && oh > 1 && row_overlap_count == 0)
            $fatal(1, "FAIL no row overlap");
        if (!cfg_res_en_i && cout_blocks > 1 && block_overlap_count == 0)
            $fatal(1, "FAIL no block overlap");
        if (!cfg_ready_o || !line_wr_idle_o || result_credit_o != 32)
            $fatal(1, "FAIL final ownership");
        $display("PASS datapath: %0d commands %0d pairs %0d beats %0d MAC beats",
            command_count, pair_count, output_count, mac_count);
        $display("latency dual=29 half=27; overlap=%0d (row=%0d block=%0d) full_cycles=%0d",
            overlap_count, row_overlap_count, block_overlap_count, full_cycles);
        $finish;
    end

    initial begin
        #2000000;
        $fatal(1, "FAIL simulation timeout at %0t", $time);
    end
endmodule
