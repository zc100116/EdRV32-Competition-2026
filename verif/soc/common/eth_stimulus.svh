// File: eth_stimulus.svh
// Spec: soc-testplan SC-06/07/08/09/10/11; eth 2.3-2.6; b2-software 3.4a/3.5a.
// Description: Send checked ARP/UDP traffic and reassemble outgoing video/monitor blocks.
// Clock domain: external Ethernet RX/TX clocks.
    bit arp_checked = 0;
    bit video_checked = 0;
    bit monitor_checked = 0;
    int video_frames = 0;
    int video_position = 0;
    int monitor_position = 0;
    byte unsigned monitor_bytes[5120];

    function automatic bit [31:0] little_word(input int offset);
        bit [31:0] value;
        for (int i = 0; i < 4; i++) value[i*8+:8] = monitor_bytes[offset+i];
        return value;
    endfunction

    task automatic net_equal(input string label, input int position,
                            input bit [31:0] expected, input bit [31:0] actual);
        if (actual != expected)
            $fatal(1, "FAIL ETH %s byte=%0d expected=%h actual=%h time=%0t",
                label, position, expected, actual, $time);
    endtask

    task automatic check_arp;
        int fd;
        int expected;
        fd = $fopen({data_dir, "/arp.bin"}, "rb");
        if (fd == 0) $fatal(1, "arp.bin open failed");
        for (int i = 0; i < 60; i++) begin
            expected = $fgetc(fd);
            net_equal("ARP", i, 32'(expected), {24'b0, u_eth.received[i]});
        end
        $fclose(fd);
        arp_checked = 1;
        $display("CHECK ETH ARP reply time=%0t", $time);
        $fflush();
    endtask

    task automatic check_monitor;
        bit [31:0] expected;
        for (int record = 0; record < 16; record++) begin
            net_equal("EDTM magic", record*320, 32'h4d544445, little_word(record*320));
            net_equal("EDTM version/type", record*320+4, 32'h00010001,
                        little_word(record*320+4));
            net_equal("EDTM seq", record*320+8, 32'(record), little_word(record*320+8));
            for (int port = 0; port < 7; port++) begin
                for (int field = 0; field < 7; field++) begin
                    expected = peek_word(32'h0a102000 + 32'((record*49+port*7+field)*4));
                    net_equal("EDTM snapshot", record*320+36+port*28+field*4, expected,
                                little_word(record*320+36+port*28+field*4));
                end
            end
            for (int i = 292; i < 320; i++)
                net_equal("EDTM reserved", record*320+i, 0,
                            {24'b0, monitor_bytes[record*320+i]});
        end
        monitor_checked = 1;
        $display("CHECK ETH 16 EDTM records time=%0t", $time);
    endtask

    task automatic check_udp;
        int length;
        int offset;
        int window;
        int expected_position;
        bit [31:0] source;
        byte unsigned expected;
        int sum;
        length = int'({u_eth.received[38], u_eth.received[39]}) - 16;
        window = int'(u_eth.received[42]);
        offset = int'({u_eth.received[46], u_eth.received[47],
                        u_eth.received[48], u_eth.received[49]});
        sum = 0;
        for (int i = 14; i < 34; i += 2)
            sum += int'({u_eth.received[i], u_eth.received[i+1]});
        sum = (sum & 65535) + (sum >> 16);
        sum = (sum & 65535) + (sum >> 16);
        net_equal("IPv4 checksum", 24, 65535, 32'(sum));
        net_equal("UDP source port", 34, 9000,
                    {16'b0, u_eth.received[34], u_eth.received[35]});
        net_equal("UDP destination port", 36, 9001,
                    {16'b0, u_eth.received[36], u_eth.received[37]});
        expected_position = window == 0 ? video_position : monitor_position;
        net_equal("block offset", 46, 32'(expected_position), 32'(offset));
        for (int i = 0; i < length; i++) begin
            if (window == 0) begin
                source = offset + i < 32 ? 32'h0a100000 + 32'(offset+i) :
                            32'h06000000 + 32'(offset+i-32);
                expected = u_ddr.peek(source);
                net_equal("EDVF/Surface", offset+i, {24'b0, expected},
                            {24'b0, u_eth.received[50+i]});
            end else if (window == 3) begin
                monitor_bytes[offset+i] = u_eth.received[50+i];
                expected = u_ddr.peek(32'h0a104000 + 32'(offset+i));
                net_equal("EDTM source", offset+i, {24'b0, expected},
                            {24'b0, u_eth.received[50+i]});
            end else $fatal(1, "FAIL TX WIN expected=0/3 actual=%0d time=%0t", window, $time);
        end
        if (window == 0) begin
            if (offset == 0) begin
                net_equal("EDVF magic", 0, 32'h46564445, peek_word(32'h0a100000));
                net_equal("EDVF version/format", 4, 32'h00010001, peek_word(32'h0a100004));
                net_equal("EDVF dimensions", 8, 32'h02d00500, peek_word(32'h0a100008));
                net_equal("EDVF stride", 12, 2560, peek_word(32'h0a10000c));
                net_equal("EDVF frame_id", 16, 7, peek_word(32'h0a100010));
                net_equal("EDVF scene", 28, 1, peek_word(32'h0a10001c));
            end
            video_position += length;
            net_equal("EDVF NOTIFY", offset, video_position == 1843232 ? 1 : 0,
                        {31'b0, u_eth.received[43][0]});
            if (video_position == 1843232) begin
                video_checked = 1;
                video_frames++;
                video_position = 0;
                $display("CHECK ETH video frame=%0d bytes=1843232 time=%0t", video_frames, $time);
            end
        end else begin
            monitor_position += length;
            net_equal("EDTM NOTIFY", offset, monitor_position == 5120 ? 1 : 0,
                        {31'b0, u_eth.received[43][0]});
            if (monitor_position == 5120) check_monitor();
        end
    endtask

    initial begin : receive_stimulus
        int fd;
        int length;
        int value;
        byte unsigned frame[$];
        wait (rx_requested);
        fd = $fopen({data_dir, "/rx.bin"}, "rb");
        if (fd == 0) $fatal(1, "rx.bin open failed");
        for (int index = 0; index < 67; index++) begin
            length = 0;
            for (int i = 0; i < 4; i++) begin
                value = $fgetc(fd);
                length |= value << (8*i);
            end
            frame.delete();
            repeat (length) begin
                value = $fgetc(fd);
                frame.push_back(8'(value));
            end
            u_eth.send_frame(frame);
            if (index == 0) wait (arp_checked);
            if (rx_stop) break;
        end
        $fclose(fd);
        rx_complete = 1;
    end

    initial begin : transmit_checker
        forever begin
            @(negedge eth_tx_clk_i);
            if (u_eth.frame_done) begin
                if ({u_eth.received[12], u_eth.received[13]} == 16'h0806) check_arp();
                else check_udp();
            end
        end
    end
