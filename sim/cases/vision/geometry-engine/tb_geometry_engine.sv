`timescale 1ns/1ps

module tb_geometry_engine;
    reg clk;
    reg rst_n;
    reg cfg_start;
    wire cfg_ready;
    reg [31:0] cfg_surface_base;
    reg [31:0] cfg_surface_stride;
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
    reg [15:0] cfg_fill_pixel;

    wire pixel_valid;
    reg pixel_ready;
    wire [15:0] pixel_data;
    wire [15:0] pixel_dst_x;
    wire [15:0] pixel_dst_y;
    wire pixel_sof;
    wire pixel_eol;
    wire pixel_eof;

    wire [3:0] m_arid;
    wire [31:0] m_araddr;
    wire [7:0] m_arlen;
    wire [2:0] m_arsize;
    wire [1:0] m_arburst;
    wire [3:0] m_arqos;
    wire m_arvalid;
    wire m_arready;
    wire [3:0] m_rid;
    wire [255:0] m_rdata;
    wire [1:0] m_rresp;
    wire m_rlast;
    wire m_rvalid;
    wire m_rready;
    wire engine_busy;
    wire engine_done;
    wire engine_error;

    integer checks;
    integer failures;
    integer output_count;
    integer expected_frame_pixels;
    integer case_mode;
    integer cycle_count;
    integer ar_command_count;
    integer ar_beat_count;
    integer multi_beat_count;
    integer ar_len_error_count;
    integer ar_4k_error_count;
    integer mem_y;
    integer mem_block;
    integer mem_lane;
    reg [255:0] mem_word_v;

    always #5 clk = ~clk;

    function automatic [15:0] pattern_pixel;
        input integer x_i;
        input integer y_i;
        integer sum_v;
        begin
            sum_v = x_i + y_i;
            pattern_pixel = {x_i[4:0], y_i[5:0], sum_v[4:0]};
        end
    endfunction

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

    function automatic integer interp5;
        input integer a_i;
        input integer b_i;
        input integer c_i;
        input integer d_i;
        input integer fx_i;
        input integer fy_i;
        input integer shift_i;
        longint signed a_v;
        longint signed b_v;
        longint signed c_v;
        longint signed d_v;
        longint signed top_v;
        longint signed bottom_v;
        longint signed value_v;
        begin
            a_v = expand5((a_i >> shift_i) & 31);
            b_v = expand5((b_i >> shift_i) & 31);
            c_v = expand5((c_i >> shift_i) & 31);
            d_v = expand5((d_i >> shift_i) & 31);
            top_v = a_v * 65536 + (b_v - a_v) * fx_i;
            bottom_v = c_v * 65536 + (d_v - c_v) * fx_i;
            value_v = top_v * 65536 +
                (bottom_v - top_v) * fy_i + 64'sd2147483648;
            interp5 = (value_v >>> 32) >>> 3;
        end
    endfunction

    function automatic integer interp6;
        input integer a_i;
        input integer b_i;
        input integer c_i;
        input integer d_i;
        input integer fx_i;
        input integer fy_i;
        longint signed a_v;
        longint signed b_v;
        longint signed c_v;
        longint signed d_v;
        longint signed top_v;
        longint signed bottom_v;
        longint signed value_v;
        begin
            a_v = expand6((a_i >> 5) & 63);
            b_v = expand6((b_i >> 5) & 63);
            c_v = expand6((c_i >> 5) & 63);
            d_v = expand6((d_i >> 5) & 63);
            top_v = a_v * 65536 + (b_v - a_v) * fx_i;
            bottom_v = c_v * 65536 + (d_v - c_v) * fx_i;
            value_v = top_v * 65536 +
                (bottom_v - top_v) * fy_i + 64'sd2147483648;
            interp6 = (value_v >>> 32) >>> 2;
        end
    endfunction

    function automatic [15:0] scale_reference;
        input integer dst_x_i;
        input integer dst_y_i;
        longint signed qx_v;
        longint signed qy_v;
        integer x0_v;
        integer y0_v;
        integer x1_v;
        integer y1_v;
        integer fx_v;
        integer fy_v;
        integer p00_v;
        integer p10_v;
        integer p01_v;
        integer p11_v;
        integer red_v;
        integer green_v;
        integer blue_v;
        begin
            qx_v = dst_x_i * 126976;
            qy_v = dst_y_i * 126976;
            x0_v = qx_v >>> 16;
            y0_v = qy_v >>> 16;
            x1_v = x0_v == 31 ? 31 : x0_v + 1;
            y1_v = y0_v == 31 ? 31 : y0_v + 1;
            fx_v = qx_v & 16'hffff;
            fy_v = qy_v & 16'hffff;
            p00_v = pattern_pixel(x0_v, y0_v);
            p10_v = pattern_pixel(x1_v, y0_v);
            p01_v = pattern_pixel(x0_v, y1_v);
            p11_v = pattern_pixel(x1_v, y1_v);
            red_v = interp5(p00_v, p10_v, p01_v, p11_v,
                            fx_v, fy_v, 11);
            green_v = interp6(p00_v, p10_v, p01_v, p11_v,
                              fx_v, fy_v);
            blue_v = interp5(p00_v, p10_v, p01_v, p11_v,
                             fx_v, fy_v, 0);
            scale_reference = {red_v[4:0], green_v[5:0], blue_v[4:0]};
        end
    endfunction

    function automatic [15:0] rotate45_reference;
        input integer dst_x_i;
        input integer dst_y_i;
        longint signed qx_v;
        longint signed qy_v;
        integer x0_v;
        integer y0_v;
        integer x1_v;
        integer y1_v;
        integer fx_v;
        integer fy_v;
        integer p00_v;
        integer p10_v;
        integer p01_v;
        integer p11_v;
        integer red_v;
        integer green_v;
        integer blue_v;
        begin
            // 5x5 crop enlarged uniformly to a 7x7 canvas, then rotated.
            // Rotation does not refit its bounding box to the canvas.
            qx_v = 470008 + dst_x_i * 30892 + dst_y_i * 30892;
            qy_v = 655360 - dst_x_i * 30892 + dst_y_i * 30892;
            x0_v = qx_v >>> 16;
            y0_v = qy_v >>> 16;
            if ((x0_v < 8) || (x0_v > 12) ||
                (y0_v < 8) || (y0_v > 12)) begin
                rotate45_reference = 16'h0000;
            end else begin
                x1_v = x0_v == 12 ? 12 : x0_v + 1;
                y1_v = y0_v == 12 ? 12 : y0_v + 1;
                fx_v = qx_v & 16'hffff;
                fy_v = qy_v & 16'hffff;
                p00_v = pattern_pixel(x0_v, y0_v);
                p10_v = pattern_pixel(x1_v, y0_v);
                p01_v = pattern_pixel(x0_v, y1_v);
                p11_v = pattern_pixel(x1_v, y1_v);
                red_v = interp5(p00_v, p10_v, p01_v, p11_v,
                                fx_v, fy_v, 11);
                green_v = interp6(p00_v, p10_v, p01_v, p11_v,
                                  fx_v, fy_v);
                blue_v = interp5(p00_v, p10_v, p01_v, p11_v,
                                 fx_v, fy_v, 0);
                rotate45_reference = {
                    red_v[4:0], green_v[5:0], blue_v[4:0]};
            end
        end
    endfunction

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

    edrv32_geometry_block_engine u_dut (
        .clk_i(clk), .rst_n_i(rst_n),
        .cfg_start_i(cfg_start), .cfg_ready_o(cfg_ready),
        .cfg_surface_base_i(cfg_surface_base),
        .cfg_surface_stride_i(cfg_surface_stride),
        .cfg_src_width_i(cfg_src_width), .cfg_src_height_i(cfg_src_height),
        .cfg_crop_x_i(cfg_crop_x), .cfg_crop_y_i(cfg_crop_y),
        .cfg_crop_width_i(cfg_crop_width),
        .cfg_crop_height_i(cfg_crop_height),
        .cfg_dst_width_i(cfg_dst_width), .cfg_dst_height_i(cfg_dst_height),
        .cfg_image_width_i(cfg_image_width),
        .cfg_image_height_i(cfg_image_height),
        .cfg_angle_i(cfg_angle), .cfg_flip_x_i(cfg_flip_x),
        .cfg_flip_y_i(cfg_flip_y), .cfg_fill_pixel_i(cfg_fill_pixel),
        .pixel_valid_o(pixel_valid), .pixel_ready_i(pixel_ready),
        .pixel_data_o(pixel_data), .pixel_dst_x_o(pixel_dst_x),
        .pixel_dst_y_o(pixel_dst_y), .pixel_sof_o(pixel_sof),
        .pixel_eol_o(pixel_eol), .pixel_eof_o(pixel_eof),
        .m_arid_o(m_arid), .m_araddr_o(m_araddr),
        .m_arlen_o(m_arlen), .m_arsize_o(m_arsize),
        .m_arburst_o(m_arburst), .m_arqos_o(m_arqos),
        .m_arvalid_o(m_arvalid), .m_arready_i(m_arready),
        .m_rid_i(m_rid), .m_rdata_i(m_rdata), .m_rresp_i(m_rresp),
        .m_rlast_i(m_rlast), .m_rvalid_i(m_rvalid),
        .m_rready_o(m_rready),
        .busy_o(engine_busy), .done_o(engine_done),
        .error_o(engine_error), .profile_phase_o()
    );

    axi256_mem_model #(.ID_W(4), .WORDS(4096)) u_mem (
        .clk_i(clk), .rst_n_i(rst_n),
        .awid_i(4'b0), .awaddr_i(32'b0), .awlen_i(8'b0),
        .awsize_i(3'd5), .awburst_i(2'b01), .awvalid_i(1'b0),
        .awready_o(), .wdata_i(256'b0), .wstrb_i(32'b0),
        .wlast_i(1'b0), .wvalid_i(1'b0), .wready_o(),
        .bid_o(), .bresp_o(), .bvalid_o(), .bready_i(1'b1),
        .arid_i(m_arid), .araddr_i(m_araddr), .arlen_i(m_arlen),
        .arsize_i(m_arsize), .arburst_i(m_arburst),
        .arvalid_i(m_arvalid), .arready_o(m_arready),
        .rid_o(m_rid), .rdata_o(m_rdata), .rresp_o(m_rresp),
        .rlast_o(m_rlast), .rvalid_o(m_rvalid), .rready_i(m_rready)
    );

    always @(negedge clk) begin
        if (!rst_n) begin
            pixel_ready = 1'b0;
            cycle_count = 0;
        end else begin
            cycle_count = cycle_count + 1;
            pixel_ready = ((cycle_count % 13) != 4) &&
                          ((cycle_count % 13) != 5) &&
                          ((cycle_count % 41) < 37);
        end
    end

    always @(posedge clk) begin
        integer expected_x_v;
        integer expected_y_v;
        reg [15:0] expected_pixel_v;
        if (rst_n && pixel_valid && pixel_ready) begin
            expected_x_v = output_count % cfg_dst_width;
            expected_y_v = output_count / cfg_dst_width;
            case (case_mode)
                0: expected_pixel_v = pattern_pixel(
                    cfg_crop_x + expected_x_v, cfg_crop_y + expected_y_v);
                1: expected_pixel_v = pattern_pixel(
                    cfg_crop_x + expected_y_v,
                    cfg_crop_y + cfg_crop_height - 1 - expected_x_v);
                2: expected_pixel_v = scale_reference(
                    expected_x_v, expected_y_v);
                3: expected_pixel_v = rotate45_reference(
                    expected_x_v, expected_y_v);
                5: expected_pixel_v =
                    ((expected_x_v < 2) || (expected_x_v > 6)) ?
                    16'h0000 : pattern_pixel(
                        8 + 2*(expected_x_v - 2), 8 + expected_y_v);
                6: expected_pixel_v =
                    ((expected_y_v < 2) || (expected_y_v > 6)) ?
                    16'h0000 : pattern_pixel(
                        4 + 2*expected_y_v, 16 - expected_x_v);
                7: expected_pixel_v =
                    ((expected_y_v < 2) || (expected_y_v > 6)) ?
                    16'h0000 : pattern_pixel(
                        8 + expected_x_v, 8 + 2*(expected_y_v - 2));
                8: expected_pixel_v = pixel_data;
                default: expected_pixel_v = pattern_pixel(
                    cfg_crop_x + cfg_crop_width - 1 - expected_x_v,
                    cfg_crop_y + expected_y_v);
            endcase
            check_true(pixel_dst_x == expected_x_v &&
                       pixel_dst_y == expected_y_v,
                       "geometry output raster coordinate");
            if ((pixel_data != expected_pixel_v) && (failures < 12))
                $display("PIXEL_MISMATCH mode=%0d index=%0d dst=(%0d,%0d) got=%h expected=%h",
                         case_mode, output_count, expected_x_v, expected_y_v,
                         pixel_data, expected_pixel_v);
            check_true(pixel_data == expected_pixel_v,
                       "geometry output pixel matches software reference");
            if (case_mode == 8) begin
                if (((expected_x_v == 2) && (expected_y_v == 6)) ||
                    ((expected_x_v == 6) && (expected_y_v == 2)))
                    check_true(pixel_data != 16'h0000,
                        "rotated corner extends outside unrotated viewport");
                if ((expected_x_v == 2) && (expected_y_v == 2))
                    check_true(pixel_data == 16'h0000,
                        "outside rotated square is filled black");
                if ((expected_x_v == 6) && (expected_y_v == 6))
                    check_true(pixel_data == pattern_pixel(12, 12),
                        "rotated square keeps its source center");
            end
            check_true(pixel_sof == (output_count == 0),
                       "geometry SOF marker");
            check_true(pixel_eol == (expected_x_v == cfg_dst_width-1),
                       "geometry EOL marker");
            check_true(pixel_eof ==
                       (output_count == expected_frame_pixels-1),
                       "geometry EOF marker");
            output_count = output_count + 1;
        end
    end

    always @(posedge clk) begin
        if (rst_n && m_arvalid && m_arready) begin
            ar_command_count = ar_command_count + 1;
            ar_beat_count = ar_beat_count + m_arlen + 1;
            if (m_arlen != 0)
                multi_beat_count = multi_beat_count + 1;
            if (m_arlen > 3)
                ar_len_error_count = ar_len_error_count + 1;
            if ((m_araddr[11:5] + m_arlen + 1) > 128)
                ar_4k_error_count = ar_4k_error_count + 1;
        end
    end

    task automatic run_case;
        input integer mode_i;
        input integer crop_x_i;
        input integer crop_y_i;
        input integer crop_w_i;
        input integer crop_h_i;
        input integer dst_w_i;
        input integer dst_h_i;
        input integer image_w_i;
        input integer image_h_i;
        input integer angle_i;
        integer guard;
        begin
            while (!cfg_ready)
                @(negedge clk);
            case_mode = mode_i;
            output_count = 0;
            ar_command_count = 0;
            ar_beat_count = 0;
            multi_beat_count = 0;
            ar_len_error_count = 0;
            ar_4k_error_count = 0;
            expected_frame_pixels = dst_w_i * dst_h_i;
            cfg_crop_x = crop_x_i;
            cfg_crop_y = crop_y_i;
            cfg_crop_width = crop_w_i;
            cfg_crop_height = crop_h_i;
            cfg_dst_width = dst_w_i;
            cfg_dst_height = dst_h_i;
            cfg_image_width = image_w_i;
            cfg_image_height = image_h_i;
            cfg_angle = angle_i;
            cfg_start = 1'b1;
            @(negedge clk);
            cfg_start = 1'b0;
            guard = 0;
            while (!engine_done && guard < 200000) begin
                @(negedge clk);
                guard = guard + 1;
            end
            check_true(guard < 200000, "geometry frame completes");
            check_true(output_count == expected_frame_pixels,
                       "geometry emits every destination pixel");
            check_true(!engine_error, "geometry frame has no protocol error");
            check_true(ar_command_count > 0,
                       "geometry issues source patch reads");
            check_true(ar_beat_count >= ar_command_count,
                       "source beat accounting covers every command");
            if (crop_w_i > 16)
                check_true(multi_beat_count > 0,
                           "wide patches use multi-beat source bursts");
            check_true(ar_len_error_count == 0,
                       "source patch burst is no longer than four beats");
            check_true(ar_4k_error_count == 0,
                       "source patch burst does not cross 4-KiB boundary");
            $display("GEOMETRY_BLOCK_TRAFFIC mode=%0d ar_commands=%0d ar_beats=%0d multi_beat=%0d",
                     mode_i, ar_command_count, ar_beat_count,
                     multi_beat_count);
            @(negedge clk);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        cfg_start = 1'b0;
        cfg_surface_base = 32'b0;
        cfg_surface_stride = 32'd64;
        cfg_src_width = 16'd32;
        cfg_src_height = 16'd32;
        cfg_crop_x = 16'b0;
        cfg_crop_y = 16'b0;
        cfg_crop_width = 16'b0;
        cfg_crop_height = 16'b0;
        cfg_dst_width = 16'b0;
        cfg_dst_height = 16'b0;
        cfg_image_width = 16'b0;
        cfg_image_height = 16'b0;
        cfg_angle = 9'b0;
        cfg_flip_x = 1'b0;
        cfg_flip_y = 1'b0;
        cfg_fill_pixel = 16'h0000;
        pixel_ready = 1'b0;
        checks = 0;
        failures = 0;
        output_count = 0;
        expected_frame_pixels = 0;
        case_mode = 0;
        cycle_count = 0;
        ar_command_count = 0;
        ar_beat_count = 0;
        multi_beat_count = 0;
        ar_len_error_count = 0;
        ar_4k_error_count = 0;

        for (mem_y = 0; mem_y < 32; mem_y = mem_y + 1) begin
            for (mem_block = 0; mem_block < 2; mem_block = mem_block + 1) begin
                mem_word_v = 256'b0;
                for (mem_lane = 0; mem_lane < 16; mem_lane = mem_lane + 1)
                    mem_word_v[mem_lane*16 +: 16] = pattern_pixel(
                        mem_block*16 + mem_lane, mem_y);
                u_mem.store[mem_y*2 + mem_block] = mem_word_v;
            end
        end

        // A second copy starts at 0x0fe0 so a two-beat source row must be
        // split into two legal AXI bursts at the 4-KiB boundary.
        for (mem_y = 0; mem_y < 32; mem_y = mem_y + 1) begin
            for (mem_block = 0; mem_block < 2; mem_block = mem_block + 1) begin
                mem_word_v = 256'b0;
                for (mem_lane = 0; mem_lane < 16; mem_lane = mem_lane + 1)
                    mem_word_v[mem_lane*16 +: 16] = pattern_pixel(
                        mem_block*16 + mem_lane, mem_y);
                u_mem.store[127 + mem_y*2 + mem_block] = mem_word_v;
            end
        end

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        run_case(0, 8, 8, 20, 20, 20, 20, 20, 20, 0);
        run_case(1, 8, 8, 20, 20, 20, 20, 20, 20, 90);
        cfg_flip_x = 1'b1;
        run_case(4, 8, 8, 20, 20, 20, 20, 20, 20, 0);
        cfg_flip_x = 1'b0;
        run_case(2, 0, 0, 32, 32, 17, 17, 17, 17, 0);
        run_case(3, 8, 8, 5, 5, 7, 7, 7, 7, 45);
        run_case(5, 8, 8, 9, 9, 9, 9, 5, 9, 0);
        run_case(6, 8, 8, 9, 9, 9, 9, 5, 9, 90);
        run_case(7, 8, 8, 9, 9, 9, 9, 9, 5, 0);
        run_case(8, 8, 8, 9, 9, 13, 13, 7, 7, 45);
        cfg_src_width = 16'd30;
        cfg_src_height = 16'd23;
        run_case(0, 14, 10, 15, 13, 15, 13, 15, 13, 0);
        cfg_surface_base = 32'h0000_0fe0;
        cfg_src_width = 16'd32;
        cfg_src_height = 16'd32;
        run_case(0, 0, 0, 32, 32, 32, 32, 32, 32, 0);

        if (failures == 0)
            $display("GEOMETRY_ENGINE_PASS checks=%0d", checks);
        else
            $fatal(1, "GEOMETRY_ENGINE_FAIL checks=%0d failures=%0d",
                   checks, failures);
        $finish;
    end

    initial begin
        #5000000;
        $fatal(1, "Geometry engine timeout");
    end

endmodule
