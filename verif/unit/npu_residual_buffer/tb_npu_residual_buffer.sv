// File: tb_npu_residual_buffer.sv
// Spec: npu-spec 2.3, 5.2, 5.5; datapath 4.2.2; OP-06/07, ER-05 local behavior.
// Description: Check ordered dual-bank scatter loads, reservation, early read release,
// exact two-edge returns, overlap and cancellation without resetting RAM contents.
// Clock: clk_npu test clock.
module tb_npu_residual_buffer;
    reg clk = 0;
    initial forever #5 clk = !clk;
    reg rst_n = 0;
    reg cancel = 0;
    reg begin_valid = 0;
    wire begin_ready;
    reg begin_bank = 0;
    reg [4:0] begin_pairs = 0;
    reg begin_half = 0;
    reg wr_valid = 0;
    reg wr_bank = 0;
    reg [3:0] wr_index = 0;
    reg [255:0] wr_data = 0;
    reg commit = 0;
    reg pair_half = 0;
    reg pair_reserve = 0;
    wire pair_ready;
    wire [4:0] pair_addr;
    reg rd_en = 0;
    reg [4:0] rd_addr = 0;
    wire rd_valid;
    wire [255:0] rd_data;
    wire idle;
    reg [255:0] memory [0:31];
    reg pending_valid = 0;
    reg [255:0] pending_data;
    integer reads = 0;

    edrv32_npu_residual_buffer dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .cancel_i(cancel),
        .residual_begin_valid_i(begin_valid),
        .residual_begin_ready_o(begin_ready),
        .residual_begin_bank_i(begin_bank),
        .residual_begin_pairs_i(begin_pairs),
        .residual_begin_half_i(begin_half),
        .residual_wr_valid_i(wr_valid),
        .residual_wr_bank_i(wr_bank),
        .residual_wr_index_i(wr_index),
        .residual_wr_data_i(wr_data),
        .residual_commit_i(commit),
        .pair_half_i(pair_half),
        .pair_reserve_i(pair_reserve),
        .pair_residual_ready_o(pair_ready),
        .pair_residual_addr_o(pair_addr),
        .residual_rd_en_i(rd_en),
        .residual_rd_addr_i(rd_addr),
        .residual_rd_valid_o(rd_valid),
        .residual_rd_data_o(rd_data),
        .idle_o(idle)
    );

    task automatic tick;
        reg expected_valid;
        reg [255:0] expected_data;
        begin
            @(posedge clk);
            expected_valid = rst_n && !cancel && pending_valid;
            expected_data = pending_data;
            pending_valid = rst_n && !cancel && rd_en;
            if (pending_valid) pending_data = memory[rd_addr];
            if (wr_valid && !cancel) memory[{wr_bank, wr_index}] = wr_data;
            #1;
            if (rd_valid !== expected_valid)
                $fatal(1, "FAIL residual valid expected=%b actual=%b t=%0t",
                    expected_valid, rd_valid, $time);
            if (expected_valid) begin
                reads++;
                if (rd_data !== expected_data)
                    $fatal(1, "FAIL residual data expected=%h actual=%h t=%0t",
                        expected_data, rd_data, $time);
            end
        end
    endtask

    task automatic load_begin(input bit bank, input integer unused_pairs, input bit half);
        begin
            begin_bank = bank;
            begin_pairs = 5'(unused_pairs);
            begin_half = half;
            begin_valid = 1;
            #1;
            if (!begin_ready) $fatal(1, "FAIL bank %0d should be free t=%0t", bank, $time);
            tick();
            begin_valid = 0;
            if (pair_ready) $fatal(1, "FAIL uncommitted batch was reservable t=%0t", $time);
        end
    endtask

    task automatic scatter(input bit bank, input integer unused_index, input integer value);
        begin
            wr_valid = 1;
            wr_bank = bank;
            wr_index = 4'(unused_index);
            for (integer byte_index = 0; byte_index < 32; byte_index++)
                wr_data[8*byte_index +: 8] = 8'(value + byte_index*7);
            tick();
            wr_valid = 0;
        end
    endtask

    task automatic reserve_pairs(input integer base, input integer pairs, input bit half);
        begin
            pair_half = half;
            for (integer p = 0; p < pairs; p++) begin
                #1;
                if (!pair_ready || pair_addr !== 5'(base + p*(half ? 1 : 2)))
                    $fatal(1, "FAIL pair address expected=%0d actual=%0d ready=%b t=%0t",
                        base + p*(half ? 1 : 2), pair_addr, pair_ready, $time);
                pair_reserve = 1;
                tick();
            end
            pair_reserve = 0;
        end
    endtask

    initial begin
        tick();
        tick();
        rst_n = 1;
        tick();
        if (!idle) $fatal(1, "FAIL reset idle");
        // Start with bank 1: consumption order cannot be inferred from bank number.
        load_begin(1, 8, 0);
        for (integer p = 0; p < 8; p++) scatter(1, 2*p, 40+p);
        for (integer p = 0; p < 8; p++) begin
            commit = (p == 7);
            scatter(1, 2*p+1, 120+p);
        end
        commit = 0;
        if (!pair_ready) $fatal(1, "FAIL commit did not expose head");
        // Load bank 0 while committed bank 1 is reserved and read.
        begin_bank = 0;
        begin_pairs = 16;
        begin_half = 1;
        begin_valid = 1;
        tick();
        begin_valid = 0;
        reserve_pairs(16, 8, 0);
        if (pair_ready) $fatal(1, "FAIL second bank must await commit");
        for (integer p = 15; p >= 0; p--) scatter(0, p, 180+p);
        commit = 1;
        tick();
        commit = 0;
        reserve_pairs(0, 16, 1);
        if (pair_ready || idle) $fatal(1, "FAIL reservations must retain RAM ownership");
        begin_bank = 1;
        #1;
        if (begin_ready) $fatal(1, "FAIL bank reused before final read");
        for (integer p = 0; p < 16; p++) begin
            rd_en = 1;
            rd_addr = 5'(16+p);
            tick();
            if (begin_ready !== (p == 15))
                $fatal(1, "FAIL ownership release edge p=%0d ready=%b t=%0t",
                    p, begin_ready, $time);
        end
        // Reload released bank while its final data is still returning from RAM.
        begin_valid = 1;
        begin_pairs = 1;
        begin_half = 1;
        rd_en = 1;
        rd_addr = 0;
        tick();
        begin_valid = 0;
        wr_valid = 1;
        wr_bank = 1;
        wr_index = 0;
        wr_data = {32{8'h35}};
        commit = 1;
        rd_addr = 1;
        tick();
        wr_valid = 0;
        commit = 0;
        for (integer p = 2; p < 16; p++) begin
            rd_addr = 5'(p);
            tick();
        end
        rd_en = 0;
        reserve_pairs(16, 1, 1);
        rd_en = 1;
        rd_addr = 16;
        tick();
        rd_en = 0;
        if (idle) $fatal(1, "FAIL idle before pending RAM response");
        tick();
        tick();
        if (!idle || reads != 33) $fatal(1, "FAIL drain reads=%0d idle=%b", reads, idle);

        // Cancel overrides commit, writes and reads, then restart without a RAM reset.
        load_begin(0, 1, 1);
        scatter(0, 0, 77);
        commit = 1;
        tick();
        commit = 0;
        reserve_pairs(0, 1, 1);
        rd_en = 1;
        rd_addr = 0;
        tick();
        cancel = 1;
        commit = 1;
        pair_reserve = 1;
        tick();
        cancel = 0;
        commit = 0;
        pair_reserve = 0;
        rd_en = 0;
        #1;
        if (!idle || pair_ready || !begin_ready) $fatal(1, "FAIL cancel control clear");
        load_begin(0, 1, 1);
        scatter(0, 0, 31);
        commit = 1;
        tick();
        commit = 0;
        reserve_pairs(0, 1, 1);
        rd_en = 1;
        rd_addr = 0;
        tick();
        rd_en = 0;
        tick();
        tick();
        if (!idle) $fatal(1, "FAIL restart idle");
        $display("PASS residual_buffer: scatter, ordered reservation, 2-edge reads, release, cancel");
        $finish;
    end
endmodule
