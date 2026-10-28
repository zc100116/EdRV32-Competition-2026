// File: tb.sv; sys-subsys-testplan uart unit coverage.
module tb;
    `include "edrv32_soc_map.vh"
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
    reg loopback = 1;
    reg rx_pin = 1;
    wire tx_pin;
    wire rx_input = loopback ? tx_pin : rx_pin;
    integer rate;
    integer divisor;
    integer i;
    realtime bit_period;
    edrv32_periph_uart dut (
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
        .uart0_rx_i(rx_input),
        .uart0_tx_o(tx_pin)
    );

    task automatic capture_tx(input [7:0] expected, input realtime period);
        reg [7:0] actual;
        @(negedge tx_pin);
        #(period / 2.0);
        if (tx_pin !== 0) $fatal(1, "FAIL transmit START");
        for (integer b = 0; b < 8; b = b + 1) begin
            #(period);
            actual[b] = tx_pin;
        end
        #(period);
        if (tx_pin !== 1 || actual !== expected)
            $fatal(1, "FAIL TX expected=%h actual=%h STOP=%b", expected, actual, tx_pin);
    endtask

    task automatic send_rx(input [7:0] data, input realtime period, input bit bad_stop = 0);
        @(negedge clk);
        rx_pin = 0;
        #(period);
        for (integer b = 0; b < 8; b = b + 1) begin
            rx_pin = data[b];
            #(period);
        end
        rx_pin = !bad_stop;
        #(period);
        rx_pin = 1;
        #(period);
    endtask

    initial begin
        reset_dut();
        check_reg('h000, 1);
        check_reg('h004, 3);
        check_reg('h008, 5);
        check_reg('h00c, 0);
        check_reg('h014, (EDRV32_CLK_SYS_HZ * 16 + 57600) / 115200);
        check_reg('h018, 1);
        check_reg('h024, 0);
        if (tx_pin !== 1 || irq !== 0) $fatal(1, "FAIL reset pads");

        // UA-01: independent pin sampling plus loopback checks at each required rate.
        for (rate = 0; rate < 3; rate = rate + 1) begin
            case (rate)
                0: divisor = (EDRV32_CLK_SYS_HZ * 16 + 57600) / 115200;
                1: divisor = (EDRV32_CLK_SYS_HZ * 16 + 460800) / 921600;
                default: divisor = (EDRV32_CLK_SYS_HZ * 16 + 1500000) / 3000000;
            endcase
            bit_period = divisor * 10.0 / 16.0;
            write_reg('h014, divisor, 0);
            check_reg('h014, divisor);
            fork
                begin
                    for (integer n = 0; n < 12; n = n + 1)
                        capture_tx(8'h35 ^ (8'h13 * n[7:0]), bit_period);
                end
                begin
                    for (integer n = 0; n < 12; n = n + 1)
                        write_reg('h020, {24'b0, (8'h35 ^ (8'h13 * n[7:0]))}, 0);
                end
            join
            #(bit_period);
            check_reg('h008, 'h000c0001);
            for (i = 0; i < 12; i = i + 1)
                check_reg('h024, {23'b0, 1'b1, (8'h35 ^ (8'h13 * i[7:0]))});
            check_reg('h008, 5);
        end
        cases = cases + 1;
        $display("PASS UA-01 115200/921600/3M transmit and loopback");

        // Fractional edge timing: cumulative error stays below one system clock.
        write_reg('h014, 805);
        fork
            begin : fractional_edges
                realtime start_time;
                realtime elapsed;
                @(negedge tx_pin);
                start_time = $realtime;
                for (integer b = 1; b <= 9; b = b + 1) begin
                    @(tx_pin);
                    elapsed = $realtime - start_time;
                    if (elapsed <= b * 503.125 - 10.0 || elapsed >= b * 503.125 + 10.0)
                        $fatal(1, "FAIL fractional bit %0d elapsed=%f", b, elapsed);
                end
            end
            write_reg('h020, 'h55);
        join
        ticks(60);
        check_reg('h024, 'h155);
        write_reg('h014, 800);

        // UA-02: disabled transmitter allows all sixteen FIFO entries to fill.
        write_reg('h004, 2);
        for (i = 0; i < 16; i = i + 1) write_reg('h020, 32'h40 + i);
        check_reg('h008, 'h1006);
        write_reg('h020, 'hee);
        check_reg('h008, 'h1006);
        fork
            begin
                for (integer n = 0; n < 16; n = n + 1)
                    capture_tx(8'h40 + n[7:0], 500.0);
            end
            write_reg('h004, 3);
        join
        ticks(60);
        check_reg('h008, 'h00100009);
        for (i = 0; i < 16; i = i + 1) check_reg('h024, 'h140 + i);
        write_reg('h004, 2);
        write_reg('h020, 'h77);
        write_reg('h004, 6);
        check_reg('h004, 2);
        check_reg('h008, 5);
        write_reg('h004, 3);
        write_reg('h020, 'h5a);
        ticks(520);
        check_reg('h008, 'h00010001);
        write_reg('h004, 11);
        check_reg('h004, 3);
        check_reg('h008, 5);
        // CLR does not interrupt an active frame; EN changes affect the next frame.
        fork
            capture_tx('h96, 500.0);
            begin
                write_reg('h020, 'h96);
                ticks(70);
                write_reg('h004, 12);
                check_reg('h008, 'h10, 'h10);
            end
        join
        ticks(60);
        check_reg('h024, 'h196);
        write_reg('h004, 3);
        cases = cases + 1;
        $display("PASS UA-02 FIFO boundaries, clears and active-frame controls");

        // UA-03: overflowing receiver preserves the first sixteen bytes.
        loopback = 0;
        for (i = 0; i < 17; i = i + 1) send_rx(i[7:0], 500.0);
        check_reg('h008, 'h00100009);
        check_reg('h010, 7);
        for (i = 0; i < 16; i = i + 1) check_reg('h024, 'h100 + i);
        check_reg('h010, 6);
        write_reg('h010, 4);
        check_reg('h010, 2);
        cases = cases + 1;
        $display("PASS UA-03 receiver overrun and retained byte order");

        // UA-04: bad STOP is discarded and FRAME_ERR remains until W1C.
        send_rx('hcd, 500.0, 1);
        check_reg('h024, 0);
        check_reg('h010, 10);
        send_rx('h42, 500.0);
        check_reg('h024, 'h142);
        check_reg('h010, 10);
        cases = cases + 1;
        $display("PASS UA-04 bad STOP discard and sticky frame error");

        // UA-05: all four interrupt conditions, masks, RO bits and threshold zero.
        write_reg('h00c, 8);
        if (irq !== 1) $fatal(1, "FAIL FRAME_ERR interrupt");
        write_reg('h010, 8);
        if (irq !== 0) $fatal(1, "FAIL FRAME_ERR clear");
        write_reg('h00c, 2);
        if (irq !== 1) $fatal(1, "FAIL TX_EMPTY interrupt");
        write_reg('h010, 3);
        if (irq !== 1) $fatal(1, "FAIL RO TX_EMPTY");
        write_reg('h00c, 1);
        write_reg('h018, 2);
        send_rx('h11, 500.0);
        if (irq !== 0) $fatal(1, "FAIL threshold early");
        send_rx('h22, 500.0);
        if (irq !== 1) $fatal(1, "FAIL RX_THRESH interrupt");
        check_reg('h024, 'h111);
        if (irq !== 0) $fatal(1, "FAIL threshold deassertion");
        write_reg('h018, 0);
        if (irq !== 0) $fatal(1, "FAIL zero threshold");
        write_reg('h004, 11);
        write_reg('h00c, 4);
        for (i = 0; i < 17; i = i + 1) send_rx(i[7:0], 500.0);
        if (irq !== 1) $fatal(1, "FAIL RX_OVERRUN interrupt");
        write_reg('h00c, 0);
        if (irq !== 0) $fatal(1, "FAIL interrupt mask");
        write_reg('h010, 4);
        write_reg('h004, 11);
        cases = cases + 1;
        $display("PASS UA-05 all interrupt sources and masks");

        // UA-06: independent source transmits with both signs of baud mismatch.
        for (i = 0; i < 8; i = i + 1) send_rx(8'had ^ i[7:0], 490.0);
        for (i = 0; i < 8; i = i + 1) send_rx(8'had ^ i[7:0], 510.0);
        for (i = 0; i < 16; i = i + 1) check_reg('h024, {23'b0, 1'b1, (8'had ^ (i[7:0] & 8'h07))});
        check_reg('h010, 2);
        write_reg('hffc, 'hffffffff);
        check_reg('hffc, 0);
        write_reg('h020, 0);
        ticks(2);
        if (tx_pin !== 0) $fatal(1, "FAIL reset test must start with active TX");
        @(negedge clk);
        rst_n = 0;
        #1;
        if (tx_pin !== 1 || irq !== 0) $fatal(1, "FAIL asynchronous reset pads");
        cases = cases + 1;
        $display("PASS UA-06 +/-2 percent source baud mismatch");
        $display("PASS periph_uart %0d cases", cases);
        $finish;
    end
endmodule
