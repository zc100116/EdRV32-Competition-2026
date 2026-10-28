// File: edrv32_eth_tb.sv
// Spec: eth 2-7; eth-testplan ET-01 through ET-15.
// Description: Scripted independent scoreboard with asynchronous MAC, APB, AXI and PHY models.
// Clock domain: three unrelated 125 MHz clocks; rx +100 ppm, tx -100 ppm.
`timescale 1ns/1fs
module edrv32_eth_tb;
    logic clk_mem = 0;
    logic clk_rx = 0;
    logic clk_tx = 0;
    logic rst_mem_n = 0;
    logic rst_rx_n = 0;
    logic rst_tx_n = 0;
    logic [7:0] rxd;
    logic rx_dv;
    logic rx_er;
    logic [7:0] txd;
    logic tx_en;
    logic tx_er;
    logic mdc;
    logic mdio_out;
    logic mdio_oe;
    logic mdio_in;
    logic phy_rst_n;
    logic irq;
    int checker_errors;
    edrv32_apb_if apb ();
    edrv32_axi256_if axi ();
    typedef byte unsigned bytes_t[$];
    bytes_t expected_frames[int];
    int expected_count;
    int checked_count = 0;
    int source_queue[$];
    string vector_dir;
    string script_path;
    int script;
    int scan;
    string op;
    bit [31:0] a;
    bit [31:0] b;
    bit [31:0] c;
    bit [31:0] d;
    bit [31:0] value;
    int source_done = 0;
    bit source_busy = 0;
    realtime measure_start;
    realtime arp_deadline_start;
    int arp_deadline_frame = -1;
    bit [31:0] perf9_snapshot;
    int overflow_accepted;
    int overflow_total;

    localparam realtime RX_HALF = 4.0 / 1.0001;
    localparam realtime TX_HALF = 4.0 / 0.9999;
    always #4 clk_mem = ~clk_mem;
    initial begin
        #1.137;
        forever #(RX_HALF) clk_rx = ~clk_rx;
    end
    initial begin
        #2.719;
        forever #(TX_HALF) clk_tx = ~clk_tx;
    end
    edrv32_eth_memory u_memory (
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
    eth_peer_model u_peer (
        .rx_clk_i(clk_rx),
        .tx_clk_i(clk_tx),
        .rst_n_i(rst_tx_n),
        .rxd_o(rxd),
        .rx_dv_o(rx_dv),
        .rx_er_o(rx_er),
        .txd_i(txd),
        .tx_en_i(tx_en),
        .tx_er_i(tx_er)
    );
    edrv32_eth_phy u_phy (
        .rst_n_i(rst_mem_n),
        .mdc_i(mdc),
        .mdio_i(mdio_out),
        .mdio_oe_i(mdio_oe),
        .mdio_o(mdio_in)
    );
    `include "dut_connections.svh"

    task automatic apb_access(input bit write_i,
        input bit [11:0] addr_i,
        input bit [31:0] data_i,
        output bit [31:0] data_o);
        @(negedge clk_mem);
        apb.paddr = addr_i;
        apb.psel = 1;
        apb.penable = 0;
        apb.pwrite = write_i;
        apb.pwdata = data_i;
        apb.pstrb = 0; // eth 4: PSTRB is ignored, including zero.
        @(negedge clk_mem);
        apb.penable = 1;
        @(posedge clk_mem);
        if (!apb.pready[0] || apb.pslverr[0])
            $fatal(1, "FAIL APB reg=%h ready/error expected=1/0 actual=%b/%b time=%0t",
                addr_i, apb.pready[0], apb.pslverr[0], $time);
        data_o = apb.prdata[31:0];
        @(negedge clk_mem);
        apb.psel = 0;
        apb.penable = 0;
    endtask

    task automatic compare(input string name_i,
        input bit [31:0] expected_i,
        input bit [31:0] actual_i);
        if (expected_i != actual_i)
            $fatal(1, "FAIL %s expected=%h actual=%h time=%0t",
                name_i, expected_i, actual_i, $time);
    endtask

    task automatic memory_file(input int id_i,
        input bit checking_i);
        int fd;
        int count;
        int result;
        bit [31:0] address;
        bit [7:0] data;
        byte unsigned expected[bit [31:0]];
        expected.delete();
        fd = $fopen($sformatf("%s/m%0d.txt", vector_dir, id_i), "r");
        if (fd == 0) $fatal(1, "FAIL open memory file id=%0d time=%0t", id_i, $time);
        result = $fscanf(fd, "%d", count);
        compare("memory header fields", 1, 32'(result));
        repeat (count) begin
            result = $fscanf(fd, "%h %h", address, data);
            compare("memory entry fields", 2, 32'(result));
            if (checking_i) begin
                expected[address] = data;
                compare($sformatf("DDR byte=%h", address), 32'(data),
                    32'(u_memory.peek(address)));
            end else u_memory.mem[address] = data;
        end
        if (checking_i) begin
            foreach (u_memory.mem[address]) begin
                data = expected.exists(address) != 0 ? expected[address] : 8'ha5;
                compare($sformatf("DDR stray byte=%h", address), 32'(data),
                    32'(u_memory.mem[address]));
            end
        end
        $fclose(fd);
    endtask

    initial begin : source
        int id;
        int fd;
        int length;
        int gap;
        int flip;
        int er;
        int trim;
        int extend;
        int result;
        bit [7:0] data;
        bytes_t bytes;
        wait (rst_rx_n);
        forever begin
            wait (source_queue.size() != 0);
            id = source_queue.pop_front();
            source_busy = 1;
            fd = $fopen($sformatf("%s/f%0d.txt", vector_dir, id), "r");
            if (fd == 0) $fatal(1, "FAIL open frame id=%0d time=%0t", id, $time);
            result = $fscanf(fd, "%d %d %d %d %d %d", length, gap, flip, er, trim, extend);
            compare("source frame header fields", 6, 32'(result));
            bytes.delete();
            repeat (length) begin
                result = $fscanf(fd, "%h", data);
                compare("frame byte fields", 1, 32'(result));
                bytes.push_back(data);
            end
            $fclose(fd);
            u_peer.send_frame(bytes, gap, flip, er, trim, extend);
            source_done++;
            source_busy = 0;
        end
    end

    always @(negedge clk_tx) begin
        if (u_peer.frame_done) begin
            if (checked_count >= expected_count)
                $fatal(1, "FAIL TX frame=%0d expected=no frame actual=frame time=%0t",
                    checked_count, $time);
            compare($sformatf("TX frame=%0d length", checked_count),
                32'(expected_frames[checked_count].size()-4), 32'(u_peer.received.size()));
            foreach (u_peer.received[i]) begin
                compare($sformatf("TX frame=%0d byte=%0d", checked_count, i),
                    32'(expected_frames[checked_count][i]), 32'(u_peer.received[i]));
            end
            for (int i = 0; i < 4; i++)
                compare($sformatf("TX frame=%0d FCS byte=%0d", checked_count, i),
                    32'(expected_frames[checked_count][u_peer.received.size()+i]),
                    32'(u_peer.received_fcs[i*8+:8]));
            if (arp_deadline_frame >= 0 && checked_count < arp_deadline_frame
                && u_peer.frame_end > arp_deadline_start)
                arp_deadline_start = u_peer.frame_end;
            if (checked_count == arp_deadline_frame) begin
                if (u_peer.frame_start-arp_deadline_start > 10000.0)
                    $fatal(1, "FAIL ARP latency expected<=10000ns actual=%0f time=%0t",
                        u_peer.frame_start-arp_deadline_start, $time);
            end
            checked_count++;
        end
    end

    initial begin : stimulus
        int fd;
        int length;
        int result;
        bit [7:0] data;
        bytes_t bytes;
        apb.paddr = 0;
        apb.psel = 0;
        apb.penable = 0;
        apb.pwrite = 0;
        apb.pwdata = 0;
        apb.pstrb = 0;
        if (!$value$plusargs("SCRIPT=%s", script_path))
            $fatal(1, "FAIL missing +SCRIPT time=%0t", $time);
        if (!$value$plusargs("VECTORS=%s", vector_dir))
            $fatal(1, "FAIL missing +VECTORS time=%0t", $time);
        fd = $fopen({vector_dir, "/expected.txt"}, "r");
        if (fd == 0) $fatal(1, "FAIL open expected frames time=%0t", $time);
        result = $fscanf(fd, "%d", expected_count);
        compare("expected frame count fields", 1, 32'(result));
        for (int i = 0; i < expected_count; i++) begin
            result = $fscanf(fd, "%d", length);
            compare("expected frame length fields", 1, 32'(result));
            bytes.delete();
            repeat (length) begin
                result = $fscanf(fd, "%h", data);
                compare("frame byte fields", 1, 32'(result));
                bytes.push_back(data);
            end
            expected_frames[i] = bytes;
        end
        $fclose(fd);
        repeat (8) @(negedge clk_mem);
        rst_mem_n = 1;
        @(negedge clk_rx);
        rst_rx_n = 1;
        @(negedge clk_tx);
        rst_tx_n = 1;
        script = $fopen(script_path, "r");
        if (script == 0) $fatal(1, "FAIL open script %s time=%0t", script_path, $time);
        while (!$feof(script)) begin
            scan = $fscanf(script, "%s %h %h %h %h", op, a, b, c, d);
            if (scan != 5 && !$feof(script))
                $fatal(1, "FAIL script fields expected=5 actual=%0d time=%0t", scan, $time);
            if (scan == 5) begin
                case (op)
                    "W": apb_access(1, a[11:0], b, value);
                    "R": begin
                        apb_access(0, a[11:0], 0, value);
                        compare($sformatf("reg=%h", a), b & c, value & c);
                    end
                    "P": begin
                        do apb_access(0, a[11:0], 0, value);
                        while ((value & c) != (b & c));
                    end
                    "D": repeat (a) @(negedge clk_mem);
                    "S": source_queue.push_back(int'(a));
                    "F": wait (source_done == int'(a));
                    "X": wait (checked_count == int'(a));
                    "L": memory_file(int'(a), 0);
                    "C": memory_file(int'(a), 1);
                    "T": begin
                        @(negedge clk_mem);
                        case (a)
                            0: u_memory.random_percent = int'(b);
                            1: u_memory.read_latency = int'(b);
                            2: u_memory.write_latency = int'(b);
                            3: u_memory.stop_write = b[0];
                            4: u_memory.hold_b = b[0];
                            5: u_memory.stop_read = b[0];
                            6: u_memory.hold_r = b[0];
                            7: u_memory.r_error_transaction = int'(b);
                            8: u_memory.b_error_transaction = int'(b);
                            9: u_memory.random_state = b;
                            10: u_memory.r_error_address = b;
                            default: $fatal(1, "FAIL unknown memory control=%0d", a);
                        endcase
                    end
                    "H": begin
                        case (a)
                            0: wait (u_memory.ar_count > int'(b));
                            1: wait (axi.arvalid && axi.araddr >= b && axi.araddr < c);
                            2: wait (tx_en);
                            3: wait (u_memory.aw_count > int'(b));
                            4: wait (rx_dv);
                            default: $fatal(1, "FAIL unknown phase=%0d", a);
                        endcase
                    end
                    "Q": begin
                        apb_access(0, 12'h010, 0, value);
                        compare("NOTIFY before B", 0, value & a);
                    end
                    "N": begin
                        do begin
                            apb_access(0, 12'h010, 0, value);
                            if ((value & a) != 0 && u_memory.aw_count != u_memory.b_count)
                                $fatal(1, "FAIL NOTIFY B count expected=%0d actual=%0d time=%0t",
                                    u_memory.aw_count, u_memory.b_count, $time);
                        end while ((value & a) != a);
                        compare("irq_o", b, 32'(irq));
                    end
                    "I": compare("irq_o", a, 32'(irq));
                    "Y": compare("PHY reset", a, 32'(phy_rst_n));
                    "V": begin
                        u_phy.registers[a[4:0]] = b[15:0];
                    end
                    "J": begin
                        compare("MDIO transactions", a, 32'(u_phy.transactions));
                        compare("MDIO PHY", b, 32'(u_phy.last_phy));
                        compare("MDIO REG", c, 32'(u_phy.last_reg));
                        compare("MDIO register data", d, 32'(u_phy.registers[c[4:0]]));
                    end
                    "O": begin : overflow_check
                        bit written;
                        overflow_accepted = 0;
                        overflow_total = int'(b);
                        for (int i = 0; i < int'(b); i++) begin
                            written = u_memory.peek(a+32'(i)*c) != 8'ha5;
                            if (written) overflow_accepted++;
                            for (int j = 0; j < int'(c); j++)
                                compare($sformatf("overflow frame=%0d byte=%0d", i, j),
                                    written ? 32'(i+1) : 32'ha5,
                                    32'(u_memory.peek(a+32'(i)*c+32'(j))));
                        end
                        if (overflow_accepted == 0 || overflow_accepted == int'(b))
                            $fatal(1, "FAIL overflow accepted expected=1..%0d actual=%0d time=%0t",
                                b-1, overflow_accepted, $time);
                        foreach (u_memory.mem[address]) begin
                            if (address < a || address >= a+b*c)
                                compare($sformatf("overflow stray byte=%h", address),
                                    32'ha5, 32'(u_memory.mem[address]));
                        end
                        apb_access(0, 12'h040, 0, value);
                        compare("overflow PERF0", b, value);
                        apb_access(0, 12'h044, 0, value);
                        compare("overflow PERF1", 32'(overflow_accepted), value);
                        apb_access(0, 12'h048, 0, value);
                        compare("overflow PERF2", 32'(overflow_accepted)*c, value);
                        apb_access(0, 12'h05c, 0, value);
                        compare("overflow PERF7", b-32'(overflow_accepted), value);
                        apb_access(0, 12'h148, 0, value);
                        compare("overflow WIN0_BYTES", 32'(overflow_accepted)*c, value);
                        for (int i = 3; i <= 6; i++) begin
                            apb_access(0, 12'(32'h40+32'(i)*4), 0, value);
                            compare($sformatf("overflow PERF%0d", i), 0, value);
                        end
                    end
                    "U": begin
                        for (int i = 0; i < int'(b); i++)
                            compare($sformatf("recovery byte=%h", a+32'(i)), c,
                                32'(u_memory.peek(a+32'(i))));
                        apb_access(0, 12'h040, 0, value);
                        compare("recovery PERF0", 32'(overflow_total+1), value);
                        apb_access(0, 12'h044, 0, value);
                        compare("recovery PERF1", 32'(overflow_accepted+1), value);
                        apb_access(0, 12'h048, 0, value);
                        compare("recovery PERF2", 32'(overflow_accepted+1)*b, value);
                        apb_access(0, 12'h05c, 0, value);
                        compare("recovery PERF7", 32'(overflow_total-overflow_accepted), value);
                    end
                    "E": begin
                        compare("AXI outstanding reads", 32'(u_memory.ar_count),
                            32'(u_memory.r_count));
                        compare("AXI outstanding writes", 32'(u_memory.aw_count),
                            32'(u_memory.b_count));
                        compare("AXI checker", 0, 32'(checker_errors));
                        apb_access(0, 12'h064, 0, perf9_snapshot);
                        if (perf9_snapshot == 0)
                            $fatal(1, "FAIL PERF9 expected>0 actual=0 time=%0t", $time);
                        repeat (20) @(negedge clk_mem);
                        apb_access(0, 12'h064, 0, value);
                        compare("PERF9 stopped", perf9_snapshot, value);
                    end
                    "K": begin
                        apb_access(0, 12'h064, 0, value);
                        if (value > a)
                            $fatal(1, "FAIL PERF9 reset expected<=%0d actual=%0d time=%0t",
                                a, value, $time);
                    end
                    "B": measure_start = $realtime;
                    "G": begin
                        // Byte count / elapsed simulation nanoseconds, decimal MB/s.
                        if (real'(a)*1000.0/($realtime-measure_start) < 100.0)
                            $fatal(1, "FAIL throughput expected>=100MB/s actual=%0f time=%0t",
                                real'(a)*1000.0/($realtime-measure_start), $time);
                        $display("ETH throughput bytes=%0d elapsed_ns=%0f MB/s=%0f", a,
                            $realtime-measure_start, real'(a)*1000.0/($realtime-measure_start));
                    end
                    "A": begin
                        arp_deadline_start = u_peer.source_end;
                        arp_deadline_frame = int'(a);
                    end
                    default: $fatal(1, "FAIL unknown operation=%s time=%0t", op, $time);
                endcase
            end
        end
        $fclose(script);
        wait (!source_busy && source_queue.size() == 0);
        repeat (100) @(negedge clk_mem);
        compare("TX frame count", 32'(expected_count), 32'(checked_count));
        $display("PASS ETH script %s time=%0t", script_path, $time);
        $finish;
    end
    initial begin
        #100000000;
        $fatal(1, {"FAIL script=%s op=%s reg=%h frame=%0d RX=%0d ",
            "target=%0d expected=%h actual=%h mask=%h timeout time=%0t"},
            script_path, op, a[11:0], checked_count, source_done,
            a, b & c, value & c, c, $time);
    end
endmodule
