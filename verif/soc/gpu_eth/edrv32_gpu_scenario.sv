// File: edrv32_gpu_scenario.sv
// Spec: gpu-soc-testplan ST-13; visual SC-06 and BIOS ETH load.
// Description: Select ETH BIOS loading, send the program, then the SC-06 receive stream.
// Clock domain: clk_sys UART observation; Ethernet RX/TX external clocks.
`timescale 1ns/1ps
/* verilator lint_off BLKSEQ */
module edrv32_gpu_scenario (
    output bit checks_complete_o,
    output wire [1:0] model_sda_oe_o
);
    bit loader_arp_seen;
    bit rx_arp_seen;
    bit receive_phase;
    integer uart_position;
    string line_text;
    bit menu_seen;
    bit load_ready;
    bit load_pass;
    bit run_seen;
    assign model_sda_oe_o = 2'b00;

    task automatic send_file(input string name, input bit loader);
        int fd;
        int value;
        int length;
        int index;
        byte unsigned frame[$];
        fd = $fopen({$root.edrv32_gpu_soc_tb.data_dir, "/", name}, "rb");
        if (fd == 0) $fatal(1, "FAIL open ETH input %s", name);
        index = 0;
        value = $fgetc(fd);
        while (value != -1) begin
            length = value;
            for (int i = 1; i < 4; i++) length |= $fgetc(fd) << (8*i);
            frame.delete();
            repeat (length) frame.push_back(8'($fgetc(fd)));
            $root.edrv32_gpu_soc_tb.u_eth.send_frame(frame);
            if (index == 0) begin
                if (loader) wait (loader_arp_seen);
                else wait (rx_arp_seen);
            end
            index++;
            value = $fgetc(fd);
        end
        $fclose(fd);
    endtask

    always @(negedge $root.edrv32_gpu_soc_tb.clk_sys_i) begin
        while (uart_position < $root.edrv32_gpu_soc_tb.uart_log.len()) begin
            if ($root.edrv32_gpu_soc_tb.uart_log[uart_position] == 10) begin
                if (line_text == "BIOS menu: 1=UART load 2=ETH load 3=Run 4=Baud")
                    menu_seen = 1;
                if (line_text == "ETH load ready 192.168.1.10:5000") load_ready = 1;
                if (line_text == "Load result: PASS")
                    load_pass = 1;
                if (line_text.len() >= 7 && line_text.substr(0, 6) == "Run: 0x") run_seen = 1;
                line_text = "";
            end else if ($root.edrv32_gpu_soc_tb.uart_log[uart_position] != 13) begin
                line_text = {line_text,
                    string'($root.edrv32_gpu_soc_tb.uart_log[uart_position])};
            end
            uart_position++;
        end
    end
    always @(negedge $root.edrv32_gpu_soc_tb.eth_tx_clk_i) begin
        if ($root.edrv32_gpu_soc_tb.u_eth.frame_done) begin
            if (receive_phase) begin
                int fd;
                int expected;
                fd = $fopen({$root.edrv32_gpu_soc_tb.data_dir, "/arp.bin"}, "rb");
                if (fd == 0) $fatal(1, "FAIL open expected ARP");
                for (int i = 0; i < 60; i++) begin
                    expected = $fgetc(fd);
                    if ({24'b0, $root.edrv32_gpu_soc_tb.u_eth.received[i]} != 32'(expected))
                        $fatal(1, "FAIL ARP byte=%0d expected=%h actual=%h time=%0t",
                            i, expected, $root.edrv32_gpu_soc_tb.u_eth.received[i], $time);
                end
                $fclose(fd);
                rx_arp_seen = 1;
            end else loader_arp_seen = 1;
        end
    end
    // Retain visual SC-18 functional-test acceleration; B1 covers physical timing.
    // GPU SYS is 125 MHz: divider 256 gives 7.8125 Mbaud (16 * SYS / divider).
    reg [63:0] bios_next_time;
    initial begin
        #1;
        force $root.edrv32_gpu_soc_tb.u_dut.u_sys.u_uart.baud_div_r = 24'd256;
        $root.edrv32_gpu_soc_tb.u_uart.baud = 7812500.0;
        forever begin
            @(negedge $root.edrv32_gpu_soc_tb.clk_sys_i);
            if ($root.edrv32_gpu_soc_tb.u_dut.u_sys.u_clint.axi_arvalid_i &&
                $root.edrv32_gpu_soc_tb.u_dut.u_sys.u_clint.axi_arready_o &&
                $root.edrv32_gpu_soc_tb.u_dut.u_sys.u_clint.axi_araddr_i[15:3] == 13'h17ff) begin
                bios_next_time = $root.edrv32_gpu_soc_tb.u_dut.u_sys.u_clint.mtime_r + 10000;
                force $root.edrv32_gpu_soc_tb.u_dut.u_sys.u_clint.mtime_next_w = bios_next_time;
                @(negedge $root.edrv32_gpu_soc_tb.clk_sys_i);
                release $root.edrv32_gpu_soc_tb.u_dut.u_sys.u_clint.mtime_next_w;
            end
        end
    end

    initial begin
        checks_complete_o = 0;
        loader_arp_seen = 0;
        rx_arp_seen = 0;
        receive_phase = 0;
        uart_position = 0;
        line_text = "";
        menu_seen = 0;
        load_ready = 0;
        load_pass = 0;
        run_seen = 0;
        #1;
        $root.edrv32_gpu_soc_tb.gpio_i[0] = 0;
        wait (menu_seen);
        $root.edrv32_gpu_soc_tb.u_uart.send("2");
        $root.edrv32_gpu_soc_tb.u_uart.send(13);
        wait (load_ready);
        send_file("bios_rx.bin", 1);
        wait (load_pass && run_seen);
        while ($root.edrv32_gpu_soc_tb.u_ddr.peek(32'h003ff000) != 13) begin
            @(negedge $root.edrv32_gpu_soc_tb.clk_mem_i);
        end
        receive_phase = 1;
        send_file("rx.bin", 0);
        if (!rx_arp_seen) $fatal(1, "FAIL RX ARP not checked time=%0t", $time);
        checks_complete_o = 1;
        $root.edrv32_gpu_soc_tb.u_ddr.poke(32'h003ff004, 8'd1);
        $display("CHECK ST-13 ETH boot plus 64KiB RX, bad checksum and wrong port");
    end
endmodule
