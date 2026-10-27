// File: tb_npu_descriptor.sv
// Spec: npu-spec 3-6; edrv32-soc-spec 4.2, 7.1.
// Description: Self-checking isolated descriptor protocol and architectural tests.
// Clock: clk_npu.
`timescale 1ns/1ps
module tb_npu_descriptor;
    logic  clk_i = 0;
    logic  rst_n_i = 0;
    logic  cancel_i = 0;
    logic  data_valid_i = 0;
    logic  data_index_i = 0;
    logic [255:0] data_i = 0;
    logic  decode_i = 0;
    logic [127:0] bases_i = 0;
    wire [511:0] desc_o;
    wire [31:0] in_addr_o;
    wire [31:0] out_addr_o;
    wire [31:0] residual_addr_o;
    wire [31:0] weight_addr_o;
    wire [31:0] quant_addr_o;
    wire  done_o;
    wire [2:0] error_o;
    always #5 clk_i = !clk_i;
    edrv32_npu_descriptor u_dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .cancel_i(cancel_i),
        .data_valid_i(data_valid_i),
        .data_index_i(data_index_i),
        .data_i(data_i),
        .decode_i(decode_i),
        .bases_i(bases_i),
        .desc_o(desc_o),
        .in_addr_o(in_addr_o),
        .out_addr_o(out_addr_o),
        .residual_addr_o(residual_addr_o),
        .weight_addr_o(weight_addr_o),
        .quant_addr_o(quant_addr_o),
        .done_o(done_o),
        .error_o(error_o)
    );
    task automatic tick;
        @(posedge clk_i);
        @(negedge clk_i);
        #1;
    endtask
    task automatic check(input bit condition, input string label);
        if (!condition) $fatal(1, "FAIL %s time=%0t", label, $time);
    endtask
    initial begin
        #2000000;
        $fatal(1, "FAIL timeout");
    end
    logic [511:0] descriptor = 0;
    task automatic decode_check(input logic [2:0] code);
        data_valid_i = 1;
        data_index_i = 0;
        data_i = descriptor[255:0];
        tick;
        data_index_i = 1;
        data_i = descriptor[511:256];
        tick;
        data_valid_i = 0;
        decode_i = 1;
        tick;
        decode_i = 0;
        check(!done_o, "registered capacity stage");
        tick;
        check(done_o && error_o == code, "decode outcome");
        check(desc_o == descriptor, "two-beat capture");
        check(in_addr_o == 32'h3020 && out_addr_o == 32'h4040
            && residual_addr_o == 32'h2060, "selected feature bases");
        check(weight_addr_o == 32'h1080 && quant_addr_o == 32'h10a0, "model bases");
        tick;
        check(!done_o, "single completion pulse");
    endtask
    initial begin
        tick;
        rst_n_i = 1;
        bases_i = 128'h00004000000030000000200000001000;
        descriptor[31:0] = (2 << 12) | (3 << 14) | (1 << 16) | 16;
        descriptor[63:32] = 32'h20;
        descriptor[127:96] = 32'h40;
        descriptor[191:160] = 32'h60;
        descriptor[223:192] = 32'h80;
        descriptor[255:224] = 32'ha0;
        descriptor[331:328] = 8;
        descriptor[362:352] = 204;
        descriptor[403:384] = 36864;
        decode_check(0);
        descriptor[362:352] = 205;
        decode_check(4);
        descriptor[4] = 0;
        descriptor[362:352] = 512;
        decode_check(0);
        descriptor[362:352] = 513;
        decode_check(4);
        descriptor[362:352] = 1;
        descriptor[331:328] = 9;
        decode_check(4);
        descriptor[331:328] = 8;
        descriptor[403:384] = 36865;
        decode_check(4);
        descriptor[403:384] = 36864;
        descriptor[3:0] = 3;
        decode_check(3);
        descriptor[3:0] = 15;
        decode_check(3);
        descriptor[3:0] = 1;
        // Non-CONV fields have no CONV capacity meaning.
        descriptor[362:352] = 2047;
        descriptor[331:328] = 15;
        descriptor[403:384] = 1048575;
        decode_check(0);
        cancel_i = 1;
        tick;
        check(!done_o && error_o == 0, "cancel controls");
        $display("PASS descriptor fields, addresses and exactly three capacity checks");
        $finish;
    end
endmodule
