// File: edrv32_board_npu_program_tb.sv
// Spec: Task T-NPU4; edrv32-soc-spec 6.3, 7.4, 7.5; CLAUDE.md 9.2.
// Description: Backdoor the unchanged board ELF into DDR, then BIOS Run at 0x80000000.
//              CPU copies NPU data and maintains caches; stop on the first B-OP-01 line.
// Clock domains: 27 MHz board, 100 MHz system, 125 MHz DDR and 150 MHz NPU.
module edrv32_board_npu_program_tb;
    timeunit 1ns;
    timeprecision 1ps;
    /* verilator lint_off UNUSEDPARAM */
    `include "edrv32_soc_map.vh"
    /* verilator lint_on UNUSEDPARAM */
    reg clk = 0;
    reg ddr_clk = 0;
    reg eth_clk = 0;
    always #4 eth_clk <= ~eth_clk;
    tri eth_mdio;
    wire unused_rgmii_txc;
    wire [3:0] unused_rgmii_txd;
    wire unused_rgmii_tx_ctl;
    wire unused_eth_mdc;
    wire unused_eth_phy_rst_n;
    reg rst_n = 0;
    reg key_n = 0;
    wire uart_rx;
    wire uart_tx;
    wire advance_time;
    wire [63:0] next_time;
    wire unused_released;
    always #18.5185 clk <= ~clk;
    always #4 ddr_clk <= ~ddr_clk;
    wire [4:0] led_o;
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

    edrv32_fpga_board_npu_top u_board (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .ddr_ref_clk_p_i(ddr_clk),
        .ddr_ref_clk_n_i(~ddr_clk),
        .uart_rx_i(uart_rx),
        .uart_tx_o(uart_tx),
        .key_n_i({3'b111, key_n}),
        .led_o(led_o),
        .rgmii_rxc_i(eth_clk),
        .rgmii_rxd_i(4'b0),
        .rgmii_rx_ctl_i(1'b0),
        .rgmii_txc_o(unused_rgmii_txc),
        .rgmii_txd_o(unused_rgmii_txd),
        .rgmii_tx_ctl_o(unused_rgmii_tx_ctl),
        .eth_mdc_o(unused_eth_mdc),
        .eth_mdio_o(eth_mdio),
        .eth_phy_rst_n_o(unused_eth_phy_rst_n),
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

    initial begin : preload_ddr
        string path;
        if (!$value$plusargs("DDR_HEX=%s", path))
            $fatal(1, "FAIL missing +DDR_HEX");
        $readmemh(path, u_board.u_ddr3.u_user.memory_r);
    end

    uart_model u_uart (
        .tx_i(uart_tx),
        .rx_o(uart_rx)
    );
    // B3-10 coordinator-approved simulation acceleration, not UART timing validation.
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
    bit bios_menu = 0;
    bit run_prompt = 0;
    initial begin : receive
        string line_text;
        string prefix;
        byte unsigned data;
        prefix = "NPU B-OP-01-c16_32 ";
        line_text = "";
        forever begin
            wait (u_uart.received.size() != 0);
            data = u_uart.received.pop_front();
            if (data == 10) begin
                $display("%s", line_text);
                $fflush();
                if (line_text == "BIOS menu: 1=UART load 2=ETH load 3=Run 4=Baud")
                    bios_menu = 1;
                if (line_text == "Run address:") run_prompt = 1;
                if (line_text.len() >= prefix.len() &&
                    line_text.substr(0, prefix.len() - 1) == prefix) begin
                    if (line_text.substr(prefix.len(), prefix.len() + 3) == "FAIL")
                        $fatal(1, "FAIL board_npu_program B-OP-01 time=%0t", $time);
                    if (line_text.substr(prefix.len(), prefix.len() + 3) != "PASS")
                        $fatal(1, "FAIL unexpected B-OP-01 result time=%0t", $time);
                    $display("PASS board_npu_program stopped after B-OP-01 time=%0t", $time);
                    $finish;
                end
                line_text = "";
            end else if (data != 13) line_text = {line_text, string'(data)};
        end
    end

    task automatic send_text(input string value);
        for (int index = 0; index < value.len(); index++)
            u_uart.send(value[index]);
    endtask

    initial begin
        repeat (4) @(negedge clk);
        rst_n = 1;
        wait (bios_menu);
        send_text("3\r");
        wait (run_prompt);
        send_text("0x80000000\r");
    end
    initial begin
        #1000000000;
        $fatal(1, "FAIL board_npu_program timeout time=%0t", $time);
    end
    wire unused_pins = ^{led_o, eth_mdio,
        mem_cs_n_o, mem_rst_n_o, mem_ck_o, mem_ck_n_o, mem_cke_o, mem_ras_n_o, mem_cas_n_o,
        mem_we_n_o, mem_odt_o, mem_a_o, mem_ba_o, mem_dqs_o, mem_dqs_n_o, mem_dq_o, mem_dm_o};
endmodule
