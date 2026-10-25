module tb_wide_cache;
    tb_cache_blocking #(.FETCH_WIDE(1)) u_test();
endmodule
