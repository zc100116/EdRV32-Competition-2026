// File: port_check.sv
// Spec: task 20261025-01-cpu-sys-synth step 4.
// Description: Elaborate ROM, SRAM and multiplier wrappers against generated IP.
// Clock domain: clk_sys (test clock).
module port_check;
    GTP_GRS GRS_INST (.GRS_N(1'b1));
    edrv32_rom_boot u_rom (
        .clk_i(1'b0),
        .en_i(1'b0),
        .addr_i(11'b0),
        .rd_data_o()
    );
    edrv32_ram_sram u_sram (
        .clk_i(1'b0),
        .en_i(1'b0),
        .wr_en_i(8'b0),
        .wr_data_i(64'b0),
        .addr_i(15'b0),
        .rd_data_o()
    );
    edrv32_mul_s33x33 u_mul (
        .clk_i(1'b0),
        .enable_i(1'b0),
        .operand_a_i(33'b0),
        .operand_b_i(33'b0),
        .product_o()
    );
endmodule
