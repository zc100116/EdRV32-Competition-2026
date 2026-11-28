// Self-checking public-interface test; independent architectural reference.
module tb;
    reg clk_i;
    reg rst_n_i;
    reg [19:0] id_rs_i;
    reg [3:0] id_owner_i;
    reg [1:0] wb_valid_i;
    reg [9:0] wb_rd_i;
    reg [63:0] wb_data_i;
    wire [31:1] lvt_o;
    wire [127:0] id_data_o;
    edrv32_cpu2_rf dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .id_rs_i(id_rs_i),
        .id_owner_i(id_owner_i),
        .wb_valid_i(wb_valid_i),
        .wb_rd_i(wb_rd_i),
        .wb_data_i(wb_data_i),
        .lvt_o(lvt_o),
        .id_data_o(id_data_o)
    );
    always #5 clk_i = ~clk_i;
    task tick; begin @(posedge clk_i); #1; end endtask
    task init_inputs; begin
        clk_i = '0;
        rst_n_i = '0;
        id_rs_i = '0;
        id_owner_i = '0;
        wb_valid_i = '0;
        wb_rd_i = '0;
        wb_data_i = '0;
        tick(); rst_n_i = 1; tick();
    end endtask
    reg [31:0] reference [0:31];
    reg [31:1] owners;
    integer n;
    integer p;
    integer r;
    reg [31:0] expected;
    task check_reads;
        begin
            #1;
            for (p=0; p<4; p=p+1) begin
                r = int'(id_rs_i[5*p +: 5]);
                expected = reference[r];
                if (wb_valid_i[0] && int'(wb_rd_i[4:0])==r && r!=0)
                    expected=wb_data_i[31:0];
                if (wb_valid_i[1] && int'(wb_rd_i[9:5])==r && r!=0)
                    expected=wb_data_i[63:32];
                if (id_data_o[32*p +: 32] !== expected)
                    $fatal(1,"RF port %0d expected %h got %h at %0t",p,expected,
                        id_data_o[32*p +: 32],$time);
            end
        end
    endtask
    task write_cycle;
        begin
            check_reads();
            tick();
            for (integer w=0;w<2;w=w+1) begin
                r=int'(wb_rd_i[5*w +: 5]);
                if (wb_valid_i[w] && r!=0) begin
                    reference[r]=wb_data_i[32*w +: 32]; owners[r]=1'(w);
                end
            end
            if (lvt_o !== owners) $fatal(1,"LVT expected %h got %h",owners,lvt_o);
            for (integer v=0;v<4;v=v+1)
                id_owner_i[v]=(id_rs_i[5*v +: 5]!=0) ? owners[id_rs_i[5*v +: 5]]:0;
        end
    endtask
    initial begin
        init_inputs(); owners=0;
        for(n=0;n<32;n=n+1) reference[n]=0;
        for(n=1;n<32;n=n+1) begin
            wb_valid_i=1; wb_rd_i={5'd0,5'(n)};wb_data_i={32'd0,32'(n*37)};
            write_cycle();
        end
        id_rs_i={5'd0,5'd7,5'd9,5'd7};
        // A waiting IB entry sees repeated owner changes and current WB forwarding.
        for(n=0;n<120;n=n+1) begin
            wb_valid_i=(n%3==0)?3:((n%2==0)?1:2);
            wb_rd_i={5'd7,5'd7};wb_data_i={32'(n+1000),32'(n+2000)};
            write_cycle();
        end
        for(n=0;n<300;n=n+1) begin
            id_rs_i=20'($random); wb_valid_i=2'($random);
            wb_rd_i=10'($random);wb_data_i={$random,$random};
            for(integer v=0;v<4;v=v+1)
                id_owner_i[v]=(id_rs_i[5*v +: 5]!=0) ? owners[id_rs_i[5*v +: 5]]:0;
            write_cycle();
        end
        wb_valid_i=3;wb_rd_i=0;wb_data_i='1;id_rs_i=0;check_reads();tick();
        $display("PASS cpu2_rf: WAW, WB, x0, 420 waiting/random cycles");$finish;
    end

endmodule
