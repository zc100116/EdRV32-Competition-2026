// File: tb.sv; sys-subsys-testplan gpio unit coverage.
module tb;
    reg clk = 0;
    always #5 clk = !clk;
    reg rst_n = 0;
    reg [11:0] addr = 0;
    reg psel = 0;
    reg penable = 0;
    reg pwrite = 0;
    reg [31:0] wdata = 0;
    reg [3:0] strb = 15;
    wire [31:0] rdata;
    wire ready;
    wire error;
    wire irq;
    reg [31:0] value;
    integer cases = 0;

    task automatic ticks(input integer n);
        repeat (n) @(negedge clk);
    endtask

    task automatic write_reg(input [11:0] a, input [31:0] d, input [3:0] s = 15);
        @(negedge clk);
        addr = a; wdata = d; strb = s; psel = 1; pwrite = 1; penable = 0;
        @(negedge clk);
        penable = 1;
        @(negedge clk);
        if (ready !== 1 || error !== 0) $fatal(1, "FAIL APB write at %h", a);
        psel = 0; penable = 0; pwrite = 0;
    endtask

    task automatic read_reg(input [11:0] a, output [31:0] d);
        @(negedge clk);
        addr = a; psel = 1; pwrite = 0; penable = 0;
        @(negedge clk);
        penable = 1;
        #1;
        d = rdata;
        if (ready !== 1 || error !== 0) $fatal(1, "FAIL APB read at %h", a);
        @(negedge clk);
        psel = 0; penable = 0;
    endtask

    task automatic check_reg(input [11:0] a, input [31:0] expected,
                             input [31:0] mask = 32'hffffffff);
        reg [31:0] actual;
        read_reg(a, actual);
        if ((actual & mask) !== (expected & mask))
            $fatal(1, "FAIL t=%0t addr=%h expected=%h actual=%h mask=%h",
                   $time, a, expected, actual, mask);
    endtask

    task automatic reset_dut;
        @(negedge clk);
        rst_n = 0;
        psel = 0; penable = 0; pwrite = 0;
        ticks(5);
        rst_n = 1;
        ticks(6);
    endtask

    initial begin
        #50000000;
        $fatal(1, "FAIL timeout");
    end
    reg [15:0] pins = 0;
    wire [15:0] gpio_out;
    wire [15:0] gpio_oe;
    reg [15:0] expected;
    integer s;
    edrv32_periph_gpio dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .apb_paddr_i(addr),
        .apb_psel_i(psel),
        .apb_penable_i(penable),
        .apb_pwrite_i(pwrite),
        .apb_pwdata_i(wdata),
        .apb_pstrb_i(strb),
        .apb_prdata_o(rdata),
        .apb_pready_o(ready),
        .apb_pslverr_o(error),
        .irq_o(irq),
        .gpio_i(pins),
        .gpio_o(gpio_out),
        .gpio_oe_o(gpio_oe)
    );

    initial begin
        reset_dut();
        check_reg('h000, 'h00010001);
        check_reg('h004, 0);
        check_reg('h008, 0);
        check_reg('h018, 0);
        check_reg('h01c, 0);
        if (gpio_out !== 0 || gpio_oe !== 0 || irq !== 0) $fatal(1, "FAIL reset");
        // GP-01: all byte strobe masks, including irrelevant upper bytes.
        for (s = 0; s < 16; s = s + 1) begin
            write_reg('h004, 'h1234);
            write_reg('h004, 'hfedc, s[3:0]);
            expected = {s[1] ? 8'hfe : 8'h12, s[0] ? 8'hdc : 8'h34};
            check_reg('h004, {16'b0, expected});
            if (gpio_out !== expected) $fatal(1, "FAIL OUT pins");
            write_reg('h008, 'h5678);
            write_reg('h008, 'hba98, s[3:0]);
            expected = {s[1] ? 8'hba : 8'h56, s[0] ? 8'h98 : 8'h78};
            check_reg('h008, {16'b0, expected});
            if (gpio_oe !== expected) $fatal(1, "FAIL OE pins");
        end
        pins = 'ha55a;
        ticks(3);
        check_reg('h00c, 'ha55a);
        write_reg('hffc, 'hffffffff);
        check_reg('hffc, 0);
        cases = cases + 1;
        $display("PASS GP-01 byte strobes and synchronized inputs");

        // GP-02: bypass has exactly the two synchronizer stages.
        addr = 'h00c;
        pins = 0;
        ticks(1);
        if (rdata[15:0] !== 16'ha55a) $fatal(1, "FAIL bypass too early");
        ticks(1);
        if (rdata !== 0) $fatal(1, "FAIL bypass delay");
        write_reg('h01c, 8);
        pins = 1;
        ticks(3);
        pins = 0;
        ticks(12);
        check_reg('h00c, 0);
        addr = 'h00c;
        pins = 'hffff;
        ticks(9);
        if (rdata !== 0) $fatal(1, "FAIL debounce accepted before 8 samples");
        ticks(1);
        if (rdata !== 'hffff) $fatal(1, "FAIL debounce sample boundary: %h", rdata);
        write_reg('h01c, 0);
        cases = cases + 1;
        $display("PASS GP-02 debounce and exact bypass latency");

        // GP-03: each polarity and pin, masking, W1C and sticky state.
        pins = 0;
        ticks(4);
        write_reg('h010, 'h00ff, 0);
        write_reg('h014, 'hff00, 0);
        pins = 'hffff;
        ticks(4);
        check_reg('h018, 'h00ff);
        if (irq !== 1) $fatal(1, "FAIL rising IRQ");
        write_reg('h018, 'h000f, 0);
        check_reg('h018, 'h00f0);
        pins = 0;
        ticks(4);
        check_reg('h018, 'hfff0);
        write_reg('h018, 'hfff0);
        check_reg('h018, 0);
        if (irq !== 0) $fatal(1, "FAIL IRQ clear");
        write_reg('h010, 'hff00);
        write_reg('h014, 'h00ff);
        pins = 'hffff;
        ticks(4);
        check_reg('h018, 'hff00);
        write_reg('h018, 'hffff);
        pins = 0;
        ticks(4);
        check_reg('h018, 'h00ff);
        write_reg('h018, 'hffff);
        write_reg('h010, 0);
        write_reg('h014, 0);
        pins = 'hffff;
        ticks(4);
        check_reg('h018, 0);
        // A rising event coincident with W1C has priority over the clear.
        pins = 0;
        ticks(4);
        write_reg('h010, 1);
        pins = 1;
        write_reg('h018, 1);
        check_reg('h018, 1);
        write_reg('h018, 1);
        check_reg('h018, 0);
        // Asynchronous reset clears state without resetting the input pins.
        @(negedge clk);
        rst_n = 0;
        #1;
        addr = 'h008;
        #1;
        if (gpio_out !== 0 || gpio_oe !== 0 || irq !== 0 || rdata !== 0)
            $fatal(1, "FAIL asynchronous reset");
        cases = cases + 1;
        $display("PASS GP-03 edge interrupts and W1C");
        $display("PASS periph_gpio %0d cases", cases);
        $finish;
    end
endmodule
