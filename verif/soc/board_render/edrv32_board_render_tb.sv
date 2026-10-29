// File: edrv32_board_render_tb.sv
// Spec: Task B3-6; edrv32-soc-spec 5.3, 6.1, 7.4, 7.5; rnd-spec 2.6/4.
// Description: Real Boot ROM BIOS menu, then reset into the preloaded SRAM application.
//              DDR user-port model exercises RND writes and CPU uncached readback.
// Clock domains: 27 MHz board, 125 MHz DDR reference, modeled system/video PLLs.
module edrv32_board_render_tb;
    timeunit 1ns;
    timeprecision 1ps;
    /* verilator lint_off UNUSEDPARAM */
    `include "edrv32_soc_map.vh"
    /* verilator lint_on UNUSEDPARAM */
    reg clk = 0;
    reg ddr_clk = 0;
    reg rst_n = 0;
    reg key_n = 0;
    wire uart_rx;
    wire uart_tx;
    bit bios_menu = 0;
    bit application_pass = 0;
    bit rnd_irq = 0;
    bit cpu_irq = 0;
    wire advance_time;
    wire [63:0] next_time;
    wire unused_released;
    always #18.5185 clk <= ~clk;
    always #4 ddr_clk <= ~ddr_clk;
    wire [4:0] led_o;
    wire [2:0] tmds_data_p_o;
    wire [2:0] tmds_data_n_o;
    wire tmds_clk_p_o;
    wire tmds_clk_n_o;
    wire mem_cs_n_o;
    wire mem_rst_n_o;
    wire mem_ck_o;
    wire mem_ck_n_o;
    wire mem_cke_o;
    wire mem_ras_n_o;
    wire mem_cas_n_o;
    wire mem_we_n_o;
    wire mem_odt_o;
    wire [14:0] mem_a_o;
    wire [2:0] mem_ba_o;
    wire [3:0] mem_dqs_o;
    wire [3:0] mem_dqs_n_o;
    wire [31:0] mem_dq_o;
    wire [3:0] mem_dm_o;

    edrv32_fpga_board_render_top u_board (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .ddr_ref_clk_p_i(ddr_clk),
        .ddr_ref_clk_n_i(~ddr_clk),
        .uart_rx_i(uart_rx),
        .uart_tx_o(uart_tx),
        .key_n_i({3'b111, key_n}),
        .led_o(led_o),
        .tmds_data_p_o(tmds_data_p_o),
        .tmds_data_n_o(tmds_data_n_o),
        .tmds_clk_p_o(tmds_clk_p_o),
        .tmds_clk_n_o(tmds_clk_n_o),
        .mem_cs_n_o(mem_cs_n_o),
        .mem_rst_n_o(mem_rst_n_o),
        .mem_ck_o(mem_ck_o),
        .mem_ck_n_o(mem_ck_n_o),
        .mem_cke_o(mem_cke_o),
        .mem_ras_n_o(mem_ras_n_o),
        .mem_cas_n_o(mem_cas_n_o),
        .mem_we_n_o(mem_we_n_o),
        .mem_odt_o(mem_odt_o),
        .mem_a_o(mem_a_o),
        .mem_ba_o(mem_ba_o),
        .mem_dqs_o(mem_dqs_o),
        .mem_dqs_n_o(mem_dqs_n_o),
        .mem_dq_o(mem_dq_o),
        .mem_dm_o(mem_dm_o)
    );

    uart_model u_uart (
        .tx_i(uart_tx),
        .rx_o(uart_rx)
    );
    // B3-6 coordinator-approved simulation acceleration, not UART timing validation.
    // BAUD_DIV is Q4: 16 sys cycles per bit = 256, matching the 6.25 Mbaud peer.
    // UART timing is covered by board_b1 and hardware validation.
    initial begin
        @(negedge u_board.clk_sys_w);
        force u_board.u_sys.u_uart.baud_div_r = 24'd256;
        u_uart.baud = 6250000.0;
    end
    // Same boot-window acceleration used by board_b1; only CLINT time advances.
    edrv32_boot_window u_window (
        .clk_i(u_board.clk_sys_w),
        .rst_n_i(u_board.rst_sys_n_w),
        .enable_i(1'b1),
        .release_once_i(1'b0),
        .sample_i(u_board.u_sys.u_gpio.apb_psel_i &&
            u_board.u_sys.u_gpio.apb_penable_i &&
            !u_board.u_sys.u_gpio.apb_pwrite_i &&
            u_board.u_sys.u_gpio.apb_paddr_i == 12'h00c),
        .time_i(u_board.u_sys.u_clint.mtime_r),
        .clock_hz_i(EDRV32_CLK_SYS_HZ),
        .advance_o(advance_time),
        .time_o(next_time),
        .key_released_o(unused_released)
    );
    initial begin
        forever begin
            @(negedge u_board.clk_sys_w);
            if (advance_time) begin
                force u_board.u_sys.u_clint.mtime_next_w = next_time;
                @(negedge u_board.clk_sys_w);
                release u_board.u_sys.u_clint.mtime_next_w;
            end
        end
    end
    always @(posedge u_board.clk_sys_w) begin
        if (u_board.irq_src_w[11]) rnd_irq <= 1;
        if (u_board.irq_meip_w) cpu_irq <= 1;
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
                if (line_text == "BIOS menu: 1=Program SRAM") bios_menu = 1;
                if (line_text == "board_render IDs and 256 pixels PASS") application_pass = 1;
                line_text = "";
            end else if (data != 13) line_text = {line_text, string'(data)};
        end
    end
    initial begin
        repeat (4) @(negedge clk);
        rst_n = 1;
        wait (bios_menu);
        @(negedge clk);
        rst_n = 0;
        key_n = 1;
        repeat (4) @(negedge clk);
        rst_n = 1;
        wait (u_board.u_sys.sim_exit_valid_o);
        if (u_board.u_sys.sim_exit_code_o == 5)
            $fatal(1, "FAIL pixel[%0d] expected=ff2468ac actual=%h time=%0t",
                u_board.u_sys.u_sysctrl.scratch1_r, u_board.u_sys.u_sysctrl.scratch0_r, $time);
        if (u_board.u_sys.sim_exit_code_o != 0)
            $fatal(1, "FAIL SIM_EXIT expected=0 actual=%h time=%0t",
                u_board.u_sys.sim_exit_code_o, $time);
        if (!application_pass || !rnd_irq || !cpu_irq)
            $fatal(1, "FAIL app=%b RND_IRQ=%b MEIP=%b time=%0t",
                application_pass, rnd_irq, cpu_irq, $time);
        if (u_uart.frame_errors != 0)
            $fatal(1, "FAIL UART errors expected=0 actual=%0d time=%0t",
                u_uart.frame_errors, $time);
        $display("PASS board_render BIOS, IDs, PLIC11 DONE, DDR 64x4 readback");
        $finish;
    end
    initial begin
        #200000000;
        $fatal(1, "FAIL board_render timeout time=%0t", $time);
    end
    wire unused_pins = ^{led_o, tmds_data_p_o, tmds_data_n_o, tmds_clk_p_o, tmds_clk_n_o,
        mem_cs_n_o, mem_rst_n_o, mem_ck_o, mem_ck_n_o, mem_cke_o, mem_ras_n_o, mem_cas_n_o,
        mem_we_n_o, mem_odt_o, mem_a_o, mem_ba_o, mem_dqs_o, mem_dqs_n_o, mem_dq_o, mem_dm_o};
endmodule
