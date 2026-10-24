`timescale 1ns/1ps

module tb_render_shadow_mask;
    localparam [31:0] MASK_BASE = 32'h0000_1000;
    localparam integer STRIDE = 96;
    reg clk, rst_n, start;
    reg [15:0] width, height;
    reg [7:0] corner_radius;
    reg [4:0] blur_radius;
    wire start_ready, busy, done, error;
    wire [31:0] beat_count;
    wire [3:0] awid, bid;
    wire [31:0] awaddr;
    wire [7:0] awlen;
    wire [2:0] awsize;
    wire [1:0] awburst;
    wire [3:0] awqos;
    wire awvalid, awready, wvalid, wready, wlast;
    wire bvalid, bready;
    wire [255:0] wdata;
    wire [31:0] wstrb;
    wire [1:0] bresp;
    reg aw_gate, w_gate, b_gate;
    integer i, x, y, cases, cycles, address;
    reg [7:0] wanted;

    always #5 clk = ~clk;

    edrv32_render_shadow_mask_dma u_dut (
        .clk_i(clk), .rst_n_i(rst_n),
        .start_i(start), .start_ready_o(start_ready),
        .mask_base_i(MASK_BASE), .mask_stride_i(STRIDE),
        .width_i(width), .height_i(height),
        .corner_radius_i(corner_radius),
        .blur_radius_i(blur_radius),
        .busy_o(busy), .done_o(done), .error_o(error),
        .beat_count_o(beat_count),
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

    axi256_mem_model #(.WORDS(2048)) u_mem (
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
        .arid_i(4'd0), .araddr_i(32'd0),
        .arlen_i(8'd0), .arsize_i(3'd5),
        .arburst_i(2'b01), .arvalid_i(1'b0),
        .arready_o(), .rid_o(), .rdata_o(),
        .rresp_o(), .rlast_o(), .rvalid_o(),
        .rready_i(1'b0)
    );

    function automatic [7:0] memory_byte;
        input integer byte_address;
        begin
            memory_byte = u_mem.store[byte_address >> 5]
                [((byte_address & 31)*8) +: 8];
        end
    endfunction

    function automatic [7:0] ref_mask;
        input integer px, py, w, h, corner, blur;
        integer lx, ly, iw, ih, rx, ry, dx, dy;
        begin
            ref_mask = 8'd0;
            lx = px-blur;
            ly = py-blur;
            iw = w-2*blur;
            ih = h-2*blur;
            if (lx>=0 && ly>=0 && lx<iw && ly<ih) begin
                rx = lx < iw-1-lx ? lx : iw-1-lx;
                ry = ly < ih-1-ly ? ly : ih-1-ly;
                dx = rx < corner ? corner-1-rx : 0;
                dy = ry < corner ? corner-1-ry : 0;
                if (corner==0 || dx*dx+dy*dy <= corner*corner)
                    ref_mask = 8'hff;
            end
        end
    endfunction

    task automatic run_case;
        input integer w, h, corner, blur;
        begin
            width = w;
            height = h;
            corner_radius = corner;
            blur_radius = blur;
            for (y=0; y<h; y=y+1)
                for (x=0; x<STRIDE; x=x+1) begin
                    address = MASK_BASE+y*STRIDE+x;
                    u_mem.store[address >> 5]
                        [((address & 31)*8) +: 8] = 8'ha5;
                end
            @(negedge clk);
            if (!start_ready)
                $fatal(1,"shadow mask not ready");
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            wait(done);
            if (error || beat_count != h*((w+31)/32))
                $fatal(1,"shadow mask failed w=%0d h=%0d r=%0d b=%0d error=%b beats=%0d",
                       w,h,corner,blur,error,beat_count);
            for (y=0; y<h; y=y+1)
                for (x=0; x<STRIDE; x=x+1) begin
                    address = MASK_BASE+y*STRIDE+x;
                    wanted = x<w ? ref_mask(x,y,w,h,corner,blur) :
                                   8'ha5;
                    if (memory_byte(address) !== wanted)
                        $fatal(1,"shadow mask mismatch case=%0d x=%0d y=%0d got=%h want=%h",
                               cases,x,y,memory_byte(address),wanted);
                end
            cases = cases+1;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        width = 16'd0;
        height = 16'd0;
        corner_radius = 8'd0;
        blur_radius = 5'd0;
        aw_gate = 1'b1;
        w_gate = 1'b1;
        b_gate = 1'b1;
        cases = 0;
        cycles = 0;
        for (i=0; i<2048; i=i+1)
            u_mem.store[i] = {32{8'ha5}};
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        run_case(32,24,0,0);
        run_case(61,45,12,4);
        run_case(33,20,6,3);
        $display("RENDER_SHADOW_MASK_PASS cases=%0d cycles=%0d",
                 cases,cycles);
        $finish;
    end

    always @(negedge clk) begin
        if (rst_n) begin
            aw_gate = $urandom_range(0,7) != 0;
            w_gate = $urandom_range(0,7) != 0;
            b_gate = $urandom_range(0,7) != 0;
        end
    end

    always @(posedge clk) begin
        if (rst_n) begin
            cycles = cycles+1;
            if (cycles > 200000)
                $fatal(1,"shadow mask timeout state=%0d row=%0d beat=%0d",
                       u_dut.state_r,u_dut.row_r,u_dut.beat_r);
        end
    end
endmodule
