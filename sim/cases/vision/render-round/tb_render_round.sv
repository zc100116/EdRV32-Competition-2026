`timescale 1ns/1ps

module tb_render_round;
    reg clk, rst_n;
    reg row_valid;
    wire row_ready;
    reg [15:0] width, height, row_y;
    reg [9:0] radius, border;
    wire edge_valid;
    reg edge_ready;
    wire [15:0] outer_edge, inner_edge;
    wire inner_active;
    reg [15:0] pixel_x;
    wire [15:0] outer_cover, inner_cover;
    integer check_count;
    integer cycles;
    integer i, x, y;
    integer outer_expected, inner_expected;
    integer inner_height, inner_y, inner_r, r;
    integer file_id;
    integer border_alpha, fill_alpha;
    integer rr, gg, bb;

    always #5 clk = ~clk;

    edrv32_render_round_row u_row (
        .clk_i(clk), .rst_n_i(rst_n),
        .row_valid_i(row_valid), .row_ready_o(row_ready),
        .width_i(width), .height_i(height), .row_y_i(row_y),
        .radius_i(radius), .border_i(border),
        .edge_valid_o(edge_valid), .edge_ready_i(edge_ready),
        .outer_edge_q4_o(outer_edge),
        .inner_edge_q4_o(inner_edge),
        .inner_active_o(inner_active)
    );
    edrv32_render_round_coverage u_coverage (
        .x_i(pixel_x), .width_i(width),
        .outer_edge_q4_i(outer_edge),
        .inner_edge_q4_i(inner_edge),
        .inner_active_i(inner_active),
        .outer_coverage_o(outer_cover),
        .inner_coverage_o(inner_cover)
    );

    function automatic integer isqrt;
        input integer value;
        integer root;
        begin
            root = 0;
            while ((root + 1)*(root + 1) <= value)
                root = root + 1;
            isqrt = root;
        end
    endfunction

    function automatic integer edge_ref;
        input integer rad;
        input integer ydist;
        integer rq4, dyq4;
        begin
            if (rad == 0 || ydist >= rad)
                edge_ref = 0;
            else begin
                rq4 = rad*16;
                dyq4 = (rad - ydist)*16 - 8;
                edge_ref = rq4 - isqrt(rq4*rq4 - dyq4*dyq4);
            end
        end
    endfunction

    task automatic check_row;
        input integer w;
        input integer h;
        input integer yy;
        input integer rad;
        input integer bord;
        integer ydist;
        begin
            @(negedge clk);
            if (!row_ready) $fatal(1, "round row not ready");
            width = w;
            height = h;
            row_y = yy;
            radius = rad;
            border = bord;
            row_valid = 1'b1;
            @(negedge clk);
            row_valid = 1'b0;
            wait(edge_valid);
            #1;
            r = rad < (w < h ? w : h)/2 ? rad : (w < h ? w : h)/2;
            ydist = yy < h-1-yy ? yy : h-1-yy;
            outer_expected = edge_ref(r, ydist);
            inner_height = h - 2*bord;
            inner_y = yy - bord;
            inner_r = r > bord ? r-bord : 0;
            if (w > 2*bord && h > 2*bord &&
                yy >= bord && yy < h-bord) begin
                ydist = inner_y < inner_height-1-inner_y ?
                        inner_y : inner_height-1-inner_y;
                inner_expected = bord*16 + edge_ref(inner_r,ydist);
                if (!inner_active) $fatal(1, "missing inner row");
            end else begin
                inner_expected = bord*16;
                if (inner_active) $fatal(1, "unexpected inner row");
            end
            if (outer_edge !== outer_expected ||
                inner_edge !== inner_expected)
                $fatal(1, "row w=%0d h=%0d y=%0d r=%0d b=%0d edge=%0d/%0d expected=%0d/%0d",
                       w,h,yy,rad,bord,outer_edge,inner_edge,
                       outer_expected,inner_expected);
            check_count = check_count + 1;
            @(negedge clk);
            edge_ready = 1'b1;
            @(negedge clk);
            edge_ready = 1'b0;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        row_valid = 1'b0;
        edge_ready = 1'b0;
        width = 16'b0;
        height = 16'b0;
        row_y = 16'b0;
        radius = 10'b0;
        border = 10'b0;
        pixel_x = 16'b0;
        check_count = 0;
        cycles = 0;
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        check_row(64,40,0,12,3);
        check_row(64,40,1,12,3);
        check_row(64,40,10,12,3);
        check_row(64,40,20,12,3);
        check_row(64,40,39,12,3);
        check_row(30,18,0,100,0);
        check_row(30,18,17,100,0);
        check_row(17,11,5,0,2);
        for (i = 0; i < 80; i = i + 1)
            check_row(20 + $urandom_range(0,100),
                      20 + $urandom_range(0,60),
                      0, $urandom_range(0,80),
                      $urandom_range(0,7));

        file_id = $fopen("sim/build/cases/vision/render-round/round.ppm", "wb");
        if (file_id == 0) $fatal(1, "cannot open round.ppm");
        $fwrite(file_id, "P6\n64 40\n255\n");
        for (y = 0; y < 40; y = y + 1) begin
            check_row(64,40,y,12,3);
            for (x = 0; x < 64; x = x + 2) begin
                pixel_x = x;
                #1;
                border_alpha = outer_cover[7:0] - inner_cover[7:0];
                fill_alpha = inner_cover[7:0];
                rr = 20 + (220*border_alpha + 20*fill_alpha)/255;
                gg = 25 + (40*border_alpha + 160*fill_alpha)/255;
                bb = 35 + (35*border_alpha + 165*fill_alpha)/255;
                $fwrite(file_id, "%c%c%c", rr, gg, bb);
                border_alpha = outer_cover[15:8] - inner_cover[15:8];
                fill_alpha = inner_cover[15:8];
                rr = 20 + (220*border_alpha + 20*fill_alpha)/255;
                gg = 25 + (40*border_alpha + 160*fill_alpha)/255;
                bb = 35 + (35*border_alpha + 165*fill_alpha)/255;
                $fwrite(file_id, "%c%c%c", rr, gg, bb);
            end
        end
        $fclose(file_id);
        $display("RENDER_ROUND_PASS rows=%0d", check_count);
        $finish;
    end

    always @(posedge clk) begin
        if (rst_n) begin
            cycles = cycles + 1;
            if (cycles > 20000)
                $fatal(1, "round row timeout");
        end
    end
endmodule
