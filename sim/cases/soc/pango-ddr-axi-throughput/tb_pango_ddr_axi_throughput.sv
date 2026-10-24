`timescale 1ns/1ps

module tb_pango_ddr_axi_throughput;

    tb_pango_ddr_axi_adapter #(
        .MODEL_RANDOM_STALL(0)
    ) u_test ();

endmodule
