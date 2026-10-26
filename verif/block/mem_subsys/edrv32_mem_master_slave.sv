// File: edrv32_mem_master_slave.sv
// Spec: task M-V1 master self-test; SoC 4.2 handshake behavior.
// Description: Empty-response slave with address/data stalls and held responses.
// Clock domain: clk_mem.
`timescale 1ns/1ps
module edrv32_mem_master_slave (
    input logic clk_i,
    input logic rst_n_i,
    edrv32_axi256_if bus
);
    int cycle;
    int remaining;
    bit write_pending;
    assign bus.arready = rst_n_i && cycle%7 == 0 && !bus.rvalid;
    assign bus.awready = rst_n_i && cycle%7 == 0 && !write_pending && !bus.bvalid;
    assign bus.wready = rst_n_i && cycle%3 != 0 && write_pending && !bus.bvalid;
    always @(posedge clk_i) begin
        if (!rst_n_i) begin
            cycle <= 0;
            remaining <= 0;
            write_pending <= 0;
            bus.bvalid <= 0;
            bus.bid <= 0;
            bus.bresp <= 0;
            bus.rvalid <= 0;
            bus.rid <= 0;
            bus.rdata <= 0;
            bus.rresp <= 0;
            bus.rlast <= 0;
        end else begin
            cycle <= cycle+1;
            if (bus.awvalid && bus.awready) begin
                bus.bid <= bus.awid;
                write_pending <= 1;
            end
            if (bus.wvalid && bus.wready && bus.wlast) begin
                bus.bvalid <= 1;
                write_pending <= 0;
            end else if (bus.bvalid && bus.bready) bus.bvalid <= 0;
            if (bus.arvalid && bus.arready) begin
                bus.rvalid <= 1;
                bus.rid <= bus.arid;
                remaining <= int'(bus.arlen);
                bus.rlast <= bus.arlen == 0;
            end else if (bus.rvalid && bus.rready) begin
                remaining <= remaining-1;
                bus.rlast <= remaining == 1;
                if (remaining == 0) bus.rvalid <= 0;
            end
        end
    end
endmodule
