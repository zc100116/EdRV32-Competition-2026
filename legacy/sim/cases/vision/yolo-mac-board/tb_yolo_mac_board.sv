`timescale 1ns/1ps

module yolo_pll (
    input  wire clkin1,
    output wire clkout0,
    output wire lock
);
    assign clkout0 = clkin1;
    assign lock = 1'b1;
endmodule

module tb_yolo_mac_board;
    reg clk_27m_i = 1'b0;
    always #5 clk_27m_i = !clk_27m_i;
    reg reset_n_i = 1'b0;
    wire uart_tx_o;
    wire [7:0] led_o;
    reg [7:0] received [0:14];
    reg [7:0] telemetry [0:11];
    integer n;
    integer bit_index;

    edrv32_pango_200h_yolo_mac_top #(
        .CLK_HZ(1000000), .BAUD(100000)
    ) dut (
        .clk_27m_i(clk_27m_i),
        .reset_n_i(reset_n_i),
        .uart_tx_o(uart_tx_o),
        .led_o(led_o)
    );

    initial begin
        repeat (5) @(negedge clk_27m_i);
        reset_n_i = 1'b1;
        for (n = 0; n < 15; n = n + 1) begin
            @(negedge uart_tx_o);
            repeat (15) @(posedge clk_27m_i);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                received[n][bit_index] = uart_tx_o;
                repeat (10) @(posedge clk_27m_i);
            end
            if (uart_tx_o !== 1'b1)
                $fatal(1, "UART stop bit missing at byte %0d", n);
        end
        $display("UART message: %c%c%c%c%c%c%c%c%c%c%c%c%c%c%c",
                 received[0],received[1],received[2],received[3],received[4],
                 received[5],received[6],received[7],received[8],received[9],
                 received[10],received[11],received[12],received[13],received[14]);
        if ({received[0],received[1],received[2],received[3],received[4],
             received[5],received[6],received[7],received[8],received[9],
             received[10],received[11],received[12],received[13],received[14]}
            !== {"YOLO MAC PASS", 8'h0d, 8'h0a})
            $fatal(1, "Unexpected UART message");
        if (led_o[7] || !led_o[2] || !led_o[1] || !led_o[0])
            $fatal(1, "Unexpected LED status %b", led_o);
        for (n = 0; n < 12; n = n + 1) begin
            @(negedge uart_tx_o);
            repeat (15) @(posedge clk_27m_i);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                telemetry[n][bit_index] = uart_tx_o;
                repeat (10) @(posedge clk_27m_i);
            end
            if (uart_tx_o !== 1'b1)
                $fatal(1, "Telemetry stop bit missing at byte %0d", n);
        end
        if (telemetry[0] !== "C" || telemetry[1] !== "=" ||
            telemetry[10] !== 8'h0d || telemetry[11] !== 8'h0a)
            $fatal(1, "Unexpected checksum telemetry frame");
        for (n = 2; n < 10; n = n + 1)
            if (!((telemetry[n] >= "0" && telemetry[n] <= "9") ||
                  (telemetry[n] >= "A" && telemetry[n] <= "F")))
                $fatal(1, "Invalid checksum digit %0d: %h", n, telemetry[n]);
        $display("PASS YOLO MAC board diagnostic: YOLO MAC PASS, checksum telemetry, LED=%b", led_o);
        $finish;
    end

    initial begin
        #50000;
        $fatal(1, "Board diagnostic timeout");
    end
endmodule
