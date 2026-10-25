// File: uart_model.sv
// Spec: sys-subsys 2.6; sys-subsys-testplan UA-01/04/06.
// Description: 8N1 peer, configurable baud/deviation and bad stop-bit injection.
// Clock domain: asynchronous serial; time unit is ns.
module uart_model (
    input logic tx_i,
    output logic rx_o
);
    timeunit 1ns;
    timeprecision 1ps;
    real baud = 115200.0;
    real deviation = 0.0;
    byte unsigned received[$];
    int frame_errors = 0;
    int sent = 0;
    int captured = 0;

    function automatic realtime bit_time(

    );
        return 1.0e9 / (baud * (1.0 + deviation));
    endfunction

    task automatic send(
        input byte unsigned data,
        input bit frame_error = 0
    );
        realtime period;
        period = bit_time();
        rx_o = 0;
        #(period);
        for (int b = 0; b < 8; b++) begin
            rx_o = data[b];
            #(period);
        end
        rx_o = !frame_error;
        #(period);
        rx_o = 1;
        #(period);
        sent++;
    endtask

    task automatic expect_byte(
        input byte unsigned expected
    );
        byte unsigned actual;
        wait (received.size() != 0);
        actual = received.pop_front();
        if (actual != expected)
            $fatal(1, "FAIL UART expected=%02h actual=%02h time=%0t",
                    expected, actual, $time);
    endtask

    initial begin : receive_stream
        byte unsigned data;
        realtime period;
        rx_o = 1;
        forever begin
            @(negedge tx_i);
            period = bit_time();
            #(period / 2.0);
            if (!tx_i) begin
                for (int b = 0; b < 8; b++) begin
                    #(period);
                    data[b] = tx_i;
                end
                #(period);
                if (tx_i) begin
                    received.push_back(data);
                    captured++;
                end else frame_errors++;
                // Stop was sampled at its midpoint; resume searching before the next start.

            end
        end
    end
endmodule
