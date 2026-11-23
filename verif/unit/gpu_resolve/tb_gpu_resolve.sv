// Self-checking gpu_resolve unit test.
module tb_gpu_resolve;
    logic clk_i = 0;
    logic rst_n_i = 0;
    logic resolve_valid_i = 0;
    logic resolve_ready_o;
    logic [255:0] resolve_command_i = 0;
    logic [255:0] resolve_target_i = 0;
    logic resolve_wide_i = 0;
    logic resolve_read_valid_o;
    logic resolve_read_ready_i = 0;
    logic [15:0] resolve_read_addr_o;
    logic resolve_color_valid_i = 0;
    logic resolve_color_ready_o;
    logic [63:0] resolve_color_data_i = 0;
    logic write_req_valid_o;
    logic write_req_ready_i = 0;
    logic [31:0] write_req_addr_o;
    logic [31:0] write_req_bytes_o;
    logic write_data_valid_o;
    logic write_data_ready_i = 0;
    logic [255:0] write_data_data_o;
    logic [31:0] write_data_keep_o;
    logic write_data_last_o;
    logic write_done_i = 0;
    logic finish_i = 0;
    logic stop_i = 0;
    logic unit_done_o;
    logic perf_resolve_busy_o;
    always #5 clk_i = !clk_i;
    edrv32_gpu_resolve u_dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .resolve_valid_i(resolve_valid_i),
        .resolve_ready_o(resolve_ready_o),
        .resolve_command_i(resolve_command_i),
        .resolve_target_i(resolve_target_i),
        .resolve_wide_i(resolve_wide_i),
        .resolve_read_valid_o(resolve_read_valid_o),
        .resolve_read_ready_i(resolve_read_ready_i),
        .resolve_read_addr_o(resolve_read_addr_o),
        .resolve_color_valid_i(resolve_color_valid_i),
        .resolve_color_ready_o(resolve_color_ready_o),
        .resolve_color_data_i(resolve_color_data_i),
        .write_req_valid_o(write_req_valid_o),
        .write_req_ready_i(write_req_ready_i),
        .write_req_addr_o(write_req_addr_o),
        .write_req_bytes_o(write_req_bytes_o),
        .write_data_valid_o(write_data_valid_o),
        .write_data_ready_i(write_data_ready_i),
        .write_data_data_o(write_data_data_o),
        .write_data_keep_o(write_data_keep_o),
        .write_data_last_o(write_data_last_o),
        .write_done_i(write_done_i),
        .finish_i(finish_i),
        .stop_i(stop_i),
        .unit_done_o(unit_done_o),
        .perf_resolve_busy_o(perf_resolve_busy_o)
    );
    task tick;
        @(posedge clk_i); #1;
    endtask
    task reset;
        rst_n_i = 0;
        repeat (3) tick();
        @(negedge clk_i); rst_n_i = 1;
    endtask
    initial begin
        #2000000;
        $fatal(1,"FAIL timeout state=%0d y=%0d sent=%0d returned=%0d groups=%0d scan=%0d output=%0d rowdone=%b finish=%b row=%0d q=%0d/%0d",
            u_dut.state_r,u_dut.y_r,u_dut.sent_r,u_dut.returned_r,u_dut.groups_r,
            u_dut.scan_r,u_dut.output_count_r,u_dut.row_done_r,finish_i,row,qh,qt);
    end
    int gx0,gy0,gx1,gy1,tx,ty,tw,stride;
    int row,beat;
    int due[200000];
    int addr[200000];
    int qh=0,qt=0;
    int cycle=0;
    int b_due=-1;
    int start_cycle;
    int measured;
    bit active=0;
    bit aa;
    int threshold;
    function [15:0] source(input int x,input int y);
        return {5'((x*3+y*7)^(x<96 ? 0 : 31)),6'((x+y*5)^(y<17 ? 0 : 63)),5'(x*7+y*3)};
    endfunction
    function int component(input int c,input int k);
        if(k==0) return ((c>>11)&31)*8+((c>>13)&7);
        if(k==1) return ((c>>5)&63)*4+((c>>9)&3);
        return (c&31)*8+((c>>2)&7);
    endfunction
    function int light(input int c);
        return (component(c,0)+2*component(c,1)+component(c,2))>>2;
    endfunction
    function [15:0] expected(input int x,input int y);
        int colors[5];
        int ys[5];
        int low,high,a,b,r,g,bl;
        colors[0]=int'(source(x,y));
        colors[1]=int'(source(x,y==gy0 ? y : y-1));
        colors[2]=int'(source(x,y==gy1-1 ? y : y+1));
        colors[3]=int'(source(x==gx0 ? x : x-1,y));
        colors[4]=int'(source(x==gx1-1 ? x : x+1,y));
        for(int k=0;k<5;k++) ys[k]=light(colors[k]);
        low=ys[0]; high=ys[0];
        for(int k=1;k<5;k++) begin
            if(ys[k]<low) low=ys[k]; if(ys[k]>high) high=ys[k];
        end
        if(!aa || high-low<threshold) return 16'(colors[0]);
        if(((ys[1]>ys[2]) ? ys[1]-ys[2] : ys[2]-ys[1])
            >= ((ys[3]>ys[4]) ? ys[3]-ys[4] : ys[4]-ys[3])) begin a=1;b=2;end
        else begin a=3;b=4;end
        r=(2*component(colors[0],0)+component(colors[a],0)+component(colors[b],0))>>2;
        g=(2*component(colors[0],1)+component(colors[a],1)+component(colors[b],1))>>2;
        bl=(2*component(colors[0],2)+component(colors[a],2)+component(colors[b],2))>>2;
        return {5'(r>>3),6'(g>>2),5'(bl>>3)};
    endfunction
    always @(negedge clk_i) begin
        if(active) begin
            cycle++;
            resolve_read_ready_i=cycle%9!=0;
            resolve_color_valid_i=qh<qt && due[qh]<=cycle;
            for(int k=0;k<4;k++) resolve_color_data_i[k*16+:16]=
                source(tx+(addr[qh]%tw)*4+k,ty+addr[qh]/tw);
            write_req_ready_i=cycle%7!=0;
            write_data_ready_i=cycle%11!=0;
            write_done_i=(cycle==b_due);
        end
    end
    always @(posedge clk_i) begin
        if(rst_n_i && active) begin
            if(resolve_read_valid_o && resolve_read_ready_i) begin
                addr[qt]=int'(resolve_read_addr_o); due[qt]=cycle+5; qt++;
            end
            if(resolve_color_valid_i && resolve_color_ready_o) qh++;
            if(write_req_valid_o && write_req_ready_i) begin
                if(write_req_addr_o !== 32'('h100000+row*stride+2*gx0)
                    || write_req_bytes_o !== 32'(2*(gx1-gx0)))
                    $fatal(1,"FAIL Surface row %0d addr=%x bytes=%0d",row,write_req_addr_o,write_req_bytes_o);
                beat=0;
            end
            if(write_data_valid_o && write_data_ready_i) begin
                for(int k=0;k<16;k++) begin
                    if(write_data_data_o[k*16+:16] !== expected(gx0+16*beat+k,row))
                        $fatal(1,"FAIL resolve x=%0d y=%0d expected=%x actual=%x",gx0+16*beat+k,
                            row,expected(gx0+16*beat+k,row),write_data_data_o[k*16+:16]);
                end
                if(write_data_keep_o!==32'hffffffff
                    || write_data_last_o !== (16*(beat+1)==gx1-gx0)) $fatal(1,"FAIL packing");
                beat++;
                if(write_data_last_o) begin row++; b_due=cycle+8; end
            end
        end
    end
    task run_case(input bit wide,input bit filter_on,input int th,input bit full_size,input bit abort_run=0);
        gx0=full_size ? 0 : 64; gx1=full_size ? 640 : 128;
        gy0=full_size ? 0 : 15; gy1=full_size ? 180 : 19;
        tx=full_size ? 0 : 20; ty=full_size ? 0 : 10;
        tw=wide ? 320 : 160; stride=wide ? 2816 : 1536;
        aa=filter_on; threshold=th; row=gy0; qh=0;qt=0; b_due=-1;
        @(negedge clk_i); active=1; finish_i=0;stop_i=0;
        tick(); @(negedge clk_i);
        resolve_command_i=0; resolve_target_i=0;
        resolve_command_i[32]=aa; resolve_command_i[47:40]=8'(th);
        resolve_command_i[95:76]=20'h100; resolve_command_i[111:101]=11'(stride>>5);
        resolve_command_i[143:128]=16'(gx0); resolve_command_i[159:144]=16'(gy0);
        resolve_command_i[175:160]=16'(gx1); resolve_command_i[191:176]=16'(gy1);
        resolve_target_i[47:32]=16'(tx); resolve_target_i[63:48]=16'(ty);
        resolve_wide_i=wide; resolve_valid_i=1; start_cycle=cycle;
        do tick(); while(!resolve_ready_o && !perf_resolve_busy_o);
        @(negedge clk_i); resolve_valid_i=0; finish_i=1;
        wait(unit_done_o); tick(); measured=cycle-start_cycle;
        if(row!=(abort_run?gy0+1:gy1) || qh!=qt) $fatal(1,"FAIL resolve drain rows=%0d",row);
        if(full_size && measured>45000) $fatal(1,"FAIL resolve AA budget cycles=%0d",measured);
        $display("resolve wide=%0d AA=%0d threshold=%0d cycles=%0d",wide,aa,th,measured);
    endtask
    initial begin
        reset();
        run_case(0,0,0,0);
        run_case(0,1,24,0);
        run_case(1,1,0,0);
        run_case(1,1,255,0);
        fork
            run_case(0,1,24,0,1);
            begin
                do begin @(posedge clk_i); end while(!(write_req_valid_o && write_req_ready_i));
                @(negedge clk_i);stop_i=1;
            end
        join
        @(negedge clk_i);stop_i=0;finish_i=0;tick();
        @(negedge clk_i);resolve_command_i[175:160]=resolve_command_i[143:128];
        resolve_valid_i=1;tick();@(negedge clk_i);resolve_valid_i=0;finish_i=1;
        wait(unit_done_o);tick();
        if(write_req_valid_o || resolve_read_valid_o) $fatal(1,"FAIL empty resolve");
        run_case(0,1,24,1);
        $display("PASS gpu_resolve formula/boundary/shapes/offset/stride/AA budget"); $finish;
    end
endmodule
