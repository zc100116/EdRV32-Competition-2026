// File: edrv32_gpu_scenario.sv
// Spec: gpu-soc-testplan ST-14; gpu-soc 5.3; visual SoC 5.3.
// Description: Check initial domain release order and media-only soft reset.
// Clock domain: sys, mem, GPU, audio and pixel reset observations.
`timescale 1ns/1ps
module edrv32_gpu_scenario (
    output bit checks_complete_o,
    output wire [1:0] model_sda_oe_o
);
    assign model_sda_oe_o = 2'b00;
    initial begin
        checks_complete_o = 0;
        @(posedge $root.edrv32_gpu_soc_tb.u_dut.rst_mem_core_n_w);
        if (!$root.edrv32_gpu_soc_tb.mem_ready_i)
            $fatal(1, "FAIL mem reset before ready time=%0t", $time);
        wait ($root.edrv32_gpu_soc_tb.u_dut.rst_gpu_n_w &&
                $root.edrv32_gpu_soc_tb.u_dut.rst_aud_n_w);
        if ($root.edrv32_gpu_soc_tb.u_dut.rst_sys_n_w)
            $fatal(1, "FAIL sys released before GPU/audio time=%0t", $time);
        @(posedge $root.edrv32_gpu_soc_tb.u_dut.rst_sys_n_w);
        while ($root.edrv32_gpu_soc_tb.u_ddr.peek(32'h003ff000) != 14) begin
            @(negedge $root.edrv32_gpu_soc_tb.clk_mem_i);
        end
        $root.edrv32_gpu_soc_tb.u_ddr.poke(32'h003ff004, 8'd1);
        wait (!$root.edrv32_gpu_soc_tb.u_dut.rst_gpu_n_w &&
                !$root.edrv32_gpu_soc_tb.u_dut.rst_aud_n_w);
        if (!$root.edrv32_gpu_soc_tb.u_dut.rst_sys_n_w ||
            !$root.edrv32_gpu_soc_tb.u_dut.rst_mem_core_n_w)
            $fatal(1, "FAIL media reset affected sys/memory core time=%0t", $time);
        wait ($root.edrv32_gpu_soc_tb.u_dut.rst_gpu_n_w &&
                $root.edrv32_gpu_soc_tb.u_dut.rst_aud_n_w &&
                $root.edrv32_gpu_soc_tb.u_dut.rst_mem_n_w &&
                $root.edrv32_gpu_soc_tb.u_dut.rst_pix_n_w);
        $root.edrv32_gpu_soc_tb.u_ddr.poke(32'h003ff004, 8'd2);
        checks_complete_o = 1;
        $display("CHECK ST-14 initial order and media soft reset");
    end
    always @(posedge $root.edrv32_gpu_soc_tb.u_dut.rst_gpu_n_w) begin
        if (!$root.edrv32_gpu_soc_tb.clk_gpu_i)
            $fatal(1, "FAIL GPU reset not synchronous time=%0t", $time);
    end
    always @(posedge $root.edrv32_gpu_soc_tb.u_dut.rst_aud_n_w) begin
        if (!$root.edrv32_gpu_soc_tb.clk_aud_i)
            $fatal(1, "FAIL AUD reset not synchronous time=%0t", $time);
    end
endmodule
