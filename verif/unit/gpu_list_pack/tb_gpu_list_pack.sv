// Self-checking gpu_list_pack unit test.
module tb_gpu_list_pack;
    logic clk_i = 0;
    logic rst_n_i = 0;
    logic pack_valid_i = 0;
    logic pack_ready_o;
    logic [255:0] pack_command_i = 0;
    logic [31:0] object_cfg_hit_base_i = 0;
    logic [23:0] object_cfg_hit_max_i = 0;
    logic [31:0] object_cfg_free_base_i = 0;
    logic [23:0] object_cfg_free_max_i = 0;
    logic object_update_valid_i = 0;
    logic object_update_ready_o;
    logic [23:0] object_update_idx_i = 0;
    logic [255:0] object_update_data_i = 0;
    logic object_event_valid_i = 0;
    logic object_event_ready_o;
    logic [23:0] object_event_idx_i = 0;
    logic [7:0] object_event_hit_i = 0;
    logic object_event_free_i = 0;
    logic object_write_req_valid_o;
    logic object_write_req_ready_i = 0;
    logic [31:0] object_write_req_addr_o;
    logic [31:0] object_write_req_bytes_o;
    logic object_write_data_valid_o;
    logic object_write_data_ready_i = 0;
    logic [255:0] object_write_data_data_o;
    logic [31:0] object_write_data_keep_o;
    logic object_write_data_last_o;
    logic object_write_done_i = 0;
    logic hit_write_req_valid_o;
    logic hit_write_req_ready_i = 0;
    logic [31:0] hit_write_req_addr_o;
    logic [31:0] hit_write_req_bytes_o;
    logic hit_write_data_valid_o;
    logic hit_write_data_ready_i = 0;
    logic [255:0] hit_write_data_data_o;
    logic [31:0] hit_write_data_keep_o;
    logic hit_write_data_last_o;
    logic hit_write_done_i = 0;
    logic free_write_req_valid_o;
    logic free_write_req_ready_i = 0;
    logic [31:0] free_write_req_addr_o;
    logic [31:0] free_write_req_bytes_o;
    logic free_write_data_valid_o;
    logic free_write_data_ready_i = 0;
    logic [255:0] free_write_data_data_o;
    logic [31:0] free_write_data_keep_o;
    logic free_write_data_last_o;
    logic free_write_done_i = 0;
    logic finish_i = 0;
    logic stop_i = 0;
    logic unit_done_o;
    always #5 clk_i = !clk_i;
    edrv32_gpu_list_pack u_dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .pack_valid_i(pack_valid_i),
        .pack_ready_o(pack_ready_o),
        .pack_command_i(pack_command_i),
        .object_cfg_hit_base_i(object_cfg_hit_base_i),
        .object_cfg_hit_max_i(object_cfg_hit_max_i),
        .object_cfg_free_base_i(object_cfg_free_base_i),
        .object_cfg_free_max_i(object_cfg_free_max_i),
        .object_update_valid_i(object_update_valid_i),
        .object_update_ready_o(object_update_ready_o),
        .object_update_idx_i(object_update_idx_i),
        .object_update_data_i(object_update_data_i),
        .object_event_valid_i(object_event_valid_i),
        .object_event_ready_o(object_event_ready_o),
        .object_event_idx_i(object_event_idx_i),
        .object_event_hit_i(object_event_hit_i),
        .object_event_free_i(object_event_free_i),
        .object_write_req_valid_o(object_write_req_valid_o),
        .object_write_req_ready_i(object_write_req_ready_i),
        .object_write_req_addr_o(object_write_req_addr_o),
        .object_write_req_bytes_o(object_write_req_bytes_o),
        .object_write_data_valid_o(object_write_data_valid_o),
        .object_write_data_ready_i(object_write_data_ready_i),
        .object_write_data_data_o(object_write_data_data_o),
        .object_write_data_keep_o(object_write_data_keep_o),
        .object_write_data_last_o(object_write_data_last_o),
        .object_write_done_i(object_write_done_i),
        .hit_write_req_valid_o(hit_write_req_valid_o),
        .hit_write_req_ready_i(hit_write_req_ready_i),
        .hit_write_req_addr_o(hit_write_req_addr_o),
        .hit_write_req_bytes_o(hit_write_req_bytes_o),
        .hit_write_data_valid_o(hit_write_data_valid_o),
        .hit_write_data_ready_i(hit_write_data_ready_i),
        .hit_write_data_data_o(hit_write_data_data_o),
        .hit_write_data_keep_o(hit_write_data_keep_o),
        .hit_write_data_last_o(hit_write_data_last_o),
        .hit_write_done_i(hit_write_done_i),
        .free_write_req_valid_o(free_write_req_valid_o),
        .free_write_req_ready_i(free_write_req_ready_i),
        .free_write_req_addr_o(free_write_req_addr_o),
        .free_write_req_bytes_o(free_write_req_bytes_o),
        .free_write_data_valid_o(free_write_data_valid_o),
        .free_write_data_ready_i(free_write_data_ready_i),
        .free_write_data_data_o(free_write_data_data_o),
        .free_write_data_keep_o(free_write_data_keep_o),
        .free_write_data_last_o(free_write_data_last_o),
        .free_write_done_i(free_write_done_i),
        .finish_i(finish_i),
        .stop_i(stop_i),
        .unit_done_o(unit_done_o)
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
        #2000000; $fatal(1, "FAIL timeout");
    end
    int cycle=0;
    bit active=0;
    int hit_expected[64];
    int free_expected[64];
    int hit_total=0,free_total=0;
    int hit_written=0,free_written=0,object_written=0;
    int pending_addr[3],pending_bytes[3],due[3];
    bit have_req[3];
    int requests[3];
    bit stall_object=0;
    function [255:0] object_data(input int idx);
        logic [255:0] result;
        for(int k=0;k<8;k++) result[k*32+:32]=32'(idx*12345+k*45678);
        return result;
    endfunction
    always @(negedge clk_i) if(active) begin
        cycle++;
        object_write_req_ready_i=cycle%5!=0;
        object_write_data_ready_i=cycle%7!=0 && !stall_object;
        object_write_done_i=due[0]>0 && cycle==due[0];
        hit_write_req_ready_i=cycle%5!=0;
        hit_write_data_ready_i=cycle%7!=0;
        hit_write_done_i=due[1]>0 && cycle==due[1];
        free_write_req_ready_i=cycle%5!=0;
        free_write_data_ready_i=cycle%7!=0;
        free_write_done_i=due[2]>0 && cycle==due[2];
    end
    always @(posedge clk_i) if(rst_n_i && active) begin
        if(object_write_req_valid_o && object_write_req_ready_i) begin
            if(have_req[0]) $fatal(1,"FAIL duplicate object interval");
            have_req[0]=1;pending_addr[0]=int'(object_write_req_addr_o);
            pending_bytes[0]=int'(object_write_req_bytes_o);requests[0]++;
        end
        if(object_write_data_valid_o && object_write_data_ready_i) begin
            if(!have_req[0] || !object_write_data_last_o) $fatal(1,"FAIL object sequencing");
            if(object_write_data_keep_o !== (32'hffffffff>>(32-pending_bytes[0])))
                $fatal(1,"FAIL object keep");
            if(pending_addr[0] != 'h10000+object_written*32 || pending_bytes[0]!=32
                || object_write_data_data_o!==object_data(object_written)) $fatal(1,"FAIL object preservation");
            object_written++;
            due[0]=cycle+12;
        end
        if(object_write_done_i) have_req[0]=0;
        if(hit_write_req_valid_o && hit_write_req_ready_i) begin
            if(have_req[1]) $fatal(1,"FAIL duplicate hit interval");
            have_req[1]=1;pending_addr[1]=int'(hit_write_req_addr_o);
            pending_bytes[1]=int'(hit_write_req_bytes_o);requests[1]++;
        end
        if(hit_write_data_valid_o && hit_write_data_ready_i) begin
            if(!have_req[1] || !hit_write_data_last_o) $fatal(1,"FAIL hit sequencing");
            if(hit_write_data_keep_o !== (32'hffffffff>>(32-pending_bytes[1])))
                $fatal(1,"FAIL hit keep");
            if(pending_addr[1]!='h20000+hit_written*4
                || pending_bytes[1]!=((13-hit_written>=8)?32:(13-hit_written)*4))
                $fatal(1,"FAIL hit interval");
            for(int j=0;j<pending_bytes[1]/4;j++) begin
                if(hit_write_data_data_o[j*32+:32]!==32'(hit_expected[hit_written]))
                    $fatal(1,"FAIL hit order index=%0d",hit_written);
                hit_written++;
            end
            due[1]=cycle+12;
        end
        if(hit_write_done_i) have_req[1]=0;
        if(free_write_req_valid_o && free_write_req_ready_i) begin
            if(have_req[2]) $fatal(1,"FAIL duplicate free interval");
            have_req[2]=1;pending_addr[2]=int'(free_write_req_addr_o);
            pending_bytes[2]=int'(free_write_req_bytes_o);requests[2]++;
        end
        if(free_write_data_valid_o && free_write_data_ready_i) begin
            if(!have_req[2] || !free_write_data_last_o) $fatal(1,"FAIL free sequencing");
            if(free_write_data_keep_o !== (32'hffffffff>>(32-pending_bytes[2])))
                $fatal(1,"FAIL free keep");
            if(pending_addr[2]!='h30000+free_written*4
                || pending_bytes[2]!=((3-free_written>=8)?32:(3-free_written)*4))
                $fatal(1,"FAIL free interval");
            for(int j=0;j<pending_bytes[2]/4;j++) begin
                if(free_write_data_data_o[j*32+:32]!==32'(free_expected[free_written]))
                    $fatal(1,"FAIL free order index=%0d",free_written);
                free_written++;
            end
            due[2]=cycle+12;
        end
        if(free_write_done_i) have_req[2]=0;
        if(unit_done_o && (have_req[0] || have_req[1] || have_req[2]))
            $fatal(1,"FAIL early pack completion");
    end
    task configure(input bit step);
        @(negedge clk_i);finish_i=0;stop_i=0;pack_command_i=0;
        pack_command_i[7:0]='h22;pack_command_i[32]=step;pack_command_i[95:69]=27'('h10000>>5);
        object_cfg_hit_base_i='h20000;object_cfg_hit_max_i=13;
        object_cfg_free_base_i='h30000;object_cfg_free_max_i=3;
        pack_valid_i=1;tick();@(negedge clk_i);pack_valid_i=0;
    endtask
    task event_send(input int idx,input int mask,input bit free_flag);
        @(negedge clk_i);object_event_valid_i=1;object_event_idx_i=24'(idx);
        object_event_hit_i=8'(mask);object_event_free_i=free_flag;
        for(int k=0;k<8;k++) if((mask&(1<<k))!=0) begin
            hit_expected[hit_total]=(k<<24)|idx;hit_total++;
        end
        if(free_flag) begin free_expected[free_total]=idx;free_total++;end
        do begin @(posedge clk_i); end while(!object_event_ready_o);
        @(negedge clk_i);object_event_valid_i=0;
    endtask
    task update_send(input int idx);
        @(negedge clk_i);object_update_valid_i=1;object_update_idx_i=24'(idx);
        object_update_data_i=object_data(idx);
        do begin @(posedge clk_i); end while(!object_update_ready_o);
        @(negedge clk_i);object_update_valid_i=0;
    endtask
    initial begin
        reset();active=1;configure(1);
        for(int i=0;i<12;i++) begin
            if(i<6) update_send(i);
            event_send(i, (i%3==0)?'h81:((i%3==1)?'h3:'h44),i%2==0);
        end
        @(negedge clk_i);finish_i=1;wait(unit_done_o);tick();
        if(hit_written!=13 || free_written!=3 || object_written!=6
            || requests[1]!=2 || requests[2]!=1) $fatal(1,"FAIL pack counts/capacity");
        configure(0);@(negedge clk_i);finish_i=1;wait(unit_done_o);tick();
        if(requests[0]!=6 || requests[1]!=2 || requests[2]!=1) $fatal(1,"FAIL STEP0");
        configure(1);stall_object=1;update_send(6);
        wait(object_write_data_valid_o);@(negedge clk_i);stop_i=1;repeat(5)tick();
        if(!object_write_data_valid_o || unit_done_o) $fatal(1,"FAIL stop discarded accepted data");
        @(negedge clk_i);stall_object=0;finish_i=1;wait(unit_done_o);tick();
        if(object_written!=7) $fatal(1,"FAIL stop drain");
        $display("PASS gpu_list_pack preservation/order/capacity/tail/STEP0/B fence/stop");$finish;
    end
endmodule
