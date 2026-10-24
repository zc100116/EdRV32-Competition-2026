`timescale 1ns/1ps

module tb_geometry_axi_writer;
    reg clk;
    reg rst_n;
    reg cfg_start;
    wire cfg_ready;
    reg abort;
    reg pixel_valid;
    wire pixel_ready;
    reg [15:0] pixel_data;
    reg [15:0] pixel_x;
    reg [15:0] pixel_y;
    reg pixel_sof;
    reg pixel_eol;
    reg pixel_eof;
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
    wire busy;
    wire done;
    wire error;

    integer checks;
    integer failures;
    integer pixel_i;
    integer guard;
    integer aw_count;
    reg [31:0] seen_addr_r [0:2];
    reg [7:0] seen_len_r [0:2];
    reg [255:0] memory_word_v;

    always #5 clk = ~clk;

    task automatic check_true;
        input condition;
        input [8*96-1:0] message;
        begin
            checks = checks + 1;
            if (!condition) begin
                failures = failures + 1;
                $display("CHECK_FAIL time=%0t %0s", $time, message);
            end
        end
    endtask

    edrv32_geometry_axi_writer u_dut (
        .clk_i(clk), .rst_n_i(rst_n),
        .cfg_start_i(cfg_start), .cfg_ready_o(cfg_ready), .abort_i(abort),
        .cfg_dst_base_i(32'h0000_0f00), .cfg_dst_stride_i(32'd800),
        .cfg_dst_width_i(16'd400), .cfg_dst_height_i(16'd1),
        .pixel_valid_i(pixel_valid), .pixel_ready_o(pixel_ready),
        .pixel_data_i(pixel_data), .pixel_dst_x_i(pixel_x),
        .pixel_dst_y_i(pixel_y), .pixel_sof_i(pixel_sof),
        .pixel_eol_i(pixel_eol), .pixel_eof_i(pixel_eof),
        .m_awid_o(awid), .m_awaddr_o(awaddr), .m_awlen_o(awlen),
        .m_awsize_o(awsize), .m_awburst_o(awburst), .m_awqos_o(awqos),
        .m_awvalid_o(awvalid), .m_awready_i(awready),
        .m_wdata_o(wdata), .m_wstrb_o(wstrb), .m_wlast_o(wlast),
        .m_wvalid_o(wvalid), .m_wready_i(wready),
        .m_bid_i(bid), .m_bresp_i(bresp), .m_bvalid_i(bvalid),
        .m_bready_o(bready), .busy_o(busy), .done_o(done), .error_o(error)
    );

    axi256_mem_model #(.ID_W(4), .WORDS(4096)) u_mem (
        .clk_i(clk), .rst_n_i(rst_n),
        .awid_i(awid), .awaddr_i(awaddr), .awlen_i(awlen),
        .awsize_i(awsize), .awburst_i(awburst),
        .awvalid_i(awvalid), .awready_o(awready),
        .wdata_i(wdata), .wstrb_i(wstrb), .wlast_i(wlast),
        .wvalid_i(wvalid), .wready_o(wready),
        .bid_o(bid), .bresp_o(bresp), .bvalid_o(bvalid), .bready_i(bready),
        .arid_i(4'b0), .araddr_i(32'b0), .arlen_i(8'b0),
        .arsize_i(3'd5), .arburst_i(2'b01), .arvalid_i(1'b0),
        .arready_o(), .rid_o(), .rdata_o(), .rresp_o(), .rlast_o(),
        .rvalid_o(), .rready_i(1'b1)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            aw_count <= 0;
        end else if (awvalid && awready) begin
            if (aw_count < 3) begin
                seen_addr_r[aw_count] <= awaddr;
                seen_len_r[aw_count] <= awlen;
            end
            aw_count <= aw_count + 1;
        end
    end

    task automatic start_writer;
        begin
            while (!cfg_ready)
                @(negedge clk);
            cfg_start = 1'b1;
            @(negedge clk);
            cfg_start = 1'b0;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        cfg_start = 1'b0;
        abort = 1'b0;
        pixel_valid = 1'b0;
        pixel_data = 16'b0;
        pixel_x = 16'b0;
        pixel_y = 16'b0;
        pixel_sof = 1'b0;
        pixel_eol = 1'b0;
        pixel_eof = 1'b0;
        checks = 0;
        failures = 0;
        aw_count = 0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);
        start_writer();

        for (pixel_i = 0; pixel_i < 400; pixel_i = pixel_i + 1) begin
            pixel_valid = 1'b1;
            pixel_data = pixel_i[15:0] ^ 16'h5a5a;
            pixel_x = pixel_i;
            pixel_y = 0;
            pixel_sof = pixel_i == 0;
            pixel_eol = pixel_i == 399;
            pixel_eof = pixel_i == 399;
            while (!pixel_ready)
                @(negedge clk);
            @(negedge clk);
        end
        pixel_valid = 1'b0;

        guard = 0;
        while (!done && guard < 5000) begin
            @(negedge clk);
            guard = guard + 1;
        end
        check_true(guard < 5000 && !error, "writer completes legal frame");
        check_true(aw_count == 3, "writer emits exactly three bursts");
        check_true(seen_addr_r[0] == 32'h0000_0f00 && seen_len_r[0] == 7,
                   "first burst stops at 4-KiB boundary");
        check_true(seen_addr_r[1] == 32'h0000_1000 && seen_len_r[1] == 15,
                   "second burst uses maximum 16 beats");
        check_true(seen_addr_r[2] == 32'h0000_1200 && seen_len_r[2] == 0,
                   "third burst writes final row beat");

        for (pixel_i = 0; pixel_i < 400; pixel_i = pixel_i + 1) begin
            memory_word_v = u_mem.store[(32'h0000_0f00 >> 5) + pixel_i/16];
            check_true(memory_word_v[(pixel_i%16)*16 +: 16] ==
                       (pixel_i[15:0] ^ 16'h5a5a),
                       "writer DDR payload matches input pixel");
        end

        @(negedge clk);
        start_writer();
        for (pixel_i = 0; pixel_i < 10; pixel_i = pixel_i + 1) begin
            pixel_valid = 1'b1;
            pixel_data = pixel_i;
            pixel_x = pixel_i;
            pixel_sof = pixel_i == 0;
            pixel_eol = 1'b0;
            pixel_eof = 1'b0;
            while (!pixel_ready)
                @(negedge clk);
            @(negedge clk);
        end
        pixel_valid = 1'b0;
        abort = 1'b1;
        @(negedge clk);
        abort = 1'b0;
        #1;
        check_true(done && error && cfg_ready,
                   "writer abort returns to idle with error completion");

        // Abort after AW ownership has transferred.  The writer must send
        // every accepted W beat and consume B before returning to idle.
        @(negedge clk);
        start_writer();
        for (pixel_i = 0; pixel_i < 128; pixel_i = pixel_i + 1) begin
            pixel_valid = 1'b1;
            pixel_data = pixel_i;
            pixel_x = pixel_i;
            pixel_y = 0;
            pixel_sof = pixel_i == 0;
            pixel_eol = 1'b0;
            pixel_eof = 1'b0;
            while (!pixel_ready)
                @(negedge clk);
            @(negedge clk);
        end
        pixel_valid = 1'b0;
        while (!(wvalid && wready && !wlast))
            @(negedge clk);
        abort = 1'b1;
        @(negedge clk);
        abort = 1'b0;
        check_true(!done && busy,
                   "mid-burst abort retains AXI write ownership");
        guard = 0;
        while (!done && guard < 100) begin
            @(negedge clk);
            guard = guard + 1;
        end
        check_true(done && error && cfg_ready &&
                   !u_mem.wr_active_r && !u_mem.bvalid_r,
                   "mid-burst abort drains all W beats and B response");

        if (failures == 0)
            $display("GEOMETRY_AXI_WRITER_PASS checks=%0d", checks);
        else
            $fatal(1, "GEOMETRY_AXI_WRITER_FAIL checks=%0d failures=%0d",
                   checks, failures);
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "Geometry AXI writer timeout");
    end

endmodule
