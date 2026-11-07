// File: tb.sv; Spec: cpu-testplan v0.7 B-13; Clock: clk_sys.
// Exercise the real frontend and I-cache with delayed AXI and a stalled decoder.
module tb;
    reg clk_i=0;
    always #5 clk_i<=~clk_i;
    reg rst_n_i=0;
    reg redirect_valid_i=0;
    wire [16:0] redirect_valid_copy_i;
    reg [31:0] redirect_pc_i=0;
    reg [36:0] redirect_ras_i=0;
    reg redirect_push_i=0;
    reg redirect_pop_i=0;
    reg [31:0] redirect_return_pc_i=0;
    reg d_redirect_valid_i=0;
    reg d_redirect_slot_i=0;
    reg [31:0] d_redirect_pc_i=0;
    reg [36:0] d_redirect_ras_i=0;
    reg d_redirect_push_i=0;
    reg d_redirect_pop_i=0;
    reg [31:0] d_redirect_return_pc_i=0;
    reg halt_i=0;
    reg update_valid_i=0;
    reg update_clear_i=0;
    reg [6:0] update_clear_index_i=0;
    reg [31:0] update_pc_i=0;
    reg [31:0] update_target_i=0;
    reg [2:0] update_type_i=0;
    reg update_taken_i=0;
    reg [11:0] update_index_i=0;
    reg [11:0] update_tournament_i=0;
    reg [1:0] decode_pop_count_i=0;
    wire [357:0] decode_data_o;
    wire [5:0] decode_index_hi_o;
    wire [23:0] decode_tournament_o;
    wire [79:0] decode_operand_addr_o;
    wire [1:0] decode_valid_count_o;
    wire [2:0] ib_count_o;
    wire ic_req_valid_o;
    wire [31:0] ic_req_addr_o;
    wire ic_req_ready_i;
    wire ic_resp_valid_i;
    wire [7:0] ic_resp_valid_copy_i;
    wire [63:0] ic_resp_data_i;
    wire ic_resp_err_i;
    wire ic_kill_o;
    reg invalidate_i=0;
    wire invalidate_done_o;
    wire ic_inv_o;
    wire ic_inv_done_i;
    wire f1_valid_o;
    wire f2_valid_o;
    wire fetch_wait_o;
    wire [3:0] axi_arid_o;
    wire [31:0] axi_araddr_o;
    wire [7:0] axi_arlen_o;
    wire [2:0] axi_arsize_o;
    wire [1:0] axi_arburst_o;
    wire axi_arvalid_o;
    wire axi_arready_i;
    wire [3:0] axi_rid_i;
    wire [63:0] axi_rdata_i;
    wire [1:0] axi_rresp_i;
    wire axi_rlast_i;
    wire axi_rvalid_i;
    wire axi_rready_o;
    edrv32_cpu_frontend u_frontend (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .redirect_valid_i(redirect_valid_i),
        .redirect_valid_copy_i(redirect_valid_copy_i),
        .redirect_pc_i(redirect_pc_i),
        .redirect_ras_i(redirect_ras_i),
        .redirect_push_i(redirect_push_i),
        .redirect_pop_i(redirect_pop_i),
        .redirect_return_pc_i(redirect_return_pc_i),
        .d_redirect_valid_i(d_redirect_valid_i),
        .d_redirect_slot_i(d_redirect_slot_i),
        .d_redirect_pc_i(d_redirect_pc_i),
        .d_redirect_ras_i(d_redirect_ras_i),
        .d_redirect_push_i(d_redirect_push_i),
        .d_redirect_pop_i(d_redirect_pop_i),
        .d_redirect_return_pc_i(d_redirect_return_pc_i),
        .halt_i(halt_i),
        .update_valid_i(update_valid_i),
        .update_clear_i(update_clear_i),
        .update_clear_index_i(update_clear_index_i),
        .update_pc_i(update_pc_i),
        .update_target_i(update_target_i),
        .update_type_i(update_type_i),
        .update_taken_i(update_taken_i),
        .update_index_i(update_index_i),
        .update_tournament_i(update_tournament_i),
        .decode_pop_count_i(decode_pop_count_i),
        .decode_predecode_o(),
        .decode_data_o(decode_data_o),
        .decode_index_hi_o(decode_index_hi_o),
        .decode_tournament_o(decode_tournament_o),
        .decode_operand_addr_o(decode_operand_addr_o),
        .decode_valid_count_o(decode_valid_count_o),
        .ib_count_o(ib_count_o),
        .ic_req_valid_o(ic_req_valid_o),
        .ic_req_addr_o(ic_req_addr_o),
        .ic_req_ready_i(ic_req_ready_i),
        .ic_resp_valid_i(ic_resp_valid_i),
        .ic_resp_valid_copy_i(ic_resp_valid_copy_i),
        .ic_resp_data_i(ic_resp_data_i),
        .ic_resp_err_i(ic_resp_err_i),
        .ic_kill_o(ic_kill_o),
        .invalidate_i(invalidate_i),
        .invalidate_done_o(invalidate_done_o),
        .ic_inv_o(ic_inv_o),
        .ic_inv_done_i(ic_inv_done_i),
        .f1_valid_o(f1_valid_o),
        .f2_valid_o(f2_valid_o),
        .fetch_wait_o(fetch_wait_o)
    );
    edrv32_icache u_icache (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .rst_sys_ivalid0_n_i({2{rst_n_i}}),
        .rst_sys_ivalid1_n_i({2{rst_n_i}}),
        .rst_sys_ilru_n_i({2{rst_n_i}}),
        .ic_req_valid_i(ic_req_valid_o),
        .ic_req_addr_i(ic_req_addr_o),
        .ic_req_ready_o(ic_req_ready_i),
        .ic_resp_valid_o(ic_resp_valid_i),
        .ic_resp_valid_copy_o(ic_resp_valid_copy_i),
        .ic_resp_data_o(ic_resp_data_i),
        .ic_resp_err_o(ic_resp_err_i),
        .ic_kill_i(ic_kill_o),
        .ic_inv_i(ic_inv_o),
        .ic_inv_done_o(ic_inv_done_i),
        .axi_arid_o(axi_arid_o),
        .axi_araddr_o(axi_araddr_o),
        .axi_arlen_o(axi_arlen_o),
        .axi_arsize_o(axi_arsize_o),
        .axi_arburst_o(axi_arburst_o),
        .axi_arvalid_o(axi_arvalid_o),
        .axi_arready_i(axi_arready_i),
        .axi_rid_i(axi_rid_i),
        .axi_rdata_i(axi_rdata_i),
        .axi_rresp_i(axi_rresp_i),
        .axi_rlast_i(axi_rlast_i),
        .axi_rvalid_i(axi_rvalid_i),
        .axi_rready_o(axi_rready_o)
    );
    reg memory_active_r=0;
    reg [11:0] data_addr_r=0;
    reg [7:0] beats_left_r=0;
    integer delay_r=0;
    reg checking_r=0;
    reg drain_r=0;
    reg [31:0] expected_pc_r=0;
    integer checked_r=0;
    integer dropped_r=0;
    integer replayed_r=0;
    integer redirected_r=0;
    integer full_response_r=0;
    integer requests_r=0;
    reg await_replay_r=0;
    reg [31:0] dropped_pc_r=0;
    reg forbidden_valid_r=0;
    reg [31:0] forbidden_pc_r=0;
    assign redirect_valid_copy_i={17{redirect_valid_i}};
    wire discovery_w;
    wire unused_status_w;
    assign unused_status_w=&{1'b0,decode_data_o,decode_tournament_o,decode_index_hi_o,
        decode_operand_addr_o,f1_valid_o,f2_valid_o,fetch_wait_o,invalidate_done_o,
        axi_araddr_o};
    function automatic [31:0] instruction(input [11:0] offset);
        instruction={offset,20'h00013};
    endfunction
    assign axi_arready_i=!memory_active_r;
    assign axi_rvalid_i=memory_active_r && delay_r==0;
    assign axi_rdata_i={instruction(data_addr_r+12'd4),instruction(data_addr_r)};
    assign axi_rresp_i=0;
    assign axi_rid_i=0;
    assign axi_rlast_i=beats_left_r==0;
    assign discovery_w=u_icache.state_r==u_icache.S_IDLE && u_icache.lookup_valid_r &&
        !u_icache.pma_err_r && (!u_icache.cacheable_r || !u_icache.hit_w);
    always @(*) begin
        decode_pop_count_i=checking_r && drain_r ? decode_valid_count_o : 2'd0;
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if(!rst_n_i)begin
            memory_active_r<=0;delay_r<=0;
        end else begin
            if(axi_arvalid_o && axi_arready_i)begin
                if(axi_arid_o!=0 || axi_arsize_o!=3 || axi_arburst_o!=1 ||
                    axi_arlen_o!=(u_icache.cacheable_r?8'd3:8'd0))
                    $fatal(1,"FAIL B13 AXI attributes");
                memory_active_r<=1;data_addr_r<=axi_araddr_o[11:0];
                beats_left_r<=axi_arlen_o;delay_r<=4;
            end else if(delay_r!=0)delay_r<=delay_r-1;
            else if(axi_rvalid_i && axi_rready_o)begin
                if(beats_left_r==0)memory_active_r<=0;
                else begin beats_left_r<=beats_left_r-1;data_addr_r<=data_addr_r+12'd8;end
            end
            if(integer'(ib_count_o)>4 || integer'(u_frontend.count_r)>4 ||
                integer'(u_frontend.credit_r)+integer'(ib_count_o)+
                integer'(u_frontend.count_r)+2*(integer'(u_frontend.f2_pending_r)+
                integer'(u_frontend.replay_valid_r))!=8)
                $fatal(1,"FAIL B13 storage credit=%0d IB=%0d F2=%0d owner=%b replay=%b",
                    u_frontend.credit_r,ib_count_o,u_frontend.count_r,
                    u_frontend.f2_pending_r,u_frontend.replay_valid_r);
            if(ic_resp_valid_copy_i !== {8{ic_resp_valid_i}})
                $fatal(1,"FAIL B13 response control copies");
            if(redirect_valid_i)begin
                await_replay_r<=0;
                if(u_icache.state_r!=u_icache.S_IDLE)redirected_r<=redirected_r+1;
            end else begin
                if(ic_req_valid_o && ic_req_ready_i)begin
                    requests_r<=requests_r+1;
                    if(forbidden_valid_r && ic_req_addr_o==forbidden_pc_r)
                        $fatal(1,"FAIL B13 stale replay=%h",ic_req_addr_o);
                    if(await_replay_r && ic_req_addr_o==dropped_pc_r)begin
                        replayed_r<=replayed_r+1;await_replay_r<=0;
                    end
                    if(discovery_w)begin
                        dropped_r<=dropped_r+1;dropped_pc_r<=ic_req_addr_o;await_replay_r<=1;
                        if(ic_resp_valid_i)$fatal(1,"FAIL B13 discovery also responded");
                    end
                end
                if(checking_r)begin
                    for(int lane=0;lane<integer'(decode_pop_count_i);lane++)begin
                        if(decode_data_o[lane*179 +: 32]!==expected_pc_r+32'(lane*4) ||
                            decode_data_o[lane*179+32 +: 32]!==
                            instruction(expected_pc_r[11:0]+12'(lane*4)) ||
                            decode_data_o[lane*179+64 +: 32]!==
                            instruction(expected_pc_r[11:0]+12'(lane*4)))
                            $fatal(1,"FAIL B13 stream expected PC=%h actual=%h time=%t",
                                expected_pc_r+32'(lane*4),
                                decode_data_o[lane*179 +: 32],$time);
                    end
                    expected_pc_r<=expected_pc_r+32'(decode_pop_count_i)*4;
                    checked_r<=checked_r+integer'(decode_pop_count_i);
                end
            end
            if(ic_resp_valid_i && u_frontend.f2_pending_r && ib_count_o==4)
                full_response_r<=full_response_r+1;
        end
    end
    task automatic start_case(input [31:0] pc,input bit stall);
        @(negedge clk_i);halt_i=1;drain_r=0;checking_r=0;
        redirect_valid_i=1;redirect_pc_i=pc;
        @(negedge clk_i);redirect_valid_i=0;halt_i=0;
        expected_pc_r=pc;checked_r=0;checking_r=1;drain_r=!stall;
    endtask
    task automatic finish_case(input integer minimum);
        integer cycles;
        cycles=0;
        while(checked_r<minimum)begin
            @(negedge clk_i);cycles++;
            if(cycles>2000)$fatal(1,"FAIL B13 timeout pc=%h",expected_pc_r);
        end
        @(negedge clk_i);halt_i=1;checking_r=0;drain_r=0;
    endtask
    task automatic redirected_miss(input [31:0] old_pc,input [31:0] target);
        start_case(old_pc,0);
        while(u_icache.state_r!=u_icache.S_FILL || u_icache.addr_r!=old_pc)
            @(negedge clk_i);
        if(!await_replay_r)$fatal(1,"FAIL B13 redirect lacked discarded successor");
        forbidden_pc_r=dropped_pc_r;forbidden_valid_r=1;
        start_case(target,0);finish_case(16);forbidden_valid_r=0;
    endtask
    initial begin
        halt_i=1;
        repeat(3)@(negedge clk_i);rst_n_i=1;
        start_case(32'h10000000,0);finish_case(24);
        if(dropped_r==0 || replayed_r==0)$fatal(1,"FAIL B13 cache replay coverage");
        start_case(32'h00000200,0);finish_case(12);
        // E and M share the older-redirect frontend contract; exercise both miss overlaps.
        redirected_miss(32'h80008000,32'h80010000);
        redirected_miss(32'h80018000,32'h80020000);
        start_case(32'h80028000,1);
        repeat(80)@(negedge clk_i);
        if(ib_count_o!=4 || u_frontend.count_r!=4 || u_frontend.credit_r!=0)
            $fatal(1,"FAIL B13 full storage IB=%0d F2=%0d credit=%0d",
                ib_count_o,u_frontend.count_r,u_frontend.credit_r);
        begin
            integer before_requests;
            before_requests=requests_r;
            repeat(10)@(negedge clk_i);
            if(requests_r!=before_requests)$fatal(1,"FAIL B13 full frontend issued request");
        end
        drain_r=1;finish_case(24);
        if(redirected_r<2 || full_response_r==0 || replayed_r<3)
            $fatal(1,"FAIL B13 coverage redirect=%0d full_response=%0d replay=%0d",
                redirected_r,full_response_r,replayed_r);
        $display("PASS B-13 dropped=%0d replayed=%0d redirect=%0d full_response=%0d",
            dropped_r,replayed_r,redirected_r,full_response_r);
        $finish;
    end
endmodule
