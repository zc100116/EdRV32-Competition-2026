// File: cache_ram/tb.sv
// Spec: cache-spec; cache-testplan 2.2.
// Description: Self-checking directed cache unit tests.
// Clock domain: clk_sys (PMA is combinational).
module tb;
    logic clk = 0;
    always #5 clk = ~clk;
    logic wr = 0;
    logic rd = 0;
    logic [8:0] addr = 0;
    logic [63:0] data = 0;
    logic [7:0] mask = 8'hff;
    wire [19:0] it;
    wire [19:0] dt;
    wire [63:0] id;
    wire [63:0] dd;
    edrv32_ram_icache_tag u_it (
        .clk_i(clk),
        .wr_en_i(wr),
        .wr_addr_i(addr[6:0]),
        .wr_data_i(data[19:0]),
        .rd_en_i(rd),
        .rd_addr_i(addr[6:0]),
        .rd_data_o(it)
    );
    edrv32_ram_dcache_tag u_dt (
        .clk_i(clk),
        .wr_en_i(wr),
        .wr_addr_i(addr[6:0]),
        .wr_data_i(data[19:0]),
        .rd_en_i(rd),
        .rd_addr_i(addr[6:0]),
        .rd_data_o(dt)
    );
    edrv32_ram_icache_data u_id (
        .clk_i(clk),
        .wr_en_i(wr),
        .wr_addr_i(addr),
        .wr_data_i(data),
        .rd_en_i(rd),
        .rd_addr_i(addr),
        .rd_data_o(id)
    );
    edrv32_ram_dcache_data u_dd (
        .clk_i(clk),
        .wr_en_i(wr),
        .wr_addr_i(addr),
        .wr_data_i(data),
        .wr_byte_en_i(mask),
        .rd_en_i(rd),
        .rd_addr_i(addr),
        .rd_data_o(dd)
    );
    task automatic tick;
        @(posedge clk); #1;
    endtask
    task automatic step;
        @(negedge clk); #1;
    endtask
    initial begin
        step(); wr = 1; addr = 9'd127; data = 64'h123456789abcdef0;
        tick(); step(); wr = 0; rd = 1;
        tick();
        if ({it, dt, id, dd} !== {20'hcdef0, 20'hcdef0,
            64'h123456789abcdef0, 64'h123456789abcdef0}) $fatal(1, "FAIL RAM read");
        step(); wr = 1; data = 64'hfedcba9876543210; mask = 8'h05;
        tick();
        if (dd !== 64'h123456789abcdef0 || id !== 64'h123456789abcdef0 ||
            it !== 20'hcdef0 || dt !== 20'hcdef0) $fatal(1, "FAIL old-data collision");
        step(); wr = 0;
        tick();
        if (dd !== 64'h123456789a54de10 || id !== 64'hfedcba9876543210 ||
            it !== 20'h43210 || dt !== 20'h43210) $fatal(1, "FAIL byte enable");
        step(); rd = 0; addr = 0;
        tick(); tick();
        if (dd !== 64'h123456789a54de10 || id !== 64'hfedcba9876543210 ||
            it !== 20'h43210 || dt !== 20'h43210) $fatal(1, "FAIL read hold");
        $display("PASS cache_ram"); $finish;
    end
endmodule
