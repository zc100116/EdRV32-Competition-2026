`timescale 1ns/1ps

module tb_yolo_exec_board;
    reg clk_27m_i = 1'b0;
    reg ref_clk_p_i = 1'b0;
    reg reset_n_i = 1'b0;
    reg uart_rx_i = 1'b1;
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
    reg [7:0] load_reply_r [0:31];
    integer uart_received_r = 0;
    integer serial_bit, serial_index;

    edrv32_pango_200h_yolo_exec_top #(
        .ENABLE_BACKGROUND(1), .UART_BAUD(15000000)
    ) dut (
        .clk_27m_i(clk_27m_i),
        .ref_clk_p_i(ref_clk_p_i), .ref_clk_n_i(ref_clk_n_i),
        .reset_n_i(reset_n_i),
        .uart_rx_i(uart_rx_i),
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
                $fatal(1, "Exec UART start bit invalid");
            for (serial_bit = 0; serial_bit < 8; serial_bit = serial_bit+1) begin
                #66.667;
                if (uart_received_r < 223)
                    uart_bytes_r[uart_received_r][serial_bit] = uart_tx_w;
                else if (uart_received_r < 255)
                    load_reply_r[uart_received_r-223][serial_bit] =
                        uart_tx_w;
            end
            #66.667;
            if (uart_tx_w !== 1'b1)
                $fatal(1, "Exec UART stop bit invalid");
            uart_received_r = uart_received_r+1;
        end
    end

`ifdef TEST_SERIAL_LOAD
    task automatic send_uart(input [7:0] value);
        integer bit_no;
        begin
            uart_rx_i = 1'b0;
            #66.667;
            for (bit_no = 0; bit_no < 8; bit_no = bit_no+1) begin
                uart_rx_i = value[bit_no];
                #66.667;
            end
            uart_rx_i = 1'b1;
            #66.667;
        end
    endtask

    reg [7:0] transport_r [0:4095];
    integer transport_fd;
    integer transport_length;
    integer load_i;
`endif

`ifdef TEST_CORRUPT_RESULT
    initial begin
        wait (dut.u_test_system.cmd_index_r == 2'd3 &&
              dut.u_test_system.exec_done_w);
        #1;
        dut.u_ddr.u_ui_model.memory_r[512] =
            dut.u_ddr.u_ui_model.memory_r[512] ^ 256'd1;
    end
`endif

    initial begin
        repeat (8) @(negedge ref_clk_p_i);
        reset_n_i = 1'b1;
        wait (dut.bist_done_w);
        #1;
        if (
`ifndef TEST_CORRUPT_RESULT
            dut.bist_fail_w || dut.bist_error_flags_w != 5'd0 ||
`else
            !dut.bist_fail_w ||
            dut.bist_error_flags_w != 5'b10000 ||
            dut.first_bad_index_w != 16'd0 ||
            dut.first_bad_got_w != 32'h02020203 ||
            dut.first_bad_expected_w != 32'h02020202 ||
`endif
            (|dut.ddr_error_sync_r) ||
            dut.fabric_read_error_w || dut.fabric_write_error_w ||
            dut.ddr_adapter_protocol_error_w ||
            dut.mac_count_w != 32'd24 ||
            dut.read_count_w != 32'd76 ||
            dut.write_count_w != 32'd96 ||
            dut.weight_cycle_count_w == 32'd0 ||
            dut.feature_cycle_count_w == 32'd0 ||
            dut.run_cycle_count_w == 32'd0 ||
            dut.background_beat_count_w == 32'd0 ||
            dut.background_max_gap_w == 32'd0 ||
            dut.background_error_w)
            $fatal(1, "Exec board path failed flags=%h ddr=%h fabric=%0d/%0d MAC=%0d RD=%0d WR=%0d state=%0d",
                   dut.bist_error_flags_w, dut.ddr_error_sync_r,
                   dut.fabric_read_error_w, dut.fabric_write_error_w,
                   dut.mac_count_w, dut.read_count_w,
                   dut.write_count_w, dut.u_test_system.state_r);
        wait (uart_received_r == 223);
        $write("UART: ");
        for (serial_index = 0; serial_index < 223;
             serial_index = serial_index+1)
            $write("%c", uart_bytes_r[serial_index]);
        if (uart_bytes_r[0] != "Y" || uart_bytes_r[1] != "E" ||
            uart_bytes_r[2] != "X" || uart_bytes_r[3] != "E" ||
`ifndef TEST_CORRUPT_RESULT
            uart_bytes_r[5] != "P" || uart_bytes_r[8] != "S" ||
`else
            uart_bytes_r[5] != "F" || uart_bytes_r[8] != "L" ||
`endif
            uart_bytes_r[20] != "1" || uart_bytes_r[21] != "8" ||
            uart_bytes_r[32] != "4" || uart_bytes_r[33] != "C" ||
            uart_bytes_r[44] != "6" || uart_bytes_r[45] != "0" ||
            uart_bytes_r[59] != 8'h0d ||
            uart_bytes_r[60] != 8'h0a ||
            uart_bytes_r[126] != "Y" ||
            uart_bytes_r[127] != "P" ||
            uart_bytes_r[131] != "C" ||
            uart_bytes_r[144] != "P" ||
            uart_bytes_r[157] != "O" ||
            uart_bytes_r[221] != 8'h0d ||
            uart_bytes_r[222] != 8'h0a)
            $fatal(1, "Exec UART report format mismatch");
        $display("PASS YOLO shared exec board path: MAC=%0d RD=%0d WR=%0d BGREAD=%0d BGGAP=%0d CNV=%0d POL=%0d OTH=%0d",
                 dut.mac_count_w, dut.read_count_w,
                 dut.write_count_w, dut.background_beat_count_w,
                 dut.background_max_gap_w,
                 dut.weight_cycle_count_w,
                 dut.feature_cycle_count_w,
                 dut.run_cycle_count_w);
`ifdef TEST_SERIAL_LOAD
        transport_fd = $fopen("sim/build/yolo_uart_smoke.ymod", "rb");
        if (transport_fd == 0)
            $fatal(1, "run yolo_serial_pack.py before TEST_SERIAL_LOAD");
        transport_length = $fread(transport_r, transport_fd);
        $fclose(transport_fd);
        if (transport_length != 122)
            $fatal(1, "unexpected serial transport length %0d",
                   transport_length);
        for (load_i = 0; load_i < transport_length; load_i = load_i+1)
            send_uart(transport_r[load_i]);
        wait (uart_received_r >= 239);
        if (load_reply_r[0] !== "Y" || load_reply_r[1] !== "R" ||
            load_reply_r[2] !== "0" || load_reply_r[3] !== "0" ||
            load_reply_r[4] !== "0" || load_reply_r[5] !== "0" ||
            load_reply_r[6] !== 8'h0d || load_reply_r[7] !== 8'h0a ||
            load_reply_r[8] !== "Y" || load_reply_r[9] !== "D" ||
            load_reply_r[10] !== "0" || load_reply_r[11] !== "0" ||
            load_reply_r[12] !== "0" || load_reply_r[13] !== "1" ||
            load_reply_r[14] !== 8'h0d || load_reply_r[15] !== 8'h0a ||
            !dut.model_ready_w || dut.model_error_w ||
            dut.model_received_w != 32)
            $fatal(1, "UART loader final response failed");
        for (load_i = 0; load_i < 32; load_i = load_i+1)
            if (dut.u_ddr.u_ui_model.memory_r[768][load_i*8 +: 8] !==
                ((load_i*7+3) & 8'hff))
                $fatal(1, "UART DDR data mismatch byte=%0d", load_i);
        // Start a second YCFG region without resetting the board.
        transport_r[4] = 8'h20;
        for (load_i = 0; load_i < transport_length; load_i = load_i+1)
            send_uart(transport_r[load_i]);
        wait (uart_received_r >= 255);
        if (load_reply_r[16] !== "Y" || load_reply_r[17] !== "R" ||
            load_reply_r[18] !== "0" || load_reply_r[19] !== "0" ||
            load_reply_r[20] !== "0" || load_reply_r[21] !== "0" ||
            load_reply_r[22] !== 8'h0d || load_reply_r[23] !== 8'h0a ||
            load_reply_r[24] !== "Y" || load_reply_r[25] !== "D" ||
            load_reply_r[26] !== "0" || load_reply_r[27] !== "0" ||
            load_reply_r[28] !== "0" || load_reply_r[29] !== "1" ||
            load_reply_r[30] !== 8'h0d || load_reply_r[31] !== 8'h0a ||
            !dut.model_ready_w || dut.model_error_w ||
            dut.model_base_w != 32'h0000_6020 ||
            dut.model_received_w != 32)
            $fatal(1, "UART second region response failed");
        for (load_i = 0; load_i < 32; load_i = load_i+1)
            if (dut.u_ddr.u_ui_model.memory_r[769][load_i*8 +: 8] !==
                ((load_i*7+3) & 8'hff))
                $fatal(1, "UART second DDR region mismatch byte=%0d", load_i);
        $display("PASS YOLO UART two DDR regions without reset");
`endif
        $finish;
    end

    initial begin
        #6000000;
        $fatal(1, "Exec board timeout state=%0d init=%0d led=%h",
               dut.u_test_system.state_r,
               dut.ddr_init_done_w, led_w);
    end
endmodule
