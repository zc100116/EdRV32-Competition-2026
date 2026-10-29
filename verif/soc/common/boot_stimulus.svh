// File: boot_stimulus.svh
// Spec: soc-testplan SC-01; SoC 7.5 steps 1-3a.
// Description: Check normal boot, enter BIOS with KEY1 and download through UART.
//              Reset without reloading SRAM and check the downloaded program runs.
// Clock domain: asynchronous UART and clk_sys reset.
    task automatic uart_expect_text(input string expected);
        int start;
        bit found;
        found = 0;
        while (!found) begin
            for (start = 0; start + expected.len() <= uart_log.len(); start++) begin
                if (uart_log.substr(start, start + expected.len() - 1) == expected)
                    found = 1;
            end
            if (!found) @(negedge clk_sys_i);
        end
    endtask

    task automatic check_boot_info;
        uart_expect_text("EdRV32 Boot ROM - UART 115200 8N1\r\n");
        uart_expect_text("CHIP_ID: ");
        uart_expect_text("CLK_SYS_HZ: 100000000\r\n");
        uart_expect_text("ROM bytes: 16384\r\n");
        uart_expect_text("SRAM bytes: 65536\r\n");
        uart_expect_text("I-cache bytes: 8192\r\n");
        uart_expect_text("D-cache bytes: 8192\r\n");
        uart_expect_text("MEM_READY: 1\r\n");
        uart_expect_text("Build commit: ");
        uart_expect_text("Compiler version: ");
    endtask

    task automatic button_reset(input bit pressed);
        @(negedge clk_sys_i);
        gpio_i[0] = !pressed;
        rst_n_i = 0;
        repeat (16) @(negedge clk_sys_i);
        rst_n_i = 1;
        uart_log = "";
    endtask

    initial begin : boot_case
        int fd;
        int length;
        int actual;
        byte unsigned image_bytes[$];
        string expected;
        #1;
        if (case_number == 1) begin
            accept_exit = 0;
            check_boot_info();
            uart_expect_text("Boot SRAM\r\n");
            @software_exit;
            button_reset(1);
            check_boot_info();
            uart_expect_text("BIOS: EdRV32\r\n");
            uart_expect_text("BIOS menu: 1=Program SRAM\r\n");
            u_uart.send("1");
            u_uart.send(8'h0d);
            uart_expect_text("UART download ready\r\n");
            fd = $fopen({data_dir, "/download.bin"}, "rb");
            if (fd == 0) $fatal(1, "download.bin open failed");
            actual = $fgetc(fd);
            while (actual != -1) begin
                image_bytes.push_back(8'(actual));
                actual = $fgetc(fd);
            end
            $fclose(fd);
            length = image_bytes.size();
            for (int i = 0; i < 4; i++) u_uart.send(8'(length >> (8*i)));
            foreach (image_bytes[i]) u_uart.send(image_bytes[i]);
            expected = $sformatf("Program SRAM bytes: %0d\r\n", length);
            uart_expect_text(expected);
            uart_expect_text("Program SRAM result: PASS, press reset to run\r\n");
            checks_complete = 1;
            accept_exit = 1;
            button_reset(0);
            check_boot_info();
            uart_expect_text("Boot SRAM\r\n");
        end
    end
