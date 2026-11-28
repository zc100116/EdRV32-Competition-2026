// File: tb.sv
// Spec: cpu-v2-testplan CV11/CV13; fpu-spec 5.5.
// Description: External D$ responder checks preparation, authorization and ordered beat errors.
// Clock: clk_sys.
module tb # (parameter FORMAT = 2);
    localparam FPU_FORMAT = FORMAT == 2 ? "FD" : FORMAT == 1 ? "F" : "NONE";
    localparam T = FORMAT == 2 ? 4 : FORMAT == 1 ? 3 : 2;
    localparam B = FORMAT == 2 ? 64 : 32;
    reg clk_i = 0;
    reg rst_n_i = 0;
    reg lsu_req_valid_i = 0;
    wire lsu_req_ready_o;
    reg [T-1:0] lsu_req_tag_i = 0;
    reg [31:0] lsu_req_instr_i = 0;
    reg [31:0] lsu_req_addr_i = 0;
    reg [B-1:0] lsu_req_store_data_i = 0;
    reg lsu_req_early_i = 0;
    reg early_req_valid_i = 0;
    reg [31:0] early_req_addr_i = 0;
    reg [T-1:0] early_req_tag_i = 0;
    wire early_resp_valid_o;
    wire [T-1:0] early_resp_tag_o;
    wire early_resp_hit_o;
    wire [31:0] early_resp_data_o;
    reg [T-1:0] age_head_i = 0;
    reg cancel_valid_i = 0;
    reg [T-1:0] cancel_tag_i = 0;
    wire lsu_complete_valid_o;
    wire [T-1:0] lsu_complete_tag_o;
    wire [B-1:0] lsu_complete_data_o;
    wire [4:0] lsu_complete_flags_o;
    wire lsu_complete_exception_o;
    wire [3:0] lsu_complete_cause_o;
    wire [31:0] lsu_complete_tval_o;
    wire lsu_complete_device_o;
    wire [31:0] lsu_complete_mem_addr_o;
    wire [63:0] lsu_complete_mem_data_o;
    wire [7:0] lsu_complete_mem_mask_o;
    reg lsu_complete_ready_i = 0;
    reg commit_lsu_valid_i = 0;
    wire commit_lsu_ready_o;
    reg [T-1:0] commit_lsu_tag_i = 0;
    wire commit_lsu_done_valid_o;
    reg commit_lsu_done_ready_i = 0;
    wire [T-1:0] commit_lsu_done_tag_o;
    wire commit_lsu_done_error_o;
    wire [31:0] commit_lsu_done_fault_addr_o;
    wire [B-1:0] commit_lsu_done_data_o;
    wire dc_req_valid_o;
    reg dc_req_ready_i = 0;
    wire [T-1:0] dc_req_tag_o;
    wire dc_req_beat_o;
    wire [31:0] dc_req_addr_o;
    wire dc_req_store_o;
    wire [1:0] dc_req_size_o;
    wire [31:0] dc_req_data_o;
    wire [3:0] dc_req_mask_o;
    wire dc_req_early_o;
    reg dc_resp_valid_i = 0;
    wire dc_resp_ready_o;
    reg [T-1:0] dc_resp_tag_i = 0;
    reg dc_resp_beat_i = 0;
    reg [1:0] dc_resp_way_hit_i = 0;
    reg [31:0] dc_resp_way0_data_i = 0;
    reg [31:0] dc_resp_way1_data_i = 0;
    reg dc_resp_error_i = 0;
    reg dc_resp_device_i = 0;
    wire dc_commit_valid_o;
    reg dc_commit_ready_i = 0;
    wire [T-1:0] dc_commit_tag_o;
    wire dc_commit_beat_o;
    wire [31:0] dc_commit_data_o;
    wire [3:0] dc_commit_mask_o;
    reg dc_done_valid_i = 0;
    wire dc_done_ready_o;
    reg [T-1:0] dc_done_tag_i = 0;
    reg dc_done_beat_i = 0;
    reg dc_done_error_i = 0;
    reg [31:0] dc_done_data_i = 0;
    wire dc_cancel_valid_o;
    wire [T-1:0] dc_cancel_tag_o;
    wire [T-1:0] dc_age_head_o;
    wire dc_early_valid_o;
    wire [31:0] dc_early_addr_o;
    wire [T-1:0] dc_early_tag_o;
    reg dc_early_resp_valid_i = 0;
    reg [T-1:0] dc_early_resp_tag_i = 0;
    reg [1:0] dc_early_hit_i = 0;
    reg [31:0] dc_early_way0_data_i = 0;
    reg [31:0] dc_early_way1_data_i = 0;
    always #5 clk_i = ~clk_i;
    edrv32_cpu2_lsu #(.FPU_FORMAT(FPU_FORMAT)) dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .lsu_req_valid_i(lsu_req_valid_i),
        .lsu_req_ready_o(lsu_req_ready_o),
        .lsu_req_tag_i(lsu_req_tag_i),
        .lsu_req_instr_i(lsu_req_instr_i),
        .lsu_req_addr_i(lsu_req_addr_i),
        .lsu_req_store_data_i(lsu_req_store_data_i),
        .lsu_req_early_i(lsu_req_early_i),
        .early_req_valid_i(early_req_valid_i),
        .early_req_addr_i(early_req_addr_i),
        .early_req_tag_i(early_req_tag_i),
        .early_resp_valid_o(early_resp_valid_o),
        .early_resp_tag_o(early_resp_tag_o),
        .early_resp_hit_o(early_resp_hit_o),
        .early_resp_data_o(early_resp_data_o),
        .age_head_i(age_head_i),
        .cancel_valid_i(cancel_valid_i),
        .cancel_tag_i(cancel_tag_i),
        .lsu_complete_valid_o(lsu_complete_valid_o),
        .lsu_complete_tag_o(lsu_complete_tag_o),
        .lsu_complete_data_o(lsu_complete_data_o),
        .lsu_complete_flags_o(lsu_complete_flags_o),
        .lsu_complete_exception_o(lsu_complete_exception_o),
        .lsu_complete_cause_o(lsu_complete_cause_o),
        .lsu_complete_tval_o(lsu_complete_tval_o),
        .lsu_complete_device_o(lsu_complete_device_o),
        .lsu_complete_mem_addr_o(lsu_complete_mem_addr_o),
        .lsu_complete_mem_data_o(lsu_complete_mem_data_o),
        .lsu_complete_mem_mask_o(lsu_complete_mem_mask_o),
        .lsu_complete_ready_i(lsu_complete_ready_i),
        .commit_lsu_valid_i(commit_lsu_valid_i),
        .commit_lsu_ready_o(commit_lsu_ready_o),
        .commit_lsu_tag_i(commit_lsu_tag_i),
        .commit_lsu_done_valid_o(commit_lsu_done_valid_o),
        .commit_lsu_done_ready_i(commit_lsu_done_ready_i),
        .commit_lsu_done_tag_o(commit_lsu_done_tag_o),
        .commit_lsu_done_error_o(commit_lsu_done_error_o),
        .commit_lsu_done_fault_addr_o(commit_lsu_done_fault_addr_o),
        .commit_lsu_done_data_o(commit_lsu_done_data_o),
        .dc_req_valid_o(dc_req_valid_o),
        .dc_req_ready_i(dc_req_ready_i),
        .dc_req_tag_o(dc_req_tag_o),
        .dc_req_beat_o(dc_req_beat_o),
        .dc_req_addr_o(dc_req_addr_o),
        .dc_req_store_o(dc_req_store_o),
        .dc_req_size_o(dc_req_size_o),
        .dc_req_data_o(dc_req_data_o),
        .dc_req_mask_o(dc_req_mask_o),
        .dc_req_early_o(dc_req_early_o),
        .dc_resp_valid_i(dc_resp_valid_i),
        .dc_resp_ready_o(dc_resp_ready_o),
        .dc_resp_tag_i(dc_resp_tag_i),
        .dc_resp_beat_i(dc_resp_beat_i),
        .dc_resp_way_hit_i(dc_resp_way_hit_i),
        .dc_resp_way0_data_i(dc_resp_way0_data_i),
        .dc_resp_way1_data_i(dc_resp_way1_data_i),
        .dc_resp_error_i(dc_resp_error_i),
        .dc_resp_device_i(dc_resp_device_i),
        .dc_commit_valid_o(dc_commit_valid_o),
        .dc_commit_ready_i(dc_commit_ready_i),
        .dc_commit_tag_o(dc_commit_tag_o),
        .dc_commit_beat_o(dc_commit_beat_o),
        .dc_commit_data_o(dc_commit_data_o),
        .dc_commit_mask_o(dc_commit_mask_o),
        .dc_done_valid_i(dc_done_valid_i),
        .dc_done_ready_o(dc_done_ready_o),
        .dc_done_tag_i(dc_done_tag_i),
        .dc_done_beat_i(dc_done_beat_i),
        .dc_done_error_i(dc_done_error_i),
        .dc_done_data_i(dc_done_data_i),
        .dc_cancel_valid_o(dc_cancel_valid_o),
        .dc_cancel_tag_o(dc_cancel_tag_o),
        .dc_age_head_o(dc_age_head_o),
        .dc_early_valid_o(dc_early_valid_o),
        .dc_early_addr_o(dc_early_addr_o),
        .dc_early_tag_o(dc_early_tag_o),
        .dc_early_resp_valid_i(dc_early_resp_valid_i),
        .dc_early_resp_tag_i(dc_early_resp_tag_i),
        .dc_early_hit_i(dc_early_hit_i),
        .dc_early_way0_data_i(dc_early_way0_data_i),
        .dc_early_way1_data_i(dc_early_way1_data_i)
    );
    int requests = 0;
    int served = 0;
    int commits = 0;
    int commit_served = 0;
    reg [31:0] committed_data [0:127];
    reg [T-1:0] committed_tag [0:127];
    reg committed_beat [0:127];
    reg [31:0] request_addr [0:127];
    reg [T-1:0] request_tag [0:127];
    reg request_beat [0:127];
    always @(posedge clk_i) begin
        if (dc_req_valid_o && dc_req_ready_i) begin
            request_addr[requests % 128] = dc_req_addr_o;
            request_tag[requests % 128] = dc_req_tag_o;
            request_beat[requests % 128] = dc_req_beat_o;
            requests = requests + 1;
        end
        if (cancel_valid_i && served < requests &&
            T'(request_tag[served % 128] - age_head_i) >= T'(cancel_tag_i - age_head_i))
            served = requests;
        if (dc_commit_valid_o && dc_commit_ready_i) begin
            committed_data[commits % 128] = dc_commit_data_o;
            committed_tag[commits % 128] = dc_commit_tag_o;
            committed_beat[commits % 128] = dc_commit_beat_o;
            commits = commits + 1;
        end
    end
    initial begin
        #100000;
        $fatal(1, "timeout");
    end
    task automatic tick;
        @(posedge clk_i);
        #1;
    endtask
    task automatic step;
        @(negedge clk_i);
    endtask
    task automatic issue(input [31:0] instr, input [31:0] addr,
                         input [63:0] data, input [T-1:0] tag);
        step();
        if (!lsu_req_ready_o) $fatal(1, "LSU not ready");
        lsu_req_valid_i = 1;
        lsu_req_instr_i = instr;
        lsu_req_addr_i = addr;
        lsu_req_store_data_i = B'(data);
        lsu_req_tag_i = tag;
        early_req_valid_i = lsu_req_early_i;
        early_req_addr_i = addr;
        early_req_tag_i = tag;
        tick();
        step();
        lsu_req_valid_i = 0;
        early_req_valid_i = 0;
        #1;
    endtask
    task automatic prep(input bit beat, input [31:0] addr, input [31:0] value,
                        input bit device, input bit error);
        while (served >= requests) begin
            tick();
            step();
        end
        if (request_beat[served % 128] != beat || request_addr[served % 128] != addr ||
            request_tag[served % 128] != lsu_req_tag_i)
            $fatal(1, "request association beat%0d addr%h", request_beat[served % 128],
                   request_addr[served % 128]);
        served++;
        dc_resp_valid_i = 1;
        dc_resp_tag_i = lsu_req_tag_i;
        dc_resp_beat_i = beat;
        dc_resp_error_i = error;
        dc_resp_device_i = device;
        dc_resp_way_hit_i = 2'b10;
        dc_resp_way1_data_i = value;
        dc_resp_way0_data_i = ~value;
        #1;
        if ((error || lsu_req_instr_i[14:12] != 3 || FORMAT != 2 || beat) &&
            !lsu_complete_valid_o) $fatal(1, "completion did not fall through D$ response");
        if (!error && FORMAT == 2 && lsu_req_instr_i[14:12] == 3 && !beat &&
            lsu_complete_valid_o) $fatal(1, "FD completed before high beat");
        tick();
        step();
        dc_resp_valid_i = 0;
        dc_resp_error_i = 0;
        dc_resp_device_i = 0;
    endtask
    task automatic complete(input [63:0] value, input bit device,
                            input bit error, input [3:0] cause, input [31:0] fault);
        while (!lsu_complete_valid_o) step();
        if (lsu_complete_tag_o != lsu_req_tag_i || lsu_complete_exception_o != error ||
            lsu_complete_device_o != device || lsu_complete_flags_o != 0)
            $fatal(1, "completion control");
        if (!error && !device && !lsu_req_instr_i[5] && lsu_complete_data_o !== B'(value))
            $fatal(1, "complete data expected %h actual %h", B'(value), lsu_complete_data_o);
        if (error && (lsu_complete_cause_o != cause || lsu_complete_tval_o != fault))
            $fatal(1, "completion fault expected %h/%h actual %h/%h", cause, fault,
                   lsu_complete_cause_o, lsu_complete_tval_o);
        if (!error && !device) begin
            reg [63:0] bytes;
            reg [63:0] raw;
            reg [7:0] mask;
            mask = FORMAT == 2 && lsu_req_instr_i[2] && lsu_req_instr_i[14:12] == 3 ? 8'hff :
                lsu_req_instr_i[2] || lsu_req_instr_i[13] ? 8'h0f :
                lsu_req_instr_i[12] ? 8'h03 : 8'h01;
            bytes = 0;
            for (int i = 0; i < 8; i++) bytes[i*8 +: 8] = {8{mask[i]}};
            raw = lsu_req_instr_i[5] ? 64'(lsu_req_store_data_i) : value;
            if (lsu_complete_mem_mask_o != mask || lsu_complete_mem_data_o != (raw & bytes) ||
                lsu_complete_mem_addr_o != lsu_req_addr_i)
                $fatal(1, "raw trace mask%h data%h expected%h/%h", lsu_complete_mem_mask_o,
                       lsu_complete_mem_data_o, mask, raw & bytes);
        end
        repeat (3) begin
            tick();
            if (!lsu_complete_valid_o) $fatal(1, "completion lost under backpressure");
        end
        step();
        lsu_complete_ready_i = 1;
        tick();
        step();
        lsu_complete_ready_i = 0;
    endtask
    task automatic authorize;
        repeat (2) begin
            tick();
            if (dc_commit_valid_o) $fatal(1, "side effect before authorization");
        end
        step();
        if (!commit_lsu_ready_o) $fatal(1, "not ready for authorization");
        commit_lsu_tag_i = lsu_req_tag_i;
        commit_lsu_valid_i = 1;
        #1;
        if ((lsu_req_instr_i[5] || lsu_req_addr_i[31:28] == 4'h2) &&
            dc_commit_ready_i && (!dc_commit_valid_o || dc_commit_beat_o))
            $fatal(1, "authorization did not fall through to first beat");
        tick();
        step();
        commit_lsu_valid_i = 0;
    endtask
    task automatic beat_done(input bit beat, input [31:0] expected_store,
                             input [31:0] returned_data, input bit error);
        while (commit_served >= commits) step();
        if (committed_tag[commit_served % 128] != lsu_req_tag_i ||
            committed_beat[commit_served % 128] != beat ||
            committed_data[commit_served % 128] != expected_store)
            $fatal(1, "commit association/data beat %b data %h", committed_beat[commit_served % 128],
                   committed_data[commit_served % 128]);
        commit_served++;
        step();
        dc_done_valid_i = 1;
        dc_done_tag_i = lsu_req_tag_i;
        dc_done_beat_i = beat;
        dc_done_error_i = error;
        dc_done_data_i = returned_data;
        #1;
        if ((error || beat || FORMAT != 2 || lsu_req_instr_i[14:12] != 3) &&
            (!commit_lsu_done_valid_o || commit_lsu_done_error_o != error))
            $fatal(1, "final D$ done did not fall through to commit");
        tick();
        step();
        dc_done_valid_i = 0;
    endtask
    task automatic done(input [63:0] expected, input bit error, input [31:0] fault);
        while (!commit_lsu_done_valid_o) step();
        if (commit_lsu_done_tag_o != lsu_req_tag_i || commit_lsu_done_error_o != error)
            $fatal(1, "done association/error");
        if (error && commit_lsu_done_fault_addr_o != fault)
            $fatal(1, "done fault expected %h actual %h", fault, commit_lsu_done_fault_addr_o);
        if (!error && !lsu_req_instr_i[5] && commit_lsu_done_data_o != B'(expected))
            $fatal(1, "done data expected %h actual %h", B'(expected), commit_lsu_done_data_o);
        repeat (3) tick();
        step();
        commit_lsu_done_ready_i = 1;
        tick();
        step();
        commit_lsu_done_ready_i = 0;
    endtask
    initial begin
        dc_req_ready_i = 1;
        dc_commit_ready_i = 1;
        repeat (2) tick();
        step();
        rst_n_i = 1;
        begin
            int before_req;
            before_req = requests;
            issue(32'h2003, 32'h10000000, 0, T'(0));
            if (requests != before_req + 1) $fatal(1, "extra request register before D$");
            lsu_complete_ready_i = 1;
            dc_resp_valid_i = 1;
            dc_resp_way_hit_i = 2'b01;
            dc_resp_way0_data_i = 32'h89abcdef;
            #1;
            if (!lsu_complete_valid_o || lsu_complete_data_o != B'(32'h89abcdef))
                $fatal(1, "hit fall-through result");
            tick();
            step();
            dc_resp_valid_i = 0;
            served = requests;
            lsu_complete_ready_i = 0;
            if (!lsu_req_ready_o || lsu_complete_valid_o)
                $fatal(1, "fall-through result was delivered twice");
        end
        // A downstream request remains stable until D$ accepts it.
        dc_req_ready_i = 0;
        issue(32'h2003, 32'h10000004, 0, T'(1));
        repeat (3) begin
            tick();
            if (!dc_req_valid_o || dc_req_addr_o != 32'h10000004 ||
                dc_req_tag_o != T'(1) || dc_req_size_o != 2 || dc_req_store_o)
                $fatal(1, "request changed under backpressure");
        end
        step();
        dc_req_ready_i = 1;
        prep(0, 32'h10000004, 32'h01234567, 0, 0);
        complete(64'h01234567, 0, 0, 0, 0);
        // An ordinary request already asserted under backpressure keeps the shared read port.
        dc_req_ready_i = 0;
        issue(32'h2003, 32'h10000008, 0, T'(1));
        early_req_valid_i = 1;
        early_req_addr_i = 32'h1000000c;
        early_req_tag_i = T'(2);
        #1;
        if (dc_early_valid_o || !dc_req_valid_o) $fatal(1, "held ordinary lost reservation");
        tick();
        step();
        early_req_valid_i = 0;
        tick();
        if (!early_resp_valid_o || early_resp_tag_o != T'(2) || early_resp_hit_o)
            $fatal(1, "blocked early query missing fixed failure response");
        step();
        cancel_valid_i = 1;
        cancel_tag_i = T'(2);
        tick();
        step();
        cancel_valid_i = 0;
        dc_req_ready_i = 1;
        prep(0, 32'h10000008, 32'h76543210, 0, 0);
        complete(64'h76543210, 0, 0, 0, 0);
        // A successful query cannot forward if its corresponding ordinary request was delayed.
        dc_req_ready_i = 0;
        lsu_req_early_i = 1;
        issue(32'h2003, 32'h1000000c, 0, T'(2));
        dc_early_resp_valid_i = 1;
        dc_early_resp_tag_i = T'(2);
        dc_early_hit_i = 2'b01;
        dc_early_way0_data_i = 32'h11223344;
        tick();
        if (!early_resp_valid_o || early_resp_hit_o) $fatal(1, "unaccepted early result used");
        step();
        dc_early_resp_valid_i = 0;
        dc_req_ready_i = 1;
        prep(0, 32'h1000000c, 32'h11223344, 0, 0);
        complete(64'h11223344, 0, 0, 0, 0);
        lsu_req_early_i = 0;
        // Integer signed/unsigned byte, halfword and word responses are already byte shifted.
        for (int f = 0; f < 6; f++) begin
            if (f != 3) begin
                issue(32'h00000003 | (32'(f) << 12), 32'h10000000, 0, T'(f));
                prep(0, 32'h10000000, 32'h12348081, 0, 0);
                case (f)
                    0: complete(64'hffffff81, 0, 0, 0, 0);
                    1: complete(64'hffff8081, 0, 0, 0, 0);
                    4: complete(64'h81, 0, 0, 0, 0);
                    5: complete(64'h8081, 0, 0, 0, 0);
                    default: complete(64'h12348081, 0, 0, 0, 0);
                endcase
            end
        end
        // Alignment fails before any D$ request; correct load/store causes and original address.
        for (int f = 0; f < 2; f++) begin
            int old_requests;
            old_requests = requests;
            issue(f == 0 ? 32'h2003 : 32'h2023, 32'h10000002, 0, T'(1));
            complete(0, 0, 1, f == 0 ? 4 : 6, 32'h10000002);
            if (requests != old_requests) $fatal(1, "misaligned request escaped");
        end
        issue(32'h2023, 32'h10000000, 64'h55667788, T'(2));
        prep(0, 32'h10000000, 0, 0, 0);
        complete(0, 0, 0, 0, 0);
        authorize();
        beat_done(0, 32'h55667788, 0, 0);
        done(0, 0, 0);
        // Ready final consumer retires on the D$ done edge, with no DONE bubble.
        issue(32'h2023, 32'h10000004, 64'h12345678, T'(2));
        prep(0, 32'h10000004, 0, 0, 0);
        complete(0, 0, 0, 0, 0);
        authorize();
        commit_lsu_done_ready_i = 1;
        beat_done(0, 32'h12345678, 0, 0);
        if (!lsu_req_ready_o) $fatal(1, "final done retained an unnecessary busy cycle");
        commit_lsu_done_ready_i = 0;
        issue(32'h0003, 32'h20000001, 0, T'(3));
        prep(0, 32'h20000001, 0, 1, 0);
        complete(0, 1, 0, 0, 0);
        authorize();
        beat_done(0, 0, 32'h80, 0);
        done(64'hffffff80, 0, 0);
        issue(32'h2003, 32'h10000000, 0, T'(1));
        prep(0, 32'h10000000, 0, 0, 1);
        complete(0, 0, 1, 5, 32'h10000000);
        if (FORMAT != 0) begin
            issue(32'h2007, 32'h10000000, 0, T'(1));
            prep(0, 32'h10000000, 32'h3f800000, 0, 0);
            complete(FORMAT == 2 ? 64'hffffffff3f800000 : 64'h3f800000, 0, 0, 0, 0);
        end
        if (FORMAT == 2) begin
            // Last legal D offset: low word at24, high at28; no line crossing.
            issue(32'h3007, 32'h10000018, 0, T'(4));
            prep(0, 32'h10000018, 32'h89abcdef, 0, 0);
            prep(1, 32'h1000001c, 32'h01234567, 0, 0);
            complete(64'h0123456789abcdef, 0, 0, 0, 0);
            authorize();
            done(64'h0123456789abcdef, 0, 0);
            issue(32'h3007, 32'h10000018, 0, T'(4));
            prep(0, 32'h10000018, 0, 0, 0);
            prep(1, 32'h1000001c, 0, 0, 1);
            complete(0, 0, 1, 5, 32'h1000001c);
            issue(32'h3027, 32'h20000018, 64'h1122334455667788, T'(5));
            prep(0, 32'h20000018, 0, 1, 0);
            prep(1, 32'h2000001c, 0, 1, 0);
            complete(0, 1, 0, 0, 0);
            authorize();
            beat_done(0, 32'h55667788, 0, 0);
            beat_done(1, 32'h11223344, 0, 1);
            done(0, 1, 32'h2000001c);
            issue(32'h3007, 32'h20000018, 0, T'(6));
            prep(0, 32'h20000018, 0, 1, 0);
            prep(1, 32'h2000001c, 0, 1, 0);
            complete(0, 1, 0, 0, 0);
            authorize();
            beat_done(0, 0, 32'h76543210, 0);
            beat_done(1, 0, 32'hfedcba98, 0);
            done(64'hfedcba9876543210, 0, 0);
            issue(32'h3027, 32'h20000018, 64'h1122334455667788, T'(7));
            prep(0, 32'h20000018, 0, 1, 0);
            prep(1, 32'h2000001c, 0, 1, 0);
            complete(0, 1, 0, 0, 0);
            authorize();
            beat_done(0, 32'h55667788, 0, 1);
            done(0, 1, 32'h20000018);
            if (dc_commit_valid_o) $fatal(1, "high beat issued after low failure");
            issue(32'h3007, 32'h1000001c, 0, T'(8));
            complete(0, 0, 1, 4, 32'h1000001c);
        end
        // Wrap-relative cancellation of a prepared store, including a held completion.
        age_head_i = T'(3);
        issue(32'h2023, 32'h10000000, 1, T'(0));
        prep(0, 32'h10000000, 0, 0, 0);
        step();
        cancel_tag_i = T'(0);
        cancel_valid_i = 1;
        tick();
        step();
        cancel_valid_i = 0;
        if (!lsu_req_ready_o || lsu_complete_valid_o || dc_commit_valid_o)
            $fatal(1, "canceled instance survived");
        // Cancellation also owns a newly accepted request on the same edge.
        cancel_valid_i = 1;
        cancel_tag_i = T'(0);
        issue(32'h2003, 32'h10000000, 0, T'(0));
        if (!lsu_req_ready_o || dc_req_valid_o || lsu_complete_valid_o)
            $fatal(1, "same-edge allocation survived cancellation");
        cancel_valid_i = 0;
        // Correlated early LB data is captured locally with ISA sign extension.
        lsu_req_early_i = 1;
        issue(32'h0003, 32'h10000000, 0, T'(2));
        dc_early_resp_valid_i = 1;
        dc_early_resp_tag_i = T'(2);
        dc_early_hit_i = 2'b10;
        dc_early_way1_data_i = 32'h12348081;
        fork
            prep(0, 32'h10000000, 32'h12348081, 0, 0);
            begin
                tick();
                if (!early_resp_valid_o || early_resp_tag_o != T'(2) || !early_resp_hit_o ||
                    early_resp_data_o != 32'hffffff81) $fatal(1, "early LB capture");
                step();
                dc_early_resp_valid_i = 0;
            end
        join
        dc_early_resp_valid_i = 0;
        complete(64'hffffff81, 0, 0, 0, 0);
        lsu_req_early_i = 0;
        $display("PASS cpu2_lsu FORMAT=%0d requests=%0d commits=%0d", FORMAT, requests, commits);
        $finish;
    end
endmodule
