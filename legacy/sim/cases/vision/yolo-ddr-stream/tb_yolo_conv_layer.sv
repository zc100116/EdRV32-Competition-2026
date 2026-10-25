`timescale 1ns/1ps

module tb_yolo_conv_layer;
    reg clk_i = 1'b0;
    always #5 clk_i = !clk_i;
    reg rst_n_i = 1'b0;
    reg start_i = 1'b0;
    wire start_ready_w;
    wire busy_w;
    wire done_w;
    wire error_w;
    wire mac_beat_w;
    reg cfg_valid_i = 1'b0;
    wire cfg_ready_w;
    reg [4:0] cfg_channel_i = 5'd0;
    wire [3:0] arid_w;
    wire [31:0] araddr_w;
    wire [7:0] arlen_w;
    wire [2:0] arsize_w;
    wire [1:0] arburst_w;
    wire arvalid_w;
    wire arready_w = cycle_r % 7 != 2;
    reg [255:0] rdata_r = 256'd0;
    reg rvalid_r = 1'b0;
    reg rlast_r = 1'b0;
    wire rready_w;
    wire [3:0] awid_w;
    wire [31:0] awaddr_w;
    wire [7:0] awlen_w;
    wire [2:0] awsize_w;
    wire [1:0] awburst_w;
    wire awvalid_w;
    wire awready_w = cycle_r % 9 != 3;
    wire [255:0] wdata_w;
    wire [31:0] wstrb_w;
    wire wlast_w;
    wire wvalid_w;
    wire wready_w = cycle_r % 8 != 5;
    wire bvalid_w = b_pending > 0 && cycle_r % 5 != 1;
    wire bready_w;

    integer cycle_r = 0;
    integer arq_addr [0:63];
    integer arq_len [0:63];
    integer arq_wr = 0;
    integer arq_rd = 0;
    integer arq_pos = 0;
    integer outstanding = 0;
    integer max_outstanding = 0;
    integer read_weight_beats = 0;
    integer read_feature_beats = 0;
    integer read_feature_bursts = 0;
    integer read_weight_bursts = 0;
    integer mac_beats = 0;
    integer output_beats = 0;
    integer overlap_seen = 0;
    integer b_pending = 0;
    integer aw_active = 0;
    integer aw_addr = 0;
    integer aw_len = 0;
    integer aw_pos = 0;
    integer current_addr;
    integer row;
    integer pair_index;
    integer plane;
    integer ch;
    integer expected0;
    integer expected1;
    integer wlast_fire;
    integer bfire;
    integer arfire;
    integer rfire;
    integer channel;
    integer case_mode = 1;
    reg [15:0] cfg_input_height = 16'd3;
    reg [9:0] cfg_output_pairs = 10'd4;
    reg [15:0] cfg_output_height = 16'd3;
    reg cfg_kernel3 = 1'b1;
    reg cfg_stride2 = 1'b0;
    reg [31:0] cfg_feature_plane_stride = 32'd384;
    reg [5:0] cfg_cin_blocks = 6'd1;
    reg [9:0] cfg_cache_row_stride = 10'd2;

    edrv32_yolo_conv_layer dut (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .start_i(start_i), .start_ready_o(start_ready_w),
        .feature_base_i(32'h0001_0000),
        .feature_plane_stride_i(cfg_feature_plane_stride),
        .weight_base_i(32'h0000_0000),
        .output_plane0_base_i(32'h0002_0000),
        .output_plane1_base_i(32'h0003_0000),
        .output_plane1_enable_i(1'b1),
        .input_width_i(11'd8), .input_height_i(cfg_input_height),
        .output_width_pairs_i(cfg_output_pairs),
        .output_height_i(cfg_output_height),
        .cin_blocks_i(cfg_cin_blocks),
        .cache_bank_stride_i(9'd2),
        .cache_row_stride_i(cfg_cache_row_stride),
        .tile_pairs_i(10'd2),
        .kernel3_i(cfg_kernel3), .stride2_i(cfg_stride2),
        .busy_o(busy_w), .done_o(done_w),
        .error_o(error_w), .mac_beat_o(mac_beat_w),
        .quant_cfg_valid_i(cfg_valid_i),
        .quant_cfg_ready_o(cfg_ready_w),
        .quant_cfg_channel_i(cfg_channel_i),
        .quant_cfg_bias_i(32'd0),
        .quant_cfg_multiplier_i(16'd1),
        .quant_cfg_shift_i(6'd4),
        .quant_cfg_zero_point_i(8'd0),
        .lut_enable_i(1'b0), .lut_cfg_valid_i(1'b0),
        .lut_cfg_ready_o(), .lut_cfg_addr_i(8'd0),
        .lut_cfg_data_i(8'd0),
        .m_arid_o(arid_w), .m_araddr_o(araddr_w),
        .m_arlen_o(arlen_w), .m_arsize_o(arsize_w),
        .m_arburst_o(arburst_w), .m_arvalid_o(arvalid_w),
        .m_arready_i(arready_w), .m_rid_i(4'h8),
        .m_rdata_i(rdata_r), .m_rresp_i(2'b00),
        .m_rlast_i(rlast_r), .m_rvalid_i(rvalid_r),
        .m_rready_o(rready_w),
        .m_awid_o(awid_w), .m_awaddr_o(awaddr_w),
        .m_awlen_o(awlen_w), .m_awsize_o(awsize_w),
        .m_awburst_o(awburst_w), .m_awvalid_o(awvalid_w),
        .m_awready_i(awready_w), .m_wdata_o(wdata_w),
        .m_wstrb_o(wstrb_w), .m_wlast_o(wlast_w),
        .m_wvalid_o(wvalid_w), .m_wready_i(wready_w),
        .m_bid_i(4'h9), .m_bresp_i(2'b00),
        .m_bvalid_i(bvalid_w), .m_bready_o(bready_w)
    );

    function integer expected_pixel;
        input integer yy;
        input integer xx;
        integer ky;
        integer kx;
        integer taps;
        begin
            taps = 0;
            if (case_mode == 0 || case_mode == 3)
                taps = yy*2+xx+1;
            else
                for (ky = -1; ky <= 1; ky = ky + 1)
                    for (kx = -1; kx <= 1; kx = kx + 1)
                        if (yy*(cfg_stride2 ? 2 : 1)+ky >= 0 &&
                            yy*(cfg_stride2 ? 2 : 1)+ky < cfg_input_height &&
                            xx*(cfg_stride2 ? 2 : 1)+kx >= 0 &&
                            xx*(cfg_stride2 ? 2 : 1)+kx < 8)
                            taps = taps +
                                (yy*(cfg_stride2 ? 2 : 1)+ky)*2 +
                                (xx*(cfg_stride2 ? 2 : 1)+kx)+1;
            expected_pixel = case_mode == 3 ? taps*2+1 : taps;
        end
    endfunction

    always @(negedge clk_i) begin
        if (rst_n_i) begin
            rvalid_r = arq_rd < arq_wr && cycle_r % 6 != 3;
            current_addr = arq_addr[arq_rd] + arq_pos*32;
            rdata_r = {32{8'h01}};
            if (current_addr >= 32'h10000 &&
                current_addr < 32'h20000) begin
                row = (current_addr - 32'h10000)%
                      cfg_feature_plane_stride/128;
                pair_index = (current_addr - 32'h10000)%128/32;
                for (ch = 0; ch < 16; ch = ch+1) begin
                    rdata_r[ch*8 +: 8] = row*2+pair_index*2+1+
                        (current_addr-32'h10000)/
                        cfg_feature_plane_stride;
                    rdata_r[(16+ch)*8 +: 8] = row*2+pair_index*2+2+
                        (current_addr-32'h10000)/
                        cfg_feature_plane_stride;
                end
            end
            rlast_r = rvalid_r && arq_pos+1 == arq_len[arq_rd];
        end
    end

    always @(posedge clk_i) begin
        if (rst_n_i) begin
            cycle_r <= cycle_r+1;
            arfire = arvalid_w && arready_w;
            rfire = rvalid_r && rready_w;
            if (arfire) begin
                if (arid_w != 4'h8 || arsize_w != 3'd5 ||
                    arburst_w != 2'b01 || arlen_w > 15 ||
                    araddr_w[4:0] != 5'd0 ||
                    araddr_w[11:0]+(arlen_w+1)*32 > 4096)
                    $fatal(1, "Invalid AR addr=%h len=%0d", araddr_w, arlen_w);
                arq_addr[arq_wr] <= araddr_w;
                arq_len[arq_wr] <= arlen_w+1;
                arq_wr <= arq_wr+1;
                if (araddr_w < 32'h10000)
                    read_weight_bursts <= read_weight_bursts+1;
                else
                    read_feature_bursts <= read_feature_bursts+1;
                if (outstanding+1 > max_outstanding)
                    max_outstanding <= outstanding+1;
            end
            if (rfire) begin
                if (current_addr < 32'h10000)
                    read_weight_beats <= read_weight_beats+1;
                else if (current_addr < 32'h20000)
                    read_feature_beats <= read_feature_beats+1;
                else
                    $fatal(1, "Read from wrong region %h", current_addr);
                if (rlast_r) begin
                    arq_rd <= arq_rd+1;
                    arq_pos <= 0;
                end else
                    arq_pos <= arq_pos+1;
            end
            outstanding <= outstanding + arfire - (rfire && rlast_r);
            if (mac_beat_w)
                mac_beats <= mac_beats+1;
            if (dut.patch_busy_w && dut.conv_busy_w)
                overlap_seen <= 1;

            if (awvalid_w && awready_w) begin
                if (aw_active || awid_w != 4'h9 || awlen_w > 15 ||
                    awsize_w != 3'd5 || awburst_w != 2'b01 ||
                    awaddr_w[4:0] != 5'd0 ||
                    awaddr_w[11:0]+(awlen_w+1)*32 > 4096)
                    $fatal(1, "Invalid AW addr=%h len=%0d", awaddr_w, awlen_w);
                aw_addr <= awaddr_w;
                aw_len <= awlen_w+1;
                aw_pos <= 0;
                aw_active <= 1;
            end
            if (wvalid_w && wready_w) begin
                if (!aw_active || wstrb_w != 32'hffff_ffff ||
                    wlast_w != (aw_pos+1 == aw_len))
                    $fatal(1, "Invalid W control");
                plane = aw_addr >= 32'h30000 ? 1 : 0;
                current_addr = aw_addr + aw_pos*32 -
                               (plane ? 32'h30000 : 32'h20000);
                row = current_addr / (cfg_output_pairs*32);
                pair_index = current_addr % (cfg_output_pairs*32) / 32;
                if (row >= cfg_output_height ||
                    pair_index >= cfg_output_pairs)
                    $fatal(1, "Wrong output address %h", aw_addr);
                expected0 = expected_pixel(row,pair_index*2);
                expected1 = expected_pixel(row,pair_index*2+1);
                for (ch = 0; ch < 16; ch = ch+1) begin
                    if (wdata_w[ch*8 +: 8] !== expected0[7:0] ||
                        wdata_w[(16+ch)*8 +: 8] !== expected1[7:0])
                        $fatal(1, "Bad output row=%0d x=%0d plane=%0d got=%0d expected=%0d",
                               row, pair_index*2, plane,
                               wdata_w[ch*8 +: 8], expected0);
                end
                output_beats <= output_beats+1;
                if (wlast_w)
                    aw_active <= 0;
                else
                    aw_pos <= aw_pos+1;
            end
            wlast_fire = wvalid_w && wready_w && wlast_w;
            bfire = bvalid_w && bready_w;
            b_pending <= b_pending + wlast_fire - bfire;
        end
    end

    initial begin
        if ($value$plusargs("MODE=%d", case_mode)) begin
            if (case_mode == 0)
                cfg_kernel3 = 1'b0;
            if (case_mode == 3) begin
                cfg_kernel3 = 1'b0;
                cfg_cin_blocks = 5'd2;
                cfg_cache_row_stride = 10'd4;
            end
            if (case_mode == 2) begin
                cfg_stride2 = 1'b1;
                cfg_input_height = 16'd4;
                cfg_output_pairs = 10'd2;
                cfg_output_height = 16'd2;
                cfg_feature_plane_stride = 32'd512;
            end
        end
        repeat (5) @(negedge clk_i);
        rst_n_i = 1'b1;
        for (channel = 0; channel < 32; channel = channel+1) begin
            @(negedge clk_i);
            if (!cfg_ready_w)
                $fatal(1, "Quant config blocked");
            cfg_valid_i = 1'b1;
            cfg_channel_i = channel;
        end
        @(negedge clk_i);
        cfg_valid_i = 1'b0;
        if (!start_ready_w)
            $fatal(1, "Layer start blocked");
        start_i = 1'b1;
        @(negedge clk_i);
        start_i = 1'b0;
        wait (done_w);
        #1;
        if (error_w || read_weight_beats !=
            (case_mode == 0 ? 16 : case_mode == 3 ? 32 : 144) ||
            read_feature_beats !=
            (case_mode == 2 ? 16 : case_mode == 3 ? 24 : 12) ||
            mac_beats != cfg_output_height * cfg_output_pairs *
                         (case_mode == 0 ? 2 : case_mode == 3 ? 4 : 18) ||
            output_beats != cfg_output_height * cfg_output_pairs * 2 ||
            (case_mode == 1 && !overlap_seen) ||
            (case_mode == 1 && max_outstanding != 4) ||
            b_pending != 0)
            $fatal(1, "Layer counters weight=%0d feature=%0d mac=%0d output=%0d overlap=%0d outstanding=%0d error=%0d",
                   read_weight_beats, read_feature_beats,
                   mac_beats, output_beats, overlap_seen,
                   max_outstanding, error_w);
        $display("PASS YOLO DDR conv mode=%0d: weight=%0d feature=%0d MAC=%0d output=%0d cycles=%0d",
                 case_mode, read_weight_beats, read_feature_beats,
                 mac_beats, output_beats, cycle_r);
        $finish;
    end
    initial begin
        #1000000;
        $fatal(1, "DDR conv timeout state=%0d read=%0d mac=%0d out=%0d",
               dut.state_r, read_feature_beats, mac_beats, output_beats);
    end
endmodule
