// File: sram_ip_check.sv
// Spec: sys-subsys-spec 2.2.
// Description: Check SRAM addresses, byte writes and disabled-port hold.
// Clock domain: clk_sys (test clock).
module sram_ip_check;
    GTP_GRS GRS_INST (.GRS_N(1'b1));
    reg clk = 0;
    always #5 clk = ~clk;
    reg en = 0;
    reg [7:0] mask = 0;
    reg [14:0] addr = 0;
    reg [63:0] data = 0;
    wire [63:0] q;
    integer checks = 0;
    bit test_passed = 0;
    edrv32_ram_sram dut (
        .clk_i(clk),
        .en_i(en),
        .wr_en_i(mask),
        .wr_data_i(data),
        .addr_i(addr),
        .rd_data_o(q)
    );
    task automatic access(
        input bit active,
        input [7:0] bytes,
        input [14:0] address,
        input [63:0] value
    );
        @(negedge clk);
        en = active; mask = bytes; addr = address; data = value;
        @(posedge clk); #1;
    endtask
    task automatic check(input [63:0] expected);
        if (q !== expected) begin
            $fatal(1, "FAIL SRAM expected=%h actual=%h time=%0t", expected, q, $time);
        end
        checks = checks + 1;
    endtask
    initial begin
        access(1, 8'hff, 15'd0, 64'h123456789abcdef0);
        access(1, 8'hff, 15'd32767, 64'hfedcba9876543210);
        access(1, 0, 0, 0); check(64'h123456789abcdef0);
        access(1, 0, 15'd32767, 0); check(64'hfedcba9876543210);
        access(1, 8'h05, 0, 64'hfedcba9876543210);
        access(1, 0, 0, 0); check(64'h123456789a54de10);
        access(0, 8'hff, 0, 0); check(64'h123456789a54de10);
        access(1, 0, 0, 0); check(64'h123456789a54de10);
        access(0, 0, 15'd32767, 0); check(64'h123456789a54de10);
        access(1, 0, 15'd32767, 0); check(64'hfedcba9876543210);
        test_passed = 1;
        $display("PASS SRAM checks=%0d", checks);
        $finish;
    end
endmodule
