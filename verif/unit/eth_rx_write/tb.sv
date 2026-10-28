// File: tb.sv
// Spec: eth 2.4, 5.1; dma2d 2.4, 5.2.
// Description: Exhaustive byte alignment and length boundaries with delayed write completion.
// Clock domain: clk_mem test clock.
module tb;
    timeunit 1ns;
    timeprecision 1ps;
    logic clk=0;
    always #4 clk=!clk;
    logic rst=0;
    logic valid=0;
    logic [151:0] meta=0;
    wire ready;
    wire rd_en;
    wire [9:0] rd_addr;
    logic [31:0] rd_data;
    wire dv;
    logic dr=0;
    wire [31:0] base;
    wire [15:0] width_bytes;
    wire v;
    logic r=0;
    wire [255:0] data;
    wire [31:0] strb;
    logic done=0;
    logic error=0;
    wire busy;
    wire complete;
    wire err;
    wire [10:0] released;
    wire [10:0] length;
    wire [1:0] window;
    wire notify;
    wire [95:0] peer;
    integer n;
    integer off;
    integer beat;
    integer packets=0;
    integer release_expected=0;
    logic descriptor_seen=0;
    logic [31:0] mem[0:1023];
    edrv32_eth_rx_write dut (
        .clk_i(clk), .rst_n_i(rst), .clear_i(1'b0),
        .valid_i(valid), .ready_o(ready), .data_i(meta),
        .bases_i({32'h4000,32'h3000,32'h2000,32'h1000}),
        .rd_en_o(rd_en), .rd_addr_o(rd_addr), .rd_data_i(rd_data),
        .desc_valid_o(dv), .desc_ready_i(dr), .desc_base_o(base), .desc_width_o(width_bytes),
        .data_valid_o(v), .data_ready_i(r), .data_o(data), .strb_o(strb),
        .done_i(done), .error_i(error), .busy_o(busy), .complete_o(complete), .error_o(err),
        .release_o(released), .length_o(length), .window_o(window), .notify_o(notify),
        .peer_o(peer)
    );
    always @(posedge clk) begin
        if(rd_en) rd_data <= mem[rd_addr];
        if(dv && dr) begin
            descriptor_seen=1;
            if(base!=32'h3000+32'(off/32*32) || int'(width_bytes)!=n+off%32)
                $fatal(1,"FAIL descriptor base=%h width=%0d n=%0d off=%0d",base,width_bytes,n,off);
        end
        if(v && r) begin
            for(integer lane=0;lane<32;lane++) begin
                if(strb[lane] != (beat*32+lane >= off%32 && beat*32+lane < off%32+n))
                    $fatal(1,"FAIL WSTRB n=%0d off=%0d beat=%0d lane=%0d",n,off,beat,lane);
                if(strb[lane] && data[lane*8 +:8] != 8'((beat*32+lane-off%32)*19+5))
                    $fatal(1,"FAIL WDATA n=%0d off=%0d beat=%0d lane=%0d expected=%0d actual=%0d",n,off,beat,lane,8'((beat*32+lane-off%32)*19+5),data[lane*8+:8]);
            end
            beat++;
        end
        if(complete) begin
            packets++;
            if(length!=11'(n) || window!=2 || !notify || peer!=96'h123456789abcdef012345678)
                $fatal(1,"FAIL completion metadata");
        end
    end
    task automatic run_packet(input integer a,input integer b);
        off=a; n=b; beat=0; descriptor_seen=0;
        for(integer i=0;i<(n+3)/4;i++)
            for(integer j=0;j<4;j++) mem[(release_expected+i)%1024][j*8+:8]=8'((i*4+j)*19+5);
        @(negedge clk); meta={10'(release_expected),11'(n),32'(off),2'd2,1'b1,
            96'h123456789abcdef012345678};valid=1;
        @(negedge clk);valid=0;
        if(n!=0) begin
            dr=0; repeat(3) @(negedge clk); dr=1;
            while(beat<(n+off%32+31)/32) begin
                @(negedge clk); r=($urandom_range(0,3)!=0);
            end
            r=0; dr=0;
            repeat(20) begin @(negedge clk); if(complete) $fatal(1,"FAIL early complete"); end
            done=1;
            @(negedge clk); done=0;
        end
        wait(complete); @(negedge clk); @(negedge clk);
        release_expected=(release_expected+(n+3)/4)%2048;
        if(released!=11'(release_expected) || !ready || busy || err || (n!=0 && !descriptor_seen))
            $fatal(1,"FAIL ring release actual=%0d expected=%0d",released,release_expected);
    endtask
    initial begin
        repeat(3) @(negedge clk); rst=1;
        for(integer a=0;a<32;a++) begin
            run_packet(a,0);run_packet(a,1);run_packet(a,3);run_packet(a,4);
            run_packet(a,31);run_packet(a,32);run_packet(a,33);run_packet(a,1464);
        end
        $display("PASS arbitrary OFFSET/LEN AXI address/WSTRB %0d packets",packets);$finish;
    end
    initial begin #10000000; $fatal(1,"FAIL timeout n=%0d off=%0d beat=%0d",n,off,beat); end
endmodule
