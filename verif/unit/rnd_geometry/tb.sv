// File: tb.sv
// Spec: rnd-spec v0.4 2.3, 2.6 TRIANGLE/LINE/ARC.
// Description: Direct polynomial/edge evaluation checks streamed coverage, clipped origins,
//              single pixel advances, round unions, signed fractions and frozen pipelines.
// Clock domain: clk_mem.
module tb;
    reg clk = 0;
    always #4 clk = ~clk;
    reg rst_n = 0;
    reg clear = 0;
    reg start = 0;
    reg request = 0;
    reg row_end = 0;
    reg [511:0] command;
    reg [1023:0] parameters;
    wire ready;
    wire valid;
    wire [7:0] coverage;
    integer cycle = 0;
    reg stalls = 1;
    wire advance = !stalls || cycle % 97 < 24;
    integer x = 0;
    integer y = 0;
    integer head = 0;
    integer tail = 0;
    integer checked = 0;
    integer last_issue = 0;
    reg measure = 0;
    reg [7:0] expected [0:1023];
    edrv32_rnd_geometry u_geometry (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .clear_i(clear),
        .start_i(start),
        .out_ready_i(advance),
        .command_i(command),
        .parameters_i(parameters),
        .left_i(12'd0),
        .top_i(12'd0),
        .request_i(request),
        .ready_o(ready),
        .row_end_i(row_end),
        .valid_o(valid),
        .coverage_o(coverage)
    );
    function automatic longint edge_value(input int index, sx, sy);
        longint e0, ex, ey;
        e0 = longint'($signed(parameters[index*32 +: 32]));
        ex = longint'($signed(parameters[(index+1)*32 +: 32]));
        ey = longint'($signed(parameters[(index+2)*32 +: 32]));
        return 8*e0 + sx*ex + sy*ey;
    endfunction
    function automatic bit circle_inside(input int index, sx, sy);
        longint q, dx, dy, a, b;
        q = longint'($signed(parameters[index*32 +: 48]));
        dx = longint'($signed(parameters[(index+2)*32 +: 32]));
        dy = longint'($signed(parameters[(index+3)*32 +: 32]));
        a = longint'(sx)-1;
        b = longint'(sy)-1;
        return q + a*(dx-64)/8 + b*(dy-64)/8 + a*a + b*b <= 0;
    endfunction
    function automatic int reference_cov(input int px, py);
        int hits, sx, sy;
        bit inside_sample, one, two;
        longint t, n;
        hits = 0;
        for (int j = 0; j < 4; j++)
            for (int i = 0; i < 4; i++) begin
                sx = 8*(px-int'($signed(command[175:160]))) + (command[16] ? 2*i+1 : 4);
                sy = 8*(py-int'($signed(command[191:176]))) + (command[16] ? 2*j+1 : 4);
                if (command[7:0] == 9) begin
                    inside_sample = 1;
                    for (int e = 0; e < 3; e++)
                        inside_sample &= command[17+e] ? edge_value(e*3, sx, sy) >= 0 :
                            edge_value(e*3, sx, sy) > 0;
                end else if (command[7:0] == 10) begin
                    t = edge_value(0, sx, sy);
                    n = edge_value(3, sx, sy);
                    inside_sample = t >= 0 && t <= 8*longint'(parameters[223:192]) &&
                        n >= -8*longint'(parameters[255:224]) &&
                        n <= 8*longint'(parameters[255:224]);
                    inside_sample |= command[17] && circle_inside(8, sx, sy);
                    inside_sample |= command[18] && circle_inside(12, sx, sy);
                end else begin
                    one = edge_value(16, sx, sy) >= 0;
                    two = edge_value(19, sx, sy) >= 0;
                    inside_sample = circle_inside(0, sx, sy) &&
                        (command[21] || !circle_inside(4, sx, sy)) &&
                        (command[20] || (command[19] ? one || two : one && two));
                    inside_sample |= !command[20] &&
                        ((command[17] && circle_inside(8, sx, sy)) ||
                         (command[18] && circle_inside(12, sx, sy)));
                end
                hits += int'(inside_sample);
            end
        return (255*hits+8)/16;
    endfunction
    always @(posedge clk) begin
        cycle <= cycle + 1;
        if (request && ready) begin
            expected[tail] = 8'(reference_cov(x, y));
            tail++;
            if (measure && last_issue != 0 && cycle-last_issue != (command[16] ? 4 : 1))
                $fatal(1, "peak interval expected=%0d actual=%0d",
                    command[16] ? 4 : 1, cycle-last_issue);
            last_issue = cycle;
        end
        if (valid && advance) begin
            if (head >= tail || coverage !== expected[head])
                $fatal(1, "op=%0d flags=%h group=%0d expected=%h actual=%h t=%0t",
                    command[7:0], command[31:16], head, expected[head], coverage, $time);
            head++;
            checked++;
        end
        if (cycle > 100000) $fatal(1, "geometry timeout");
    end
    task automatic edge_parameters(input int p, e0, ex, ey);
        parameters[p*32 +: 32] = 32'(e0);
        parameters[(p+1)*32 +: 32] = 32'(ex);
        parameters[(p+2)*32 +: 32] = 32'(ey);
    endtask
    task automatic circle_parameters(input int p, cx, cy, radius);
        longint vx, vy, q;
        vx = -3*8+1-longint'(cx);
        vy = -2*8+1-longint'(cy);
        q = vx*vx+vy*vy-longint'(radius)*longint'(radius);
        parameters[p*32 +: 64] = 64'(q);
        parameters[(p+2)*32 +: 32] = 32'(16*vx+64);
        parameters[(p+3)*32 +: 32] = 32'(16*vy+64);
    endtask
    task automatic draw_case(input int op, flags, mode);
        request = 0;
        command = 0;
        command[7:0] = 8'(op);
        command[31:16] = 16'(flags);
        command[191:160] = {16'(-2),16'(-3)};
        parameters = 0;
        if (op == 9) begin
            edge_parameters(0, -4*65536, 65536, 0);
            edge_parameters(3, -3*65536, 0, 65536);
            edge_parameters(6, 12*65536, -65536, -65536);
            if (mode == 1) begin
                // A sub-LSB diagonal: strictness must preserve the fractional sign.
                edge_parameters(0, 1, 1, -1);
                edge_parameters(3, 0, 0, 0);
                edge_parameters(6, 0, 0, 0);
            end
        end else if (op == 10) begin
            edge_parameters(0, -4*65536, 65536, 0);
            edge_parameters(3, -4*65536, 0, 65536);
            parameters[223:192] = 4*65536;
            parameters[255:224] = 81920;
            circle_parameters(8, 8, 16, 10);
            circle_parameters(12, 40, 16, 10);
            if (mode == 1) edge_parameters(0, -65536, 0, 0);
        end else begin
            circle_parameters(0, 24, 16, 28);
            circle_parameters(4, 24, 16, 12);
            circle_parameters(8, 44, 16, 8);
            circle_parameters(12, 24, 36, 8);
            edge_parameters(16, -6*65536, 65536, 0);
            edge_parameters(19, -4*65536, 0, 65536);
        end
        // Bounded random coefficients retain all old directed cases. Even at sx/sy=95,
        // |8E| < 2^35; circles have |q| < 2^35 and |delta| < 2^24/2.
        if (mode == 3) begin
            if (op == 9)
                for (int k = 0; k < 3; k++)
                    edge_parameters(k*3, int'($urandom),
                        int'($urandom_range(0, 33554430))-16777215,
                        int'($urandom_range(0, 33554430))-16777215);
            else
                for (int k = 0; k < 4; k++)
                    circle_parameters(k*4, int'($urandom_range(0, 131070))-65535,
                        int'($urandom_range(0, 131070))-65535,
                        int'($urandom_range(0, 131071)));
        end
        head = 0; tail = 0; last_issue = 0;
        @(negedge clk); start = 1;
        @(negedge clk); start = 0;
        for (int py = 0; py < 5; py++) begin
            x = 0; y = py;
            while (x < 9) begin
                row_end = x >= 8;
                request = 1;
                @(posedge clk);
                while (!ready) @(posedge clk);
                @(negedge clk);
                request = 0;
                x++;
            end
        end
        wait (head == tail);
        repeat (3) @(negedge clk);
    endtask
    task automatic boundary_case(input int kind, aa);
        longint vx, vy, radius, q, endpoint, e0, ex, ey;
        request = 0;
        command = 0;
        parameters = 0;
        command[7:0] = kind < 2 ? 9 : 11;
        command[31:16] = 16'(aa | (kind < 2 ? 14 : 48));
        endpoint = aa != 0 ? 6 : 3;
        if (kind < 2) begin
            if (aa != 0) begin
                e0 = 2147483642;
                ex = 2147483647;
                ey = (64'sd34359738367 - 8*e0)/7 - ex;
            end else begin
                command[175:160] = 16'(-1);
                e0 = 2147483647; ex = 1431655765; ey = 2;
            end
            if (kind == 1) begin e0 = -e0; ex = -ex; ey = -ey; end
            for (int k = 0; k < 3; k++)
                edge_parameters(k*3, int'(e0), int'(ex), int'(ey));
        end else begin
            case (kind)
                2: begin vx = 131072; vy = 131072; radius = 1; end
                3: begin vx = -65536; vy = -1; radius = 196608; end
                4: begin vx = 524283; vy = 0; radius = 524283; end
                default: begin vx = -524292+endpoint; vy = 0; radius = 524292; end
            endcase
            vx -= endpoint;
            vy -= endpoint;
            q = vx*vx+vy*vy-radius*radius;
            for (int k = 0; k < 4; k++) begin
                parameters[k*128 +: 64] = 64'(q);
                parameters[k*128+64 +: 32] = 32'(16*vx+64);
                parameters[k*128+96 +: 32] = 32'(16*vy+64);
            end
        end
        head = 0; tail = 0; last_issue = 0; x = 0; y = 0; row_end = 1;
        @(negedge clk); start = 1;
        @(negedge clk); start = 0; request = 1;
        @(posedge clk);
        while (!ready) @(posedge clk);
        @(negedge clk); request = 0;
        wait (head == tail);
        repeat (3) @(negedge clk);
    endtask
    initial begin
        repeat (4) @(negedge clk);
        rst_n = 1;
        draw_case(9, 15, 0);
        draw_case(9, 14, 2);
        draw_case(9, 13, 0);
        draw_case(9, 15, 1);
        draw_case(10, 7, 0);
        draw_case(10, 6, 0);
        draw_case(10, 3, 1);
        draw_case(10, 1, 2);
        draw_case(11, 7, 0);
        draw_case(11, 15, 0);
        draw_case(11, 23, 0);
        draw_case(11, 55, 0);
        draw_case(11, 6, 0);
        for (int aa = 0; aa < 2; aa++)
            for (int kind = 0; kind < 6; kind++) boundary_case(kind, aa);
        for (int k = 0; k < 20; k++) begin
            draw_case(9, 14 | (k & 1), 3);
            draw_case(11, 48 | (k & 1), 3);
        end
        stalls = 0;
        measure = 1;
        draw_case(9, 15, 0);
        draw_case(9, 14, 0);
        $display("PASS rnd_geometry groups=%0d peak=1 pixel/4 AA cycles or 1 non-AA cycle", checked);
        $finish;
    end
endmodule
