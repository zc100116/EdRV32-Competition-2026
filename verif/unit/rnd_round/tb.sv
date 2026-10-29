// File: tb.sv
// Spec: rnd-spec 2.3.
// Description: Independent integer reference for signed exterior, row_edge fractions and clamping.
// Clock domain: clk_mem.
module tb;
    reg clk = 0;
    always #4 clk = ~clk;
    reg rst_n = 0;
    reg valid = 0;
    wire ready;
    reg [16:0] width_value;
    reg [16:0] height_value;
    reg [16:0] row;
    reg [11:0] radius;
    wire edge_valid;
    reg edge_ready = 0;
    wire [15:0] row_edge;
    wire [11:0] clamped;
    reg signed [17:0] x;
    reg row_inside = 1;
    wire [15:0] cov;
    edrv32_rnd_round_row u_row (
        .clk_i(clk), .rst_n_i(rst_n), .clear_i(1'b0), .row_valid_i(valid), .row_ready_o(ready),
        .width_i(width_value), .height_i(height_value), .row_y_i(row), .radius_i(radius),
        .edge_valid_o(edge_valid), .edge_ready_i(edge_ready),
        .edge_q4_o(row_edge), .radius_o(clamped)
    );
    edrv32_rnd_coverage u_coverage (
        .x_i(x), .width_i(width_value), .edge_q4_i(row_edge),
        .row_inside_i(row_inside), .coverage_o(cov)
    );
    function automatic int root(input longint n);
        longint lo = 0;
        longint hi = 65536;
        longint mid;
        while (hi - lo > 1) begin
            mid = (hi + lo) / 2;
            if (mid * mid <= n) lo = mid;
            else hi = mid;
        end
        return int'(lo);
    endfunction
    function automatic int reference_edge(input int w, h, r, j);
        int limit, yd;
        limit = (w < h ? w : h) / 2;
        if (r > limit) r = limit;
        yd = j < h - 1 - j ? j : h - 1 - j;
        if (r == 0 || yd >= r) return 0;
        return 16*r - root(256*longint'(r)*r - (16*(longint'(r)-longint'(yd))-8)**2);
    endfunction
    function automatic int reference_cov(input int w, i, e);
        int a, b, room_value;
        if (i < 0 || i >= w) return 0;
        a = 16*i + 16-e;
        b = 16*w-e-16*i;
        room_value = a < b ? a : b;
        if (room_value <= 0) return 0;
        if (room_value >= 16) return 255;
        return 16*room_value;
    endfunction
    task automatic check_row(input int w, h, r, j);
        int expected_edge, expected_radius;
        @(negedge clk);
        width_value = 17'(w);
        height_value = 17'(h);
        radius = 12'(r);
        row = 17'(j);
        valid = 1;
        do @(posedge clk); while (!ready);
        @(negedge clk);
        valid = 0;
        while (!edge_valid) @(negedge clk);
        expected_edge = reference_edge(w,h,r,j);
        expected_radius = (w < h ? w : h)/2;
        if (r < expected_radius) expected_radius = r;
        if (int'(row_edge) != expected_edge || int'(clamped) != expected_radius)
            $fatal(1,"row_edge W=%0d H=%0d R=%0d j=%0d want=%0d got=%0d t=%0t",
                w,h,r,j,expected_edge,row_edge,$time);
        for (int i=-2; i<w+1; i++) begin
            x = 18'(i);
            #1;
            if (int'(cov[7:0]) != reference_cov(w,i,expected_edge) ||
                int'(cov[15:8]) != reference_cov(w,i+1,expected_edge))
                $fatal(1,"coverage x=%0d row_edge=%0d got=%h t=%0t",i,row_edge,cov,$time);
        end
        row_inside = 0;
        #1;
        if (cov !== 0) $fatal(1,"exterior row coverage %h t=%0t",cov,$time);
        row_inside = 1;
        @(negedge clk);
        edge_ready = 1;
        @(negedge clk);
        edge_ready = 0;
    endtask
    initial begin
        repeat(3) @(negedge clk);
        rst_n = 1;
        for (int w=1; w<=28; w++)
            for (int h=1; h<=28; h+=3)
                for (int r=0; r<=18; r+=3)
                    for (int j=0; j<h; j++) check_row(w,h,r,j);
        check_row(65536,65536,4095,0);
        check_row(8192,8192,4095,4094);
        for (int n=0; n<100; n++) begin
            int w,h,r,j;
            w=$urandom_range(1,8192);
            h=$urandom_range(1,8192);
            r=$urandom_range(0,4095);
            j=$urandom_range(0,h-1);
            check_row(w,h,r,j);
        end
        $display("PASS rounded rows and two-lane coverage");
        $finish;
    end
endmodule
