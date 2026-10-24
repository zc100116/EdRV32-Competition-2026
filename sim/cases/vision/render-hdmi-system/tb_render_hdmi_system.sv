`timescale 1ns/1ps

module tb_render_hdmi_system;
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
        .m_awid_o(awid), .m_awaddr_o(awaddr),
        .m_awlen_o(awlen), .m_awsize_o(awsize),
        .m_awburst_o(awburst), .m_awqos_o(awqos),
        .m_awvalid_o(awvalid), .m_awready_i(awready),
        .m_wdata_o(wdata), .m_wstrb_o(wstrb),
        .m_wlast_o(wlast), .m_wvalid_o(wvalid),
        .m_wready_i(wready),
        .m_bid_i(bid), .m_bresp_i(bresp),
        .m_bvalid_i(bvalid), .m_bready_o(bready),
        .m_arid_o(arid), .m_araddr_o(araddr),
        .m_arlen_o(arlen), .m_arsize_o(arsize),
        .m_arburst_o(arburst), .m_arqos_o(arqos),
        .m_arvalid_o(arvalid), .m_arready_i(arready),
        .m_rid_i(rid), .m_rdata_i(rdata),
        .m_rresp_i(rresp), .m_rlast_i(rlast),
        .m_rvalid_i(rvalid), .m_rready_o(rready)
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
            reader_error || fabric_error || underflows != 0)
            $fatal(1,"integration status release=%0d/%0d retire=%0d overlap=%0d reader=%b fabric=%b underflow=%0d",
                   releases0,releases1,retired_target0,
                   compose_reader_overlap,reader_error,
                   fabric_error,underflows);
        $display("RENDER_HDMI_SYSTEM_PASS blue=%0d green=%0d releases=%0d/%0d overlap=%0d frames=%0d cycles=%0d",
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
