// File: eth_stimulus.svh
// Spec: soc-testplan SC-06; eth 2.2-2.5.
// Description: Send checked ARP/UDP traffic and verify the hardware ARP reply.
// Clock domain: external Ethernet RX/TX clocks.
    bit arp_checked = 0;
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
        end
        $fclose(fd);
        rx_complete = 1;
    end

    initial begin : transmit_checker
        forever begin
            @(negedge eth_tx_clk_i);
            if (u_eth.frame_done) begin
                check_arp();
            end
        end
    end
