`timescale 1ns/1ps

module tb_yolo_v8n_exec;
    reg clk_i = 1'b0;
    always #5 clk_i = !clk_i;
    reg rst_n_i = 1'b0;
    reg cmd_valid_i = 1'b0;
    reg [1:0] cmd_op_i = 2'd0;
    reg [31:0] cmd_input_base_i = 32'h1000;
    reg [31:0] cmd_aux_base_i = 32'd0;
    reg [31:0] cmd_output_base_i = 32'h2000;
    reg [31:0] cmd_input_plane_stride_i = 32'd384;
    reg [31:0] cmd_output_plane_stride_i = 32'd384;
    reg [5:0] cmd_cin_blocks_i = 6'd1;
    wire cmd_ready_w, busy_w, done_w, error_w, mac_beat_w;
    wire [4:0] cfg_block_w, cfg_channel_w;
    wire cfg_ready_w;
    integer cfg_count_r = 0;
    integer mac_count_r = 0;
    integer read_count_r = 0;
    integer write_count_r = 0;
    integer idx, plane, row, pair, pix, ch;
    reg [255:0] actual_beat;
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

    edrv32_yolo_v8n_exec dut (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .cmd_valid_i(cmd_valid_i), .cmd_ready_o(cmd_ready_w),
        .cmd_op_i(cmd_op_i),
        .cmd_input_base_i(cmd_input_base_i),
        .cmd_aux_base_i(cmd_aux_base_i),
        .cmd_output_base_i(cmd_output_base_i),
        .cmd_input_plane_stride_i(cmd_input_plane_stride_i),
        .cmd_output_plane_stride_i(cmd_output_plane_stride_i),
        .cmd_weight_base_i(32'd0),
        .cmd_weight_block_stride_i(32'd0),
        .cmd_input_width_i(11'd8),
        .cmd_input_height_i(16'd3),
        .cmd_output_width_pairs_i(10'd4),
        .cmd_output_height_i(16'd3),
        .cmd_cin_blocks_i(cmd_cin_blocks_i),
        .cmd_output_blocks_i(5'd1),
        .cmd_cache_bank_stride_i(9'd2),
        .cmd_cache_row_stride_i(10'd2),
        .cmd_tile_pairs_i(10'd2),
        .cmd_kernel3_i(1'b0),
        .cmd_stride2_i(1'b0),
        .cmd_last_c16_only_i(1'b0),
        .cmd_beat_count_i(16'd12),
        .cmd_residual_zero_point_i(8'd0),
        .cmd_lut_enable_i(1'b0),
        .busy_o(busy_w), .done_o(done_w),
        .error_o(error_w), .mac_beat_o(mac_beat_w),
        .cfg_block_o(cfg_block_w), .cfg_channel_o(cfg_channel_w),
        .cfg_valid_i(1'b1), .cfg_ready_o(cfg_ready_w),
        .cfg_bias_i(32'd0), .cfg_multiplier_i(16'd1),
        .cfg_shift_i(6'd4), .cfg_zero_point_i(8'd0),
        .cfg_lut_valid_i(1'b0), .cfg_lut_ready_o(),
        .cfg_lut_addr_o(), .cfg_lut_data_i(8'd0),
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
            if (cfg_ready_w) begin
                if (cmd_op_i != 2'd0 || cfg_block_w != 5'd0 ||
                    cfg_channel_w != cfg_count_r)
                    $fatal(1, "Exec quant configuration mismatch");
                cfg_count_r <= cfg_count_r + 1;
            end
            if (mac_beat_w) mac_count_r <= mac_count_r + 1;
            if (rvalid_w && rready_w)
                read_count_r <= read_count_r + 1;
            if (wvalid_w && wready_w)
                write_count_r <= write_count_r + 1;
        end
    end

    task run_command;
        input [1:0] op;
        begin
            @(negedge clk_i);
            if (!cmd_ready_w) $fatal(1, "Exec command not ready");
            cmd_op_i = op;
            cmd_valid_i = 1'b1;
            @(negedge clk_i);
            cmd_valid_i = 1'b0;
            wait (done_w);
            #1;
            if (error_w || busy_w)
                $fatal(1, "Exec op %0d failed", op);
        end
    endtask

    initial begin
        for (idx = 0; idx < 16; idx = idx + 1)
            u_memory.store[idx] = {32{8'd1}};
        for (idx = 0; idx < 12; idx = idx + 1)
            u_memory.store[(32'h1000 >> 5)+idx] = {32{8'd1}};
        repeat (5) @(negedge clk_i);
        rst_n_i = 1'b1;
        run_command(2'd0);
        cmd_input_base_i = 32'h2000;
        cmd_aux_base_i = 32'h2180;
        cmd_output_base_i = 32'h2180;
        run_command(2'd1);
        cmd_input_base_i = 32'h2180;
        cmd_output_base_i = 32'h3000;
        cmd_cin_blocks_i = 6'd1;
        run_command(2'd2);
        cmd_input_base_i = 32'h3000;
        cmd_output_base_i = 32'h4000;
        cmd_output_plane_stride_i = 32'd1536;
        run_command(2'd3);

        if (cfg_count_r != 32 || mac_count_r != 24 ||
            read_count_r != 76 || write_count_r != 96)
            $fatal(1, "Exec counts cfg=%0d mac=%0d read=%0d write=%0d",
                   cfg_count_r, mac_count_r,
                   read_count_r, write_count_r);
        for (idx = 0; idx < 12; idx = idx + 1)
            if (u_memory.store[(32'h2000 >> 5)+idx] !== {32{8'd1}} ||
                u_memory.store[(32'h2180 >> 5)+idx] !== {32{8'd2}} ||
                u_memory.store[(32'h3000 >> 5)+idx] !== {32{8'd2}})
                $fatal(1, "Exec intermediate mismatch beat=%0d", idx);
        for (row = 0; row < 6; row = row + 1)
            for (pair = 0; pair < 8; pair = pair + 1) begin
                actual_beat = u_memory.store[(32'h4000 >> 5)+row*8+pair];
                if (actual_beat !== {32{8'd2}})
                    $fatal(1, "Exec output mismatch row=%0d pair=%0d",
                           row, pair);
            end
        $display("PASS YOLO shared exec: CONV -> ADD -> MAXPOOL5 -> UPSAMPLE2x cfg=%0d mac=%0d read=%0d write=%0d",
                 cfg_count_r, mac_count_r,
                 read_count_r, write_count_r);
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "Exec timeout state=%0d op=%0d", dut.state_r,
               dut.op_r);
    end
endmodule
