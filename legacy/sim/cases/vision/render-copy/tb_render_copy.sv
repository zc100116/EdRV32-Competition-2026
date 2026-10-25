`timescale 1ns/1ps

module tb_render_copy;
    localparam integer WORDS = 2048;
    localparam integer STRIDE = 128;

    reg clk, rst_n, start;
    wire start_ready, busy, done, error;
    reg [31:0] src_base, dst_base;
    reg [31:0] src_stride, dst_stride;
    reg [15:0] src_x, dst_x, width, height;
    reg argb;
    reg separate_surfaces;
    wire [31:0] beat_count;
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
    reg [255:0] expected [0:WORDS-1];
    reg [7:0] snapshot [0:4095];
    integer i, j, row, byte_index, bytes_per_pixel;
    integer cycles, cases;
    integer write_bursts, write_beats;
    reg reverse_eight_witness;
    integer random_width, random_height;
    integer random_source_row, random_target_row;
    integer random_source_x, random_target_x;
    integer random_argb, pixels_per_row, surface_base;

    always #5 clk = ~clk;

    edrv32_render_copy_dma u_dut (
        .clk_i(clk), .rst_n_i(rst_n),
        .start_i(start), .start_ready_o(start_ready),
        .source_row0_addr_i(src_base),
        .source_stride_i(src_stride), .source_x_i(src_x),
        .target_row0_addr_i(dst_base),
        .target_stride_i(dst_stride), .target_x_i(dst_x),
        .width_i(width), .height_i(height), .argb_i(argb),
        .separate_surfaces_i(separate_surfaces),
        .busy_o(busy), .done_o(done), .error_o(error),
        .beat_count_o(beat_count),
        .m_arid_o(arid), .m_araddr_o(araddr),
        .m_arlen_o(arlen), .m_arsize_o(arsize),
        .m_arburst_o(arburst), .m_arqos_o(arqos),
        .m_arvalid_o(arvalid), .m_arready_i(arready && ar_gate),
        .m_rid_i(rid), .m_rdata_i(rdata),
        .m_rresp_i(rresp), .m_rlast_i(rlast),
        .m_rvalid_i(rvalid && r_gate),
        .m_rready_o(rready),
        .m_awid_o(awid), .m_awaddr_o(awaddr),
        .m_awlen_o(awlen), .m_awsize_o(awsize),
        .m_awburst_o(awburst), .m_awqos_o(awqos),
        .m_awvalid_o(awvalid), .m_awready_i(awready && aw_gate),
        .m_wdata_o(wdata), .m_wstrb_o(wstrb),
        .m_wlast_o(wlast), .m_wvalid_o(wvalid),
        .m_wready_i(wready && w_gate),
        .m_bid_i(bid), .m_bresp_i(bresp),
        .m_bvalid_i(bvalid && b_gate),
        .m_bready_o(bready)
    );

    axi256_mem_model #(.WORDS(WORDS)) u_mem (
        .clk_i(clk), .rst_n_i(rst_n),
        .awid_i(awid), .awaddr_i(awaddr),
        .awlen_i(awlen), .awsize_i(awsize),
        .awburst_i(awburst),
        .awvalid_i(awvalid && aw_gate), .awready_o(awready),
        .wdata_i(wdata), .wstrb_i(wstrb),
        .wlast_i(wlast), .wvalid_i(wvalid && w_gate),
        .wready_o(wready), .bid_o(bid), .bresp_o(bresp),
        .bvalid_o(bvalid), .bready_i(bready && b_gate),
        .arid_i(arid), .araddr_i(araddr),
        .arlen_i(arlen), .arsize_i(arsize),
        .arburst_i(arburst),
        .arvalid_i(arvalid && ar_gate), .arready_o(arready),
        .rid_o(rid), .rdata_o(rdata), .rresp_o(rresp),
        .rlast_o(rlast), .rvalid_o(rvalid),
        .rready_i(rready && r_gate)
    );

    function automatic [7:0] expected_byte;
        input integer address;
        begin
            expected_byte = expected[address >> 5]
                                    [(address & 31)*8 +: 8];
        end
    endfunction

    task automatic run_copy;
        input integer source_address, target_address;
        input integer source_pixel_x, target_pixel_x;
        input integer copy_width, copy_height;
        input integer argb_mode;
        input integer row_stride;
        integer n, source_byte_addr, target_byte_addr;
        begin
            bytes_per_pixel = argb_mode ? 4 : 2;
            n = 0;
            for (row=0; row<copy_height; row=row+1)
                for (byte_index=0;
                     byte_index<copy_width*bytes_per_pixel;
                     byte_index=byte_index+1) begin
                    source_byte_addr = source_address + row*row_stride +
                                       source_pixel_x*bytes_per_pixel +
                                       byte_index;
                    snapshot[n] = expected_byte(source_byte_addr);
                    n = n + 1;
                end
            n = 0;
            for (row=0; row<copy_height; row=row+1)
                for (byte_index=0;
                     byte_index<copy_width*bytes_per_pixel;
                     byte_index=byte_index+1) begin
                    target_byte_addr = target_address + row*row_stride +
                                       target_pixel_x*bytes_per_pixel +
                                       byte_index;
                    expected[target_byte_addr >> 5]
                        [(target_byte_addr & 31)*8 +: 8] = snapshot[n];
                    n = n + 1;
                end
            @(negedge clk);
            wait(start_ready);
            src_base = source_address;
            dst_base = target_address;
            src_stride = row_stride;
            dst_stride = row_stride;
            src_x = source_pixel_x;
            dst_x = target_pixel_x;
            width = copy_width;
            height = copy_height;
            argb = argb_mode != 0;
            separate_surfaces = 1'b0;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            wait(done);
            if (error || beat_count == 0)
                $fatal(1, "copy failed case=%0d error=%b beats=%0d",
                       cases,error,beat_count);
            for (i=0; i<WORDS; i=i+1)
                if (u_mem.store[i] !== expected[i])
                    $fatal(1, "copy mismatch case=%0d word=%0d got=%h want=%h",
                           cases,i,u_mem.store[i],expected[i]);
            cases = cases + 1;
        end
    endtask

    task automatic run_disjoint_copy;
        input integer source_address, target_address;
        input integer source_row_stride, target_row_stride;
        input integer source_pixel_x, target_pixel_x;
        input integer copy_width, copy_height, argb_mode;
        integer n, source_byte_addr, target_byte_addr;
        begin
            bytes_per_pixel = argb_mode ? 4 : 2;
            n = 0;
            for (row=0; row<copy_height; row=row+1)
                for (byte_index=0;
                     byte_index<copy_width*bytes_per_pixel;
                     byte_index=byte_index+1) begin
                    source_byte_addr = source_address +
                        row*source_row_stride +
                        source_pixel_x*bytes_per_pixel + byte_index;
                    snapshot[n] = expected_byte(source_byte_addr);
                    n = n + 1;
                end
            n = 0;
            for (row=0; row<copy_height; row=row+1)
                for (byte_index=0;
                     byte_index<copy_width*bytes_per_pixel;
                     byte_index=byte_index+1) begin
                    target_byte_addr = target_address +
                        row*target_row_stride +
                        target_pixel_x*bytes_per_pixel + byte_index;
                    expected[target_byte_addr >> 5]
                        [(target_byte_addr & 31)*8 +: 8] = snapshot[n];
                    n = n + 1;
                end
            @(negedge clk);
            wait(start_ready);
            src_base = source_address;
            dst_base = target_address;
            src_stride = source_row_stride;
            dst_stride = target_row_stride;
            src_x = source_pixel_x;
            dst_x = target_pixel_x;
            width = copy_width;
            height = copy_height;
            argb = argb_mode != 0;
            separate_surfaces = 1'b1;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            wait(done);
            if (error || beat_count == 0)
                $fatal(1,"disjoint copy failed case=%0d error=%b",
                       cases,error);
            for (i=0; i<WORDS; i=i+1)
                if (u_mem.store[i] !== expected[i])
                    $fatal(1,"disjoint copy mismatch case=%0d word=%0d",
                           cases,i);
            cases = cases + 1;
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
        src_base = 32'd0;
        dst_base = 32'd0;
        src_stride = 32'd0;
        dst_stride = 32'd0;
        src_x = 16'd0;
        dst_x = 16'd0;
        width = 16'd0;
        height = 16'd0;
        argb = 1'b0;
        separate_surfaces = 1'b0;
        cycles = 0;
        cases = 0;
        write_bursts = 0;
        write_beats = 0;
        reverse_eight_witness = 1'b0;
        for (i=0; i<WORDS; i=i+1) begin
            for (j=0; j<32; j=j+1)
                expected[i][j*8 +: 8] = (i*37+j*11)&8'hff;
            u_mem.store[i] = expected[i];
        end
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        run_copy('h2000,'h2000,3,7,27,5,0,STRIDE);
        run_copy('h2000+5*STRIDE,'h2000+5*STRIDE,
                 17,2,31,4,0,STRIDE);
        run_copy('h6000,'h6000+2*STRIDE,1,5,18,7,1,STRIDE);
        run_copy('h6000+3*STRIDE,'h6000,6,2,20,6,1,STRIDE);
        run_copy('h3fe0,'hbfe0,1,9,26,3,0,STRIDE);
        run_copy('ha000,'ha000,0,7,64,1,1,512);
        run_copy('ha000,'hbfe0,0,7,64,1,1,512);
        if (!reverse_eight_witness)
            $fatal(1,"reverse eight-beat COPY tile was not issued");

        for (j=0; j<32; j=j+1) begin
            random_argb = j & 1;
            pixels_per_row = random_argb ? 32 : 64;
            surface_base = random_argb ? 'h6000 : 'h2000;
            random_width = 1 + $urandom_range(0,
                           random_argb ? 23 : 39);
            random_height = 1 + $urandom_range(0,7);
            random_source_row = $urandom_range(0,16-random_height);
            random_target_row = $urandom_range(0,16-random_height);
            random_source_x = $urandom_range(0,
                              pixels_per_row-random_width);
            random_target_x = $urandom_range(0,
                              pixels_per_row-random_width);
            run_copy(surface_base + random_source_row*STRIDE,
                     surface_base + random_target_row*STRIDE,
                     random_source_x,random_target_x,
                     random_width,random_height,random_argb,STRIDE);
        end

        @(negedge clk);
        wait(start_ready);
        src_base = 'h2000;
        dst_base = 'h3000;
        src_stride = STRIDE;
        dst_stride = STRIDE + 32;
        src_x = 0;
        dst_x = 0;
        width = 8;
        height = 2;
        argb = 1'b0;
        separate_surfaces = 1'b0;
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        wait(done);
        if (!error || beat_count != 0)
            $fatal(1, "mismatched strides were not rejected");
        run_disjoint_copy('h4000,'hc000,128,192,3,7,25,5,0);
        run_disjoint_copy('h5000,'hd000,256,160,5,1,19,4,1);
        $display("RENDER_COPY_PASS cases=%0d invalid=1 writes=%0d bursts=%0d reverse8=1 cycles=%0d",
                 cases,write_beats,write_bursts,cycles);
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
            cycles = cycles + 1;
            if (awvalid && awready && aw_gate) begin
                if (awlen > 8'd7 ||
                    awaddr[11:0] + (awlen+1)*32 > 4096)
                    $fatal(1,"COPY write burst invalid");
                write_bursts = write_bursts + 1;
                if (awaddr == 32'h0000_c000 && awlen == 8'd7)
                    reverse_eight_witness = 1'b1;
            end
            if (wvalid && wready && w_gate)
                write_beats = write_beats + 1;
            if (cycles > 200000)
                $fatal(1, "copy timeout state=%0d case=%0d",
                       u_dut.state_r,cases);
        end
    end
endmodule
