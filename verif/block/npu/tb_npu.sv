// File: tb_npu.sv
// Spec: npu-testplan 2 and 3.2-3.7; npu-spec 3, 4, 6; SoC 4.2/4.3/7.1.
// Description: Black-box APB programming, protocol monitors and byte comparison.
//              SELFTEST exercises the harness using only testbench register storage.
// Clock domains: clk_mem and clk_npu; independent reset release.
`timescale 1ns/1ps
module tb_npu #(
    parameter bit SELFTEST = 0
);
    bit clk_mem = 0;
    bit clk_npu = 0;
    bit rst_mem_n = 0;
    bit rst_npu_n = 0;
    real npu_mhz = 150.0;
    real mem_mhz = 125.0;
    wire irq;
    int checker_errors;
    int busy_cycles;
    int frame_busy_cycles;
    int npu_cycles;
    bit tracking;
    bit [31:0] reg_values[6];
    byte unsigned reference[bit [31:0]];
    string case_dir;
    string test_id;
    string frame2_dir;
    string recovery_dir;
    int expect_error;
    int expect_desc;
    int abort_phase;
    int desc_count;
    longint unsigned frame_read_start;
    longint unsigned frame_write_start;
    int done_before;
    bit abort_sent;
    int abort_ar;
    int abort_aw;
    int observed_ar;
    int observed_aw;
    int observed_b;
    int illegal_data_reads;
    bit [31:0] forbidden_out;
    int forbidden_bytes;
    bit forbid_output;
    bit [31:0] first_output;
    bit [31:0] first_output_bytes;
    bit [31:0] second_input;
    bit [31:0] second_input_bytes;
    bit [31:0] second_weight;
    bit [31:0] second_weight_bytes;
    int first_completed_bytes;
    typedef struct packed {
        bit [31:0] addr;
        int bytes;
    } write_request_t;
    write_request_t observed_writes[$];
    edrv32_axi256_if axi();
    edrv32_apb_if apb();

    npu_axi256_mem u_mem (
        .clk_i(clk_mem),
        .rst_n_i(rst_mem_n),
        .bus(axi)
    );
    edrv32_axi256_checker u_axi_checker (
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

    generate
        if (SELFTEST) begin : g_selftest
            bit self_done;
            bit [31:0] self_regs[128];
            assign axi.awid = 0;
            assign axi.awaddr = 0;
            assign axi.awlen = 0;
            assign axi.awvalid = 0;
            assign axi.wdata = 0;
            assign axi.wstrb = 0;
            assign axi.wlast = 0;
            assign axi.wvalid = 0;
            assign axi.bready = 1;
            assign axi.arid = 0;
            assign axi.araddr = 0;
            assign axi.arlen = 0;
            assign axi.arvalid = 0;
            assign axi.rready = 1;
            assign apb.pready = 16'b1;
            assign apb.pslverr = 0;
            assign apb.prdata = {480'b0, self_regs[apb.paddr[8:2]]};
            assign irq = |(self_regs[4] & self_regs[3]);
            always @(posedge clk_mem) begin
                if (!rst_mem_n) begin
                    for (int n = 0; n < 128; n++) self_regs[n] = 0;
                    self_regs[0] = 'h00060001;
                    self_regs[2] = 2;
                    self_done = 0;
                end else begin
                    if (self_done) begin
                        self_regs[2] = 2;
                        self_regs[4] = 1;
                        self_regs[11]++;
                        self_done = 0;
                    end
                    if (apb.psel[0] && apb.penable && apb.pwrite) begin
                        if (apb.paddr == 'h028) begin
                            self_regs[2] = 1;
                            self_done = 1;
                        end else if (apb.paddr == 'h010)
                            self_regs[4] &= ~apb.pwdata;
                        else self_regs[apb.paddr[8:2]] = apb.pwdata;
                    end
                end
            end
        end else begin : g_dut
            longint layer_cycles;
            longint layer_values;
            longint quant_groups;
            longint quant_busy;
            longint burst_cycles;
            longint finish8;
            longint finish4;
            longint baseline_finish;
            longint groups;
            longint delay8;
            longint delay4;
            longint first_result;
            longint last_result;
            longint result_values;
            always @(posedge clk_npu) begin
                if (u_dut.conv_start_w || u_dut.nonconv_start_w) begin
                    layer_cycles = 0;
                    layer_values = 0;
                    quant_groups = 0;
                    quant_busy = 0;
                    first_result = 0;
                    last_result = 0;
                    finish8 = 0;
                    finish4 = 0;
                    baseline_finish = 0;
                end
                if (u_dut.busy_w) begin
                    layer_cycles++;
                    if (u_dut.u_conv.u_datapath.quant_prepare_valid_w) begin
                        groups = u_dut.u_conv.u_datapath.quant_prepare_tag_w[26] ? 2 : 4;
                        quant_groups += groups;
                        // Two APMs implement one quant lane: 32 -> 8/4 APM is 4x/8x service.
                        baseline_finish = layer_cycles+groups;
                        finish8 = ((finish8 > layer_cycles) ? finish8 : layer_cycles)+groups*4;
                        finish4 = ((finish4 > layer_cycles) ? finish4 : layer_cycles)+groups*8;
                    end
                    if (u_dut.u_conv.u_datapath.u_result_quant.q_valid_r[0]) quant_busy++;
                    if (u_dut.is_conv_r && u_dut.u_conv.u_datapath.quant_valid_w) begin
                        result_values = u_dut.u_conv.u_datapath.quant_tag_w[26] ? 32 : 64;
                        layer_values += result_values;
                        if (first_result == 0) first_result = layer_cycles;
                        last_result = layer_cycles;
                    end else if (!u_dut.is_conv_r && u_dut.nonconv_write_data_valid_w
                        && u_dut.nonconv_write_data_ready_w) layer_values += 32;
                    if (u_dut.local_done_w) begin
                        burst_cycles = last_result-first_result+1;
                        $display("LAYER desc=%0d conv=%0d cycles=%0d values=%0d groups=%0d "
                            , u_dut.cur_desc_r, u_dut.is_conv_r, layer_cycles,
                            layer_values, quant_groups);
                        delay8 = (finish8 > baseline_finish) ? finish8-baseline_finish : 0;
                        delay4 = (finish4 > baseline_finish) ? finish4-baseline_finish : 0;
                        $display("QUANT busy=%0d span=%0d delay8=%0d delay4=%0d",
                            quant_busy, burst_cycles, delay8, delay4);
                    end
                end
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
        end
    endgenerate

    initial begin
        void'($value$plusargs("NPU_MHZ=%f", npu_mhz));
        forever #(500.0/npu_mhz) clk_npu = ~clk_npu;
    end
    initial begin
        void'($value$plusargs("MEM_MHZ=%f", mem_mhz));
        forever #(500.0/mem_mhz) clk_mem = ~clk_mem;
    end

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
            busy_cycles = 0;
            tracking = 1;
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
            default: $fatal(1, "FAIL unknown register %s time=%0t", name, $time);
        endcase
    endfunction

    function automatic bit [31:0] word_at(input bit [31:0] addr);
        bit [31:0] value;
        for (int n = 0; n < 4; n++) value[n*8 +: 8] = u_mem.peek(addr+32'(n));
        return value;
    endfunction

    task automatic load_case(input string path, input bit frame_only = 0);
        int fd;
        int count;
        string name;
        bit [31:0] value;
        bit [11:0] addr;
        string regions[6] = '{"model", "desc", "input", "work", "output", "state"};
        for (int n = 0; n < 6; n++) begin
            if (frame_only && n < 2) continue;
            fd = $fopen({path, "/mem_", regions[n], ".hex"}, "r");
            if (fd != 0) begin
                $fclose(fd);
                u_mem.load_hex({path, "/mem_", regions[n], ".hex"});
            end
        end
        fd = $fopen({path, "/regs.txt"}, "r");
        check(fd != 0, {"cannot open ", path, "/regs.txt"});
        count = 0;
        while ($fscanf(fd, "%s %h", name, value) == 2) begin
            addr = reg_addr(name);
            if (!frame_only || name == "INPUT_BASE" || name == "OUTPUT_BASE")
                wr(addr, value);
            equals(addr, value);
            case (name)
                "MODEL_BASE": reg_values[0] = value;
                "WORK_BASE": reg_values[1] = value;
                "INPUT_BASE": reg_values[2] = value;
                "OUTPUT_BASE": reg_values[3] = value;
                "DESC_BASE": reg_values[4] = value;
                "DESC_COUNT": begin reg_values[5] = value; desc_count = int'(value); end
                default: begin end
            endcase
            count++;
        end
        $fclose(fd);
        check(count == 6, $sformatf("regs expected=6 actual=%0d", count));
    endtask

    task automatic load_reference(input string path);
        int fd;
        int status;
        string word;
        bit [31:0] beat_addr;
        bit [255:0] data;
        reference.delete();
        fd = $fopen({path, "/ref_out.hex"}, "r");
        check(fd != 0, {"cannot open ", path, "/ref_out.hex"});
        beat_addr = 0;
        while ($fscanf(fd, "%s", word) == 1) begin
            if (word.substr(0, 0) == "@")
                status = $sscanf(word.substr(1, word.len()-1), "%h", beat_addr);
            else begin
                status = $sscanf(word, "%h", data);
                for (int b = 0; b < 32; b++) reference[beat_addr*32+32'(b)] = data[b*8 +: 8];
                beat_addr++;
            end
            check(status == 1, {"bad reference token ", word});
        end
        $fclose(fd);
    endtask

    function automatic int output_descriptor(input bit [31:0] addr, input int current);
        bit [31:0] desc;
        bit [31:0] first;
        bit [31:0] stride;
        bit [31:0] bytes;
        int planes;
        int result;
        result = current;
        for (int n = 0; n < desc_count; n++) begin
            desc = reg_values[4]+32'(n*64);
            planes = (word_at(desc) & 15) == 0 ?
                int'((word_at(desc+40) >> 8) & 15)*2-int'((word_at(desc) >> 9) & 1) :
                int'(word_at(desc+40) & 63);
            first = reg_values[int'((word_at(desc) >> 14) & 3)]+word_at(desc+12);
            stride = word_at(desc+16);
            bytes = (word_at(desc+36) & 4095)*((word_at(desc+36) >> 16) & 4095)*16;
            for (int plane = 0; plane < planes; plane++) begin
                if (addr >= first+32'(plane)*stride &&
                    addr < first+32'(plane)*stride+bytes) result = n;
            end
        end
        return result;
    endfunction

    task automatic compare_outputs(input string path);
        int fd;
        string name;
        bit [31:0] addr;
        bit [31:0] length;
        bit [31:0] cur_desc;
        int compared;
        rd('h110, cur_desc);
        compared = 0;
        fd = $fopen({path, "/check.txt"}, "r");
        check(fd != 0, {"cannot open ", path, "/check.txt"});
        while ($fscanf(fd, "%s %h %h", name, addr, length) == 3) begin
            for (bit [31:0] b = 0; b < length; b++) begin
                check(reference.exists(addr+b) != 0,
                    $sformatf("missing reference addr=%08h", addr+b));
                if (reference[addr+b] != u_mem.peek(addr+b))
                    $fatal(1,
                        "FAIL desc=%0d %s addr=%08h expected=%02h actual=%02h time=%0t",
                        output_descriptor(addr+b, int'(cur_desc)), name, addr+b,
                        reference[addr+b], u_mem.peek(addr+b), $time);
                compared++;
            end
        end
        $fclose(fd);
        check(compared > 0, "check.txt contains no output bytes");
        $display("CHECK bytes=%0d desc=%0d time=%0t", compared, cur_desc, $time);
    endtask

    task automatic reset_registers();
        bit [11:0] rw[7] = '{'h004, 'h00c, 'h020, 'h024, 'h100, 'h104, 'h108};
        bit [11:0] ro[5] = '{'h000, 'h008, 'h014, 'h02c, 'h110};
        bit [31:0] expected;
        equals('h000, 'h00060001);
        equals('h008, 2);
        equals('h010, 0);
        equals('h10c, 0);
        for (int n = 0; n < 7; n++) equals(rw[n], 0);
        for (int n = 0; n < 16; n++) begin
            equals(12'('h040+n*4), 0);
            wr(12'('h040+n*4), 'hffffffff);
            equals(12'('h040+n*4), 0);
        end
        for (int n = 2; n < 5; n++) equals(ro[n], 0);
        for (int n = 0; n < 7; n++) begin
            expected = rw[n] == 'h004 ? 1 : (rw[n] == 'h00c ? 3 : 'h12345000);
            wr(rw[n], expected);
            equals(rw[n], expected);
            wr(rw[n], 0);
        end
        wr('h10c, 'h05000000);
        equals('h10c, 'h05000000);
        for (int n = 0; n < 5; n++) begin
            rd(ro[n], expected);
            wr(ro[n], 'hffffffff);
            equals(ro[n], expected);
        end
        wr('h004, 2);
        equals('h004, 0);
    endtask

    task automatic soft_reset_registers();
        bit [11:0] rw[8] = '{'h004, 'h00c, 'h020, 'h024, 'h100, 'h104, 'h108, 'h10c};
        string names[8] = '{"CTRL", "IRQ_EN", "DESC_BASE", "DESC_COUNT",
            "MODEL_BASE", "WORK_BASE", "INPUT_BASE", "OUTPUT_BASE"};
        bit [31:0] expected;
        bit [31:0] actual;
        // npu-spec 4 / RG-01: reset a populated register block while IDLE.
        equals('h008, 2, "STATUS before SOFT_RST");
        equals('h010, 1, "IRQ_STAT before SOFT_RST");
        equals('h02c, 1, "DONE_COUNT before SOFT_RST");
        equals('h110, 32'(desc_count-1), "CUR_DESC before SOFT_RST");
        for (int n = 0; n < 8; n++) begin
            rd(12'('h040+n*4), actual);
            check(actual != 0,
                $sformatf("reg=PERF[%0d] before SOFT_RST expected=nonzero actual=%08h", n, actual));
        end
        for (int n = 0; n < 8; n++) begin
            expected = n == 0 ? 1 : (n == 1 ? 3 : 'h12345000+32'(n*'h1000));
            wr(rw[n], expected);
            equals(rw[n], expected, {names[n], " before SOFT_RST"});
        end
        // Keep ENABLE set in the triggering write so SOFT_RST must clear it.
        wr('h004, 9);
        equals('h000, 'h00060001, "ID after SOFT_RST");
        equals('h008, 2, "STATUS after SOFT_RST");
        equals('h010, 0, "IRQ_STAT after SOFT_RST");
        equals('h014, 0, "ERR_CODE after SOFT_RST");
        equals('h02c, 0, "DONE_COUNT after SOFT_RST");
        equals('h110, 0, "CUR_DESC after SOFT_RST");
        for (int n = 0; n < 8; n++) equals(rw[n], 0, {names[n], " after SOFT_RST"});
        for (int n = 0; n < 16; n++)
            equals(12'('h040+n*4), 0, $sformatf("PERF[%0d] after SOFT_RST", n));
    endtask

    task automatic wait_idle();
        bit [31:0] status;
        do rd('h008, status); while (status[0]);
        check(status[1], $sformatf("STATUS.IDLE expected=1 actual=%h", status));
        check(u_mem.read_outstanding == 0 && u_mem.write_outstanding == 0,
            "IDLE with pending AXI transactions");
        check(!axi.arvalid && !axi.awvalid && !axi.wvalid,
            "IDLE with an unfinished AXI request/data offer");
    endtask

    task automatic start_frame();
        bit [31:0] value;
        rd('h02c, value);
        done_before = int'(value);
        busy_cycles = 0;
        tracking = 0;
        frame_read_start = u_mem.read_beats;
        frame_write_start = u_mem.write_beats;
        wr('h00c, 3);
        wr('h028, 0);
    endtask

    task automatic finish_frame(input string path);
        bit [31:0] status;
        bit [31:0] desc;
        bit [31:0] perf;
        bit [31:0] perf_total;
        bit [31:0] descriptors_seen;
        bit saw_busy;
        int largest_desc;
        saw_busy = 0;
        descriptors_seen = 0;
        largest_desc = -1;
        do begin
            rd('h008, status);
            saw_busy |= status[0];
            rd('h110, desc);
            if (!SELFTEST) begin
                check(int'(desc) >= largest_desc && int'(desc) < desc_count,
                    $sformatf("CUR_DESC previous=%0d actual=%0d", largest_desc, desc));
                largest_desc = int'(desc);
                if (test_id == "RG-02") descriptors_seen[int'(desc)] = 1;
            end
            rd('h010, status);
        end while ((status & 3) == 0);
        check(status[1:0] == 1, $sformatf("DONE expected=1 ERROR=0 actual=%h", status));
        wait_idle();
        tracking = 0;
        frame_busy_cycles = busy_cycles;
        equals('h02c, 32'(done_before+1));
        check(irq, "IRQ_EN=3 DONE did not assert irq");
        wr('h00c, 0);
        repeat (3) @(negedge clk_npu);
        check(!irq, "IRQ_EN=0 did not mask irq");
        wr('h00c, 1);
        repeat (3) @(negedge clk_npu);
        check(irq, "IRQ_EN=1 did not unmask DONE");
        if (!SELFTEST && test_id == "RG-02") begin
            check(saw_busy, "STATUS.BUSY never observed");
            check(descriptors_seen == (32'b1 << desc_count)-1,
                $sformatf("CUR_DESC expected all descriptors actual bitmap=%h", descriptors_seen));
            equals('h110, 32'(desc_count-1));
        end
        if (test_id == "RG-03") begin
            rd('h040, perf);
            perf_total = perf;
            // testplan RG-03: doorbell is accepted before the APB response returns.
            check(int'(perf) <= frame_busy_cycles+16 &&
                int'(perf) >= frame_busy_cycles-16,
                $sformatf("PERF0 expected=[%0d,%0d] actual=%0d",
                        frame_busy_cycles-16, frame_busy_cycles+16, perf));
            for (int n = 1; n < 8; n++) begin
                rd(12'('h040+n*4), perf);
                check(perf != 0, $sformatf("PERF%0d expected nonzero actual=0", n));
                if (n == 1) check(perf <= perf_total, "PERF1 exceeds PERF0");
                if (n == 2) check(64'(perf) == u_mem.read_beats-frame_read_start,
                    "PERF2 read beat count/DOORBELL clear");
                if (n == 3) check(64'(perf) == u_mem.write_beats-frame_write_start,
                    "PERF3 write beat count/DOORBELL clear");
            end
        end
        for (int n = 0; n < 16; n++) begin
            rd(12'('h040+n*4), perf);
            $display("PERF%0d=%0d", n, perf);
        end
        load_reference(path);
        compare_outputs(path);
        if (test_id != "RG-01") begin
            wr('h010, 1);
            equals('h010, 0);
            repeat (3) @(negedge clk_npu);
            check(!irq, "RW1C DONE did not clear irq");
        end
        $display("METRICS npu_cycles=%0d doorbell_irq_cycles=%0d", npu_cycles, frame_busy_cycles);
        $display("MEM read_beats=%0d write_beats=%0d mem_cycles=%0d",
            u_mem.read_beats, u_mem.write_beats, u_mem.elapsed_cycles());
    endtask

    always @(posedge clk_npu) begin
        if (rst_npu_n) begin
            npu_cycles++;
            // Coordinator contract: APB completion to irq rising gives a 16-cycle window.
            if (tracking) begin
                busy_cycles++;
                if (irq) tracking = 0;
            end
        end
    end
    always @(posedge clk_mem) begin : observe_memory
        write_request_t request;
        if (rst_mem_n) begin
            if (test_id == "SQ-01" || test_id == "SQ-02") begin
                if (axi.awvalid && axi.awready) begin
                    request.addr = axi.awaddr;
                    request.bytes = (int'(axi.awlen)+1)*32;
                    observed_writes.push_back(request);
                end
                if (axi.bvalid && axi.bready) begin
                    request = observed_writes.pop_front();
                    if (request.addr >= first_output &&
                        request.addr < first_output+first_output_bytes)
                        first_completed_bytes += request.bytes;
                end
                if (axi.arvalid && axi.arready) begin
                    if (axi.araddr >= second_input &&
                        axi.araddr < second_input+second_input_bytes)
                        check(32'(first_completed_bytes) >= first_output_bytes,
                            $sformatf("input crossed B fence completed=%0d expected=%0d",
                                first_completed_bytes, first_output_bytes));
                    if (test_id == "SQ-02" && axi.araddr >= second_weight &&
                        axi.araddr < second_weight+second_weight_bytes)
                        $display("PREFETCH weight_addr=%08h first_B_bytes=%0d time=%0t",
                            axi.araddr, first_completed_bytes, $time);
                end
            end
            if (axi.arvalid && axi.arready) begin
                observed_ar++;
                if (test_id == "ER-03" && (axi.araddr < reg_values[4] ||
                    axi.araddr >= reg_values[4]+reg_values[5]*64)) illegal_data_reads++;
            end
            if (axi.awvalid && axi.awready) begin
                observed_aw++;
                if (forbid_output) check(axi.awaddr < forbidden_out ||
                    axi.awaddr >= forbidden_out+32'(forbidden_bytes),
                    "subsequent descriptor executed after error");
            end
            if (axi.bvalid && axi.bready) observed_b++;
        end
    end

    initial begin : run
        bit [31:0] value;
        bit [31:0] word;
        bit [31:0] base;
        apb.paddr = 0;
        apb.psel = 0;
        apb.penable = 0;
        apb.pwrite = 0;
        apb.pwdata = 0;
        apb.pstrb = 0;
        check($value$plusargs("CASE_DIR=%s", case_dir), "CASE_DIR required");
        void'($value$plusargs("TEST_ID=%s", test_id));
        void'($value$plusargs("FRAME2_DIR=%s", frame2_dir));
        void'($value$plusargs("RECOVERY_DIR=%s", recovery_dir));
        void'($value$plusargs("EXPECT_ERR=%d", expect_error));
        void'($value$plusargs("EXPECT_DESC=%d", expect_desc));
        void'($value$plusargs("ABORT_PHASE=%d", abort_phase));
        repeat (5) @(negedge clk_mem);
        rst_mem_n = 1;
        repeat (5) @(negedge clk_npu);
        rst_npu_n = 1;
        if (test_id == "RG-01") reset_registers();
        load_case(case_dir);
        if (SELFTEST) begin : selftest_images
            int fd;
            string region;
            bit [31:0] addr;
            bit [31:0] length;
            for (int n = 0; n < 5; n++) begin
                case (n)
                    0: base = reg_values[0];
                    1: base = reg_values[4];
                    2: base = reg_values[2];
                    3: base = reg_values[1];
                    default: base = reg_values[3];
                endcase
                for (int b = 0; b < 64; b++)
                    check(u_mem.peek(base+32'(b)) == byte'(b*7+n*31),
                        $sformatf("image %0d addr=%08h expected=%02h actual=%02h",
                            n, base+32'(b), byte'(b*7+n*31), u_mem.peek(base+32'(b))));
            end
            load_reference(case_dir);
            u_mem.load_hex({case_dir, "/ref_out.hex"});
            if ($test$plusargs("SELFTEST_CORRUPT")) begin
                fd = $fopen({case_dir, "/check.txt"}, "r");
                check(fd != 0, "cannot open selftest check.txt");
                check($fscanf(fd, "%s %h %h", region, addr, length) == 3,
                    "cannot read selftest check interval");
                $fclose(fd);
                $display("SELFTEST corrupt region=%s bytes=%0d addr=%08h", region, length, addr);
                u_mem.poke(addr, u_mem.peek(addr)^8'h01);
            end
        end
        if (test_id == "SQ-01" || test_id == "SQ-02") begin
            base = reg_values[4];
            word = word_at(base);
            first_output = reg_values[int'(word[15:14])]+word_at(base+12);
            word = word_at(base+36);
            first_output_bytes = 32'(word[11:0])*32'(word[27:16])*32;
            base += 64;
            word = word_at(base);
            second_input = reg_values[int'(word[13:12])]+word_at(base+4);
            word = word_at(base+32);
            second_input_bytes = 32'(word[11:0])*32'(word[27:16])*32;
            second_weight = reg_values[0]+word_at(base+24);
            word = word_at(base+40);
            second_weight_bytes = 32'(word[11:8])*word_at(base+48);
        end
        if (expect_error != 0 && desc_count >= 3) begin
            base = reg_values[4]+128;
            word = word_at(base);
            forbidden_out = reg_values[int'(word[15:14])]+word_at(base+12);
            word = word_at(base+36);
            forbidden_bytes = int'(word[11:0])*int'(word[27:16])*16;
            forbid_output = 1;
        end
        if (abort_phase == 1) begin
            wr('h004, 4);
            wait_idle();
            equals('h02c, 0);
            abort_ar = observed_ar;
            abort_aw = observed_aw;
            repeat (200) @(negedge clk_mem);
            check(observed_ar == abort_ar && observed_aw == abort_aw,
                "new AXI requests after idle ABORT");
            abort_sent = 1;
        end
        start_frame();
        if (!SELFTEST && abort_phase >= 2) begin
            if (abort_phase == 2) wait (u_mem.read_outstanding != 0 &&
                u_mem.reads[0].addr >= reg_values[0] && u_mem.reads[0].addr < reg_values[1]);
            else wait (u_mem.write_outstanding != 0 && u_mem.write_beats != 0);
            wr('h004, 4);
            abort_sent = 1;
            wait_idle();
            abort_ar = observed_ar;
            abort_aw = observed_aw;
            // Coordinator contract: allow bridge contents to drain, then observe 200 cycles.
            repeat (200) @(negedge clk_mem);
            check(observed_ar == abort_ar && observed_aw == abort_aw,
                "new AXI requests after ABORT");
            equals('h02c, 32'(done_before));
            wr('h010, 3);
            start_frame();
        end
        if (expect_error != 0) begin
            do rd('h010, value); while (!value[1]);
            check(value[1:0] == 2, $sformatf("ERROR expected=2 actual=%08h", value));
            equals('h014, 32'(expect_error));
            equals('h110, 32'(expect_desc));
            check(irq, "ERROR interrupt missing");
            wait_idle();
            rd('h008, value);
            check(value[2:0] == 6, $sformatf("error IDLE STATUS expected=6 actual=%h", value));
            equals('h110, 32'(expect_desc));
            equals('h02c, 32'(done_before));
            if (test_id == "ER-03")
                check(observed_aw == 0 && illegal_data_reads == 0,
                    "illegal OP issued data transactions");
            wr('h010, 2);
            equals('h014, 0);
            equals('h010, 0);
            rd('h008, value);
            check(value[2:0] == 2, $sformatf("clear ERROR STATUS expected=2 actual=%h", value));
            u_mem.read_error_enable = 0;
            u_mem.write_error_enable = 0;
            forbid_output = 0;
            if (recovery_dir != "") begin
                case_dir = recovery_dir;
                load_case(case_dir);
            end
            start_frame();
        end
        finish_frame(case_dir);
        if (test_id == "RG-01") soft_reset_registers();
        if (frame2_dir != "") begin
            // The model and descriptor image stay fixed across frames.
            base = reg_values[4];
            word = reg_values[0];
            load_case(frame2_dir, 1);
            check(base == reg_values[4] && word == reg_values[0], "frame model/desc changed");
            start_frame();
            finish_frame(frame2_dir);
            if (test_id == "RG-04") begin
                load_reference(case_dir);
                compare_outputs(case_dir);
            end
        end
        check(checker_errors == 0, "AXI checker error");
        $display("PASS NB test=%s selftest=%0d abort=%0d", test_id, SELFTEST, abort_sent);
        $finish;
    end
    initial begin
        #2000000000;
        $fatal(1, "FAIL NB timeout test=%s time=%0t", test_id, $time);
    end
endmodule
