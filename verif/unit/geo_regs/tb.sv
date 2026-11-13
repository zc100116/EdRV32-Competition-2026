// File: tb.sv
// Spec: geo-spec 2, 4, 5.
// Description: Independent formula-based unit checks.
// Clock domain: clk_mem.
module tb;
    reg clk = 0;
    always #4 clk = !clk;
    reg r_clk_i;
    reg r_rst_n_i;
    reg [11:0] r_apb_paddr_i;
    reg r_apb_psel_i;
    reg r_apb_penable_i;
    reg r_apb_pwrite_i;
    reg [31:0] r_apb_pwdata_i;
    reg [3:0] r_apb_pstrb_i;
    wire r_apb_pready_o;
    wire [31:0] r_apb_prdata_o;
    wire r_apb_pslverr_o;
    reg r_busy_i;
    reg r_done_i;
    reg r_desc_done_i;
    reg [15:0] r_cur_desc_i;
    reg [1:0] r_error_i;
    wire r_start_o;
    wire r_abort_o;
    wire r_soft_reset_o;
    wire [31:0] r_desc_base_o;
    wire [15:0] r_desc_count_o;
    wire r_irq_o;
    edrv32_geo_regs u_r_ (
        .clk_i(r_clk_i),
        .rst_n_i(r_rst_n_i),
        .apb_paddr_i(r_apb_paddr_i),
        .apb_psel_i(r_apb_psel_i),
        .apb_penable_i(r_apb_penable_i),
        .apb_pwrite_i(r_apb_pwrite_i),
        .apb_pwdata_i(r_apb_pwdata_i),
        .apb_pstrb_i(r_apb_pstrb_i),
        .apb_pready_o(r_apb_pready_o),
        .apb_prdata_o(r_apb_prdata_o),
        .apb_pslverr_o(r_apb_pslverr_o),
        .busy_i(r_busy_i),
        .done_i(r_done_i),
        .desc_done_i(r_desc_done_i),
        .cur_desc_i(r_cur_desc_i),
        .error_i(r_error_i),
        .start_o(r_start_o),
        .abort_o(r_abort_o),
        .soft_reset_o(r_soft_reset_o),
        .desc_base_o(r_desc_base_o),
        .desc_count_o(r_desc_count_o),
        .irq_o(r_irq_o)
    );
    integer address;
    task read_check(input reg [11:0] addr,input reg [31:0] expected);
        begin
            @(negedge clk);r_apb_paddr_i=addr;r_apb_psel_i=1;
            r_apb_pwrite_i=0;r_apb_penable_i=0;
            @(negedge clk);r_apb_penable_i=1;#1;
            if(r_apb_prdata_o!==expected)
                $fatal(1,"FAIL reg %h expected %h got %h at %t",
                    addr,expected,r_apb_prdata_o,$time);
            @(negedge clk);r_apb_psel_i=0;r_apb_penable_i=0;
        end
    endtask
    task write_reg(input reg [11:0] addr,input reg [31:0] value);
        begin
            @(negedge clk);
            r_apb_paddr_i=addr;r_apb_pwdata_i=value;
            r_apb_psel_i=1;r_apb_pwrite_i=1;r_apb_penable_i=0;
            @(negedge clk);r_apb_penable_i=1;
            @(negedge clk);r_apb_psel_i=0;r_apb_penable_i=0;r_apb_pwrite_i=0;
            if (addr==12'h028 || (addr==4 && value[3])) @(negedge clk);
        end
    endtask
    initial begin
        r_rst_n_i = 0;
        r_apb_paddr_i = 0;
        r_apb_psel_i = 0;
        r_apb_penable_i = 0;
        r_apb_pwrite_i = 0;
        r_apb_pwdata_i = 0;
        r_apb_pstrb_i = 0;
        r_busy_i = 0;
        r_done_i = 0;
        r_desc_done_i = 0;
        r_cur_desc_i = 0;
        r_error_i = 0;
        repeat(2) @(negedge clk);r_rst_n_i=1;
        read_check(12'h000,32'h00030001);
        read_check(12'h008,2);
        for(address=12;address<128;address+=4) read_check(12'(address),0);
        read_check(12'h100,0);
        if(!r_apb_pready_o || r_apb_pslverr_o) $fatal(1,"FAIL APB response constants");
        write_reg(12'h000,32'hffffffff);read_check(0,32'h00030001);
        write_reg(12'h004,3);read_check(4,1);
        write_reg(12'h080,32'hffffffff);read_check(12'h080,0);
        @(negedge clk);r_apb_psel_i=1;r_apb_pwrite_i=1;
        r_apb_paddr_i=12'h004;r_apb_pwdata_i=4;r_apb_penable_i=0;#1;
        if(r_abort_o) $fatal(1,"FAIL ABORT fired in APB setup");
        @(negedge clk);r_apb_penable_i=1;#1;
        if(r_abort_o) $fatal(1,"FAIL ABORT bypassed command register");
        @(negedge clk);r_apb_psel_i=0;r_apb_penable_i=0;r_apb_pwrite_i=0;#1;
        if(!r_abort_o) $fatal(1,"FAIL registered ABORT pulse missing");
        @(negedge clk);#1;
        if(r_abort_o) $fatal(1,"FAIL ABORT pulse did not end");
        write_reg(12'h020,32'h1234567f);read_check(12'h020,32'h12345660);
        write_reg(12'h024,32'hffff0000);read_check(12'h024,0);
        write_reg(12'h00c,32'hffffffff);read_check(12'h00c,3);
        write_reg(12'h028,0);read_check(12'h010,1);
        if(!r_irq_o) $fatal(1,"FAIL IRQ done enable");
        write_reg(12'h010,1);read_check(12'h010,0);
        write_reg(12'h024,5);
        @(negedge clk);r_busy_i=1;r_cur_desc_i=2;
        read_check(12'h008,1);read_check(12'h100,2);
        @(negedge clk);r_apb_psel_i=1;r_apb_penable_i=0;r_apb_pwrite_i=1;
        r_apb_paddr_i=12'h028;
        @(negedge clk);r_apb_penable_i=1;#1;
        if(r_start_o) $fatal(1,"FAIL busy doorbell was accepted");
        @(negedge clk);r_apb_psel_i=0;
        write_reg(12'h004,8);read_check(12'h024,5);
        @(negedge clk);
        r_desc_done_i=1;
        @(negedge clk);r_desc_done_i=0;
        repeat(2) @(negedge clk);
        @(negedge clk);
        read_check(12'h02c,1);
        read_check(12'h044,0);read_check(12'h048,0);read_check(12'h04c,0);
        read_check(12'h050,0);read_check(12'h054,0);
        read_check(12'h058,0);
        @(negedge clk);
        @(negedge clk);
        @(negedge clk);
        read_check(12'h044,0);
        @(negedge clk);r_error_i=2;
        @(negedge clk);r_error_i=0;
        read_check(12'h014,2);read_check(12'h010,2);read_check(12'h008,5);
        write_reg(12'h010,2);read_check(12'h014,0);
        @(negedge clk);r_busy_i=0;r_done_i=1;
        @(negedge clk);r_done_i=0;
        read_check(12'h010,1);read_check(12'h008,2);
        write_reg(12'h028,99);read_check(12'h040,0);read_check(12'h044,0);
        write_reg(12'h004,8);
        read_check(12'h004,0);read_check(12'h020,0);read_check(12'h024,0);
        read_check(12'h00c,0);read_check(12'h010,0);read_check(12'h02c,0);
        $display("PASS geo_regs reset, masks, APB, doorbell, IRQ, counters and soft reset");
        $finish;
    end
    always @(*) r_clk_i=clk;
endmodule
