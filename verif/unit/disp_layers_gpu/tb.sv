// File: tb.sv
// Spec: disp-spec 2.4, 2.7, 4.3, 6.
// Description: L0 scroll offsets, frame-latched CDC parameters and X2 pixels.
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
    reg [5:0] params_src = 0;
    wire params_ready;
    wire params_valid;
    wire [5:0] params;
    reg valid0 = 0;
    wire ready0;
    reg [255:0] data0 = 0;
    wire [23:0] rgb;
    wire frame_req;
    wire error0;
    wire [9:0] read0;
    wire [31:0] perf0;
    wire [31:0] perf1;
    int pops0 = 0;
    int receipts = 0;
    // disp-spec 2.7 specifies pixel correspondence, without a fixed output latency.
    // FIFO schedules follow the three raster/rectangle stages; RGB follows eleven stages.
    localparam SCAN_STAGES = 11;
    reg [SCAN_STAGES-1:0] expect_valid = 0;
    reg [23:0] expect_rgb [0:SCAN_STAGES-1];
    reg [3:0] expect_pop0 = 0;
    reg [3:0] expect_error0 = 0;
    reg source_valid = 0;
    reg [23:0] source_rgb = 0;
    reg source_pop0 = 0;
    reg source_error0 = 0;
    reg valid0_pipe0 = 0;
    reg valid0_pipe1 = 0;
    reg valid0_pipe2 = 0;
    reg [255:0] data0_pipe0 = 0;
    reg [255:0] data0_pipe1 = 0;
    reg [255:0] data0_pipe2 = 0;
    always @(negedge clk) source_valid = 0;
    always @(posedge clk) begin
        valid0_pipe0 <= valid0;
        valid0_pipe1 <= valid0_pipe0;
        valid0_pipe2 <= valid0_pipe1;



        data0_pipe0 <= data0;
        data0_pipe1 <= data0_pipe0;
        data0_pipe2 <= data0_pipe1;



    end
    always @(posedge clk) begin : pipeline_scoreboard
        bit actual_pop;
        bit actual_error;
        actual_pop = valid0_pipe2 && ready0;
        actual_error = error0;
        if (!rst_n) begin
            expect_valid = 0;
        end else begin
            for (int stage = SCAN_STAGES-1; stage > 0; stage--)
                expect_rgb[stage] = expect_rgb[stage-1];
            expect_rgb[0] = source_rgb;
            expect_valid = {expect_valid[SCAN_STAGES-2:0], source_valid};
            expect_pop0 = {expect_pop0[2:0], source_pop0};
            expect_error0 = {expect_error0[2:0], source_error0};
            if (expect_valid[3]) begin
                if (actual_pop !== expect_pop0[3] || actual_error !== expect_error0[3])
                    $fatal(1,"FAIL L0 pop/error got=%b/%b expected=%b/%b time=%0t",
                        actual_pop,actual_error,expect_pop0[3],expect_error0[3],$time);
                pops0 += int'(expect_pop0[3]);
            end
            #2;
            if (expect_valid[SCAN_STAGES-1] && rgb !== expect_rgb[SCAN_STAGES-1])
                $fatal(1,"FAIL RGB got=%h expected=%h time=%0t",
                    rgb,expect_rgb[SCAN_STAGES-1],$time);
            if (expect_valid[3] && read0 !== 10'(pops0))
                $fatal(1,"FAIL L0 read count got=%0d expected=%0d",read0,pops0);
        end
    end
    task automatic drain;
        @(negedge clk);
        de = 0;
        valid0 = 0;

        repeat (SCAN_STAGES+1) @(negedge clk);
    endtask
    edrv32_cdc_handshake #(.WIDTH(6)) u_params (
        .clk_src_i(clk_mem), .rst_src_n_i(rst_n), .clk_dst_i(clk), .rst_dst_n_i(rst_n),
        .valid_i(params_send), .ready_o(params_ready), .data_i(params_src),
        .valid_o(params_valid), .ready_i(1'b1), .data_o(params)
    );
    edrv32_disp_scan_gpu dut (
        .clk_i(clk), .rst_n_i(rst_n), .enable_i(enable), .de_i(de), .x_i(x), .y_i(y),
        .frame_start_i(de && x == 0 && y == 0),
        .vblank_i(vblank), .params_valid_i(params_valid), .params_i(params),
        .fifo_valid_i(valid0_pipe2), .fifo_ready_o(ready0), .fifo_data_i(data0_pipe2),
        .rgb_o(rgb),
        .frame_req_o(frame_req), .underflow_o(error0), .read_cnt_o(read0), .perf0_o(perf0), .perf1_o(perf1)
    );
    always @(posedge clk) if (rst_n && params_valid) receipts++;
    function automatic [15:0] pixel0(input int index, input int row);
        return 16'(index*173+row*379+2051);
    endfunction
    function automatic [255:0] packet0(input int index, input int row);
        for (int n = 0; n < 16; n++) packet0[n*16 +: 16] = pixel0(index+n, row);
    endfunction
    function automatic [23:0] expand(input [15:0] pixel);
        return {pixel[15:11], pixel[15:13], pixel[10:5], pixel[10:9],
                pixel[4:0], pixel[4:2]};
    endfunction
    task automatic sample(input [23:0] expected, input bit pop0, input bit err0 = 0);
        #1;
        source_valid = 1;
        source_rgb = expected;
        source_pop0 = pop0;

        source_error0 = err0;

        @(posedge clk);
        #3;
    endtask
    task automatic idle;
        @(negedge clk);
        de = 0;
        valid0 = 0;

    endtask
    task automatic config_frame(input bit en0, input int offset, input bit x2 = 0);
        int before_receipts;
        reg [5:0] sent_params;
        idle();
        before_receipts = receipts;
        sent_params = {x2, en0, 4'(offset)};
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
        repeat (5) @(negedge clk);
        rst_n = 1;
        // Every p reads exactly ceil((p+1280)/16) beats, including discarded row tail.
        for (int offset = 0; offset < 16; offset++) begin
            config_frame(1, offset);
            boundary();
            for (int row = 0; row < 2; row++) begin
                row_pops = pops0;
                for (int column = 0; column < 1280; column++) begin
                    @(negedge clk);
                    de = 1; x = 11'(column); y = 10'(row);
                    valid0 = 1;
                    data0 = packet0(((column+offset)/16)*16, row);
                    sample(expand(pixel0(column+offset,row)),
                           column == 0 || (column+offset)%16 == 0);
                end
                drain();
                if (pops0-row_pops != (offset == 0 ? 80 : 81))
                    $fatal(1, "FAIL scroll beat count p=%0d",offset);
                // Receipt in the middle of a frame must leave the second row unchanged.
                if (row == 0) config_frame(0, 0);
                idle();
            end
        end
        // X2 configuration arrives through the handshake and latches at frame start.
        config_frame(1, 0, 1);
        boundary();
        for (int row = 0; row < 2; row++) begin
            row_pops = pops0;
            for (int column = 0; column < 1280; column++) begin
                @(negedge clk);
                de = 1; x = 11'(column); y = 10'(row);
                valid0 = 1;
                data0 = packet0((column/32)*16, row/2);
                sample(expand(pixel0(column/2,row/2)), column%32 == 0);
            end
            drain();
            if (pops0-row_pops != 40) $fatal(1,"FAIL X2 beat count");
            if (row == 0) config_frame(0, 0, 0);
        end
        $display("PASS L0 all scroll offsets, frame-latched config and X2 pixels");
        $finish;
    end
endmodule
