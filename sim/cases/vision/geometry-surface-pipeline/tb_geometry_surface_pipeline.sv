`timescale 1ns/1ps

module tb_geometry_surface_pipeline;
    localparam [31:0] SRC_BASE = 32'h0000_0000;
    localparam [31:0] DST_BASE = 32'h0001_0000;
    localparam [31:0] STRIDE = 32'd64;

    reg clk;
    reg rst_n;
    reg cfg_start;
    wire cfg_ready;
    reg [8:0] cfg_angle;
    reg [15:0] cfg_image_width;
    wire [3:0] rd_arid;
    wire [31:0] rd_araddr;
    wire [7:0] rd_arlen;
    wire [2:0] rd_arsize;
    wire [1:0] rd_arburst;
    wire [3:0] rd_arqos;
    wire rd_arvalid;
    wire rd_arready;
    wire [3:0] rd_rid;
    wire [255:0] rd_rdata;
    wire [1:0] rd_rresp;
    wire rd_rlast;
    wire rd_rvalid;
    wire rd_rready;
    wire [3:0] wr_awid;
    wire [31:0] wr_awaddr;
    wire [7:0] wr_awlen;
    wire [2:0] wr_awsize;
    wire [1:0] wr_awburst;
    wire [3:0] wr_awqos;
    wire wr_awvalid;
    wire wr_awready;
    wire [255:0] wr_wdata;
    wire [31:0] wr_wstrb;
    wire wr_wlast;
    wire wr_wvalid;
    wire wr_wready;
    wire [3:0] wr_bid;
    wire [1:0] wr_bresp;
    wire wr_bvalid;
    wire wr_bready;
    wire busy;
    wire done;
    wire error;

    integer checks;
    integer failures;
    integer mem_y;
    integer mem_block;
    integer mem_lane;
    integer check_x;
    integer check_y;
    integer guard;
    reg [255:0] mem_word_v;
    reg [15:0] actual_pixel_v;
    reg [15:0] expected_pixel_v;

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

    edrv32_geometry_surface_pipeline u_dut (
        .clk_i(clk), .rst_n_i(rst_n),
        .cfg_start_i(cfg_start), .cfg_ready_o(cfg_ready),
        .cfg_src_base_i(SRC_BASE), .cfg_src_stride_i(STRIDE),
        .cfg_src_width_i(16'd32), .cfg_src_height_i(16'd32),
        .cfg_crop_x_i(16'd8), .cfg_crop_y_i(16'd8),
        .cfg_crop_width_i(16'd20), .cfg_crop_height_i(16'd20),
        .cfg_dst_base_i(DST_BASE), .cfg_dst_stride_i(STRIDE),
        .cfg_dst_width_i(16'd20), .cfg_dst_height_i(16'd20),
        .cfg_image_width_i(cfg_image_width),
        .cfg_image_height_i(16'd20),
        .cfg_angle_i(cfg_angle), .cfg_flip_x_i(1'b0),
        .cfg_flip_y_i(1'b0), .cfg_fill_pixel_i(16'h0000),
        .rd_arid_o(rd_arid), .rd_araddr_o(rd_araddr),
        .rd_arlen_o(rd_arlen), .rd_arsize_o(rd_arsize),
        .rd_arburst_o(rd_arburst), .rd_arqos_o(rd_arqos),
        .rd_arvalid_o(rd_arvalid), .rd_arready_i(rd_arready),
        .rd_rid_i(rd_rid), .rd_rdata_i(rd_rdata),
        .rd_rresp_i(rd_rresp), .rd_rlast_i(rd_rlast),
        .rd_rvalid_i(rd_rvalid), .rd_rready_o(rd_rready),
        .wr_awid_o(wr_awid), .wr_awaddr_o(wr_awaddr),
        .wr_awlen_o(wr_awlen), .wr_awsize_o(wr_awsize),
        .wr_awburst_o(wr_awburst), .wr_awqos_o(wr_awqos),
        .wr_awvalid_o(wr_awvalid), .wr_awready_i(wr_awready),
        .wr_wdata_o(wr_wdata), .wr_wstrb_o(wr_wstrb),
        .wr_wlast_o(wr_wlast), .wr_wvalid_o(wr_wvalid),
        .wr_wready_i(wr_wready), .wr_bid_i(wr_bid),
        .wr_bresp_i(wr_bresp), .wr_bvalid_i(wr_bvalid),
        .wr_bready_o(wr_bready),
        .busy_o(busy), .done_o(done), .error_o(error),
        .profile_phase_o()
    );

    axi256_mem_model #(.ID_W(4), .WORDS(4096)) u_mem (
        .clk_i(clk), .rst_n_i(rst_n),
        .awid_i(wr_awid), .awaddr_i(wr_awaddr), .awlen_i(wr_awlen),
        .awsize_i(wr_awsize), .awburst_i(wr_awburst),
        .awvalid_i(wr_awvalid), .awready_o(wr_awready),
        .wdata_i(wr_wdata), .wstrb_i(wr_wstrb), .wlast_i(wr_wlast),
        .wvalid_i(wr_wvalid), .wready_o(wr_wready),
        .bid_o(wr_bid), .bresp_o(wr_bresp), .bvalid_o(wr_bvalid),
        .bready_i(wr_bready),
        .arid_i(rd_arid), .araddr_i(rd_araddr), .arlen_i(rd_arlen),
        .arsize_i(rd_arsize), .arburst_i(rd_arburst),
        .arvalid_i(rd_arvalid), .arready_o(rd_arready),
        .rid_o(rd_rid), .rdata_o(rd_rdata), .rresp_o(rd_rresp),
        .rlast_o(rd_rlast), .rvalid_o(rd_rvalid), .rready_i(rd_rready)
    );

    task automatic initialize_destination;
        begin
            for (mem_y = 0; mem_y < 20; mem_y = mem_y + 1)
                for (mem_block = 0; mem_block < 2; mem_block = mem_block + 1)
                    u_mem.store[(DST_BASE >> 5) + mem_y*2 + mem_block] =
                        {16{16'ha5a5}};
        end
    endtask

    task automatic run_and_check;
        input integer angle_i;
        input integer image_width_i;
        begin
            initialize_destination();
            while (!cfg_ready)
                @(negedge clk);
            cfg_angle = angle_i;
            cfg_image_width = image_width_i;
            cfg_start = 1'b1;
            @(negedge clk);
            cfg_start = 1'b0;
            guard = 0;
            while (!done && guard < 200000) begin
                @(negedge clk);
                guard = guard + 1;
            end
            check_true(guard < 200000, "surface geometry operation completes");
            check_true(!error, "surface geometry operation has no error");

            for (check_y = 0; check_y < 20; check_y = check_y + 1) begin
                for (check_x = 0; check_x < 20; check_x = check_x + 1) begin
                    mem_word_v = u_mem.store[(DST_BASE >> 5) +
                                             check_y*2 + check_x/16];
                    actual_pixel_v = mem_word_v[(check_x%16)*16 +: 16];
                    if (image_width_i != 20) begin
                        if ((check_x < 5) || (check_x >= 15))
                            check_true(actual_pixel_v == 16'h0000,
                                "scaled image has black side borders");
                        else if (check_x == 5)
                            check_true(actual_pixel_v == pattern_pixel(
                                8, 8 + check_y),
                                "scaled image begins at source left edge");
                        else if (check_x == 14)
                            check_true(actual_pixel_v == pattern_pixel(
                                27, 8 + check_y),
                                "scaled image ends at source right edge");
                    end else if (angle_i == 0)
                        expected_pixel_v = pattern_pixel(
                            8 + check_x, 8 + check_y);
                    else
                        expected_pixel_v = pattern_pixel(
                            8 + check_y, 8 + 19 - check_x);
                    if (image_width_i == 20)
                        check_true(actual_pixel_v == expected_pixel_v,
                            "destination DDR pixel matches geometry output");
                end
                mem_word_v = u_mem.store[(DST_BASE >> 5) + check_y*2 + 1];
                for (check_x = 4; check_x < 16; check_x = check_x + 1)
                    check_true(mem_word_v[check_x*16 +: 16] == 16'ha5a5,
                               "partial row WSTRB preserves padding pixel");
            end
            @(negedge clk);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        cfg_start = 1'b0;
        cfg_angle = 9'b0;
        cfg_image_width = 16'd20;
        checks = 0;
        failures = 0;

        for (mem_y = 0; mem_y < 32; mem_y = mem_y + 1) begin
            for (mem_block = 0; mem_block < 2; mem_block = mem_block + 1) begin
                mem_word_v = 256'b0;
                for (mem_lane = 0; mem_lane < 16; mem_lane = mem_lane + 1)
                    mem_word_v[mem_lane*16 +: 16] = pattern_pixel(
                        mem_block*16 + mem_lane, mem_y);
                u_mem.store[mem_y*2 + mem_block] = mem_word_v;
            end
        end

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        run_and_check(0, 20);
        run_and_check(90, 20);
        run_and_check(0, 10);

        if (failures == 0)
            $display("GEOMETRY_SURFACE_PIPELINE_PASS checks=%0d", checks);
        else
            $fatal(1,
                   "GEOMETRY_SURFACE_PIPELINE_FAIL checks=%0d failures=%0d",
                   checks, failures);
        $finish;
    end

    initial begin
        #5000000;
        $fatal(1, "Geometry Surface pipeline timeout");
    end

endmodule
