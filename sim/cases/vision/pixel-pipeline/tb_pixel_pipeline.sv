`timescale 1ns/1ps

module tb_pixel_pipeline;
    localparam integer H_ACTIVE = 32;
    localparam integer V_ACTIVE = 8;
    localparam integer FRAME_PIXELS = H_ACTIVE * V_ACTIVE;
    localparam integer FRAME_BEATS = FRAME_PIXELS / 16;

    reg clk_r;
    reg rst_n_r;
    reg [257:0] stream_data_r;
    reg stream_valid_r;
    wire stream_ready_w;
    wire [257:0] output_data_w;
    wire output_valid_w;
    reg output_ready_r;

    reg cfg_commit_r;
    reg cfg_enable_r;
    reg cfg_grayscale_r;
    reg cfg_threshold_enable_r;
    reg cfg_invert_r;
    reg signed [8:0] cfg_brightness_r;
    reg [8:0] cfg_contrast_r;
    reg [7:0] cfg_threshold_r;
    reg cfg_spatial_enable_r;
    reg [2:0] cfg_spatial_mode_r;
    reg [7:0] cfg_spatial_threshold_r;
    wire cfg_pending_w;
    wire [31:0] frame_count_w;
    wire [31:0] unpack_frame_count_w;
    wire [31:0] point_frame_count_w;
    wire [31:0] spatial_frame_count_w;

    integer checks;
    integer failures;
    integer output_pixel_count;
    integer point_pair_count;
    integer expected_mode;
    integer expected_spatial_mode;
    integer gray_file;
    integer threshold_file;
    integer sobel_file;
    integer mean_file;
    integer gaussian_file;
    integer sharpen_file;
    integer erode_file;
    integer dilate_file;
    integer lane;
    integer index;
    reg [15:0] actual_pixel_r;
    reg [15:0] expected_pixel_r;
    reg [23:0] actual_rgb888_r;
    reg [31:0] lfsr_r;
    string image_output_dir;

    initial clk_r = 1'b0;
    always #5 clk_r = ~clk_r;

    function automatic [15:0] source_pixel;
        input integer pixel_index;
        integer x;
        integer y;
        integer red;
        integer green;
        integer blue;
        begin
            x = pixel_index % H_ACTIVE;
            y = pixel_index / H_ACTIVE;
            red = (x * 31) / (H_ACTIVE - 1);
            green = (y * 63) / (V_ACTIVE - 1);
            blue = ((x + y) * 31) / (H_ACTIVE + V_ACTIVE - 2);
            source_pixel = {red[4:0], green[5:0], blue[4:0]};
        end
    endfunction

    function automatic integer expand5;
        input integer value;
        begin
            expand5 = ((value & 31) << 3) | ((value >> 2) & 7);
        end
    endfunction

    function automatic integer expand6;
        input integer value;
        begin
            expand6 = ((value & 63) << 2) | ((value >> 4) & 3);
        end
    endfunction

    function automatic integer clamp8;
        input integer value;
        begin
            if (value < 0)
                clamp8 = 0;
            else if (value > 255)
                clamp8 = 255;
            else
                clamp8 = value;
        end
    endfunction

    function automatic integer adjust;
        input integer value;
        input integer brightness;
        input integer contrast;
        integer product;
        begin
            product = (value - 128) * contrast;
            adjust = clamp8((product >>> 8) + 128 + brightness);
        end
    endfunction

    function automatic [15:0] golden_pixel;
        input [15:0] pixel;
        input integer mode;
        integer red;
        integer green;
        integer blue;
        integer gray;
        integer brightness;
        integer contrast;
        integer threshold;
        integer white;
        begin
            if (mode == 0) begin
                golden_pixel = pixel;
            end else begin
                brightness = (mode == 1) ? 16 :
                    ((mode == 3) ? -32 :
                    ((mode == 4) ? 255 : ((mode == 5) ? -256 : 0)));
                contrast = (mode == 1) ? 320 :
                    ((mode == 3) ? 192 :
                    ((mode == 4) ? 511 : ((mode == 5) ? 0 : 256)));
                threshold = 100;
                red = adjust(expand5(pixel[15:11]), brightness, contrast);
                green = adjust(expand6(pixel[10:5]), brightness, contrast);
                blue = adjust(expand5(pixel[4:0]), brightness, contrast);
                gray = (red * 77 + green * 150 + blue * 29 + 128) >> 8;
                if (mode == 2 || mode == 6) begin
                    white = (gray >= threshold) ^ (mode == 6);
                    golden_pixel = white ? 16'hffff : 16'h0000;
                end else if (mode == 1) begin
                    golden_pixel = {
                        gray[7:3], gray[7:2], gray[7:3]
                    };
                end else begin
                    golden_pixel = {
                        red[7:3], green[7:2], blue[7:3]
                    };
                end
            end
        end
    endfunction

    function automatic [23:0] rgb565_to_rgb888;
        input [15:0] pixel;
        reg [7:0] red;
        reg [7:0] green;
        reg [7:0] blue;
        begin
            red = {pixel[15:11], pixel[15:13]};
            green = {pixel[10:5], pixel[10:9]};
            blue = {pixel[4:0], pixel[4:2]};
            rgb565_to_rgb888 = {red, green, blue};
        end
    endfunction

    function automatic integer source_gray;
        input integer x;
        input integer y;
        reg [15:0] pixel;
        integer red;
        integer green;
        integer blue;
        begin
            if (x < 0 || x >= H_ACTIVE || y < 0 || y >= V_ACTIVE) begin
                source_gray = 0;
            end else begin
                pixel = source_pixel(y * H_ACTIVE + x);
                red = expand5(pixel[15:11]);
                green = expand6(pixel[10:5]);
                blue = expand5(pixel[4:0]);
                source_gray = (red * 77 + green * 150 + blue * 29 + 128)
                    >> 8;
            end
        end
    endfunction

    function automatic [15:0] spatial_golden;
        input integer pixel_index;
        input integer mode;
        input integer threshold;
        integer x;
        integer y;
        integer p00;
        integer p01;
        integer p02;
        integer p10;
        integer p11;
        integer p12;
        integer p20;
        integer p21;
        integer p22;
        integer gx;
        integer gy;
        integer value;
        integer white;
        begin
            x = pixel_index % H_ACTIVE;
            y = pixel_index / H_ACTIVE;
            p00 = source_gray(x - 1, y - 1);
            p01 = source_gray(x,     y - 1);
            p02 = source_gray(x + 1, y - 1);
            p10 = source_gray(x - 1, y);
            p11 = source_gray(x,     y);
            p12 = source_gray(x + 1, y);
            p20 = source_gray(x - 1, y + 1);
            p21 = source_gray(x,     y + 1);
            p22 = source_gray(x + 1, y + 1);
            value = p11;
            if (mode == 1) begin
                gx = -p00 + p02 - 2*p10 + 2*p12 - p20 + p22;
                gy = -p00 - 2*p01 - p02 + p20 + 2*p21 + p22;
                if (gx < 0)
                    gx = -gx;
                if (gy < 0)
                    gy = -gy;
                value = clamp8(gx + gy);
            end else if (mode == 2) begin
                value = (p00 + p01 + p02 + p10 + p11 + p12 +
                    p20 + p21 + p22 + 4) / 9;
            end else if (mode == 3) begin
                value = (p00 + 2*p01 + p02 + 2*p10 + 4*p11 +
                    2*p12 + p20 + 2*p21 + p22 + 8) >> 4;
            end else if (mode == 4) begin
                value = clamp8(5*p11 - p01 - p10 - p12 - p21);
            end else if (mode == 5) begin
                white = (p00 >= threshold) && (p01 >= threshold) &&
                    (p02 >= threshold) && (p10 >= threshold) &&
                    (p11 >= threshold) && (p12 >= threshold) &&
                    (p20 >= threshold) && (p21 >= threshold) &&
                    (p22 >= threshold);
                value = white ? 255 : 0;
            end else if (mode == 6) begin
                white = (p00 >= threshold) || (p01 >= threshold) ||
                    (p02 >= threshold) || (p10 >= threshold) ||
                    (p11 >= threshold) || (p12 >= threshold) ||
                    (p20 >= threshold) || (p21 >= threshold) ||
                    (p22 >= threshold);
                value = white ? 255 : 0;
            end
            spatial_golden = {value[7:3], value[7:2], value[7:3]};
        end
    endfunction

    task automatic check_true;
        input condition;
        input [8*120-1:0] message;
        begin
            checks = checks + 1;
            if (!condition) begin
                failures = failures + 1;
                $display("FAIL: %0s", message);
            end
        end
    endtask

    task automatic configure_mode;
        input integer mode;
        begin
            @(negedge clk_r);
            cfg_enable_r = mode != 0;
            cfg_grayscale_r = mode == 1;
            cfg_threshold_enable_r = (mode == 2) || (mode == 6);
            cfg_invert_r = mode == 6;
            cfg_brightness_r = (mode == 1) ? 9'sd16 :
                ((mode == 3) ? -9'sd32 :
                ((mode == 4) ? 9'sd255 :
                ((mode == 5) ? 9'sh100 : 9'sd0)));
            cfg_contrast_r = (mode == 1) ? 9'd320 :
                ((mode == 3) ? 9'd192 :
                ((mode == 4) ? 9'd511 :
                ((mode == 5) ? 9'd0 : 9'd256)));
            cfg_threshold_r = 8'd100;
            cfg_spatial_enable_r = 1'b0;
            cfg_spatial_mode_r = 3'b0;
            cfg_spatial_threshold_r = 8'd100;
            cfg_commit_r = 1'b1;
            @(negedge clk_r);
            cfg_commit_r = 1'b0;
            expected_mode = mode;
            expected_spatial_mode = 0;
            check_true(cfg_pending_w,
                "configuration waits for the next frame boundary");
        end
    endtask

    task automatic configure_spatial_mode;
        input integer mode;
        begin
            @(negedge clk_r);
            cfg_enable_r = 1'b0;
            cfg_grayscale_r = 1'b0;
            cfg_threshold_enable_r = 1'b0;
            cfg_invert_r = 1'b0;
            cfg_brightness_r = 9'sd0;
            cfg_contrast_r = 9'd256;
            cfg_threshold_r = 8'd100;
            cfg_spatial_enable_r = mode != 0;
            cfg_spatial_mode_r = mode[2:0];
            cfg_spatial_threshold_r = 8'd100;
            cfg_commit_r = 1'b1;
            @(negedge clk_r);
            cfg_commit_r = 1'b0;
            expected_mode = 0;
            expected_spatial_mode = mode;
            check_true(cfg_pending_w,
                "spatial configuration waits for the next frame boundary");
        end
    endtask

    task automatic send_frame;
        integer beat;
        integer beat_lane;
        reg [255:0] pixels;
        begin
            for (beat = 0; beat < FRAME_BEATS; beat = beat + 1) begin
                pixels = 256'b0;
                for (beat_lane = 0; beat_lane < 16;
                     beat_lane = beat_lane + 1)
                    pixels[beat_lane*16 +: 16] =
                        source_pixel(beat * 16 + beat_lane);

                @(negedge clk_r);
                stream_data_r = {
                    beat == 0, beat == FRAME_BEATS - 1, pixels
                };
                stream_valid_r = 1'b1;
                while (!stream_ready_w)
                    @(negedge clk_r);
                @(negedge clk_r);
                stream_valid_r = 1'b0;
            end
        end
    endtask

    task automatic wait_for_frame;
        input integer count;
        integer timeout;
        begin
            timeout = 0;
            while ((frame_count_w < count) && (timeout < 100000)) begin
                @(posedge clk_r);
                timeout = timeout + 1;
            end
            check_true(frame_count_w >= count,
                "processed frame reaches output");
        end
    endtask

    edrv32_pixel_pipeline #(
        .H_ACTIVE(H_ACTIVE)
    ) u_dut (
        .clk_i(clk_r), .rst_n_i(rst_n_r),
        .stream_data_i(stream_data_r),
        .stream_valid_i(stream_valid_r),
        .stream_ready_o(stream_ready_w),
        .stream_data_o(output_data_w),
        .stream_valid_o(output_valid_w),
        .stream_ready_i(output_ready_r),
        .cfg_commit_i(cfg_commit_r),
        .cfg_enable_i(cfg_enable_r),
        .cfg_grayscale_i(cfg_grayscale_r),
        .cfg_threshold_enable_i(cfg_threshold_enable_r),
        .cfg_invert_i(cfg_invert_r),
        .cfg_brightness_i(cfg_brightness_r),
        .cfg_contrast_i(cfg_contrast_r),
        .cfg_threshold_i(cfg_threshold_r),
        .cfg_spatial_enable_i(cfg_spatial_enable_r),
        .cfg_spatial_mode_i(cfg_spatial_mode_r),
        .cfg_spatial_threshold_i(cfg_spatial_threshold_r),
        .cfg_pending_o(cfg_pending_w),
        .frame_count_o(frame_count_w),
        .unpack_frame_count_o(unpack_frame_count_w),
        .point_frame_count_o(point_frame_count_w),
        .spatial_frame_count_o(spatial_frame_count_w)
    );

    always @(posedge clk_r or negedge rst_n_r) begin
        if (!rst_n_r) begin
            lfsr_r <= 32'h1ace_b00c;
            output_ready_r <= 1'b0;
        end else begin
            lfsr_r <= {lfsr_r[30:0],
                lfsr_r[31] ^ lfsr_r[21] ^ lfsr_r[1] ^ lfsr_r[0]};
            output_ready_r <= lfsr_r[0] | lfsr_r[3];
        end
    end

    always @(posedge clk_r) begin
        if (!rst_n_r) begin
            output_pixel_count = 0;
        end else if (output_valid_w && output_ready_r) begin
            check_true(output_data_w[257] == (output_pixel_count == 0),
                "SOF metadata is preserved");
            check_true(output_data_w[256] ==
                (output_pixel_count == FRAME_PIXELS - 16),
                "EOF metadata is preserved");

            for (lane = 0; lane < 16; lane = lane + 1) begin
                index = output_pixel_count + lane;
                actual_pixel_r = output_data_w[lane*16 +: 16];
                if (expected_spatial_mode == 0)
                    expected_pixel_r = golden_pixel(source_pixel(index),
                                                     expected_mode);
                else
                    expected_pixel_r = spatial_golden(index,
                        expected_spatial_mode, 100);
                check_true(actual_pixel_r == expected_pixel_r,
                    "processed RGB565 pixel matches golden result");
                actual_rgb888_r = rgb565_to_rgb888(actual_pixel_r);

                if (expected_mode == 1)
                    $fwrite(gray_file, "%0d %0d %0d\n",
                        actual_rgb888_r[23:16], actual_rgb888_r[15:8],
                        actual_rgb888_r[7:0]);
                if (expected_mode == 2)
                    $fwrite(threshold_file, "%0d %0d %0d\n",
                        actual_rgb888_r[23:16], actual_rgb888_r[15:8],
                        actual_rgb888_r[7:0]);
                if (expected_spatial_mode == 1)
                    $fwrite(sobel_file, "%0d %0d %0d\n",
                        actual_rgb888_r[23:16], actual_rgb888_r[15:8],
                        actual_rgb888_r[7:0]);
                if (expected_spatial_mode == 2)
                    $fwrite(mean_file, "%0d %0d %0d\n",
                        actual_rgb888_r[23:16], actual_rgb888_r[15:8],
                        actual_rgb888_r[7:0]);
                if (expected_spatial_mode == 3)
                    $fwrite(gaussian_file, "%0d %0d %0d\n",
                        actual_rgb888_r[23:16], actual_rgb888_r[15:8],
                        actual_rgb888_r[7:0]);
                if (expected_spatial_mode == 4)
                    $fwrite(sharpen_file, "%0d %0d %0d\n",
                        actual_rgb888_r[23:16], actual_rgb888_r[15:8],
                        actual_rgb888_r[7:0]);
                if (expected_spatial_mode == 5)
                    $fwrite(erode_file, "%0d %0d %0d\n",
                        actual_rgb888_r[23:16], actual_rgb888_r[15:8],
                        actual_rgb888_r[7:0]);
                if (expected_spatial_mode == 6)
                    $fwrite(dilate_file, "%0d %0d %0d\n",
                        actual_rgb888_r[23:16], actual_rgb888_r[15:8],
                        actual_rgb888_r[7:0]);
            end

            if (output_pixel_count == FRAME_PIXELS - 16)
                output_pixel_count = 0;
            else
                output_pixel_count = output_pixel_count + 16;
        end
    end

    always @(posedge clk_r) begin
        if (!rst_n_r) begin
            point_pair_count = 0;
        end else if (u_dut.point_valid_w && u_dut.point_ready_w) begin
            check_true(u_dut.point_sol_w ==
                ((point_pair_count % (H_ACTIVE / 2)) == 0),
                "SOL is derived from fixed frame geometry");
            check_true(u_dut.point_eol_w ==
                ((point_pair_count % (H_ACTIVE / 2)) ==
                 (H_ACTIVE / 2) - 1),
                "EOL is derived from fixed frame geometry");
            if (point_pair_count == (FRAME_PIXELS / 2) - 1)
                point_pair_count = 0;
            else
                point_pair_count = point_pair_count + 1;
        end
    end

    initial begin
        checks = 0;
        failures = 0;
        output_pixel_count = 0;
        point_pair_count = 0;
        expected_mode = 0;
        expected_spatial_mode = 0;
        rst_n_r = 1'b0;
        stream_data_r = 258'b0;
        stream_valid_r = 1'b0;
        cfg_commit_r = 1'b0;
        cfg_enable_r = 1'b0;
        cfg_grayscale_r = 1'b0;
        cfg_threshold_enable_r = 1'b0;
        cfg_invert_r = 1'b0;
        cfg_brightness_r = 9'sd0;
        cfg_contrast_r = 9'd256;
        cfg_threshold_r = 8'd128;
        cfg_spatial_enable_r = 1'b0;
        cfg_spatial_mode_r = 3'b0;
        cfg_spatial_threshold_r = 8'd128;

        if (!$value$plusargs("IMAGE_OUT_DIR=%s", image_output_dir))
            image_output_dir = "sim/build/cases/vision/pixel-pipeline";
        gray_file = $fopen({image_output_dir, "/pixel_grayscale.ppm"}, "w");
        threshold_file = $fopen(
            {image_output_dir, "/pixel_threshold.ppm"}, "w");
        sobel_file = $fopen({image_output_dir, "/pixel_sobel.ppm"}, "w");
        mean_file = $fopen({image_output_dir, "/pixel_mean.ppm"}, "w");
        gaussian_file = $fopen(
            {image_output_dir, "/pixel_gaussian.ppm"}, "w");
        sharpen_file = $fopen(
            {image_output_dir, "/pixel_sharpen.ppm"}, "w");
        erode_file = $fopen({image_output_dir, "/pixel_erode.ppm"}, "w");
        dilate_file = $fopen(
            {image_output_dir, "/pixel_dilate.ppm"}, "w");
        check_true(gray_file != 0, "grayscale PPM opens");
        check_true(threshold_file != 0, "threshold PPM opens");
        check_true(sobel_file != 0 && mean_file != 0 &&
            gaussian_file != 0 && sharpen_file != 0 &&
            erode_file != 0 && dilate_file != 0,
            "spatial-filter PPM files open");
        $fwrite(gray_file, "P3\n%0d %0d\n255\n", H_ACTIVE, V_ACTIVE);
        $fwrite(threshold_file, "P3\n%0d %0d\n255\n",
            H_ACTIVE, V_ACTIVE);
        $fwrite(sobel_file, "P3\n%0d %0d\n255\n", H_ACTIVE, V_ACTIVE);
        $fwrite(mean_file, "P3\n%0d %0d\n255\n", H_ACTIVE, V_ACTIVE);
        $fwrite(gaussian_file, "P3\n%0d %0d\n255\n",
            H_ACTIVE, V_ACTIVE);
        $fwrite(sharpen_file, "P3\n%0d %0d\n255\n",
            H_ACTIVE, V_ACTIVE);
        $fwrite(erode_file, "P3\n%0d %0d\n255\n", H_ACTIVE, V_ACTIVE);
        $fwrite(dilate_file, "P3\n%0d %0d\n255\n",
            H_ACTIVE, V_ACTIVE);

        repeat (5) @(posedge clk_r);
        rst_n_r = 1'b1;
        repeat (3) @(posedge clk_r);

        configure_mode(0);
        send_frame();
        wait_for_frame(1);
        check_true(!cfg_pending_w, "bypass configuration commits at SOF");

        configure_mode(1);
        send_frame();
        wait_for_frame(2);

        configure_mode(2);
        send_frame();
        wait_for_frame(3);

        configure_mode(3);
        send_frame();
        wait_for_frame(4);

        configure_mode(4);
        send_frame();
        wait_for_frame(5);

        configure_mode(5);
        send_frame();
        wait_for_frame(6);

        configure_mode(6);
        send_frame();
        wait_for_frame(7);

        configure_spatial_mode(1);
        send_frame();
        wait_for_frame(8);
        configure_spatial_mode(2);
        send_frame();
        wait_for_frame(9);
        configure_spatial_mode(3);
        send_frame();
        wait_for_frame(10);
        configure_spatial_mode(4);
        send_frame();
        wait_for_frame(11);
        configure_spatial_mode(5);
        send_frame();
        wait_for_frame(12);
        configure_spatial_mode(6);
        send_frame();
        wait_for_frame(13);

        $fclose(gray_file);
        $fclose(threshold_file);
        $fclose(sobel_file);
        $fclose(mean_file);
        $fclose(gaussian_file);
        $fclose(sharpen_file);
        $fclose(erode_file);
        $fclose(dilate_file);

        check_true(unpack_frame_count_w == 13 &&
            point_frame_count_w == 13 &&
            spatial_frame_count_w == 13,
            "EOF monitors agree at every pixel-pipeline stage");

        if (failures == 0)
            $display("PIXEL_PIPELINE_PASS checks=%0d frames=%0d",
                checks, frame_count_w);
        else
            $display("PIXEL_PIPELINE_FAIL checks=%0d failures=%0d",
                checks, failures);
        $finish;
    end

endmodule
