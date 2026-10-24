`timescale 1ns/1ps

module tb_render_shadow_image;
    localparam integer WIDTH = 1280;
    localparam integer HEIGHT = 720;
    localparam integer BASE_STRIDE = WIDTH*2;
    localparam integer FRONT_STRIDE = WIDTH*4;
    localparam [31:0] LIST_BASE = 32'h0000_1000;
    localparam [31:0] BASE = 32'h0002_0000;
    localparam [31:0] FRONT = 32'h0020_0000;
    localparam [31:0] MASK = 32'h0060_0000;
    localparam [31:0] SCRATCH = 32'h0061_0000;
    localparam [31:0] BLURRED = 32'h0062_0000;
    localparam [15:0] BASE_COLOR = 16'hc638;
    reg clk, rst_n, start;
    wire start_ready, busy, done, error;
    wire [15:0] completed_count;
    wire [3:0] arid, awid, rid, bid;
    wire [31:0] araddr, awaddr;
    wire [7:0] arlen, awlen;
    wire [2:0] arsize, awsize;
    wire [1:0] arburst, awburst;
    wire [3:0] arqos, awqos;
    wire arvalid, arready, rvalid, rready, rlast;
    wire awvalid, awready, wvalid, wready, wlast;
    wire bvalid, bready;
    wire [255:0] rdata, wdata;
    wire [31:0] wstrb;
    wire [1:0] rresp, bresp;
    reg [511:0] command [0:8];
    reg [15:0] actual;
    reg [31:0] rgb;
    integer i, j, x, y, file_id, cycles;

    always #5 clk = ~clk;

    edrv32_render_engine u_dut (
        .clk_i(clk), .rst_n_i(rst_n),
        .start_i(start), .start_ready_o(start_ready),
        .list_base_i(LIST_BASE), .list_count_i(16'd9),
        .busy_o(busy), .done_o(done), .error_o(error),
        .completed_count_o(completed_count),
        .compose_direct_start_i(1'b0),
        .compose_direct_ready_o(),
        .compose_direct_base_i(32'd0),
        .compose_direct_base_stride_i(32'd0),
        .compose_direct_front_i(32'd0),
        .compose_direct_front_stride_i(32'd0),
        .compose_direct_target_i(32'd0),
        .compose_direct_target_stride_i(32'd0),
        .compose_direct_width_i(16'd0),
        .compose_direct_height_i(16'd0),
        .compose_direct_done_o(),
        .compose_direct_error_o(),
        .m_arid_o(arid), .m_araddr_o(araddr),
        .m_arlen_o(arlen), .m_arsize_o(arsize),
        .m_arburst_o(arburst), .m_arqos_o(arqos),
        .m_arvalid_o(arvalid), .m_arready_i(arready),
        .m_rid_i(rid), .m_rdata_i(rdata),
        .m_rresp_i(rresp), .m_rlast_i(rlast),
        .m_rvalid_i(rvalid), .m_rready_o(rready),
        .m_awid_o(awid), .m_awaddr_o(awaddr),
        .m_awlen_o(awlen), .m_awsize_o(awsize),
        .m_awburst_o(awburst), .m_awqos_o(awqos),
        .m_awvalid_o(awvalid), .m_awready_i(awready),
        .m_wdata_o(wdata), .m_wstrb_o(wstrb),
        .m_wlast_o(wlast), .m_wvalid_o(wvalid),
        .m_wready_i(wready),
        .m_bid_i(bid), .m_bresp_i(bresp),
        .m_bvalid_i(bvalid), .m_bready_o(bready)
    );

    axi256_mem_model #(.WORDS(262144)) u_mem (
        .clk_i(clk), .rst_n_i(rst_n),
        .awid_i(awid), .awaddr_i(awaddr),
        .awlen_i(awlen), .awsize_i(awsize),
        .awburst_i(awburst), .awvalid_i(awvalid),
        .awready_o(awready),
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
        input integer byte_address;
        begin
            read_pixel16 = u_mem.store[byte_address >> 5]
                [((byte_address & 31)*8) +: 16];
        end
    endfunction

    task automatic set_shadow;
        input integer index, px, py, blur, corner;
        begin
            command[index] = 512'd0;
            command[index][7:0] = 8'h0a;
            command[index][63:32] = FRONT+py*FRONT_STRIDE;
            command[index][95:64] = FRONT_STRIDE;
            command[index][127:96] = {16'd280,px[15:0]};
            command[index][159:128] = {corner[15:0],16'd190};
            command[index][191:160] = MASK;
            command[index][223:192] = SCRATCH;
            command[index][255:224] = BLURRED;
            command[index][287:256] = 32'd288;
            command[index][319:288] = 32'ha000_0000;
            command[index][324:320] = blur[4:0];
        end
    endtask

    task automatic set_card;
        input integer index, px, py, corner;
        begin
            command[index] = 512'd0;
            command[index][7:0] = 8'h04;
            command[index][63:32] = FRONT+(py+12)*FRONT_STRIDE;
            command[index][95:64] = FRONT_STRIDE;
            command[index][127:96] = {16'd256,16'(px+12)};
            command[index][159:128] = {corner[15:0],16'd166};
            command[index][191:160] = 32'd3;
            command[index][223:192] = 32'hfff5_f5f2;
            command[index][255:224] = 32'hff6b_8091;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        cycles = 0;
        for (i=0; i<9; i=i+1)
            command[i] = 512'd0;
        command[0][7:0] = 8'h01;
        command[0][63:32] = BASE;
        command[0][95:64] = BASE_STRIDE;
        command[0][127:96] = {16'd1280,16'd0};
        command[0][143:128] = 16'd720;
        command[0][191:160] = {16'd0,BASE_COLOR};
        command[1][7:0] = 8'h02;
        command[1][63:32] = FRONT;
        command[1][95:64] = FRONT_STRIDE;
        command[1][127:96] = {16'd1280,16'd0};
        command[1][143:128] = 16'd720;
        command[1][191:160] = 32'd0;
        set_shadow(2,100,250,3,18);
        set_card(3,100,250,14);
        set_shadow(4,500,250,7,24);
        set_card(5,500,250,20);
        set_shadow(6,900,250,12,30);
        set_card(7,900,250,26);
        command[8][7:0] = 8'h03;
        command[8][63:32] = BASE;
        command[8][95:64] = BASE_STRIDE;
        command[8][127:96] = FRONT;
        command[8][159:128] = FRONT_STRIDE;
        command[8][191:160] = BASE;
        command[8][223:192] = BASE_STRIDE;
        command[8][255:224] = {16'd720,16'd1280};
        for (i=0; i<9; i=i+1) begin
            j = (LIST_BASE >> 5)+i*2;
            u_mem.store[j] = command[i][255:0];
            u_mem.store[j+1] = command[i][511:256];
        end
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        wait(done);
        if (error || completed_count != 9)
            $fatal(1,"shadow image commands=%0d error=%b",
                   completed_count,error);
        if (read_pixel16(BASE) !== BASE_COLOR ||
            read_pixel16(BASE+345*BASE_STRIDE+240*2) === BASE_COLOR ||
            read_pixel16(BASE+345*BASE_STRIDE+640*2) === BASE_COLOR ||
            read_pixel16(BASE+345*BASE_STRIDE+1040*2) === BASE_COLOR ||
            read_pixel16(BASE+345*BASE_STRIDE+905*2) === BASE_COLOR)
            $fatal(1,"shadow image spot check failed");
        file_id = $fopen(
            "sim/build/cases/vision/render-shadow-image/shadow.ppm","wb");
        if (file_id == 0)
            $fatal(1,"cannot open shadow.ppm");
        $fwrite(file_id,"P6\n1280 720\n255\n");
        for (y=0; y<HEIGHT; y=y+1)
            for (x=0; x<WIDTH; x=x+1) begin
                actual = read_pixel16(BASE+y*BASE_STRIDE+x*2);
                if (^actual === 1'bx)
                    $fatal(1,"unknown shadow image pixel x=%0d y=%0d",
                           x,y);
                rgb = {8'hff,actual[15:11],actual[15:13],
                       actual[10:5],actual[10:9],
                       actual[4:0],actual[4:2]};
                $fwrite(file_id,"%c%c%c",rgb[23:16],rgb[15:8],
                        rgb[7:0]);
            end
        $fclose(file_id);
        $display("RENDER_SHADOW_IMAGE_PASS size=1280x720 shadows=3 cycles=%0d",
                 cycles);
        $finish;
    end

    always @(posedge clk) begin
        if (rst_n) begin
            cycles = cycles+1;
            if (cycles > 3000000)
                $fatal(1,"shadow image timeout command=%0d engine=%0d mask=%0d blur=%0d",
                       completed_count,u_dut.state_r,
                       u_dut.u_mask.state_r,
                       u_dut.u_blur.state_r);
        end
    end
endmodule
