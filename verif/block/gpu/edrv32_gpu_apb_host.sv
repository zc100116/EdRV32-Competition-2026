// File: edrv32_gpu_apb_host.sv
// Spec: SoC 4.3, 7.1–7.2; gpu-testplan 2.
// Description: Single-slot APB host with setup/access phases and direct error reporting.
// Clock domain: clk_gpu.
`timescale 1ns/1ps
module edrv32_gpu_apb_host (
    input logic clk_i,
    edrv32_apb_if bus
);
    task automatic idle();
        bus.psel = 0;
        bus.penable = 0;
        bus.paddr = 0;
        bus.pwrite = 0;
        bus.pwdata = 0;
        bus.pstrb = 0;
    endtask

    task automatic transfer(input bit write_i, input bit [11:0] address_i,
                            input bit [31:0] data_i, output bit [31:0] data_o);
        @(negedge clk_i);
        bus.psel = 1;
        bus.penable = 0;
        bus.paddr = address_i;
        bus.pwrite = write_i;
        bus.pwdata = data_i;
        bus.pstrb = write_i ? 4'hf : 4'h0;
        @(negedge clk_i);
        bus.penable = 1;
        do @(posedge clk_i); while (!bus.pready[0]);
        if (bus.pslverr[0])
            $fatal(1, "FAIL APB address=%h expected=OKAY actual=SLVERR time=%0t",
                    address_i, $time);
        data_o = bus.prdata[31:0];
        @(negedge clk_i);
        idle();
    endtask

    task automatic write_reg(input bit [11:0] address_i, input bit [31:0] data_i);
        bit [31:0] unused_read;
        transfer(1, address_i, data_i, unused_read);
    endtask

    task automatic read_reg(input bit [11:0] address_i, output bit [31:0] data_o);
        transfer(0, address_i, 0, data_o);
    endtask
endmodule
