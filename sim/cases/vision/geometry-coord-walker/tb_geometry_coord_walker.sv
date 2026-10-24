`timescale 1ns/1ps

module tb_geometry_coord_walker;
    reg clk;
    reg rst_n;
    reg cfg_start;
    reg [15:0] cfg_dst_width;
    reg [15:0] cfg_dst_height;
    reg [15:0] cfg_src_width;
    reg [15:0] cfg_src_height;
    reg signed [31:0] cfg_origin_x;
    reg signed [31:0] cfg_origin_y;
    reg signed [31:0] cfg_pixel_step_x;
    reg signed [31:0] cfg_pixel_step_y;
    reg signed [31:0] cfg_row_step_x;
    reg signed [31:0] cfg_row_step_y;
    wire coord_valid;
    reg coord_ready;
    wire [15:0] dst_x;
    wire [15:0] dst_y;
    wire signed [15:0] src_x;
    wire signed [15:0] src_y;
    wire [15:0] src_x_frac;
    wire [15:0] src_y_frac;
    wire src_in_bounds;
    wire sof;
    wire eol;
    wire eof_signal;
    wire busy;
    wire done;
    wire error;

    integer checks;
    integer failures;
    integer ready_cycle;

    always #5 clk = ~clk;

    edrv32_geometry_coord_walker u_dut (
        .clk_i(clk), .rst_n_i(rst_n),
        .cfg_start_i(cfg_start),
        .cfg_dst_width_i(cfg_dst_width),
        .cfg_dst_height_i(cfg_dst_height),
        .cfg_src_width_i(cfg_src_width),
        .cfg_src_height_i(cfg_src_height),
        .cfg_origin_x_i(cfg_origin_x),
        .cfg_origin_y_i(cfg_origin_y),
        .cfg_pixel_step_x_i(cfg_pixel_step_x),
        .cfg_pixel_step_y_i(cfg_pixel_step_y),
        .cfg_row_step_x_i(cfg_row_step_x),
        .cfg_row_step_y_i(cfg_row_step_y),
        .coord_valid_o(coord_valid), .coord_ready_i(coord_ready),
        .dst_x_o(dst_x), .dst_y_o(dst_y),
        .src_x_o(src_x), .src_y_o(src_y),
        .src_x_frac_o(src_x_frac), .src_y_frac_o(src_y_frac),
        .src_in_bounds_o(src_in_bounds),
        .sof_o(sof), .eol_o(eol), .eof_o(eof_signal),
        .busy_o(busy), .done_o(done), .error_o(error)
    );

    task automatic check_true;
        input condition;
        input [8*120-1:0] message;
        begin
            checks = checks + 1;
            if (!condition) begin
                failures = failures + 1;
                $display("CHECK_FAIL time=%0t %0s", $time, message);
            end
        end
    endtask

    task automatic run_case;
        input [8*32-1:0] name;
        input integer dst_w;
        input integer dst_h;
        input integer src_w;
        input integer src_h;
        input integer origin_x;
        input integer origin_y;
        input integer pixel_dx;
        input integer pixel_dy;
        input integer row_dx;
        input integer row_dy;
        integer expected_x;
        integer expected_y;
        integer accepted;
        integer guard;
        integer ex_qx;
        integer ex_qy;
        reg expected_bounds;
        begin
            @(negedge clk);
            cfg_dst_width = dst_w;
            cfg_dst_height = dst_h;
            cfg_src_width = src_w;
            cfg_src_height = src_h;
            cfg_origin_x = origin_x;
            cfg_origin_y = origin_y;
            cfg_pixel_step_x = pixel_dx;
            cfg_pixel_step_y = pixel_dy;
            cfg_row_step_x = row_dx;
            cfg_row_step_y = row_dy;
            cfg_start = 1'b1;
            @(negedge clk);
            cfg_start = 1'b0;

            accepted = 0;
            guard = 0;
            ready_cycle = 0;
            while ((accepted < dst_w * dst_h) && (guard < 2000)) begin
                coord_ready = (ready_cycle % 4) != 1;
                #1;
                if (coord_valid && coord_ready) begin
                    expected_x = accepted % dst_w;
                    expected_y = accepted / dst_w;
                    ex_qx = origin_x + expected_x * pixel_dx +
                        expected_y * row_dx;
                    ex_qy = origin_y + expected_x * pixel_dy +
                        expected_y * row_dy;
                    expected_bounds = ((ex_qx >>> 16) >= 0) &&
                        ((ex_qx >>> 16) < src_w) &&
                        ((ex_qy >>> 16) >= 0) &&
                        ((ex_qy >>> 16) < src_h);
                    check_true(dst_x == expected_x && dst_y == expected_y,
                               "destination raster coordinate matches");
                    check_true($signed(src_x) == (ex_qx >>> 16) &&
                               $signed(src_y) == (ex_qy >>> 16),
                               "source integer coordinate matches affine walk");
                    check_true(src_x_frac == (ex_qx & 16'hffff) &&
                               src_y_frac == (ex_qy & 16'hffff),
                               "source fractional coordinate matches Q16.16");
                    check_true(src_in_bounds == expected_bounds,
                               "source bounds flag matches");
                    check_true(sof == (accepted == 0),
                               "SOF appears on the first coordinate");
                    check_true(eol == (expected_x == dst_w-1),
                               "EOL appears at destination line end");
                    check_true(eof_signal == (accepted == dst_w*dst_h-1),
                               "EOF appears on the final coordinate");
                    accepted = accepted + 1;
                end
                ready_cycle = ready_cycle + 1;
                guard = guard + 1;
                @(negedge clk);
            end
            coord_ready = 1'b0;
            check_true(guard < 2000, "coordinate case completed");
            check_true(done && !busy, "done pulses after final coordinate");
            check_true(!error, name);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        cfg_start = 1'b0;
        cfg_dst_width = 16'b0;
        cfg_dst_height = 16'b0;
        cfg_src_width = 16'b0;
        cfg_src_height = 16'b0;
        cfg_origin_x = 32'sb0;
        cfg_origin_y = 32'sb0;
        cfg_pixel_step_x = 32'sb0;
        cfg_pixel_step_y = 32'sb0;
        cfg_row_step_x = 32'sb0;
        cfg_row_step_y = 32'sb0;
        coord_ready = 1'b0;
        checks = 0;
        failures = 0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        // Identity/crop: src=(2+x, 1+y).
        run_case("identity crop", 5, 3, 10, 8,
                 2 <<< 16, 1 <<< 16, 1 <<< 16, 0, 0, 1 <<< 16);
        // Coordinate-only 2:1 downscale with a half-pixel origin.
        run_case("fractional scale", 4, 3, 8, 6,
                 16'h8000, 16'h8000, 2 <<< 16, 0, 0, 2 <<< 16);
        // Horizontal flip.
        run_case("horizontal flip", 5, 3, 5, 3,
                 4 <<< 16, 0, -(1 <<< 16), 0, 0, 1 <<< 16);
        // Vertical flip.
        run_case("vertical flip", 5, 3, 5, 3,
                 0, 2 <<< 16, 1 <<< 16, 0, 0, -(1 <<< 16));
        // 90-degree clockwise inverse map: src=(dst_y, H-1-dst_x).
        run_case("rotate 90", 3, 4, 4, 3,
                 0, 2 <<< 16, 0, -(1 <<< 16), 1 <<< 16, 0);
        // Negative origin checks out-of-bounds reporting.
        run_case("negative border", 4, 2, 4, 2,
                 -(1 <<< 15), -(1 <<< 16), 1 <<< 16, 0, 0, 1 <<< 16);

        if (failures == 0)
            $display("GEOMETRY_COORD_WALKER_PASS checks=%0d", checks);
        else
            $fatal(1, "GEOMETRY_COORD_WALKER_FAIL checks=%0d failures=%0d",
                   checks, failures);
        $finish;
    end

    initial begin
        #500000;
        $fatal(1, "Geometry coordinate walker timeout");
    end

endmodule
