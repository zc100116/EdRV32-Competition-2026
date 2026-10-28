// File: cache_dcache/tb.sv
// Spec: cache-spec; cache-testplan 2.2.
// Description: Self-checking directed cache unit tests.
// Clock domain: clk_sys (PMA is combinational).
module tb;
    logic clk_i = 0;
    logic rst_n_i = 0;
    logic dc_req_valid_i = 0;
    logic [31:0] dc_req_addr_i = 0;
    logic dc_req_store_i = 0;
    logic [1:0] dc_req_size_i = 0;
    logic dc_req_ready_o;
    logic dc_resp_valid_o;
    logic [31:0] dc_resp_data_o;
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
        .dc_req_valid_i(dc_req_valid_i),
        .dc_req_addr_i(dc_req_addr_i),
        .dc_req_store_i(dc_req_store_i),
        .dc_req_size_i(dc_req_size_i),
        .dc_req_ready_o(dc_req_ready_o),
        .dc_resp_valid_o(dc_resp_valid_o),
        .dc_resp_data_o(dc_resp_data_o),
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
                (dut.device_state_r == dut.D_RETURN ? dut.device_err_r :
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
        #200000;
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
        tick(); step(); maint_req_valid_i = 0;
        while (maint_busy_o) tick();
    endtask
    initial begin
        for (int i = 0; i < 8192; i++) memory[i] = {32'(i+8192), 32'(i+4096)};
        tick(); step(); rst_n_i = 1;
        access_word(32'h10000000, 0, 2, 4096);
        if (reads != 1 || dut.lru_r[0] != 1) $fatal(1, "FAIL D cold fill LRU");
        access_word(32'h10001000, 0, 2, 4608);
        if (reads != 2 || dut.lru_r[0] != 0) $fatal(1, "FAIL D second fill LRU");
        access_word(32'h10000000, 1, 2, 32'hdeadbeef);
        access_word(32'h10000000, 0, 2, 32'hdeadbeef);
        if (reads != 2 || dut.lru_r[0] != 1) $fatal(1, "FAIL D hit LRU");
        access_word(32'h10001000, 0, 2, 4608);
        allow_aw = 0;
        fork
            access_word(32'h10002000, 0, 2, 5120);
            begin
                wait (axi_awvalid_o);
                repeat (3) tick();
                if (wb_events != 0) $fatal(1, "FAIL event before AW handshake");
                step(); allow_aw = 1;
            end
        join
        if (reads != 3 || writes != 1 || memory[0][31:0] != 32'hdeadbeef)
            $fatal(1, "FAIL D dirty victim writes=%0d memory=%h", writes, memory[0]);
        access_word(32'h10002005, 1, 0, 32'haa);
        access_word(32'h10002004, 0, 2, 32'h0000aa00);
        maintenance(3, 32'h10002001, 1);
        if (writes != 2 || memory[1024][63:32] != (32'h0000aa00))
            $fatal(1, "FAIL maintenance clean/invalidate");
        access_word(32'h10002000, 0, 2, 5120);
        if (reads != 4) $fatal(1, "FAIL invalidate miss");
        access_word(32'h40000003, 1, 0, 32'h5a);
        access_word(32'h40000000, 0, 2, 32'h5aadbeef);
        // Four successive stores retire without a gap; the final write forwards
        // across a simultaneous RAM read/write collision.
        step(); dc_req_valid_i = 1; dc_req_store_i = 1; dc_req_size_i = 2;
        dc_req_addr_i = 32'h10002000;
        tick();
        for (int n = 0; n < 4; n++) begin
            if (!dc_resp_valid_o || !dc_req_ready_o) $fatal(1, "FAIL store throughput");
            step(); dc_commit_i = 1; dc_store_data_i = 32'h11223300 + 32'(n);
            dc_req_addr_i = 32'h10002000 + 32'((n+1)*4);
            if (n == 3) dc_req_valid_i = 0;
            tick();
        end
        step(); dc_commit_i = 0; dc_req_valid_i = 1; dc_req_store_i = 0;
        dc_req_addr_i = 32'h1000200c;
        tick();
        if (!dc_resp_valid_o || dc_resp_data_o != 32'h11223303)
            $fatal(1, "FAIL buffer drain forwarding got=%h", dc_resp_data_o);
        step(); dc_req_valid_i = 0; tick();
        // A byte store committed with a same-word load must merge into RAM data.
        step(); dc_req_valid_i = 1; dc_req_store_i = 1; dc_req_size_i = 0;
        dc_req_addr_i = 32'h1000200d; tick();
        step(); dc_commit_i = 1; dc_store_data_i = 32'haa;
        dc_req_addr_i = 32'h1000200c; dc_req_store_i = 0; dc_req_size_i = 2;
        tick();
        if (!dc_resp_valid_o || dc_resp_data_o != 32'h1122aa03)
            $fatal(1, "FAIL partial buffer forwarding got=%h", dc_resp_data_o);
        step(); dc_req_valid_i = 0; dc_commit_i = 0; tick();
        // Device polling remains live while the array walker is busy.
        step(); maint_cmd_i = 4; maint_req_valid_i = 1;
        while (!maint_req_ready_o) tick();
        tick(); step(); maint_req_valid_i = 0;
        dc_req_addr_i = 32'h10002000; #1;
        if (!dc_req_ready_o || !maint_busy_o) $fatal(1, "FAIL maintenance request ready");
        access_word(32'h40000000, 0, 2, 32'h5aadbeef);
        while (maint_busy_o) tick();
        if (memory[1025] != 64'h1122aa0311223302)
            $fatal(1, "FAIL clean data %h", memory[1025]);
        // cache-spec 5.4: an empty range finishes immediately. A simultaneous
        // accepted cached hit retains the next-cycle latency from 5.2.
        step(); maint_cmd_i = 1; maint_size_i = 0; maint_req_valid_i = 1;
        dc_req_valid_i = 1; dc_req_addr_i = 32'h1000200c;
        dc_req_store_i = 0; dc_req_size_i = 2;
        #1;
        if (!dc_req_ready_o || !maint_req_ready_o)
            $fatal(1, "FAIL empty maintenance simultaneous acceptance");
        tick();
        if (maint_busy_o || !dc_resp_valid_o || dc_resp_data_o != 32'h1122aa03)
            $fatal(1, "FAIL empty maintenance hit latency/data got=%h", dc_resp_data_o);
        step(); maint_req_valid_i = 0; dc_req_valid_i = 0; tick();
        // FENCE.I is a held request and completes once.
        access_word(32'h10002000, 1, 2, 32'h12345678);
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
        $display("PASS cache_dcache WB events=%0d", wb_events); $finish;
    end
endmodule
