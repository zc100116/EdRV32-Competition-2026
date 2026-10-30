// File: tb.sv
// Spec: eth 3, 5.1-5.2; Task E-F1.
// Description: Check one-cycle RX/TX IO staging, DDR nibble/control alignment and
//              completion with the final FCS byte at the ODDR input.
// Clock domain: clk_eth (125 MHz).
module tb;
    timeunit 1ns;
    timeprecision 1ps;
    logic clk = 0;
    always #4 clk = !clk;
    logic rst = 0;
    logic [3:0] rxd = 0;
    logic rx_ctl = 0;
    wire eth_clk;
    wire [7:0] rx_data;
    wire rx_dv;
    wire rx_er;
    logic front_mode = 0;
    logic [7:0] tx_data = 0;
    logic tx_en = 0;
    logic tx_er = 0;
    logic front_valid = 0;
    logic [8:0] front_data = 0;
    wire front_ready;
    wire [7:0] front_tx_data;
    wire front_tx_en;
    wire front_tx_er;
    wire front_done;
    wire txc;
    wire [3:0] txd;
    wire tx_ctl;
    wire [7:0] mac_data = front_mode ? front_tx_data : tx_data;
    wire mac_en = front_mode ? front_tx_en : tx_en;
    wire mac_er = front_mode ? front_tx_er : tx_er;
    logic [7:0] expected_frame[$];
    integer frame_index = 0;
    integer completed = 0;
    integer checked = 0;

    edrv32_eth_tx_front front (
        .clk_i(eth_clk),
        .rst_n_i(rst),
        .valid_i(front_valid),
        .ready_o(front_ready),
        .data_i(front_data),
        .data_o(front_tx_data),
        .valid_o(front_tx_en),
        .error_o(front_tx_er),
        .done_o(front_done)
    );
    edrv32_fpga_rgmii dut (
        .rgmii_rxc_i(clk),
        .rgmii_rxd_i(rxd),
        .rgmii_rx_ctl_i(rx_ctl),
        .clk_eth_o(eth_clk),
        .eth_rxd_o(rx_data),
        .eth_rx_dv_o(rx_dv),
        .eth_rx_er_o(rx_er),
        .eth_txd_i(mac_data),
        .eth_tx_en_i(mac_en),
        .eth_tx_er_i(mac_er),
        .rgmii_txc_o(txc),
        .rgmii_txd_o(txd),
        .rgmii_tx_ctl_o(tx_ctl)
    );

    // Sample before NBA: the ordinary stage must capture the old IDDR/MAC values.
    always @(posedge eth_clk) begin : check_cycle
        logic [9:0] expected_rx;
        logic [9:0] expected_tx;
        logic [4:0] expected_rise;
        logic [4:0] expected_fall;
        expected_rx = {dut.rx_rise_w[4], dut.rx_rise_w[4] ^ dut.rx_fall_w[4],
                       dut.rx_fall_w[3:0], dut.rx_rise_w[3:0]};
        expected_tx = {mac_en, mac_er, mac_data};
        expected_rise = dut.tx_rise_w[4:0];
        expected_fall = dut.tx_fall_w[4:0];
        if (rst && front_mode) begin
            if (front_done !== (dut.tx_rise_w[4] && frame_index == 71))
                $fatal(1, "FAIL done/FCS alignment byte=%0d done=%b at %0t",
                       frame_index, front_done, $time);
            if (dut.tx_rise_w[4]) begin
                if ({dut.tx_fall_w[3:0], dut.tx_rise_w[3:0]} !== expected_frame[frame_index])
                    $fatal(1, "FAIL ODDR input byte=%0d expected=%h actual=%h at %0t",
                           frame_index, expected_frame[frame_index],
                           {dut.tx_fall_w[3:0], dut.tx_rise_w[3:0]}, $time);
                frame_index++;
            end
            if (front_done) completed++;
        end
        #1;
        if (rst) begin
            if ({rx_dv, rx_er, rx_data} !== expected_rx)
                $fatal(1, "FAIL RX stage expected=%h actual=%h at %0t",
                       expected_rx, {rx_dv, rx_er, rx_data}, $time);
            if ({dut.tx_en_r, dut.tx_er_r, dut.tx_data_r} !== expected_tx)
                $fatal(1, "FAIL TX stage expected=%h actual=%h at %0t",
                       expected_tx, {dut.tx_en_r, dut.tx_er_r, dut.tx_data_r}, $time);
            if ({tx_ctl, txd} !== expected_rise || txc !== 1'b1)
                $fatal(1, "FAIL TX rise expected=%h actual=%h clock=%b at %0t",
                       expected_rise, {tx_ctl, txd}, txc, $time);
            checked++;
        end
        @(negedge eth_clk);
        #1;
        if (rst && ({tx_ctl, txd} !== expected_fall || txc !== 1'b0))
            $fatal(1, "FAIL TX fall expected=%h actual=%h clock=%b at %0t",
                   expected_fall, {tx_ctl, txd}, txc, $time);
    end

    // Independent MSB-first CRC, serialized in the bit order used on Ethernet.
    function automatic logic [31:0] crc_update(input logic [31:0] old,
                                              input logic [7:0] octet);
        logic [31:0] value;
        value = old;
        for (integer b = 0; b < 8; b++) begin
            if (value[31] ^ octet[b]) value = (value << 1) ^ 32'h04c11db7;
            else value = value << 1;
        end
        return value;
    endfunction

    initial begin : stimulus
        logic [31:0] crc;
        logic [7:0] octet;
        repeat (4) @(negedge eth_clk);
        #2;
        rst = 1;
        for (integer i = 0; i < 256; i++) begin
            // Drive both RX edges away from sampling; all DV/ER and EN/ER combinations.
            tx_data = 8'(i);
            tx_en = i[0];
            tx_er = i[1];
            rxd = 4'(i);
            rx_ctl = i[0];
            @(posedge eth_clk);
            #2;
            rxd = 4'(i >> 4);
            rx_ctl = i[0] ^ i[1];
            @(negedge eth_clk);
            #2;
        end
        tx_en = 0;
        tx_er = 0;
        rx_ctl = 0;
        repeat (4) @(negedge eth_clk);
        #2;
        for (integer i = 0; i < 8; i++)
            expected_frame.push_back(i == 7 ? 8'hd5 : 8'h55);
        crc = 32'hffffffff;
        for (integer i = 0; i < 60; i++) begin
            octet = 8'(i * 37 + 11);
            expected_frame.push_back(octet);
            crc = crc_update(crc, octet);
        end
        for (integer i = 0; i < 4; i++) begin
            for (integer b = 0; b < 8; b++) octet[b] = ~crc[31 - i * 8 - b];
            expected_frame.push_back(octet);
        end
        front_mode = 1;
        for (integer i = 0; i < 60; i++) begin
            front_valid = 1;
            front_data = {i == 59, 8'(i * 37 + 11)};
            do @(posedge eth_clk); while (!front_ready);
            @(negedge eth_clk);
            #2;
        end
        front_valid = 0;
        wait (completed == 1);
        repeat (16) @(negedge eth_clk);
        if (frame_index != 72 || completed != 1 || checked < 330)
            $fatal(1, "FAIL frame bytes=%0d completed=%0d checked=%0d",
                   frame_index, completed, checked);
        $display("PASS RGMII RX/TX staging, DDR control, TX clock and done/FCS alignment");
        $finish;
    end
    initial begin
        #10000;
        $fatal(1, "FAIL timeout");
    end
endmodule
