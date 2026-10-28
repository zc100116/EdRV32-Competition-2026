// File: tb.sv
// Spec: eth 2.2, 2.6, 5.1-5.2.
// Description: MAC FCS/padding/IFG and receive error checks against a bit-serial polynomial model.
// Clock domain: 125 MHz test clock.
module tb;
    timeunit 1ns;
    timeprecision 1ps;
    logic clk = 0;
    always #4 clk = !clk;
    logic rst = 0;
    logic valid = 0;
    logic [8:0] data = 0;
    wire ready;
    wire [7:0] tx;
    wire en;
    wire er;
    wire done;
    logic corrupt = 0;
    logic rx_er = 0;
    wire rx_valid;
    wire [9:0] rx_data;
    wire unused_rx_bytes = &{1'b0, rx_data[7:0]};
    integer length = 0;
    integer count = 0;
    integer endings = 0;
    integer errors = 0;
    integer gap = 100;
    logic was_en = 0;
    logic [31:0] remainder;
    logic [7:0] captured[$];
    edrv32_eth_tx_front dut (
        .clk_i(clk), .rst_n_i(rst), .valid_i(valid), .ready_o(ready),
        .data_i(data), .data_o(tx), .valid_o(en), .error_o(er), .done_o(done)
    );
    edrv32_eth_rx_front receiver (
        .clk_i(clk), .rst_n_i(rst), .data_i(tx ^ (corrupt ? 8'h01 : 8'h00)),
        .valid_i(en), .error_i(rx_er), .valid_o(rx_valid), .data_o(rx_data)
    );
    // MSB-first polynomial and explicit bit reversal are independent of the DUT's reflected update.
    function automatic logic [31:0] update(input logic [31:0] old, input logic [7:0] octet);
        logic [31:0] r;
        r = old;
        for (integer b = 0; b < 8; b++) begin
            if (r[31] ^ octet[b]) r = (r << 1) ^ 32'h04c11db7;
            else r = r << 1;
        end
        return r;
    endfunction
    always @(posedge clk) begin
        if (rst) begin
            if (er) $fatal(1, "FAIL unexpected TX error");
            if (en) begin
                if (!was_en) begin
                    if (gap < 12) $fatal(1, "FAIL IFG %0d", gap);
                    count = 0;
                    captured.delete();
                end
                captured.push_back(tx);
                count++;
                gap = 0;
            end else begin
                gap++;
                if (was_en) begin
                    if (count != 8 + ((length < 60) ? 60 : length) + 4)
                        $fatal(1, "FAIL frame length actual=%0d length=%0d", count, length);
                    for (integer i = 0; i < 8; i++)
                        if (captured[i] != ((i == 7) ? 8'hd5 : 8'h55))
                            $fatal(1, "FAIL preamble byte %0d", i);
                    remainder = 32'hffffffff;
                    for (integer i = 8; i < count - 4; i++) begin
                        if (captured[i] != ((i - 8 < length) ? 8'((i-8)*37+11) : 8'd0))
                            $fatal(1, "FAIL data/pad byte %0d", i);
                        remainder = update(remainder, captured[i]);
                    end
                    for (integer b = 0; b < 32; b++)
                        if (captured[count-4+b/8][b%8] != ~remainder[31-b])
                            $fatal(1, "FAIL FCS bit %0d", b);
                end
            end
            was_en = en;
            if (rx_valid && rx_data[9]) begin
                endings++;
                if (rx_data[8]) errors++;
            end
        end
    end
    task automatic frame(input integer n, input integer bad);
        length = n;
        for (integer i = 0; i < n; i++) begin
            @(negedge clk);
            valid = 1;
            data = {i == n-1, 8'(i*37+11)};
            do @(posedge clk); while (!ready);
        end
        @(negedge clk); valid = 0;
        // Corrupt one data byte after the preamble on the receive path only.
        if (bad == 1) begin corrupt = 1; @(negedge clk); corrupt = 0; end
        if (bad == 2) begin rx_er = 1; @(negedge clk); rx_er = 0; end
        wait(done); @(negedge clk); repeat (20) @(negedge clk);
    endtask
    initial begin
        repeat(3) @(negedge clk); rst = 1;
        frame(1,0); frame(59,0); frame(60,0); frame(1074,1); frame(100,2);
        if (endings != 5 || errors != 2)
            $fatal(1, "FAIL receive endings=%0d errors=%0d", endings, errors);
        $display("PASS FCS generation/check, padding and IFG");
        $finish;
    end
    initial begin #100000; $fatal(1,"FAIL timeout"); end
endmodule
