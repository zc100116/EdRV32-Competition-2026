// File: tb.sv
// Spec: cpu-v2-testplan CV11/CV12.
// Description: Byte-address reference and variable-latency AXI64 instruction source.
// Clock: clk_sys.
module tb # (parameter ISSUE_WIDTH = 2);
    reg clk_i = 0;
    reg rst_n_i = 0;
    reg ic_req_valid_i = 0;
    wire ic_req_ready_o;
    reg [31:0] ic_req_addr_i = 0;
    wire ic_resp_valid_o;
    reg ic_resp_ready_i = 0;
    wire [31:0] ic_resp_bank0_way0_instr_o;
    wire [31:0] ic_resp_bank0_way1_instr_o;
    wire [1:0] ic_resp_bank0_way_hit_o;
    wire ic_resp_bank0_error_o;
    wire [31:0] ic_resp_bank1_way0_instr_o;
    wire [31:0] ic_resp_bank1_way1_instr_o;
    wire [1:0] ic_resp_bank1_way_hit_o;
    wire ic_resp_bank1_error_o;
    reg ic_cancel_i = 0;
    reg ic_inv_valid_i = 0;
    wire ic_inv_ready_o;
    wire ic_inv_done_o;
    wire ic_miss_event_o;
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
    always #5 clk_i = ~clk_i;
    edrv32_cpu2_icache #(.ISSUE_WIDTH(ISSUE_WIDTH)) dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .ic_req_valid_i(ic_req_valid_i),
        .ic_req_ready_o(ic_req_ready_o),
        .ic_req_addr_i(ic_req_addr_i),
        .ic_resp_valid_o(ic_resp_valid_o),
        .ic_resp_ready_i(ic_resp_ready_i),
        .ic_resp_bank0_way0_instr_o(ic_resp_bank0_way0_instr_o),
        .ic_resp_bank0_way1_instr_o(ic_resp_bank0_way1_instr_o),
        .ic_resp_bank0_way_hit_o(ic_resp_bank0_way_hit_o),
        .ic_resp_bank0_error_o(ic_resp_bank0_error_o),
        .ic_resp_bank1_way0_instr_o(ic_resp_bank1_way0_instr_o),
        .ic_resp_bank1_way1_instr_o(ic_resp_bank1_way1_instr_o),
        .ic_resp_bank1_way_hit_o(ic_resp_bank1_way_hit_o),
        .ic_resp_bank1_error_o(ic_resp_bank1_error_o),
        .ic_cancel_i(ic_cancel_i),
        .ic_inv_valid_i(ic_inv_valid_i),
        .ic_inv_ready_o(ic_inv_ready_o),
        .ic_inv_done_o(ic_inv_done_o),
        .ic_miss_event_o(ic_miss_event_o),
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
        // I06 observation-only outputs.
        .debug_miss_o()
    );
    reg [31:0] queue_addr [0:127];
    int push = 0;
    int pull = 0;
    int responses = 0;
    int ar_count = 0;
    int misses = 0;
    int cycles = 0;
    reg [31:0] error_line = 32'hffffffff;
    reg [31:0] bus_addr;
    reg [7:0] bus_len;
    reg [7:0] bus_beat;
    reg bus_busy = 0;
    int delay_count = 0;
    reg long_delay = 0;
    function automatic [31:0] memory_word(input [31:0] addr);
        memory_word = addr ^ 32'h5aa50ff0;
    endfunction
    function automatic bit word_error(input [31:0] addr);
        word_error = !((addr[31:16] == 16'h1000) || (addr[31:30] == 2'b10) ||
                       addr < 32'h4000) || (addr[31:5] == error_line[31:5]);
    endfunction
    always @(posedge clk_i) begin
        cycles <= cycles + 1;
        if (ic_miss_event_o) misses <= misses + 1;
        if (ic_req_valid_i && ic_req_ready_o) begin
            queue_addr[push % 128] = ic_req_addr_i;
            push = push + 1;
        end
        if (ic_resp_valid_o && ic_resp_ready_i) begin
            reg [31:0] pc;
            reg [31:0] actual0;
            reg [31:0] actual1;
            reg error0;
            reg error1;
            reg [1:0] hit0;
            reg [1:0] hit1;
            pc = queue_addr[pull % 128];
            if (ISSUE_WIDTH == 2 && pc[2]) begin
                actual0 = ic_resp_bank1_way_hit_o[1] ? ic_resp_bank1_way1_instr_o :
                    ic_resp_bank1_way0_instr_o;
                actual1 = ic_resp_bank0_way_hit_o[1] ? ic_resp_bank0_way1_instr_o :
                    ic_resp_bank0_way0_instr_o;
            end else begin
                actual0 = ic_resp_bank0_way_hit_o[1] ? ic_resp_bank0_way1_instr_o :
                    ic_resp_bank0_way0_instr_o;
                actual1 = ic_resp_bank1_way_hit_o[1] ? ic_resp_bank1_way1_instr_o :
                    ic_resp_bank1_way0_instr_o;
            end
            error0 = ISSUE_WIDTH == 2 && pc[2] ? ic_resp_bank1_error_o : ic_resp_bank0_error_o;
            error1 = ISSUE_WIDTH == 2 && pc[2] ? ic_resp_bank0_error_o : ic_resp_bank1_error_o;
            hit0 = ISSUE_WIDTH == 2 && pc[2] ? ic_resp_bank1_way_hit_o : ic_resp_bank0_way_hit_o;
            hit1 = ISSUE_WIDTH == 2 && pc[2] ? ic_resp_bank0_way_hit_o : ic_resp_bank1_way_hit_o;
            if (pull >= push) $fatal(1, "response with no accepted context");
            if (error0 !== word_error(pc) || error1 !== word_error(pc + 4))
                $fatal(1, "error pc%h expected%b/%b actual%b/%b", pc, word_error(pc),
                       word_error(pc+4), error0, error1);
            if (!word_error(pc) && (actual0 !== memory_word(pc) ||
                hit0 == 0))
                $fatal(1, "word0 pc%h expected%h actual%h", pc, memory_word(pc), actual0);
            if (!word_error(pc+4) && (actual1 !== memory_word(pc+4) ||
                hit1 == 0))
                $fatal(1, "word1 pc%h expected%h actual%h", pc+4, memory_word(pc+4), actual1);
            pull = pull + 1;
            responses <= responses + 1;
        end
        if (ic_cancel_i) pull = push;
        axi_arready_i <= !bus_busy && cycles % 3 != 0;
        if (axi_arvalid_o && axi_arready_i) begin
            if (axi_arid_o != 0 || axi_arsize_o != 3 || axi_arburst_o != 1 ||
                (axi_arlen_o != 0 && axi_arlen_o != 3)) $fatal(1, "AXI AR shape");
            bus_busy <= 1;
            bus_addr <= axi_araddr_o;
            bus_len <= axi_arlen_o;
            bus_beat <= 0;
            delay_count <= long_delay ? 600 : 2;
            ar_count <= ar_count + 1;
        end
        if (bus_busy && !axi_rvalid_i) begin
            if (delay_count == 0) begin
                axi_rvalid_i <= 1;
                axi_rdata_i <= {memory_word(bus_addr + {21'd0, bus_beat, 3'd0} + 4),
                               memory_word(bus_addr + {21'd0, bus_beat, 3'd0})};
                axi_rresp_i <= bus_addr[31:5] == error_line[31:5] && bus_beat == 0 ? 2 : 0;
                axi_rlast_i <= bus_beat == bus_len;
            end else delay_count <= delay_count - 1;
        end
        if (axi_rvalid_i && axi_rready_o) begin
            axi_rvalid_i <= 0;
            bus_beat <= bus_beat + 1;
            delay_count <= cycles % 3;
            if (axi_rlast_i) bus_busy <= 0;
        end
    end
    task automatic tick;
        @(posedge clk_i);
        #1;
    endtask
    task automatic step;
        @(negedge clk_i);
    endtask
    task automatic request(input [31:0] pc);
        step();
        ic_req_valid_i = 1;
        ic_req_addr_i = pc;
        while (!ic_req_ready_o) step();
        tick();
        step();
        ic_req_valid_i = 0;
    endtask
    task automatic drain;
        while (pull != push) tick();
        step();
    endtask
    task automatic invalidate;
        step();
        while (!ic_inv_ready_o) step();
        ic_inv_valid_i = 1;
        tick();
        step();
        ic_inv_valid_i = 0;
        for (int n = 1; n <= 512; n++) begin
            tick();
            if (ic_inv_done_o != (n == 512)) $fatal(1, "invalidate scan cycle%0d", n);
        end
    endtask
    initial begin
        #3000000;
        $fatal(1, "timeout push%0d pull%0d", push, pull);
    end
    initial begin
        ic_resp_ready_i = 1;
        repeat (2) tick();
        step();
        rst_n_i = 1;
        for (int n = 1; n <= 512; n++) begin
            tick();
            if (ic_req_ready_o != (n == 512)) $fatal(1, "reset scan cycle%0d", n);
        end
        // Fill both ways, then stream hits at II=1, including all data words.
        request(32'h10000000);
        request(32'h10000008);
        drain();
        request(32'h10004000);
        drain();
        for (int i = 0; i < 8; i++) request(32'h10000000 + 32'((i%4)*8));
        drain();
        begin
            int start_ar;
            int start_resp;
            start_ar = ar_count;
            start_resp = responses;
            step();
            ic_req_valid_i = 1;
            ic_req_addr_i = 32'h10000000;
            repeat (12) begin
                tick();
                if (!ic_req_ready_o || !ic_resp_valid_o)
                    $fatal(1, "warm hit throughput");
                step();
            end
            ic_req_valid_i = 0;
            drain();
            if (ar_count != start_ar || responses != start_resp + 12)
                $fatal(1, "warm stream issued AXI or lost group");
        end
        // Response backpressure fills the two reserved group contexts.
        ic_resp_ready_i = 0;
        request(32'h10000000);
        request(32'h10000008);
        repeat (3) tick();
        if (ic_req_ready_o) $fatal(1, "more than two contexts accepted");
        step();
        ic_resp_ready_i = 1;
        drain();
        if (ISSUE_WIDTH == 2) begin
            request(32'h1000001c);
            drain();
            request(32'h1000001c);
            drain();
            begin
                int start_ar;
                start_ar = ar_count;
                step();
                ic_req_valid_i = 1;
                ic_req_addr_i = 32'h1000001c;
                repeat (8) begin
                    tick();
                    if (!ic_req_ready_o || !ic_resp_valid_o)
                        $fatal(1, "cross-line hit throughput");
                    step();
                end
                ic_req_valid_i = 0;
                drain();
                if (ar_count != start_ar) $fatal(1, "cross-line warm miss");
            end
            request(32'h00000004);
            drain();
        end
        request(32'h00000000);
        drain();
        request(32'h20000000);
        request(32'hc0000000);
        drain();
        error_line = 32'h80000020;
        request(32'h80000020);
        drain();
        begin
            int start_ar;
            start_ar = ar_count;
            request(32'h80000020);
            drain();
            if (ar_count != start_ar + 1) $fatal(1, "failed fill installed valid tag");
        end
        if (ISSUE_WIDTH == 2) begin
            request(32'h8000001c);
            drain();
            invalidate();
            error_line = 32'h80000000;
            request(32'h8000001c);
            drain();
        end
        error_line = 32'hffffffff;
        invalidate();
        request(32'h10000000);
        drain();
        // Cancel a miss while its AXI burst is active, then reuse contexts.
        request(32'h80001000);
        while (!bus_busy) tick();
        step();
        ic_cancel_i = 1;
        tick();
        step();
        ic_cancel_i = 0;
        while (!ic_req_ready_o) tick();
        request(32'h80001000);
        drain();
        // Invalidate overlaps a live refill; it drains but must not install.
        request(32'h80002000);
        while (!bus_busy) tick();
        invalidate();
        drain();
        begin
            int start_ar;
            start_ar = ar_count;
            request(32'h80002000);
            drain();
            if (ar_count != start_ar + 1) $fatal(1, "overlap fill survived invalidation");
        end
        // A late AXI return after the 512-cycle scan still must not install the old fill.
        long_delay = 1;
        request(32'h80003000);
        while (!bus_busy) tick();
        invalidate();
        drain();
        long_delay = 0;
        begin
            int start_ar;
            start_ar = ar_count;
            request(32'h80003000);
            drain();
            if (ar_count != start_ar + 1) $fatal(1, "late fill survived invalidation");
        end
        // All 512 set indices, line offsets and three competing tags.
        for (int i = 0; i < 512; i++) begin
            request(32'h80000000 + 32'(i*32));
            drain();
        end
        for (int i = 0; i < 3; i++) begin
            request(32'h80010000 + 32'(i*16384));
            drain();
        end
        $display("PASS cpu2_icache ISSUE_WIDTH=%0d groups=%0d AR=%0d miss=%0d",
                 ISSUE_WIDTH, responses, ar_count, misses);
        $finish;
    end
endmodule
