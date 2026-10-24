`timescale 1ns/1ps

module tb_render_fill_dma;
    reg clk;
    reg rst_n;
    reg start;
    wire start_ready;
    reg [31:0] row0_base;
    reg [31:0] stride;
    reg [15:0] x;
    reg [15:0] width;
    reg [15:0] height;
    reg argb;
    reg [31:0] color;
    reg gradient, gradient_vertical;
    reg [31:0] step_a, step_r, step_g, step_b;
    wire busy;
    wire done;
    wire error;
    wire [31:0] beat_count;
    wire [31:0] burst_count;

    wire [3:0] awid;
    wire [31:0] awaddr;
    wire [7:0] awlen;
    wire [2:0] awsize;
    wire [1:0] awburst;
    wire [3:0] awqos;
    wire awvalid;
    wire awready;
    wire [255:0] wdata;
    wire [31:0] wstrb;
    wire wlast;
    wire wvalid;
    wire wready;
    wire [3:0] bid;
    wire [1:0] bresp;
    wire bvalid;
    wire bready;
    wire model_awready;
    wire model_wready;
    wire model_bvalid;
    wire model_bready;
    reg aw_gate;
    reg w_gate;
    reg b_gate;
    integer cycles;
    integer aw_seen;
    integer i;
    integer row;
    integer col;
    integer addr;
    reg [7:0] actual;
    reg [7:0] want;

    always #5 clk = ~clk;

    assign awready = model_awready && aw_gate;
    assign wready = model_wready && w_gate;
    assign bvalid = model_bvalid && b_gate;
    assign model_bready = bready && b_gate;

    edrv32_render_fill_dma u_dut (
        .clk_i(clk), .rst_n_i(rst_n),
        .start_i(start), .start_ready_o(start_ready),
        .row0_base_i(row0_base), .stride_i(stride),
        .x_i(x), .width_i(width), .height_i(height),
        .argb_i(argb), .color_i(color),
        .gradient_i(gradient),
        .gradient_vertical_i(gradient_vertical),
        .gradient_step_a_i(step_a),
        .gradient_step_r_i(step_r),
        .gradient_step_g_i(step_g),
        .gradient_step_b_i(step_b),
        .busy_o(busy), .done_o(done), .error_o(error),
        .beat_count_o(beat_count), .burst_count_o(burst_count),
        .m_awid_o(awid), .m_awaddr_o(awaddr),
        .m_awlen_o(awlen), .m_awsize_o(awsize),
        .m_awburst_o(awburst), .m_awqos_o(awqos),
        .m_awvalid_o(awvalid), .m_awready_i(awready),
        .m_wdata_o(wdata), .m_wstrb_o(wstrb),
        .m_wlast_o(wlast), .m_wvalid_o(wvalid),
        .m_wready_i(wready), .m_bid_i(bid),
        .m_bresp_i(bresp), .m_bvalid_i(bvalid),
        .m_bready_o(bready)
    );

    axi256_mem_model #(.WORDS(4096)) u_mem (
        .clk_i(clk), .rst_n_i(rst_n),
        .awid_i(awid), .awaddr_i(awaddr),
        .awlen_i(awlen), .awsize_i(awsize),
        .awburst_i(awburst), .awvalid_i(awvalid && aw_gate),
        .awready_o(model_awready),
        .wdata_i(wdata), .wstrb_i(wstrb),
        .wlast_i(wlast), .wvalid_i(wvalid && w_gate),
        .wready_o(model_wready),
        .bid_o(bid), .bresp_o(bresp),
        .bvalid_o(model_bvalid), .bready_i(model_bready),
        .arid_i(4'b0), .araddr_i(32'b0),
        .arlen_i(8'b0), .arsize_i(3'b0),
        .arburst_i(2'b0), .arvalid_i(1'b0),
        .arready_o(), .rid_o(), .rdata_o(),
        .rresp_o(), .rlast_o(), .rvalid_o(), .rready_i(1'b0)
    );

    function automatic [7:0] memory_byte;
        input integer byte_address;
        begin
            memory_byte = u_mem.store[byte_address >> 5]
                                      [(byte_address & 31)*8 +: 8];
        end
    endfunction

    function automatic [15:0] memory_pixel16;
        input integer byte_address;
        begin
            memory_pixel16 = u_mem.store[byte_address >> 5]
                [((byte_address & 31)*8) +: 16];
        end
    endfunction

    function automatic [31:0] memory_pixel32;
        input integer byte_address;
        begin
            memory_pixel32 = u_mem.store[byte_address >> 5]
                [((byte_address & 31)*8) +: 32];
        end
    endfunction

    task automatic launch;
        begin
            @(negedge clk);
            if (!start_ready) $fatal(1, "fill DMA not ready");
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            wait(done);
            if (error) $fatal(1, "unexpected fill DMA error");
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        row0_base = 32'b0;
        stride = 32'b0;
        x = 16'b0;
        width = 16'b0;
        height = 16'b0;
        argb = 1'b0;
        color = 32'b0;
        gradient = 1'b0;
        gradient_vertical = 1'b0;
        step_a = 32'd0;
        step_r = 32'd0;
        step_g = 32'd0;
        step_b = 32'd0;
        aw_gate = 1'b1;
        w_gate = 1'b1;
        b_gate = 1'b1;
        cycles = 0;
        aw_seen = 0;
        for (i = 0; i < 4096; i = i + 1)
            u_mem.store[i] = {32{8'ha5}};
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        row0_base = 32'h0000_3000;
        stride = 32'd64;
        x = 16'd3;
        width = 16'd19;
        height = 16'd3;
        argb = 1'b0;
        color = 32'h0000_f81f;
        launch();
        if (beat_count != 6 || burst_count != 3)
            $fatal(1, "RGB565 burst count beats=%0d bursts=%0d",
                   beat_count, burst_count);
        for (row = 0; row < 3; row = row + 1) begin
            for (col = 0; col < 64; col = col + 1) begin
                addr = 'h3000 + row*64 + col;
                want = 8'ha5;
                if (col >= 6 && col < 44)
                    want = col[0] ? 8'hf8 : 8'h1f;
                actual = memory_byte(addr);
                if (actual !== want)
                    $fatal(1, "RGB565 addr=%h got=%h want=%h", addr, actual, want);
            end
        end

        row0_base = 32'h0000_0f00;
        stride = 32'd832;
        x = 16'd0;
        width = 16'd200;
        height = 16'd1;
        argb = 1'b1;
        color = 32'h80ff_00aa;
        launch();
        if (beat_count != 25 || burst_count != 3)
            $fatal(1, "ARGB burst count beats=%0d bursts=%0d",
                   beat_count, burst_count);
        for (col = 0; col < 832; col = col + 1) begin
            addr = 'h0f00 + col;
            want = 8'ha5;
            if (col < 800) begin
                case (col & 3)
                    0: want = 8'haa;
                    1: want = 8'h00;
                    2: want = 8'hff;
                    3: want = 8'h80;
                endcase
            end
            actual = memory_byte(addr);
            if (actual !== want)
                $fatal(1, "ARGB addr=%h got=%h want=%h", addr, actual, want);
        end

        gradient = 1'b1;
        gradient_vertical = 1'b0;
        row0_base = 32'h0000_5000;
        stride = 32'd64;
        x = 16'd3;
        width = 16'd19;
        height = 16'd2;
        argb = 1'b0;
        color = 32'hff00_0000;
        step_a = 32'd0;
        step_r = 32'h0008_0000;
        step_g = 32'h0004_0000;
        step_b = 32'd0;
        launch();
        if (beat_count != 4 || burst_count != 4)
            $fatal(1,"RGB565 gradient count beats=%0d bursts=%0d",
                   beat_count,burst_count);
        for (row=0; row<2; row=row+1)
            for (col=0; col<32; col=col+1) begin
                addr = 32'h0000_5000+row*64+col*2;
                if (col>=3 && col<22)
                    if (memory_pixel16(addr) !==
                        {5'((col-3)),6'((col-3)),5'd0})
                        $fatal(1,"RGB565 gradient mismatch row=%0d col=%0d got=%h",
                               row,col,memory_pixel16(addr));
                if ((col<3 || col>=22) &&
                    memory_pixel16(addr) !== 16'ha5a5)
                    $fatal(1,"RGB565 gradient changed outside rect");
            end

        gradient_vertical = 1'b1;
        row0_base = 32'h0000_7000;
        stride = 32'd96;
        x = 16'd5;
        width = 16'd10;
        height = 16'd5;
        argb = 1'b1;
        color = 32'h2020_0000;
        step_a = 32'h0020_0000;
        step_r = 32'h0020_0000;
        step_g = 32'h0008_0000;
        step_b = 32'd0;
        launch();
        for (row=0; row<5; row=row+1)
            for (col=0; col<24; col=col+1) begin
                addr = 32'h0000_7000+row*96+col*4;
                if (col>=5 && col<15) begin
                    if (memory_pixel32(addr) !==
                        {8'(32+row*32),8'(32+row*32),
                         8'(row*8),8'd0})
                        $fatal(1,"ARGB vertical gradient mismatch row=%0d col=%0d got=%h",
                               row,col,memory_pixel32(addr));
                end else if (memory_pixel32(addr) !== 32'ha5a5_a5a5)
                    $fatal(1,"ARGB gradient changed outside rect");
            end

        gradient_vertical = 1'b0;
        row0_base = 32'h0000_8000;
        stride = 32'd32;
        x = 16'd0;
        width = 16'd8;
        height = 16'd1;
        argb = 1'b1;
        color = 32'hfffe_0000;
        step_a = 32'd0;
        step_r = 32'hffc0_0000;
        step_g = 32'd0;
        step_b = 32'd0;
        launch();
        for (col=0; col<8; col=col+1) begin
            addr = 32'h0000_8000+col*4;
            want = col<4 ? 8'(254-col*64) : 8'd0;
            if (memory_pixel32(addr) !== {8'hff,want,16'd0})
                $fatal(1,"negative gradient clamp mismatch col=%0d got=%h",
                       col,memory_pixel32(addr));
        end
        $display("RENDER_FILL_DMA_PASS bursts=%0d beats=%0d", burst_count,
                 beat_count);
        $finish;
    end

    always @(negedge clk) begin
        if (rst_n) begin
            aw_gate = $urandom_range(0, 3) != 0;
            w_gate  = $urandom_range(0, 3) != 0;
            b_gate  = $urandom_range(0, 3) != 0;
        end
    end

    always @(posedge clk) begin
        if (rst_n) begin
            cycles = cycles + 1;
            if (awvalid && awready) begin
                aw_seen = aw_seen + 1;
                if (awaddr[4:0] != 5'd0 || awlen > 8'd15 ||
                    awsize != 3'd5 || awburst != 2'b01 ||
                    (awaddr[11:0] + (awlen + 1)*32 > 4096))
                    $fatal(1, "invalid fill burst addr=%h len=%0d", awaddr, awlen);
            end
            if (cycles > 20000)
                $fatal(1, "fill DMA timeout");
        end
    end
endmodule
