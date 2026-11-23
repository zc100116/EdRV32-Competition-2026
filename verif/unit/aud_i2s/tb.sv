// File: tb.sv
// Spec: aud-spec 2.5, 6, 8.1.
// Description: Bit-accurate I2S clocks, channel slots, disabled output and underruns.
// Clock domain: independent test clock representing clk_aud.
module tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg enable = 0;
    reg valid = 1;
    wire ready;
    wire bclk;
    wire lrck;
    wire data_out;
    wire underrun;
    reg [31:0] sample = 32'h96a53cc3;
    integer takes = 0;
    integer underruns = 0;
    integer cycle = 0;
    reg frame_valid = 0;
    reg expected;
    integer slot;
    integer phase;
    edrv32_aud_i2s dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .enable_i(enable),
        .sample_valid_i(valid),
        .sample_ready_o(ready),
        .sample_data_i(sample),
        .aud_bclk_o(bclk),
        .aud_lrck_o(lrck),
        .aud_sdata_o(data_out),
        .underrun_o(underrun)
    );
    always @(posedge clk) begin
        if (rst_n) begin
            if (ready && valid) takes = takes + 1;
            if (underrun) underruns = underruns + 1;
            if (!enable) frame_valid = 0;
            else if (cycle % 256 == 255) frame_valid = valid;
            cycle = cycle + 1;
            #1;
            phase = cycle % 256;
            slot = (phase / 4) % 32;
            expected = 0;
            if (enable && frame_valid && slot >= 1 && slot <= 16)
                expected = sample[(phase >= 128 ? 32 : 16) - slot];
            if (bclk !== ((phase % 4) >= 2) || lrck !== (phase >= 128))
                $fatal(1, "FAIL clocks cycle=%0d bclk=%b lrck=%b", cycle, bclk, lrck);
            if (data_out !== expected)
                $fatal(1, "FAIL sample cycle=%0d expected=%b actual=%b", cycle, expected,
                    data_out);
        end
    end
    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1;
        repeat (300) @(negedge clk);
        if (takes != 0 || underruns != 0) $fatal(1, "FAIL disabled ownership");
        enable = 1;
        repeat (1000) @(negedge clk);
        if (takes != 4) $fatal(1, "FAIL takes=%0d expected=4", takes);
        valid = 0;
        repeat (512) @(negedge clk);
        if (underruns != 2) $fatal(1, "FAIL underruns=%0d expected=2", underruns);
        enable = 0;
        valid = 1;
        repeat (512) @(negedge clk);
        if (takes != 4 || underruns != 2) $fatal(1, "FAIL disabled events");
        $display("PASS I2S 2324 clock cycles, 4 samples, 2 underruns");
        $finish;
    end
    initial begin
        #100000;
        $fatal(1, "FAIL timeout");
    end
endmodule
