// File: tb.sv; sys-subsys-testplan i2c unit coverage.
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
    wire [1:0] scl_out;
    wire [1:0] scl_oe;
    wire [1:0] sda_out;
    wire [1:0] sda_oe;
    reg [1:0] slave_low = 0;
    wire [1:0] scl = ~scl_oe;
    wire [1:0] sda = ~(sda_oe | slave_low);
    integer selected_port = 0;
    integer quarter_cycles = 94;
    integer start_count [0:1];
    integer stop_count [0:1];
    integer byte_count [0:1];
    integer address_phase [0:1];
    reg [15:0] register_addr [0:1];
    reg [7:0] registers [0:1][0:65535];
    integer port_number;
    integer speed;
    integer old_count;
    integer starts_before;
    integer stops_before;
    reg timing_enabled = 0;
    edrv32_periph_i2c dut (
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
        .i2c0_scl_i(scl),
        .i2c0_scl_o(scl_out),
        .i2c0_scl_oe_o(scl_oe),
        .i2c0_sda_i(sda),
        .i2c0_sda_o(sda_out),
        .i2c0_sda_oe_o(sda_oe)
    );

    // Observe the pads independently; each unselected pair must remain released.
    always @(negedge clk) begin
        if (rst_n) begin
            if (scl_out !== 0 || sda_out !== 0) $fatal(1, "FAIL open drain data");
            if (scl_oe[1-selected_port] !== 0 || sda_oe[1-selected_port] !== 0)
                $fatal(1, "FAIL inactive port driven");
        end
    end

    generate
        for (genvar p = 0; p < 2; p = p + 1) begin : g_bus_monitor
            time sda_fall;
            time sda_rise;
            time scl_rise;
            always @(negedge sda[p]) begin
                if (rst_n && scl[p]) begin
                    start_count[p] = start_count[p] + 1;
                    sda_fall = $time;
                    if (timing_enabled && $time - scl_rise < quarter_cycles * 10)
                        $fatal(1, "FAIL START setup");
                end
            end
            always @(posedge sda[p]) begin
                if (rst_n && scl[p]) begin
                    stop_count[p] = stop_count[p] + 1;
                    sda_rise = $time;
                    if (timing_enabled && $time - scl_rise != quarter_cycles * 10)
                        $fatal(1, "FAIL STOP setup");
                end
            end
            always @(posedge scl[p]) scl_rise = $time;
            always @(negedge scl[p]) begin
                if (rst_n && timing_enabled && $time - sda_fall < quarter_cycles * 10)
                    $fatal(1, "FAIL START hold");
            end
        end
    endgenerate

    task automatic start_slave(input integer p);
        @(negedge sda[p]);
        if (scl[p] !== 1) $fatal(1, "FAIL missing START on port %0d", p);
        address_phase[p] = 0;
    endtask

    task automatic stop_slave(input integer p);
        // Releasing the slave ACK can raise SDA while SCL is low; that is not STOP.
        do @(posedge sda[p]); while (scl[p] !== 1);
    endtask

    // Minimal SCCB slave: address byte, high/low register address, then byte data.
    task automatic slave_write(input integer p, input [7:0] expected,
                               input bit has_start, input bit has_stop, input bit nack);
        reg [7:0] actual;
        time previous_edge;
        time rising_edge;
        time falling_edge;
        if (has_start) start_slave(p);
        previous_edge = 0;
        for (integer b = 7; b >= 0; b = b - 1) begin
            @(posedge scl[p]);
            rising_edge = $time;
            if (previous_edge != 0 && rising_edge - previous_edge != quarter_cycles * 40)
                $fatal(1, "FAIL SCL period expected=%0d actual=%0t",
                       quarter_cycles * 40, rising_edge - previous_edge);
            previous_edge = rising_edge;
            actual[b] = sda[p];
            @(negedge scl[p]);
            falling_edge = $time;
            if (falling_edge - rising_edge != quarter_cycles * 20)
                $fatal(1, "FAIL SCL high time");
        end
        slave_low[p] = !nack;
        @(posedge scl[p]);
        if ($time - previous_edge != quarter_cycles * 40) $fatal(1, "FAIL ACK period");
        @(negedge scl[p]);
        slave_low[p] = 0;
        if (actual !== expected)
            $fatal(1, "FAIL port=%0d expected byte=%h actual=%h", p, expected, actual);
        byte_count[p] = byte_count[p] + 1;
        if (!nack) begin
            case (address_phase[p])
                0: if (actual != 'h78 && actual != 'h79) $fatal(1, "FAIL SCCB address");
                1: register_addr[p][15:8] = actual;
                2: register_addr[p][7:0] = actual;
                default: registers[p][register_addr[p]] = actual;
            endcase
            address_phase[p] = address_phase[p] + 1;
        end
        if (has_stop) stop_slave(p);
    endtask

    task automatic slave_read(input integer p, input bit has_stop, input bit nack);
        reg [7:0] data;
        data = registers[p][register_addr[p]];
        // The preceding address command leaves SCL low, so data can be set up now.
        for (integer b = 7; b >= 0; b = b - 1) begin
            slave_low[p] = !data[b];
            @(posedge scl[p]);
            @(negedge scl[p]);
        end
        slave_low[p] = 0;
        @(posedge scl[p]);
        if (sda[p] !== nack) $fatal(1, "FAIL master ACK/NACK expected=%b actual=%b", nack, sda[p]);
        @(negedge scl[p]);
        byte_count[p] = byte_count[p] + 1;
        if (has_stop) stop_slave(p);
    endtask

    task automatic issue_command(input [11:0] command, input bit inject_busy = 0);
        reg [31:0] status;
        write_reg('h010, 1, 0);
        if (irq !== 0) $fatal(1, "FAIL DONE clear");
        write_reg('h018, {20'b0, command}, 0);
        read_reg('h008, status);
        if (status[0] !== 1) $fatal(1, "FAIL BUSY not asserted");
        if (inject_busy) begin
            write_reg('h018, 'h3ee);
            write_reg('h004, selected_port == 0 ? 3 : 1);
            check_reg('h004, selected_port == 0 ? 1 : 3);
        end
        do begin
            read_reg('h008, status);
        end while (status[0]);
        check_reg('h010, 1);
        if (irq !== 1) $fatal(1, "FAIL command DONE interrupt");
        if (status[2] !== !command[9]) $fatal(1, "FAIL BUS_HELD after command");
    endtask

    task automatic write_byte(input [7:0] data, input bit start_bit = 0,
                              input bit stop_bit = 0, input bit nack = 0,
                              input bit inject_busy = 0);
        fork
            slave_write(selected_port, data, start_bit, stop_bit, nack);
            issue_command({1'b0, 1'b0, stop_bit, start_bit, data}, inject_busy);
        join
        check_reg('h008, nack ? 2 : 0, 2);
    endtask

    task automatic read_byte(input bit stop_bit, input bit nack, input [7:0] expected);
        fork
            slave_read(selected_port, stop_bit, nack);
            issue_command({nack, 1'b1, stop_bit, 1'b0, 8'b0});
        join
        check_reg('h01c, {24'b0, expected});
    endtask

    initial begin
        for (integer p = 0; p < 2; p = p + 1) begin
            start_count[p] = 0;
            stop_count[p] = 0;
            byte_count[p] = 0;
            address_phase[p] = 0;
            register_addr[p] = 0;
        end
        reset_dut();
        check_reg('h000, 'h00040001);
        check_reg('h004, 0);
        check_reg('h008, 0);
        check_reg('h00c, 0);
        check_reg('h010, 0);
        check_reg('h014, 93);
        check_reg('h01c, 0);
        write_reg('h018, 'h378);
        ticks(20);
        check_reg('h008, 0);
        if (scl_oe !== 0 || sda_oe !== 0 || irq !== 0) $fatal(1, "FAIL disabled state");
        write_reg('h00c, 1, 0);

        // IC-01/04/05: both physical ports, real 400k and 100k divider values.
        for (speed = 0; speed < 2; speed = speed + 1) begin
            quarter_cycles = speed == 0 ? 94 : 375;
            write_reg('h014, quarter_cycles - 1, 0);
            for (port_number = 0; port_number < 2; port_number = port_number + 1) begin
                @(negedge clk);
                selected_port = port_number;
                write_reg('h004, selected_port == 0 ? 1 : 3);
                timing_enabled = 1;
                write_byte('h78, 1);
                write_byte('h30);
                write_byte('h12);
                write_byte(8'h51 + port_number[7:0] + speed[7:0], 0, 1);
                if (registers[selected_port]['h3012] !== 8'h51 + port_number[7:0] + speed[7:0])
                    $fatal(1, "FAIL SCCB register write");
                if (scl_oe !== 0 || sda_oe !== 0) $fatal(1, "FAIL STOP release");
            end
        end
        cases = cases + 1;
        $display("PASS IC-01 both SCCB ports, address and register bytes");
        cases = cases + 1;
        $display("PASS IC-04 inactive port release and open drain outputs");
        cases = cases + 1;
        $display("PASS IC-05 100k/400k SCL and START/STOP timing");

        // IC-02: address write followed by STOP/START, then repeated START.
        for (port_number = 0; port_number < 2; port_number = port_number + 1) begin
            @(negedge clk);
            selected_port = port_number;
            write_reg('h004, selected_port == 0 ? 1 : 3);
            for (integer repeated = 0; repeated < 2; repeated = repeated + 1) begin
                starts_before = start_count[selected_port];
                stops_before = stop_count[selected_port];
                write_byte('h78, 1);
                write_byte('h30);
                write_byte('h12, 0, repeated == 0);
                write_byte('h79, 1);
                // Exercise read ACK and NACK on the same held bus.
                read_byte(0, 0, 8'h52 + port_number[7:0]);
                read_byte(1, 1, 8'h52 + port_number[7:0]);
                if (start_count[selected_port] != starts_before + 2)
                    $fatal(1, "FAIL repeated START count");
                if (stop_count[selected_port] != stops_before + (repeated == 0 ? 2 : 1))
                    $fatal(1, "FAIL STOP count");
            end
        end
        cases = cases + 1;
        $display("PASS IC-02 read ACK/NACK and STOP/START/repeated START");

        // IC-03: NACK still completes, sets status and raises DONE; mask/W1C work.
        write_byte('h78, 1, 1, 1);
        check_reg('h008, 2);
        check_reg('h010, 1);
        write_reg('h00c, 0);
        if (irq !== 0) $fatal(1, "FAIL DONE mask");
        check_reg('h010, 1);
        write_reg('h010, 1);
        check_reg('h010, 0);
        write_reg('h00c, 1);
        write_byte('h78, 1, 1);
        check_reg('h008, 0);
        cases = cases + 1;
        $display("PASS IC-03 NACK status, completion, IRQ mask and W1C");

        // IC-06: a second CMD and a port switch attempted while BUSY are ignored.
        old_count = byte_count[selected_port];
        write_byte('h78, 1, 1, 0, 1);
        ticks(quarter_cycles * 40);
        if (byte_count[selected_port] != old_count + 1) $fatal(1, "FAIL BUSY command accepted");
        write_reg('hffc, 'hffffffff);
        check_reg('hffc, 0);
        write_reg('h018, 'h100);
        ticks(quarter_cycles * 3);
        if (sda_oe === 0) $fatal(1, "FAIL reset test must start on active bus");
        @(negedge clk);
        rst_n = 0;
        #1;
        if (scl_oe !== 0 || sda_oe !== 0 || irq !== 0)
            $fatal(1, "FAIL asynchronous reset release");
        cases = cases + 1;
        $display("PASS IC-06 BUSY writes ignored");
        $display("PASS periph_i2c %0d cases", cases);
        $finish;
    end
endmodule
