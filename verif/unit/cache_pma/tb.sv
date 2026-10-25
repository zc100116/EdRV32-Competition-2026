// File: cache_pma/tb.sv
// Spec: cache-spec; cache-testplan 2.2.
// Description: Self-checking directed cache unit tests.
// Clock domain: clk_sys (PMA is combinational).
module tb;
    logic [31:0] addr;
    logic execute;
    logic store;
    wire cacheable;
    wire device_access;
    wire err;
    edrv32_cache_pma dut (
        .addr_i(addr),
        .execute_i(execute),
        .store_i(store),
        .cacheable_o(cacheable),
        .device_o(device_access),
        .err_o(err)
    );
    task automatic check(input logic [31:0] a, input logic [2:0] i,
                         input logic [2:0] l, input logic [2:0] s);
        addr = a; execute = 1; store = 0; #1;
        if ({cacheable, device_access, err} !== i) $fatal(1, "FAIL I PMA %h", a);
        execute = 0; #1;
        if ({cacheable, device_access, err} !== l) $fatal(1, "FAIL load PMA %h", a);
        store = 1; #1;
        if ({cacheable, device_access, err} !== s) $fatal(1, "FAIL store PMA %h", a);
    endtask
    initial begin
        check(32'h00000000, 3'b000, 3'b010, 3'b001);
        check(32'h00003fff, 3'b000, 3'b010, 3'b001);
        check(32'h00004000, 3'b001, 3'b001, 3'b001);
        check(32'h10000000, 3'b100, 3'b100, 3'b100);
        check(32'h1003ffff, 3'b100, 3'b100, 3'b100);
        check(32'h10040000, 3'b001, 3'b001, 3'b001);
        check(32'h20000000, 3'b001, 3'b010, 3'b010);
        check(32'h2000ffff, 3'b001, 3'b010, 3'b010);
        check(32'h20010000, 3'b001, 3'b001, 3'b001);
        check(32'h30000000, 3'b001, 3'b010, 3'b010);
        check(32'h303fffff, 3'b001, 3'b010, 3'b010);
        check(32'h30400000, 3'b001, 3'b001, 3'b001);
        check(32'h40000000, 3'b001, 3'b010, 3'b010);
        check(32'h4000ffff, 3'b001, 3'b010, 3'b010);
        check(32'h40010000, 3'b001, 3'b001, 3'b001);
        check(32'h41000000, 3'b001, 3'b010, 3'b010);
        check(32'h4100ffff, 3'b001, 3'b010, 3'b010);
        check(32'h41010000, 3'b001, 3'b001, 3'b001);
        check(32'h80000000, 3'b100, 3'b100, 3'b100);
        check(32'hbfffffff, 3'b100, 3'b100, 3'b100);
        check(32'hc0000000, 3'b001, 3'b010, 3'b010);
        check(32'hc0000000, 3'b001, 3'b010, 3'b010);
        check(32'hffffffff, 3'b001, 3'b010, 3'b010);
        $display("PASS cache_pma"); $finish;
    end
endmodule
