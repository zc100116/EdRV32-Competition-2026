`timescale 1ns/1ps

module tb_geometry_bilinear;
    localparam integer SAMPLE_COUNT = 204;

    reg clk;
    reg rst_n;
    reg sample_valid;
    wire sample_ready;
    reg [15:0] sample_p00;
    reg [15:0] sample_p10;
    reg [15:0] sample_p01;
    reg [15:0] sample_p11;
    reg [15:0] sample_frac_x;
    reg [15:0] sample_frac_y;
    reg sample_in_bounds;
    reg [15:0] sample_fill_pixel;
    reg [15:0] sample_dst_x;
    reg [15:0] sample_dst_y;
    reg sample_sof;
    reg sample_eol;
    reg sample_eof;

    wire pixel_valid;
    reg pixel_ready;
    wire [15:0] pixel_data;
    wire [15:0] pixel_dst_x;
    wire [15:0] pixel_dst_y;
    wire pixel_sof;
    wire pixel_eol;
    wire pixel_eof;

    reg [15:0] expected_pixel_r [0:SAMPLE_COUNT-1];
    reg [15:0] expected_x_r [0:SAMPLE_COUNT-1];
    reg [15:0] expected_y_r [0:SAMPLE_COUNT-1];
    reg expected_sof_r [0:SAMPLE_COUNT-1];
    reg expected_eol_r [0:SAMPLE_COUNT-1];
    reg expected_eof_r [0:SAMPLE_COUNT-1];
    integer expected_write;
    integer expected_read;
    integer checks;
    integer failures;
    integer cycle_count;
    integer random_seed;
    reg stalled_r;
    reg [50:0] stalled_payload_r;

    always #5 clk = ~clk;

    edrv32_geometry_bilinear u_dut (
        .clk_i(clk), .rst_n_i(rst_n),
        .sample_valid_i(sample_valid), .sample_ready_o(sample_ready),
        .sample_p00_i(sample_p00), .sample_p10_i(sample_p10),
        .sample_p01_i(sample_p01), .sample_p11_i(sample_p11),
        .sample_frac_x_i(sample_frac_x), .sample_frac_y_i(sample_frac_y),
        .sample_in_bounds_i(sample_in_bounds),
        .sample_fill_pixel_i(sample_fill_pixel),
        .sample_dst_x_i(sample_dst_x), .sample_dst_y_i(sample_dst_y),
        .sample_sof_i(sample_sof), .sample_eol_i(sample_eol),
        .sample_eof_i(sample_eof),
        .pixel_valid_o(pixel_valid), .pixel_ready_i(pixel_ready),
        .pixel_data_o(pixel_data),
        .pixel_dst_x_o(pixel_dst_x), .pixel_dst_y_o(pixel_dst_y),
        .pixel_sof_o(pixel_sof), .pixel_eol_o(pixel_eol),
        .pixel_eof_o(pixel_eof)
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

    function automatic integer expand5;
        input integer value_i;
        begin
            expand5 = ((value_i & 31) << 3) | ((value_i >> 2) & 7);
        end
    endfunction

    function automatic integer expand6;
        input integer value_i;
        begin
            expand6 = ((value_i & 63) << 2) | ((value_i >> 4) & 3);
        end
    endfunction

    function automatic integer channel5;
        input [15:0] p00_i;
        input [15:0] p10_i;
        input [15:0] p01_i;
        input [15:0] p11_i;
        input [15:0] frac_x_i;
        input [15:0] frac_y_i;
        input integer shift_i;
        longint signed a;
        longint signed b;
        longint signed c;
        longint signed d;
        longint signed top;
        longint signed bottom;
        longint signed value;
        begin
            a = expand5((p00_i >> shift_i) & 31);
            b = expand5((p10_i >> shift_i) & 31);
            c = expand5((p01_i >> shift_i) & 31);
            d = expand5((p11_i >> shift_i) & 31);
            top = a * 65536 + (b - a) * frac_x_i;
            bottom = c * 65536 + (d - c) * frac_x_i;
            value = top * 65536 + (bottom - top) * frac_y_i +
                64'sd2147483648;
            channel5 = (value >>> 32) >>> 3;
        end
    endfunction

    function automatic integer channel6;
        input [15:0] p00_i;
        input [15:0] p10_i;
        input [15:0] p01_i;
        input [15:0] p11_i;
        input [15:0] frac_x_i;
        input [15:0] frac_y_i;
        longint signed a;
        longint signed b;
        longint signed c;
        longint signed d;
        longint signed top;
        longint signed bottom;
        longint signed value;
        begin
            a = expand6((p00_i >> 5) & 63);
            b = expand6((p10_i >> 5) & 63);
            c = expand6((p01_i >> 5) & 63);
            d = expand6((p11_i >> 5) & 63);
            top = a * 65536 + (b - a) * frac_x_i;
            bottom = c * 65536 + (d - c) * frac_x_i;
            value = top * 65536 + (bottom - top) * frac_y_i +
                64'sd2147483648;
            channel6 = (value >>> 32) >>> 2;
        end
    endfunction

    function automatic [15:0] reference_pixel;
        input [15:0] p00_i;
        input [15:0] p10_i;
        input [15:0] p01_i;
        input [15:0] p11_i;
        input [15:0] frac_x_i;
        input [15:0] frac_y_i;
        integer red_v;
        integer green_v;
        integer blue_v;
        begin
            red_v = channel5(p00_i, p10_i, p01_i, p11_i,
                             frac_x_i, frac_y_i, 11);
            green_v = channel6(p00_i, p10_i, p01_i, p11_i,
                               frac_x_i, frac_y_i);
            blue_v = channel5(p00_i, p10_i, p01_i, p11_i,
                              frac_x_i, frac_y_i, 0);
            reference_pixel = {red_v[4:0], green_v[5:0], blue_v[4:0]};
        end
    endfunction

    task automatic enqueue_expected;
        begin
            expected_pixel_r[expected_write] = sample_in_bounds ?
                reference_pixel(sample_p00, sample_p10, sample_p01,
                                sample_p11, sample_frac_x, sample_frac_y) :
                sample_fill_pixel;
            expected_x_r[expected_write] = sample_dst_x;
            expected_y_r[expected_write] = sample_dst_y;
            expected_sof_r[expected_write] = sample_sof;
            expected_eol_r[expected_write] = sample_eol;
            expected_eof_r[expected_write] = sample_eof;
            expected_write = expected_write + 1;
        end
    endtask

    always @(negedge clk) begin
        if (!rst_n) begin
            pixel_ready = 1'b0;
        end else begin
            cycle_count = cycle_count + 1;
            pixel_ready = ((cycle_count % 11) != 3) &&
                          ((cycle_count % 11) != 4) &&
                          ((cycle_count % 37) < 31);
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            expected_read <= 0;
            stalled_r <= 1'b0;
        end else begin
            if (stalled_r)
                check_true({pixel_data, pixel_dst_x, pixel_dst_y,
                            pixel_sof, pixel_eol, pixel_eof} == stalled_payload_r,
                           "bilinear output remains stable under backpressure");

            stalled_r <= pixel_valid && !pixel_ready;
            if (pixel_valid && !pixel_ready)
                stalled_payload_r <= {pixel_data, pixel_dst_x, pixel_dst_y,
                                      pixel_sof, pixel_eol, pixel_eof};

            if (pixel_valid && pixel_ready) begin
                check_true(expected_read < expected_write,
                           "bilinear output has an expected transaction");
                check_true(pixel_data == expected_pixel_r[expected_read],
                           "bilinear RGB565 result matches software reference");
                check_true(pixel_dst_x == expected_x_r[expected_read] &&
                           pixel_dst_y == expected_y_r[expected_read],
                           "bilinear destination metadata remains ordered");
                check_true(pixel_sof == expected_sof_r[expected_read] &&
                           pixel_eol == expected_eol_r[expected_read] &&
                           pixel_eof == expected_eof_r[expected_read],
                           "bilinear frame markers remain ordered");
                expected_read <= expected_read + 1;
            end
        end
    end

    task automatic send_current;
        begin
            sample_valid = 1'b1;
            while (!sample_ready)
                @(negedge clk);
            enqueue_expected();
            @(negedge clk);
        end
    endtask

    integer sample_i;
    integer guard;
    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        sample_valid = 1'b0;
        sample_p00 = 16'b0;
        sample_p10 = 16'b0;
        sample_p01 = 16'b0;
        sample_p11 = 16'b0;
        sample_frac_x = 16'b0;
        sample_frac_y = 16'b0;
        sample_in_bounds = 1'b1;
        sample_fill_pixel = 16'b0;
        sample_dst_x = 16'b0;
        sample_dst_y = 16'b0;
        sample_sof = 1'b0;
        sample_eol = 1'b0;
        sample_eof = 1'b0;
        pixel_ready = 1'b0;
        expected_write = 0;
        expected_read = 0;
        checks = 0;
        failures = 0;
        cycle_count = 0;
        random_seed = 32'h1357_2468;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        sample_p00 = 16'hf800;
        sample_p10 = 16'h07e0;
        sample_p01 = 16'h001f;
        sample_p11 = 16'hffff;
        sample_frac_x = 16'h0000;
        sample_frac_y = 16'h0000;
        sample_sof = 1'b1;
        send_current();

        sample_frac_x = 16'h8000;
        sample_frac_y = 16'h8000;
        sample_sof = 1'b0;
        send_current();

        sample_frac_x = 16'hffff;
        sample_frac_y = 16'hffff;
        send_current();

        sample_in_bounds = 1'b0;
        sample_fill_pixel = 16'h39e7;
        sample_eol = 1'b1;
        send_current();

        sample_valid = 1'b1;
        for (sample_i = 4; sample_i < SAMPLE_COUNT; sample_i = sample_i + 1) begin
            sample_p00 = $random(random_seed);
            sample_p10 = $random(random_seed);
            sample_p01 = $random(random_seed);
            sample_p11 = $random(random_seed);
            sample_frac_x = $random(random_seed);
            sample_frac_y = $random(random_seed);
            sample_in_bounds = (sample_i % 13) != 0;
            sample_fill_pixel = 16'h2104 ^ sample_i[15:0];
            sample_dst_x = sample_i % 17;
            sample_dst_y = sample_i / 17;
            sample_sof = sample_i == 4;
            sample_eol = (sample_i % 17) == 16;
            sample_eof = sample_i == SAMPLE_COUNT-1;
            while (!sample_ready)
                @(negedge clk);
            enqueue_expected();
            @(negedge clk);
        end
        sample_valid = 1'b0;

        guard = 0;
        while ((expected_read < SAMPLE_COUNT) && (guard < 3000)) begin
            @(negedge clk);
            guard = guard + 1;
        end
        check_true(guard < 3000, "all bilinear samples drain");
        check_true(expected_write == SAMPLE_COUNT,
                   "all input samples were accepted exactly once");

        if (failures == 0)
            $display("GEOMETRY_BILINEAR_PASS checks=%0d samples=%0d",
                     checks, expected_read);
        else
            $fatal(1, "GEOMETRY_BILINEAR_FAIL checks=%0d failures=%0d",
                   checks, failures);
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "Geometry bilinear timeout");
    end

endmodule
