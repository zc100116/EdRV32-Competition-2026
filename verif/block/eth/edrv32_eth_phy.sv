// File: edrv32_eth_phy.sv
// Spec: eth 2.7; eth-testplan ET-13.
// Description: Clause-22 PHY register responder and bit-exact command monitor.
// Clock domain: MDC, derived from clk_mem / 64.
`timescale 1ns/1ps
module edrv32_eth_phy (
    input logic rst_n_i,
    input logic mdc_i,
    input logic mdio_i,
    input logic mdio_oe_i,
    output logic mdio_o
);
    bit [15:0] registers[32];
    bit [63:0] capture;
    int bit_count = 0;
    int idle_ones = 0;
    int transactions = 0;
    bit [4:0] last_phy;
    bit [4:0] last_reg;
    bit last_write;
    bit reading = 0;
    bit [4:0] read_reg;
    realtime last_edge = 0;

    always @(posedge mdc_i) begin
        if (!rst_n_i) begin
            bit_count = 0;
            idle_ones = 0;
            transactions = 0;
            last_edge = 0;
        end else begin
            if (bit_count != 0 && last_edge != 0 && $realtime-last_edge != 512.0)
                $fatal(1, "FAIL MDC period expected=512ns actual=%0f time=%0t",
                    $realtime-last_edge, $time);
            last_edge = $realtime;
            // Clause 22 permits idle high with either released or driven MDIO.
            // Find ST's first zero after the preamble, independently of idle length.
            if (bit_count == 0) begin
                if (!mdio_oe_i || mdio_i) idle_ones++;
                else begin
                    if (idle_ones < 32)
                        $fatal(1, "FAIL MDIO preamble expected>=32 actual=%0d time=%0t",
                            idle_ones, $time);
                    capture = 64'h00000001fffffffe;
                    bit_count = 33;
                    idle_ones = 0;
                end
            end else begin
                capture = {capture[62:0], mdio_oe_i ? mdio_i : mdio_o};
                if (bit_count < 46 && !mdio_oe_i)
                    $fatal(1, "FAIL MDIO bit=%0d OE expected=1 actual=0 time=%0t",
                        bit_count, $time);
                if (bit_count == 45) begin
                    reading = capture[11:10] == 2'b10;
                    read_reg = capture[4:0];
                end
                if (bit_count >= 46 && reading && mdio_oe_i)
                    $fatal(1, "FAIL MDIO read OE expected=0 actual=1 time=%0t", $time);
                if (bit_count >= 46 && !reading && !mdio_oe_i)
                    $fatal(1, "FAIL MDIO write OE expected=1 actual=0 time=%0t", $time);
                if (bit_count == 63) begin
                    if (capture[63:32] != 32'hffffffff || capture[31:30] != 2'b01
                        || !(capture[29:28] inside {2'b01, 2'b10}))
                        $fatal(1, "FAIL MDIO header expected=ffffffff/01/01|10 actual=%h time=%0t",
                            capture, $time);
                    last_phy = capture[27:23];
                    last_reg = capture[22:18];
                    last_write = capture[29:28] == 2'b01;
                    if (capture[17:16] != 2'b10)
                        $fatal(1, "FAIL MDIO TA expected=10 actual=%b time=%0t",
                            capture[17:16], $time);
                    if (last_write) registers[last_reg] = capture[15:0];
                    bit_count = 0;
                    transactions++;
                end else bit_count++;
            end
        end
    end

    always @(negedge mdc_i) begin
        mdio_o = 1;
        if (reading && bit_count == 47) mdio_o = 0;
        if (reading && bit_count >= 48 && bit_count <= 63)
            mdio_o = registers[read_reg][63-bit_count];
    end
endmodule
