// File: tb.sv
// Spec: eth 2.5-2.6, 5.2-5.3, 6.
// Description: Independent packet construction, descriptor boundaries, ARP priority and read errors.
//              Actual FIFO/front end run on an independent 100 ppm slower transmit clock.
// Clock domain: clk_mem and eth_tx_clk.
module tb #(parameter realtime TX_HALF = 4.0004);
    timeunit 1ns;
    timeprecision 1ps;
    logic clk=0;
    always #4 clk=!clk;
    logic tx_clk=0;
    always #(TX_HALF) tx_clk=!tx_clk;
    logic rst=0;
    logic clear=0;
    logic start=0;
    logic abort_cmd=0;
    logic [15:0] desc_count=1;
    logic arp_valid=0;
    wire arp_ready;
    wire valid;
    wire ready;
    wire [9:0] data;
    wire frame_done;
    wire busy;
    wire unused_running;
    wire done;
    wire error;
    wire [15:0] current;
    wire desc_done;
    wire udp_done;
    wire arp_done;
    wire axi_arid_o;
    wire [31:0] axi_araddr_o;
    wire [3:0] axi_arlen_o;
    wire axi_arvalid_o;
    logic axi_arready_i=0;
    logic axi_rid_i=0;
    logic [255:0] axi_rdata_i=0;
    logic [1:0] axi_rresp_i=0;
    logic axi_rlast_i=0;
    logic axi_rvalid_i=0;
    wire axi_rready_o;
    edrv32_eth_tx dut (
        .clk_i(clk), .rst_n_i(rst), .clear_i(clear), .start_i(start), .abort_i(abort_cmd),
        .desc_base_i(32'h100), .desc_count_i(desc_count), .mac_i(48'h020304050607),
        .ip_i(32'hc0a80102), .dst_mac_i(48'h002233445566), .dst_ip_i(32'hc0a80103),
        .ports_i({16'd5678,16'd1234}), .arp_valid_i(arp_valid), .arp_ready_o(arp_ready),
        .arp_mac_i(48'h102030405060), .arp_ip_i(32'h0a000001),
        .valid_o(valid), .ready_i(ready), .data_o(data), .frame_done_i(frame_done),
        .axi_arid_o(axi_arid_o),
        .axi_araddr_o(axi_araddr_o),
        .axi_arlen_o(axi_arlen_o),
        .axi_arvalid_o(axi_arvalid_o),
        .axi_arready_i(axi_arready_i),
        .axi_rid_i(axi_rid_i),
        .axi_rdata_i(axi_rdata_i),
        .axi_rresp_i(axi_rresp_i),
        .axi_rlast_i(axi_rlast_i),
        .axi_rvalid_i(axi_rvalid_i),
        .axi_rready_o(axi_rready_o),
        .busy_o(busy), .running_o(unused_running), .done_o(done), .error_o(error), .current_o(current),
        .descriptor_done_o(desc_done), .udp_done_o(udp_done), .arp_done_o(arp_done)
    );
    wire fv;
    wire fr;
    wire [9:0] fd;
    wire front_done;
    wire [7:0] txd;
    wire txen;
    wire txer;
    edrv32_eth_fifo fifo (
        .clk_write_i(clk), .rst_write_n_i(rst), .clk_read_i(tx_clk), .rst_read_n_i(rst),
        .valid_i(valid), .ready_o(ready), .data_i(data), .valid_o(fv), .ready_i(fr), .data_o(fd)
    );
    edrv32_eth_tx_front front (
        .clk_i(tx_clk), .rst_n_i(rst), .valid_i(fv), .ready_o(fr), .data_i(fd[8:0]),
        .data_o(txd), .valid_o(txen), .error_o(txer), .done_o(front_done)
    );
    edrv32_cdc_pulse completion (
        .clk_src_i(tx_clk), .rst_src_n_i(rst), .clk_dst_i(clk), .rst_dst_n_i(rst),
        .pulse_i(front_done), .pulse_o(frame_done)
    );
    wire unused = &{1'b0, axi_arid_o,fd[9],txd,txen,udp_done};
    byte unsigned memory[0:65535];
    logic [35:0] requests[$];
    logic [35:0] req;
    integer rd_left=0;
    integer rd_addr=0;
    integer bad_addr=-1;
    integer outstanding=0;
    integer frames=0;
    integer descriptor_completions=0;
    integer dones=0;
    integer errors=0;
    integer arp_frames=0;
    integer id=0;
    integer total=0;
    integer sent_data=0;
    integer seen_in_command=0;
    integer offset_base=32'h12345678;
    logic multi_mode=0;
    logic stall_ar=0;
    integer arp_expected_frame=-1;
    logic expect_arp=0;
    byte unsigned captured[$];
    byte unsigned expected[$];
    always @(negedge clk) axi_arready_i=!stall_ar && ($urandom_range(0,3)!=0);
    always @(posedge clk) begin
        if(axi_arvalid_o && axi_arready_i) begin
            requests.push_back({axi_araddr_o,axi_arlen_o});outstanding++;
        end
        if(axi_rvalid_i && axi_rready_o) begin
            rd_addr+=32;rd_left--;
            if(axi_rlast_i) outstanding--;
        end
        if(!axi_rvalid_i || axi_rready_o) begin
            axi_rvalid_i<=0;
            if(rd_left==0 && requests.size()!=0) begin
                req=requests.pop_front();rd_addr=int'(req[35:4]);rd_left=int'(req[3:0])+1;
            end
            if(rd_left!=0 && $urandom_range(0,3)!=0) begin
                axi_rvalid_i<=1;axi_rlast_i<=rd_left==1;
                axi_rresp_i <= rd_addr==bad_addr ? 2'b10 : 2'b00;
                for(integer i=0;i<32;i++) axi_rdata_i[i*8+:8]<=memory[(rd_addr+i)%65536];
            end
        end
        if(desc_done) descriptor_completions++;
        if(done) dones++;
        if(error) errors++;
        if(arp_done) arp_frames++;
        if(valid && ready) begin
            captured.push_back(data[7:0]);
            if(data[8]) begin
                check_frame();captured.delete();frames++;seen_in_command++;
            end
        end
    end
    always @(posedge tx_clk) begin
        if(fr && !fv) $fatal(1,"FAIL transmit underflow at %0t",$time);
        if(txer) $fatal(1,"FAIL TX error");
    end
    task automatic put16(input integer off,input integer val);
        expected[off]=8'(val>>8);expected[off+1]=8'(val);
    endtask
    task automatic put32(input integer off,input logic[31:0] val);
        for(integer i=0;i<4;i++) expected[off+i]=val[31-i*8-:8];
    endtask
    task automatic putmac(input integer off,input logic[47:0] mac);
        for(integer i=0;i<6;i++) expected[off+i]=mac[47-i*8-:8];
    endtask
    task automatic check_frame;
        integer n;
        integer sum;
        expected.delete();
        if(captured.size()>13 && captured[13]==6) begin
            for(integer i=0;i<42;i++) expected.push_back(0);
            putmac(0,48'h102030405060);putmac(6,48'h020304050607);
            put16(12,32'h0806);put16(14,1);put16(16,32'h0800);
            expected[18]=6;expected[19]=4;put16(20,2);
            putmac(22,48'h020304050607);put32(28,32'hc0a80102);
            putmac(32,48'h102030405060);put32(38,32'h0a000001);
            if(!expect_arp || frames!=arp_expected_frame)
                $fatal(1,"FAIL ARP priority actual=%0d expected=%0d",frames,arp_expected_frame);
            expect_arp=0;
        end else begin
            n=total-sent_data>1024 ? 1024 : total-sent_data;
            for(integer i=0;i<50+n;i++) expected.push_back(0);
            putmac(0,48'h002233445566);putmac(6,48'h020304050607);
            put16(12,32'h0800);expected[14]=8'h45;put16(16,n+36);put16(18,id);
            put16(20,32'h4000);expected[22]=64;expected[23]=17;
            put32(26,32'hc0a80102);put32(30,32'hc0a80103);
            sum=0;
            for(integer i=14;i<34;i+=2) sum+=(int'(expected[i])<<8)+int'(expected[i+1]);
            sum=(sum&65535)+(sum>>16);sum=(sum&65535)+(sum>>16);
            put16(24,(~sum)&65535);
            put16(34,5678);put16(36,1234);put16(38,n+16);
            expected[42]=2;expected[43]=(sent_data+n==total)?1:0;
            put32(46,32'(offset_base+sent_data));
            for(integer i=0;i<n;i++) expected[50+i]=memory[4096+sent_data+i];
            sent_data+=n;id=(id+1)%65536;
            if(multi_mode && sent_data==total) sent_data=0;
        end
        if(captured.size()!=expected.size())
            $fatal(1,"FAIL frame length expected=%0d actual=%0d",expected.size(),captured.size());
        foreach(expected[i])
            if(captured[i]!=expected[i])
                $fatal(1,"FAIL frame=%0d byte=%0d expected=%02h actual=%02h",frames,i,expected[i],captured[i]);
    endtask
    task automatic store32(input integer addr,input logic[31:0] val);
        for(integer i=0;i<4;i++) memory[addr+i]=val[i*8+:8];
    endtask
    task automatic command(input integer len);
        total=len;sent_data=0;seen_in_command=0;
        store32(256,32'h1003);store32(260,32'(len));store32(264,32'h102);
        store32(268,32'(offset_base));
        for(integer i=272;i<288;i++) memory[i]=8'($urandom);
        @(negedge clk);start=1;
        @(negedge clk);start=0;
    endtask
    task automatic normal(input integer len);
        integer before_done;
        before_done=dones;
        command(len);
        wait(!busy);repeat(4) @(negedge clk);
        if(dones!=before_done+1 || current!=1 || seen_in_command!=((len==0)?1:(len+1023)/1024))
            $fatal(1,"FAIL descriptor completion len=%0d frames=%0d current=%0d",len,seen_in_command,current);
        if(outstanding!=0) $fatal(1,"FAIL pending reads");
    endtask
    initial begin
        foreach(memory[i]) memory[i]=8'(i*17+9);
        repeat(3) @(negedge clk);rst=1;
        normal(0);normal(1);normal(1023);normal(1024);normal(1025);normal(3000);
        multi_mode=1;desc_count=3;
        for(integer d=1;d<3;d++) begin
            store32(256+32*d,32'h1000);store32(260+32*d,33);
            store32(264+32*d,32'h102);store32(268+32*d,32'(offset_base));
        end
        command(33);wait(!busy);repeat(5) @(negedge clk);
        if(current!=3 || seen_in_command!=3) $fatal(1,"FAIL descriptor sequence");
        multi_mode=0;desc_count=1;
        // ARP takes the next wire slot while a UDP packet is in progress.
        command(3000);wait(valid);repeat(100) @(negedge clk);
        arp_expected_frame=frames+1;expect_arp=1;arp_valid=1;
        do @(posedge clk); while(!arp_ready);
        @(negedge clk);arp_valid=0;
        wait(!busy);repeat(5) @(negedge clk);
        if(arp_frames!=1 || expect_arp) $fatal(1,"FAIL ARP completion");
        // ABORT preserves the frame already committed to the FIFO and drops prefetched work.
        command(3000);wait(valid);repeat(50) @(negedge clk);
        abort_cmd=1;@(negedge clk);abort_cmd=0;
        wait(!busy);repeat(5) @(negedge clk);
        if(seen_in_command!=1 || current!=0 || outstanding!=0) $fatal(1,"FAIL ABORT");
        // A stalled AR remains valid and drains after ABORT.
        stall_ar=1;command(1024);wait(axi_arvalid_o);
        @(negedge clk);abort_cmd=1;@(negedge clk);abort_cmd=0;
        repeat(5) @(negedge clk);stall_ar=0;
        wait(!busy);repeat(5) @(negedge clk);
        if(seen_in_command!=0 || current!=0 || outstanding!=0) $fatal(1,"FAIL AR ABORT");
        command(3000);wait(axi_arvalid_o && axi_araddr_o>=4096);
        repeat(2) @(negedge clk);abort_cmd=1;@(negedge clk);abort_cmd=0;
        wait(!busy);repeat(5) @(negedge clk);
        if(seen_in_command!=0 || current!=0 || outstanding!=0) $fatal(1,"FAIL data ABORT");
        bad_addr=256;command(1024);wait(!busy);repeat(5) @(negedge clk);
        if(seen_in_command!=0 || current!=0 || outstanding!=0) $fatal(1,"FAIL descriptor read error");
        bad_addr=4096;command(1024);wait(!busy);repeat(5) @(negedge clk);
        if(seen_in_command!=0 || current!=0 || outstanding!=0 || errors<2)
            $fatal(1,"FAIL payload read error");
        bad_addr=5120;command(3000);wait(!busy);repeat(5) @(negedge clk);
        if(seen_in_command!=1 || current!=0 || outstanding!=0)
            $fatal(1,"FAIL completed packet before later read error");
        bad_addr=-1;normal(1);
        desc_count=0;command(0);repeat(5) @(negedge clk);
        if(busy || current!=0) $fatal(1,"FAIL zero descriptor count");
        $display("PASS TX boundaries/checksum/ARP/ABORT/errors frames=%0d descriptors=%0d",frames,descriptor_completions);
        $finish;
    end
    initial begin #10000000;$fatal(1,"FAIL timeout state=%0d frames=%0d",dut.state_r,frames);end
endmodule
