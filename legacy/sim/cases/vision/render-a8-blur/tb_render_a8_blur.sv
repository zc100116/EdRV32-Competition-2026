`timescale 1ns/1ps

module tb_render_a8_blur;
    localparam [31:0] SOURCE = 32'h0000_1000;
    localparam [31:0] SCRATCH = 32'h0000_4000;
    localparam [31:0] OUTPUT = 32'h0000_7000;
    localparam integer STRIDE = 96;
    reg clk, rst_n, start;
    reg [15:0] width, height;
    reg [4:0] radius;
    wire start_ready, busy, done, error;
    wire [31:0] write_beats;
    wire [3:0] arid, rid, awid, bid;
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
    reg [7:0] src_ref [0:6143];
    reg [7:0] h_ref [0:6143];
    reg [7:0] v_ref [0:6143];
    integer i, x, y, tap, sum, win, cases, cycles, address;

    always #5 clk = ~clk;

    edrv32_render_a8_blur_dma u_dut (
        .clk_i(clk), .rst_n_i(rst_n),
        .start_i(start), .start_ready_o(start_ready),
        .source_base_i(SOURCE), .source_stride_i(STRIDE),
        .scratch_base_i(SCRATCH), .scratch_stride_i(STRIDE),
        .output_base_i(OUTPUT), .output_stride_i(STRIDE),
        .width_i(width), .height_i(height), .radius_i(radius),
        .busy_o(busy), .done_o(done), .error_o(error),
        .write_beat_count_o(write_beats),
        .m_arid_o(arid), .m_araddr_o(araddr),
        .m_arlen_o(arlen), .m_arsize_o(arsize),
        .m_arburst_o(arburst), .m_arqos_o(arqos),
        .m_arvalid_o(arvalid), .m_arready_i(arready && ar_gate),
        .m_rid_i(rid), .m_rdata_i(rdata),
        .m_rresp_i(rresp), .m_rlast_i(rlast),
        .m_rvalid_i(rvalid && r_gate), .m_rready_o(rready),
        .m_awid_o(awid), .m_awaddr_o(awaddr),
        .m_awlen_o(awlen), .m_awsize_o(awsize),
        .m_awburst_o(awburst), .m_awqos_o(awqos),
        .m_awvalid_o(awvalid), .m_awready_i(awready && aw_gate),
        .m_wdata_o(wdata), .m_wstrb_o(wstrb),
        .m_wlast_o(wlast), .m_wvalid_o(wvalid),
        .m_wready_i(wready && w_gate),
        .m_bid_i(bid), .m_bresp_i(bresp),
        .m_bvalid_i(bvalid && b_gate), .m_bready_o(bready)
    );

    axi256_mem_model #(.WORDS(4096)) u_mem (
        .clk_i(clk), .rst_n_i(rst_n),
        .awid_i(awid), .awaddr_i(awaddr),
        .awlen_i(awlen), .awsize_i(awsize),
        .awburst_i(awburst), .awvalid_i(awvalid && aw_gate),
        .awready_o(awready),
        .wdata_i(wdata), .wstrb_i(wstrb),
        .wlast_i(wlast), .wvalid_i(wvalid && w_gate),
        .wready_o(wready),
        .bid_o(bid), .bresp_o(bresp),
        .bvalid_o(bvalid), .bready_i(bready && b_gate),
        .arid_i(arid), .araddr_i(araddr),
        .arlen_i(arlen), .arsize_i(arsize),
        .arburst_i(arburst), .arvalid_i(arvalid && ar_gate),
        .arready_o(arready),
        .rid_o(rid), .rdata_o(rdata),
        .rresp_o(rresp), .rlast_o(rlast),
        .rvalid_o(rvalid), .rready_i(rready && r_gate)
    );

    function automatic [7:0] memory_byte;
        input integer byte_address;
        begin
            memory_byte = u_mem.store[byte_address >> 5]
                [((byte_address & 31)*8) +: 8];
        end
    endfunction

    task automatic run_blur;
        input integer test_width, test_height, test_radius;
        begin
            width = test_width;
            height = test_height;
            radius = test_radius;
            win = 2*test_radius+1;
            for (y=0; y<test_height; y=y+1) begin
                for (x=0; x<STRIDE; x=x+1) begin
                    address = SOURCE+y*STRIDE+x;
                    u_mem.store[address >> 5]
                        [((address & 31)*8) +: 8] = 8'd0;
                    address = SCRATCH+y*STRIDE+x;
                    u_mem.store[address >> 5]
                        [((address & 31)*8) +: 8] = 8'ha5;
                    address = OUTPUT+y*STRIDE+x;
                    u_mem.store[address >> 5]
                        [((address & 31)*8) +: 8] = 8'ha5;
                end
                for (x=0; x<test_width; x=x+1) begin
                    src_ref[y*STRIDE+x] = $urandom_range(0,255);
                    address = SOURCE+y*STRIDE+x;
                    u_mem.store[address >> 5]
                        [((address & 31)*8) +: 8] =
                        src_ref[y*STRIDE+x];
                end
            end
            for (y=0; y<test_height; y=y+1)
                for (x=0; x<test_width; x=x+1) begin
                    sum = 0;
                    for (tap=-test_radius; tap<=test_radius;
                         tap=tap+1)
                        if (x+tap>=0 && x+tap<test_width)
                            sum = sum + src_ref[y*STRIDE+x+tap];
                    h_ref[y*STRIDE+x] = (sum+win/2)/win;
                end
            for (y=0; y<test_height; y=y+1)
                for (x=0; x<test_width; x=x+1) begin
                    sum = 0;
                    for (tap=-test_radius; tap<=test_radius;
                         tap=tap+1)
                        if (y+tap>=0 && y+tap<test_height)
                            sum = sum + h_ref[(y+tap)*STRIDE+x];
                    v_ref[y*STRIDE+x] = (sum+win/2)/win;
                end
            @(negedge clk);
            if (!start_ready)
                $fatal(1,"blur not ready");
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            wait(done);
            if (error || write_beats !=
                2*test_height*((test_width+31)/32))
                $fatal(1,"blur failed width=%0d height=%0d radius=%0d error=%b beats=%0d",
                       test_width,test_height,test_radius,
                       error,write_beats);
            for (y=0; y<test_height; y=y+1)
                for (x=0; x<STRIDE; x=x+1) begin
                    address = SCRATCH+y*STRIDE+x;
                    if (memory_byte(address) !==
                        (x<test_width ? h_ref[y*STRIDE+x] : 8'ha5))
                        $fatal(1,"horizontal blur mismatch case=%0d x=%0d y=%0d got=%h",
                               cases,x,y,memory_byte(address));
                    address = OUTPUT+y*STRIDE+x;
                    if (memory_byte(address) !==
                        (x<test_width ? v_ref[y*STRIDE+x] : 8'ha5))
                        $fatal(1,"vertical blur mismatch case=%0d x=%0d y=%0d got=%h",
                               cases,x,y,memory_byte(address));
                end
            cases = cases + 1;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        width = 16'd0;
        height = 16'd0;
        radius = 5'd0;
        ar_gate = 1'b1;
        r_gate = 1'b1;
        aw_gate = 1'b1;
        w_gate = 1'b1;
        b_gate = 1'b1;
        cycles = 0;
        cases = 0;
        for (i=0; i<4096; i=i+1)
            u_mem.store[i] = {32{8'ha5}};
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        run_blur(1,1,0);
        run_blur(17,3,1);
        run_blur(32,7,3);
        run_blur(33,5,2);
        run_blur(61,4,15);
        run_blur(65,40,15);
        $display("RENDER_A8_BLUR_PASS cases=%0d cycles=%0d",cases,cycles);
        $finish;
    end

    always @(negedge clk) begin
        if (rst_n) begin
            ar_gate = $urandom_range(0,7) != 0;
            r_gate = $urandom_range(0,7) != 0;
            aw_gate = $urandom_range(0,7) != 0;
            w_gate = $urandom_range(0,7) != 0;
            b_gate = $urandom_range(0,7) != 0;
        end
    end

    always @(posedge clk) begin
        if (rst_n) begin
            cycles = cycles+1;
            if (cycles > 200000)
                $fatal(1,"A8 blur timeout state=%0d row=%0d beat=%0d",
                       u_dut.state_r,u_dut.row_r,u_dut.beat_r);
        end
    end
endmodule
