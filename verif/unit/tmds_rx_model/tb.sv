// File: tb.sv
// Spec: DISP testplan 2; DVI 1.0 Figure 3-5.
// Description: Exhaust all bytes with independent forward encoding, controls,
//              running disparity sequences, lane order and frame collection.
// Clock domain: clk.
`timescale 1ns/1ps
module tb;
    logic clk = 0;
    logic rst_n = 0;
    logic [29:0] sym = {3{10'b1101010100}};
    logic hs;
    logic vs;
    logic de;
    logic [23:0] rgb;
    int frames;
    int pixels;
    int disparity[3];
    always #5 clk = !clk;
    tmds_rx_model u_rx (
        .clk_pix_i(clk),
        .rst_n_i(rst_n),
        .sym_i(sym),
        .hs_o(hs),
        .vs_o(vs),
        .de_o(de),
        .rgb_o(rgb),
        .frame_count_o(frames),
        .frame_pixel_count_o(pixels)
    );
    function automatic logic [9:0] encode(input logic [7:0] value_i, input int lane_i);
        logic [8:0] q;
        logic [9:0] word_out;
        bit use_xnor;
        int ones;
        int balance;
        ones = $countones(value_i);
        use_xnor = ones > 4 || (ones == 4 && !value_i[0]);
        q[0] = value_i[0];
        for (int i = 1; i < 8; i++) q[i] = q[i-1] ^ value_i[i] ^ use_xnor;
        q[8] = !use_xnor;
        balance = 2 * $countones(q[7:0]) - 8;
        if (disparity[lane_i] == 0 || balance == 0)
            word_out = {!q[8], q[8], q[7:0] ^ {8{!q[8]}}};
        else if ((disparity[lane_i] > 0) == (balance > 0))
            word_out = {1'b1, q[8], ~q[7:0]};
        else word_out = {1'b0, q[8], q[7:0]};
        disparity[lane_i] += 2 * $countones(word_out) - 10;
        return word_out;
    endfunction
    task automatic control_symbol(input int control_i);
        logic [9:0] blue;
        case (control_i)
            0: blue = 10'b1101010100;
            1: blue = 10'b0010101011;
            2: blue = 10'b0101010100;
            3: blue = 10'b1010101011;
            default: $fatal(1, "FAIL control stimulus time=%0t", $time);
        endcase
        @(negedge clk);
        sym = {10'b1101010100, 10'b1101010100, blue};
        for (int c = 0; c < 3; c++) disparity[c] = 0;
        #1;
        if (de || {vs, hs} != 2'(control_i))
            $fatal(1, "FAIL control expected=%0d actual=%b/%b time=%0t",
                    control_i, de, {vs, hs}, $time);
        @(posedge clk);
        #1;
    endtask
    task automatic pixel(input logic [23:0] value_i);
        @(negedge clk);
        sym = {encode(value_i[23:16], 2), encode(value_i[15:8], 1),
                encode(value_i[7:0], 0)};
        #1;
        if (!de || rgb != value_i)
            $fatal(1, "FAIL decode expected=%h actual=%h DE=%b time=%0t",
                    value_i, rgb, de, $time);
        @(posedge clk);
        #1;
    endtask
    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1;
        for (int c = 0; c < 4; c++) control_symbol(c);
        control_symbol(0);
        for (int pass = 0; pass < 4; pass++) begin
            for (int v = 0; v < 256; v++)
                pixel({8'(v), 8'(255-v), 8'(v ^ (pass*73))});
            control_symbol(0);
        end
        control_symbol(2);
        if (pixels != 1024)
            $fatal(1, "FAIL frame expected=1024 actual=%0d time=%0t", pixels, $time);
        control_symbol(0);
        for (int p = 0; p < 12; p++) pixel(24'h123400 + 24'(p));
        control_symbol(2);
        if (pixels != 12 || u_rx.frame_pixels[11] != 24'h12340b)
            $fatal(1, "FAIL collection expected=12/12340b actual=%0d/%h time=%0t",
                    pixels, u_rx.frame_pixels[11], $time);
        $display("PASS tmds_rx_model exhaustive bytes, controls, lanes, frames");
        $finish;
    end
endmodule
