// File: edrv32_gpu_tb.sv
// Spec: gpu-spec 3–6; gpu-testplan 2, 4; SoC 7.1–7.2.
// Description: Command-list startup via APB, external DDR export, no internal DUT probes.
// Clock domain: clk_gpu at 150 MHz.
`timescale 1ns/1ps
module edrv32_gpu_tb;
    logic clk_r = 0;
    logic rst_n_r = 0;
    wire irq_w;
    int checker_errors;
    bit [31:0] expected_irq;
    int cycle_r = 0;
    int doorbell_cycle = -1;
    int fetch_cycle = -1;
    int abort_cycle;
    int abort_command;
    int abort_after;
    int abort_kind;
    bit [31:0] abort_first;
    bit [31:0] abort_last;
    bit [31:0] descriptor_base;
    bit [31:0] descriptor_count;
    bit [31:0] abort_address;
    always @(posedge clk_r) begin
        cycle_r <= cycle_r+1;
        if (apb.psel[0] && apb.penable && apb.pready[0] && apb.pwrite &&
            apb.paddr == 12'h028) begin
            doorbell_cycle = cycle_r;
            fetch_cycle = -1;
        end
        if (abort_command != 0 && fetch_cycle < 0 && axi.arvalid && axi.arready &&
            axi.araddr <= abort_address &&
            abort_address < axi.araddr+32'(32*(int'(axi.arlen)+1))) fetch_cycle = cycle_r;
        if (fetch_cycle < 0 && abort_kind == 1 && axi.arvalid && axi.arready &&
            axi.araddr <= abort_last &&
            abort_first < axi.araddr+32'(32*(int'(axi.arlen)+1))) fetch_cycle = cycle_r;
        if (fetch_cycle < 0 && abort_kind == 2 && axi.awvalid && axi.awready &&
            axi.awaddr <= abort_last &&
            abort_first < axi.awaddr+32'(32*(int'(axi.awlen)+1))) fetch_cycle = cycle_r;
    end
    edrv32_axi256_if axi();
    edrv32_apb_if apb();
    assign apb.pready[15:1] = 0;
    assign apb.pslverr[15:1] = 0;
    assign apb.prdata[511:32] = 0;
    always #3.333 clk_r = ~clk_r;

    edrv32_gpu_memory u_memory (
        .clk_i(clk_r),
        .rst_n_i(rst_n_r),
        .bus(axi)
    );
    edrv32_axi256_checker u_axi_checker (
        .clk_i(clk_r),
        .rst_n_i(rst_n_r),
        .bus(axi),
        .errors_o(checker_errors)
    );
    edrv32_gpu_apb_host u_apb_host (
        .clk_i(clk_r),
        .bus(apb)
    );
    edrv32_apb_checker u_apb_checker (
        .clk_i(clk_r),
        .rst_n_i(rst_n_r),
        .bus(apb)
    );

    edrv32_gpu u_dut (
        // Clock and reset.
        .clk_gpu_i(clk_r),
        .rst_gpu_n_i(rst_n_r),

        // APB control interface.
        .s_apb_paddr_i(apb.paddr),
        .s_apb_psel_i(apb.psel[0]),
        .s_apb_penable_i(apb.penable),
        .s_apb_pwrite_i(apb.pwrite),
        .s_apb_pwdata_i(apb.pwdata),
        .s_apb_pstrb_i(apb.pstrb),
        .s_apb_pready_o(apb.pready[0]),
        .s_apb_prdata_o(apb.prdata[31:0]),
        .s_apb_pslverr_o(apb.pslverr[0]),

        // AXI256 DDR interface.
        .m_axi_awid_o(axi.awid),
        .m_axi_awaddr_o(axi.awaddr),
        .m_axi_awlen_o(axi.awlen),
        .m_axi_awvalid_o(axi.awvalid),
        .m_axi_awready_i(axi.awready),
        .m_axi_wdata_o(axi.wdata),
        .m_axi_wstrb_o(axi.wstrb),
        .m_axi_wlast_o(axi.wlast),
        .m_axi_wvalid_o(axi.wvalid),
        .m_axi_wready_i(axi.wready),
        .m_axi_bid_i(axi.bid),
        .m_axi_bresp_i(axi.bresp),
        .m_axi_bvalid_i(axi.bvalid),
        .m_axi_bready_o(axi.bready),
        .m_axi_arid_o(axi.arid),
        .m_axi_araddr_o(axi.araddr),
        .m_axi_arlen_o(axi.arlen),
        .m_axi_arvalid_o(axi.arvalid),
        .m_axi_arready_i(axi.arready),
        .m_axi_rid_i(axi.rid),
        .m_axi_rdata_i(axi.rdata),
        .m_axi_rresp_i(axi.rresp),
        .m_axi_rlast_i(axi.rlast),
        .m_axi_rvalid_i(axi.rvalid),
        .m_axi_rready_o(axi.rready),

        // Completion and error interrupt.
        .irq_o(irq_w)
    );

    // DONE is published only after issued transactions have drained (SoC 7.2).
    always @(negedge clk_r) begin
        if (rst_n_r && irq_w && expected_irq[0] &&
            (u_memory.reading || u_memory.writing))
            $fatal(1, "FAIL completion with pending DDR transaction time=%0t", $time);
    end

    initial begin : run
        string directory;
        int control;
        int completion;
        int output_fd;
        int events;
        int timing;
        int reset_fd;
        int reset_output;
        int reset_count;
        bit [31:0] reset_expected;
        bit [31:0] base;
        int words;
        int writes;
        int samples;
        bit [11:0] address;
        bit [31:0] value;
        bit [31:0] observed_irq;
        if (!$value$plusargs("CASE_DIR=%s", directory))
            $fatal(1, "FAIL CASE_DIR is required");
        control = $fopen({directory, "/control.txt"}, "r");
        if (control == 0) $fatal(1, "FAIL cannot open control.txt");
        if ($fscanf(control, "%h %d %d %d", base, words, writes, samples) != 4)
            $fatal(1, "FAIL control header");
        completion = $fopen({directory, "/completion.txt"}, "r");
        if (completion == 0) $fatal(1, "FAIL cannot open completion.txt");
        if ($fscanf(completion, "%h", expected_irq) != 1)
            $fatal(1, "FAIL completion record");
        $fclose(completion);
        events = $fopen({directory, "/events.txt"}, "r");
        if (events == 0) $fatal(1, "FAIL cannot open events.txt");
        if ($fscanf(events, "%d %d %d %d %h %h", abort_cycle, abort_command,
                    abort_after, abort_kind, abort_first, abort_last) != 6)
            $fatal(1, "FAIL events record");
        $fclose(events);
        timing = $fopen({directory, "/timing.txt"}, "w");
        if (timing == 0) $fatal(1, "FAIL cannot create timing.txt");
        u_apb_host.idle();
        u_memory.load({directory, "/initial.hex"}, base, words);
        repeat (5) @(negedge clk_r);
        rst_n_r = 1;
        reset_fd = $fopen({directory, "/reset.txt"}, "r");
        reset_output = $fopen({directory, "/actual.reset.txt"}, "w");
        if (reset_fd == 0 || reset_output == 0) $fatal(1, "FAIL reset file open");
        if ($fscanf(reset_fd, "%d", reset_count) != 1) $fatal(1, "FAIL reset header");
        for (int n = 0; n < reset_count; n++) begin
            if ($fscanf(reset_fd, "%h %h", address, reset_expected) != 2)
                $fatal(1, "FAIL reset sample=%0d", n);
            u_apb_host.read_reg(address, value);
            if (value != reset_expected)
                $fatal(1, "FAIL reset address=%h expected=%h actual=%h time=%0t",
                        address, reset_expected, value, $time);
            $fdisplay(reset_output, "%03x %08x", address, value);
        end
        $fclose(reset_fd);
        $fclose(reset_output);
        for (int n = 0; n < writes; n++) begin
            if ($fscanf(control, "%h %h", address, value) != 2)
                $fatal(1, "FAIL APB write record=%0d", n);
            if (address == 12'h020) begin
                descriptor_base = value;
                abort_address = value+32'(32*(abort_command-1));
            end
            if (address == 12'h024) descriptor_count = value;
            u_apb_host.write_reg(address, value);
            if (address == 12'h028) begin
                if (abort_cycle >= 0 || abort_command != 0 || abort_kind != 0) begin
                    if (abort_command != 0 || abort_kind != 0) begin
                        wait (fetch_cycle >= 0);
                        wait (cycle_r >= fetch_cycle+abort_after);
                    end else wait (cycle_r >= doorbell_cycle+abort_cycle);
                    u_apb_host.write_reg(12'h004, 5);
                    u_apb_host.read_reg(12'h008, value);
                    while (value[0]) u_apb_host.read_reg(12'h008, value);
                    u_apb_host.read_reg(12'h010, observed_irq);
                end else begin
                    observed_irq = 0;
                    while (!(|observed_irq[1:0]))
                        u_apb_host.read_reg(12'h010, observed_irq);
                end
                wait (!u_memory.reading && !u_memory.writing);
                $fdisplay(timing, "%08x %0d %0d %0d %08x", descriptor_base,
                            descriptor_count, doorbell_cycle, cycle_r, observed_irq);
            end
        end
        $fclose(timing);
        if (observed_irq != expected_irq)
            $fatal(1, "FAIL IRQ_STAT expected=%h actual=%h time=%0t",
                    expected_irq, observed_irq, $time);
        if (irq_w != (|expected_irq[1:0]))
            $fatal(1, "FAIL irq_o expected=%b actual=%b time=%0t",
                    |expected_irq[1:0], irq_w, $time);
        wait (!u_memory.reading && !u_memory.writing);
        // Statistics lag events by one clock (SoC 7.1).
        repeat (2) @(negedge clk_r);
        output_fd = $fopen({directory, "/actual.regs.txt"}, "w");
        if (output_fd == 0) $fatal(1, "FAIL cannot create actual.regs.txt");
        for (int n = 0; n < samples; n++) begin
            if ($fscanf(control, "%h", address) != 1)
                $fatal(1, "FAIL register sample record=%0d", n);
            u_apb_host.read_reg(address, value);
            $fdisplay(output_fd, "%03x %08x", address, value);
        end
        $fclose(output_fd);
        $fclose(control);
        u_memory.dump({directory, "/actual.ddr.hex"}, base, words);
        if (checker_errors != 0) $fatal(1, "FAIL AXI errors=%0d", checker_errors);
        $display("PASS GPU external export time=%0t", $time);
        $finish;
    end

    initial begin
        repeat (2000000) @(posedge clk_r);
        $fatal(1, "FAIL GPU test timeout time=%0t", $time);
    end
endmodule
