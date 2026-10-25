// edrv32_cache_ic_08_tb.sv
// cache-testplan 3; test selector 108. Clock domain: clk_sys.
module edrv32_cache_ic_08_tb #(parameter int SEEDS = 50);
    edrv32_cache_env #(
        .SEEDS(SEEDS),
        .TEST(108)
    ) u_env ();
endmodule
