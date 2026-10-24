`timescale 1ns/1ps

module tb_render_hdmi_split;
    localparam [31:0] LIST_BASE = 32'h0000_1000;
    localparam [31:0] FRONT = 32'h0000_4000;
    localparam [31:0] TARGET0 = 32'h0000_8000;
    localparam [31:0] TARGET1 = 32'h0000_9000;
    localparam [31:0] TARGET2 = 32'h0000_a000;
    localparam [31:0] BASE0 = 32'h0000_c000;
    localparam [31:0] BASE1 = 32'h0000_d000;
    localparam integer FRAME_PIXELS = 32*8;

    reg ddr_clk, pixel_clk, serial_clk, rst_n;
    reg [31:0] paddr, pwdata;
    reg psel, penable, pwrite;
    reg [3:0] pstrb;
    wire pready, pslverr, irq;
    wire [31:0] prdata;
    reg base_valid;
    reg [1:0] base_buffer;
    reg [31:0] base_addr, base_stride;
    wire base_release_valid;
    wire [1:0] base_release_buffer;
    wire [23:0] rgb;
    wire hs, vs, de, tmds_clk_p, tmds_clk_n;
    wire [2:0] tmds_data_p, tmds_data_n;
    wire [31:0] reader_frames, scanout_frames, underflows;
    wire reader_error, fabric_error;
    wire [3:0] awid, bid, arid, rid;
    wire [31:0] awaddr, araddr;
    wire [7:0] awlen, arlen;
    wire [2:0] awsize, arsize;
    wire [1:0] awburst, arburst;
    wire [3:0] awqos, arqos;
    wire awvalid, awready, wvalid, wready, wlast;
    wire bvalid, bready, arvalid, arready;
    wire rvalid, rready, rlast;
    wire [255:0] wdata, rdata;
    wire [31:0] wstrb;
    wire [1:0] bresp, rresp;
    wire [3:0] render_awid, render_bid, render_arid, render_rid;
    wire [31:0] render_awaddr, render_araddr;
    wire [7:0] render_awlen, render_arlen;
    wire [2:0] render_awsize, render_arsize;
    wire [1:0] render_awburst, render_arburst;
    wire [3:0] render_awqos, render_arqos;
    wire render_awvalid, render_awready, render_wvalid, render_wready;
    wire render_wlast, render_bvalid, render_bready;
    wire render_arvalid, render_arready, render_rvalid, render_rready;
    wire render_rlast;
    wire [255:0] render_wdata, render_rdata;
    wire [31:0] render_wstrb;
    wire [1:0] render_bresp, render_rresp;
    wire [3:0] display_arid, display_rid;
    wire [31:0] display_araddr;
    wire [7:0] display_arlen;
    wire [2:0] display_arsize;
    wire [1:0] display_arburst, display_rresp;
    wire [3:0] display_arqos;
    wire display_arvalid, display_arready;
    wire [255:0] display_rdata;
    wire display_rlast, display_rvalid, display_rready;
    wire display_read_urgent;
    wire [9:0] unused_read_outstanding, unused_write_outstanding;
    wire unused_read_error, unused_write_error;
    wire unused_owner_valid, unused_owner;
    wire unused_display_awready, unused_display_wready;
    wire [3:0] unused_display_bid;
    wire [1:0] unused_display_bresp;
    wire unused_display_bvalid;
    reg [511:0] command [0:1];
    integer i, x, y, cycles, frame_pixels;
    integer blue_frames, green_frames, releases0, releases1;
    integer retired_target0, compose_reader_overlap;
    reg [15:0] frame_base565;
    reg [15:0] expected565;

    always #4 ddr_clk = ~ddr_clk;
    always #5 pixel_clk = ~pixel_clk;
    always #1 serial_clk = ~serial_clk;

    edrv32_render_hdmi_system #(
        .H_ACTIVE(32), .H_FP(2), .H_SYNC(2), .H_BP(2),
        .V_ACTIVE(8), .V_FP(1), .V_SYNC(1), .V_BP(1),
        .BURST_BEATS(4), .PREFILL_BEATS(4),
        .SPLIT_AXI(1),
        .FRONT_BASE(FRONT),
        .TARGET_BASE0(TARGET0),
        .TARGET_BASE1(TARGET1),
        .TARGET_BASE2(TARGET2)
    ) u_dut (
        .ddr_clk_i(ddr_clk), .ddr_rst_n_i(rst_n),
        .ddr_ready_i(1'b1),
        .pixel_clk_i(pixel_clk), .pixel_rst_n_i(rst_n),
        .serial_clk_i(serial_clk), .serial_rst_n_i(rst_n),
        .display_enable_i(1'b1),
        .paddr_i(paddr), .psel_i(psel),
        .penable_i(penable), .pwrite_i(pwrite),
        .pwdata_i(pwdata), .pstrb_i(pstrb),
        .pready_o(pready), .prdata_o(prdata),
        .pslverr_o(pslverr), .irq_o(irq),
        .base_valid_i(base_valid),
        .base_buffer_i(base_buffer),
        .base_addr_i(base_addr),
        .base_stride_i(base_stride),
        .base_release_valid_o(base_release_valid),
        .base_release_buffer_o(base_release_buffer),
        .rgb_o(rgb), .hs_o(hs), .vs_o(vs), .de_o(de),
        .tmds_clk_p_o(tmds_clk_p),
        .tmds_clk_n_o(tmds_clk_n),
        .tmds_data_p_o(tmds_data_p),
        .tmds_data_n_o(tmds_data_n),
        .reader_frame_count_o(reader_frames),
        .scanout_frame_count_o(scanout_frames),
        .underflow_count_o(underflows),
        .reader_error_o(reader_error),
        .fabric_error_o(fabric_error),
        .m_awid_o(render_awid), .m_awaddr_o(render_awaddr),
        .m_awlen_o(render_awlen), .m_awsize_o(render_awsize),
        .m_awburst_o(render_awburst), .m_awqos_o(render_awqos),
        .m_awvalid_o(render_awvalid), .m_awready_i(render_awready),
        .m_wdata_o(render_wdata), .m_wstrb_o(render_wstrb),
        .m_wlast_o(render_wlast), .m_wvalid_o(render_wvalid),
        .m_wready_i(render_wready),
        .m_bid_i(render_bid), .m_bresp_i(render_bresp),
        .m_bvalid_i(render_bvalid), .m_bready_o(render_bready),
        .m_arid_o(render_arid), .m_araddr_o(render_araddr),
        .m_arlen_o(render_arlen), .m_arsize_o(render_arsize),
        .m_arburst_o(render_arburst), .m_arqos_o(render_arqos),
        .m_arvalid_o(render_arvalid), .m_arready_i(render_arready),
        .m_rid_i(render_rid), .m_rdata_i(render_rdata),
        .m_rresp_i(render_rresp), .m_rlast_i(render_rlast),
        .m_rvalid_i(render_rvalid), .m_rready_o(render_rready),
        .display_read_urgent_o(display_read_urgent),
        .display_arid_o(display_arid),
        .display_araddr_o(display_araddr),
        .display_arlen_o(display_arlen),
        .display_arsize_o(display_arsize),
        .display_arburst_o(display_arburst),
        .display_arqos_o(display_arqos),
        .display_arvalid_o(display_arvalid),
        .display_arready_i(display_arready),
        .display_rid_i(display_rid),
        .display_rdata_i(display_rdata),
        .display_rresp_i(display_rresp),
        .display_rlast_i(display_rlast),
        .display_rvalid_i(display_rvalid),
        .display_rready_o(display_rready)
    );

    edrv32_axi_m2s_interconnect #(
        .NUM_M(2), .WR_ORDER_DEPTH(8), .STARVE_CYCLES(64)
    ) u_fabric (
        .clk_i(ddr_clk), .rst_n_i(rst_n), .accept_i(1'b1),
        .m_awid_i({4'd0,render_awid}),
        .m_awaddr_i({32'd0,render_awaddr}),
        .m_awlen_i({8'd0,render_awlen}),
        .m_awsize_i({3'd5,render_awsize}),
        .m_awburst_i({2'b01,render_awburst}),
        .m_awqos_i({4'd0,render_awqos}),
        .m_awvalid_i({1'b0,render_awvalid}),
        .m_awready_o({unused_display_awready,render_awready}),
        .m_wdata_i({256'd0,render_wdata}),
        .m_wstrb_i({32'd0,render_wstrb}),
        .m_wlast_i({1'b0,render_wlast}),
        .m_wvalid_i({1'b0,render_wvalid}),
        .m_wready_o({unused_display_wready,render_wready}),
        .m_bid_o({unused_display_bid,render_bid}),
        .m_bresp_o({unused_display_bresp,render_bresp}),
        .m_bvalid_o({unused_display_bvalid,render_bvalid}),
        .m_bready_i({1'b1,render_bready}),
        .m_arid_i({display_arid,render_arid}),
        .m_araddr_i({display_araddr,render_araddr}),
        .m_arlen_i({display_arlen,render_arlen}),
        .m_arsize_i({display_arsize,render_arsize}),
        .m_arburst_i({display_arburst,render_arburst}),
        .m_arqos_i({display_arqos,render_arqos}),
        .m_arvalid_i({display_arvalid,render_arvalid}),
        .m_arready_o({display_arready,render_arready}),
        .m_rid_o({display_rid,render_rid}),
        .m_rdata_o({display_rdata,render_rdata}),
        .m_rresp_o({display_rresp,render_rresp}),
        .m_rlast_o({display_rlast,render_rlast}),
        .m_rvalid_o({display_rvalid,render_rvalid}),
        .m_rready_i({display_rready,render_rready}),
        .m_read_urgent_i({display_read_urgent,1'b0}),
        .m_write_urgent_i(2'b00),
        .m_read_weight_i({4'd12,4'd3}),
        .m_write_weight_i({4'd1,4'd8}),
        .m_read_credit_i({5'd12,5'd4}),
        .m_write_credit_i({5'd1,5'd4}),
        .s_awid_o(awid), .s_awaddr_o(awaddr),
        .s_awlen_o(awlen), .s_awsize_o(awsize),
        .s_awburst_o(awburst), .s_awqos_o(awqos),
        .s_awvalid_o(awvalid), .s_awready_i(awready),
        .s_wdata_o(wdata), .s_wstrb_o(wstrb),
        .s_wlast_o(wlast), .s_wvalid_o(wvalid),
        .s_wready_i(wready),
        .s_bid_i(bid), .s_bresp_i(bresp),
        .s_bvalid_i(bvalid), .s_bready_o(bready),
        .s_arid_o(arid), .s_araddr_o(araddr),
        .s_arlen_o(arlen), .s_arsize_o(arsize),
        .s_arburst_o(arburst), .s_arqos_o(arqos),
        .s_arvalid_o(arvalid), .s_arready_i(arready),
        .s_rid_i(rid), .s_rdata_i(rdata),
        .s_rresp_i(rresp), .s_rlast_i(rlast),
        .s_rvalid_i(rvalid), .s_rready_o(rready),
        .read_outstanding_o(unused_read_outstanding),
        .write_outstanding_o(unused_write_outstanding),
        .read_protocol_error_o(unused_read_error),
        .write_protocol_error_o(unused_write_error),
        .write_owner_valid_o(unused_owner_valid),
        .write_owner_o(unused_owner)
    );

    axi256_mem_model #(.WORDS(4096)) u_mem (
        .clk_i(ddr_clk), .rst_n_i(rst_n),
        .awid_i(awid), .awaddr_i(awaddr),
        .awlen_i(awlen), .awsize_i(awsize),
        .awburst_i(awburst),
        .awvalid_i(awvalid), .awready_o(awready),
        .wdata_i(wdata), .wstrb_i(wstrb),
        .wlast_i(wlast), .wvalid_i(wvalid),
        .wready_o(wready),
        .bid_o(bid), .bresp_o(bresp),
        .bvalid_o(bvalid), .bready_i(bready),
        .arid_i(arid), .araddr_i(araddr),
        .arlen_i(arlen), .arsize_i(arsize),
        .arburst_i(arburst), .arvalid_i(arvalid),
        .arready_o(arready),
        .rid_o(rid), .rdata_o(rdata),
        .rresp_o(rresp), .rlast_o(rlast),
        .rvalid_o(rvalid), .rready_i(rready)
    );

    function automatic [15:0] read_pixel16;
        input integer address;
        begin
            read_pixel16 = u_mem.store[address >> 5]
                [((address & 31)*8) +: 16];
        end
    endfunction

    function automatic [23:0] rgb565_to888;
        input [15:0] color;
        begin
            rgb565_to888 = {
                color[15:11],color[15:13],
                color[10:5],color[10:9],
                color[4:0],color[4:2]};
        end
    endfunction

    function automatic [15:0] expected_pixel;
        input [15:0] base_color;
        input integer px, py;
        begin
            expected_pixel = px>=8 && px<24 && py>=2 && py<6 ?
                (base_color == 16'h001f ? 16'h800f : 16'h83e0) :
                base_color;
        end
    endfunction

    task automatic apb_write;
        input [7:0] offset;
        input [31:0] value;
        begin
            @(negedge ddr_clk);
            paddr = {24'd0,offset};
            pwdata = value;
            psel = 1'b1;
            penable = 1'b0;
            pwrite = 1'b1;
            @(negedge ddr_clk);
            penable = 1'b1;
            #1;
            if (!pready || pslverr)
                $fatal(1,"APB rejected offset=%h",offset);
            @(posedge ddr_clk);
            @(negedge ddr_clk);
            psel = 1'b0;
            penable = 1'b0;
            pwrite = 1'b0;
        end
    endtask

    task automatic send_base;
        input [1:0] buffer;
        input [31:0] address;
        begin
            @(negedge ddr_clk);
            base_buffer = buffer;
            base_addr = address;
            base_stride = 32'd64;
            base_valid = 1'b1;
            @(negedge ddr_clk);
            base_valid = 1'b0;
        end
    endtask

    task automatic check_target;
        input [31:0] address;
        input [15:0] base_color;
        begin
            for (y=0; y<8; y=y+1)
                for (x=0; x<32; x=x+1)
                    if (read_pixel16(address+y*64+x*2) !==
                        expected_pixel(base_color,x,y))
                        $fatal(1,"target mismatch base=%h x=%0d y=%0d got=%h want=%h",
                               address,x,y,
                               read_pixel16(address+y*64+x*2),
                               expected_pixel(base_color,x,y));
        end
    endtask

    initial begin
        ddr_clk = 1'b0;
        pixel_clk = 1'b0;
        serial_clk = 1'b0;
        rst_n = 1'b0;
        paddr = 32'd0;
        pwdata = 32'd0;
        psel = 1'b0;
        penable = 1'b0;
        pwrite = 1'b0;
        pstrb = 4'hf;
        base_valid = 1'b0;
        base_buffer = 2'd0;
        base_addr = 32'd0;
        base_stride = 32'd64;
        cycles = 0;
        frame_pixels = 0;
        blue_frames = 0;
        green_frames = 0;
        releases0 = 0;
        releases1 = 0;
        retired_target0 = 0;
        compose_reader_overlap = 0;
        frame_base565 = 16'd0;
        for (i=0; i<4096; i=i+1)
            u_mem.store[i] = 256'd0;
        for (i=0; i<16; i=i+1) begin
            u_mem.store[(BASE0 >> 5)+i] = {16{16'h001f}};
            u_mem.store[(BASE1 >> 5)+i] = {16{16'h07e0}};
        end
        command[0] = 512'd0;
        command[1] = 512'd0;
        command[0][7:0] = 8'h02;
        command[0][63:32] = FRONT;
        command[0][95:64] = 32'd128;
        command[0][127:96] = {16'd32,16'd0};
        command[0][143:128] = 16'd8;
        command[1][7:0] = 8'h02;
        command[1][63:32] = FRONT+2*128;
        command[1][95:64] = 32'd128;
        command[1][127:96] = {16'd16,16'd8};
        command[1][143:128] = 16'd4;
        command[1][191:160] = 32'h8080_0000;
        u_mem.store[LIST_BASE >> 5] = command[0][255:0];
        u_mem.store[(LIST_BASE >> 5)+1] = command[0][511:256];
        u_mem.store[(LIST_BASE >> 5)+2] = command[1][255:0];
        u_mem.store[(LIST_BASE >> 5)+3] = command[1][511:256];
        repeat (5) @(posedge ddr_clk);
        @(negedge ddr_clk);
        rst_n = 1'b1;
        apb_write(8'h18,FRONT);
        apb_write(8'h1c,32'd128);
        apb_write(8'h20,{16'd8,16'd32});
        apb_write(8'h24,32'd64);
        apb_write(8'h10,LIST_BASE);
        apb_write(8'h14,32'd2);
        apb_write(8'h08,32'd1);
        apb_write(8'h28,32'd1);
        send_base(2'd0,BASE0);
        wait(blue_frames >= 1);
        check_target(TARGET0,16'h001f);
        send_base(2'd1,BASE1);
        wait(green_frames >= 1);
        check_target(TARGET1,16'h07e0);
        if (releases0 < 1 || releases1 < 1 ||
            retired_target0 < 1 || compose_reader_overlap < 1 ||
            reader_error || fabric_error || unused_read_error ||
            unused_write_error || underflows != 0)
            $fatal(1,"integration status release=%0d/%0d retire=%0d overlap=%0d reader=%b fabric=%b underflow=%0d",
                   releases0,releases1,retired_target0,
                   compose_reader_overlap,reader_error,
                   fabric_error,underflows);
        $display("RENDER_HDMI_SPLIT_PASS blue=%0d green=%0d releases=%0d/%0d overlap=%0d frames=%0d cycles=%0d",
                 blue_frames,green_frames,releases0,releases1,
                 compose_reader_overlap,scanout_frames,cycles);
        $finish;
    end

    always @(posedge ddr_clk) begin
        if (rst_n) begin
            if (base_release_valid) begin
                if (base_release_buffer == 2'd0)
                    releases0 = releases0 + 1;
                else if (base_release_buffer == 2'd1)
                    releases1 = releases1 + 1;
                else
                    $fatal(1,"unexpected base release %h",
                           base_release_buffer);
            end
            if (u_dut.u_display.display_retire_valid_o &&
                u_dut.u_display.display_retire_token_o == 3'd4)
                retired_target0 = retired_target0 + 1;
            if (u_dut.u_render.u_frame_ctrl.state_r == 2'd2 &&
                u_dut.u_display.u_reader.active_o)
                compose_reader_overlap = compose_reader_overlap + 1;
        end
    end

    always @(posedge pixel_clk) begin
        if (rst_n) begin
            cycles = cycles + 1;
            if (de) begin
                if (frame_pixels == 0) begin
                    if (rgb == rgb565_to888(16'h001f))
                        frame_base565 = 16'h001f;
                    else if (rgb == rgb565_to888(16'h07e0))
                        frame_base565 = 16'h07e0;
                    else
                        $fatal(1,"unexpected HDMI frame base %h",rgb);
                end
                expected565 = expected_pixel(frame_base565,
                    u_dut.u_display.u_scanout.active_x_o,
                    u_dut.u_display.u_scanout.active_y_o);
                if (rgb !== rgb565_to888(expected565))
                    $fatal(1,"HDMI pixel mismatch frame=%h x=%0d y=%0d got=%h want=%h",
                           frame_base565,
                           u_dut.u_display.u_scanout.active_x_o,
                           u_dut.u_display.u_scanout.active_y_o,
                           rgb,rgb565_to888(expected565));
                frame_pixels = frame_pixels + 1;
                if (frame_pixels == FRAME_PIXELS) begin
                    if (frame_base565 == 16'h001f)
                        blue_frames = blue_frames + 1;
                    else
                        green_frames = green_frames + 1;
                    frame_pixels = 0;
                end
            end
            if (cycles > 100000)
                $fatal(1,"shared DDR HDMI timeout blue=%0d green=%0d releases=%0d/%0d",
                       blue_frames,green_frames,releases0,releases1);
        end
    end
endmodule
