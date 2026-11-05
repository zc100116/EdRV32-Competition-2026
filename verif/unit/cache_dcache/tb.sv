// File: cache_dcache/tb.sv
// Spec: cache-spec; cache-testplan 2.2.
// Description: Self-checking directed cache unit tests.
// Clock domain: clk_sys (PMA is combinational).
module tb;
    logic clk_i = 0;
    logic rst_n_i = 0;
    logic dc_early_valid_i = 0;
    logic [31:0] dc_early_addr_i = 0;
    wire dc_early_hit_o;
    wire [31:0] dc_early_data_o;
    wire [1:0] dc_early_way_hit_o;
    wire [63:0] dc_early_way_data_o;
    assign dc_early_hit_o = |dc_early_way_hit_o;
    assign dc_early_data_o =
        ({32{dc_early_way_hit_o[0]}} & dc_early_way_data_o[31:0]) |
        ({32{dc_early_way_hit_o[1]}} & dc_early_way_data_o[63:32]);
    logic dc_req_valid_i = 0;
    logic [31:0] dc_req_addr_i = 0;
    logic dc_req_store_i = 0;
    logic [1:0] dc_req_size_i = 0;
    logic dc_req_ready_o;
    logic dc_resp_valid_o;
    wire [31:0] dc_resp_data_o;
    wire [1:0] dc_resp_way_hit_o;
    wire [63:0] dc_resp_way_data_o;
    assign dc_resp_data_o =
        ({32{dc_resp_way_hit_o[0]}} & dc_resp_way_data_o[31:0]) |
        ({32{dc_resp_way_hit_o[1]}} & dc_resp_way_data_o[63:32]);
    logic dc_resp_err_o;
    logic dc_resp_device_o;
    logic dc_kill_i = 0;
    logic dc_commit_i = 0;
    logic [31:0] dc_store_data_i = 0;
    logic dc_fence_i = 0;
    logic dc_clean_all_i = 0;
    logic dc_fence_done_o;
    logic dc_wb_event_o;
    integer wb_events = 0;
    integer wb_bursts = 0;
    integer clock_cycles = 0;
    integer wb_begin_cycle = 0;
    integer wb_bus_cycles = 0;
    always @(posedge clk_i) begin
        clock_cycles <= clock_cycles + 1;
        if (dc_wb_event_o) wb_begin_cycle <= clock_cycles;
        if (dut.state_r == dut.S_WB_B && axi_bvalid_i)
            wb_bus_cycles <= wb_bus_cycles + clock_cycles - wb_begin_cycle + 1;
    end
    logic [3:0] axi_awid_o;
    logic [31:0] axi_awaddr_o;
    logic [7:0] axi_awlen_o;
    logic [2:0] axi_awsize_o;
    logic [1:0] axi_awburst_o;
    logic axi_awvalid_o;
    logic axi_awready_i = 0;
    logic [63:0] axi_wdata_o;
    logic [7:0] axi_wstrb_o;
    logic axi_wlast_o;
    logic axi_wvalid_o;
    logic axi_wready_i = 0;
    logic [3:0] axi_bid_i = 0;
    logic [1:0] axi_bresp_i = 0;
    logic axi_bvalid_i = 0;
    logic axi_bready_o;
    logic [3:0] axi_arid_o;
    logic [31:0] axi_araddr_o;
    logic [7:0] axi_arlen_o;
    logic [2:0] axi_arsize_o;
    logic [1:0] axi_arburst_o;
    logic axi_arvalid_o;
    logic axi_arready_i = 0;
    logic [3:0] axi_rid_i = 0;
    logic [63:0] axi_rdata_i = 0;
    logic [1:0] axi_rresp_i = 0;
    logic axi_rlast_i = 0;
    logic axi_rvalid_i = 0;
    logic axi_rready_o;
    logic maint_req_valid_i = 0;
    logic maint_req_ready_o;
    logic [2:0] maint_cmd_i = 0;
    logic [31:0] maint_addr_i = 0;
    logic [31:0] maint_size_i = 0;
    logic maint_busy_o;
    logic wb_err_o;
    logic [31:0] wb_err_addr_o;
    always #5 clk_i = ~clk_i;
    edrv32_dcache dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .rst_sys_dlru_n_i({2{rst_n_i}}),
        .dc_early_valid_i(dc_early_valid_i),
        .dc_early_addr_i(dc_early_addr_i),
        .dc_early_way_hit_o(dc_early_way_hit_o),
        .dc_early_way_data_o(dc_early_way_data_o),
        .dc_req_valid_i(dc_req_valid_i),
        .dc_req_addr_i(dc_req_addr_i),
        .dc_req_store_i(dc_req_store_i),
        .dc_req_size_i(dc_req_size_i),
        .dc_req_ready_o(dc_req_ready_o),
        .dc_resp_valid_o(dc_resp_valid_o),
        .dc_resp_way_data_o(dc_resp_way_data_o),
        .dc_resp_way_hit_o(dc_resp_way_hit_o),
        .dc_resp_err_o(dc_resp_err_o),
        .dc_resp_device_o(dc_resp_device_o),
        .dc_kill_i(dc_kill_i),
        .dc_commit_i(dc_commit_i),
        .dc_store_data_i(dc_store_data_i),
        .dc_fence_i(dc_fence_i),
        .dc_clean_all_i(dc_clean_all_i),
        .dc_fence_done_o(dc_fence_done_o),
        .dc_wb_event_o(dc_wb_event_o),
        .axi_awid_o(axi_awid_o),
        .axi_awaddr_o(axi_awaddr_o),
        .axi_awlen_o(axi_awlen_o),
        .axi_awsize_o(axi_awsize_o),
        .axi_awburst_o(axi_awburst_o),
        .axi_awvalid_o(axi_awvalid_o),
        .axi_awready_i(axi_awready_i),
        .axi_wdata_o(axi_wdata_o),
        .axi_wstrb_o(axi_wstrb_o),
        .axi_wlast_o(axi_wlast_o),
        .axi_wvalid_o(axi_wvalid_o),
        .axi_wready_i(axi_wready_i),
        .axi_bid_i(axi_bid_i),
        .axi_bresp_i(axi_bresp_i),
        .axi_bvalid_i(axi_bvalid_i),
        .axi_bready_o(axi_bready_o),
        .axi_arid_o(axi_arid_o),
        .axi_araddr_o(axi_araddr_o),
        .axi_arlen_o(axi_arlen_o),
        .axi_arsize_o(axi_arsize_o),
        .axi_arburst_o(axi_arburst_o),
        .axi_arvalid_o(axi_arvalid_o),
        .axi_arready_i(axi_arready_i),
        .axi_rid_i(axi_rid_i),
        .axi_rdata_i(axi_rdata_i),
        .axi_rresp_i(axi_rresp_i),
        .axi_rlast_i(axi_rlast_i),
        .axi_rvalid_i(axi_rvalid_i),
        .axi_rready_o(axi_rready_o),
        .maint_req_valid_i(maint_req_valid_i),
        .maint_req_ready_o(maint_req_ready_o),
        .maint_cmd_i(maint_cmd_i),
        .maint_addr_i(maint_addr_i),
        .maint_size_i(maint_size_i),
        .maint_busy_o(maint_busy_o),
        .wb_err_o(wb_err_o),
        .wb_err_addr_o(wb_err_addr_o)
    );
    // The event must also remain low for device writes and AW backpressure.
    always @(posedge clk_i) begin
        if (rst_n_i) begin
            if (dc_resp_err_o && !dc_resp_valid_o)
                $fatal(1, "FAIL D error without response time=%0t", $time);
            // P1 preserves the old error on every valid response cycle.
            if (dc_resp_err_o !== (dc_resp_valid_o &&
                (dut.early_response_r ? 1'b0 : dut.device_state_r == dut.D_RETURN ? dut.device_err_r :
                (dut.state_r == dut.S_RETURN ? dut.fill_err_r : dut.pma_err_w))))
                $fatal(1, "FAIL D effective error changed time=%0t", $time);
            if (dc_wb_event_o !== (axi_awvalid_o && axi_awready_i && axi_awlen_o == 3))
                $fatal(1, "FAIL writeback event timing");
            if (dc_wb_event_o) wb_events <= wb_events + 1;
            if (axi_awvalid_o && axi_awready_i && axi_awlen_o == 3)
                wb_bursts <= wb_bursts + 1;
        end
    end
    task automatic tick;
        @(posedge clk_i); #1;
    endtask
    task automatic step;
        @(negedge clk_i); #1;
    endtask
    initial begin
        #2000000;
        $fatal(1, "FAIL timeout");
    end
    logic [63:0] memory [0:8191];
    logic read_active = 0;
    logic [12:0] read_idx;
    logic [7:0] read_left;
    integer reads = 0;
    integer writes = 0;
    assign axi_arready_i = !read_active;
    assign axi_rvalid_i = read_active;
    assign axi_rdata_i = memory[read_idx];
    assign axi_rlast_i = read_left == 0;
    assign axi_rresp_i = 0;
    assign axi_rid_i = 0;
    always @(posedge clk_i) begin
        if (axi_arvalid_o && axi_arready_i) begin
            if (axi_arid_o != 0 || axi_arburst_o != 1) $fatal(1, "FAIL read attributes");
            read_active <= 1;
            read_idx <= axi_araddr_o[15:3];
            read_left <= axi_arlen_o;
            reads <= reads + 1;
        end else if (axi_rvalid_i && axi_rready_o) begin
            read_idx <= read_idx + 1;
            read_left <= read_left - 1;
            if (read_left == 0) read_active <= 0;
        end
    end
    integer reads_before;
    logic write_active = 0;
    logic allow_aw = 1;
    logic [12:0] write_idx;
    logic [7:0] write_left;
    assign axi_awready_i = allow_aw && !write_active && !axi_bvalid_i;
    assign axi_wready_i = write_active;
    assign axi_bid_i = 0;
    assign axi_bresp_i = 0;
    always @(posedge clk_i) begin
        if (axi_awvalid_o && axi_awready_i) begin
            if (axi_awid_o != 0 || axi_awburst_o != 1) $fatal(1, "FAIL write attributes");
            write_active <= 1;
            write_idx <= axi_awaddr_o[15:3];
            write_left <= axi_awlen_o;
            writes <= writes + 1;
        end
        if (axi_wvalid_o && axi_wready_i) begin
            if (axi_wlast_o != (write_left == 0)) $fatal(1, "FAIL WLAST");
            for (int b = 0; b < 8; b++) begin
                if (axi_wstrb_o[b]) memory[write_idx][8*b +: 8] <= axi_wdata_o[8*b +: 8];
            end
            write_idx <= write_idx + 1;
            write_left <= write_left - 1;
            if (write_left == 0) begin
                write_active <= 0;
                axi_bvalid_i <= 1;
            end
        end else if (axi_bvalid_i && axi_bready_o) axi_bvalid_i <= 0;
    end
    task automatic access_word(input logic [31:0] addr, input logic store_access,
                               input logic [1:0] size, input logic [31:0] data);
        step(); dc_req_valid_i = 1; dc_req_addr_i = addr;
        dc_req_store_i = store_access; dc_req_size_i = size; #1;
        while (!dc_req_ready_o) tick();
        tick(); step(); dc_req_valid_i = 0;
        if (dc_resp_device_o) begin
            dc_commit_i = 1; dc_store_data_i = data;
            tick(); step(); dc_commit_i = 0;
        end
        while (!dc_resp_valid_o) tick();
        if (dc_resp_err_o) $fatal(1, "FAIL D error %h", addr);
        if (!store_access && dc_resp_data_o !== data)
            $fatal(1, "FAIL D %h expected %h got %h", addr, data, dc_resp_data_o);
        if (store_access && !dc_resp_device_o) begin
            step(); dc_commit_i = 1; dc_store_data_i = data;
            tick(); step(); dc_commit_i = 0;
        end
        tick();
    endtask
    task automatic maintenance(input logic [2:0] cmd, input logic [31:0] addr,
                               input logic [31:0] size);
        step(); maint_cmd_i = cmd; maint_addr_i = addr; maint_size_i = size;
        maint_req_valid_i = 1;
        while (!maint_req_ready_o) tick();
        begin
            time started;
            int before_bursts;
            int before_bus_cycles;
            started = $time;
            before_bursts = wb_bursts;
            before_bus_cycles = wb_bus_cycles;
            tick(); step(); maint_req_valid_i = 0;
            while (maint_busy_o) tick();
            if ($test$plusargs("MAINT_PERF"))
                $display("PERF cmd=%0d addr=%h size=%0d cycles=%0d writes=%0d wb_cycles=%0d",
                         cmd, addr, size, int'(($time-started-4)/10),
                         wb_bursts-before_bursts, wb_bus_cycles-before_bus_cycles);
        end
    endtask
    // Compare externally visible bus traces with/without discarded early queries.
    logic compare_active = 0;
    int compare_phase = 0;
    int ar_count = 0;
    int aw_count = 0;
    int w_count = 0;
    int ar_expected;
    int aw_expected;
    int w_expected;
    logic [31:0] ar_reference[0:31];
    logic [31:0] aw_reference[0:31];
    logic [71:0] w_reference[0:127];
    always @(posedge clk_i) begin
        if (compare_active) begin
            if (axi_arvalid_o && axi_arready_i) begin
                if (compare_phase == 0) ar_reference[ar_count] = axi_araddr_o;
                else if (ar_reference[ar_count] != axi_araddr_o)
                    $fatal(1,"FAIL early query changed AR sequence index=%0d",ar_count);
                ar_count++;
            end
            if (axi_awvalid_o && axi_awready_i) begin
                if (compare_phase == 0) aw_reference[aw_count] = axi_awaddr_o;
                else if (aw_reference[aw_count] != axi_awaddr_o)
                    $fatal(1,"FAIL early query changed AW sequence index=%0d",aw_count);
                aw_count++;
            end
            if (axi_wvalid_o && axi_wready_i) begin
                if (compare_phase == 0) w_reference[w_count] = {axi_wstrb_o,axi_wdata_o};
                else if (w_reference[w_count] != {axi_wstrb_o,axi_wdata_o})
                    $fatal(1,"FAIL early query changed W sequence index=%0d",w_count);
                w_count++;
            end
        end
    end
    task automatic discarded_query(input logic [31:0] address,
                                   input logic expected_hit,
                                   input logic [31:0] expected_data);
        logic [19:0] tags0[0:511];
        logic [19:0] tags1[0:511];
        logic [511:0] lru;
        int before_reads;
        int before_writes;
        for (int i=0;i<512;i++) begin
            tags0[i]=dut.u_tag0.memory_r[i];
            tags1[i]=dut.u_tag1.memory_r[i];
        end
        lru=dut.lru_r; before_reads=reads; before_writes=writes;
        step(); dc_early_valid_i=1; dc_early_addr_i=address;
        tick();
        if (dc_early_hit_o !== expected_hit ||
            (expected_hit && dc_early_data_o !== expected_data))
            $fatal(1,"FAIL early query address=%h hit=%b/%b data=%h/%h",
                address,dc_early_hit_o,expected_hit,dc_early_data_o,expected_data);
        step(); dc_early_valid_i=0; dc_kill_i=1;
        tick(); step(); dc_kill_i=0; tick();
        for (int i=0;i<512;i++)
            if (tags0[i] !== dut.u_tag0.memory_r[i] || tags1[i] !== dut.u_tag1.memory_r[i])
                $fatal(1,"FAIL early query modified tag/dirty/valid group=%0d",i);
        if (lru !== dut.lru_r || reads != before_reads || writes != before_writes ||
            dut.buffer_valid_r || dut.store_pending_r || dut.state_r != dut.S_IDLE)
            $fatal(1,"FAIL discarded query changed cache state/bus address=%h",address);
    endtask
    task automatic check_early_queries;
        // Identical ordinary accesses must retain the same replacement and bus trace.
        for (int phase=0;phase<2;phase++) begin
            step(); rst_n_i=0; tick(); step(); rst_n_i=1;
            repeat(512) tick();
            memory[512]=64'h1122334400001234;
            memory[2560]=64'h5566778800005678;
            memory[4608]=64'h99aabbcc00009abc;
            compare_phase=phase; ar_count=0; aw_count=0; w_count=0; compare_active=1;
            access_word(32'h10001000,0,2,32'h1234);
            access_word(32'h10005000,0,2,32'h5678);
            access_word(32'h10001000,1,2,32'hdeadbeef);
            tick();
            if (phase==1) begin
                discarded_query(32'h10005000,1,32'h5678);
                discarded_query(32'h10009000,0,0);
                discarded_query(32'h40000000,0,0);
            end
            access_word(32'h10009000,0,2,32'h9abc);
            access_word(32'h10001000,0,2,32'hdeadbeef);
            maintenance(4,0,0);
            compare_active=0;
            if (phase==0) begin
                ar_expected=ar_count; aw_expected=aw_count; w_expected=w_count;
            end else if (ar_count!=ar_expected || aw_count!=aw_expected || w_count!=w_expected)
                $fatal(1,"FAIL early query changed transaction counts AR=%0d AW=%0d W=%0d",
                    ar_count,aw_count,w_count);
        end
        // Successful E requests reuse data while the port reads the next D load.
        step(); dc_early_valid_i=1; dc_early_addr_i=32'h10001000;
        tick();
        if (!dc_early_hit_o) $fatal(1,"FAIL early chain first hit");
        step(); dc_req_valid_i=1; dc_req_store_i=0; dc_req_size_i=2;
        dc_req_addr_i=32'h10001000; dc_early_addr_i=32'h10009000;
        #1;
        if (!dut.early_promote_w || dut.read_addr_w != 11'h200)
            $fatal(1,"FAIL early promotion did not free RAM port");
        tick();
        if (!dc_resp_valid_o || dc_resp_data_o!=32'hdeadbeef || !dc_early_hit_o)
            $fatal(1,"FAIL early chain first response/second query");
        step(); dc_commit_i=1; dc_req_addr_i=32'h10009000; dc_early_valid_i=0;
        tick();
        if (!dc_resp_valid_o || dc_resp_data_o!=32'h9abc)
            $fatal(1,"FAIL early chain second response");
        step(); dc_req_valid_i=0; dc_commit_i=0; tick();
        // A normal store wins the port, and pending stores forbid early same-word data.
        step(); dc_req_valid_i=1; dc_req_store_i=1; dc_req_addr_i=32'h10001000;
        dc_early_valid_i=1; dc_early_addr_i=32'h10001000;
        tick();
        if (dc_early_hit_o) $fatal(1,"FAIL ordinary request priority");
        step(); dc_req_valid_i=0;
        tick();
        if (dc_early_hit_o) $fatal(1,"FAIL pending store early conflict");
        step(); dc_commit_i=1; dc_store_data_i=32'hcafebabe;
        tick();
        if (dc_early_hit_o) $fatal(1,"FAIL committed buffer early conflict");
        step(); dc_commit_i=0; dc_early_valid_i=0; tick(); tick();
        access_word(32'h10001000,0,2,32'hcafebabe);
        $display("PASS early query readonly/promotion/store-conflict");
    endtask
    initial begin
        for (int i = 0; i < 8192; i++) memory[i] = {32'(i+8192), 32'(i+4096)};
        // DC-16, cache-spec 5.5: arbitrary metadata, interrupted scan and restart.
        for (int i = 0; i < 512; i++) begin
            dut.u_tag0.memory_r[i] = 20'hc0000 | 20'($urandom_range(0, 262143));
            dut.u_tag1.memory_r[i] = 20'hc0000 | 20'($urandom_range(0, 262143));
        end
        tick(); step(); rst_n_i = 1;
        repeat (129) begin
            if (dc_req_ready_o || maint_req_ready_o) $fatal(1, "FAIL early init ready");
            tick();
        end
        step(); rst_n_i = 0; tick(); step(); rst_n_i = 1;
        dc_req_valid_i = 1; dc_req_addr_i = 32'h10000000;
        maint_req_valid_i = 1; maint_cmd_i = 4;
        for (int i = 0; i < 512; i++) begin
            if (dc_req_ready_o || maint_req_ready_o || maint_busy_o)
                $fatal(1, "FAIL initialization accepted request cycle=%0d", i);
            tick();
        end
        if (!dc_req_ready_o || !maint_req_ready_o)
            $fatal(1, "FAIL initialization exceeds 512 cycles");
        step(); dc_req_valid_i = 0; maint_req_valid_i = 0;
        for (int i = 0; i < 512; i++) begin
            if (dut.u_tag0.memory_r[i][19:18] != 0 ||
                dut.u_tag1.memory_r[i][19:18] != 0)
                $fatal(1, "FAIL initialization metadata group=%0d", i);
        end
        if (reads != 0 || writes != 0) $fatal(1, "FAIL initialization bus activity");
        $display("PASS DC-16 initialization=512 restart=512");
        if ($test$plusargs("MAINT_PERF")) begin
            int capacity;
            int lengths[5] = '{1,16,128,512,2048};
            capacity = 1024;
            if ($value$plusargs("CACHE_LINES=%d", capacity)) begin end
            for (int n = 0; n < 5; n++) maintenance(1, 32'h10000000, 32'(lengths[n]*32));
            maintenance(4, 0, 0);
            access_word(32'h10000000, 1, 2, 32'h12345678);
            maintenance(4, 0, 0);
            access_word(32'h10003fe0, 1, 2, 32'h87654321);
            maintenance(4, 0, 0);
            for (int n = 0; n < capacity; n++)
                access_word(32'h10000000 + 32'(n*32), 1, 2, 32'habcdef00 + 32'(n));
            maintenance(4, 0, 0);
            $display("PASS maintenance_perf capacity=%0d", capacity);
            $finish;
        end
        access_word(32'h10000000, 0, 2, 4096);
        if (reads != 1 || dut.lru_r[0] != 1) $fatal(1, "FAIL D cold fill LRU");
        access_word(32'h10004000, 0, 2, 6144);
        if (reads != 2 || dut.lru_r[0] != 0) $fatal(1, "FAIL D second fill LRU");
        access_word(32'h10000000, 1, 2, 32'hdeadbeef);
        access_word(32'h10000000, 0, 2, 32'hdeadbeef);
        if (reads != 2 || dut.lru_r[0] != 1) $fatal(1, "FAIL D hit LRU");
        access_word(32'h10004000, 0, 2, 6144);
        allow_aw = 0;
        fork
            access_word(32'h10008000, 0, 2, 8192);
            begin
                wait (axi_awvalid_o);
                repeat (3) tick();
                if (wb_events != 0) $fatal(1, "FAIL event before AW handshake");
                step(); allow_aw = 1;
            end
        join
        if (reads != 3 || writes != 1 || memory[0][31:0] != 32'hdeadbeef)
            $fatal(1, "FAIL D dirty victim writes=%0d memory=%h", writes, memory[0]);
        access_word(32'h10008005, 1, 0, 32'haa);
        access_word(32'h10008004, 0, 2, 32'h0000aa00);
        maintenance(3, 32'h10008001, 1);
        if (writes != 2 || memory[4096][63:32] != (32'h0000aa00))
            $fatal(1, "FAIL maintenance clean/invalidate");
        access_word(32'h10008000, 0, 2, 8192);
        if (reads != 4) $fatal(1, "FAIL invalidate miss");
        access_word(32'h40000003, 1, 0, 32'h5a);
        access_word(32'h40000000, 0, 2, 32'h5aadbeef);
        // Four successive stores retire without a gap; the final write forwards
        // across a simultaneous RAM read/write collision.
        step(); dc_req_valid_i = 1; dc_req_store_i = 1; dc_req_size_i = 2;
        dc_req_addr_i = 32'h10008000;
        tick();
        for (int n = 0; n < 4; n++) begin
            if (!dc_resp_valid_o || !dc_req_ready_o) $fatal(1, "FAIL store throughput");
            step(); dc_commit_i = 1; dc_store_data_i = 32'h11223300 + 32'(n);
            dc_req_addr_i = 32'h10008000 + 32'((n+1)*4);
            if (n == 3) dc_req_valid_i = 0;
            tick();
        end
        step(); dc_commit_i = 0; dc_req_valid_i = 1; dc_req_store_i = 0;
        dc_req_addr_i = 32'h1000800c;
        tick();
        if (!dc_resp_valid_o || dc_resp_data_o != 32'h11223303)
            $fatal(1, "FAIL buffer drain forwarding got=%h", dc_resp_data_o);
        step(); dc_req_valid_i = 0; tick();
        // A byte store committed with a same-word load must merge into RAM data.
        step(); dc_req_valid_i = 1; dc_req_store_i = 1; dc_req_size_i = 0;
        dc_req_addr_i = 32'h1000800d; tick();
        step(); dc_commit_i = 1; dc_store_data_i = 32'haa;
        dc_req_addr_i = 32'h1000800c; dc_req_store_i = 0; dc_req_size_i = 2;
        tick();
        if (!dc_resp_valid_o || dc_resp_data_o != 32'h1122aa03)
            $fatal(1, "FAIL partial buffer forwarding got=%h", dc_resp_data_o);
        step(); dc_req_valid_i = 0; dc_commit_i = 0; tick();
        // Device polling remains live while the array walker is busy.
        step(); maint_cmd_i = 4; maint_req_valid_i = 1;
        while (!maint_req_ready_o) tick();
        tick(); step(); maint_req_valid_i = 0;
        dc_req_addr_i = 32'h10008000; #1;
        if (!dc_req_ready_o || !maint_busy_o) $fatal(1, "FAIL maintenance request ready");
        access_word(32'h40000000, 0, 2, 32'h5aadbeef);
        while (maint_busy_o) tick();
        if (memory[4097] != 64'h1122aa0311223302)
            $fatal(1, "FAIL clean data %h", memory[4097]);
        // cache-spec 5.4: an empty range finishes immediately. A simultaneous
        // accepted cached hit retains the next-cycle latency from 5.2.
        step(); maint_cmd_i = 1; maint_size_i = 0; maint_req_valid_i = 1;
        dc_req_valid_i = 1; dc_req_addr_i = 32'h1000800c;
        dc_req_store_i = 0; dc_req_size_i = 2;
        #1;
        if (!dc_req_ready_o || !maint_req_ready_o)
            $fatal(1, "FAIL empty maintenance simultaneous acceptance");
        tick();
        if (maint_busy_o || !dc_resp_valid_o || dc_resp_data_o != 32'h1122aa03)
            $fatal(1, "FAIL empty maintenance hit latency/data got=%h", dc_resp_data_o);
        step(); maint_req_valid_i = 0; dc_req_valid_i = 0; tick();
        // FENCE.I is a held request and completes once.
        access_word(32'h10008000, 1, 2, 32'h12345678);
        step(); dc_clean_all_i = 1;
        while (!dc_fence_done_o) tick();
        tick();
        if (maint_busy_o) $fatal(1, "FAIL clean request repeated");
        step(); dc_clean_all_i = 0;
        maintenance(4, 0, 0);
        if (wb_events != wb_bursts || wb_events != 4)
            $fatal(1, "FAIL WB count events=%0d bursts=%0d", wb_events, wb_bursts);
        // A PMA error must drop with response valid even though the registered address retains its PMA error.
        step(); dc_req_valid_i = 1; dc_req_addr_i = 32'h50000000;
        tick();
        if (!dc_resp_valid_o || !dc_resp_err_o) $fatal(1, "FAIL D PMA response");
        step(); dc_req_valid_i = 0; tick();
        if (dc_resp_valid_o || dc_resp_err_o) $fatal(1, "FAIL D stale PMA error");
        // C-F1 path 6: an unaligned two-byte range crosses a tag/set boundary;
        // an aligned exclusive end must leave the following line cached.
        access_word(32'h10003fe0, 0, 2, 32'(4096 + 2044));
        access_word(32'h10004000, 0, 2, 32'(4096 + 2048));
        access_word(32'h10004020, 0, 2, 32'(4096 + 2052));
        reads_before = reads;
        maintenance(2, 32'h10003fff, 2);
        access_word(32'h10004020, 0, 2, 32'(4096 + 2052));
        if (reads != reads_before) $fatal(1, "FAIL range invalidated following line");
        access_word(32'h10003fe0, 0, 2, 32'(4096 + 2044));
        access_word(32'h10004000, 0, 2, 32'(4096 + 2048));
        if (reads != reads_before + 2) $fatal(1, "FAIL range missed boundary lines");
        maintenance(2, 32'h10004000, 32);
        access_word(32'h10004020, 0, 2, 32'(4096 + 2052));
        if (reads != reads_before + 2) $fatal(1, "FAIL range end was not exclusive");
        access_word(32'h10004000, 0, 2, 32'(4096 + 2048));
        if (reads != reads_before + 3) $fatal(1, "FAIL range did not invalidate first line");
        // A store drains on the same acceptance edge as a conflicting miss.
        // The dirty snapshot must include that drain, while LRU bypass selects A.
        begin : dirty_drain_snapshot
            int before_writes;
            logic [31:0] expected_c;
            maintenance(2, 32'h10000000, 65536);
            access_word(32'h10000000, 0, 2, memory[0][31:0]);
            access_word(32'h10004000, 0, 2, memory[2048][31:0]);
            before_writes = writes;
            expected_c = memory[4096][31:0];
            step(); dc_req_valid_i = 1; dc_req_addr_i = 32'h10000000;
            dc_req_store_i = 1; dc_req_size_i = 2;
            tick();
            if (!dc_resp_valid_o) $fatal(1, "FAIL drain store hit");
            step(); dc_commit_i = 1; dc_store_data_i = 32'hf00d1234;
            dc_req_addr_i = 32'h10004000; dc_req_store_i = 0;
            tick();
            if (!dc_resp_valid_o) $fatal(1, "FAIL drain LRU hit");
            step(); dc_commit_i = 0; dc_req_addr_i = 32'h10008000;
            tick();
            if (dc_resp_valid_o) $fatal(1, "FAIL drain conflict expected miss");
            step(); dc_req_valid_i = 0;
            while (!dc_resp_valid_o) tick();
            if (dc_resp_data_o != expected_c || writes != before_writes + 1 ||
                memory[0][31:0] != 32'hf00d1234)
                $fatal(1, "FAIL drained store lost on miss writes=%0d expected=%0d data=%h",
                       writes, before_writes+1, memory[0][31:0]);
            tick();
        end
        check_early_queries();
        $display("PASS cache_dcache WB events=%0d", wb_events); $finish;
    end
endmodule
