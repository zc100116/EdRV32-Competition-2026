`timescale 1ns/1ps

module tb_vision_uart_command;

    reg clk_i = 1'b0;
    always #5 clk_i = !clk_i;
    reg rst_n_i = 1'b0;
    reg uart_rx_i = 1'b1;
    wire byte_valid_w;
    wire [7:0] byte_w;
    wire frame_error_w;
    wire command_valid_w;
    wire [2:0] command_kind_w;
    wire [15:0] command_value_w;
    integer checks_r = 0;
    integer command_count_r = 0;

    edrv32_uart_rx #(
        .CLK_HZ(1000000), .BAUD(100000)
    ) u_rx (
        .clk_i(clk_i), .rst_n_i(rst_n_i), .rx_i(uart_rx_i),
        .data_valid_o(byte_valid_w), .data_o(byte_w),
        .frame_error_o(frame_error_w)
    );

    edrv32_vision_uart_command #(
        .CLK_HZ(1000000), .GAP_MS(1)
    ) u_command (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .data_valid_i(byte_valid_w), .data_i(byte_w),
        .command_valid_o(command_valid_w),
        .command_kind_o(command_kind_w),
        .command_value_o(command_value_w)
    );

    always @(posedge clk_i) begin
        if (command_valid_w)
            command_count_r <= command_count_r + 1;
    end

    task send_byte;
        input [7:0] data_i;
        integer bit_index;
        begin
            @(negedge clk_i);
            uart_rx_i = 1'b0;
            repeat (10) @(negedge clk_i);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                uart_rx_i = data_i[bit_index];
                repeat (10) @(negedge clk_i);
            end
            uart_rx_i = 1'b1;
            repeat (10) @(negedge clk_i);
        end
    endtask

    task expect_command;
        input integer target_count_i;
        input [2:0] expected_kind_i;
        input [15:0] expected_value_i;
        begin
            wait (command_count_r == target_count_i);
            checks_r = checks_r + 1;
            if ((command_kind_w !== expected_kind_i) ||
                (command_value_w !== expected_value_i))
                $fatal(1, "command %0d got kind=%0d value=%0d",
                    target_count_i, command_kind_w, command_value_w);
        end
    endtask

    initial begin
        repeat (5) @(negedge clk_i);
        rst_n_i = 1'b1;
        send_byte("M"); send_byte("1"); send_byte("5"); send_byte(8'h0d);
        expect_command(1, 3'd0, 16'd15);
        send_byte(8'h0a);
        send_byte("p"); send_byte("7"); send_byte(8'h0a);
        expect_command(2, 3'd1, 16'd7);
        send_byte("m"); send_byte("3"); send_byte("2"); send_byte(8'h0a);
        repeat (20) @(negedge clk_i);
        if (command_count_r != 2)
            $fatal(1, "out-of-range command accepted");
        checks_r = checks_r + 1;
        send_byte("a");
        expect_command(3, 3'd2, 16'd0);
        send_byte(8'h0a);
        send_byte("S");
        expect_command(4, 3'd3, 16'd0);
        send_byte("M"); send_byte("0"); send_byte(8'h0a);
        expect_command(5, 3'd0, 16'd0);
        send_byte("X"); send_byte("9"); send_byte("6"); send_byte("0");
        send_byte(8'h0d);
        expect_command(6, 3'd5, 16'd960);
        send_byte("y"); send_byte("5"); send_byte("4"); send_byte("0");
        send_byte(8'h0a);
        expect_command(7, 3'd6, 16'd540);
        send_byte("R"); send_byte("1"); send_byte("3"); send_byte("5");
        send_byte(8'h0d);
        expect_command(8, 3'd4, 16'd135);
        send_byte("X"); send_byte("1"); send_byte("0"); send_byte("0");
        send_byte(8'h0d);
        repeat (20) @(negedge clk_i);
        if (command_count_r != 8)
            $fatal(1, "out-of-range image width accepted");
        checks_r = checks_r + 1;
        send_byte("X"); send_byte("6"); send_byte("5"); send_byte("0");
        expect_command(9, 3'd5, 16'd650);
        send_byte("Y"); send_byte("6"); send_byte("5"); send_byte("0");
        expect_command(10, 3'd6, 16'd650);
        send_byte("R"); send_byte("4"); send_byte("5");
        expect_command(11, 3'd4, 16'd45);
        send_byte("X"); send_byte("1"); send_byte("0"); send_byte("0");
        repeat (1200) @(negedge clk_i);
        if (command_count_r != 11)
            $fatal(1, "invalid command without newline was accepted");
        checks_r = checks_r + 1;
        send_byte("M"); send_byte("2"); send_byte("5");
        expect_command(12, 3'd0, 16'd25);
        $display("VISION_UART_COMMAND_PASS checks=%0d", checks_r);
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "UART command timeout");
    end

endmodule
