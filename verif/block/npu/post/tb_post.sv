// File: tb_post.sv
// Spec: npu-spec 2.6, 3, 4, 5.5/5.6; npu-testplan PP-01-13/PP-P-01.
// Description: Public APB/AXI only; independent reference and completion fences.
// Clock domains: clk_npu 180 MHz, clk_mem 125 MHz.
`timescale 1ns/1ps
module tb_post;
    bit clk_mem = 0;
    bit clk_npu = 0;
    bit rst_mem_n = 0;
    bit rst_npu_n = 0;
    wire irq;
    int checker_errors;
    int start_cycle;
    int npu_cycle;
    int last_raw_b;
    int last_candidate_b;
    int first_gather;
    int last_table;
    int candidate_bytes;
    int gather_bytes;
    int table_bytes[3];
    int table_pending;
    int table_wait_cycles;
    int done_edges;
    int post_ctrl;
    int raw_bytes;
    bit previous_irq;
    bit running;
    bit [31:0] output_base;
    bit [31:0] post_base;
    bit [31:0] model_base;
    bit [31:0] desc_base;
    bit [31:0] table_base[3];
    int desc_count;
    int expected_count;
    int expected_post;
    int done_before;
    string case_dir;
    string test_id;
    string frame2_dir;
    int fault_phase;
    int abort_phase;
    typedef struct packed {
        bit [31:0] addr;
        int bytes;
    } request_t;
    request_t pending_w[$];
    request_t pending_b[$];
    request_t pending_r[$];
    byte unsigned reference[bit [31:0]];
    byte unsigned first_frame[bit [31:0]];
    edrv32_axi256_if axi();
    edrv32_apb_if apb();
    post_mem u_mem (
        .clk_i(clk_mem),
        .rst_n_i(rst_mem_n),
        .bus(axi)
    );
    edrv32_axi256_checker u_checker (
        .clk_i(clk_mem),
        .rst_n_i(rst_mem_n),
        .bus(axi),
        .errors_o(checker_errors)
    );
    edrv32_apb_checker u_apb_checker (
        .clk_i(clk_mem),
        .rst_n_i(rst_mem_n),
        .bus(apb)
    );
    initial forever #(500.0/180.0) clk_npu = ~clk_npu;
    initial forever #4 clk_mem = ~clk_mem;
    always @(posedge clk_npu) begin
        npu_cycle++;
        if (running && table_pending != 0) table_wait_cycles++;
        if (running && irq && !previous_irq) begin
            done_edges++;
            if (fault_phase == 0 && abort_phase == 0) begin
                check(u_mem.read_outstanding == 0 && u_mem.write_outstanding == 0,
                    "DONE IRQ before final AXI drain");
                check(raw_bytes == (post_ctrl == 1 ? 322560 : 725760),
                    "DONE IRQ before raw completion");
                check(candidate_bytes == ((expected_count*24+31)/32)*32,
                    "DONE IRQ before candidate writes");
            end
        end
        previous_irq = irq;
    end
edrv32_npu u_dut (
    .clk_npu_i(clk_npu),
    .rst_npu_n_i(rst_npu_n),
    .clk_mem_i(clk_mem),
    .rst_mem_n_i(rst_mem_n),

    .apb_paddr_i(apb.paddr),
    .apb_psel_i(apb.psel[0]),
    .apb_penable_i(apb.penable),
    .apb_pwrite_i(apb.pwrite),
    .apb_pwdata_i(apb.pwdata),
    .apb_pstrb_i(apb.pstrb),
    .apb_pready_o(apb.pready[0]),
    .apb_prdata_o(apb.prdata[31:0]),
    .apb_pslverr_o(apb.pslverr[0]),

    .axi_awid_o(axi.awid),
    .axi_awaddr_o(axi.awaddr),
    .axi_awlen_o(axi.awlen),
    .axi_awvalid_o(axi.awvalid),
    .axi_awready_i(axi.awready),
    .axi_wdata_o(axi.wdata),
    .axi_wstrb_o(axi.wstrb),
    .axi_wlast_o(axi.wlast),
    .axi_wvalid_o(axi.wvalid),
    .axi_wready_i(axi.wready),
    .axi_bid_i(axi.bid),
    .axi_bresp_i(axi.bresp),
    .axi_bvalid_i(axi.bvalid),
    .axi_bready_o(axi.bready),
    .axi_arid_o(axi.arid),
    .axi_araddr_o(axi.araddr),
    .axi_arlen_o(axi.arlen),
    .axi_arvalid_o(axi.arvalid),
    .axi_arready_i(axi.arready),
    .axi_rid_i(axi.rid),
    .axi_rdata_i(axi.rdata),
    .axi_rresp_i(axi.rresp),
    .axi_rlast_i(axi.rlast),
    .axi_rvalid_i(axi.rvalid),
    .axi_rready_o(axi.rready),

    .irq_o(irq)
);
assign apb.pready[15:1] = 0;
assign apb.prdata[511:32] = 0;
assign apb.pslverr[15:1] = 0;
    task automatic check(input bit condition, input string message);
        if (!condition) $fatal(1, "FAIL %s test=%s time=%0t", message, test_id, $time);
    endtask

    task automatic access(input bit write, input bit [11:0] addr,
        input bit [31:0] value, output bit [31:0] result);
        @(negedge clk_mem);
        apb.paddr = addr;
        apb.psel = 1;
        apb.penable = 0;
        apb.pwrite = write;
        apb.pwdata = value;
        apb.pstrb = 15;
        @(negedge clk_mem);
        apb.penable = 1;
        do @(posedge clk_mem); while (!apb.pready[0]);
        check(!apb.pslverr[0], $sformatf("APB addr=%03h SLVERR", addr));
        result = apb.prdata[31:0];
        if (write && addr == 'h028) begin
            start_cycle = npu_cycle;
        end
        @(negedge clk_mem);
        apb.psel = 0;
        apb.penable = 0;
    endtask

    task automatic wr(input bit [11:0] addr, input bit [31:0] value);
        bit [31:0] unused_result;
        access(1, addr, value, unused_result);
    endtask

    task automatic rd(input bit [11:0] addr, output bit [31:0] value);
        access(0, addr, 0, value);
    endtask

    task automatic equals(input bit [11:0] addr, input bit [31:0] expected,
        input string name = "");
        bit [31:0] actual;
        rd(addr, actual);
        check(actual == expected, $sformatf("reg=%s addr=%03h expected=%08h actual=%08h",
            name, addr, expected, actual));
    endtask

    function automatic bit [11:0] reg_addr(input string name);
        case (name)
            "MODEL_BASE": return 'h100;
            "WORK_BASE": return 'h104;
            "INPUT_BASE": return 'h108;
            "OUTPUT_BASE": return 'h10c;
            "DESC_BASE": return 'h020;
            "DESC_COUNT": return 'h024;
            "POST_CTRL": return 'h114;
            "POST_BASE": return 'h118;
            "POST_INT8_TH0": return 'h11c;
            "POST_INT8_TH1": return 'h120;
            "POST_INT8_TH2": return 'h124;
            "POST_PROB_TH": return 'h128;
            default: $fatal(1, "FAIL unknown register %s", name);
        endcase
    endfunction

    task automatic load_case(input string path);
        int fd;
        string name;
        bit [31:0] value;
        string token;
        bit [31:0] beat;
        bit [255:0] data;
        int status;
        bit [3:0] tag;
        bit [31:0] offset_value;
        u_mem.load_hex({path, "/mem_state.hex"});
        fd = $fopen({path, "/regs.txt"}, "r");
        check(fd != 0, "missing regs.txt");
        while ($fscanf(fd, "%s %h", name, value) == 2) begin
            wr(reg_addr(name), value);
            equals(reg_addr(name), value);
            case (name)
                "MODEL_BASE": model_base = value;
                "OUTPUT_BASE": output_base = value;
                "POST_BASE": post_base = value;
                "DESC_COUNT": desc_count = int'(value);
                "DESC_BASE": desc_base = value;
                "POST_CTRL": post_ctrl = int'(value);
                default: begin end
            endcase
        end
        $fclose(fd);
        for (int n = 0; n < desc_count; n++) begin
            tag = 4'(u_mem.peek(desc_base+32'(n*64+52)));
            offset_value = 0;
            for (int b = 0; b < 4; b++) begin
                offset_value[b*8+:8] = u_mem.peek(desc_base+32'(n*64+56+b));
            end
            if (tag[1:0] == 1) table_base[tag[3:2]] = model_base+offset_value;
        end
        fd = $fopen({path, "/expected.txt"}, "r");
        check(fd != 0, "missing expected.txt");
        status = $fscanf(fd, "%d %d", expected_count, expected_post);
        check(status == 2, "bad expected.txt");
        $fclose(fd);
        reference.delete();
        fd = $fopen({path, "/ref_out.hex"}, "r");
        check(fd != 0, "missing ref_out.hex");
        beat = 0;
        while ($fscanf(fd, "%s", token) == 1) begin
            if (token.substr(0, 0) == "@")
                status = $sscanf(token.substr(1, token.len()-1), "%h", beat);
            else begin
                status = $sscanf(token, "%h", data);
                for (int b = 0; b < 32; b++) reference[beat*32+32'(b)] = data[b*8 +: 8];
                beat++;
            end
            check(status == 1, "bad reference hex");
        end
        $fclose(fd);
    endtask

    always @(posedge clk_mem) begin : traffic
        request_t request;
        if (rst_mem_n && running) begin
            if (axi.awvalid && axi.awready) begin
                if (post_ctrl == 1) begin
                    check(!(axi.awaddr >= output_base+245760 &&
                        axi.awaddr < output_base+552960), "forbidden head0 cls write");
                    check(!(axi.awaddr >= output_base+614400 &&
                        axi.awaddr < output_base+691200), "forbidden head1 cls write");
                    check(!(axi.awaddr >= output_base+706560 &&
                        axi.awaddr < output_base+725760), "forbidden head2 cls write");
                end
                request.addr = axi.awaddr;
                request.bytes = (int'(axi.awlen)+1)*32;
                pending_w.push_back(request);
            end
            if (axi.wvalid && axi.wready && axi.wlast) begin
                check(pending_w.size() != 0, "W without AW");
                request = pending_w.pop_front();
                pending_b.push_back(request);
                if (request.addr >= post_base && request.addr < post_base+120960)
                    candidate_bytes += request.bytes;
                if (request.addr >= output_base && request.addr < output_base+725760)
                    raw_bytes += request.bytes;
            end
            if (axi.bvalid && axi.bready) begin
                check(pending_b.size() != 0, "B without complete W");
                request = pending_b.pop_front();
                if (request.addr >= post_base && request.addr < post_base+120960)
                    last_candidate_b = npu_cycle;
                else if (request.addr >= output_base && request.addr < output_base+725760)
                    last_raw_b = npu_cycle;
            end
            if (axi.arvalid && axi.arready) begin
                request.addr = axi.araddr;
                request.bytes = (int'(axi.arlen)+1)*32;
                pending_r.push_back(request);
                if (axi.araddr >= output_base && axi.araddr < output_base+725760) begin
                    if (first_gather == 0) first_gather = npu_cycle;
                    gather_bytes += (int'(axi.arlen)+1)*32;
                end
                for (int h = 0; h < 3; h++) begin
                    if (axi.araddr >= table_base[h] && axi.araddr < table_base[h]+2048)
                        begin
                            table_bytes[h] += (int'(axi.arlen)+1)*32;
                            table_pending++;
                        end
                end
            end
            if (axi.rvalid && axi.rready && axi.rlast) begin
                request = pending_r.pop_front();
                for (int h = 0; h < 3; h++)
                    if (request.addr >= table_base[h] && request.addr < table_base[h]+2048)
                        begin
                            last_table = npu_cycle;
                            table_pending--;
                        end
            end
        end
    end

    task automatic before_completion();
        bit [31:0] value;
        rd('h008, value);
        check((value & 7) == 1, "BUSY missing before completion fence");
        equals('h12c, 0, "POST_COUNT before fence");
        equals('h130, 0, "POST_DONE before fence");
        equals('h02c, 32'(done_before), "DONE_COUNT before fence");
        equals('h010, 0, "IRQ before fence");
    endtask

    task automatic idle();
        bit [31:0] value;
        do rd('h008, value); while (value[0]);
        check((value & 3) == 2, "missing IDLE");
        check(u_mem.read_outstanding == 0 && u_mem.write_outstanding == 0,
            "IDLE before AXI drain");
        check(pending_w.size() == 0 && pending_b.size() == 0 && pending_r.size() == 0,
            "unfinished AXI transactions");
    endtask

    task automatic gate(input int phase, input bit abort_it);
        bit target;
        int ar_before;
        int aw_before;
        // Observe the public request before the acceptance edge; never force DUT signals.
        do begin
            @(negedge clk_mem);
            case (phase)
                1: target = axi.arvalid && axi.araddr >= model_base+'h10000 &&
                    axi.araddr < model_base+'h11800;
                2: target = axi.arvalid && axi.araddr >= output_base &&
                    axi.araddr < output_base+725760;
                3: target = axi.awvalid && axi.awaddr >= post_base &&
                    axi.awaddr < post_base+120960;
                4: target = axi.awvalid && axi.awaddr >= output_base+691200 &&
                    axi.awaddr < output_base+706560;
                default: target = 0;
            endcase
        end while (!target);
        if (phase <= 2) u_mem.hold_r = 1;
        else u_mem.hold_b = 1;
        repeat (20) @(negedge clk_mem);
        before_completion();
        if (phase == 2 || phase == 3) equals('h110, 32'(desc_count-1), "tail CUR_DESC");
        if (abort_it) begin
            wr('h004, 4);
            u_mem.hold_r = 0;
            u_mem.hold_b = 0;
            idle();
            equals('h130, 0);
            equals('h02c, 32'(done_before));
            ar_before = u_mem.first_request;
            aw_before = u_mem.last_response;
            repeat (200) begin
                @(negedge clk_mem);
                check(!axi.arvalid && !axi.awvalid, "new request after ABORT drain");
            end
            check(ar_before == u_mem.first_request && aw_before == u_mem.last_response,
                "AXI traffic after abort drain");
        end else begin
            repeat (200) @(negedge clk_mem);
            before_completion();
            u_mem.hold_r = 0;
            u_mem.hold_b = 0;
        end
    endtask

    task automatic finish_frame();
        bit [31:0] value;
        int finish_cycle;
        int dump_file;
        do rd('h010, value); while (value == 0);
        check(value == 1, $sformatf("IRQ expected DONE actual=%h", value));
        finish_cycle = npu_cycle;
        idle();
        equals('h02c, 32'(done_before+1));
        equals('h12c, 32'(expected_count));
        equals('h130, 32'(expected_post));
        equals('h110, 32'(desc_count-1));
        check(done_edges == 1, $sformatf("single IRQ expected=1 actual=%0d", done_edges));
        check(last_candidate_b <= finish_cycle, "DONE precedes final candidate B");
        check(gather_bytes == expected_count*128, "gather traffic != 128B/candidate");
        check(candidate_bytes == ((expected_count*24+31)/32)*32, "candidate beat count");
        check(raw_bytes == (post_ctrl == 1 ? 322560 : 725760), "raw/debug write bytes");
        for (int h = 0; h < 3; h++)
            check(table_bytes[h] == (expected_post == 1 ? 2048 : 0),
                $sformatf("head=%0d table load bytes=%0d", h, table_bytes[h]));
        foreach (reference[address]) begin
            check(u_mem.peek(address) == reference[address],
                $sformatf("addr=%08h expected=%02h actual=%02h", address,
                reference[address], u_mem.peek(address)));
        end
        dump_file = $fopen({case_dir, "/actual_candidates.hex"}, "w");
        for (int b = 0; b < ((expected_count*24+31)/32)*32; b++)
            $fdisplay(dump_file, "%02x", u_mem.peek(post_base+32'(b)));
        $fclose(dump_file);
        repeat (200) @(negedge clk_mem);
        equals('h02c, 32'(done_before+1));
        $display("PERF table_wait_cycles=%0d", table_wait_cycles);
        $display("PERF core_cycles=%0d table_last=%0d drain_gather=%0d tail_cycles=%0d",
            last_raw_b-start_cycle, last_table-start_cycle, first_gather-last_raw_b,
            last_candidate_b-last_raw_b);
        $display("PERF done_cycles=%0d gather_bytes=%0d candidate_bytes=%0d budget=%0d",
            finish_cycle-start_cycle, gather_bytes, candidate_bytes, expected_count*320);
        $display("PERF read_beats=%0d write_beats=%0d raw_bytes=%0d",
            u_mem.read_beats, u_mem.write_beats, raw_bytes);
    endtask

    task automatic start();
        bit [31:0] value;
        wr('h010, 3);
        wr('h00c, 3);
        rd('h02c, value);
        done_before = int'(value);
        done_edges = 0;
        last_raw_b = 0;
        last_candidate_b = 0;
        first_gather = 0;
        last_table = 0;
        table_wait_cycles = 0;
        candidate_bytes = 0;
        raw_bytes = 0;
        gather_bytes = 0;
        for (int h = 0; h < 3; h++) table_bytes[h] = 0;
        running = 1;
        wr('h028, 0);
        equals('h12c, 0);
        equals('h130, 0);
    endtask

    initial begin : run
        bit [31:0] value;
        int fence_phase;
        check($value$plusargs("CASE_DIR=%s", case_dir), "CASE_DIR missing");
        void'($value$plusargs("TEST_ID=%s", test_id));
        void'($value$plusargs("FRAME2_DIR=%s", frame2_dir));
        void'($value$plusargs("FAULT_PHASE=%d", fault_phase));
        void'($value$plusargs("ABORT_PHASE=%d", abort_phase));
        fence_phase = 0;
        void'($value$plusargs("FENCE_PHASE=%d", fence_phase));
        apb.psel = 0;
        apb.penable = 0;
        repeat (8) @(negedge clk_mem);
        rst_mem_n = 1;
        repeat (8) @(negedge clk_npu);
        rst_npu_n = 1;
        repeat (20) @(negedge clk_mem);
        for (int n = 0; n < 8; n++) equals(12'('h114+n*4), 0, "post reset");
        load_case(case_dir);
        if (test_id == "PP-01") begin
            wr('h004, 8);
            for (int n = 0; n < 8; n++) equals(12'('h114+n*4), 0, "post SOFT_RST");
            load_case(case_dir);
        end
        if (fault_phase != 0) begin
            u_mem.read_error_enable = fault_phase != 3;
            u_mem.write_error_enable = fault_phase == 3;
            u_mem.read_error_first = fault_phase == 1 ? model_base+'h10000 : output_base;
            u_mem.read_error_last = u_mem.read_error_first+31;
            u_mem.write_error_first = post_base;
            u_mem.write_error_last = post_base+31;
        end
        start();
        if (abort_phase != 0) begin
            gate(abort_phase, 1);
            running = 0;
            start();
        end
        if (fault_phase != 0) begin
            do rd('h010, value); while (!value[1]);
            check(value == 2, "error IRQ must not include DONE");
            equals('h014, fault_phase == 3 ? 2 : 1);
            idle();
            equals('h130, 0);
            equals('h02c, 32'(done_before));
            if (fault_phase != 1) equals('h110, 32'(desc_count-1));
            u_mem.read_error_enable = 0;
            u_mem.write_error_enable = 0;
            wr('h010, 2);
            start();
        end
        if (fence_phase != 0) gate(fence_phase, 0);
        finish_frame();
        if (frame2_dir != "") begin
            foreach (reference[address]) begin
                if (address >= post_base && address < post_base+120960)
                    first_frame[address] = reference[address];
            end
            running = 0;
            load_case(frame2_dir);
            start();
            finish_frame();
            foreach (first_frame[address])
                check(u_mem.peek(address) == first_frame[address], "frame one overwritten");
        end
        check(checker_errors == 0, "AXI checker errors");
        $display("PASS POST %s", test_id);
        $finish;
    end
    initial begin
        #2000000000;
        $fatal(1, "FAIL POST timeout test=%s", test_id);
    end
endmodule
