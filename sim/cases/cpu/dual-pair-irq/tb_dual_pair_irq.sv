module tb_dual_pair_irq;
    tb_core_irq_fencei #(.DUAL_ISSUE(1),.PAIR_IRQ(1)) u_test();
endmodule
