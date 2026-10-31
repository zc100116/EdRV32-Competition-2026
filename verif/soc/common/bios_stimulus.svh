// File: bios_stimulus.svh
// Spec: edrv32-soc-spec 7.5(3a); T-BIOS2 acceptance.
// Description: Drive real UART/ETH sessions, including one missing packet and full resend.
// Clock domain: UART asynchronous; Ethernet RX/TX; clk_sys observations.
    bit bios_menu_seen = 0;
    bit bios_ready_seen = 0;
    bit bios_eth_ready = 0;
    bit bios_bytes_failed = 0;
    bit bios_run_seen = 0;
    int bios_retry = 0;
    int bios_uart = 0;
    string bios_line_text = "";

    task automatic bios_observe(input byte unsigned value);
        if (value == 10) begin
            case (bios_line_text)
                "BIOS menu: 1=UART load 2=ETH load 3=Run 4=Baud": bios_menu_seen = 1;
                "UART load ready": bios_ready_seen = 1;
                "ETH load ready 192.168.1.10:5000": bios_eth_ready = 1;
                "BIOS application PASS": checks_complete = bios_run_seen;
                default: begin end
            endcase
            if (bios_line_text.len() >= 29 &&
                bios_line_text.substr(0, 28) == "ETH load result: FAIL bytes w")
                bios_bytes_failed = 1;
            if (bios_line_text.len() == 15 && bios_line_text.substr(0, 6) == "Run: 0x")
                bios_run_seen = 1;
            bios_line_text = "";
        end else if (value != 13) bios_line_text = {bios_line_text, string'(value)};
    endtask

    task automatic bios_send_frames(input bit omit_first);
        int fd;
        int value;
        int length;
        int index;
        byte unsigned frame[$];
        fd = $fopen({data_dir, "/bios_rx.bin"}, "rb");
        if (fd == 0) $fatal(1, "FAIL open BIOS Ethernet input");
        index = 0;
        value = $fgetc(fd);
        while (value != -1) begin
            length = value;
            for (int i = 1; i < 4; i++) length |= $fgetc(fd) << (8*i);
            frame.delete();
            repeat (length) frame.push_back(8'($fgetc(fd)));
            if (!omit_first || index != 0) u_eth.send_frame(frame);
            index++;
            value = $fgetc(fd);
        end
        $fclose(fd);
    endtask

    initial begin : bios_session_stimulus
        int fd;
        int value;
        #1;
        if (case_number == 18) begin
            void'($value$plusargs("BIOS_RETRY=%d", bios_retry));
            void'($value$plusargs("BIOS_UART=%d", bios_uart));
            gpio_i[0] = 0;
            wait (bios_menu_seen);
            if (bios_uart != 0) begin
                u_uart.send("1");
                u_uart.send(13);
                wait (bios_ready_seen);
                fd = $fopen({data_dir, "/bios_uart.bin"}, "rb");
                if (fd == 0) $fatal(1, "FAIL open BIOS UART input");
                value = $fgetc(fd);
                while (value != -1) begin
                    u_uart.send(8'(value));
                    value = $fgetc(fd);
                end
                $fclose(fd);
            end else begin
                u_uart.send("2");
                u_uart.send(13);
                wait (bios_eth_ready);
                bios_send_frames(bios_retry != 0);
                if (bios_retry != 0) begin
                    wait (bios_bytes_failed);
                    bios_send_frames(0);
                end
            end
        end
    end

    // CASE18 coordinator-approved acceleration; B1 covers physical baud and 100 ms timing.
    reg [63:0] bios_next_time;
    initial begin : bios_accelerate
        #1;
        if (case_number == 18) begin
            force u_dut.u_sys.u_uart.baud_div_r = 24'd256;
            u_uart.baud = 6250000.0;
            forever begin
                @(negedge clk_sys_i);
                if (u_dut.u_sys.u_clint.axi_arvalid_i &&
                    u_dut.u_sys.u_clint.axi_arready_o &&
                    u_dut.u_sys.u_clint.axi_araddr_i[15:3] == 13'h17ff) begin
                    bios_next_time = u_dut.u_sys.u_clint.mtime_r + 10000;
                    force u_dut.u_sys.u_clint.mtime_next_w = bios_next_time;
                    @(negedge clk_sys_i);
                    release u_dut.u_sys.u_clint.mtime_next_w;
                end
            end
        end
    end
