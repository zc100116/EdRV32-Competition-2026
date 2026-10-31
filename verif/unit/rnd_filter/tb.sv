// File: tb.sv
// Spec: rnd-spec v0.3 2.6 AFFINE_BLIT bilinear integer arithmetic.
// Description: Direct weighted sums check transparent colored taps, alpha reciprocal
//              reconstruction and one-pixel/cycle flow with randomized output stalls.
// Clock domain: clk_mem.
module tb;
    reg clk = 0;
    always #4 clk = ~clk;
    reg rst_n = 0;
    reg clear = 0;
    reg in_valid = 0;
    wire in_ready;
    reg bilinear = 1;
    reg [127:0] taps;
    reg [7:0] fx, fy;
    reg [31:0] tag, dest;
    reg [7:0] cov;
    wire out_valid;
    reg out_ready = 1;
    wire [31:0] pixel, out_tag, out_dest;
    wire [7:0] out_cov;
    reg [103:0] expected [0:4095];
    int head = 0, tail = 0, cycle = 0, checked = 0;
    reg stalls = 1;
    edrv32_rnd_filter u_filter (
        .clk_i(clk), .rst_n_i(rst_n), .clear_i(clear),
        .in_valid_i(in_valid), .in_ready_o(in_ready), .bilinear_i(bilinear),
        .taps_i(taps), .fraction_x_i(fx), .fraction_y_i(fy),
        .destination_i(dest), .tag_i(tag), .coverage_i(cov),
        .out_valid_o(out_valid), .out_ready_i(out_ready), .pixel_o(pixel),
        .destination_o(out_dest), .tag_o(out_tag), .coverage_o(out_cov)
    );
    function automatic int d(input int n);
        int t;
        t = n+128;
        return (t+(t>>8))>>8;
    endfunction
    function automatic reg [31:0] reference_pixel(input reg [127:0] values,
                                                 input int x, y);
        longint weights [0:3];
        longint sum, a, p, q, value;
        reg [31:0] result;
        weights[0] = (256-longint'(x))*(256-longint'(y));
        weights[1] = longint'(x)*(256-longint'(y));
        weights[2] = (256-longint'(x))*longint'(y);
        weights[3] = longint'(x)*longint'(y);
        sum = 0;
        for (int t = 0; t < 4; t++) sum += weights[t]*longint'(values[t*32+24 +: 8]);
        a = (sum+32768)/65536;
        if (a == 0) return 0;
        q = (255*65536+a/2)/a;
        result = 32'(a)<<24;
        for (int c = 0; c < 3; c++) begin
            sum = 0;
            for (int t = 0; t < 4; t++)
                sum += weights[t]*longint'(d(int'(values[t*32+24 +: 8])*
                    int'(values[t*32+c*8 +: 8])));
            p = (sum+32768)/65536;
            value = (p*q+32768)/65536;
            if (value > 255) value = 255;
            result[c*8 +: 8] = 8'(value);
        end
        return result;
    endfunction
    always @(posedge clk) begin
        cycle <= cycle+1;
        if (in_valid && in_ready) begin
            expected[tail] = {cov, tag, dest, bilinear ? reference_pixel(taps,int'(fx),int'(fy)) :
                taps[31:0]};
            tail++;
        end
        if (out_valid && out_ready) begin
            if (head >= tail || {out_cov,out_tag,out_dest,pixel} !== expected[head])
                $fatal(1,"filter sample=%0d expected=%h actual=%h t=%0t",head,expected[head],
                    {out_cov,out_tag,out_dest,pixel},$time);
            head++;
            checked++;
        end
        if (cycle > 20000) $fatal(1,"filter timeout");
    end
    always @(negedge clk) out_ready = !stalls || cycle%7 != 0;
    task automatic samples;
        for (int i = 0; i < 700; i++) begin
            @(negedge clk);
            in_valid = 1;
            fx = i < 16 ? 8'((i%4)*85) : 8'($urandom);
            fy = i < 16 ? 8'((i/4)*85) : 8'($urandom);
            tag = 32'(i);
            dest = $urandom;
            cov = 8'($urandom);
            for (int t = 0; t < 4; t++) begin
                taps[t*32 +: 32] = $urandom;
                if (i < 64) taps[t*32+24 +: 8] = i%4 == 0 ? 0 : i%4 == 1 ? 1 :
                    i%4 == 2 ? 255 : 128;
            end
            @(posedge clk);
            while (!in_ready) @(posedge clk);
        end
        @(negedge clk); in_valid = 0;
        wait (head == tail);
        repeat (2) @(negedge clk);
    endtask
    initial begin
        repeat (4) @(negedge clk);
        rst_n = 1;
        samples();
        bilinear = 0;
        samples();
        stalls = 0;
        bilinear = 1;
        samples();
        $display("PASS rnd_filter %0d samples",checked);
        $finish;
    end
endmodule
