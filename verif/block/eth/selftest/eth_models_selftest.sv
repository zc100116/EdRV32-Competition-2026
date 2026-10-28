// File: eth_models_selftest.sv
// Spec: eth-testplan 2; V-T5 independent environment selftest.
// Description: Exercises RAM stalls/latency/errors and a Clause-22 PHY write/read.
// Clock domain: clk_mem (125 MHz) and MDC (clk_mem/64).
`timescale 1ns/1ps
module eth_models_selftest (
    output bit done_o
);
    logic clk = 0;
    logic rst_n = 0;
    logic mdc = 0;
    logic mdc_enable = 0;
    logic mdio_out = 1;
    logic mdio_oe = 0;
    logic mdio_in;
    int errors;
    int write_end_cycle;
    int read_start_cycle;
    bit [15:0] read_value;
    edrv32_axi256_if bus ();
    edrv32_eth_memory u_ram (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .bus(bus)
    );
    edrv32_axi256_checker u_checker (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .bus(bus),
        .errors_o(errors)
    );
    edrv32_eth_phy u_phy (
        .rst_n_i(rst_n),
        .mdc_i(mdc),
        .mdio_i(mdio_out),
        .mdio_oe_i(mdio_oe),
        .mdio_o(mdio_in)
    );
    always #4 clk = ~clk;
    always #256 begin
        if (mdc_enable) mdc = ~mdc;
    end

    task automatic equal(input string name_i,
        input bit [31:0] expected_i,
        input bit [31:0] actual_i);
        if (expected_i != actual_i)
            $fatal(1, "FAIL model %s expected=%h actual=%h time=%0t",
                name_i, expected_i, actual_i, $time);
    endtask

    task automatic mdio_bit(input bit oe_i,
        input bit data_i);
        @(negedge mdc);
        mdio_oe = oe_i;
        mdio_out = data_i;
        @(posedge mdc);
        #1;
    endtask

    task automatic mdio_command(input bit write_i);
        bit [13:0] header;
        header = {2'b01, (write_i ? 2'b01 : 2'b10), 5'd17, 5'd3};
        repeat (32) mdio_bit(1, 1);
        for (int i = 13; i >= 0; i--) mdio_bit(1, header[i]);
        if (write_i) begin
            mdio_bit(1, 1);
            mdio_bit(1, 0);
            for (int i = 15; i >= 0; i--) mdio_bit(1, 1'(16'hbeef >> i));
        end else begin
            mdio_bit(0, 1);
            mdio_bit(0, 1);
            equal("read TA", 0, 32'(mdio_in));
            for (int i = 15; i >= 0; i--) begin
                mdio_bit(0, 1);
                read_value[i] = mdio_in;
            end
        end
        @(negedge mdc);
        mdio_oe = 0;
    endtask

    initial begin
        done_o = 0;
        bus.awid = 0;
        bus.awaddr = 32'h100;
        bus.awlen = 1;
        bus.awvalid = 0;
        bus.wdata = 0;
        bus.wstrb = 0;
        bus.wlast = 0;
        bus.wvalid = 0;
        bus.bready = 0;
        bus.arid = 0;
        bus.araddr = 32'h100;
        bus.arlen = 1;
        bus.arvalid = 0;
        bus.rready = 0;
        repeat (8) @(negedge clk);
        rst_n = 1;
        u_ram.random_percent = 35;
        u_ram.read_latency = 40;
        u_ram.write_latency = 40;
        u_ram.b_error_transaction = 0;
        u_ram.r_error_transaction = 0;
        bus.awvalid = 1;
        do @(posedge clk); while (!bus.awready);
        @(negedge clk);
        bus.awvalid = 0;
        for (int beat = 0; beat < 2; beat++) begin
            for (int lane = 0; lane < 32; lane++)
                bus.wdata[lane*8+:8] = 8'(beat*32+lane);
            bus.wstrb = beat == 0 ? 32'h80000001 : 32'h000000ff;
            bus.wlast = beat == 1;
            bus.wvalid = 1;
            do @(posedge clk); while (!bus.wready);
            @(negedge clk);
        end
        write_end_cycle = u_ram.cycle;
        bus.wvalid = 0;
        bus.bready = 1;
        do @(posedge clk); while (!bus.bvalid);
        equal("B ID", 0, 32'(bus.bid));
        equal("B SLVERR", 2, 32'(bus.bresp));
        if (u_ram.cycle-write_end_cycle < 40)
            $fatal(1, "FAIL B delay expected>=40 actual=%0d time=%0t",
                u_ram.cycle-write_end_cycle, $time);
        @(negedge clk);
        bus.bready = 0;
        bus.arvalid = 1;
        do @(posedge clk); while (!bus.arready);
        @(negedge clk);
        read_start_cycle = u_ram.cycle;
        bus.arvalid = 0;
        bus.rready = 1;
        for (int beat = 0; beat < 2; beat++) begin
            do @(posedge clk); while (!bus.rvalid);
            if (beat == 0 && u_ram.cycle-read_start_cycle < 40)
                $fatal(1, "FAIL R delay expected>=40 actual=%0d time=%0t",
                    u_ram.cycle-read_start_cycle, $time);
            equal("R ID", 0, 32'(bus.rid));
            equal("R SLVERR", 2, 32'(bus.rresp));
            equal("RLAST", 32'(beat == 1), 32'(bus.rlast));
            for (int lane = 0; lane < 32; lane++)
                equal($sformatf("RAM beat=%0d byte=%0d", beat, lane),
                    (beat == 0 ? (lane inside {0, 31}) : lane < 8)
                    ? 32'(beat*32+lane) : 32'ha5, 32'(bus.rdata[lane*8+:8]));
            @(negedge clk);
        end
        bus.rready = 0;
        equal("AXI checker", 0, 32'(errors));
        equal("RAM B count", 1, 32'(u_ram.b_count));
        equal("RAM R count", 1, 32'(u_ram.r_count));
        equal("RAM AW count", 1, 32'(u_ram.aw_count));
        equal("RAM AR count", 1, 32'(u_ram.ar_count));
        mdc_enable = 1;
        mdio_command(1);
        equal("PHY transaction count", 1, 32'(u_phy.transactions));
        equal("PHY data", 32'hbeef, 32'(u_phy.registers[3]));
        mdio_command(0);
        equal("PHY transaction count", 2, 32'(u_phy.transactions));
        equal("PHY address", 17, 32'(u_phy.last_phy));
        equal("PHY register", 3, 32'(u_phy.last_reg));
        equal("PHY read operation", 0, 32'(u_phy.last_write));
        equal("PHY read data", 32'hbeef, {16'b0, read_value});
        $display("PASS ETH AXI/PHY models selftest");
        done_o = 1;
    end
endmodule
