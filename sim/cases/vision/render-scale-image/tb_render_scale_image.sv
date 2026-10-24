`timescale 1ns/1ps

module tb_render_scale_image #(
    parameter integer GRADIENT_PANELS = 0
);
    localparam integer WIDTH = 1280;
    localparam integer HEIGHT = 720;
    localparam integer BASE_STRIDE = WIDTH*2;
    localparam integer FRONT_STRIDE = WIDTH*4;
    localparam [31:0] LIST_BASE = 32'h0000_1000;
    localparam [31:0] BASE = 32'h0002_0000;
    localparam [31:0] FRONT = 32'h0020_0000;
    localparam [31:0] SOURCE = 32'h0060_0000;
    localparam [15:0] BACKGROUND = 16'h10a4;
    localparam [15:0] PANEL_OUTER = 16'h528a;
    localparam [15:0] PANEL_INNER = 16'h2108;
    localparam [15:0] KEY_COLOR = 16'hf81f;
    localparam [15:0] ARROW_COLOR = 16'hfd20;

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
    reg ar_gate, r_gate, aw_gate, w_gate, b_gate;
    reg [511:0] command [0:14];
    reg [15:0] actual, source_color;
    reg [31:0] rgb;
    integer i, j, x, y, p, px, file_id, cycles;

    always #5 clk = ~clk;

    edrv32_render_engine u_dut (
        .clk_i(clk), .rst_n_i(rst_n),
        .start_i(start), .start_ready_o(start_ready),
        .list_base_i(LIST_BASE), .list_count_i(16'd15),
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
        .m_arvalid_o(arvalid),
        .m_arready_i(arready && ar_gate),
        .m_rid_i(rid), .m_rdata_i(rdata),
        .m_rresp_i(rresp), .m_rlast_i(rlast),
        .m_rvalid_i(rvalid && r_gate),
        .m_rready_o(rready),
        .m_awid_o(awid), .m_awaddr_o(awaddr),
        .m_awlen_o(awlen), .m_awsize_o(awsize),
        .m_awburst_o(awburst), .m_awqos_o(awqos),
        .m_awvalid_o(awvalid),
        .m_awready_i(awready && aw_gate),
        .m_wdata_o(wdata), .m_wstrb_o(wstrb),
        .m_wlast_o(wlast), .m_wvalid_o(wvalid),
        .m_wready_i(wready && w_gate),
        .m_bid_i(bid), .m_bresp_i(bresp),
        .m_bvalid_i(bvalid && b_gate),
        .m_bready_o(bready)
    );

    axi256_mem_model #(.WORDS(262144)) u_mem (
        .clk_i(clk), .rst_n_i(rst_n),
        .awid_i(awid), .awaddr_i(awaddr),
        .awlen_i(awlen), .awsize_i(awsize),
        .awburst_i(awburst),
        .awvalid_i(awvalid && aw_gate),
        .awready_o(awready),
        .wdata_i(wdata), .wstrb_i(wstrb),
        .wlast_i(wlast), .wvalid_i(wvalid && w_gate),
        .wready_o(wready),
        .bid_o(bid), .bresp_o(bresp),
        .bvalid_o(bvalid), .bready_i(bready && b_gate),
        .arid_i(arid), .araddr_i(araddr),
        .arlen_i(arlen), .arsize_i(arsize),
        .arburst_i(arburst),
        .arvalid_i(arvalid && ar_gate),
        .arready_o(arready),
        .rid_o(rid), .rdata_o(rdata),
        .rresp_o(rresp), .rlast_o(rlast),
        .rvalid_o(rvalid), .rready_i(rready && r_gate)
    );

    function automatic [15:0] read_pixel16;
        input integer address;
        begin
            read_pixel16 = u_mem.store[address >> 5]
                [((address & 31)*8) +: 16];
        end
    endfunction

    function automatic [15:0] source_pixel;
        input integer sx, sy;
        integer ax, ay;
        begin
            ax = sx-48;
            ay = sy-48;
            if (ay < 0)
                ay = -ay;
            source_pixel = KEY_COLOR;
            if (sx>=10 && sx<28 && sy>=10 && sy<28)
                source_pixel = 16'h07e0;
            if (sx>=10 && sx<30 && sy>=65 && sy<84)
                source_pixel = 16'h1cdf;
            if (sx>=12 && sx<62 && sy>=37 && sy<59)
                source_pixel = 16'hfbe0;
            if (sx>=54 && sx<=84 && ay<=(84-sx))
                source_pixel = ARROW_COLOR;
            if (ax*ax + (sy-48)*(sy-48) < 25 && sx<16)
                source_pixel = 16'hffff;
        end
    endfunction

    task automatic set_fill565;
        input integer index, dx, dy, dw, dh;
        input [15:0] color;
        begin
            command[index] = 512'd0;
            command[index][7:0] = 8'h01;
            command[index][63:32] = BASE+dy*BASE_STRIDE;
            command[index][95:64] = BASE_STRIDE;
            command[index][127:96] = {dw[15:0],dx[15:0]};
            command[index][143:128] = dh[15:0];
            command[index][191:160] = {16'd0,color};
        end
    endtask

    task automatic set_gradient;
        input integer index, dx, dy, dw, dh;
        input integer vertical;
        input [31:0] start_color;
        input [31:0] step_r, step_g, step_b;
        begin
            command[index] = 512'd0;
            command[index][31:0] = vertical ? 32'h0000_0208 :
                                             32'h0000_0008;
            command[index][63:32] = BASE+dy*BASE_STRIDE;
            command[index][95:64] = BASE_STRIDE;
            command[index][127:96] = {dw[15:0],dx[15:0]};
            command[index][143:128] = dh[15:0];
            command[index][191:160] = start_color;
            command[index][223:192] = 32'd0;
            command[index][255:224] = step_r;
            command[index][287:256] = step_g;
            command[index][319:288] = step_b;
        end
    endtask

    task automatic set_bitmap;
        input integer index, dx, dy, dw, dh;
        input [31:0] flags, source_addr;
        input [15:0] source_x;
        input [31:0] step_x, step_y;
        begin
            command[index] = 512'd0;
            command[index][31:0] = flags;
            command[index][63:32] = FRONT+dy*FRONT_STRIDE;
            command[index][95:64] = FRONT_STRIDE;
            command[index][127:96] = {dw[15:0],dx[15:0]};
            command[index][159:128] = {source_x,dh[15:0]};
            command[index][191:160] = source_addr;
            command[index][223:192] = 32'd192;
            command[index][255:224] = {16'd0,KEY_COLOR};
            command[index][287:256] = step_x;
            command[index][319:288] = step_y;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        ar_gate = 1'b1;
        r_gate = 1'b1;
        aw_gate = 1'b1;
        w_gate = 1'b1;
        b_gate = 1'b1;
        cycles = 0;
        for (i=0; i<15; i=i+1)
            command[i] = 512'd0;

        for (y=0; y<96; y=y+1) begin
            for (j=0; j<6; j=j+1)
                u_mem.store[(SOURCE+y*192+j*32) >> 5] = 256'd0;
            for (x=0; x<96; x=x+1)
                u_mem.store[(SOURCE+y*192+x*2) >> 5]
                    [((x*2)&31)*8 +: 16] = source_pixel(x,y);
        end

        set_fill565(0,0,0,WIDTH,HEIGHT,BACKGROUND);
        command[1][7:0] = 8'h02;
        command[1][63:32] = FRONT;
        command[1][95:64] = FRONT_STRIDE;
        command[1][127:96] = {16'd1280,16'd0};
        command[1][143:128] = 16'd720;
        command[1][191:160] = 32'd0;
        for (p=0; p<4; p=p+1) begin
            px = 40+p*300;
            set_fill565(2+p*2,px,110,260,400,PANEL_OUTER);
            set_fill565(3+p*2,px+4,114,252,392,PANEL_INNER);
        end
        if (GRADIENT_PANELS != 0) begin
            set_gradient(3,44,114,252,392,0,32'hff20_3040,
                         32'h0000_3000,32'h0000_1000,32'd0);
            set_gradient(5,344,114,252,392,1,32'hff18_3050,
                         32'h0000_1000,32'h0000_2000,
                         32'h0000_3000);
            set_gradient(7,644,114,252,392,0,32'hff20_3020,
                         32'd0,32'h0000_4000,32'h0000_1000);
            set_gradient(9,944,114,252,392,1,32'hff30_2018,
                         32'h0000_3000,32'h0000_2000,32'd0);
        end

        set_bitmap(10,110,215,96,96,32'h00ff_1006,
                   SOURCE,16'd0,32'd0,32'd0);
        set_bitmap(11,375,170,192,192,32'h00ff_3006,
                   SOURCE,16'd0,32'h0000_8000,32'h0000_8000);
        set_bitmap(12,735,240,48,48,32'h00ff_3006,
                   SOURCE,16'd0,32'h0002_0000,32'h0002_0000);
        set_bitmap(13,975,170,192,192,32'h00ff_3c06,
                   SOURCE+95*192,16'd95,
                   32'h0000_8000,32'h0000_8000);
        command[14][7:0] = 8'h03;
        command[14][63:32] = BASE;
        command[14][95:64] = BASE_STRIDE;
        command[14][127:96] = FRONT;
        command[14][159:128] = FRONT_STRIDE;
        command[14][191:160] = BASE;
        command[14][223:192] = BASE_STRIDE;
        command[14][255:224] = {16'd720,16'd1280};

        for (i=0; i<15; i=i+1) begin
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
        if (error || completed_count != 15)
            $fatal(1,"scale image commands=%0d error=%b",
                   completed_count,error);
        if (read_pixel16(BASE) !== BACKGROUND ||
            read_pixel16(BASE+(215+48)*BASE_STRIDE+(110+70)*2) !==
                ARROW_COLOR ||
            read_pixel16(BASE+(170+96)*BASE_STRIDE+(375+140)*2) !==
                ARROW_COLOR ||
            read_pixel16(BASE+(240+24)*BASE_STRIDE+(735+35)*2) !==
                ARROW_COLOR ||
            read_pixel16(BASE+(170+94)*BASE_STRIDE+(975+50)*2) !==
                ARROW_COLOR)
            $fatal(1,"scaled sprite spot checks failed");

        if (GRADIENT_PANELS != 0)
            file_id = $fopen(
                "sim/build/cases/vision/render-scale-image/gradient.ppm",
                "wb");
        else
            file_id = $fopen(
                "sim/build/cases/vision/render-scale-image/scale.ppm",
                "wb");
        if (file_id == 0)
            $fatal(1,"cannot open scale.ppm");
        $fwrite(file_id,"P6\n1280 720\n255\n");
        for (y=0; y<HEIGHT; y=y+1)
            for (x=0; x<WIDTH; x=x+1) begin
                actual = read_pixel16(BASE+y*BASE_STRIDE+x*2);
                if (^actual === 1'bx)
                    $fatal(1,"unknown display pixel x=%0d y=%0d",x,y);
                rgb = {8'hff,actual[15:11],actual[15:13],
                       actual[10:5],actual[10:9],
                       actual[4:0],actual[4:2]};
                $fwrite(file_id,"%c%c%c",rgb[23:16],rgb[15:8],
                        rgb[7:0]);
            end
        $fclose(file_id);
        $display("RENDER_SCALE_IMAGE_PASS size=1280x720 elements=4 gradients=%0d cycles=%0d",
                 GRADIENT_PANELS,cycles);
        $finish;
    end

    always @(posedge clk) begin
        if (rst_n) begin
            cycles = cycles+1;
            if (cycles > 3000000)
                $fatal(1,"scale image timeout command=%0d engine=%0d bitmap=%0d row=%0d beat=%0d",
                       completed_count,u_dut.state_r,
                       u_dut.u_bitmap.state_r,
                       u_dut.u_bitmap.row_r,
                       u_dut.u_bitmap.beat_r);
        end
    end
endmodule
