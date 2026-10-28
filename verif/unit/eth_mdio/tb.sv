// File: tb.sv
// Spec: eth 2.7, 4.2.
// Description: Decode Clause 22 wire bits, check divider and emulate PHY read data.
// Clock domain: clk_mem test clock.
module tb;
    timeunit 1ns;
    timeprecision 1ps;
    logic clk=0;
    always #4 clk=!clk;
    logic rst=0;
    logic clear=0;
    logic start=0;
    logic [31:0] command=0;
    wire busy;
    wire [15:0] result;
    wire mdc;
    wire mdio;
    wire oe;
    logic mdi=1;
    logic [63:0] sampled=0;
    integer bits_seen=0;
    integer transactions=0;
    time previous_rise=0;
    logic writing=0;
    edrv32_eth_mdio dut (
        .clk_i(clk), .rst_n_i(rst), .clear_i(clear), .start_i(start), .command_i(command),
        .busy_o(busy), .data_o(result), .mdc_o(mdc), .mdio_o(mdio), .mdio_oe(oe),
        .mdio_i(mdi)
    );
    always @(negedge clk) begin
        if(busy && bits_seen>=48 && bits_seen<64) mdi=1'(16'ha35c >> (63-bits_seen));
    end
    always @(posedge mdc) begin
        if(busy) begin
            if(bits_seen!=0 && $time-previous_rise!=512)
                $fatal(1,"FAIL MDC period %0t",$time-previous_rise);
            previous_rise=$time;
            if(oe!=(writing || bits_seen<46)) $fatal(1,"FAIL MDIO turnaround bit=%0d",bits_seen);
            sampled={sampled[62:0],mdio};bits_seen++;
        end
    end
    task automatic run(input logic write_cmd,input integer unused_phy,input integer unused_reg_addr);
        writing=write_cmd;bits_seen=0;sampled=0;
        @(negedge clk); command={16'hb762,5'd0,write_cmd,5'(unused_phy),5'(unused_reg_addr)};start=1;
        @(negedge clk);start=0;
        repeat(200) @(negedge clk);
        command=32'hffffffff;start=1;
        @(negedge clk);start=0;
        wait(!busy);@(negedge clk);
        if(bits_seen!=64 || sampled[63:18]!={32'hffffffff,2'b01,
            write_cmd?2'b01:2'b10,5'(unused_phy),5'(unused_reg_addr)})
            $fatal(1,"FAIL MDIO frame %h bits=%0d",sampled,bits_seen);
        if(write_cmd && sampled[17:0]!={2'b10,16'hb762}) $fatal(1,"FAIL MDIO write data");
        if(!write_cmd && result!=16'ha35c) $fatal(1,"FAIL MDIO read actual=%h",result);
        transactions++;
    endtask
    initial begin
        repeat(3) @(negedge clk);rst=1;
        run(1,3,21);run(0,29,7);run(1,31,0);run(0,0,31);
        clear=1;@(negedge clk);clear=0;
        if(busy || result!=0) $fatal(1,"FAIL MDIO soft reset");
        $display("PASS MDIO format/read/write/busy/divider transactions=%0d",transactions);$finish;
    end
    initial begin #1000000;$fatal(1,"FAIL timeout");end
endmodule
