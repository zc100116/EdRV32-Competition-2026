`timescale 1ns/1ps

module yolo_pll (
    input  wire clkin1,
    output wire clkout0,
    output wire lock
);
    assign clkout0 = clkin1;
    assign lock = 1'b1;
endmodule

module tb_yolo_conv_board;
    reg clk_27m_i = 1'b0;
    always #5 clk_27m_i = !clk_27m_i;
    reg reset_n_i = 1'b0;
    wire uart_tx_o;
    wire [7:0] led_o;
    reg [7:0] message [0:15];
    reg [7:0] telemetry [0:75];
    reg [31:0] mac_count;
    reg [31:0] stall_count;
    reg [31:0] pair_count;
    reg [31:0] tile_count;
    integer n;
    integer bit_index;

    edrv32_pango_200h_yolo_conv_top #(
        .CLK_HZ(1000000), .BAUD(500000), .TELEM_WINDOW_LOG2(11)
    ) dut (
        .clk_27m_i(clk_27m_i),
        .reset_n_i(reset_n_i),
        .uart_tx_o(uart_tx_o),
        .led_o(led_o)
    );

    task receive_byte;
        output [7:0] value;
        integer b;
        begin
            @(negedge uart_tx_o);
            repeat (3) @(posedge clk_27m_i);
            for (b = 0; b < 8; b = b + 1) begin
                value[b] = uart_tx_o;
                repeat (2) @(posedge clk_27m_i);
            end
            if (uart_tx_o !== 1'b1)
                $fatal(1, "UART stop bit missing");
        end
    endtask

    function [3:0] hex_digit;
        input [7:0] byte_value;
        begin
            if (byte_value >= "0" && byte_value <= "9")
                hex_digit = byte_value - "0";
            else if (byte_value >= "A" && byte_value <= "F")
                hex_digit = byte_value - "A" + 4'd10;
            else
                $fatal(1, "Invalid metric hex digit: %h", byte_value);
        end
    endfunction

    initial begin
        repeat (5) @(negedge clk_27m_i);
        reset_n_i = 1'b1;
        for (n = 0; n < 16; n = n + 1)
            receive_byte(message[n]);
        if ({message[0],message[1],message[2],message[3],
             message[4],message[5],message[6],message[7],
             message[8],message[9],message[10],message[11],
             message[12],message[13],message[14],message[15]}
            !== {"YOLO TILE PASS",8'h0d,8'h0a})
            $fatal(1, "Unexpected tile BIST UART message");
        if (led_o[7] || !led_o[2] || !led_o[0])
            $fatal(1, "Unexpected LED status %b", led_o);
        for (n = 0; n < 76; n = n + 1)
            receive_byte(telemetry[n]);
        if ({telemetry[0],telemetry[1],telemetry[2],telemetry[3],telemetry[4],
             telemetry[5],telemetry[6],telemetry[7],telemetry[8],telemetry[9]}
            !== "YMET MACU=" ||
            {telemetry[19],telemetry[20],telemetry[21],telemetry[22],telemetry[23]}
            !== "STAL=" ||
            {telemetry[33],telemetry[34],telemetry[35],telemetry[36],telemetry[37]}
            !== "PAIR=" ||
            {telemetry[47],telemetry[48],telemetry[49],telemetry[50],telemetry[51]}
            !== "TILE=" ||
            {telemetry[61],telemetry[62],telemetry[63],telemetry[64],telemetry[65]}
            !== "CSUM=" || telemetry[74] !== 8'h0d ||
            telemetry[75] !== 8'h0a)
            $fatal(1, "Unexpected YMET telemetry format");
        mac_count = 32'd0;
        stall_count = 32'd0;
        pair_count = 32'd0;
        tile_count = 32'd0;
        for (n = 0; n < 8; n = n + 1) begin
            mac_count = (mac_count << 4) | hex_digit(telemetry[10+n]);
            stall_count = (stall_count << 4) | hex_digit(telemetry[24+n]);
            pair_count = (pair_count << 4) | hex_digit(telemetry[38+n]);
            tile_count = (tile_count << 4) | hex_digit(telemetry[52+n]);
            bit_index = hex_digit(telemetry[66+n]);
        end
        if (mac_count == 0 || pair_count == 0 || tile_count == 0 ||
            pair_count < tile_count || mac_count < pair_count)
            $fatal(1, "Invalid YMET counters MAC=%0d STAL=%0d PAIR=%0d TILE=%0d",
                   mac_count, stall_count, pair_count, tile_count);
        $display("PASS YOLO board: INT32/INT8 BIST, pipelined quant, YMET counters");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "Board diagnostic timeout");
    end
endmodule
