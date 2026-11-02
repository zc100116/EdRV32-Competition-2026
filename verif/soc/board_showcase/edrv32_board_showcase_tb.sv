// File: edrv32_board_showcase_tb.sv
// Spec: Task B3-6; edrv32-soc-spec 5.3, 6.1, 7.4, 7.5; rnd-spec 2.6/4.
// Description: Real Boot ROM BIOS menu, then reset into the preloaded SRAM application.
//              DDR user-port model exercises RND writes and CPU uncached readback.
// Clock domains: 27 MHz board, 125 MHz DDR reference, modeled system/video PLLs.
module edrv32_board_showcase_tb;
    timeunit 1ns;
    timeprecision 1ps;
    /* verilator lint_off UNUSEDPARAM */
    `include "edrv32_soc_map.vh"
    `include "regs/edrv32_eth_regs.vh"
    /* verilator lint_on UNUSEDPARAM */
    reg clk = 0;
    reg ddr_clk = 0;
    reg rst_n = 0;
    reg key_n = 1;
    wire uart_rx;
    wire uart_tx;
    reg [31:0] rendered_base;
    reg [15:0] rendered_pixel;
    integer launcher_count = 0;
    bit first_frame = 0;
    bit application_entered = 0;
    bit nes_entered = 0;
    reg [31:0] nes_base;
    reg [31:0] nes_bytes;
    reg [31:0] last_surface;
    integer nes_switches = 0;
    initial begin
        if (!$value$plusargs("NES_BASE=%h", nes_base)) $fatal(1, "NES_BASE required");
        if (!$value$plusargs("NES_BYTES=%h", nes_bytes)) $fatal(1, "NES_BYTES required");
    end
    bit rnd_irq = 0;
    bit cpu_irq = 0;

    always #18.5185 clk <= ~clk;
    always #4 ddr_clk <= ~ddr_clk;
    reg eth_clk = 0;
    always #4 eth_clk <= ~eth_clk;
    tri eth_mdio;
    wire rgmii_txc;
    wire [3:0] rgmii_txd;
    wire rgmii_tx_ctl;
    wire eth_mdc;
    wire eth_phy_rst_n;
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
        .rgmii_rxc_i(eth_clk),
        .rgmii_rxd_i(4'b0),
        .rgmii_rx_ctl_i(1'b0),
        .rgmii_txc_o(rgmii_txc),
        .rgmii_txd_o(rgmii_txd),
        .rgmii_tx_ctl_o(rgmii_tx_ctl),
        .eth_mdc_o(eth_mdc),
        .eth_mdio_o(eth_mdio),
        .eth_phy_rst_n_o(eth_phy_rst_n),
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
    always @(posedge u_board.clk_sys_w) begin
        if (u_board.irq_src_w[11]) rnd_irq <= 1;
        if (u_board.irq_meip_w) cpu_irq <= 1;
        last_surface <= u_board.u_disp.u_regs.cur_base_r;
        if (u_board.u_disp.u_regs.cur_base_r != last_surface &&
            last_surface >= nes_base && last_surface < nes_base + nes_bytes &&
            u_board.u_disp.u_regs.cur_base_r >= nes_base &&
            u_board.u_disp.u_regs.cur_base_r < nes_base + nes_bytes)
            nes_switches <= nes_switches + 1;
    end
    // SoC 7.3: producers may only write a released Surface, including after
    // stopping an app with an outstanding asynchronous GUI flush.
    always @(posedge u_board.clk_mem_w) begin
        if (u_board.rst_mem_n_w && u_board.p4_awvalid_w && u_board.p4_awready_w &&
            u_board.u_disp.busy_w && u_board.u_disp.u_regs.cur_layer_ctrl_r[0] &&
            u_board.p4_awaddr_w >= u_board.u_disp.u_regs.cur_base_r &&
            u_board.p4_awaddr_w < u_board.u_disp.u_regs.cur_base_r + 32'd1843200)
            $fatal(1, "FAIL RND writes owned front address=%h front=%h time=%0t",
                   u_board.p4_awaddr_w, u_board.u_disp.u_regs.cur_base_r, $time);
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
                if (line_text == "showcase launcher") launcher_count++;
                if (line_text == "showcase first frame") first_frame = 1;
                if (line_text == "showcase enter 系统状态") application_entered = 1;
                if (line_text == "showcase enter NES 游戏") nes_entered = 1;
                if (line_text.substr(0, 11) == "showcase CPU" ||
                    line_text.substr(0, 3) == "RND " || line_text.substr(0, 4) == "DISP ")
                    $fatal(1, "FAIL firmware error %s time=%0t", line_text, $time);
                line_text = "";
            end else if (data != 13) line_text = {line_text, string'(data)};
        end
    end
    reg [63:0] advanced_time;
    reg [63:0] phy_delay_ticks;
    // PHY timing itself is outside this application test. The PHY_CTRL write
    // arms an advance; two low-word reads let software first form its deadline.
    initial begin : accelerate_phy_waits
        for (integer phase = 0; phase < 2; phase = phase + 1) begin
            do @(posedge u_board.clk_mem_w);
            while (!(u_board.u_eth.apb_psel_i && u_board.u_eth.apb_penable_i &&
                u_board.u_eth.apb_pready_o && u_board.u_eth.apb_pwrite_i &&
                u_board.u_eth.apb_paddr_i == EDRV32_ETH_PHY_CTRL_OFFSET[11:0]));
            phy_delay_ticks = u_board.u_eth.apb_pwdata_i[0] ?
                {32'b0, EDRV32_CLK_SYS_HZ} / 100 : {32'b0, EDRV32_CLK_SYS_HZ} / 10;
            for (integer reads = 0; reads < 2; reads = reads + 1) begin
                do @(posedge u_board.clk_sys_w);
                while (!(u_board.u_sys.u_clint.axi_arvalid_i &&
                    u_board.u_sys.u_clint.axi_arready_o &&
                    u_board.u_sys.u_clint.axi_araddr_i[15:0] == 16'hbff8));
            end
            @(negedge u_board.clk_sys_w);
            advanced_time = u_board.u_sys.u_clint.mtime_r + phy_delay_ticks;
            force u_board.u_sys.u_clint.mtime_next_w = advanced_time;
            @(negedge u_board.clk_sys_w);
            release u_board.u_sys.u_clint.mtime_next_w;
            $display("board_showcase PHY_CTRL phase=%0d CLINT advance=%0d ticks time=%0t",
                     phase, phy_delay_ticks, $time);
            $fflush();
        end
    end
    task automatic controller(input reg [15:0] keys);
        u_uart.send(8'h1b);
        u_uart.send(8'h56);
        u_uart.send(keys[7:0]);
        u_uart.send(keys[15:8]);
        repeat (6) u_uart.send(0);
        #2000000;
    endtask
    initial begin
        repeat (4) @(negedge clk);
        rst_n = 1;
        wait (first_frame && launcher_count == 1);
        if (!rnd_irq || !cpu_irq)
            $fatal(1, "FAIL RND=%b MEIP=%b time=%0t", rnd_irq, cpu_irq, $time);
        rendered_base = u_board.u_disp.u_regs.cur_base_r;
        rendered_pixel = {u_board.u_ddr3.u_user.memory_r[rendered_base + 1],
                          u_board.u_ddr3.u_user.memory_r[rendered_base]};
        if (rendered_pixel != 16'h08a4)
            $fatal(1, "FAIL launcher pixel expected=08a4 actual=%h base=%h time=%0t",
                   rendered_pixel, rendered_base, $time);
        controller(16'h0100);
        controller(0);
        wait (nes_entered);
        wait (u_board.u_disp.u_regs.cur_base_r != rendered_base);
        controller(16'h0100);
        controller(0);
        wait (nes_switches >= 3);
        controller(16'h0200);
        controller(0);
        wait (u_board.u_disp.u_regs.cur_base_r < nes_base ||
              u_board.u_disp.u_regs.cur_base_r >= nes_base + nes_bytes);
        controller(16'h0200);
        controller(0);
        wait (launcher_count == 2);
        repeat (4) begin
            controller(16'h0800);
            controller(0);
        end
        controller(16'h0100);
        controller(0);
        wait (application_entered);
        controller(16'h0200);
        controller(0);
        wait (launcher_count == 3);
        if (u_uart.frame_errors != 0)
            $fatal(1, "FAIL UART errors=%0d time=%0t", u_uart.frame_errors, $time);
        $display("PASS board_showcase launcher pixel, app enter/exit, NES %0d flips and exit",
                 nes_switches);
        $finish;
    end
    initial begin
        forever begin
            #10000000;
            $display("board_showcase progress time=%0t PC=%h mtime=%0d",
                     $time, u_board.u_cpu.u_core.trace_pc_w,
                     u_board.u_sys.u_clint.mtime_r);
            $fflush();
        end
    end
    initial begin
        #2000000000;
        $fatal(1, "FAIL board_showcase timeout time=%0t", $time);
    end
    wire unused_pins = ^{rgmii_txc, rgmii_txd, rgmii_tx_ctl,
        eth_mdc, eth_mdio, eth_phy_rst_n, led_o, tmds_data_p_o, tmds_data_n_o, tmds_clk_p_o, tmds_clk_n_o,
        mem_cs_n_o, mem_rst_n_o, mem_ck_o, mem_ck_n_o, mem_cke_o, mem_ras_n_o, mem_cas_n_o,
        mem_we_n_o, mem_odt_o, mem_a_o, mem_ba_o, mem_dqs_o, mem_dqs_n_o, mem_dq_o, mem_dm_o};
endmodule
