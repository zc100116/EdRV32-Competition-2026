// File: tb.sv
// Spec: disp-spec 2.4, 4.1, 5.2; X5/X6 reset-drain clarification.
// Description: Check frame-request acknowledgement and scan-live drain at varied ratios.
// Clock domain: independent test memory and pixel clocks.
module tb;
    reg clk_mem = 0;
    reg clk_pix = 0;
    int mem_half = 4;
    int pix_half = 7;
    always #(mem_half) clk_mem = ~clk_mem;
    always #(pix_half) clk_pix = ~clk_pix;
    reg rst_mem_n = 0;
    reg rst_pix_n = 0;
    reg enable = 0;
    reg frame_req = 0;
    wire enable_pix;
    wire frame_req_mem;
    wire scan_live;
    int requests = 0;
    int sent = 0;
    bit check_drain = 0;
    edrv32_disp_control dut (
        .clk_mem_i(clk_mem), .rst_mem_n_i(rst_mem_n),
        .clk_pix_i(clk_pix), .rst_pix_n_i(rst_pix_n),
        .enable_i(enable), .frame_req_i(frame_req), .enable_o(enable_pix),
        .frame_req_o(frame_req_mem), .scan_live_o(scan_live)
    );
    always @(posedge clk_mem) begin
        if (rst_mem_n) begin
            if (frame_req_mem) requests++;
            if (check_drain && !scan_live && requests != sent)
                $fatal(1, "FAIL stop acknowledged before in-flight frame was counted");
        end
    end
    initial begin
        repeat (4) @(negedge clk_mem);
        rst_mem_n = 1;
        @(negedge clk_pix);
        rst_pix_n = 1;
        for (int ratio = 0; ratio < 3; ratio++) begin
            case (ratio)
                0: begin mem_half = 4; pix_half = 7; end
                1: begin mem_half = 11; pix_half = 3; end
                2: begin mem_half = 3; pix_half = 17; end
            endcase
            for (int trial = 0; trial < 20; trial++) begin
                @(negedge clk_mem);
                enable = 1;
                repeat (12) @(negedge clk_pix);
                repeat (5) @(negedge clk_mem);
                if (!enable_pix || !scan_live) $fatal(1, "FAIL enable crossing");
                @(negedge clk_pix);
                sent++;
                frame_req = 1;
                @(negedge clk_pix);
                frame_req = 0;
                @(negedge clk_mem);
                enable = 0;
                check_drain = 1;
                repeat (30) @(negedge clk_mem);
                repeat (8) @(negedge clk_pix);
                repeat (5) @(negedge clk_mem);
                if (enable_pix || scan_live || requests != sent)
                    $fatal(1, "FAIL drained request count actual=%0d expected=%0d",
                           requests, sent);
                check_drain = 0;
            end
            // A short ENABLE can still be in X5 while the returned live level is zero.
            // Every falling edge requires a fresh pixel-domain stop acknowledgement.
            for (int trial = 0; trial < 12; trial++) begin
                @(negedge clk_mem);
                enable = 1;
                repeat (1 + trial%3) @(negedge clk_mem);
                enable = 0;
                #1;
                if (!scan_live) $fatal(1, "FAIL stale scan-live allowed an early reset");
                repeat (40) @(negedge clk_pix);
                repeat (8) @(negedge clk_mem);
                if (enable_pix || scan_live || requests != sent)
                    $fatal(1, "FAIL short-enable stop acknowledgement");
            end
            // A second disable may arrive while the previous stop is in flight.
            @(negedge clk_mem);
            enable = 1;
            @(negedge clk_mem);
            enable = 0;
            @(negedge clk_mem);
            enable = 1;
            @(negedge clk_mem);
            enable = 0;
            #1;
            if (!scan_live) $fatal(1, "FAIL repeated disable lost its stop request");
            repeat (40) @(negedge clk_pix);
            repeat (8) @(negedge clk_mem);
            if (enable_pix || scan_live || requests != sent)
                $fatal(1, "FAIL repeated disable did not drain");
        end
        $display("PASS control: 60 in-flight, 36 short-enable and 3 overlapping stops");
        $finish;
    end
endmodule
