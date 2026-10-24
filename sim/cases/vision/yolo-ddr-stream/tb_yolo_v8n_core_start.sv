`timescale 1ns/1ps

module tb_yolo_v8n_core_start;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg start = 0;
    wire start_ready, busy, done, error, cfg_error;
    wire [6:0] step;
    wire [4:0] layer_id, cfg_block, cfg_channel;
    wire [31:0] cfg_record_addr, cfg_lut_addr;
    wire cfg_ready, cfg_lut_ready;
    wire [3:0] arid;
    wire [31:0] araddr;
    wire [7:0] arlen;
    wire [2:0] arsize;
    wire [1:0] arburst;
    wire arvalid, arready, rready;
    reg [255:0] rdata;
    reg read_active = 0;
    reg [4:0] read_index = 0;
    integer quant_requests = 0;
    integer lane;

    assign arready = !read_active;

    edrv32_yolo_v8n_core dut (
        .clk_i(clk), .rst_n_i(rst_n),
        .start_i(start), .start_ready_o(start_ready),
        .busy_o(busy), .done_o(done), .error_o(error),
        .step_o(step), .layer_id_o(layer_id), .mac_beat_o(),
        .cfg_record_addr_o(cfg_record_addr),
        .cfg_block_o(cfg_block), .cfg_channel_o(cfg_channel),
        .cfg_ready_o(cfg_ready),
        .cfg_lut_addr_o(cfg_lut_addr),
        .cfg_lut_ready_o(cfg_lut_ready),
        .cfg_dma_error_o(cfg_error),
        .m_arid_o(arid), .m_araddr_o(araddr),
        .m_arlen_o(arlen), .m_arsize_o(arsize),
        .m_arburst_o(arburst), .m_arvalid_o(arvalid),
        .m_arready_i(arready),
        .m_rid_i(4'hd), .m_rdata_i(rdata),
        .m_rresp_i(2'b00), .m_rlast_i(read_index == 15),
        .m_rvalid_i(read_active), .m_rready_o(rready),
        .m_awid_o(), .m_awaddr_o(), .m_awlen_o(),
        .m_awsize_o(), .m_awburst_o(), .m_awvalid_o(),
        .m_awready_i(1'b0),
        .m_wdata_o(), .m_wstrb_o(), .m_wlast_o(),
        .m_wvalid_o(), .m_wready_i(1'b0),
        .m_bid_i(4'd0), .m_bresp_i(2'd0),
        .m_bvalid_i(1'b0), .m_bready_o()
    );

    always_comb begin
        rdata = 256'd0;
        if (read_index < 8) begin
            for (lane = 0; lane < 4; lane = lane + 1)
                rdata[lane*64 +: 64] = 64'h00_04_0001_00000000;
        end else begin
            for (lane = 0; lane < 32; lane = lane + 1)
                rdata[lane*8 +: 8] = ((read_index - 8) * 32 + lane) & 8'hff;
        end
    end

    always @(posedge clk) begin
        if (rst_n) begin
            if (arvalid && arready) begin
                if (araddr == 32'h0041_c000) begin
                    if (arid != 4'hd || arlen != 15 || arsize != 3'd5 ||
                        arburst != 2'b01 || quant_requests != 0)
                        $fatal(1, "first quantization read is incorrect");
                    quant_requests <= quant_requests + 1;
                    read_index <= 0;
                    read_active <= 1;
                end else if (araddr == 32'h0010_0000) begin
                    if (quant_requests != 1 || step != 0 || layer_id != 0 ||
                        cfg_error || error || !busy)
                        $fatal(1, "first CONV started without valid config");
                    $display("tb_yolo_v8n_core_start PASS: quant -> weight");
                    $finish;
                end else
                    $fatal(1, "unexpected AXI read address %h", araddr);
            end
            if (read_active && rready) begin
                if (read_index == 15)
                    read_active <= 0;
                else
                    read_index <= read_index + 1;
            end
            if (cfg_ready && cfg_channel == 0 &&
                cfg_record_addr != 32'h0041_c000)
                $fatal(1, "quant record address mismatch");
        end
    end

    initial begin
        repeat (5) @(negedge clk);
        rst_n = 1;
        @(negedge clk); start = 1;
        @(negedge clk); start = 0;
    end

    initial begin
        #20000;
        $fatal(1, "core start timeout step=%0d q=%0d state=%0d/%0d conv=%0d ch=%0d ready=%b valid=%b bias=%h mult=%h shift=%h rec0=%h rdata=%h beats=%0d",
               step, quant_requests, dut.u_cfg_dma.state_r,
               dut.u_exec.state_r, dut.u_exec.u_conv.state_r,
               cfg_channel, cfg_ready, dut.cfg_valid_w,
               dut.cfg_bias_w, dut.cfg_multiplier_w, dut.cfg_shift_w,
               dut.u_cfg_dma.record_r[0], rdata,
               dut.u_cfg_dma.u_reader.returned_beats_r);
    end
endmodule
