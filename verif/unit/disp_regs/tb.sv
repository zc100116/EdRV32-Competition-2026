// File: tb.sv
// Spec: disp-spec 4-6; SoC 7.1.
// Description: Register reset, alignment, handoff, IRQ priority and deferred local reset.
// Clock domain: test memory clock.
module tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg [11:0] paddr = 0;
    reg psel = 0;
    reg penable = 0;
    reg pwrite = 0;
    reg [31:0] pwdata = 0;
    reg [3:0] pstrb = 0;
    wire pready;
    wire [31:0] prdata;
    wire pslverr;
    wire enable;
    wire [31:0] next_base;
    wire [31:0] stride;
    wire soft_clear;
    reg busy = 0;
    reg frame_start = 0;
    reg underflow = 0;
    reg dma_err = 0;
    reg urgent = 0;
    reg delayed_req = 0;
    reg [31:0] perf0 = 0;
    reg [31:0] perf1 = 0;
    reg [31:0] perf2 = 0;
    wire [31:0] scan_cnt;
    wire irq;
    edrv32_disp_regs dut (
        .clk_i(clk), .rst_n_i(rst_n), .apb_paddr_i(paddr), .apb_psel_i(psel),
        .apb_penable_i(penable), .apb_pwrite_i(pwrite), .apb_pwdata_i(pwdata),
        .apb_pstrb_i(pstrb), .apb_pready_o(pready), .apb_prdata_o(prdata),
        .apb_pslverr_o(pslverr), .enable_o(enable), .next_base_o(next_base),
        .stride_o(stride), .soft_clear_o(soft_clear), .busy_i(busy),
        .frame_start_i(frame_start), .underflow_i(underflow), .dma_err_i(dma_err),
        .urgent_i(urgent), .delayed_req_i(delayed_req), .perf0_i(perf0),
        .perf1_i(perf1), .perf2_i(perf2), .scan_cnt_o(scan_cnt), .irq_o(irq)
    );
    task automatic tick;
        @(posedge clk);
        #1;
        @(negedge clk);
    endtask
    task automatic write_reg(input [11:0] addr, input [31:0] value);
        paddr = addr;
        pwdata = value;
        pwrite = 1;
        psel = 1;
        penable = 0;
        tick();
        penable = 1;
        tick();
        psel = 0;
        penable = 0;
        pwrite = 0;
    endtask
    task automatic check_reg(input [11:0] addr, input [31:0] expected);
        paddr = addr;
        #1;
        if (!pready || pslverr || prdata !== expected)
            $fatal(1, "FAIL reg %h = %h expected=%h", addr, prdata, expected);
    endtask
    task automatic start_frame;
        frame_start = 1;
        tick();
        frame_start = 0;
    endtask
    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1;
        check_reg('h000, 'h0005_0001);
        check_reg('h004, 0);
        check_reg('h008, 2);
        check_reg('h104, 'ha00);
        for (int offset = 'h40; offset <= 'h7c; offset += 4) check_reg(12'(offset), 0);
        check_reg('h108, 0);
        check_reg('h10c, 0);
        check_reg('h110, 0);
        write_reg('h00c, '1);
        check_reg('h00c, 'h106);
        write_reg('h100, 'h1234_5fff);
        write_reg('h104, 'h9876_123f);
        check_reg('h100, 'h1234_5000);
        check_reg('h104, 'h1220);
        if (next_base != 'h12345000 || stride != 'h1220) $fatal(1, "FAIL cfg outputs");
        write_reg('h004, 3);
        check_reg('h004, 1);
        start_frame();
        check_reg('h108, 'h1234_5000);
        check_reg('h10c, 0);
        check_reg('h110, 1);
        check_reg('h02c, 1);
        check_reg('h010, 'h104);
        if (!irq) $fatal(1, "FAIL frame IRQ");
        write_reg('h010, '1);
        start_frame();
        check_reg('h010, 4);
        write_reg('h010, '1);
        write_reg('h100, 'h2000_0123);
        check_reg('h108, 'h1234_5000);
        start_frame();
        check_reg('h108, 'h2000_0000);
        check_reg('h10c, 'h1234_5000);
        check_reg('h110, 3);
        underflow = 1;
        tick();
        underflow = 0;
        check_reg('h014, 1);
        check_reg('h008, 6);
        dma_err = 1;
        tick();
        dma_err = 0;
        check_reg('h014, 2);
        write_reg('h010, 2);
        check_reg('h014, 0);
        check_reg('h008, 2);
        // A new error wins over simultaneous RW1C.
        paddr = 'h010;
        psel = 1;
        penable = 1;
        pwrite = 1;
        pwdata = 2;
        underflow = 1;
        tick();
        psel = 0;
        penable = 0;
        pwrite = 0;
        underflow = 0;
        check_reg('h014, 1);
        check_reg('h010, 'h106);
        perf0 = 7;
        perf1 = 2;
        perf2 = 93;
        urgent = 1;
        delayed_req = 1;
        tick();
        delayed_req = 0;
        repeat (8) tick();
        urgent = 0;
        check_reg('h040, 7);
        check_reg('h044, 2);
        check_reg('h048, 93);
        check_reg('h04c, 9);
        check_reg('h050, 1);
        write_reg('h004, 5);
        check_reg('h004, 0);
        write_reg('h020, '1);
        write_reg('h024, '1);
        write_reg('h028, '1);
        write_reg('h180, '1);
        check_reg('h020, 0);
        check_reg('h024, 0);
        check_reg('h028, 0);
        check_reg('h180, 0);
        busy = 1;
        write_reg('h004, 9);
        if (soft_clear || enable) $fatal(1, "FAIL reset did not wait for drain");
        repeat (3) tick();
        check_reg('h110, 3);
        perf0 = 10;
        perf1 = 3;
        perf2 = 99;
        busy = 0;
        #1;
        if (!soft_clear) $fatal(1, "FAIL missing deferred reset completion");
        tick();
        check_reg('h004, 0);
        check_reg('h00c, 0);
        check_reg('h010, 0);
        check_reg('h014, 0);
        check_reg('h100, 0);
        check_reg('h104, 'ha00);
        check_reg('h108, 0);
        check_reg('h10c, 0);
        check_reg('h110, 0);
        for (int offset = 'h40; offset <= 'h7c; offset += 4) check_reg(12'(offset), 0);
        if (scan_cnt != 0 || irq) $fatal(1, "FAIL reset bases/IRQ");
        perf0++;
        perf1++;
        perf2 += 5;
        check_reg('h040, 1);
        check_reg('h044, 1);
        check_reg('h048, 5);
        $display("PASS regs: frame handoff, alignment, IRQ/RW1C, counters, deferred SOFT_RST");
        $finish;
    end
endmodule
