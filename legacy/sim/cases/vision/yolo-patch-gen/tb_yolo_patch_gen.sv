`timescale 1ns/1ps

module tb_yolo_patch_gen;
    reg clk_i = 1'b0;
    always #5 clk_i = !clk_i;
    reg rst_n_i = 1'b0;
    reg wr_valid_i = 1'b0;
    reg wr_bank_i = 1'b0;
    reg [9:0] wr_addr_i = 10'd0;
    reg [255:0] wr_data_i = 256'd0;
    wire cache_rd_valid_w;
    wire cache_rd_ready_w;
    wire patch_cache_ready_w;
    wire cache_request_allow_w;
    wire cache_rd_bank0_w;
    wire [9:0] cache_rd_addr0_w;
    wire cache_rd_bank1_w;
    wire [9:0] cache_rd_addr1_w;
    wire cache_result_valid_w;
    wire [255:0] cache_rd_data0_w;
    wire [255:0] cache_rd_data1_w;
    reg start_i = 1'b0;
    wire start_ready_o;
    reg kernel3_i = 1'b0;
    reg stride2_i = 1'b0;
    reg [10:0] input_width_i = 11'd8;
    reg [4:0] cin_blocks_i = 5'd2;
    reg [8:0] block_bank_stride_i = 9'd2;
    reg [9:0] pair_x_base_i = 10'd0;
    reg [9:0] pair_count_i = 10'd2;
    reg [10:0] activation_base_i = 11'd0;
    reg [9:0] row_base0_i = 10'd0;
    reg [9:0] row_base1_i = 10'd4;
    reg [9:0] row_base2_i = 10'd8;
    reg [2:0] row_valid_i = 3'b001;
    wire activation_valid_o;
    wire [10:0] activation_addr_o;
    wire [127:0] activation_data_o;
    wire busy_o;
    wire done_o;
    integer case_mode_r = -1;
    integer received_r = 0;
    integer cycle_r = 0;
    integer last_output_cycle_r = -1;
    integer y;
    integer cb;
    integer xp;
    integer pixel;
    integer ch;
    integer value;
    integer expected;
    integer rows_per_pair;
    integer q;
    integer krow;
    integer ky;
    integer kx;
    integer block;
    integer half;
    integer src_y;
    integer src_x;

    edrv32_yolo_line_cache u_cache (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .wr_valid_i(wr_valid_i), .wr_bank_i(wr_bank_i),
        .wr_addr_i(wr_addr_i), .wr_data_i(wr_data_i),
        .rd_valid_i(cache_rd_valid_w && cache_request_allow_w),
        .rd_ready_o(cache_rd_ready_w),
        .rd_bank0_i(cache_rd_bank0_w), .rd_addr0_i(cache_rd_addr0_w),
        .rd_bank1_i(cache_rd_bank1_w), .rd_addr1_i(cache_rd_addr1_w),
        .rd_valid_o(cache_result_valid_w),
        .rd_data0_o(cache_rd_data0_w), .rd_data1_o(cache_rd_data1_w)
    );

    edrv32_yolo_patch_gen u_patch (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .start_i(start_i), .start_ready_o(start_ready_o),
        .kernel3_i(kernel3_i), .stride2_i(stride2_i),
        .input_width_i(input_width_i), .cin_blocks_i(cin_blocks_i),
        .block_bank_stride_i(block_bank_stride_i),
        .pair_x_base_i(pair_x_base_i), .pair_count_i(pair_count_i),
        .activation_base_i(activation_base_i),
        .row_base0_i(row_base0_i), .row_base1_i(row_base1_i),
        .row_base2_i(row_base2_i), .row_valid_i(row_valid_i),
        .cache_rd_valid_o(cache_rd_valid_w),
        .cache_rd_ready_i(patch_cache_ready_w),
        .cache_rd_bank0_o(cache_rd_bank0_w),
        .cache_rd_addr0_o(cache_rd_addr0_w),
        .cache_rd_bank1_o(cache_rd_bank1_w),
        .cache_rd_addr1_o(cache_rd_addr1_w),
        .cache_rd_data0_i(cache_rd_data0_w),
        .cache_rd_data1_i(cache_rd_data1_w),
        .activation_valid_o(activation_valid_o),
        .activation_addr_o(activation_addr_o),
        .activation_data_o(activation_data_o),
        .busy_o(busy_o), .done_o(done_o)
    );

    assign cache_request_allow_w = case_mode_r != 3 ||
                                   cycle_r % 7 != 3;
    assign patch_cache_ready_w = cache_rd_ready_w &&
                                 cache_request_allow_w;

    function integer feature_value;
        input integer row;
        input integer column;
        input integer channel;
        begin
            if (row < 0 || row >= 3 || column < 0 || column >= 8)
                feature_value = 0;
            else
                feature_value = ((row*53 + column*17 + channel*7) % 255) - 127;
        end
    endfunction

    always @(posedge clk_i) begin
        if (rst_n_i && case_mode_r >= 0) begin
            cycle_r <= cycle_r + 1;
            if (activation_valid_o) begin
                if (case_mode_r != 3 && last_output_cycle_r >= 0 &&
                    cycle_r != last_output_cycle_r + 1)
                    $fatal(1, "Patch throughput gap at row %0d", received_r);
                last_output_cycle_r = cycle_r;
                if (!cache_result_valid_w)
                    $fatal(1, "Patch row without cache response");
                rows_per_pair = case_mode_r == 0 ? 4 : 36;
                q = received_r / rows_per_pair;
                krow = received_r % rows_per_pair;
                half = krow % 2;
                block = (krow / 2) % 2;
                if (case_mode_r == 0) begin
                    ky = 0;
                    kx = 0;
                end else begin
                    kx = (krow / 4) % 3;
                    ky = krow / 12;
                end
                if (activation_addr_o !== activation_base_i + received_r)
                    $fatal(1, "Wrong activation address row %0d", received_r);
                for (pixel = 0; pixel < 2; pixel = pixel + 1)
                    for (ch = 0; ch < 8; ch = ch + 1) begin
                        src_y = case_mode_r == 0 ? 0 : ky - 1;
                        src_x = (q*2+pixel)*(case_mode_r == 2 ? 2 : 1) +
                                (case_mode_r == 0 ? 0 : kx - 1);
                        expected = feature_value(src_y, src_x,
                                                 block*16+half*8+ch);
                        if ($signed(activation_data_o[(pixel*8+ch)*8 +: 8])
                            !== expected)
                            $fatal(1, "case=%0d row=%0d p=%0d ch=%0d expected=%0d actual=%0d",
                                   case_mode_r, received_r, pixel, ch,
                                   expected,
                                   $signed(activation_data_o[(pixel*8+ch)*8 +: 8]));
                    end
                received_r <= received_r + 1;
            end
        end
    end

    task run_case;
        input integer mode;
        integer target;
        begin
            @(negedge clk_i);
            case_mode_r = mode;
            received_r = 0;
            cycle_r = 0;
            last_output_cycle_r = -1;
            kernel3_i = mode != 0;
            stride2_i = mode == 2;
            activation_base_i = mode == 0 ? 11'd0 :
                                mode == 1 ? 11'd128 : 11'd512;
            row_valid_i = mode == 0 ? 3'b001 : 3'b110;
            row_base0_i = 10'd0;
            row_base1_i = 10'd0;
            row_base2_i = 10'd4;
            if (!start_ready_o)
                $fatal(1, "Patch generator not ready");
            start_i = 1'b1;
            @(negedge clk_i);
            start_i = 1'b0;
            target = mode == 0 ? 8 : 72;
            wait (done_o);
            #1;
            if (received_r != target ||
                cycle_r > (mode == 3 ? target+100 : target+5))
                $fatal(1, "case=%0d rows=%0d/%0d cycles=%0d",
                       mode, received_r, target, cycle_r);
            $display("PASS YOLO patch mode=%0d rows=%0d cycles=%0d",
                     mode, received_r, cycle_r);
            case_mode_r = -1;
        end
    endtask

    initial begin
        repeat (5) @(negedge clk_i);
        rst_n_i = 1'b1;
        for (y = 0; y < 3; y = y + 1)
            for (cb = 0; cb < 2; cb = cb + 1)
                for (xp = 0; xp < 4; xp = xp + 1) begin
                    @(negedge clk_i);
                    wr_valid_i = 1'b1;
                    wr_bank_i = xp % 2;
                    wr_addr_i = y*4 + cb*2 + xp/2;
                    for (pixel = 0; pixel < 2; pixel = pixel + 1)
                        for (ch = 0; ch < 16; ch = ch + 1) begin
                            value = feature_value(y, xp*2+pixel, cb*16+ch);
                            wr_data_i[(pixel*16+ch)*8 +: 8] = value[7:0];
                        end
                end
        @(negedge clk_i);
        wr_valid_i = 1'b0;
        run_case(0);
        run_case(1);
        run_case(2);
        run_case(3);
        $display("PASS YOLO C16 line cache and 1x1/3x3 patch generation");
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "Patch generator timeout");
    end
endmodule
