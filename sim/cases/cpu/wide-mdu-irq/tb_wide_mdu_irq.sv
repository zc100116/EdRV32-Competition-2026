module tb_wide_mdu_irq;
    tb_core_mdu_raw_irq #(.DUAL_ISSUE(1),.FETCH_WIDE(1)) u_test();
endmodule
