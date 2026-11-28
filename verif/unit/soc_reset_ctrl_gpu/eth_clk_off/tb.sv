// File: tb.sv
// Spec: sys-subsys-spec 2.10 step 3; gpu-soc-spec 5.3.
// Description: With the PHY-sourced ETH clocks stopped (no link), rst_sys must
//              still release after the clk_mem copy (card 107 round 12 hang).
// Clock: sys, mem, pix, gpu, aud; eth_rx and eth_tx held low.
module tb;
    reg rst_n = 0;
    reg mem_ready = 0;
    reg clk_sys = 0;
    always #5 clk_sys = ~clk_sys;
    reg clk_mem = 0;
    always #7 clk_mem = ~clk_mem;
    reg clk_pix = 0;
    always #9 clk_pix = ~clk_pix;
    reg clk_gpu = 0;
    always #3 clk_gpu = ~clk_gpu;
    reg clk_aud = 0;
    always #41 clk_aud = ~clk_aud;
    wire rst_sys_por_n;
    wire rst_sys_n;
    wire rst_mem_core_n;
    wire rst_mem_n;
    wire rst_pix_n;
    wire rst_gpu_n;
    wire rst_aud_n;
    wire rst_eth_rx_n;
    wire rst_eth_tx_n;
    edrv32_soc_reset_ctrl_gpu u_reset (
        .clk_sys_i(clk_sys),
        .clk_mem_i(clk_mem),
        .clk_pix_i(clk_pix),
        .clk_gpu_i(clk_gpu),
        .clk_aud_i(clk_aud),
        .clk_eth_rx_i(1'b0),
        .clk_eth_tx_i(1'b0),
        .rst_n_i(rst_n),
        .mem_ready_i(mem_ready),
        .soft_reset_media_i(1'b0),
        .soft_reset_soc_i(1'b0),
        .rst_sys_por_n_o(rst_sys_por_n),
        .rst_sys_n_o(rst_sys_n),
        .rst_mem_core_n_o(rst_mem_core_n),
        .rst_mem_n_o(rst_mem_n),
        .rst_pix_n_o(rst_pix_n),
        .rst_gpu_n_o(rst_gpu_n),
        .rst_aud_n_o(rst_aud_n),
        .rst_eth_rx_n_o(rst_eth_rx_n),
        .rst_eth_tx_n_o(rst_eth_tx_n)
    );
    initial begin
        #100 rst_n = 1;
        #200 mem_ready = 1;
        #2000;
        if (rst_sys_n !== 1'b1) begin
            $display("FAIL rst_sys_n=%b expected 1 with ETH clocks stopped at %0t",
                     rst_sys_n, $time);
            $fatal(1);
        end
        if (rst_eth_rx_n !== 1'b0 || rst_eth_tx_n !== 1'b0) begin
            $display("FAIL ETH resets released without ETH clock at %0t", $time);
            $fatal(1);
        end
        $display("PASS");
        $finish;
    end
endmodule
