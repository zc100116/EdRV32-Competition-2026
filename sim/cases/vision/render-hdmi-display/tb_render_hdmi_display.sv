`timescale 1ns/1ps

module tb_render_hdmi_display;
    localparam [31:0] BASE0 = 32'h0000_1000;
    localparam [31:0] BASE1 = 32'h0000_2000;
    localparam integer FRAME_PIXELS = 32*8;

    reg ddr_clk, pixel_clk, serial_clk, rst_n;
    reg display_valid;
    wire display_ready;
    reg [2:0] display_token;
    reg [31:0] display_base;
    wire retire_valid;
    wire [2:0] retire_token, active_token;
    wire [31:0] reader_frames, scanout_frames, underflows;
    wire reader_error;
    wire [23:0] rgb;
    wire hs, vs, de, tmds_clk_p, tmds_clk_n;
    wire [2:0] tmds_data_p, tmds_data_n;
    wire [3:0] arid, rid;
    wire [31:0] araddr;
    wire [7:0] arlen;
    wire [2:0] arsize;
    wire [1:0] arburst;
    wire [3:0] arqos;
    wire arvalid, arready, rvalid, rready, rlast;
    wire [255:0] rdata;
    wire [1:0] rresp;
    integer cycle_count, frame_pixels, complete_frames;
    integer blue_frames, red_frames, retired;
    integer i;
    reg [23:0] frame_color;

    always #4 ddr_clk = ~ddr_clk;
    always #5 pixel_clk = ~pixel_clk;
    always #1 serial_clk = ~serial_clk;

    edrv32_render_hdmi_display #(
        .H_ACTIVE(32), .H_FP(2), .H_SYNC(2), .H_BP(2),
        .V_ACTIVE(8), .V_FP(1), .V_SYNC(1), .V_BP(1),
        .BURST_BEATS(4), .PREFILL_BEATS(4)
    ) u_dut (
        .ddr_clk_i(ddr_clk), .ddr_rst_n_i(rst_n),
        .pixel_clk_i(pixel_clk), .pixel_rst_n_i(rst_n),
        .serial_clk_i(serial_clk), .serial_rst_n_i(rst_n),
        .display_enable_i(1'b1),
        .display_valid_i(display_valid),
        .display_ready_o(display_ready),
        .display_token_i(display_token),
        .display_base_i(display_base),
        .display_retire_valid_o(retire_valid),
        .display_retire_token_o(retire_token),
        .active_token_o(active_token),
        .reader_frame_count_o(reader_frames),
        .scanout_frame_count_o(scanout_frames),
        .underflow_count_o(underflows),
        .reader_error_o(reader_error),
        .rgb_o(rgb), .hs_o(hs), .vs_o(vs), .de_o(de),
        .tmds_clk_p_o(tmds_clk_p),
        .tmds_clk_n_o(tmds_clk_n),
        .tmds_data_p_o(tmds_data_p),
        .tmds_data_n_o(tmds_data_n),
        .m_arid_o(arid), .m_araddr_o(araddr),
        .m_arlen_o(arlen), .m_arsize_o(arsize),
        .m_arburst_o(arburst), .m_arqos_o(arqos),
        .m_arvalid_o(arvalid), .m_arready_i(arready),
        .m_rid_i(rid), .m_rdata_i(rdata),
        .m_rresp_i(rresp), .m_rlast_i(rlast),
        .m_rvalid_i(rvalid), .m_rready_o(rready)
    );

    axi256_mem_model #(.WORDS(1024)) u_mem (
        .clk_i(ddr_clk), .rst_n_i(rst_n),
        .awid_i(4'd0), .awaddr_i(32'd0),
        .awlen_i(8'd0), .awsize_i(3'd5),
        .awburst_i(2'b01), .awvalid_i(1'b0), .awready_o(),
        .wdata_i(256'd0), .wstrb_i(32'd0),
        .wlast_i(1'b0), .wvalid_i(1'b0), .wready_o(),
        .bid_o(), .bresp_o(), .bvalid_o(), .bready_i(1'b0),
        .arid_i(arid), .araddr_i(araddr),
        .arlen_i(arlen), .arsize_i(arsize),
        .arburst_i(arburst), .arvalid_i(arvalid),
        .arready_o(arready), .rid_o(rid),
        .rdata_o(rdata), .rresp_o(rresp),
        .rlast_o(rlast), .rvalid_o(rvalid),
        .rready_i(rready)
    );

    task automatic send_frame;
        input [2:0] token;
        input [31:0] base;
        begin
            @(negedge ddr_clk);
            display_token = token;
            display_base = base;
            display_valid = 1'b1;
            do @(posedge ddr_clk); while (!display_ready);
            @(negedge ddr_clk);
            display_valid = 1'b0;
        end
    endtask

    initial begin
        ddr_clk = 1'b0;
        pixel_clk = 1'b0;
        serial_clk = 1'b0;
        rst_n = 1'b0;
        display_valid = 1'b0;
        display_token = 3'd0;
        display_base = 32'd0;
        cycle_count = 0;
        frame_pixels = 0;
        complete_frames = 0;
        blue_frames = 0;
        red_frames = 0;
        retired = 0;
        frame_color = 24'd0;
        for (i=0; i<1024; i=i+1)
            u_mem.store[i] = 256'd0;
        for (i=0; i<16; i=i+1) begin
            u_mem.store[(BASE0 >> 5)+i] = {16{16'h001f}};
            u_mem.store[(BASE1 >> 5)+i] = {16{16'hf800}};
        end
        repeat (5) @(posedge ddr_clk);
        @(negedge ddr_clk);
        rst_n = 1'b1;
        send_frame(3'd0,BASE0);
        wait(blue_frames >= 1);
        send_frame(3'd4,BASE1);
        wait(red_frames >= 1);
        if (retired != 1 || reader_error || underflows != 0)
            $fatal(1,"display status retired=%0d error=%b underflows=%0d",
                   retired,reader_error,underflows);
        $display("RENDER_HDMI_DISPLAY_PASS blue=%0d red=%0d retired=%0d scanout=%0d cycles=%0d",
                 blue_frames,red_frames,retired,scanout_frames,
                 cycle_count);
        $finish;
    end

    always @(posedge ddr_clk) begin
        if (rst_n && retire_valid) begin
            if (retire_token !== 3'd0 || retired != 0)
                $fatal(1,"wrong display token retired %h",retire_token);
            retired = retired + 1;
        end
    end

    always @(posedge pixel_clk) begin
        if (rst_n) begin
            cycle_count = cycle_count + 1;
            if (de) begin
                if (frame_pixels == 0)
                    frame_color = rgb;
                else if (rgb !== frame_color)
                    $fatal(1,"mixed HDMI frame pixel=%0d rgb=%h first=%h",
                           frame_pixels,rgb,frame_color);
                frame_pixels = frame_pixels + 1;
                if (frame_pixels == FRAME_PIXELS) begin
                    complete_frames = complete_frames + 1;
                    if (frame_color == 24'h0000ff)
                        blue_frames = blue_frames + 1;
                    else if (frame_color == 24'hff0000)
                        red_frames = red_frames + 1;
                    else
                        $fatal(1,"unexpected HDMI color %h",frame_color);
                    frame_pixels = 0;
                end
            end
            if (cycle_count > 60000)
                $fatal(1,"HDMI display timeout frames=%0d red=%0d",
                       complete_frames,red_frames);
        end
    end
endmodule
