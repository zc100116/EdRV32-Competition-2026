`timescale 1ns/1ps

module tb_colorbar_ddr_hdmi;
    localparam integer H_ACTIVE = 128;
    localparam integer V_ACTIVE = 72;
    localparam integer BURST_BEATS = 4;
    localparam integer FRAME_PIXELS = H_ACTIVE * V_ACTIVE;
    localparam integer NUM_M = 4;

    reg ddr_clk;
    reg pixel_clk;
    reg serial_clk;
    reg rst_n;
    reg writer_start;

    integer checks;
    integer failures;
    integer writer_bursts;
    integer reader_bursts;
    integer output_pixels;
    integer output_frames;
    integer timeout_cycles;
    integer hdmi_image_file;
    integer hdmi_capture_enable;
    string image_output_dir;

    initial ddr_clk = 1'b0;
    always #4 ddr_clk = ~ddr_clk;

    initial pixel_clk = 1'b0;
    always #7 pixel_clk = ~pixel_clk;

    initial serial_clk = 1'b0;
    always #1 serial_clk = ~serial_clk;

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

    function automatic [15:0] expected_rgb565;
        input integer x;
        begin
            if (x < H_ACTIVE / 8)
                expected_rgb565 = 16'hffff;
            else if (x < H_ACTIVE * 2 / 8)
                expected_rgb565 = 16'hffe0;
            else if (x < H_ACTIVE * 3 / 8)
                expected_rgb565 = 16'h07ff;
            else if (x < H_ACTIVE * 4 / 8)
                expected_rgb565 = 16'h07e0;
            else if (x < H_ACTIVE * 5 / 8)
                expected_rgb565 = 16'hf81f;
            else if (x < H_ACTIVE * 6 / 8)
                expected_rgb565 = 16'hf800;
            else if (x < H_ACTIVE * 7 / 8)
                expected_rgb565 = 16'h001f;
            else
                expected_rgb565 = 16'h0000;
        end
    endfunction

    function automatic [23:0] expected_rgb888;
        input integer x;
        reg [15:0] pixel;
        begin
            pixel = expected_rgb565(x);
            expected_rgb888 = {
                pixel[15:11], pixel[15:13],
                pixel[10:5],  pixel[10:9],
                pixel[4:0],   pixel[4:2]
            };
        end
    endfunction

    function automatic [255:0] expected_word;
        input integer word_index;
        integer lane;
        begin
            expected_word = 256'b0;
            for (lane = 0; lane < 16; lane = lane + 1)
                expected_word[lane*16 +: 16] =
                    expected_rgb565(word_index * 16 + lane);
        end
    endfunction

    task automatic dump_ddr_image;
        integer image_file;
        integer x;
        integer y;
        integer linear_pixel;
        integer word_index;
        integer lane_index;
        reg [15:0] pixel;
        reg [7:0] red;
        reg [7:0] green;
        reg [7:0] blue;
        begin
            image_file = $fopen({image_output_dir,
                "/colorbar_ddr.ppm"}, "w");
            check_true(image_file != 0, "DDR image file opens");
            $fwrite(image_file, "P3\n%0d %0d\n255\n",
                H_ACTIVE, V_ACTIVE);
            for (y = 0; y < V_ACTIVE; y = y + 1) begin
                for (x = 0; x < H_ACTIVE; x = x + 1) begin
                    linear_pixel = y * H_ACTIVE + x;
                    word_index = linear_pixel / 16;
                    lane_index = linear_pixel % 16;
                    pixel = u_mem.store[word_index][lane_index*16 +: 16];
                    red = {pixel[15:11], pixel[15:13]};
                    green = {pixel[10:5], pixel[10:9]};
                    blue = {pixel[4:0], pixel[4:2]};
                    $fwrite(image_file, "%0d %0d %0d\n", red, green, blue);
                end
            end
            $fclose(image_file);
        end
    endtask

    wire writer_busy;
    wire writer_done;
    wire writer_error;
    wire [3:0] writer_awid;
    wire [31:0] writer_awaddr;
    wire [7:0] writer_awlen;
    wire [2:0] writer_awsize;
    wire [1:0] writer_awburst;
    wire [3:0] writer_awqos;
    wire writer_awvalid;
    wire writer_awready;
    wire [255:0] writer_wdata;
    wire [31:0] writer_wstrb;
    wire writer_wlast;
    wire writer_wvalid;
    wire writer_wready;
    wire [3:0] writer_bid;
    wire [1:0] writer_bresp;
    wire writer_bvalid;
    wire writer_bready;

    edrv32_colorbar_axi_writer #(
        .H_ACTIVE   (H_ACTIVE),
        .V_ACTIVE   (V_ACTIVE),
        .BURST_BEATS(BURST_BEATS),
        .FRAME_BASE (32'h0000_0000),
        .AXI_ID     (4'h3)
    ) u_writer (
        .clk_i       (ddr_clk),
        .rst_n_i     (rst_n),
        .start_i     (writer_start),
        .busy_o      (writer_busy),
        .done_o      (writer_done),
        .error_o     (writer_error),
        .m_awid_o    (writer_awid),
        .m_awaddr_o  (writer_awaddr),
        .m_awlen_o   (writer_awlen),
        .m_awsize_o  (writer_awsize),
        .m_awburst_o (writer_awburst),
        .m_awqos_o   (writer_awqos),
        .m_awvalid_o (writer_awvalid),
        .m_awready_i (writer_awready),
        .m_wdata_o   (writer_wdata),
        .m_wstrb_o   (writer_wstrb),
        .m_wlast_o   (writer_wlast),
        .m_wvalid_o  (writer_wvalid),
        .m_wready_i  (writer_wready),
        .m_bid_i     (writer_bid),
        .m_bresp_i   (writer_bresp),
        .m_bvalid_i  (writer_bvalid),
        .m_bready_o  (writer_bready)
    );

    wire reader_active;
    wire reader_prefill_done;
    wire [31:0] reader_frame_count;
    wire reader_error;
    wire [3:0] reader_arid;
    wire [31:0] reader_araddr;
    wire [7:0] reader_arlen;
    wire [2:0] reader_arsize;
    wire [1:0] reader_arburst;
    wire [3:0] reader_arqos;
    wire reader_arvalid;
    wire reader_arready;
    wire [3:0] reader_rid;
    wire [255:0] reader_rdata;
    wire [1:0] reader_rresp;
    wire reader_rlast;
    wire reader_rvalid;
    wire reader_rready;
    wire [255:0] fifo_write_data;
    wire fifo_write_valid;
    wire fifo_write_ready;

    edrv32_hdmi_axi_reader #(
        .H_ACTIVE    (H_ACTIVE),
        .V_ACTIVE    (V_ACTIVE),
        .BURST_BEATS (BURST_BEATS),
        .PREFILL_BEATS(4),
        .FRAME_BASE  (32'h0000_0000),
        .AXI_ID      (4'h5)
    ) u_reader (
        .clk_i           (ddr_clk),
        .rst_n_i         (rst_n),
        .start_i         (writer_done && !writer_error),
        .active_o        (reader_active),
        .prefill_done_o  (reader_prefill_done),
        .frame_count_o   (reader_frame_count),
        .error_o         (reader_error),
        .m_arid_o        (reader_arid),
        .m_araddr_o      (reader_araddr),
        .m_arlen_o       (reader_arlen),
        .m_arsize_o      (reader_arsize),
        .m_arburst_o     (reader_arburst),
        .m_arqos_o       (reader_arqos),
        .m_arvalid_o     (reader_arvalid),
        .m_arready_i     (reader_arready),
        .m_rid_i         (reader_rid),
        .m_rdata_i       (reader_rdata),
        .m_rresp_i       (reader_rresp),
        .m_rlast_i       (reader_rlast),
        .m_rvalid_i      (reader_rvalid),
        .m_rready_o      (reader_rready),
        .fifo_data_o     (fifo_write_data),
        .fifo_valid_o    (fifo_write_valid),
        .fifo_ready_i    (fifo_write_ready)
    );

    wire [255:0] fifo_read_data;
    wire fifo_read_valid;
    wire fifo_read_ready;
    wire fifo_almost_empty;

    edrv32_hdmi_fifo #(
        .ADDR_W            (4),
        .ALMOST_EMPTY_WORDS(2)
    ) u_fifo (
        .wr_clk_i       (ddr_clk),
        .wr_rst_n_i     (rst_n),
        .wr_data_i      (fifo_write_data),
        .wr_valid_i     (fifo_write_valid),
        .wr_ready_o     (fifo_write_ready),
        .rd_clk_i       (pixel_clk),
        .rd_rst_n_i     (rst_n),
        .rd_data_o      (fifo_read_data),
        .rd_valid_o     (fifo_read_valid),
        .rd_ready_i     (fifo_read_ready),
        .almost_empty_o (fifo_almost_empty),
        .local_count_o  ()
    );

    reg prefill_meta_r;
    reg prefill_sync_r;
    always @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            prefill_meta_r <= 1'b0;
            prefill_sync_r <= 1'b0;
        end else begin
            prefill_meta_r <= reader_prefill_done;
            prefill_sync_r <= prefill_meta_r;
        end
    end

    reg almost_empty_meta_r;
    reg almost_empty_sync_r;
    always @(posedge ddr_clk or negedge rst_n) begin
        if (!rst_n) begin
            almost_empty_meta_r <= 1'b1;
            almost_empty_sync_r <= 1'b1;
        end else begin
            almost_empty_meta_r <= fifo_almost_empty;
            almost_empty_sync_r <= almost_empty_meta_r;
        end
    end

    wire [23:0] scan_rgb;
    wire scan_hs;
    wire scan_vs;
    wire scan_de;
    wire [15:0] scan_x;
    wire [15:0] scan_y;
    wire [31:0] scan_frame_count;
    wire [31:0] scan_underflow_count;

    edrv32_hdmi_scanout #(
        .H_ACTIVE(H_ACTIVE),
        .H_FP    (4),
        .H_SYNC  (4),
        .H_BP    (4),
        .V_ACTIVE(V_ACTIVE),
        .V_FP    (2),
        .V_SYNC  (2),
        .V_BP    (2),
        .H_POL   (1),
        .V_POL   (1)
    ) u_scanout (
        .clk_i             (pixel_clk),
        .rst_n_i           (rst_n),
        .enable_i          (prefill_sync_r),
        .output_enable_i   (1'b1),
        .fifo_data_i       (fifo_read_data),
        .fifo_valid_i      (fifo_read_valid),
        .fifo_ready_o      (fifo_read_ready),
        .rgb_o             (scan_rgb),
        .hs_o              (scan_hs),
        .vs_o              (scan_vs),
        .de_o              (scan_de),
        .active_x_o        (scan_x),
        .active_y_o        (scan_y),
        .frame_count_o     (scan_frame_count),
        .underflow_count_o (scan_underflow_count)
    );

    wire tmds_clk_p;
    wire tmds_clk_n;
    wire [2:0] tmds_data_p;
    wire [2:0] tmds_data_n;

    edrv32_tmds_tx u_tmds (
        .pixel_clk_i  (pixel_clk),
        .serial_clk_i (serial_clk),
        .pixel_rst_n_i(rst_n),
        .serial_rst_n_i(rst_n),
        .rgb_i        (scan_rgb),
        .hs_i         (scan_hs),
        .vs_i         (scan_vs),
        .de_i         (scan_de),
        .tmds_clk_p_o (tmds_clk_p),
        .tmds_clk_n_o (tmds_clk_n),
        .tmds_data_p_o(tmds_data_p),
        .tmds_data_n_o(tmds_data_n)
    );

    wire [NUM_M*4-1:0] m_awid = {4'b0, writer_awid, 8'b0};
    wire [NUM_M*32-1:0] m_awaddr = {32'b0, writer_awaddr, 64'b0};
    wire [NUM_M*8-1:0] m_awlen = {8'b0, writer_awlen, 16'b0};
    wire [NUM_M*3-1:0] m_awsize = {3'd5, writer_awsize, 3'd5, 3'd5};
    wire [NUM_M*2-1:0] m_awburst = {2'b01, writer_awburst, 2'b01, 2'b01};
    wire [NUM_M*4-1:0] m_awqos = {4'b0, writer_awqos, 8'b0};
    wire [NUM_M-1:0] m_awvalid = {1'b0, writer_awvalid, 2'b00};
    wire [NUM_M-1:0] m_awready;
    wire [NUM_M*256-1:0] m_wdata = {256'b0, writer_wdata, 512'b0};
    wire [NUM_M*32-1:0] m_wstrb = {32'b0, writer_wstrb, 64'b0};
    wire [NUM_M-1:0] m_wlast = {1'b0, writer_wlast, 2'b00};
    wire [NUM_M-1:0] m_wvalid = {1'b0, writer_wvalid, 2'b00};
    wire [NUM_M-1:0] m_wready;
    wire [NUM_M*4-1:0] m_bid;
    wire [NUM_M*2-1:0] m_bresp;
    wire [NUM_M-1:0] m_bvalid;
    wire [NUM_M-1:0] m_bready = {1'b1, writer_bready, 2'b11};

    wire [NUM_M*4-1:0] m_arid = {reader_arid, 12'b0};
    wire [NUM_M*32-1:0] m_araddr = {reader_araddr, 96'b0};
    wire [NUM_M*8-1:0] m_arlen = {reader_arlen, 24'b0};
    wire [NUM_M*3-1:0] m_arsize = {reader_arsize, 3'd5, 3'd5, 3'd5};
    wire [NUM_M*2-1:0] m_arburst = {reader_arburst, 2'b01, 2'b01, 2'b01};
    wire [NUM_M*4-1:0] m_arqos = {reader_arqos, 12'b0};
    wire [NUM_M-1:0] m_arvalid = {reader_arvalid, 3'b000};
    wire [NUM_M-1:0] m_arready;
    wire [NUM_M*4-1:0] m_rid;
    wire [NUM_M*256-1:0] m_rdata;
    wire [NUM_M*2-1:0] m_rresp;
    wire [NUM_M-1:0] m_rlast;
    wire [NUM_M-1:0] m_rvalid;
    wire [NUM_M-1:0] m_rready = {reader_rready, 3'b111};

    assign writer_awready = m_awready[2];
    assign writer_wready = m_wready[2];
    assign writer_bid = m_bid[11:8];
    assign writer_bresp = m_bresp[5:4];
    assign writer_bvalid = m_bvalid[2];
    assign reader_arready = m_arready[3];
    assign reader_rid = m_rid[15:12];
    assign reader_rdata = m_rdata[1023:768];
    assign reader_rresp = m_rresp[7:6];
    assign reader_rlast = m_rlast[3];
    assign reader_rvalid = m_rvalid[3];

    wire [3:0] s_awid;
    wire [31:0] s_awaddr;
    wire [7:0] s_awlen;
    wire [2:0] s_awsize;
    wire [1:0] s_awburst;
    wire [3:0] s_awqos;
    wire s_awvalid;
    wire s_awready;
    wire [255:0] s_wdata;
    wire [31:0] s_wstrb;
    wire s_wlast;
    wire s_wvalid;
    wire s_wready;
    wire [3:0] s_bid;
    wire [1:0] s_bresp;
    wire s_bvalid;
    wire s_bready;
    wire [3:0] s_arid;
    wire [31:0] s_araddr;
    wire [7:0] s_arlen;
    wire [2:0] s_arsize;
    wire [1:0] s_arburst;
    wire [3:0] s_arqos;
    wire s_arvalid;
    wire s_arready;
    wire [3:0] s_rid;
    wire [255:0] s_rdata;
    wire [1:0] s_rresp;
    wire s_rlast;
    wire s_rvalid;
    wire s_rready;
    wire [NUM_M*5-1:0] read_outstanding;
    wire [NUM_M*5-1:0] write_outstanding;
    wire read_protocol_error;
    wire write_protocol_error;

    edrv32_axi_m2s_interconnect #(
        .NUM_M         (NUM_M),
        .ADDR_W        (32),
        .DATA_W        (256),
        .ID_W          (4),
        .S_ID_W        (4),
        .LEN_W         (8),
        .WR_ORDER_DEPTH(4),
        .STARVE_CYCLES (8),
        .COUNT_W       (5)
    ) u_interconnect (
        .clk_i                  (ddr_clk),
        .rst_n_i                (rst_n),
        .accept_i               (1'b1),
        .m_awid_i               (m_awid),
        .m_awaddr_i             (m_awaddr),
        .m_awlen_i              (m_awlen),
        .m_awsize_i             (m_awsize),
        .m_awburst_i            (m_awburst),
        .m_awqos_i              (m_awqos),
        .m_awvalid_i            (m_awvalid),
        .m_awready_o            (m_awready),
        .m_wdata_i              (m_wdata),
        .m_wstrb_i              (m_wstrb),
        .m_wlast_i              (m_wlast),
        .m_wvalid_i             (m_wvalid),
        .m_wready_o             (m_wready),
        .m_bid_o                (m_bid),
        .m_bresp_o              (m_bresp),
        .m_bvalid_o             (m_bvalid),
        .m_bready_i             (m_bready),
        .m_arid_i               (m_arid),
        .m_araddr_i             (m_araddr),
        .m_arlen_i              (m_arlen),
        .m_arsize_i             (m_arsize),
        .m_arburst_i            (m_arburst),
        .m_arqos_i              (m_arqos),
        .m_arvalid_i            (m_arvalid),
        .m_arready_o            (m_arready),
        .m_rid_o                (m_rid),
        .m_rdata_o              (m_rdata),
        .m_rresp_o              (m_rresp),
        .m_rlast_o              (m_rlast),
        .m_rvalid_o             (m_rvalid),
        .m_rready_i             (m_rready),
        .m_read_urgent_i        ({almost_empty_sync_r, 3'b000}),
        .m_write_urgent_i       (4'b0000),
        .m_read_weight_i        ({4'd4, 4'd1, 4'd1, 4'd1}),
        .m_write_weight_i       ({4'd1, 4'd2, 4'd1, 4'd1}),
        .m_read_credit_i        ({5'd1, 5'd1, 5'd1, 5'd1}),
        .m_write_credit_i       ({5'd1, 5'd1, 5'd1, 5'd1}),
        .s_awid_o               (s_awid),
        .s_awaddr_o             (s_awaddr),
        .s_awlen_o              (s_awlen),
        .s_awsize_o             (s_awsize),
        .s_awburst_o            (s_awburst),
        .s_awqos_o              (s_awqos),
        .s_awvalid_o            (s_awvalid),
        .s_awready_i            (s_awready),
        .s_wdata_o              (s_wdata),
        .s_wstrb_o              (s_wstrb),
        .s_wlast_o              (s_wlast),
        .s_wvalid_o             (s_wvalid),
        .s_wready_i             (s_wready),
        .s_bid_i                (s_bid),
        .s_bresp_i              (s_bresp),
        .s_bvalid_i             (s_bvalid),
        .s_bready_o             (s_bready),
        .s_arid_o               (s_arid),
        .s_araddr_o             (s_araddr),
        .s_arlen_o              (s_arlen),
        .s_arsize_o             (s_arsize),
        .s_arburst_o            (s_arburst),
        .s_arqos_o              (s_arqos),
        .s_arvalid_o            (s_arvalid),
        .s_arready_i            (s_arready),
        .s_rid_i                (s_rid),
        .s_rdata_i              (s_rdata),
        .s_rresp_i              (s_rresp),
        .s_rlast_i              (s_rlast),
        .s_rvalid_i             (s_rvalid),
        .s_rready_o             (s_rready),
        .read_outstanding_o     (read_outstanding),
        .write_outstanding_o    (write_outstanding),
        .read_protocol_error_o  (read_protocol_error),
        .write_protocol_error_o (write_protocol_error)
    );

    axi256_mem_model #(
        .ID_W (4),
        .WORDS(1024)
    ) u_mem (
        .clk_i     (ddr_clk),
        .rst_n_i   (rst_n),
        .awid_i    (s_awid),
        .awaddr_i  (s_awaddr),
        .awlen_i   (s_awlen),
        .awsize_i  (s_awsize),
        .awburst_i (s_awburst),
        .awvalid_i (s_awvalid),
        .awready_o (s_awready),
        .wdata_i   (s_wdata),
        .wstrb_i   (s_wstrb),
        .wlast_i   (s_wlast),
        .wvalid_i  (s_wvalid),
        .wready_o  (s_wready),
        .bid_o     (s_bid),
        .bresp_o   (s_bresp),
        .bvalid_o  (s_bvalid),
        .bready_i  (s_bready),
        .arid_i    (s_arid),
        .araddr_i  (s_araddr),
        .arlen_i   (s_arlen),
        .arsize_i  (s_arsize),
        .arburst_i (s_arburst),
        .arvalid_i (s_arvalid),
        .arready_o (s_arready),
        .rid_o     (s_rid),
        .rdata_o   (s_rdata),
        .rresp_o   (s_rresp),
        .rlast_o   (s_rlast),
        .rvalid_o  (s_rvalid),
        .rready_i  (s_rready)
    );

    always @(posedge ddr_clk) begin
        if (rst_n && s_awvalid && s_awready)
            writer_bursts = writer_bursts + 1;
        if (rst_n && s_arvalid && s_arready)
            reader_bursts = reader_bursts + 1;
    end

    always @(posedge pixel_clk) begin
        #1;
        if (rst_n && scan_de) begin
            check_true(scan_rgb == expected_rgb888(scan_x),
                "scanout pixel matches the DDR color bar");
            if (hdmi_capture_enable != 0)
                $fwrite(hdmi_image_file, "%0d %0d %0d\n",
                    scan_rgb[23:16], scan_rgb[15:8], scan_rgb[7:0]);
            output_pixels = output_pixels + 1;
            if ((scan_x == H_ACTIVE - 1) &&
                (scan_y == V_ACTIVE - 1)) begin
                check_true(output_pixels == FRAME_PIXELS,
                    "one HDMI active frame contains the expected pixel count");
                output_frames = output_frames + 1;
                output_pixels = 0;
                if (hdmi_capture_enable != 0) begin
                    $fclose(hdmi_image_file);
                    hdmi_capture_enable = 0;
                end
            end
        end
    end

    initial begin
        checks = 0;
        failures = 0;
        writer_bursts = 0;
        reader_bursts = 0;
        output_pixels = 0;
        output_frames = 0;
        timeout_cycles = 0;
        hdmi_image_file = 0;
        hdmi_capture_enable = 0;
        if (!$value$plusargs("IMAGE_OUT=%s", image_output_dir))
            image_output_dir = ".";
        rst_n = 1'b0;
        writer_start = 1'b0;

        repeat (6) @(posedge ddr_clk);
        #1 rst_n = 1'b1;
        @(posedge ddr_clk);
        #1 writer_start = 1'b1;
        @(posedge ddr_clk);
        #1 writer_start = 1'b0;

        while (!writer_done && timeout_cycles < 5000) begin
            @(posedge ddr_clk);
            timeout_cycles = timeout_cycles + 1;
        end
        #1;
        check_true(writer_done, "color-bar writer completes");
        check_true(!writer_busy, "writer leaves busy after the final B response");
        check_true(!writer_error, "writer reports no AXI error");
        check_true(writer_bursts == 144,
            "writer emits 144 four-beat bursts");
        check_true(u_mem.store[0] == expected_word(0),
            "first DDR word contains the expected first color bar");
        check_true(u_mem.store[1] == expected_word(1),
            "second DDR word contains the expected next color bar");
        dump_ddr_image();

        hdmi_image_file = $fopen({image_output_dir,
            "/colorbar_hdmi.ppm"}, "w");
        check_true(hdmi_image_file != 0, "HDMI image file opens");
        $fwrite(hdmi_image_file, "P3\n%0d %0d\n255\n",
            H_ACTIVE, V_ACTIVE);
        hdmi_capture_enable = 1;

        timeout_cycles = 0;
        while (output_frames < 2 && timeout_cycles < 60000) begin
            @(posedge ddr_clk);
            timeout_cycles = timeout_cycles + 1;
        end
        #1;
        check_true(output_frames >= 2, "two complete HDMI frames are emitted");
        check_true(reader_active, "HDMI reader remains active");
        check_true(reader_prefill_done, "reader reaches its prefill threshold");
        check_true(reader_frame_count >= 2, "reader wraps across framebuffer frames");
        check_true(reader_bursts >= 288,
            "reader issues repeated framebuffer bursts");
        check_true(!reader_error, "reader reports no AXI error");
        check_true(scan_underflow_count == 0, "prefill prevents HDMI underflow");
        check_true(!read_protocol_error && !write_protocol_error,
            "DDR interconnect reports no protocol error");

        if (failures == 0)
            $display("COLORBAR_DDR_HDMI_PASS checks=%0d", checks);
        else
            $display("COLORBAR_DDR_HDMI_FAIL failures=%0d checks=%0d",
                failures, checks);
        $finish;
    end

endmodule
