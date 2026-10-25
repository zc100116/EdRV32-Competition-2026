`timescale 1ns/1ps

module tb_yolo_ddr_board #(
`ifdef TEST_BG0
    parameter integer BACKGROUND = 0
`else
    parameter integer BACKGROUND = 1
`endif
`ifdef TEST_BENCH
    , parameter integer BENCHMARK = 1
`else
    , parameter integer BENCHMARK = 0
`endif
    , parameter [9:0] BENCH_TILE_PAIRS = 10'd4
);
    reg clk_27m_i = 1'b0;
    reg ref_clk_p_i = 1'b0;
    reg reset_n_i = 1'b0;
    always #18.518 clk_27m_i = !clk_27m_i;
    always #4 ref_clk_p_i = !ref_clk_p_i;
    wire ref_clk_n_i = !ref_clk_p_i;
    wire uart_tx_w;
    wire [7:0] led_w;
    wire mem_rst_n_w;
    wire mem_ck_w, mem_ck_n_w, mem_cke_w, mem_cs_n_w;
    wire mem_ras_n_w, mem_cas_n_w, mem_we_n_w, mem_odt_w;
    wire [14:0] mem_a_w;
    wire [2:0] mem_ba_w;
    wire [3:0] mem_dqs_w, mem_dqs_n_w, mem_dm_w;
    wire [31:0] mem_dq_w;
    reg [7:0] uart_bytes_r [0:222];
    integer uart_received_r = 0;
    integer serial_bit;
    integer serial_index;

    edrv32_pango_200h_yolo_ddr_top #(
        .ENABLE_BACKGROUND(BACKGROUND),
        .BENCHMARK_MODE(BENCHMARK),
        .BENCH_TILE_PAIRS(BENCH_TILE_PAIRS),
        .UART_BAUD(15000000)
    ) dut (
        .clk_27m_i(clk_27m_i),
        .ref_clk_p_i(ref_clk_p_i), .ref_clk_n_i(ref_clk_n_i),
        .reset_n_i(reset_n_i),
        .uart_tx_o(uart_tx_w), .led_o(led_w),
        .mem_rst_n_o(mem_rst_n_w),
        .mem_ck_o(mem_ck_w), .mem_ck_n_o(mem_ck_n_w),
        .mem_cke_o(mem_cke_w), .mem_cs_n_o(mem_cs_n_w),
        .mem_ras_n_o(mem_ras_n_w),
        .mem_cas_n_o(mem_cas_n_w),
        .mem_we_n_o(mem_we_n_w),
        .mem_odt_o(mem_odt_w),
        .mem_a_o(mem_a_w), .mem_ba_o(mem_ba_w),
        .mem_dqs_io(mem_dqs_w), .mem_dqs_n_io(mem_dqs_n_w),
        .mem_dq_io(mem_dq_w), .mem_dm_o(mem_dm_w)
    );

    initial begin
        forever begin
            @(negedge uart_tx_w);
            #33.333;
            if (uart_tx_w !== 1'b0)
                $fatal(1, "UART start bit invalid");
            for (serial_bit = 0; serial_bit < 8; serial_bit = serial_bit+1) begin
                #66.667;
                if (uart_received_r < 223)
                    uart_bytes_r[uart_received_r][serial_bit] = uart_tx_w;
            end
            #66.667;
            if (uart_tx_w !== 1'b1)
                $fatal(1, "UART stop bit invalid");
            uart_received_r = uart_received_r+1;
        end
    end

`ifdef TEST_CORRUPT_RESULT
    initial begin
        wait (dut.u_test_system.layer_done_w);
        #1;
        dut.u_ddr.u_ui_model.memory_r[4096] =
            dut.u_ddr.u_ui_model.memory_r[4096] ^ 256'd1;
    end
`endif

    initial begin
        repeat (8) @(negedge ref_clk_p_i);
        reset_n_i = 1'b1;
        wait (dut.bist_done_w);
        #1;
        if (
`ifndef TEST_CORRUPT_RESULT
            dut.bist_fail_w ||
`else
            !dut.bist_fail_w ||
            dut.bist_error_flags_w != 5'b10000 ||
            dut.first_bad_index_w != 16'd0 ||
            dut.first_bad_got_w !=
                (BENCHMARK ? 32'h0404_0405 : 32'h0a0a_0a0b) ||
            dut.first_bad_expected_w !=
                (BENCHMARK ? 32'h0404_0404 : 32'h0a0a_0a0a) ||
`endif
`ifdef TEST_PHY_POST_ERROR
            dut.ddr_error_sync_r != 4'b0001 ||
`else
            (|dut.ddr_error_sync_r) ||
`endif
            dut.fabric_read_error_w || dut.fabric_write_error_w ||
            dut.ddr_adapter_protocol_error_w ||
            dut.mac_count_w != (BENCHMARK ? 32'd18432 : 32'd216) ||
            dut.read_count_w != (BENCHMARK ? 32'd1168 : 32'd156) ||
            dut.write_count_w != (BENCHMARK ? 32'd2048 : 32'd24) ||
            dut.weight_cycle_count_w == 32'd0 ||
            dut.feature_cycle_count_w == 32'd0 ||
            dut.run_cycle_count_w == 32'd0 ||
            (BACKGROUND != 0 && dut.background_max_gap_w == 32'd0) ||
            (BACKGROUND == 0 && dut.background_max_gap_w != 32'd0) ||
            dut.background_error_w ||
            (BACKGROUND != 0 && dut.background_beat_count_w == 32'd0) ||
            (BACKGROUND == 0 && dut.background_beat_count_w != 32'd0))
            $fatal(1, "Board path failed: fail=%0d flags=%h loc=%h got=%h exp=%h ddr=%0d fabric=%0d/%0d adapter=%0d MAC=%0d RD=%0d WR=%0d state=%0d",
                   dut.bist_fail_w, dut.bist_error_flags_w,
                   dut.first_bad_index_w, dut.first_bad_got_w,
                   dut.first_bad_expected_w, dut.ddr_error_sync_r,
                   dut.fabric_read_error_w, dut.fabric_write_error_w,
                   dut.ddr_adapter_protocol_error_w,
                   dut.mac_count_w, dut.read_count_w,
                   dut.write_count_w, dut.u_test_system.state_r);
        wait (uart_received_r == 223);
        $write("UART: ");
        for (serial_index = 0; serial_index < 223;
             serial_index = serial_index+1)
            $write("%c", uart_bytes_r[serial_index]);
        if (uart_bytes_r[0] != "Y" || uart_bytes_r[1] != "D" ||
            uart_bytes_r[2] != "D" || uart_bytes_r[3] != "R" ||
`ifndef TEST_CORRUPT_RESULT
`ifndef TEST_PHY_POST_ERROR
            uart_bytes_r[5] != "P" || uart_bytes_r[8] != "S" ||
`else
            uart_bytes_r[5] != "F" || uart_bytes_r[8] != "L" ||
`endif
`else
            uart_bytes_r[5] != "F" || uart_bytes_r[8] != "L" ||
`endif
            uart_bytes_r[14] != "0" ||
            (!BENCHMARK && (uart_bytes_r[20] != "D" ||
                           uart_bytes_r[21] != "8" ||
                           uart_bytes_r[32] != "9" ||
                           uart_bytes_r[33] != "C" ||
                           uart_bytes_r[44] != "1" ||
                           uart_bytes_r[45] != "8")) ||
            (BENCHMARK && (uart_bytes_r[18] != "4" ||
                          uart_bytes_r[19] != "8" ||
                          uart_bytes_r[20] != "0" ||
                          uart_bytes_r[21] != "0" ||
                          uart_bytes_r[31] != "4" ||
                          uart_bytes_r[32] != "9" ||
                          uart_bytes_r[33] != "0" ||
                          uart_bytes_r[44] != "0" ||
                          uart_bytes_r[45] != "0")) ||
            uart_bytes_r[59] != 8'h0d ||
            uart_bytes_r[60] != 8'h0a ||
            uart_bytes_r[61] != "Y" || uart_bytes_r[62] != "D" ||
            uart_bytes_r[63] != "B" || uart_bytes_r[64] != "G" ||
            uart_bytes_r[70] != "0" ||
`ifndef TEST_CORRUPT_RESULT
`ifndef TEST_PHY_POST_ERROR
            uart_bytes_r[77] != "0" ||
`else
            uart_bytes_r[76] != "2" || uart_bytes_r[77] != "0" ||
`endif
`else
            uart_bytes_r[76] != "1" || uart_bytes_r[77] != "0" ||
`endif
            uart_bytes_r[118] != "P" ||
            uart_bytes_r[121] != "=" ||
`ifdef TEST_PHY_TRANSIENT
            uart_bytes_r[122] != "0" ||
            uart_bytes_r[123] != "3" ||
            dut.phy_status_sync_r != 6'b000011 ||
`elsif TEST_PHY_POST_ERROR
            uart_bytes_r[122] != "2" ||
            uart_bytes_r[123] != "A" ||
            dut.phy_status_sync_r != 6'b101010 ||
`else
            uart_bytes_r[122] != "0" ||
            uart_bytes_r[123] != "0" ||
`endif
            uart_bytes_r[124] != 8'h0d ||
            uart_bytes_r[125] != 8'h0a ||
            uart_bytes_r[126] != "Y" ||
            uart_bytes_r[127] != "P" ||
            uart_bytes_r[128] != "R" ||
            uart_bytes_r[129] != "F" ||
            uart_bytes_r[208] != " " ||
            uart_bytes_r[209] != "G" ||
            uart_bytes_r[221] != 8'h0d ||
            uart_bytes_r[222] != 8'h0a)
            $fatal(1, "YDDR UART line mismatch: verdict=%c%c err=%c%c phy=%c%c raw_phy=%h raw_err=%h",
                   uart_bytes_r[5], uart_bytes_r[8],
                   uart_bytes_r[76], uart_bytes_r[77],
                   uart_bytes_r[122], uart_bytes_r[123],
                   dut.phy_status_sync_r, dut.ddr_error_sync_r);
        $display("PASS YOLO DDR full path BG=%0d BENCH=%0d: 150-MHz CDC -> 125-MHz 256-bit interconnect -> adapter -> DDR UI model; MAC=%0d RD=%0d WR=%0d BGREAD=%0d BGGAP=%0d CYC=%0d WGT=%0d FET=%0d RUN=%0d",
                 BACKGROUND, BENCHMARK,
                 dut.mac_count_w, dut.read_count_w,
                 dut.write_count_w, dut.background_beat_count_w,
                 dut.background_max_gap_w,
                 dut.cycle_count_w, dut.weight_cycle_count_w,
                 dut.feature_cycle_count_w, dut.run_cycle_count_w);
        $finish;
    end
    initial begin
        #5000000;
        $fatal(1, "YOLO DDR board path timeout: state=%0d init=%0d led=%h",
               dut.u_test_system.state_r,
               dut.ddr_init_done_w, led_w);
    end
endmodule
