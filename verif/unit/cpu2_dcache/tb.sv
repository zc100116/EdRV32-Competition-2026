// File: tb.sv
// Spec: cpu-v2-testplan CV11/CV12.
// Description: AXI64 byte memory and independent architectural store scoreboard.
// Clock: clk_sys.
module tb # (parameter FORMAT = 0);
    localparam [31:0] FPU_FORMAT = FORMAT == 2 ? "FD" : FORMAT == 1 ? "F" : "NONE";
    localparam T = FORMAT == 2 ? 4 : FORMAT == 1 ? 3 : 2;
    reg clk_i = 0;
    reg rst_n_i = 0;
    reg [T-1:0] dc_req_tag_i = 0;
    reg [31:0] dc_req_addr_i = 0;
    reg [1:0] dc_req_size_i = 0;
    reg [31:0] dc_req_data_i = 0;
    reg [3:0] dc_req_mask_i = 0;
    wire [T-1:0] dc_resp_tag_o;
    wire [1:0] dc_resp_way_hit_o;
    wire [31:0] dc_resp_way0_data_o;
    wire [31:0] dc_resp_way1_data_o;
    reg [T-1:0] dc_commit_tag_i = 0;
    reg [31:0] dc_commit_data_i = 0;
    reg [3:0] dc_commit_mask_i = 0;
    wire [T-1:0] dc_done_tag_o;
    wire [31:0] dc_done_data_o;
    reg [T-1:0] dc_cancel_tag_i = 0;
    reg [T-1:0] dc_age_head_i = 0;
    reg [31:0] dc_early_addr_i = 0;
    reg [T-1:0] dc_early_tag_i = 0;
    wire [T-1:0] dc_early_resp_tag_o;
    wire [1:0] dc_early_hit_o;
    wire [31:0] dc_early_way0_data_o;
    wire [31:0] dc_early_way1_data_o;
    reg dc_req_valid_i = 0;
    wire dc_req_ready_o;
    reg dc_req_beat_i = 0;
    reg dc_req_store_i = 0;
    reg dc_req_early_i = 0;
    wire dc_resp_valid_o;
    reg dc_resp_ready_i = 0;
    wire dc_resp_beat_o;
    wire dc_resp_error_o;
    wire dc_resp_device_o;
    reg dc_commit_valid_i = 0;
    wire dc_commit_ready_o;
    reg dc_commit_beat_i = 0;
    wire dc_done_valid_o;
    reg dc_done_ready_i = 0;
    wire dc_done_beat_o;
    wire dc_done_error_o;
    reg dc_cancel_valid_i = 0;
    reg dc_early_valid_i = 0;
    wire dc_early_resp_valid_o;
    reg dc_fence_valid_i = 0;
    wire dc_fence_ready_o;
    reg dc_fence_clean_all_i = 0;
    wire dc_fence_done_o;
    wire dc_wb_event_o;
    wire dc_miss_event_o;
    reg maint_req_valid_i = 0;
    wire maint_req_ready_o;
    reg [2:0] maint_cmd_i = 0;
    reg [31:0] maint_addr_i = 0;
    reg [31:0] maint_size_i = 0;
    wire maint_busy_o;
    wire wb_err_o;
    wire [31:0] wb_err_addr_o;
    wire [3:0] axi_arid_o;
    wire [31:0] axi_araddr_o;
    wire [7:0] axi_arlen_o;
    wire [2:0] axi_arsize_o;
    wire [1:0] axi_arburst_o;
    wire axi_arvalid_o;
    reg axi_arready_i = 0;
    reg [3:0] axi_rid_i = 0;
    reg [63:0] axi_rdata_i = 0;
    reg [1:0] axi_rresp_i = 0;
    reg axi_rlast_i = 0;
    reg axi_rvalid_i = 0;
    wire axi_rready_o;
    wire [3:0] axi_awid_o;
    wire [31:0] axi_awaddr_o;
    wire [7:0] axi_awlen_o;
    wire [2:0] axi_awsize_o;
    wire [1:0] axi_awburst_o;
    wire axi_awvalid_o;
    reg axi_awready_i = 0;
    wire [63:0] axi_wdata_o;
    wire [7:0] axi_wstrb_o;
    wire axi_wlast_o;
    wire axi_wvalid_o;
    reg axi_wready_i = 0;
    reg [3:0] axi_bid_i = 0;
    reg [1:0] axi_bresp_i = 0;
    reg axi_bvalid_i = 0;
    wire axi_bready_o;
    always #5 clk_i = ~clk_i;
    edrv32_cpu2_dcache #(.FPU_FORMAT(FPU_FORMAT)) dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .dc_req_tag_i(dc_req_tag_i),
        .dc_req_addr_i(dc_req_addr_i),
        .dc_req_size_i(dc_req_size_i),
        .dc_req_data_i(dc_req_data_i),
        .dc_req_mask_i(dc_req_mask_i),
        .dc_resp_tag_o(dc_resp_tag_o),
        .dc_resp_way_hit_o(dc_resp_way_hit_o),
        .dc_resp_way0_data_o(dc_resp_way0_data_o),
        .dc_resp_way1_data_o(dc_resp_way1_data_o),
        .dc_commit_tag_i(dc_commit_tag_i),
        .dc_commit_data_i(dc_commit_data_i),
        .dc_commit_mask_i(dc_commit_mask_i),
        .dc_done_tag_o(dc_done_tag_o),
        .dc_done_data_o(dc_done_data_o),
        .dc_cancel_tag_i(dc_cancel_tag_i),
        .dc_age_head_i(dc_age_head_i),
        .dc_early_addr_i(dc_early_addr_i),
        .dc_early_tag_i(dc_early_tag_i),
        .dc_early_resp_tag_o(dc_early_resp_tag_o),
        .dc_early_hit_o(dc_early_hit_o),
        .dc_early_way0_data_o(dc_early_way0_data_o),
        .dc_early_way1_data_o(dc_early_way1_data_o),
        .dc_req_valid_i(dc_req_valid_i),
        .dc_req_ready_o(dc_req_ready_o),
        .dc_req_beat_i(dc_req_beat_i),
        .dc_req_store_i(dc_req_store_i),
        .dc_req_early_i(dc_req_early_i),
        .dc_resp_valid_o(dc_resp_valid_o),
        .dc_resp_ready_i(dc_resp_ready_i),
        .dc_resp_beat_o(dc_resp_beat_o),
        .dc_resp_error_o(dc_resp_error_o),
        .dc_resp_device_o(dc_resp_device_o),
        .dc_commit_valid_i(dc_commit_valid_i),
        .dc_commit_ready_o(dc_commit_ready_o),
        .dc_commit_beat_i(dc_commit_beat_i),
        .dc_done_valid_o(dc_done_valid_o),
        .dc_done_ready_i(dc_done_ready_i),
        .dc_done_beat_o(dc_done_beat_o),
        .dc_done_error_o(dc_done_error_o),
        .dc_cancel_valid_i(dc_cancel_valid_i),
        .dc_early_valid_i(dc_early_valid_i),
        .dc_early_resp_valid_o(dc_early_resp_valid_o),
        .dc_fence_valid_i(dc_fence_valid_i),
        .dc_fence_ready_o(dc_fence_ready_o),
        .dc_fence_clean_all_i(dc_fence_clean_all_i),
        .dc_fence_done_o(dc_fence_done_o),
        .dc_wb_event_o(dc_wb_event_o),
        .dc_miss_event_o(dc_miss_event_o),
        .maint_req_valid_i(maint_req_valid_i),
        .maint_req_ready_o(maint_req_ready_o),
        .maint_cmd_i(maint_cmd_i),
        .maint_addr_i(maint_addr_i),
        .maint_size_i(maint_size_i),
        .maint_busy_o(maint_busy_o),
        .wb_err_o(wb_err_o),
        .wb_err_addr_o(wb_err_addr_o),
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
        // I06 observation-only outputs.
        .trace_mem_effect_valid_o(),
        .trace_mem_effect_tag_o(),
        .trace_mem_effect_addr_o(),
        .trace_mem_effect_data_o(),
        .trace_mem_effect_mask_o(),
        .debug_miss_o()
    );
    reg [7:0] memory [0:1048575];
    reg [7:0] reference_memory [0:1048575];
    int cycle = 0;
    int ar_count = 0;
    int aw_count = 0;
    int wb_count = 0;
    int wb_errors = 0;
    int miss_count = 0;
    int delay_r = 0;
    int delay_b = 0;
    reg read_busy = 0;
    reg write_busy = 0;
    reg [31:0] read_addr;
    reg [7:0] read_len;
    reg [7:0] read_beat;
    reg [31:0] write_addr;
    reg [7:0] write_len;
    reg [7:0] write_beat;
    reg [31:0] read_error_line = 32'hffffffff;
    reg [31:0] write_error_line = 32'hffffffff;
    reg [31:0] last_wb_error;
    reg [31:0] expected_addr [0:127];
    reg [T-1:0] expected_tag [0:127];
    reg expected_beat [0:127];
    reg expected_store [0:127];
    reg expected_error [0:127];
    reg expected_device [0:127];
    int push = 0;
    int pull = 0;
    int issued_tag = 0;
    int responses = 0;
    function automatic int index_of(input [31:0] addr);
        int region;
        case (addr[31:28])
            4'h0: region = 0;
            4'h1: region = 1;
            4'h8, 4'hc: region = 2;
            default: region = 3;
        endcase
        index_of = (region << 18) | int'(addr[17:0]);
    endfunction
    function automatic [31:0] expected_word(input [31:0] addr);
        expected_word = {reference_memory[index_of(addr)+3], reference_memory[index_of(addr)+2],
                         reference_memory[index_of(addr)+1], reference_memory[index_of(addr)]};
    endfunction
    always @(posedge clk_i) begin
        cycle <= cycle + 1;
        if (dc_miss_event_o) miss_count <= miss_count + 1;
        if (dc_wb_event_o) wb_count <= wb_count + 1;
        if (wb_err_o) begin
            wb_errors <= wb_errors + 1;
            last_wb_error <= wb_err_addr_o;
        end
        if (dc_resp_valid_o && dc_resp_ready_i) begin
            reg [31:0] value;
            int q;
            q = pull % 128;
            value = dc_resp_way_hit_o[1] ? dc_resp_way1_data_o : dc_resp_way0_data_o;
            if (pull >= push) $fatal(1, "unexpected response");
            if (dc_resp_tag_o != expected_tag[q] || dc_resp_beat_o != expected_beat[q] ||
                dc_resp_error_o != expected_error[q] || dc_resp_device_o != expected_device[q])
                $fatal(1, "response metadata q%0d tag%h beat%b err%b dev%b expected %h/%b/%b/%b",
                       q, dc_resp_tag_o, dc_resp_beat_o, dc_resp_error_o, dc_resp_device_o,
                       expected_tag[q], expected_beat[q], expected_error[q], expected_device[q]);
            if (!expected_store[q] && !expected_device[q] && !expected_error[q] &&
                value !== expected_word(expected_addr[q]))
                $fatal(1, "load addr%h expected%h actual%h", expected_addr[q],
                       expected_word(expected_addr[q]), value);
            pull = pull + 1;
            responses <= responses + 1;
        end
        axi_arready_i <= !read_busy && cycle % 3 != 0;
        if (axi_arvalid_o && axi_arready_i) begin
            if (axi_arid_o != 0 || axi_arburst_o != 1 ||
                (axi_arlen_o != 0 && axi_arlen_o != 3)) $fatal(1, "read shape");
            ar_count <= ar_count + 1;
            read_busy <= 1;
            read_addr <= axi_araddr_o;
            read_len <= axi_arlen_o;
            read_beat <= 0;
            delay_r <= 2;
        end
        if (read_busy && !axi_rvalid_i) begin
            if (delay_r == 0) begin
                int base;
                base = index_of({read_addr[31:3], 3'd0}) + int'(read_beat)*8;
                for (int b = 0; b < 8; b++) axi_rdata_i[b*8 +: 8] <= memory[base+b];
                axi_rresp_i <= read_addr[31:5] == read_error_line[31:5] &&
                    read_beat == 0 ? 2 : 0;
                axi_rlast_i <= read_beat == read_len;
                axi_rvalid_i <= 1;
            end else delay_r <= delay_r - 1;
        end
        if (axi_rvalid_i && axi_rready_o) begin
            axi_rvalid_i <= 0;
            read_beat <= read_beat + 1;
            delay_r <= cycle % 3;
            if (axi_rlast_i) read_busy <= 0;
        end
        axi_awready_i <= !write_busy && !axi_bvalid_i && cycle % 4 != 0;
        axi_wready_i <= write_busy && cycle % 3 != 0;
        if (axi_awvalid_o && axi_awready_i) begin
            if (axi_awid_o != 0 || axi_awburst_o != 1 ||
                (axi_awlen_o != 0 && axi_awlen_o != 3)) $fatal(1, "write shape");
            aw_count <= aw_count + 1;
            write_busy <= 1;
            write_addr <= axi_awaddr_o;
            write_len <= axi_awlen_o;
            write_beat <= 0;
        end
        if (axi_wvalid_o && axi_wready_i) begin
            int base;
            base = index_of({write_addr[31:3], 3'd0}) + int'(write_beat)*8;
            for (int b = 0; b < 8; b++) begin
                if (axi_wstrb_o[b]) memory[base+b] <= axi_wdata_o[b*8 +: 8];
            end
            if (axi_wlast_o != (write_beat == write_len)) $fatal(1, "write last");
            write_beat <= write_beat + 1;
            if (axi_wlast_o) begin
                write_busy <= 0;
                delay_b <= 3;
            end
        end
        if (delay_b != 0) begin
            delay_b <= delay_b - 1;
            if (delay_b == 1) begin
                axi_bvalid_i <= 1;
                axi_bresp_i <= write_addr[31:5] == write_error_line[31:5] ? 2 : 0;
            end
        end
        if (axi_bvalid_i && axi_bready_o) axi_bvalid_i <= 0;
    end
    task automatic tick;
        @(posedge clk_i);
        #1;
    endtask
    task automatic step;
        @(negedge clk_i);
    endtask
    task automatic send(input [31:0] addr, input bit store, input [1:0] size,
                        input bit beat, input [T-1:0] tag, input bit device, input bit error);
        step();
        while (!dc_req_ready_o) step();
        expected_addr[push % 128] = addr;
        expected_store[push % 128] = store;
        expected_tag[push % 128] = tag;
        expected_beat[push % 128] = beat;
        expected_device[push % 128] = device;
        expected_error[push % 128] = error;
        push = push + 1;
        dc_req_valid_i = 1;
        dc_req_addr_i = addr;
        dc_req_store_i = store;
        dc_req_size_i = size;
        dc_req_beat_i = beat;
        dc_req_tag_i = tag;
        tick();
        step();
        dc_req_valid_i = 0;
    endtask
    task automatic drain;
        while (push != pull) tick();
        step();
    endtask
    task automatic authorize(input [31:0] addr, input [T-1:0] tag, input bit beat,
                             input [31:0] data, input [3:0] mask,
                             input bit error, input bit store);
        step();
        dc_commit_tag_i = tag;
        dc_commit_beat_i = beat;
        dc_commit_data_i = data;
        dc_commit_mask_i = mask;
        dc_commit_valid_i = 1;
        while (!dc_commit_ready_o) step();
        tick();
        step();
        dc_commit_valid_i = 0;
        if (!error && store) begin
            for (int b = 0; b < 4; b++) begin
                if (mask[b]) reference_memory[index_of(addr)+b] = data[b*8 +: 8];
            end
        end
        while (!dc_done_valid_o) tick();
        if (dc_done_tag_o != tag || dc_done_beat_o != beat || dc_done_error_o != error)
            $fatal(1, "done metadata expected tag%h beat%b err%b actual%h/%b/%b",
                   tag, beat, error, dc_done_tag_o, dc_done_beat_o, dc_done_error_o);
        if (!store && !error && dc_done_data_o !== expected_word(addr))
            $fatal(1, "device load expected%h actual%h", expected_word(addr), dc_done_data_o);
        // Keep done stable under downstream backpressure.
        repeat (3) tick();
        step();
        dc_done_ready_i = 1;
        tick();
        step();
        dc_done_ready_i = 0;
    endtask
    task automatic load(input [31:0] addr);
        send(addr, 0, 2, 0, T'(issued_tag), 0, 0);
        issued_tag++;
        drain();
    endtask
    task automatic store_word(input [31:0] addr, input [31:0] data, input [3:0] mask);
        reg [T-1:0] tag;
        tag = T'(issued_tag);
        issued_tag++;
        send(addr, 1, 2, 0, tag, 0, 0);
        drain();
        authorize(addr, tag, 0, data, mask, 0, 1);
    endtask
    task automatic maintain(input [2:0] cmd, input [31:0] addr, input [31:0] size);
        int start_cycle;
        step();
        maint_cmd_i = cmd;
        maint_addr_i = addr;
        maint_size_i = size;
        maint_req_valid_i = 1;
        while (!maint_req_ready_o) step();
        tick();
        step();
        maint_req_valid_i = 0;
        start_cycle = cycle;
        while (maint_busy_o) tick();
        $display("maint cmd%0d addr%h size%h cycles%0d", cmd, addr, size, cycle-start_cycle);
        step();
    endtask
    task automatic fence(input bit clean);
        step();
        dc_fence_valid_i = 1;
        dc_fence_clean_all_i = clean;
        while (!dc_fence_ready_o) step();
        tick();
        step();
        dc_fence_valid_i = 0;
        while (!dc_fence_done_o) tick();
        step();
    endtask
    initial begin
        #10000000;
        $fatal(1, "timeout push%0d pull%0d", push, pull);
    end
    initial begin
        for (int b = 0; b < 1048576; b++) begin
            memory[b] = 8'((b*13) ^ (b>>8) ^ (b>>16));
            reference_memory[b] = 8'((b*13) ^ (b>>8) ^ (b>>16));
        end
        dc_resp_ready_i = 1;
        repeat (2) tick();
        step();
        rst_n_i = 1;
        for (int n = 1; n <= 512; n++) begin
            tick();
            if (dc_req_ready_o != (n == 512)) $fatal(1, "reset scan cycle%0d", n);
        end
        load(32'h10000000);
        load(32'h1000001c);
        store_word(32'h10000004, 32'h12345678, 4'hf);
        load(32'h10000004);
        store_word(32'h10000005, 32'h000000ab, 4'h1);
        load(32'h10000004);
        store_word(32'h10000006, 32'h0000cdef, 4'h3);
        load(32'h10000004);
        // Write allocate and two dirty cache colors are both written back on replacement.
        store_word(32'h10004000, 32'haabbccdd, 4'hf);
        load(32'h80008000);
        load(32'h10000004);
        maintain(1, 32'h10000005, 32'd1);
        for (int b = 4; b < 8; b++) begin
            if (memory[index_of(32'h10000000)+b] !== reference_memory[index_of(32'h10000000)+b]) $fatal(1, "range clean byte%0d", b);
        end
        // Warm cache hit throughput has no AXI transactions and one response per cycle.
        begin
            int before_ar;
            before_ar = ar_count;
            step();
            for (int i = 0; i < 16; i++) begin
                if (!dc_req_ready_o) $fatal(1, "warm ready");
                expected_addr[push % 128] = 32'h10000000 + 32'((i % 8)*4);
                expected_tag[push % 128] = T'(i);
                expected_beat[push % 128] = 0;
                expected_store[push % 128] = 0;
                expected_device[push % 128] = 0;
                expected_error[push % 128] = 0;
                push++;
                dc_req_valid_i = 1;
                dc_req_addr_i = 32'h10000000 + 32'((i % 8)*4);
                dc_req_store_i = 0;
                dc_req_tag_i = T'(i);
                tick();
                if (!dc_resp_valid_o) $fatal(1, "warm response latency");
                step();
            end
            dc_req_valid_i = 0;
            drain();
            if (ar_count != before_ar) $fatal(1, "warm cache miss");
        end
        // Reserve both contexts on adjacent edges before the first miss can block ready.
        // Check both a retained hit and a second miss behind that miss.
        for (int pair = 0; pair < 2; pair++) begin
            step();
            for (int i = 0; i < 2; i++) begin
                if (!dc_req_ready_o) $fatal(1, "miss lookahead admission");
                dc_req_addr_i = pair == 0 ?
                    (i == 0 ? 32'h80010000 : 32'h10000000) :
                    (i == 0 ? 32'h80010020 : 32'h80010040);
                dc_req_valid_i = 1;
                dc_req_store_i = 0;
                dc_req_tag_i = T'(i);
                expected_addr[push % 128] = dc_req_addr_i;
                expected_tag[push % 128] = T'(i);
                expected_beat[push % 128] = 0;
                expected_store[push % 128] = 0;
                expected_device[push % 128] = 0;
                expected_error[push % 128] = 0;
                push++;
                tick();
                step();
            end
            dc_req_valid_i = 0;
            drain();
        end
        // All byte masks merge independently and survive full clean.
        for (int mask = 1; mask < 16; mask++) begin
            store_word(32'h10000008, 32'h11223344 ^ (32'(mask)*32'h10101010), 4'(mask));
            load(32'h10000008);
        end
        fence(0);
        fence(1);
        for (int b = 0; b < 32; b++) begin
            if (memory[index_of(32'h10000000)+b] !== reference_memory[index_of(32'h10000000)+b]) $fatal(1, "full clean byte%0d", b);
        end
        maintain(1, 32'h10000003, 0);
        maintain(2, 32'h10000003, 0);
        maintain(3, 32'h10000003, 0);
        maintain(2, 32'h10000003, 33);
        load(32'h10000004);
        // Invalidate is explicitly allowed to discard dirty data.
        store_word(32'h10000010, 32'hdeadbeef, 4'hf);
        maintain(2, 32'h10000010, 1);
        for (int b = 16; b < 20; b++) reference_memory[index_of(32'h10000000)+b] = memory[index_of(32'h10000000)+b];
        load(32'h10000010);
        store_word(32'h10000010, 32'h1234abcd, 4'hf);
        maintain(3, 32'h10000010, 1);
        load(32'h10000010);
        maintain(2, 32'h80000000, 32'h100000);
        // Device requests are only preparations until authorization, including ROM loads.
        begin
            int before_ar;
            before_ar = ar_count;
            send(32'h20000004, 0, 2, 0, T'(1), 1, 0);
            drain();
            repeat (3) tick();
            if (ar_count != before_ar) $fatal(1, "device request issued before head");
            authorize(32'h20000004, T'(1), 0, 0, 4'hf, 0, 0);
        end
        send(32'h20000007, 1, 0, 0, T'(2), 1, 0);
        drain();
        authorize(32'h20000007, T'(2), 0, 32'hab, 4'h1, 0, 1);
        send(32'h00000000, 0, 2, 0, T'(3), 1, 0);
        drain();
        authorize(0, T'(3), 0, 0, 4'hf, 0, 0);
        send(32'hc0000004, 0, 2, 0, T'(0), 1, 0);
        drain();
        authorize(32'hc0000004, T'(0), 0, 0, 4'hf, 0, 0);
        // PMA rejection never reaches AXI.
        begin
            int before_ar;
            int before_aw;
            before_ar = ar_count;
            before_aw = aw_count;
            send(0, 1, 2, 0, T'(1), 0, 1);
            send(32'h60000000, 0, 2, 0, T'(2), 0, 1);
            drain();
            if (ar_count != before_ar || aw_count != before_aw) $fatal(1, "PMA AXI escape");
        end
        // Error fills drain all four beats and never install; writeback errors keep progressing.
        read_error_line = 32'h80012000;
        send(32'h80012000, 0, 2, 0, T'(1), 0, 1);
        drain();
        send(32'h80012000, 0, 2, 0, T'(2), 0, 1);
        drain();
        read_error_line = 32'hffffffff;
        write_error_line = 32'h80012000;
        store_word(32'h80012000, 32'h55aa55aa, 4'hf);
        maintain(1, 32'h80012000, 32);
        if (wb_errors == 0 || last_wb_error != 32'h80012000) $fatal(1, "writeback error path");
        write_error_line = 32'hffffffff;
        // The read port samples old RAM data when the store buffer drains.
        // Combine that old buffer with a newly committed replacement in byte order.
        load(32'h10000020);
        send(32'h10000020, 1, 2, 0, T'(0), 0, 0);
        send(32'h10000020, 1, 2, 0, T'(1), 0, 0);
        drain();
        step();
        dc_done_ready_i = 1;
        dc_commit_valid_i = 1;
        dc_commit_tag_i = T'(0);
        dc_commit_beat_i = 0;
        dc_commit_data_i = 32'h000000ab;
        dc_commit_mask_i = 4'h1;
        reference_memory[index_of(32'h10000020)] = 8'hab;
        tick();
        step();
        dc_commit_tag_i = T'(1);
        dc_commit_data_i = 32'h00cd0000;
        dc_commit_mask_i = 4'h4;
        reference_memory[index_of(32'h10000022)] = 8'hcd;
        expected_addr[push % 128] = 32'h10000020;
        expected_tag[push % 128] = T'(2);
        expected_beat[push % 128] = 0;
        expected_store[push % 128] = 0;
        expected_device[push % 128] = 0;
        expected_error[push % 128] = 0;
        push++;
        dc_req_valid_i = 1;
        dc_req_tag_i = T'(2);
        dc_req_addr_i = 32'h10000020;
        dc_req_store_i = 0;
        tick();
        step();
        dc_commit_valid_i = 0;
        dc_req_valid_i = 0;
        tick();
        step();
        dc_done_ready_i = 0;
        drain();
        load(32'h10000020);
        // A fixed next-cycle early query is reused only by the following request.
        step();
        dc_early_valid_i = 1;
        dc_early_addr_i = 32'h10000020;
        dc_early_tag_i = T'(3);
        tick();
        if (!dc_early_resp_valid_o || dc_early_resp_tag_o != T'(3) || dc_early_hit_o == 0 ||
            (dc_early_hit_o[1] ? dc_early_way1_data_o : dc_early_way0_data_o) !==
                expected_word(32'h10000020)) $fatal(1, "early fixed response");
        step();
        dc_early_valid_i = 0;
        dc_req_valid_i = 1;
        dc_req_early_i = 1;
        dc_req_tag_i = T'(3);
        dc_req_addr_i = 32'h10000020;
        expected_addr[push % 128] = 32'h10000020;
        expected_tag[push % 128] = T'(3);
        expected_beat[push % 128] = 0;
        expected_store[push % 128] = 0;
        expected_device[push % 128] = 0;
        expected_error[push % 128] = 0;
        push++;
        tick();
        if (!dc_resp_valid_o) $fatal(1, "promoted early request latency");
        step();
        dc_req_valid_i = 0;
        dc_req_early_i = 0;
        drain();
        // Successful early promotion and the following query share the port each cycle.
        step();
        dc_early_valid_i = 1;
        dc_early_addr_i = 32'h10000020;
        dc_early_tag_i = 0;
        tick();
        step();
        for (int i = 0; i < 8; i++) begin
            if (!dc_early_resp_valid_o || dc_early_resp_tag_o != T'(i) ||
                dc_early_hit_o == 0 || !dc_req_ready_o)
                $fatal(1, "consecutive early query n=%0d", i);
            dc_req_valid_i = 1;
            dc_req_early_i = 1;
            dc_req_tag_i = T'(i);
            dc_req_addr_i = 32'h10000020 + 32'(i*4);
            dc_early_valid_i = i < 7;
            dc_early_tag_i = T'(i+1);
            dc_early_addr_i = 32'h10000020 + 32'((i+1)*4);
            expected_addr[push % 128] = dc_req_addr_i;
            expected_tag[push % 128] = T'(i);
            expected_beat[push % 128] = 0;
            expected_store[push % 128] = 0;
            expected_device[push % 128] = 0;
            expected_error[push % 128] = 0;
            push++;
            tick();
            if (!dc_resp_valid_o || dc_resp_tag_o != T'(i))
                $fatal(1, "consecutive early promotion response n=%0d", i);
            step();
        end
        dc_req_valid_i = 0;
        dc_req_early_i = 0;
        dc_early_valid_i = 0;
        drain();
        // Both reserved contexts retain hit responses during backpressure.
        dc_resp_ready_i = 0;
        send(32'h10000020, 0, 2, 0, T'(0), 0, 0);
        send(32'h10000024, 0, 2, 0, T'(1), 0, 0);
        repeat (3) tick();
        if (dc_req_ready_o) $fatal(1, "response capacity exceeded");
        step();
        dc_resp_ready_i = 1;
        drain();
        // A cached request waits locally while a range scan owns the read port.
        step();
        maint_cmd_i = 1;
        maint_addr_i = 32'h10000000;
        maint_size_i = 256;
        maint_req_valid_i = 1;
        tick();
        step();
        maint_req_valid_i = 0;
        dc_early_valid_i = 1;
        dc_early_addr_i = 32'h10000020;
        tick();
        if (!dc_early_resp_valid_o || dc_early_hit_o != 0)
            $fatal(1, "early maintenance conflict");
        step();
        dc_early_valid_i = 0;
        send(32'h10000020, 0, 2, 0, T'(2), 0, 0);
        repeat (5) begin
            tick();
            if (dc_resp_valid_o) $fatal(1, "cached response during maintenance");
        end
        while (maint_busy_o) tick();
        drain();
        // Device polling shares the external bus between maintenance line writes.
        store_word(32'h10000020, 32'h01234567, 4'hf);
        fork
            maintain(4, 0, 0);
            begin
                while (!maint_busy_o) tick();
                send(32'h20000004, 0, 2, 0, T'(1), 1, 0);
                drain();
                authorize(32'h20000004, T'(1), 0, 0, 4'hf, 0, 0);
            end
        join
        // Device bus errors report through done, without using the writeback IRQ path.
        read_error_line = 32'h20004000;
        send(32'h20004000, 0, 2, 0, T'(2), 1, 0);
        drain();
        authorize(32'h20004000, T'(2), 0, 0, 4'hf, 1, 0);
        read_error_line = 32'hffffffff;
        write_error_line = 32'h20004000;
        send(32'h20004004, 1, 2, 0, T'(3), 1, 0);
        drain();
        authorize(32'h20004004, T'(3), 0, 32'haabbccdd, 4'hf, 1, 1);
        write_error_line = 32'hffffffff;
        // Cancel a live miss, drain AXI, then reuse the same tag for a new instance.
        dc_age_head_i = T'(3);
        send(32'h80016000, 0, 2, 0, T'(0), 0, 0);
        while (!read_busy) tick();
        step();
        dc_cancel_tag_i = T'(0);
        dc_cancel_valid_i = 1;
        pull = push;
        tick();
        step();
        dc_cancel_valid_i = 0;
        while (read_busy || !dc_req_ready_o) tick();
        send(32'h80016000, 0, 2, 0, T'(0), 0, 0);
        drain();
        dc_age_head_i = 0;
        // FD preparation keeps two beat records with a shared tag until individual commits.
        if (FORMAT == 2) begin
            send(32'h10000038, 1, 2, 0, T'(4), 0, 0);
            send(32'h1000003c, 1, 2, 1, T'(4), 0, 0);
            drain();
            authorize(32'h10000038, T'(4), 0, 32'h89abcdef, 4'hf, 0, 1);
            authorize(32'h1000003c, T'(4), 1, 32'h01234567, 4'hf, 0, 1);
            load(32'h10000038);
            load(32'h1000003c);
        end
        // Zero-size range commands finish immediately even during an unrelated refill.
        send(32'h80018000, 0, 2, 0, T'(2), 0, 0);
        while (!read_busy) tick();
        maintain(1, 32'h10000000, 0);
        if (!read_busy) $fatal(1, "zero range waited for an in-flight fill");
        drain();
        // Set scan geometry and upper tag bits, including the final set.
        for (int i = 0; i < 512; i++) load(32'h80000000 + 32'(i*32));
        maintain(4, 0, 0);
        maintain(4, 0, 0);
        $display("PASS cpu2_dcache FORMAT=%0d responses=%0d AR=%0d AW=%0d WB=%0d miss=%0d",
                 FORMAT, responses, ar_count, aw_count, wb_count, miss_count);
        $finish;
    end
endmodule
