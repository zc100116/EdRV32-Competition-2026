// File: eth_selftest.sv
// Spec: eth-testplan 2; V-T5 independent model selftest.
// Description: Loops source frames through the checked sink and compares every byte.
// Clock domain: 125 MHz MAC loopback; independent RAM and MDC test clocks.
`timescale 1ns/1ps
module eth_selftest;
    logic clk = 0;
    logic rst_n = 0;
    logic [7:0] data;
    logic valid;
    logic error;
    byte unsigned expected[$];
    bit models_done;
    localparam bit [479:0] UDP_BODY = {
        160'h0200000000010200000000020800450000240000,
        160'h40004011b75ac0a80114c0a8010a177013880010,
        160'h0000000000000000000000000000000000000000
    };
    eth_models_selftest u_models (
        .done_o(models_done)
    );
    eth_peer_model u_peer (
        .rx_clk_i(clk),
        .tx_clk_i(clk),
        .rst_n_i(rst_n),
        .rxd_o(data),
        .rx_dv_o(valid),
        .rx_er_o(error),
        .txd_i(data),
        .tx_en_i(valid),
        .tx_er_i(error)
    );
    always #4 clk = ~clk;
    initial begin
        repeat (4) @(negedge clk);
        rst_n = 1;
        for (int n = 0; n < 3; n++) begin
            expected.delete();
            for (int i = 0; i < (n == 1 ? 1514 : 60); i++)
                expected.push_back(n == 2 ? UDP_BODY[479-i*8-:8] : 8'(i*17+n));
            u_peer.send_frame(expected, 12+n);
            @(negedge clk);
            if (u_peer.frame_count != n+1)
                $fatal(1, "FAIL frame count expected=%0d actual=%0d time=%0t",
                    n+1, u_peer.frame_count, $time);
            if (!u_peer.frame_done || u_peer.frame_end <= u_peer.frame_start
                || u_peer.source_end > $realtime)
                $fatal(1, "FAIL frame timing expected=done/end>start actual=%b/%0f/%0f time=%0t",
                    u_peer.frame_done, u_peer.frame_end, u_peer.frame_start, $time);
            if (n == 2 && u_peer.received_fcs != 32'ha53f00b4)
                $fatal(1, "FAIL UDP FCS expected=a53f00b4 actual=%h time=%0t",
                    u_peer.received_fcs, $time);
            foreach (expected[i]) begin
                if (u_peer.received[i] != expected[i])
                    $fatal(1, "FAIL frame=%0d byte=%0d expected=%h actual=%h time=%0t",
                        n, i, expected[i], u_peer.received[i], $time);
            end
        end
        wait (models_done);
        $display("PASS ETH peer selftest");
        $finish;
    end
    initial begin
        #1000000;
        $fatal(1, "FAIL model selftest expected=completion actual=timeout time=%0t", $time);
    end
endmodule
