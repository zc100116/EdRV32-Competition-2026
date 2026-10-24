`timescale 1ns/1ps

module tb_cache_array_equivalence;
    reg clk;
    reg rst_n;
    reg rd_en;
    reg [6:0] rd_index;
    reg tag_wr_en;
    reg [6:0] tag_wr_index;
    reg [20:0] tag_wr_data;
    reg data_wr_en;
    reg [6:0] data_wr_index;
    reg [127:0] data_wr_line;
    reg [15:0] data_wr_byte_en;
    wire [20:0] dut_tag;
    wire [127:0] dut_line;
    reg [20:0] expected_tag [0:127];
    reg [127:0] expected_line [0:127];
    reg [20:0] held_tag;
    reg [127:0] held_line;
    integer checks;
    integer index;
    integer byte_index;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    edrv32_cache_array u_dut (
        .clk_i(clk), .rst_n_i(rst_n),
        .rd_en_i(rd_en), .rd_index_i(rd_index),
        .rd_tag_o(dut_tag), .rd_line_o(dut_line),
        .tag_wr_en_i(tag_wr_en), .tag_wr_index_i(tag_wr_index),
        .tag_wr_data_i(tag_wr_data), .data_wr_en_i(data_wr_en),
        .data_wr_index_i(data_wr_index), .data_wr_line_i(data_wr_line),
        .data_wr_byte_en_i(data_wr_byte_en)
    );

    task automatic check_equal;
        input [20:0] expected_tag_i;
        input [127:0] expected_line_i;
        input [8*96-1:0] message;
        begin
            checks = checks + 1;
            if ((dut_tag !== expected_tag_i) ||
                (dut_line !== expected_line_i)) begin
                $display("FAIL: %0s", message);
                $display(" dut      tag=%x line=%x", dut_tag, dut_line);
                $display(" expected tag=%x line=%x", expected_tag_i, expected_line_i);
                $fatal(1);
            end
        end
    endtask

    initial begin
        checks = 0;
        rst_n = 1'b0;
        rd_en = 1'b0;
        rd_index = 7'd0;
        tag_wr_en = 1'b0;
        tag_wr_index = 7'd0;
        tag_wr_data = 21'd0;
        data_wr_en = 1'b0;
        data_wr_index = 7'd0;
        data_wr_line = 128'd0;
        data_wr_byte_en = 16'd0;
        repeat (2) @(posedge clk);
        rst_n = 1'b1;

        // Initialize all storage explicitly; neither synthesizable backend
        // resets tag/data contents.
        for (index = 0; index < 128; index = index + 1) begin
            @(negedge clk);
            tag_wr_en = 1'b1;
            tag_wr_index = index[6:0];
            tag_wr_data = 21'h10000 ^ index;
            data_wr_en = 1'b1;
            data_wr_index = index[6:0];
            data_wr_line = {4{32'h5a00_0000 ^ index}};
            data_wr_byte_en = 16'hffff;
            expected_tag[index] = 21'h10000 ^ index;
            expected_line[index] = {4{32'h5a00_0000 ^ index}};
            @(posedge clk);
        end
        @(negedge clk);
        tag_wr_en = 1'b0;
        data_wr_en = 1'b0;

        for (index = 0; index < 128; index = index + 1) begin
            rd_en = 1'b1;
            rd_index = index[6:0];
            @(posedge clk); #1;
            check_equal(expected_tag[index], expected_line[index],
                        "full array synchronous read equivalence");
            @(negedge clk);
        end

        // Byte-write coverage, including independent tag and data addresses.
        for (index = 0; index < 64; index = index + 1) begin
            rd_en = 1'b0;
            tag_wr_en = 1'b1;
            tag_wr_index = (index * 3) & 7'h7f;
            tag_wr_data = $random;
            data_wr_en = 1'b1;
            data_wr_index = (index * 5) & 7'h7f;
            data_wr_line = {$random, $random, $random, $random};
            data_wr_byte_en = $random;
            expected_tag[tag_wr_index] = tag_wr_data;
            for (byte_index = 0; byte_index < 16; byte_index = byte_index + 1) begin
                if (data_wr_byte_en[byte_index])
                    expected_line[data_wr_index][byte_index*8 +: 8] =
                        data_wr_line[byte_index*8 +: 8];
            end
            @(posedge clk);
            @(negedge clk);
            tag_wr_en = 1'b0;
            data_wr_en = 1'b0;
            rd_en = 1'b1;
            rd_index = data_wr_index;
            @(posedge clk); #1;
            check_equal(expected_tag[data_wr_index], expected_line[data_wr_index],
                        "byte-enable update equivalence");
            @(negedge clk);
        end

        // The public wrapper promises output hold while rd_en is low.
        held_tag = dut_tag;
        held_line = dut_line;
        rd_en = 1'b0;
        rd_index = ~rd_index;
        repeat (4) begin
            @(posedge clk); #1;
            check_equal(held_tag, held_line, "read output holds while disabled");
        end

        // Same-address read/write is read-first in both implementations.
        @(negedge clk);
        rd_en = 1'b1;
        rd_index = 7'd17;
        tag_wr_en = 1'b1;
        tag_wr_index = 7'd17;
        tag_wr_data = 21'h1abcde;
        data_wr_en = 1'b1;
        data_wr_index = 7'd17;
        data_wr_line = 128'hffeeddccbbaa99887766554433221100;
        data_wr_byte_en = 16'hffff;
        @(posedge clk); #1;
        check_equal(expected_tag[17], expected_line[17],
                    "same-address collision is read-first");
        expected_tag[17] = tag_wr_data;
        expected_line[17] = data_wr_line;
        @(negedge clk);
        tag_wr_en = 1'b0;
        data_wr_en = 1'b0;
        @(posedge clk); #1;
        check_equal(expected_tag[17], expected_line[17],
                    "collision write is visible on next synchronous read");

`ifdef FPGA_MODE
        $display("PASS: FPGA_MODE cache-array contract (%0d checks)", checks);
`else
        $display("PASS: SIM_MODE cache-array contract (%0d checks)", checks);
`endif
        $finish;
    end
endmodule
