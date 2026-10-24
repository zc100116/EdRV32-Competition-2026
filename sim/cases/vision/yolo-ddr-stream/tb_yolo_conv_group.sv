`timescale 1ns/1ps

module tb_yolo_conv_group;
    reg clk_i = 1'b0;
    reg rst_n_i = 1'b0;
    always #5 clk_i = !clk_i;

    reg start_i = 1'b0;
    wire start_ready_w;
    reg [31:0] feature_base_i = 32'd0;
    reg [31:0] feature_plane_stride_i = 32'd512;
    reg [31:0] weight_base_i = 32'd0;
    reg [31:0] weight_block_stride_i = 32'd0;
    reg [31:0] output_base_i = 32'd0;
    reg [31:0] output_plane_stride_i = 32'd512;
    reg [4:0] output_blocks_i = 5'd1;
    reg last_block_c16_only_i = 1'b0;
    reg [10:0] input_width_i = 11'd8;
    reg [15:0] input_height_i = 16'd4;
    reg [9:0] output_width_pairs_i = 10'd4;
    reg [15:0] output_height_i = 16'd4;
    reg [5:0] cin_blocks_i = 6'd1;
    reg [8:0] cache_bank_stride_i = 9'd2;
    reg [9:0] cache_row_stride_i = 10'd2;
    wire busy_w;
    wire done_w;
    wire error_w;
    wire mac_beat_w;
    wire [4:0] cfg_block_w;
    wire [4:0] cfg_channel_w;
    wire cfg_ready_w;

    wire [3:0] arid_w, rid_w, awid_w, bid_w;
    wire [31:0] araddr_w, awaddr_w;
    wire [7:0] arlen_w, awlen_w;
    wire [2:0] arsize_w, awsize_w;
    wire [1:0] arburst_w, awburst_w, rresp_w, bresp_w;
    wire arvalid_w, arready_w, rlast_w, rvalid_w, rready_w;
    wire awvalid_w, awready_w, wlast_w, wvalid_w, wready_w;
    wire bvalid_w, bready_w;
    wire [255:0] rdata_w, wdata_w;
    wire [31:0] wstrb_w;

    integer cfg_count_r = 0;
    integer cycle_count_r = 0;
    integer mac_count_r = 0;
    integer read_count_r = 0;
    integer write_count_r = 0;
    integer layer_number_r = 0;
    integer idx;
    integer plane;
    integer beat;
    reg [7:0] expected_byte;

    edrv32_yolo_conv_group dut (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .start_i(start_i), .start_ready_o(start_ready_w),
        .feature_base_i(feature_base_i),
        .feature_plane_stride_i(feature_plane_stride_i),
        .weight_base_i(weight_base_i),
        .weight_block_stride_i(weight_block_stride_i),
        .output_base_i(output_base_i),
        .output_plane_stride_i(output_plane_stride_i),
        .output_blocks_i(output_blocks_i),
        .last_block_c16_only_i(last_block_c16_only_i),
        .input_width_i(input_width_i),
        .input_height_i(input_height_i),
        .output_width_pairs_i(output_width_pairs_i),
        .output_height_i(output_height_i),
        .cin_blocks_i(cin_blocks_i),
        .cache_bank_stride_i(cache_bank_stride_i),
        .cache_row_stride_i(cache_row_stride_i),
        .tile_pairs_i(10'd2),
        .kernel3_i(1'b0), .stride2_i(1'b0),
        .busy_o(busy_w), .done_o(done_w),
        .error_o(error_w), .mac_beat_o(mac_beat_w),
        .cfg_block_o(cfg_block_w), .cfg_channel_o(cfg_channel_w),
        .cfg_valid_i(cycle_count_r % 5 != 2),
        .cfg_ready_o(cfg_ready_w),
        .cfg_bias_i(32'd0),
        .cfg_multiplier_i(layer_number_r == 2 && cfg_block_w == 5'd1 ?
                          16'd2 : 16'd1),
        .cfg_shift_i(6'd4),
        .cfg_zero_point_i(8'd0),
        .lut_enable_i(1'b0), .lut_cfg_valid_i(1'b0),
        .lut_cfg_ready_o(), .lut_cfg_addr_o(),
        .lut_cfg_data_i(8'd0),
        .m_arid_o(arid_w), .m_araddr_o(araddr_w),
        .m_arlen_o(arlen_w), .m_arsize_o(arsize_w),
        .m_arburst_o(arburst_w), .m_arvalid_o(arvalid_w),
        .m_arready_i(arready_w), .m_rid_i(rid_w),
        .m_rdata_i(rdata_w), .m_rresp_i(rresp_w),
        .m_rlast_i(rlast_w), .m_rvalid_i(rvalid_w),
        .m_rready_o(rready_w),
        .m_awid_o(awid_w), .m_awaddr_o(awaddr_w),
        .m_awlen_o(awlen_w), .m_awsize_o(awsize_w),
        .m_awburst_o(awburst_w), .m_awvalid_o(awvalid_w),
        .m_awready_i(awready_w), .m_wdata_o(wdata_w),
        .m_wstrb_o(wstrb_w), .m_wlast_o(wlast_w),
        .m_wvalid_o(wvalid_w), .m_wready_i(wready_w),
        .m_bid_i(bid_w), .m_bresp_i(bresp_w),
        .m_bvalid_i(bvalid_w), .m_bready_o(bready_w)
    );

    axi256_mem_model #(.WORDS(4096)) u_memory (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .awid_i(awid_w), .awaddr_i(awaddr_w),
        .awlen_i(awlen_w), .awsize_i(awsize_w),
        .awburst_i(awburst_w), .awvalid_i(awvalid_w),
        .awready_o(awready_w),
        .wdata_i(wdata_w), .wstrb_i(wstrb_w),
        .wlast_i(wlast_w), .wvalid_i(wvalid_w),
        .wready_o(wready_w),
        .bid_o(bid_w), .bresp_o(bresp_w),
        .bvalid_o(bvalid_w), .bready_i(bready_w),
        .arid_i(arid_w), .araddr_i(araddr_w),
        .arlen_i(arlen_w), .arsize_i(arsize_w),
        .arburst_i(arburst_w), .arvalid_i(arvalid_w),
        .arready_o(arready_w),
        .rid_o(rid_w), .rdata_o(rdata_w),
        .rresp_o(rresp_w), .rlast_o(rlast_w),
        .rvalid_o(rvalid_w), .rready_i(rready_w)
    );

    always @(posedge clk_i) begin
        if (rst_n_i) begin
            cycle_count_r <= cycle_count_r + 1;
            if (cfg_ready_w && cycle_count_r % 5 != 2) begin
                if (cfg_channel_w != cfg_count_r % 32 ||
                    (layer_number_r == 2 &&
                     cfg_block_w != (cfg_count_r - 32) / 32))
                    $fatal(1, "Quant request order layer=%0d block=%0d channel=%0d count=%0d",
                           layer_number_r, cfg_block_w,
                           cfg_channel_w, cfg_count_r);
                cfg_count_r <= cfg_count_r + 1;
            end
            if (mac_beat_w)
                mac_count_r <= mac_count_r + 1;
            if (rvalid_w && rready_w)
                read_count_r <= read_count_r + 1;
            if (wvalid_w && wready_w)
                write_count_r <= write_count_r + 1;
        end
    end

    task automatic start_layer;
        input integer layer_i;
        input [31:0] feature_i;
        input [31:0] weight_i;
        input [31:0] weight_stride_i;
        input [31:0] output_i;
        input [5:0] cin_i;
        input [4:0] blocks_i;
        begin
            @(negedge clk_i);
            layer_number_r = layer_i;
            feature_base_i = feature_i;
            weight_base_i = weight_i;
            weight_block_stride_i = weight_stride_i;
            output_base_i = output_i;
            cin_blocks_i = cin_i;
            output_blocks_i = blocks_i;
            cache_bank_stride_i = input_width_i >> 2;
            cache_row_stride_i = cin_i * cache_bank_stride_i;
            if (!start_ready_w)
                $fatal(1, "CONV group not ready for layer %0d", layer_i);
            start_i = 1'b1;
            @(negedge clk_i);
            start_i = 1'b0;
            wait (done_w);
            #1;
            if (error_w || busy_w)
                $fatal(1, "CONV group error on layer %0d", layer_i);
        end
    endtask

    task automatic check_surface;
        input [31:0] base_i;
        input integer plane_count_i;
        input integer first_value_i;
        input integer second_value_i;
        begin
            for (plane = 0; plane < plane_count_i; plane = plane + 1) begin
                expected_byte = plane < 2 ? first_value_i : second_value_i;
                for (beat = 0; beat < 16; beat = beat + 1) begin
                    if (u_memory.store[(base_i >> 5) + plane*16 + beat]
                        !== {32{expected_byte}})
                        $fatal(1, "Surface mismatch base=%h plane=%0d beat=%0d got=%h expected=%h",
                               base_i, plane, beat,
                               u_memory.store[(base_i >> 5) +
                                              plane*16 + beat],
                               {32{expected_byte}});
                end
            end
        end
    endtask

    initial begin
        // Three dependent layers: C16->C32, C32->C64, C64->C32.
        for (idx = 0; idx < 16; idx = idx + 1)
            u_memory.store[(32'h0000 >> 5) + idx] = {32{8'd1}};
        for (idx = 0; idx < 32; idx = idx + 1) begin
            u_memory.store[(32'h1000 >> 5) + idx] = {32{8'd1}};
            u_memory.store[(32'h1400 >> 5) + idx] = {32{8'd2}};
        end
        for (idx = 0; idx < 64; idx = idx + 1)
            u_memory.store[(32'h2000 >> 5) + idx] = {32{8'd1}};
        for (idx = 0; idx < 48; idx = idx + 1)
            u_memory.store[(32'h3000 >> 5) + idx] = {32{8'd1}};
        for (idx = 0; idx < 16; idx = idx + 1)
            u_memory.store[(32'h4000 >> 5) + idx] = {32{8'd1}};

        repeat (5) @(negedge clk_i);
        rst_n_i = 1'b1;
        start_layer(1, 32'h4000, 32'h0000, 32'd512,
                    32'h8000, 5'd1, 5'd1);
        check_surface(32'h8000, 2, 1, 1);
        if (cfg_count_r != 32)
            $fatal(1, "First layer config count %0d", cfg_count_r);

        start_layer(2, 32'h8000, 32'h1000, 32'd1024,
                    32'hA000, 5'd2, 5'd2);
        check_surface(32'hA000, 4, 2, 8);
        if (cfg_count_r != 96)
            $fatal(1, "Second layer config count %0d", cfg_count_r);

        start_layer(3, 32'hA000, 32'h2000, 32'd2048,
                    32'hC000, 5'd4, 5'd1);
        check_surface(32'hC000, 2, 20, 20);
        if (cfg_count_r != 128 || mac_count_r != 288 ||
            read_count_r != 288 || write_count_r != 128)
            $fatal(1, "Chain counters cfg=%0d mac=%0d read=%0d write=%0d",
                   cfg_count_r, mac_count_r, read_count_r,
                   write_count_r);

        // C2f-style concatenation is represented by adjacent C16 planes.
        // The consumer reads three planes directly without a copy pass.
        start_layer(4, 32'hA000, 32'h3000, 32'd1536,
                    32'hE000, 5'd3, 5'd1);
        check_surface(32'hE000, 2, 12, 12);

        // A YOLOv8n head 1x1 source can exceed the five-row cache layout.
        // Five output rows must still work by reusing cache slot zero.
        for (idx = 0; idx < 384; idx = idx + 1)
            u_memory.store[idx] = {32{8'd1}};
        for (idx = 0; idx < 2400; idx = idx + 1)
            u_memory.store[(32'h4000 >> 5) + idx] = {32{8'd1}};
        input_width_i = 11'd40;
        input_height_i = 16'd5;
        output_width_pairs_i = 10'd20;
        output_height_i = 16'd5;
        feature_plane_stride_i = 32'd3200;
        output_plane_stride_i = 32'd3200;
        start_layer(5, 32'h4000, 32'h0000, 32'd12288,
                    32'h18000, 5'd24, 5'd1);
        for (plane = 0; plane < 2; plane = plane + 1)
            for (beat = 0; beat < 100; beat = beat + 1)
                if (u_memory.store[(32'h18000 >> 5) + plane*100 + beat]
                    !== {32{8'd24}})
                    $fatal(1, "Wide 1x1 surface mismatch plane=%0d beat=%0d got=%h",
                           plane, beat,
                           u_memory.store[(32'h18000 >> 5) +
                                          plane*100 + beat]);
        if (cfg_count_r != 192 || mac_count_r != 5184 ||
            read_count_r != 3168 || write_count_r != 360)
            $fatal(1, "Wide 1x1 counters cfg=%0d mac=%0d read=%0d write=%0d",
                   cfg_count_r, mac_count_r, read_count_r,
                   write_count_r);

        // The SPPF fusion shape needs all 32 C16 input blocks (512 channels).
        for (idx = 0; idx < 512; idx = idx + 1)
            u_memory.store[idx] = {32{8'd1}};
        for (idx = 0; idx < 1600; idx = idx + 1)
            u_memory.store[(32'h4000 >> 5) + idx] = {32{8'd1}};
        input_width_i = 11'd20;
        input_height_i = 16'd5;
        output_width_pairs_i = 10'd10;
        output_height_i = 16'd5;
        feature_plane_stride_i = 32'd1600;
        output_plane_stride_i = 32'd1600;
        start_layer(6, 32'h4000, 32'h0000, 32'd16384,
                    32'h18000, 6'd32, 5'd1);
        for (plane = 0; plane < 2; plane = plane + 1)
            for (beat = 0; beat < 50; beat = beat + 1)
                if (u_memory.store[(32'h18000 >> 5) + plane*50 + beat]
                    !== {32{8'd32}})
                    $fatal(1, "C512 1x1 surface mismatch plane=%0d beat=%0d got=%h",
                           plane, beat,
                           u_memory.store[(32'h18000 >> 5) +
                                          plane*50 + beat]);
        if (cfg_count_r != 224 || mac_count_r != 8384 ||
            read_count_r != 5280 || write_count_r != 460)
            $fatal(1, "C512 counters cfg=%0d mac=%0d read=%0d write=%0d",
                   cfg_count_r, mac_count_r, read_count_r,
                   write_count_r);

        // YOLOv8n's first layer produces C16: no second C16 plane is written.
        for (idx = 0; idx < 16; idx = idx + 1)
            u_memory.store[(32'h1C000 >> 5) + 16 + idx] =
                {32{8'hA5}};
        input_width_i = 11'd8;
        input_height_i = 16'd4;
        output_width_pairs_i = 10'd4;
        output_height_i = 16'd4;
        feature_plane_stride_i = 32'd512;
        output_plane_stride_i = 32'd512;
        last_block_c16_only_i = 1'b1;
        start_layer(7, 32'h4000, 32'h0000, 32'd512,
                    32'h1C000, 6'd1, 5'd1);
        check_surface(32'h1C000, 1, 1, 1);
        for (idx = 0; idx < 16; idx = idx + 1)
            if (u_memory.store[(32'h1C000 >> 5) + 16 + idx]
                !== {32{8'hA5}})
                $fatal(1, "Disabled output plane was modified at beat %0d", idx);
        if (cfg_count_r != 256 || mac_count_r != 8416 ||
            read_count_r != 5312 || write_count_r != 476)
            $fatal(1, "C16 output counters cfg=%0d mac=%0d read=%0d write=%0d",
                   cfg_count_r, mac_count_r, read_count_r,
                   write_count_r);
        $display("PASS YOLO DDR chain, concat, C384/C512, C16 output: cfg=%0d mac=%0d read=%0d write=%0d",
                 cfg_count_r, mac_count_r, read_count_r, write_count_r);
        $finish;
    end

    initial begin
        #2000000;
        $fatal(1, "YOLO CONV group timeout layer=%0d state=%0d block=%0d",
               layer_number_r, dut.state_r, cfg_block_w);
    end
endmodule
