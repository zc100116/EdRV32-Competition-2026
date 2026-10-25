// edrv32_cache_dc_15_tb.sv
// cache-testplan 3; test selector 215. Clock domain: clk_sys.
module edrv32_cache_dc_15_tb #(parameter int SEEDS = 50);
    edrv32_cache_env #(
        .SEEDS(SEEDS),
        .TEST(215)
    ) u_env ();
endmodule
