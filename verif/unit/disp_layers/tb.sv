// File: tb.sv
// Spec: disp-spec 2.4, 2.7, 4.3, 6.
// Description: Bit-exact blend, all scroll offsets, rectangle edges and per-layer debt.
// Clock domain: asynchronous test memory and pixel clocks.
module tb;
    reg clk_mem = 0;
    reg clk = 0;
    int mem_half = 3;
    int pix_half = 5;
    always #(mem_half) clk_mem = ~clk_mem;
    always #(pix_half) clk = ~clk;
    reg rst_n = 0;
    reg enable = 0;
    reg de = 0;
    reg [10:0] x = 0;
    reg [9:0] y = 0;
    reg vblank = 0;
    reg params_send = 0;
    reg [55:0] params_src = 0;
    wire params_ready;
    wire params_valid;
    wire [55:0] params;
    reg valid0 = 0;
    reg valid1 = 0;
    wire ready0;
    wire ready1;
    reg [255:0] data0 = 0;
    reg [255:0] data1 = 0;
    wire [23:0] rgb;
    wire frame_req;
    wire error0;
    wire error1;
    wire [9:0] read0;
    wire [9:0] read1;
    wire [31:0] perf0;
    wire [31:0] perf1;
    int pops0 = 0;
    int pops1 = 0;
    int receipts = 0;
    // disp-spec 2.7 specifies pixel correspondence, without a fixed output latency.
    // FIFO schedules follow the three raster/rectangle stages; RGB follows eleven stages.
    localparam SCAN_STAGES = 11;
    reg [SCAN_STAGES-1:0] expect_valid = 0;
    reg [23:0] expect_rgb [0:SCAN_STAGES-1];
    reg [3:0] expect_pop0 = 0;
    reg [3:0] expect_pop1 = 0;
    reg [3:0] expect_error0 = 0;
    reg [3:0] expect_error1 = 0;
    reg source_valid = 0;
    reg [23:0] source_rgb = 0;
    reg source_pop0 = 0;
    reg source_pop1 = 0;
    reg source_error0 = 0;
    reg source_error1 = 0;
    reg valid0_pipe0 = 0;
    reg valid0_pipe1 = 0;
    reg valid0_pipe2 = 0;
    reg valid1_pipe0 = 0;
    reg valid1_pipe1 = 0;
    reg valid1_pipe2 = 0;
    reg [255:0] data0_pipe0 = 0;
    reg [255:0] data0_pipe1 = 0;
    reg [255:0] data0_pipe2 = 0;
    reg [255:0] data1_pipe0 = 0;
    reg [255:0] data1_pipe1 = 0;
    reg [255:0] data1_pipe2 = 0;
    always @(negedge clk) source_valid = 0;
    always @(posedge clk) begin
        valid0_pipe0 <= valid0;
        valid0_pipe1 <= valid0_pipe0;
        valid0_pipe2 <= valid0_pipe1;
        valid1_pipe0 <= valid1;
        valid1_pipe1 <= valid1_pipe0;
        valid1_pipe2 <= valid1_pipe1;
        data0_pipe0 <= data0;
        data0_pipe1 <= data0_pipe0;
        data0_pipe2 <= data0_pipe1;
        data1_pipe0 <= data1;
        data1_pipe1 <= data1_pipe0;
        data1_pipe2 <= data1_pipe1;
    end
    always @(posedge clk) begin : pipeline_scoreboard
        bit actual_pop0;
        bit actual_pop1;
        bit actual_error0;
        bit actual_error1;
        actual_pop0 = valid0_pipe2 && ready0;
        actual_pop1 = valid1_pipe2 && ready1;
        actual_error0 = error0;
        actual_error1 = error1;
        if (!rst_n) begin
            expect_valid = 0;
        end else begin
            for (int stage = SCAN_STAGES-1; stage > 0; stage--)
                expect_rgb[stage] = expect_rgb[stage-1];
            expect_rgb[0] = source_rgb;
            expect_valid = {expect_valid[SCAN_STAGES-2:0], source_valid};
            expect_pop0 = {expect_pop0[2:0], source_pop0};
            expect_pop1 = {expect_pop1[2:0], source_pop1};
            expect_error0 = {expect_error0[2:0], source_error0};
            expect_error1 = {expect_error1[2:0], source_error1};
            if (expect_valid[3]) begin
                if (actual_pop0 !== expect_pop0[3] || actual_pop1 !== expect_pop1[3] ||
                    actual_error0 !== expect_error0[3] || actual_error1 !== expect_error1[3])
                    $fatal(1, "FAIL scan pops/errors actual=%b%b/%b%b expected=%b%b/%b%b",
                           actual_pop1, actual_pop0, actual_error1, actual_error0,
                           expect_pop1[3], expect_pop0[3], expect_error1[3], expect_error0[3]);
                pops0 += int'(expect_pop0[3]);
                pops1 += int'(expect_pop1[3]);
            end
            #2;
            if (expect_valid[SCAN_STAGES-1] && rgb !== expect_rgb[SCAN_STAGES-1])
                $fatal(1, "FAIL pipelined RGB actual=%h expected=%h time=%0t",
                       rgb, expect_rgb[SCAN_STAGES-1], $time);
            if (expect_valid[3] && read0 !== 10'(pops0))
                $fatal(1, "FAIL pipelined L0 read counter actual=%0d expected=%0d",
                       read0, pops0);
            if (expect_valid[3] && read1 !== 10'(pops1))
                $fatal(1, "FAIL pipelined L1 read counter actual=%0d expected=%0d",
                       read1, pops1);
        end
    end
    task automatic drain;
        @(negedge clk);
        de = 0;
        valid0 = 0;
        valid1 = 0;
        repeat (SCAN_STAGES+1) @(negedge clk);
    endtask
    edrv32_cdc_handshake #(.WIDTH(56)) u_params (
        .clk_src_i(clk_mem), .rst_src_n_i(rst_n), .clk_dst_i(clk), .rst_dst_n_i(rst_n),
        .valid_i(params_send), .ready_o(params_ready), .data_i(params_src),
        .valid_o(params_valid), .ready_i(1'b1), .data_o(params)
    );
    edrv32_disp_scan dut (
        .clk_i(clk), .rst_n_i(rst_n), .enable_i(enable), .de_i(de), .x_i(x), .y_i(y),
        .frame_start_i(de && x == 0 && y == 0),
        .vblank_i(vblank), .params_valid_i(params_valid), .params_i(params),
        .fifo_valid_i(valid0_pipe2), .fifo_ready_o(ready0), .fifo_data_i(data0_pipe2),
        .fifo1_valid_i(valid1_pipe2), .fifo1_ready_o(ready1), .fifo1_data_i(data1_pipe2), .rgb_o(rgb),
        .frame_req_o(frame_req), .underflow_o(error0), .underflow1_o(error1),
        .read_cnt_o(read0), .read1_cnt_o(read1), .perf0_o(perf0), .perf1_o(perf1)
    );
    always @(posedge clk) if (rst_n && params_valid) receipts++;
    function automatic [15:0] pixel0(input int index, input int row);
        return 16'(index*173+row*379+2051);
    endfunction
    function automatic [255:0] packet0(input int index, input int row);
        for (int n = 0; n < 16; n++) packet0[n*16 +: 16] = pixel0(index+n, row);
    endfunction
    function automatic [255:0] packet1(input int alpha, input int index);
        for (int n = 0; n < 8; n++)
            packet1[n*32 +: 32] = {8'(alpha+n), 8'((index+n)*37),
                                   8'(255-(index+n)*17), 8'((index+n)*71)};
    endfunction
    function automatic [23:0] expand(input [15:0] pixel);
        return {pixel[15:11], pixel[15:13], pixel[10:5], pixel[10:9],
                pixel[4:0], pixel[4:2]};
    endfunction
    function automatic [23:0] blend(input [23:0] background, input [31:0] foreground,
                                    input int opacity);
        int alpha;
        int result_c;
        alpha = (int'(foreground[31:24])*opacity+127)/255;
        for (int c = 0; c < 3; c++) begin
            result_c = (alpha*int'(foreground[c*8 +: 8])+
                        (255-alpha)*int'(background[c*8 +: 8])+127)/255;
            blend[c*8 +: 8] = 8'(result_c);
        end
    endfunction
    task automatic sample(input [23:0] expected, input bit pop0, input bit pop1,
                          input bit err0 = 0, input bit err1 = 0);
        #1;
        source_valid = 1;
        source_rgb = expected;
        source_pop0 = pop0;
        source_pop1 = pop1;
        source_error0 = err0;
        source_error1 = err1;
        @(posedge clk);
        #3;
    endtask
    task automatic idle;
        @(negedge clk);
        de = 0;
        valid0 = 0;
        valid1 = 0;
    endtask
    task automatic config_frame(input bit en0, input int offset, input bit en1,
                                input int px, input int py, input int width1,
                                input int height1, input int opacity);
        int before_receipts;
        reg [55:0] sent_params;
        idle();
        before_receipts = receipts;
        sent_params = {en0, 4'(offset), en1, 11'(px), 10'(py), 11'(width1),
                       10'(height1), 8'(opacity)};
        @(negedge clk_mem);
        if (!params_ready) $fatal(1, "FAIL previous parameter handshake incomplete");
        params_src = sent_params;
        params_send = 1;
        @(negedge clk_mem);
        params_send = 0;
        params_src = ~sent_params;
        wait (receipts == before_receipts+1);
        #1;
        if (params !== sent_params) $fatal(1, "FAIL parameter payload changed after send");
        wait (params_ready);
        idle();
    endtask
    task automatic boundary(input bit scan_enable = 1);
        idle();
        enable = scan_enable;
        vblank = 1;
        #1;
        if (frame_req !== scan_enable) $fatal(1, "FAIL request enable");
        sample(0, 0, 0);
        @(negedge clk);
        vblank = 0;
    endtask
    initial begin
        int row_pops;
        reg [255:0] expected_packet;
        reg [31:0] foreground;
        reg [23:0] background;
        repeat (5) @(negedge clk);
        rst_n = 1;
        // Every p reads exactly ceil((p+1280)/16) beats, including discarded row tail.
        for (int offset = 0; offset < 16; offset++) begin
            config_frame(1, offset, 0, 0, 0, 1280, 720, 255);
            boundary();
            for (int row = 0; row < 2; row++) begin
                row_pops = pops0;
                for (int column = 0; column < 1280; column++) begin
                    @(negedge clk);
                    de = 1; x = 11'(column); y = 10'(row);
                    valid0 = 1;
                    data0 = packet0(((column+offset)/16)*16, row);
                    sample(expand(pixel0(column+offset,row)),
                           column == 0 || (column+offset)%16 == 0, 0);
                end
                drain();
                if (pops0-row_pops != (offset == 0 ? 80 : 81))
                    $fatal(1, "FAIL scroll beat count p=%0d",offset);
                // Receipt in the middle of a frame must leave the second row unchanged.
                if (row == 0) config_frame(0, 0, 1, 0, 0, 1280, 720, 0);
                idle();
            end
        end
        // Every alpha/OPA pair; colors and RGB565 background also vary per pixel.
        for (int opacity = 0; opacity < 256; opacity++) begin
            config_frame(1, 0, 1, 0, 0, 1280, 720, opacity);
            boundary();
            for (int column = 0; column < 256; column++) begin
                @(negedge clk);
                de = 1; x = 11'(column); y = 0;
                valid0 = 1; valid1 = 1;
                data0 = packet0((column/16)*16, opacity);
                data1 = packet1((column/8)*8, (column/8)*8);
                foreground = {8'(column), 8'(column*37), 8'(255-column*17), 8'(column*71)};
                background = expand(pixel0(column,opacity));
                sample(blend(background,foreground,opacity), column%16 == 0, column%8 == 0);
            end
        end
        // Eight-pixel rectangle ending at the screen edge, one row at y=719.
        config_frame(0, 0, 1, 1272, 719, 8, 1, 255);
        boundary();
        for (int row = 0; row < 2; row++) begin
            for (int column = 0; column < 1280; column++) begin
                @(negedge clk);
                de = 1; x = 11'(column); y = row == 0 ? 10'd0 : 10'd719;
                valid0 = 1; valid1 = 1;
                for (int n = 0; n < 8; n++)
                    data1[n*32 +: 32] = {8'hff, 24'(n*57373)};
                expected_packet = data1;
                sample(row == 1 && column >= 1272 ?
                       expected_packet[(column-1272)*32 +: 24] : 24'd0,
                       0, row == 1 && column == 1272);
            end
            idle();
        end
        drain();
        if (perf0 != 1 || perf1 != 0)
            $fatal(1, "FAIL good scan statistics");
        // L1 rectangle begins at x=8: L0 misses a beat, L1 remains visible.
        config_frame(1, 3, 1, 8, 0, 16, 1, 255);
        boundary();
        for (int column = 0; column < 32; column++) begin
            @(negedge clk);
            de = 1; x = 11'(column); y = 0;
            valid0 = column >= 1;
            valid1 = 1;
            data0 = packet0(((column+3)/16)*16,0);
            data1 = {8{32'hff804020}};
            background = column < 13 ? 24'd0 : expand(pixel0(column+3,0));
            sample(column >= 8 && column < 24 ? 24'h804020 : background,
                   column == 1 || column == 13 || column == 29,
                   column == 8 || column == 16, column == 0, 0);
        end
        drain();
        if (perf1 != 1) $fatal(1, "FAIL independent L0 debt");
        // L1 misses at x=8 and x=16; a late beat at x=16 repays while missing again.
        config_frame(1, 0, 1, 8, 0, 24, 1, 255);
        boundary();
        for (int column = 0; column < 32; column++) begin
            @(negedge clk);
            de = 1; x = 11'(column); y = 0;
            valid0 = 1;
            valid1 = column == 16 || column == 17 || column >= 24;
            data0 = packet0((column/16)*16,0);
            data1 = {8{32'hff204080}};
            sample(column >= 24 ? 24'h204080 : expand(pixel0(column,0)),
                   column%16 == 0, column == 16 || column == 17 || column == 24,
                   0, column == 8);
        end
        drain();
        // Both layers miss, retain debts across frames and repay while not scanning.
        boundary();
        @(negedge clk);
        de = 1; x = 0; y = 0; valid0 = 0; valid1 = 0;
        sample(0,0,0,1,0);
        for (int column = 1; column <= 8; column++) begin
            @(negedge clk);
            x = 11'(column);
            sample(0,0,0,0,column == 8);
        end
        boundary(0);
        @(negedge clk);
        de = 1; x = 0; valid0 = 1; valid1 = 1;
        sample(0,1,1);
        @(negedge clk);
        sample(0,0,0);
        drain();
        if (perf1 != 2)
            $fatal(1, "FAIL cross-frame disabled debt counts");
        // A requested frame with both layers disabled is black and consumes nothing.
        config_frame(0, 0, 0, 0, 0, 1280, 720, 255);
        boundary();
        for (int column = 0; column < 32; column++) begin
            @(negedge clk);
            de = 1; x = 11'(column); y = 0; valid0 = 1; valid1 = 1;
            sample(0,0,0);
        end
        @(negedge clk);
        x = 1279; y = 719;
        sample(0,0,0);
        drain();
        if (perf0 != 2 || perf1 != 2)
            $fatal(1, "FAIL both-disabled frame accounting");
        // Repeat a parameter transfer with the memory clock slower than pixel clock.
        mem_half = 11; pix_half = 3;
        config_frame(0, 0, 1, 0, 0, 8, 1, 255);
        boundary();
        @(negedge clk);
        de = 1; x = 0; y = 0; valid0 = 0; valid1 = 1;
        data1 = {8{32'hffabcdef}};
        sample(24'habcdef,0,1);
        drain();
        $display("PASS layers: scroll, 65536 alpha/OPA pairs, rectangle, debt, parameter CDC");
        $finish;
    end
endmodule
