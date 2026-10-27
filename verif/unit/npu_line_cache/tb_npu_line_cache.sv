// File: tb_npu_line_cache.sv
// Spec: npu-spec 5.2; datapath design 4.4, 4.5; CP-02.
// Description: Sweep both banks and capacity edges, independent read enables and overlap.
// Clock: clk_npu.
module tb_npu_line_cache;
    reg clk = 0;
    always #5 clk <= ~clk;
    reg wr_valid = 0;
    reg wr_bank = 0;
    reg [9:0] wr_addr = 0;
    reg [255:0] wr_data = 0;
    reg [1:0] rd_en = 0;
    reg [9:0] rd_addr0 = 0;
    reg [9:0] rd_addr1 = 0;
    wire [255:0] rd_data0;
    wire [255:0] rd_data1;
    reg [255:0] memory [0:1][0:1023];
    reg [255:0] array_data [0:1];
    reg [255:0] expected_data [0:1];
    bit [1:0] array_valid = 0;
    bit [1:0] output_valid = 0;
    integer checks = 0;
    integer cycle = 0;

    edrv32_npu_line_cache dut (
        .clk_i(clk),
        .cache_wr_valid_i(wr_valid),
        .cache_wr_bank_i(wr_bank),
        .cache_wr_addr_i(wr_addr),
        .cache_wr_data_i(wr_data),
        .cache_rd_en_i(rd_en),
        .cache_rd_addr0_i(rd_addr0),
        .cache_rd_addr1_i(rd_addr1),
        .cache_rd_data0_o(rd_data0),
        .cache_rd_data1_o(rd_data1)
    );

    function automatic [255:0] pattern(input integer b, input integer a);
        for (integer j = 0; j < 8; j++) pattern[32*j+:32] = 32'(b*65536+a*17+j);
    endfunction

    initial forever begin
        @(posedge clk);
        cycle++;
        for (integer b = 0; b < 2; b++) begin
            output_valid[b] = array_valid[b];
            expected_data[b] = array_data[b];
            if (rd_en[b]) begin
                array_data[b] = memory[b][b == 0 ? rd_addr0 : rd_addr1];
                array_valid[b] = 1;
            end
        end
        // Read first: a same-address write is only visible to later requests.
        if (wr_valid) memory[wr_bank][wr_addr] = wr_data;
        #1;
        if (output_valid[0]) begin
            if (rd_data0 !== expected_data[0])
                $fatal(1, "FAIL bank0 cycle=%0d expected=%h got=%h", cycle,
                    expected_data[0], rd_data0);
            checks++;
        end
        if (output_valid[1]) begin
            if (rd_data1 !== expected_data[1])
                $fatal(1, "FAIL bank1 cycle=%0d expected=%h got=%h", cycle,
                    expected_data[1], rd_data1);
            checks++;
        end
    end

    initial begin
        // Cover every location, including five slots of 204 and two slots of 512.
        for (integer a = 0; a < 1024; a++) begin
            for (integer b = 0; b < 2; b++) begin
                @(negedge clk);
                wr_valid = 1;
                wr_bank = 1'(b);
                wr_addr = 10'(a);
                wr_data = pattern(b, a);
            end
        end
        @(negedge clk);
        wr_valid = 0;
        for (integer a = 0; a < 1024; a++) begin
            rd_en = 3;
            rd_addr0 = 10'(a);
            rd_addr1 = 10'(1023-a);
            @(negedge clk);
        end
        for (integer a = 0; a < 200; a++) begin
            rd_en = 2'(a % 4);
            rd_addr0 = 10'(a*7 % 1024);
            rd_addr1 = 10'(a*13 % 1024);
            wr_valid = 1;
            wr_bank = 1'(a % 2);
            wr_addr = 10'(a*3);
            wr_data = pattern(5, a);
            @(negedge clk);
        end
        wr_valid = 0;
        rd_en = 0;
        repeat (4) @(negedge clk);
        $display("PASS line_cache: %0d data checks, 2-stage read and held outputs", checks);
        $finish;
    end
endmodule
