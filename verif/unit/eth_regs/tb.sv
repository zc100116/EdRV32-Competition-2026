// File: tb.sv
// Spec: eth 4, 6; SoC 7.1.
// Description: APB reset/masks/commands/RW1C/interrupt/performance/soft reset checks.
// Clock domain: clk_mem test clock.
module tb;
    timeunit 1ns;
    timeprecision 1ps;
    logic clk_i = 0;
    logic rst_n_i = 0;
    logic [11:0] apb_paddr_i = 0;
    logic apb_psel_i = 0;
    logic apb_penable_i = 0;
    logic apb_pwrite_i = 0;
    logic [31:0] apb_pwdata_i = 0;
    logic [3:0] apb_pstrb_i = 0;
    wire apb_pready_o;
    wire [31:0] apb_prdata_o;
    wire apb_pslverr_o;
    logic busy_i = 0;
    logic tx_busy_i = 0;
    logic done_i = 0;
    logic desc_done_i = 0;
    logic [15:0] current_i = 0;
    logic read_error_i = 0;
    logic write_error_i = 0;
    logic frame_i = 0;
    logic [3:0] drop_i = 0;
    logic rx_complete_i = 0;
    logic [10:0] rx_length_i = 0;
    logic [1:0] rx_window_i = 0;
    logic rx_notify_i = 0;
    logic [95:0] peer_i = 0;
    logic udp_done_i = 0;
    logic arp_done_i = 0;
    logic mdio_busy_i = 0;
    logic [15:0] mdio_data_i = 0;
    wire enable_o;
    wire [11:0] irq_en_o;
    wire [31:0] desc_base_o;
    wire [15:0] desc_count_o;
    wire [31:0] mac_lo_o;
    wire [15:0] mac_hi_o;
    wire [31:0] ip_o;
    wire [15:0] rx_port_o;
    wire [31:0] dst_mac_lo_o;
    wire [15:0] dst_mac_hi_o;
    wire [31:0] dst_ip_o;
    wire [31:0] ports_o;
    wire phy_o;
    wire [127:0] bases_o;
    wire [111:0] sizes_o;
    wire clear_o;
    wire start_o;
    wire abort_o;
    wire mdio_start_o;
    wire error_o;
    wire irq_o;
    always #4 clk_i = !clk_i;
    edrv32_eth_regs dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .apb_paddr_i(apb_paddr_i),
        .apb_psel_i(apb_psel_i),
        .apb_penable_i(apb_penable_i),
        .apb_pwrite_i(apb_pwrite_i),
        .apb_pwdata_i(apb_pwdata_i),
        .apb_pstrb_i(apb_pstrb_i),
        .apb_pready_o(apb_pready_o),
        .apb_prdata_o(apb_prdata_o),
        .apb_pslverr_o(apb_pslverr_o),
        .busy_i(busy_i),
        .tx_busy_i(tx_busy_i),
        .done_i(done_i),
        .desc_done_i(desc_done_i),
        .current_i(current_i),
        .read_error_i(read_error_i),
        .write_error_i(write_error_i),
        .frame_i(frame_i),
        .drop_i(drop_i),
        .rx_complete_i(rx_complete_i),
        .rx_length_i(rx_length_i),
        .rx_window_i(rx_window_i),
        .rx_notify_i(rx_notify_i),
        .peer_i(peer_i),
        .udp_done_i(udp_done_i),
        .arp_done_i(arp_done_i),
        .mdio_busy_i(mdio_busy_i),
        .mdio_data_i(mdio_data_i),
        .enable_o(enable_o),
        .irq_en_o(irq_en_o),
        .desc_base_o(desc_base_o),
        .desc_count_o(desc_count_o),
        .mac_lo_o(mac_lo_o),
        .mac_hi_o(mac_hi_o),
        .ip_o(ip_o),
        .rx_port_o(rx_port_o),
        .dst_mac_lo_o(dst_mac_lo_o),
        .dst_mac_hi_o(dst_mac_hi_o),
        .dst_ip_o(dst_ip_o),
        .ports_o(ports_o),
        .phy_o(phy_o),
        .bases_o(bases_o),
        .sizes_o(sizes_o),
        .clear_o(clear_o),
        .start_o(start_o),
        .abort_o(abort_o),
        .mdio_start_o(mdio_start_o),
        .error_o(error_o),
        .irq_o(irq_o)
    );
    wire unused = &{1'b0, enable_o, irq_en_o, desc_base_o, desc_count_o, mac_lo_o, mac_hi_o, ip_o, rx_port_o, dst_mac_lo_o, dst_mac_hi_o, dst_ip_o, ports_o, phy_o, bases_o, sizes_o, mdio_start_o};
    integer starts=0;
    integer aborts=0;
    integer clears=0;
    always @(posedge clk_i) begin
        if(start_o) starts++;
        if(abort_o) aborts++;
        if(clear_o) clears++;
    end
    task automatic write_reg(input integer unused_addr,input logic [31:0] data);
        @(negedge clk_i);apb_psel_i=1;apb_penable_i=1;apb_pwrite_i=1;
        apb_paddr_i=12'(unused_addr);apb_pwdata_i=data;apb_pstrb_i=0;
        @(negedge clk_i);apb_psel_i=0;apb_penable_i=0;apb_pwrite_i=0;
    endtask
    task automatic check(input integer addr,input logic [31:0] expected);
        apb_paddr_i=12'(addr);#1;
        if(apb_prdata_o!==expected || !apb_pready_o || apb_pslverr_o)
            $fatal(1,"FAIL register %h expected=%h actual=%h",addr,expected,apb_prdata_o);
    endtask
    initial begin
        repeat(3) @(negedge clk_i);rst_n_i=1;
        check(0,32'h00070001);check(8,2);check(32'h188,1);
        for(integer a=4;a<32'h190;a+=4)
            if(a!=8 && a!=32'h188) check(a,0);
        write_reg(32'h100,32'h11223344);check(32'h100,32'h11223344);
        write_reg(32'h104,32'hffffffff);check(32'h104,65535);
        write_reg(32'h108,32'h0a010203);check(32'h108,32'h0a010203);
        write_reg(32'h10c,32'hffff1234);check(32'h10c,32'h1234);
        write_reg(32'h110,32'h55667788);check(32'h110,32'h55667788);
        write_reg(32'h114,32'h12345678);check(32'h114,32'h5678);
        write_reg(32'h118,32'h0a020304);check(32'h118,32'h0a020304);
        write_reg(32'h11c,32'h12345678);check(32'h11c,32'h12345678);
        write_reg(32'h20,32'h876543ff);check(32'h20,32'h876543e0);
        write_reg(32'h24,32'hffff0003);check(32'h24,3);
        for(integer i=0;i<4;i++) begin
            write_reg(32'h140+i*16,32'h1003+32'(i*8192));
            check(32'h140+i*16,32'h1000+32'(i*8192));
            write_reg(32'h144+i*16,32'hffffffff);check(32'h144+i*16,32'h0fffffff);
        end
        write_reg(4,7);check(4,1);
        if(aborts!=1) $fatal(1,"FAIL abort command");
        busy_i=1;write_reg(32'h28,0);write_reg(4,9);check(4,1);check(8,1);
        if(starts!=0 || clears!=0) $fatal(1,"FAIL busy commands");busy_i=0;
        write_reg(32'h28,32'hdeadbeef);if(starts!=1) $fatal(1,"FAIL doorbell");
        @(negedge clk_i);done_i=1;desc_done_i=1;frame_i=1;rx_complete_i=1;
        rx_length_i=33;rx_window_i=2;rx_notify_i=1;peer_i=96'haabbccddeeff0a010203beef;
        udp_done_i=1;arp_done_i=1;
        @(negedge clk_i);done_i=0;desc_done_i=0;frame_i=0;rx_complete_i=0;
        udp_done_i=0;arp_done_i=0;
        check(32'h10,32'h401);check(32'h2c,1);check(32'h168,33);
        check(32'h120,32'hccddeeff);check(32'h124,32'haabb);
        check(32'h128,32'h0a010203);check(32'h12c,32'hbeef);
        check(32'h40,1);check(32'h44,1);check(32'h48,33);check(32'h60,1);check(32'h68,1);
        write_reg(32'hc,32'hffffffff);check(32'hc,32'hf03);
        if(!irq_o) $fatal(1,"FAIL IRQ");
        write_reg(32'h10,32'h401);check(32'h10,0);if(irq_o) $fatal(1,"FAIL RW1C");
        for(integer w=0;w<4;w++) begin
            @(negedge clk_i);rx_complete_i=1;rx_window_i=2'(w);rx_length_i=11'(w+1);
            @(negedge clk_i);rx_complete_i=0;
            check(32'h10,32'd1 << (8+w));
            check(32'h148+w*16,32'(w+1+((w==2)?33:0)));
            write_reg(32'h10,32'd1 << (8+w));
        end
        @(negedge clk_i);read_error_i=1;
        @(negedge clk_i);read_error_i=0;
        check(32'h14,1);check(32'h10,2);if(!error_o) $fatal(1,"FAIL ERROR");
        write_reg(32'h10,2);check(32'h14,0);
        @(negedge clk_i);write_error_i=1;
        @(negedge clk_i);write_error_i=0;check(32'h14,2);
        write_reg(32'h10,2);
        for(integer i=3;i<=7;i++) begin
            @(negedge clk_i);drop_i=4'(i);
            @(negedge clk_i);drop_i=0;check(32'h40+i*4,1);
        end
        write_reg(32'h168,32'h12345678);check(32'h168,0);
        write_reg(32'h28,0);check(32'h40,1);check(32'h60,1);check(32'h64,0);check(32'h68,0);
        mdio_busy_i=1;mdio_data_i=16'h1234;check(32'h184,32'h12340001);
        check(32'h180,0);check(32'h18c,0);check(32'hffc,0);
        write_reg(0,32'hffffffff);check(0,32'h00070001);
        write_reg(32'h188,0);check(32'h188,0);
        write_reg(4,8);if(clears!=1) $fatal(1,"FAIL soft reset command");
        check(0,32'h00070001);check(8,2);check(32'h188,1);
        mdio_busy_i=0;mdio_data_i=0;
        for(integer a=4;a<32'h190;a+=4) if(a!=8 && a!=32'h188) check(a,0);
        $display("PASS register reset/masks/commands/events/IRQ/RW1C/counters");$finish;
    end
    initial begin #1000000;$fatal(1,"FAIL timeout");end
endmodule
