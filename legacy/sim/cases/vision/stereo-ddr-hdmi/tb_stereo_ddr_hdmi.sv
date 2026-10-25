`timescale 1ns/1ps

module tb_stereo_ddr_hdmi;
    localparam integer H_ACTIVE = 32;
    localparam integer V_ACTIVE = 8;
    localparam integer FRAME_PIXELS = H_ACTIVE * V_ACTIVE;
    localparam [15:0] CAM0_PIXEL = 16'hf800;
    localparam [15:0] CAM1_PIXEL = 16'h07e0;
    localparam [7:0] SENSOR_READ_VALUE = 8'h56;

    reg ctrl_clk;
    reg ddr_clk;
    reg pixel_clk;
    reg serial_clk;
    reg cam0_pclk;
    reg cam1_pclk;
    reg rst_n;
    reg button_n;
    reg display_enable;
    reg cfg_req_toggle;
    reg cfg_camera;
    reg cfg_read;
    reg [15:0] cfg_reg_addr;
    reg [7:0] cfg_write_data;
    reg pixel_cfg_req_toggle;
    wire pixel_cfg_ack_toggle;
    reg pixel_spatial_enable;
    reg [2:0] pixel_spatial_mode;
    reg [7:0] cam0_data;
    reg cam0_href;
    reg cam0_vsync;
    reg [7:0] cam1_data;
    reg cam1_href;
    reg cam1_vsync;

    integer checks;
    integer failures;
    integer timeout_cycles;
    integer left_file;
    integer right_file;
    integer gray_file;
    integer sobel_file;
    integer write_burst_count;
    integer read_burst_count;
    integer illegal_ddr_address_count;
    integer left_display_count;
    integer right_display_count;
    string image_output_dir;

    initial ctrl_clk = 1'b0;
    always #5 ctrl_clk = ~ctrl_clk;
    initial ddr_clk = 1'b0;
    always #4 ddr_clk = ~ddr_clk;
    initial pixel_clk = 1'b0;
    always #7 pixel_clk = ~pixel_clk;
    initial serial_clk = 1'b0;
    always #1 serial_clk = ~serial_clk;
    initial cam0_pclk = 1'b0;
    always #6 cam0_pclk = ~cam0_pclk;
    initial cam1_pclk = 1'b0;
    always #8 cam1_pclk = ~cam1_pclk;

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

    task automatic send_cam0_frame;
        integer x;
        integer y;
        begin
            @(negedge cam0_pclk);
            cam0_vsync = 1'b0;
            repeat (2) @(negedge cam0_pclk);
            for (y = 0; y < V_ACTIVE; y = y + 1) begin
                cam0_href = 1'b1;
                for (x = 0; x < H_ACTIVE; x = x + 1) begin
                    cam0_data = CAM0_PIXEL[15:8];
                    @(negedge cam0_pclk);
                    cam0_data = CAM0_PIXEL[7:0];
                    @(negedge cam0_pclk);
                end
                cam0_href = 1'b0;
                repeat (4) @(negedge cam0_pclk);
            end
            cam0_vsync = 1'b1;
            repeat (8) @(negedge cam0_pclk);
        end
    endtask

    task automatic send_cam1_frame;
        integer x;
        integer y;
        begin
            @(negedge cam1_pclk);
            cam1_vsync = 1'b0;
            repeat (2) @(negedge cam1_pclk);
            for (y = 0; y < V_ACTIVE; y = y + 1) begin
                cam1_href = 1'b1;
                for (x = 0; x < H_ACTIVE; x = x + 1) begin
                    cam1_data = CAM1_PIXEL[15:8];
                    @(negedge cam1_pclk);
                    cam1_data = CAM1_PIXEL[7:0];
                    @(negedge cam1_pclk);
                end
                cam1_href = 1'b0;
                repeat (4) @(negedge cam1_pclk);
            end
            cam1_vsync = 1'b1;
            repeat (8) @(negedge cam1_pclk);
        end
    endtask

    task automatic capture_active_frame;
        input integer file_handle;
        input [23:0] expected_rgb;
        integer pixel_count;
        begin
            pixel_count = 0;
            while (!(u_dut.scanout_de_w &&
                     (u_dut.scanout_rgb_w == expected_rgb)))
                @(posedge pixel_clk);
            $fwrite(file_handle, "P3\n%0d %0d\n255\n",
                H_ACTIVE, V_ACTIVE);
            while (pixel_count < FRAME_PIXELS) begin
                @(posedge pixel_clk);
                if (u_dut.scanout_de_w) begin
                    check_true(u_dut.scanout_rgb_w == expected_rgb,
                        "HDMI active pixel matches selected camera");
                    $fwrite(file_handle, "%0d %0d %0d\n",
                        u_dut.scanout_rgb_w[23:16],
                        u_dut.scanout_rgb_w[15:8],
                        u_dut.scanout_rgb_w[7:0]);
                    pixel_count = pixel_count + 1;
                end
            end
        end
    endtask

    task automatic capture_sobel_frame;
        input integer file_handle;
        integer pixel_count;
        integer x;
        integer y;
        reg [23:0] expected_rgb;
        begin
            pixel_count = 0;
            while (!(u_dut.scanout_de_w &&
                     (u_dut.unused_scanout_x_w == 0) &&
                     (u_dut.unused_scanout_y_w == 0) &&
                     (u_dut.scanout_rgb_w == 24'hffffff)))
                @(posedge pixel_clk);
            $fwrite(file_handle, "P3\n%0d %0d\n255\n",
                H_ACTIVE, V_ACTIVE);
            while (pixel_count < FRAME_PIXELS) begin
                if (u_dut.scanout_de_w) begin
                    x = u_dut.unused_scanout_x_w;
                    y = u_dut.unused_scanout_y_w;
                    expected_rgb = (x == 0 || x == H_ACTIVE - 1 ||
                        y == 0 || y == V_ACTIVE - 1) ?
                        24'hffffff : 24'h000000;
                    check_true(u_dut.scanout_rgb_w == expected_rgb,
                        "integrated Sobel HDMI pixel matches border golden");
                    $fwrite(file_handle, "%0d %0d %0d\n",
                        u_dut.scanout_rgb_w[23:16],
                        u_dut.scanout_rgb_w[15:8],
                        u_dut.scanout_rgb_w[7:0]);
                    pixel_count = pixel_count + 1;
                end
                @(posedge pixel_clk);
            end
        end
    endtask

    wire cam0_scl;
    tri1 cam0_sda;
    wire cam0_rst_n;
    wire cam1_scl;
    tri1 cam1_sda;
    wire cam1_rst_n;
    wire cam0_init_done;
    wire cam1_init_done;
    wire cfg_ack_toggle;
    wire cfg_error;
    wire [7:0] cfg_read_data;
    wire selected_camera;
    wire [31:0] cam0_frame_count;
    wire [31:0] cam1_frame_count;
    wire [31:0] display_frame_count;
    wire [31:0] underflow_count;
    wire dut_error;
    wire telemetry_tx;

    wire [3:0] awid;
    wire [31:0] awaddr;
    wire [7:0] awlen;
    wire [2:0] awsize;
    wire [1:0] awburst;
    wire [3:0] awqos;
    wire awvalid;
    wire awready;
    wire [255:0] wdata;
    wire [31:0] wstrb;
    wire wlast;
    wire wvalid;
    wire wready;
    wire [3:0] bid;
    wire [1:0] bresp;
    wire bvalid;
    wire bready;
    wire [3:0] arid;
    wire [31:0] araddr;
    wire [7:0] arlen;
    wire [2:0] arsize;
    wire [1:0] arburst;
    wire [3:0] arqos;
    wire arvalid;
    wire arready;
    wire [3:0] rid;
    wire [255:0] rdata;
    wire [1:0] rresp;
    wire rlast;
    wire rvalid;
    wire rready;
    wire tmds_clk_p;
    wire tmds_clk_n;
    wire [2:0] tmds_data_p;
    wire [2:0] tmds_data_n;

    wire sccb_dont_care_phase_w =
        u_dut.u_camera_init.u_sccb.state_r == 4'd3;
    wire sccb_read_phase_w =
        u_dut.u_camera_init.u_sccb.state_r == 4'd5;
    wire sccb_read_bit_w = SENSOR_READ_VALUE[
        u_dut.u_camera_init.u_sccb.bit_index_r];
    wire cam0_sensor_drive_low_w =
        !u_dut.u_camera_init.camera_select_r &&
        (sccb_dont_care_phase_w ||
         (sccb_read_phase_w && !sccb_read_bit_w));
    wire cam1_sensor_drive_low_w =
        u_dut.u_camera_init.camera_select_r &&
        (sccb_dont_care_phase_w ||
         (sccb_read_phase_w && !sccb_read_bit_w));

    assign cam0_sda = cam0_sensor_drive_low_w ? 1'b0 : 1'bz;
    assign cam1_sda = cam1_sensor_drive_low_w ? 1'b0 : 1'bz;

    edrv32_stereo_hdmi #(
        .H_ACTIVE(H_ACTIVE), .H_FP(4), .H_SYNC(4), .H_BP(4),
        .V_ACTIVE(V_ACTIVE), .V_FP(2), .V_SYNC(2), .V_BP(2),
        .BURST_BEATS(4), .PREFILL_BEATS(4),
        .CAMERA_FIFO_ADDR_W(4), .CAMERA_DISCARD_FRAMES(0),
        .TELEMETRY_ENABLE(1),
        .BUTTON_DEBOUNCE_CYCLES(2),
        .INIT_RESET_CYCLES(2), .INIT_SETTLE_CYCLES(2),
        .INIT_REG_COUNT(2),
        .DISPLAY_BASE0(32'h0000_4000), .DISPLAY_BASE1(32'h0000_5000),
        .DISPLAY_BASE2(32'h0000_6000),
        .GEOMETRY_BASE0(32'h0000_7000), .GEOMETRY_BASE1(32'h0000_8000),
        .GEOMETRY_BASE2(32'h0000_9000)
    ) u_dut (
        .ctrl_clk_i(ctrl_clk), .ctrl_rst_n_i(rst_n),
        .ddr_clk_i(ddr_clk), .ddr_rst_n_i(rst_n),
        .pixel_clk_i(pixel_clk), .pixel_rst_n_i(rst_n),
        .serial_clk_i(serial_clk), .serial_rst_n_i(rst_n),
        .enable_i(1'b1),
        .select_button_n_i(button_n),
        .cam0_enable_i(1'b1), .cam1_enable_i(1'b1),
        .display_enable_i(display_enable),
        .cfg_req_toggle_i(cfg_req_toggle), .cfg_camera_i(cfg_camera),
        .cfg_read_i(cfg_read),
        .cfg_reg_addr_i(cfg_reg_addr), .cfg_write_data_i(cfg_write_data),
        .cfg_ack_toggle_o(cfg_ack_toggle),
        .cfg_error_o(cfg_error), .cfg_read_data_o(cfg_read_data),
        .pixel_cfg_req_toggle_i(pixel_cfg_req_toggle),
        .pixel_cfg_enable_i(1'b1), .pixel_cfg_grayscale_i(1'b1),
        .pixel_cfg_threshold_enable_i(1'b0),
        .pixel_cfg_invert_i(1'b0), .pixel_cfg_brightness_i(9'sd0),
        .pixel_cfg_contrast_i(9'd256),
        .pixel_cfg_threshold_i(8'd128),
        .pixel_cfg_spatial_enable_i(pixel_spatial_enable),
        .pixel_cfg_spatial_mode_i(pixel_spatial_mode),
        .pixel_cfg_spatial_threshold_i(8'd128),
        .pixel_cfg_ack_toggle_o(pixel_cfg_ack_toggle),
        .geometry_mode_i(5'd0),
        .geometry_cfg_req_toggle_i(1'b0),
        .geometry_image_override_i(1'b0),
        .geometry_image_width_i(16'd1280),
        .geometry_image_height_i(16'd720),
        .geometry_angle_override_i(1'b0),
        .geometry_angle_i(9'd0),
        .cam0_pclk_i(cam0_pclk), .cam0_data_i(cam0_data),
        .cam0_href_i(cam0_href), .cam0_vsync_i(cam0_vsync),
        .cam0_scl_o(cam0_scl), .cam0_sda_io(cam0_sda),
        .cam0_rst_n_o(cam0_rst_n),
        .cam1_pclk_i(cam1_pclk), .cam1_data_i(cam1_data),
        .cam1_href_i(cam1_href), .cam1_vsync_i(cam1_vsync),
        .cam1_scl_o(cam1_scl), .cam1_sda_io(cam1_sda),
        .cam1_rst_n_o(cam1_rst_n),
        .selected_camera_o(selected_camera),
        .cam0_init_done_o(cam0_init_done),
        .cam1_init_done_o(cam1_init_done),
        .display_active_buffer_o(),
        .cam0_frame_count_o(cam0_frame_count),
        .cam1_frame_count_o(cam1_frame_count),
        .display_frame_count_o(display_frame_count),
        .pixel_frame_count_o(), .underflow_count_o(underflow_count),
        .reader_prefill_done_o(), .hdmi_fifo_read_valid_o(),
        .hdmi_fifo_local_count_o(), .scanout_frame_count_o(),
        .read_urgent_o(), .write_urgent_o(),
        .camera_error_o(), .display_error_o(), .error_o(dut_error),
        .telemetry_tx_o(telemetry_tx),
        .m_awid_o(awid), .m_awaddr_o(awaddr), .m_awlen_o(awlen),
        .m_awsize_o(awsize), .m_awburst_o(awburst), .m_awqos_o(awqos),
        .m_awvalid_o(awvalid), .m_awready_i(awready),
        .m_wdata_o(wdata), .m_wstrb_o(wstrb), .m_wlast_o(wlast),
        .m_wvalid_o(wvalid), .m_wready_i(wready), .m_bid_i(bid),
        .m_bresp_i(bresp), .m_bvalid_i(bvalid), .m_bready_o(bready),
        .m_arid_o(arid), .m_araddr_o(araddr), .m_arlen_o(arlen),
        .m_arsize_o(arsize), .m_arburst_o(arburst), .m_arqos_o(arqos),
        .m_arvalid_o(arvalid), .m_arready_i(arready), .m_rid_i(rid),
        .m_rdata_i(rdata), .m_rresp_i(rresp), .m_rlast_i(rlast),
        .m_rvalid_i(rvalid), .m_rready_o(rready),
        .tmds_clk_p_o(tmds_clk_p), .tmds_clk_n_o(tmds_clk_n),
        .tmds_data_p_o(tmds_data_p), .tmds_data_n_o(tmds_data_n)
    );

    axi256_mem_model #(.WORDS(1024)) u_mem (
        .clk_i(ddr_clk), .rst_n_i(rst_n), .awid_i(awid),
        .awaddr_i(awaddr), .awlen_i(awlen), .awsize_i(awsize),
        .awburst_i(awburst), .awvalid_i(awvalid), .awready_o(awready),
        .wdata_i(wdata), .wstrb_i(wstrb), .wlast_i(wlast),
        .wvalid_i(wvalid), .wready_o(wready), .bid_o(bid),
        .bresp_o(bresp), .bvalid_o(bvalid), .bready_i(bready),
        .arid_i(arid), .araddr_i(araddr), .arlen_i(arlen),
        .arsize_i(arsize), .arburst_i(arburst), .arvalid_i(arvalid),
        .arready_o(arready), .rid_o(rid), .rdata_o(rdata),
        .rresp_o(rresp), .rlast_o(rlast), .rvalid_o(rvalid),
        .rready_i(rready)
    );

    always @(posedge ddr_clk) begin
        if (!rst_n) begin
            write_burst_count <= 0;
            read_burst_count <= 0;
            illegal_ddr_address_count <= 0;
        end else begin
            if (awvalid && awready) begin
                write_burst_count <= write_burst_count + 1;
                if (!(((awaddr >= 32'h0000_4000) &&
                       (awaddr < 32'h0000_4200)) ||
                      ((awaddr >= 32'h0000_5000) &&
                       (awaddr < 32'h0000_5200)) ||
                      ((awaddr >= 32'h0000_6000) &&
                       (awaddr < 32'h0000_6200)) ||
                      ((awaddr >= 32'h0000_7000) &&
                       (awaddr < 32'h0000_7200)) ||
                      ((awaddr >= 32'h0000_8000) &&
                       (awaddr < 32'h0000_8200)) ||
                      ((awaddr >= 32'h0000_9000) &&
                       (awaddr < 32'h0000_9200))))
                    illegal_ddr_address_count <=
                        illegal_ddr_address_count + 1;
            end
            if (arvalid && arready) begin
                read_burst_count <= read_burst_count + 1;
                if (!(((araddr >= 32'h0000_4000) &&
                       (araddr < 32'h0000_4200)) ||
                      ((araddr >= 32'h0000_5000) &&
                       (araddr < 32'h0000_5200)) ||
                      ((araddr >= 32'h0000_6000) &&
                       (araddr < 32'h0000_6200)) ||
                      ((araddr >= 32'h0000_7000) &&
                       (araddr < 32'h0000_7200)) ||
                      ((araddr >= 32'h0000_8000) &&
                       (araddr < 32'h0000_8200)) ||
                      ((araddr >= 32'h0000_9000) &&
                       (araddr < 32'h0000_9200))))
                    illegal_ddr_address_count <=
                        illegal_ddr_address_count + 1;
            end
        end
    end

    initial begin
        checks = 0;
        failures = 0;
        write_burst_count = 0;
        read_burst_count = 0;
        illegal_ddr_address_count = 0;
        left_display_count = 0;
        rst_n = 1'b0;
        button_n = 1'b1;
        display_enable = 1'b1;
        cfg_req_toggle = 1'b0;
        cfg_camera = 1'b0;
        cfg_read = 1'b0;
        cfg_reg_addr = 16'b0;
        cfg_write_data = 8'b0;
        pixel_cfg_req_toggle = 1'b0;
        pixel_spatial_enable = 1'b0;
        pixel_spatial_mode = 3'b0;
        cam0_data = 8'b0;
        cam0_href = 1'b0;
        cam0_vsync = 1'b1;
        cam1_data = 8'b0;
        cam1_href = 1'b0;
        cam1_vsync = 1'b1;
        if (!$value$plusargs("IMAGE_OUT_DIR=%s", image_output_dir))
            image_output_dir =
                "sim/build/modelsim/cases/vision/stereo-ddr-hdmi";
        left_file = $fopen({image_output_dir,
            "/stereo_left_hdmi.ppm"}, "w");
        right_file = $fopen({image_output_dir,
            "/stereo_right_hdmi.ppm"}, "w");
        gray_file = $fopen({image_output_dir,
            "/stereo_pixel_gray_hdmi.ppm"}, "w");
        sobel_file = $fopen({image_output_dir,
            "/stereo_spatial_sobel_hdmi.ppm"}, "w");
        check_true(left_file != 0, "left HDMI image file opens");
        check_true(right_file != 0, "right HDMI image file opens");
        check_true(gray_file != 0, "processed HDMI image file opens");
        check_true(sobel_file != 0, "Sobel HDMI image file opens");

        repeat (8) @(posedge ctrl_clk);
        rst_n = 1'b1;

        repeat (18000) @(posedge ctrl_clk);
        check_true(cam0_rst_n && cam1_rst_n, "both camera resets released");
        check_true(cam0_init_done && cam1_init_done,
            "both camera ROM initializations complete");

        cfg_camera = 1'b1;
        cfg_reg_addr = 16'h3821;
        cfg_write_data = 8'h06;
        cfg_req_toggle = ~cfg_req_toggle;
        timeout_cycles = 0;
        while ((cfg_ack_toggle != cfg_req_toggle) &&
               (timeout_cycles < 10000)) begin
            @(posedge ctrl_clk);
            timeout_cycles = timeout_cycles + 1;
        end
        check_true(cfg_ack_toggle == cfg_req_toggle,
            "runtime SCCB command completes with toggle acknowledgement");
        check_true(!cfg_error, "runtime SCCB write completes without bus error");
        check_true(u_dut.u_camera_init.runtime_data_r == 24'h3821_06 &&
                   u_dut.u_camera_init.camera_select_r,
            "runtime SCCB command targets camera 1 with stable payload");

        cfg_camera = 1'b0;
        cfg_read = 1'b1;
        cfg_reg_addr = 16'h300a;
        cfg_req_toggle = ~cfg_req_toggle;
        timeout_cycles = 0;
        while ((cfg_ack_toggle != cfg_req_toggle) &&
               (timeout_cycles < 10000)) begin
            @(posedge ctrl_clk);
            timeout_cycles = timeout_cycles + 1;
        end
        check_true(cfg_ack_toggle == cfg_req_toggle && !cfg_error,
            "runtime SCCB read completes without bus error");
        check_true(cfg_read_data == 8'h56,
            "runtime SCCB read returns modeled OV5640 chip ID high byte");
        cfg_read = 1'b0;

        repeat (4) begin
            fork
                send_cam0_frame();
                send_cam1_frame();
            join
        end

        timeout_cycles = 0;
        while ((display_frame_count < 1) && (timeout_cycles < 200000)) begin
            @(posedge ddr_clk);
            timeout_cycles = timeout_cycles + 1;
        end
        check_true(cam0_frame_count == 4, "four left camera frames captured");
        check_true(cam1_frame_count == 4, "four right camera frames captured");
        check_true(display_frame_count >= 1, "left frame stored for display");
        check_true(!selected_camera, "left camera selected by default");
        capture_active_frame(left_file, 24'hff0000);
        left_display_count = display_frame_count;

        display_enable = 1'b0;
        timeout_cycles = 0;
        while (u_dut.u_scanout.output_enable_r &&
               (timeout_cycles < 5000)) begin
            @(posedge pixel_clk);
            timeout_cycles = timeout_cycles + 1;
        end
        check_true(!u_dut.u_scanout.output_enable_r,
            "HDMI disable commits at frame boundary");
        while (!u_dut.u_scanout.timing_de_w)
            @(posedge pixel_clk);
        check_true(!u_dut.scanout_de_w &&
                   (u_dut.scanout_rgb_w == 24'b0),
            "disabled HDMI blanks pixels but keeps timing alive");

        display_enable = 1'b1;
        timeout_cycles = 0;
        while (!u_dut.u_scanout.output_enable_r &&
               (timeout_cycles < 5000)) begin
            @(posedge pixel_clk);
            timeout_cycles = timeout_cycles + 1;
        end
        check_true(u_dut.u_scanout.output_enable_r,
            "HDMI enable commits at frame boundary");
        while (!(u_dut.scanout_de_w &&
                 (u_dut.scanout_rgb_w == 24'hff0000)))
            @(posedge pixel_clk);
        check_true(underflow_count == 0,
            "HDMI dynamic blank/unblank preserves FIFO alignment");

        button_n = 1'b0;
        repeat (6) @(posedge ctrl_clk);
        button_n = 1'b1;
        repeat (8) @(posedge ctrl_clk);

        repeat (4)
            send_cam1_frame();

        timeout_cycles = 0;
        while ((!selected_camera ||
                (display_frame_count <= left_display_count)) &&
               (timeout_cycles < 200000)) begin
            @(posedge ddr_clk);
            timeout_cycles = timeout_cycles + 1;
        end
        check_true(selected_camera, "button selects right camera");
        check_true(cam1_frame_count == 8, "four more right frames captured");
        check_true(display_frame_count > left_display_count,
            "right frame stored for display");
        capture_active_frame(right_file, 24'h00ff00);
        right_display_count = display_frame_count;

        pixel_cfg_req_toggle = ~pixel_cfg_req_toggle;
        repeat (4)
            send_cam1_frame();
        timeout_cycles = 0;
        while (((pixel_cfg_ack_toggle != pixel_cfg_req_toggle) ||
                (display_frame_count <= right_display_count)) &&
               (timeout_cycles < 200000)) begin
            @(posedge ddr_clk);
            timeout_cycles = timeout_cycles + 1;
        end
        check_true(pixel_cfg_ack_toggle == pixel_cfg_req_toggle,
            "pixel configuration applies at a camera frame boundary");
        check_true(display_frame_count > right_display_count,
            "processed frame reaches the display buffer pool");
        capture_active_frame(gray_file, 24'h949694);

        right_display_count = display_frame_count;
        pixel_spatial_enable = 1'b1;
        pixel_spatial_mode = 3'd1;
        pixel_cfg_req_toggle = ~pixel_cfg_req_toggle;
        repeat (4)
            send_cam1_frame();
        timeout_cycles = 0;
        while (((pixel_cfg_ack_toggle != pixel_cfg_req_toggle) ||
                (display_frame_count <= right_display_count)) &&
               (timeout_cycles < 200000)) begin
            @(posedge ddr_clk);
            timeout_cycles = timeout_cycles + 1;
        end
        check_true(pixel_cfg_ack_toggle == pixel_cfg_req_toggle,
            "spatial configuration applies at a camera frame boundary");
        capture_sobel_frame(sobel_file);

        $fclose(left_file);
        $fclose(right_file);
        $fclose(gray_file);
        $fclose(sobel_file);
        check_true(write_burst_count >= 8,
            "multiple camera frames issue direct display write bursts");
        check_true(read_burst_count > 0, "HDMI reads display buffers");
        check_true(illegal_ddr_address_count == 0,
            "all traffic remains inside the display buffer pool");
        check_true(!dut_error, "pipeline reports no error");
        check_true(underflow_count == 0, "HDMI scanout has no underflow");

        if (failures == 0)
            $display("STEREO_DDR_HDMI_PASS checks=%0d", checks);
        else
            $display("STEREO_DDR_HDMI_FAIL checks=%0d failures=%0d",
                checks, failures);
        $finish;
    end

    initial begin
        #20000000;
        $display("STEREO_DDR_HDMI_TIMEOUT");
        $finish;
    end

endmodule
