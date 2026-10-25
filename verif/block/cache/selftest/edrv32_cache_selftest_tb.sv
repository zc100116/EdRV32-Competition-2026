// edrv32_cache_selftest_tb.sv
// cache-testplan 3; test selector 0. Clock domain: clk_sys.
module edrv32_cache_selftest_tb;
    edrv32_cache_env #(
        .TEST(0)
    ) u_env ();
endmodule
