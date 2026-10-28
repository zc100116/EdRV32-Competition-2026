// edrv32_cache_mt_07_tb.sv
// cache-testplan v0.2 MT-07; cache-spec v0.6 5.4. Clock domain: clk_sys.
// Accept cached requests during maintenance; defer their arrays and response.
// Verify address-independent ready and live device STATUS polling.
module edrv32_cache_mt_07_tb;
    edrv32_cache_env #(
        .TEST(307)
    ) u_env ();
endmodule
