// File: tb.sv
// Spec: aud-spec 2.4; gpu-soc-spec 5.2 X11.
// Description: Full-capacity RAM FIFO, conservative occupancy and pointer wraps.
// Clock domain: unrelated write/read test clocks.
module tb;
    reg mem_clk = 0;
    reg aud_clk = 0;
    always #5 mem_clk = ~mem_clk;
    always #7 aud_clk = ~aud_clk;
    reg mem_rst_n = 0;
    reg aud_rst_n = 0;
    reg valid = 0;
    wire ready;
    reg [31:0] data_in = 0;
    wire [9:0] level;
    wire out_valid;
    reg out_ready = 0;
    wire [31:0] data_out;
    integer sent = 0;
    integer received = 0;
    integer round_idx;
    integer idx;
    edrv32_aud_fifo dut (
        .clk_mem_i(mem_clk),
        .rst_mem_n_i(mem_rst_n),
        .clk_aud_i(aud_clk),
        .rst_aud_n_i(aud_rst_n),
        .sample_valid_i(valid),
        .sample_ready_o(ready),
        .sample_data_i(data_in),
        .level_o(level),
        .sample_valid_o(out_valid),
        .sample_ready_i(out_ready),
        .sample_data_o(data_out)
    );
    always @(posedge mem_clk) begin
        if (mem_rst_n && valid && ready) sent = sent + 1;
        #1;
        if (mem_rst_n && int'(level) < sent-received)
            $fatal(1, "FAIL optimistic occupancy level=%0d actual=%0d", level, sent-received);
    end
    always @(posedge aud_clk) begin
        if (aud_rst_n && out_valid && out_ready) begin
            if (data_out !== (32'hf0000000 + 32'(received)))
                $fatal(1, "FAIL FIFO sample=%0d actual=%h", received, data_out);
            received = received + 1;
        end
    end
    initial begin
        repeat (3) @(negedge mem_clk);
        mem_rst_n = 1;
        @(negedge aud_clk);
        aud_rst_n = 1;
        for (round_idx = 0; round_idx < 3; round_idx = round_idx + 1) begin
            for (idx = 0; idx < 512; idx = idx + 1) begin
                @(negedge mem_clk);
                valid = 1;
                data_in = 32'hf0000000 + 32'(sent);
                do @(posedge mem_clk); while (!ready);
            end
            @(negedge mem_clk);
            valid = 0;
            repeat (5) @(negedge mem_clk);
            if (ready || level != 512) $fatal(1, "FAIL full level=%0d", level);
            @(negedge aud_clk);
            out_ready = 1;
            wait (received == sent);
            @(negedge aud_clk);
            out_ready = 0;
            repeat (8) @(negedge mem_clk);
            if (level != 0 || !ready) $fatal(1, "FAIL empty level=%0d", level);
        end
        $display("PASS FIFO 1536 samples, three full/empty cycles and counter wrap");
        $finish;
    end
    initial begin
        #1000000;
        $fatal(1, "FAIL timeout");
    end
endmodule
