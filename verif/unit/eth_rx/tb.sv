// File: tb.sv
// Spec: eth 2.2-2.5, 5.1-5.2.
// Description: Every ordered receive filter rule, byte packing, checksums and ring exhaustion.
// Clock domain: clk_mem test clock.
module tb;
    timeunit 1ns;
    timeprecision 1ps;
    logic clk = 0;
    always #4 clk = !clk;
    logic rst = 0;
    logic clear = 0;
    logic valid = 0;
    logic [9:0] data = 0;
    logic enable = 1;
    logic error = 0;
    logic [111:0] sizes = {4{28'd8192}};
    logic [10:0] released = 0;
    logic metadata_ready = 1;
    logic arp_pending = 0;
    wire packet;
    wire [151:0] metadata;
    wire wr_en;
    wire [9:0] wr_addr;
    wire [31:0] wr_data;
    wire busy;
    wire arp;
    wire [47:0] arp_mac;
    wire [31:0] arp_ip;
    wire frame_event;
    wire [3:0] drop;
    byte unsigned bytes_q[$];
    logic [31:0] memory [0:1023];
    integer expected = 0;
    integer arp_accepted = 0;
    integer frame_seen = 0;
    integer last_drop = 0;
    integer drops = 0;
    integer expected_len = 0;
    integer accepted = 0;
    integer start_word;
    logic auto_release = 1;
    edrv32_eth_rx dut (
        .clk_i(clk), .rst_n_i(rst), .clear_i(clear),
        .valid_i(valid), .data_i(data), .enable_i(enable), .error_i(error),
        .mac_i(48'h020304050607), .ip_i(32'hc0a80102), .port_i(16'd1234),
        .sizes_i(sizes), .release_i(released), .packet_o(packet), .metadata_o(metadata),
        .metadata_ready_i(metadata_ready), .wr_en_o(wr_en), .wr_addr_o(wr_addr),
        .wr_data_o(wr_data), .busy_o(busy), .arp_pending_i(arp_pending), .arp_o(arp),
        .arp_mac_o(arp_mac), .arp_ip_o(arp_ip), .frame_o(frame_event), .drop_o(drop)
    );
    wire unused = &{1'b0, busy, metadata[130:96]};
    always @(posedge clk) begin
        if (clear) released = 0;
        if (wr_en) memory[wr_addr] = wr_data;
        if (packet) begin
            accepted++;
            if (expected != 1 || metadata[141:131] != 11'(expected_len))
                $fatal(1, "FAIL unexpected packet expected=%0d len=%0d", expected, expected_len);
            if (metadata[95:0] != 96'h1020304050600a000001abcd)
                $fatal(1, "FAIL peer metadata %h", metadata[95:0]);
            start_word = int'(metadata[151:142]);
            for (integer i = 0; i < expected_len; i++)
                if (memory[(start_word+i/4)%1024][(i%4)*8 +: 8] != 8'(i*13+7))
                    $fatal(1, "FAIL RX byte %0d", i);
            if (auto_release) released = released + 11'((expected_len+3)/4);
        end
        if (arp) begin
            arp_accepted++;
            if (expected != 2 || arp_mac != 48'h102030405060 || arp_ip != 32'h0a000001)
                $fatal(1, "FAIL ARP request metadata");
        end
        if (frame_event) begin
            frame_seen++;last_drop=int'(drop);
            if(drop!=0) drops++;
        end
    end
    task automatic put16(input integer off, input integer val);
        bytes_q[off] = 8'(val >> 8); bytes_q[off+1] = 8'(val);
    endtask
    task automatic put32(input integer off, input logic [31:0] val);
        for (integer i=0; i<4; i++) bytes_q[off+i] = val[31-i*8 -: 8];
    endtask
    function automatic integer sum_bytes(input integer off, input integer n);
        integer s;
        s = 0;
        for (integer i=0; i<n; i+=2)
            s += (int'(bytes_q[off+i]) << 8) + ((i+1<n) ? int'(bytes_q[off+i+1]) : 0);
        return s;
    endfunction
    function automatic integer complement(input integer s);
        integer f;
        f = (s & 65535) + (s >> 16); f = (f & 65535) + (f >> 16);
        return (~f) & 65535;
    endfunction
    task automatic ip_checksum;
        put16(24,0); put16(24, complement(sum_bytes(14,20)));
    endtask
    task automatic udp_checksum;
        integer s;
        put16(40,0);
        s = sum_bytes(26,8) + 17 + 16 + expected_len + sum_bytes(34,16+expected_len);
        put16(40,complement(s));
    endtask
    task automatic udp(input integer n);
        bytes_q.delete(); expected_len=n;
        for(integer i=0;i<((n+54<64)?64:n+54);i++) bytes_q.push_back(0);
        for(integer i=0;i<6;i++) begin
            bytes_q[i]=8'((48'h020304050607 >> (40-i*8)) & 255);
            bytes_q[6+i]=8'((48'h102030405060 >> (40-i*8)) & 255);
        end
        put16(12,32'h0800); bytes_q[14]=8'h45; put16(16,n+36);
        put16(20,32'h4000); bytes_q[22]=64; bytes_q[23]=17;
        put32(26,32'h0a000001); put32(30,32'hc0a80102);
        put16(34,32'habcd); put16(36,1234); put16(38,n+16);
        bytes_q[42]=8'hfc; bytes_q[43]=8'h81; put32(46,32'd3);
        for(integer i=0;i<n;i++) bytes_q[50+i]=8'(i*13+7);
        ip_checksum();
    endtask
    task automatic arp_request;
        bytes_q.delete();
        for(integer i=0;i<64;i++) bytes_q.push_back(0);
        for(integer i=0;i<6;i++) begin
            bytes_q[i]=255;
            bytes_q[6+i]=8'((48'h102030405060 >> (40-i*8)) & 255);
            bytes_q[22+i]=bytes_q[6+i];
        end
        put16(12,32'h0806); put16(14,1); put16(16,32'h0800);
        bytes_q[18]=6; bytes_q[19]=4; put16(20,1);
        put32(28,32'h0a000001); put32(38,32'hc0a80102);
    endtask
    task automatic send(input integer result, input logic link_bad=0,input integer soft_at=-1,input integer free_at=-1,input bit gaps=0);
        integer before_packets;
        integer before_arp;
        integer before_frames;
        before_packets=accepted;before_arp=arp_accepted;before_frames=frame_seen;
        expected=result;
        foreach(bytes_q[i]) begin
            @(negedge clk); valid=1; data={2'b00,bytes_q[i]}; clear=(i==soft_at);
            if(i==free_at) released=released+11'd732;
            if(gaps && i%3==1) begin
                @(negedge clk); valid=0;
            end
        end
        @(negedge clk); valid=1; data={1'b1,link_bad,8'd0};clear=0;
        @(negedge clk); valid=0;
        repeat(3) @(negedge clk);
        if(frame_seen!=before_frames+1 || accepted!=before_packets+((result==1)?1:0) ||
            arp_accepted!=before_arp+((result==2)?1:0) ||
            last_drop!=((result>=3)?result:0))
            $fatal(1,"FAIL filter expected=%0d accepted=%0d arp=%0d drop=%0d",result,
                accepted-before_packets,arp_accepted-before_arp,last_drop);
    endtask
    initial begin
        repeat(3) @(negedge clk); rst=1;
        udp(0); send(1); udp(1); udp_checksum(); send(1); udp(33); udp_checksum(); send(1);
        udp(1464); udp_checksum(); send(1);
        // Exercise the shortest four-byte FCS tail on either side of the padding boundary.
        for(integer n=0;n<36;n++) begin
            udp(n); udp_checksum(); send(1);
        end
        udp(19); udp_checksum(); send(1,0,-1,-1,1);
        for(integer w=0;w<4;w++) begin udp(9);bytes_q[42]=8'(w);send(1);end
        udp(33);send(0,0,20);
        udp(33);send(1);
        enable=0; udp(1); send(0,1); enable=1;
        error=1; udp(1); send(0); error=0;
        udp(1); send(3,1);
        udp(1); while(bytes_q.size()>63) void'(bytes_q.pop_back()); send(3);
        udp(1); while(bytes_q.size()<1519) bytes_q.push_back(0); send(3);
        udp(1); while(bytes_q.size()<65600) bytes_q.push_back(0); send(3);
        udp(1); bytes_q[0]^=1; send(5);
        udp(1); for(integer i=0;i<6;i++) bytes_q[i]=255; send(5);
        arp_request(); send(2);
        arp_request();
        for(integer i=0;i<6;i++) bytes_q[i]=8'(48'h020304050607 >> (40-i*8));
        send(2);
        for(integer f=0;f<6;f++) begin
            arp_request();
            case(f)
                0: bytes_q[15]=2;
                1: bytes_q[17]=1;
                2: bytes_q[18]=5;
                3: bytes_q[19]=5;
                4: bytes_q[21]=2;
                5: bytes_q[41]^=1;
            endcase
            send(5);
        end
        arp_request(); arp_pending=1; send(5); arp_pending=0;
        for(integer f=0;f<10;f++) begin
            udp(7);
            case(f)
                0: bytes_q[14]=8'h65;
                1: bytes_q[14]=8'h46;
                2: bytes_q[20]=8'h20;
                3: bytes_q[21]=1;
                4: bytes_q[23]=6;
                5: bytes_q[33]^=1;
                6: put16(16,1500);
                7: bytes_q[36]^=1;
                8: put16(38,22);
                9: begin put16(38,15); put16(16,35); end
            endcase
            ip_checksum(); send(5);
        end
        udp(17); bytes_q[24]^=1; send(4);
        udp(17); udp_checksum(); bytes_q[51]^=1; send(4);
        udp(1); bytes_q[36]^=1; bytes_q[24]^=1; send(4);
        udp(1); sizes=0; send(6); sizes={4{28'd8192}};
        udp(1); put32(46,8191); send(1);
        udp(1); put32(46,8192); send(6);
        udp(2); put32(46,32'hffffffff); send(6);
        udp(1); metadata_ready=0; send(7); metadata_ready=1;
        udp(1); sizes=0; metadata_ready=0; send(6); sizes={4{28'd8192}}; metadata_ready=1;
        auto_release=0; udp(1464); send(1); udp(1464); send(1); udp(1464); send(7);
        // Releasing storage after a failed speculative write must not resurrect that frame.
        udp(1464);send(7,0,-1,1400);auto_release=1;udp(4);send(1);
        $display("PASS RX filtering every rule, checksums, ring packing/exhaustion accepted=%0d drops=%0d",accepted,drops);
        $finish;
    end
    initial begin #1000000; $fatal(1,"FAIL timeout"); end
endmodule
