// File: edrv32_board_b1_tb.sv
// Spec: board-plan B1-4/B1-5; edrv32-soc-spec 7.5.
// Description: Exercise the real board top through UART after PLL lock and key reset.
//              Check preload/menu and host-generated front-door download separately.
// Clock domain: 27 MHz board reference, 100 MHz clk_sys, asynchronous UART.
module edrv32_board_b1_tb;
    timeunit 1ns;
    timeprecision 1ps;
    /* verilator lint_off UNUSEDPARAM */
    `include "edrv32_soc_map.vh"
    /* verilator lint_on UNUSEDPARAM */
    reg clk = 0;
    reg rst_n = 0;
    reg key_n = 1;
    wire uart_rx;
    wire uart_tx;
    wire [3:0] led;
    int case_id = 0;
    int menus = 0;
    int bios_menus = 0;
    bit bios_seen = 0;
    bit download_ready = 0;
    bit download_complete = 0;
    bit download_bytes = 0;
    int app_messages = 0;
    int app_values = 0;
    bit info_pass = 0;
    bit isa_seen = 0;
    bit clock_seen = 0;
    bit [4:0] logo_seen = 0;
    wire advance_time;
    wire [63:0] next_time;
    wire released_key;

    always #18.5185 clk <= ~clk;

    edrv32_fpga_board_b1_top u_board (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .uart_rx_i(uart_rx),
        .uart_tx_o(uart_tx),
        .key_n_i(case_id == 0 ? released_key : key_n),
        .led_o(led)
    );

    uart_model u_uart (
        .tx_i(uart_tx),
        .rx_o(uart_rx)
    );

    edrv32_boot_window u_window (
        .clk_i(u_board.clk_sys_w),
        .rst_n_i(u_board.rst_sys_n_w),
        .enable_i(case_id != 2),
        .release_once_i(case_id == 0),
        .sample_i(u_board.u_sys_subsys.u_gpio.apb_psel_i &&
            u_board.u_sys_subsys.u_gpio.apb_penable_i &&
            !u_board.u_sys_subsys.u_gpio.apb_pwrite_i &&
            u_board.u_sys_subsys.u_gpio.apb_paddr_i == 12'h00c),
        .time_i(u_board.u_sys_subsys.u_clint.mtime_r),
        .clock_hz_i(EDRV32_CLK_SYS_HZ),
        .advance_o(advance_time),
        .time_o(next_time),
        .key_released_o(released_key)
    );

    initial begin : advance_boot_time
        forever begin
            @(negedge u_board.clk_sys_w);
            if (advance_time) begin
                force u_board.u_sys_subsys.u_clint.mtime_next_w = next_time;
                @(negedge u_board.clk_sys_w);
                release u_board.u_sys_subsys.u_clint.mtime_next_w;
            end
        end
    end

    initial begin
        void'($value$plusargs("CASE_ID=%d", case_id));
        key_n = case_id == 0;
        repeat (4) @(negedge clk);
        rst_n = 1;
        wait (u_board.pll_lock_w);
        @(posedge u_board.clk_sys_w);
        begin
            realtime previous_edge;
            previous_edge = $realtime;
            @(posedge u_board.clk_sys_w);
            if ($realtime - previous_edge != 10.0)
                $fatal(1, "FAIL PLL period expected=10ns actual=%0f time=%0t",
                    $realtime - previous_edge, $time);
        end
    end

    initial begin : receive
        string line_text;
        byte unsigned data;
        line_text = "";
        forever begin
            wait (u_uart.received.size() != 0);
            data = u_uart.received.pop_front();
            if (data == 10) begin
                $display("%s", line_text);
                $fflush();
                case (line_text)
                    "  EEEEEEE   DDDD    RRRRR   V   V   3333   2222 ": logo_seen[0] = 1;
                    "  E         D   D   R   R   V   V      3      2 ": logo_seen[1] = 1;
                    "  EEEE      D   D   RRRRR    V V    3333   2222 ": logo_seen[2] = 1;
                    "  E         D   D   R  R     V V       3   2    ": logo_seen[3] = 1;
                    "  EEEEEEE   DDDD    R    R    V     3333   2222 ": logo_seen[4] = 1;
                    "Menu: 1=CoreMark 2=Peripheral tests 3=System info": menus++;
                    "UART download ready": download_ready = 1;
                    "BIOS: EdRV32": bios_seen = 1;
                    "BIOS menu: 1=Program SRAM": bios_menus++;
                    "Program SRAM result: PASS, press reset to run": download_complete = 1;
                    "B1 UART application PASS": app_messages++;
                    "B1 data hi/lo: 7/7 bss: 0": app_values++;
                    "System info result: PASS": info_pass = 1;
                    "ISA: rv32im_zicsr_zifencei": isa_seen = 1;
                    default: begin end
                endcase
                if (line_text == $sformatf("CLK_SYS_HZ: %0d", EDRV32_CLK_SYS_HZ))
                    clock_seen = 1;
                if (line_text == $sformatf("Program SRAM bytes: %0d", download_length))
                    download_bytes = 1;
                line_text = "";
            end else if (data != 13) line_text = {line_text, string'(data)};
        end
    end

    task automatic reset_board;
        @(negedge clk);
        rst_n = 0;
        repeat (4) @(negedge clk);
        rst_n = 1;
    endtask

    int download_length = 0;

    initial begin : stimulus
        string wire_path;
        int file_handle;
        int value;
        wait (rst_n);
        if (case_id == 0) begin
            wait (menus == 1);
            u_uart.send("3");
            u_uart.send(8'h0d);
            wait (menus == 2);
            if (logo_seen != 5'b11111 || !clock_seen || !isa_seen || !info_pass)
                $fatal(1, "FAIL board menu logo=%b clock=%b ISA=%b info=%b time=%0t",
                    logo_seen, clock_seen, isa_seen, info_pass, $time);
        end else if (case_id == 2) begin
            wait (bios_menus == 1);
            if (!bios_seen || u_board.u_sys_subsys.u_clint.mtime_r <
                64'(EDRV32_CLK_SYS_HZ) / 10)
                $fatal(1, "FAIL real KEY1 window time=%0t", $time);
        end else begin
            if (!$value$plusargs("DOWNLOAD_WIRE=%s", wire_path))
                $fatal(1, "FAIL missing DOWNLOAD_WIRE");
            file_handle = $fopen(wire_path, "rb");
            if (file_handle == 0) $fatal(1, "FAIL open %s", wire_path);
            wait (bios_menus == 1);
            if (!bios_seen) $fatal(1, "FAIL missing BIOS banner time=%0t", $time);
            u_uart.send("1");
            u_uart.send(8'h0d);
            u_uart.send(8'h0a);
            wait (download_ready);
            for (int n = 0; n < 4; n++) begin
                value = $fgetc(file_handle);
                download_length |= value << (8*n);
                u_uart.send(8'(value));
            end
            value = $fgetc(file_handle);
            while (value != -1) begin
                u_uart.send(8'(value));
                value = $fgetc(file_handle);
            end
            $fclose(file_handle);
            wait (bios_menus == 2);
            if (!download_complete || !download_bytes || app_messages != 0 ||
                !clock_seen || logo_seen != 5'b11111)
                $fatal(1, "FAIL programming bytes=%b result=%b app=%0d time=%0t",
                    download_bytes, download_complete, app_messages, $time);
            key_n = 1;
            for (int run = 1; run <= 2; run++) begin
                reset_board();
                wait (u_board.u_sys_subsys.sim_exit_valid_o);
                if (u_board.u_sys_subsys.sim_exit_code_o != 0 || app_messages != run ||
                    app_values != run)
                    $fatal(1, "FAIL run=%0d exit=%h messages=%0d initial_values=%0d time=%0t",
                        run, u_board.u_sys_subsys.sim_exit_code_o, app_messages,
                        app_values, $time);
            end
        end
        if (u_uart.frame_errors != 0)
            $fatal(1, "FAIL UART framing errors=%0d time=%0t", u_uart.frame_errors, $time);
        $display("PASS board_b1 case=%0d", case_id);
        $finish;
    end

    initial begin
        #500000000;
        $fatal(1, "FAIL board_b1 timeout case=%0d menus=%0d time=%0t", case_id, menus, $time);
    end

    // LEDs are GPIO outputs; no software in these cases enables them.
    wire unused_led = ^led;
endmodule
