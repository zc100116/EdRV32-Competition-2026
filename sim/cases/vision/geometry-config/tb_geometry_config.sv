`timescale 1ns/1ps

module tb_geometry_config;
    reg clk;
    reg rst_n;
    reg cfg_start;
    reg [15:0] cfg_src_width;
    reg [15:0] cfg_src_height;
    reg [15:0] cfg_crop_x;
    reg [15:0] cfg_crop_y;
    reg [15:0] cfg_crop_width;
    reg [15:0] cfg_crop_height;
    reg [15:0] cfg_dst_width;
    reg [15:0] cfg_dst_height;
    reg [15:0] cfg_image_width;
    reg [15:0] cfg_image_height;
    reg [8:0] cfg_angle;
    reg cfg_flip_x;
    reg cfg_flip_y;

    wire walker_start;
    wire [15:0] walker_dst_width;
    wire [15:0] walker_dst_height;
    wire [15:0] walker_src_width;
    wire [15:0] walker_src_height;
    wire signed [31:0] walker_origin_x;
    wire signed [31:0] walker_origin_y;
    wire signed [31:0] walker_pixel_step_x;
    wire signed [31:0] walker_pixel_step_y;
    wire signed [31:0] walker_row_step_x;
    wire signed [31:0] walker_row_step_y;
    wire config_busy;
    wire config_done;
    wire config_error;

    reg coord_ready;
    wire coord_valid;
    wire [15:0] dst_x;
    wire [15:0] dst_y;
    wire signed [15:0] src_x;
    wire signed [15:0] src_y;
    wire [15:0] src_x_frac;
    wire [15:0] src_y_frac;
    wire src_in_bounds;
    wire coord_sof;
    wire coord_eol;
    wire coord_eof;
    wire walker_busy;
    wire walker_done;
    wire walker_error;

    integer checks;
    integer failures;
    integer divider_start_count;
    integer rom_capture_count;
    integer divider_before;
    integer rom_before;

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (!rst_n) begin
            divider_start_count <= 0;
            rom_capture_count <= 0;
        end else begin
            if (u_config.div_start_r)
                divider_start_count <= divider_start_count + 1;
            if (u_config.state_r == 4'd2)
                rom_capture_count <= rom_capture_count + 1;
        end
    end

    edrv32_geometry_config u_config (
        .clk_i(clk), .rst_n_i(rst_n),
        .cfg_start_i(cfg_start),
        .cfg_src_width_i(cfg_src_width),
        .cfg_src_height_i(cfg_src_height),
        .cfg_crop_x_i(cfg_crop_x), .cfg_crop_y_i(cfg_crop_y),
        .cfg_crop_width_i(cfg_crop_width),
        .cfg_crop_height_i(cfg_crop_height),
        .cfg_dst_width_i(cfg_dst_width),
        .cfg_dst_height_i(cfg_dst_height),
        .cfg_image_width_i(cfg_image_width),
        .cfg_image_height_i(cfg_image_height),
        .cfg_angle_i(cfg_angle),
        .cfg_flip_x_i(cfg_flip_x), .cfg_flip_y_i(cfg_flip_y),
        .walker_start_o(walker_start),
        .walker_dst_width_o(walker_dst_width),
        .walker_dst_height_o(walker_dst_height),
        .walker_src_width_o(walker_src_width),
        .walker_src_height_o(walker_src_height),
        .walker_origin_x_o(walker_origin_x),
        .walker_origin_y_o(walker_origin_y),
        .walker_pixel_step_x_o(walker_pixel_step_x),
        .walker_pixel_step_y_o(walker_pixel_step_y),
        .walker_row_step_x_o(walker_row_step_x),
        .walker_row_step_y_o(walker_row_step_y),
        .busy_o(config_busy), .done_o(config_done), .error_o(config_error)
    );

    edrv32_geometry_coord_walker u_walker (
        .clk_i(clk), .rst_n_i(rst_n),
        .cfg_start_i(walker_start),
        .cfg_dst_width_i(walker_dst_width),
        .cfg_dst_height_i(walker_dst_height),
        .cfg_src_width_i(walker_src_width),
        .cfg_src_height_i(walker_src_height),
        .cfg_origin_x_i(walker_origin_x),
        .cfg_origin_y_i(walker_origin_y),
        .cfg_pixel_step_x_i(walker_pixel_step_x),
        .cfg_pixel_step_y_i(walker_pixel_step_y),
        .cfg_row_step_x_i(walker_row_step_x),
        .cfg_row_step_y_i(walker_row_step_y),
        .coord_valid_o(coord_valid), .coord_ready_i(coord_ready),
        .dst_x_o(dst_x), .dst_y_o(dst_y),
        .src_x_o(src_x), .src_y_o(src_y),
        .src_x_frac_o(src_x_frac), .src_y_frac_o(src_y_frac),
        .src_in_bounds_o(src_in_bounds),
        .sof_o(coord_sof), .eol_o(coord_eol), .eof_o(coord_eof),
        .busy_o(walker_busy), .done_o(walker_done), .error_o(walker_error)
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

    function automatic integer abs_diff;
        input integer lhs;
        input integer rhs;
        begin
            abs_diff = lhs >= rhs ? lhs - rhs : rhs - lhs;
        end
    endfunction

    task automatic start_config;
        input integer src_w;
        input integer src_h;
        input integer crop_x;
        input integer crop_y;
        input integer crop_w;
        input integer crop_h;
        input integer dst_w;
        input integer dst_h;
        input integer image_w;
        input integer image_h;
        input integer angle;
        input integer flip_x;
        input integer flip_y;
        begin
            @(negedge clk);
            cfg_src_width = src_w;
            cfg_src_height = src_h;
            cfg_crop_x = crop_x;
            cfg_crop_y = crop_y;
            cfg_crop_width = crop_w;
            cfg_crop_height = crop_h;
            cfg_dst_width = dst_w;
            cfg_dst_height = dst_h;
            cfg_image_width = image_w;
            cfg_image_height = image_h;
            cfg_angle = angle;
            cfg_flip_x = flip_x;
            cfg_flip_y = flip_y;
            cfg_start = 1'b1;
            @(negedge clk);
            cfg_start = 1'b0;
        end
    endtask

    task automatic wait_launch;
        integer guard;
        begin
            guard = 0;
            while (!walker_start && guard < 300) begin
                @(negedge clk);
                guard = guard + 1;
            end
            check_true(guard < 300, "geometry configuration launches walker");
            check_true(config_done && !config_error,
                       "geometry configuration completes without error");
            @(negedge clk);
        end
    endtask

    task automatic check_matrix;
        input integer origin_x;
        input integer origin_y;
        input integer pixel_x;
        input integer pixel_y;
        input integer row_x;
        input integer row_y;
        input integer tolerance;
        begin
            check_true(abs_diff($signed(walker_origin_x), origin_x) <= tolerance,
                       "origin x matches expected Q16.16 value");
            check_true(abs_diff($signed(walker_origin_y), origin_y) <= tolerance,
                       "origin y matches expected Q16.16 value");
            check_true(abs_diff($signed(walker_pixel_step_x), pixel_x) <= tolerance,
                       "pixel step x matches expected Q16.16 value");
            check_true(abs_diff($signed(walker_pixel_step_y), pixel_y) <= tolerance,
                       "pixel step y matches expected Q16.16 value");
            check_true(abs_diff($signed(walker_row_step_x), row_x) <= tolerance,
                       "row step x matches expected Q16.16 value");
            check_true(abs_diff($signed(walker_row_step_y), row_y) <= tolerance,
                       "row step y matches expected Q16.16 value");
        end
    endtask

    task automatic drain_rotate_90;
        integer accepted;
        integer guard;
        integer expected_x;
        integer expected_y;
        begin
            accepted = 0;
            guard = 0;
            while ((accepted < 12) && (guard < 200)) begin
                coord_ready = (guard % 5) != 2;
                #1;
                if (coord_valid && coord_ready) begin
                    expected_x = accepted % 3;
                    expected_y = accepted / 3;
                    check_true(dst_x == expected_x && dst_y == expected_y,
                               "rotate90 destination raster order");
                    check_true($signed(src_x) == expected_y &&
                               $signed(src_y) == 2 - expected_x,
                               "rotate90 source coordinate");
                    check_true(src_x_frac == 0 && src_y_frac == 0,
                               "rotate90 exact orthogonal fraction");
                    check_true(src_in_bounds,
                               "rotate90 source coordinate remains in crop");
                    check_true(coord_sof == (accepted == 0),
                               "rotate90 SOF marker");
                    check_true(coord_eof == (accepted == 11),
                               "rotate90 EOF marker");
                    accepted = accepted + 1;
                end
                guard = guard + 1;
                @(negedge clk);
            end
            coord_ready = 1'b0;
            check_true(accepted == 12, "rotate90 walker drains all coordinates");
            check_true(walker_done && !walker_error,
                       "rotate90 walker completes without error");
        end
    endtask

    task automatic drain_current;
        integer guard;
        begin
            guard = 0;
            coord_ready = 1'b1;
            while (!walker_done && guard < 1000) begin
                @(negedge clk);
                guard = guard + 1;
            end
            coord_ready = 1'b0;
            check_true(guard < 1000 && !walker_error,
                       "configured walker completes");
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        cfg_start = 1'b0;
        cfg_src_width = 0;
        cfg_src_height = 0;
        cfg_crop_x = 0;
        cfg_crop_y = 0;
        cfg_crop_width = 0;
        cfg_crop_height = 0;
        cfg_dst_width = 0;
        cfg_dst_height = 0;
        cfg_image_width = 0;
        cfg_image_height = 0;
        cfg_angle = 0;
        cfg_flip_x = 1'b0;
        cfg_flip_y = 1'b0;
        coord_ready = 1'b0;
        checks = 0;
        failures = 0;
        divider_start_count = 0;
        rom_capture_count = 0;
        divider_before = 0;
        rom_before = 0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;

        start_config(10, 8, 2, 1, 5, 3, 5, 3, 5, 3, 0, 0, 0);
        wait_launch();
        check_matrix(2 <<< 16, 1 <<< 16,
                     1 <<< 16, 0, 0, 1 <<< 16, 0);
        drain_current();

        divider_before = divider_start_count;
        rom_before = rom_capture_count;
        start_config(10, 8, 2, 1, 5, 3, 5, 3, 5, 3, 0, 0, 0);
        check_true(walker_start && config_done && !config_busy,
                   "identical frame configuration launches immediately");
        wait_launch();
        check_matrix(2 <<< 16, 1 <<< 16,
                     1 <<< 16, 0, 0, 1 <<< 16, 0);
        drain_current();
        check_true(divider_start_count == divider_before &&
                   rom_capture_count == rom_before,
                   "identical frame reuses ROM and divider coefficients");

        // Rotation keeps the original scale and clips against the unchanged
        // canvas.  It must not resize the rotated bounding box to fit.
        start_config(4, 3, 0, 0, 4, 3, 4, 3, 4, 3, 90, 0, 0);
        wait_launch();
        check_matrix(1 <<< 15, 5 <<< 15,
                     0, -(1 <<< 16), 1 <<< 16, 0, 0);
        drain_current();
        check_true(divider_start_count == divider_before + 2 &&
                   rom_capture_count == rom_before + 1,
                   "changed angle recomputes matrix once");

        start_config(10, 8, 2, 1, 5, 3, 5, 3, 5, 3, 0, 1, 1);
        wait_launch();
        check_matrix(6 <<< 16, 3 <<< 16,
                     -(1 <<< 16), 0, 0, -(1 <<< 16), 0);
        drain_current();

        start_config(8, 6, 0, 0, 8, 6, 4, 3, 4, 3, 0, 0, 0);
        wait_launch();
        check_matrix(1, 0, 152917, 0, 0, 163840, 2);
        drain_current();

        // A 45-degree transform remains a pure rotation.  The four step
        // components use one common magnitude, so no parallelogram distortion
        // or implicit fit-to-screen shrink is permitted.
        start_config(5, 5, 0, 0, 5, 5, 5, 5, 5, 5, 45, 0, 0);
        wait_launch();
        check_matrix(-54292, 131072,
                     46341, -46341, 46341, 46341, 8);
        drain_current();

        start_config(8, 6, 0, 0, 8, 6, 4, 3, 4, 3, 360, 0, 0);
        #1;
        check_true(config_done && config_error && !config_busy,
                   "out-of-range angle is rejected without launching walker");

        divider_before = divider_start_count;
        rom_before = rom_capture_count;
        start_config(5, 5, 0, 0, 5, 5, 5, 5, 5, 5, 45, 0, 0);
        check_true(walker_start && config_done && !config_error,
                   "invalid request does not poison previous valid matrix");
        wait_launch();
        drain_current();
        check_true(divider_start_count == divider_before &&
                   rom_capture_count == rom_before,
                   "valid cached matrix survives an invalid request");

        // A 5x6 image on an 8x6 canvas changes only the vertical ratio.
        // The two axes must not collapse to the larger inverse scale.
        start_config(10, 8, 2, 1, 5, 3, 8, 6, 5, 6, 0, 0, 0);
        wait_launch();
        check_matrix(1 <<< 16, 1 <<< 16,
                     1 <<< 16, 0, 0, 26214, 2);
        drain_current();

        // Scale the source axes first, then rotate with one inverse walk.
        start_config(10, 8, 2, 1, 5, 3, 8, 6, 5, 6, 90, 0, 0);
        wait_launch();
        check_matrix(98304, 209714,
                     0, -26214, 1 <<< 16, 0, 2);
        drain_current();

        start_config(10, 8, 2, 1, 5, 3, 8, 6, 5, 6, 45, 0, 0);
        wait_launch();
        check_matrix(7269, 140340,
                     46341, -18536, 46341, 18536, 3);
        drain_current();

        divider_before = divider_start_count;
        rom_before = rom_capture_count;
        start_config(10, 8, 2, 1, 5, 3, 8, 6, 5, 6, 45, 0, 0);
        wait_launch();
        drain_current();
        check_true(divider_start_count == divider_before &&
                   rom_capture_count == rom_before,
                   "scaled rotated frame reuses cached matrix");

        start_config(10, 8, 2, 1, 5, 3, 8, 6, 2, 6, 0, 0, 0);
        #1;
        check_true(config_done && config_error && !config_busy,
                   "image narrower than half the crop is rejected");

        if (failures == 0)
            $display("GEOMETRY_CONFIG_PASS checks=%0d", checks);
        else
            $fatal(1, "GEOMETRY_CONFIG_FAIL checks=%0d failures=%0d",
                   checks, failures);
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "Geometry configuration timeout");
    end

endmodule
