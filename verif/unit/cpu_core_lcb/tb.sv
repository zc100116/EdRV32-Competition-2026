// File: cpu_core_lcb/tb.sv
// Spec: cpu-spec 4.4, 4.11.
// Description: Exercise six load-compare conditions, one/two dependent operands,
//              delayed load responses and registered M-stage redirects.
// Clock: clk_sys.
`timescale 1ns/1ps
module tb;
    reg clk_i=0;
    always #5 clk_i=~clk_i;
    reg rst_n_i=0;
    wire ic_req_valid;
    wire [31:0] ic_req_addr;
    reg ic_resp_valid=0;
    reg [63:0] ic_resp_data;
    wire ic_kill;
    wire unused_ic_inv;
    wire dc_req_valid;
    wire [31:0] dc_req_addr;
    wire dc_req_store;
    wire [1:0] unused_dc_size;
    wire dc_commit;
    wire dc_kill;
    wire [31:0] dc_store_data;
    wire unused_dc_fence;
    wire unused_dc_clean;
    wire unused_early_valid;
    wire [31:0] unused_early_addr;
    wire [63:0] unused_debug;
    reg pending=0;
    reg pending_store;
    reg pending_way;
    reg [31:0] pending_addr;
    integer delay_left=0;
    integer load_count=0;
    integer cycles=0;
    integer done_cycle=0;
    reg [7:0] conditions_seen=0;
    integer m_redirects=0;
    integer killed_stores=0;
    reg [31:0] rom[0:255];
    localparam EXPECTED = 9; // Filled by the test-program generator below.
    edrv32_cpu_core dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .rst_sys_csr_n_i(rst_n_i),
        .rst_sys_counter_n_i({10{rst_n_i}}),
        .ic_req_valid_o(ic_req_valid),
        .ic_req_addr_o(ic_req_addr),
        .ic_req_ready_i(1'b1),
        .ic_resp_valid_i(ic_resp_valid),
        .ic_resp_data_i(ic_resp_data),
        .ic_resp_err_i(1'b0),
        .ic_kill_o(ic_kill),
        .ic_inv_o(unused_ic_inv),
        .ic_inv_done_i(1'b1),
        .dc_req_valid_o(dc_req_valid),
        .dc_req_addr_o(dc_req_addr),
        .dc_req_store_o(dc_req_store),
        .dc_req_size_o(unused_dc_size),
        .dc_req_ready_i(!pending || delay_left==0),
        .dc_resp_valid_i(pending && delay_left==0),
        .dc_resp_way_data_i(pending_way ? 64'h0000000100000000 : 64'd1),
        .dc_resp_way_hit_i(pending_way ? 2'b10 : 2'b01),
        .dc_resp_err_i(1'b0),
        .dc_resp_device_i(1'b0),
        .dc_kill_o(dc_kill),
        .dc_commit_o(dc_commit),
        .dc_store_data_o(dc_store_data),
        .dc_fence_o(unused_dc_fence),
        .dc_clean_all_o(unused_dc_clean),
        .dc_fence_done_i(1'b1),
        .dc_wb_event_i(1'b0),
        .dc_early_valid_o(unused_early_valid),
        .dc_early_addr_o(unused_early_addr),
        .dc_early_way_hit_i(2'b0),
        .dc_early_way_data_i(64'b0),
        .irq_meip_i(1'b0),
        .irq_msip_i(1'b0),
        .irq_mtip_i(1'b0),
        .mtime_i(64'b0),
        .debug_o(unused_debug)
    );
    always @(posedge clk_i) begin
        if (rst_n_i) begin
            cycles=cycles+1;
            ic_resp_valid<=ic_req_valid && !ic_kill;
            if (ic_req_valid)
                ic_resp_data<={rom[ic_req_addr[9:2]+1],rom[ic_req_addr[9:2]]};
            if (pending && delay_left!=0) delay_left<=delay_left-1;
            else if (pending) pending<=0;
            if (dc_kill) begin
                pending<=0;
                if (pending_store) killed_stores=killed_stores+1;
            end
            if (dc_req_valid && (!pending || delay_left==0)) begin
                pending<=1; pending_store<=dc_req_store; pending_addr<=dc_req_addr;
                pending_way<=load_count[0];
                delay_left<=dc_req_store ? 0 : (load_count%3==0 ? 3 : 0);
                if (!dc_req_store) load_count<=load_count+1;
            end
            for (int lane=0;lane<2;lane++)
                if (dut.e_valid_r[lane] && dut.e_lcb_r[lane])
                    conditions_seen[dut.e_record_r[lane][46:44]]=1;
            if (dut.trace_redirect_stage_w==3 && dut.trace_redirect_cause_w!=0)
                m_redirects=m_redirects+1;
            if (dut.trace_trap_w) $fatal(1,"FAIL LCB trap cause=%h",dut.trace_cause_w);
            if (dc_commit && pending_store && pending_addr!=1024)
                $fatal(1,"FAIL wrong-path store committed address=%h",pending_addr);
            if (dc_commit && pending_store && pending_addr==1024) begin
                if (dc_store_data!=EXPECTED)
                    $fatal(1,"FAIL LCB result expected=%0d actual=%0d",EXPECTED,dc_store_data);
                done_cycle=cycles;
            end
            if (done_cycle!=0 && cycles>=done_cycle+4) begin
                if (conditions_seen!=8'b11110011 || m_redirects==0 || killed_stores==0)
                    $fatal(1,"FAIL LCB coverage conditions=%b redirects=%0d",
                        conditions_seen,m_redirects);
                $display("PASS LCB conditions=%b redirects=%0d cycles=%0d",
                    conditions_seen,m_redirects,cycles);
                $finish;
            end
            if (cycles>4000) $fatal(1,"FAIL LCB timeout pc=%h",dut.trace_pc_w);
        end
    end
    initial begin
        for (int i=0;i<256;i++) rom[i]=32'h00000013;
        rom[0]=32'h00000513;
        rom[1]=32'h00200193;
        rom[2]=32'h10000093;
        rom[3]=32'h0000a103;
        rom[4]=32'h00310663;
        rom[5]=32'h34002073;
        rom[6]=32'h00150513;
        rom[7]=32'h00200193;
        rom[8]=32'h10000093;
        rom[9]=32'h0000a103;
        rom[10]=32'h00218663;
        rom[11]=32'h34002073;
        rom[12]=32'h00150513;
        rom[13]=32'h00200193;
        rom[14]=32'h10000093;
        rom[15]=32'h0000a103;
        rom[16]=32'h00210663;
        rom[17]=32'h34002073;
        rom[18]=32'h01050513;
        rom[19]=32'h00200193;
        rom[20]=32'h10000093;
        rom[21]=32'h0000a103;
        rom[22]=32'h00311663;
        rom[23]=32'h34002073;
        rom[24]=32'h01050513;
        rom[25]=32'h00200193;
        rom[26]=32'h10000093;
        rom[27]=32'h0000a103;
        rom[28]=32'h00219663;
        rom[29]=32'h34002073;
        rom[30]=32'h01050513;
        rom[31]=32'h00200193;
        rom[32]=32'h10000093;
        rom[33]=32'h0000a103;
        rom[34]=32'h00211663;
        rom[35]=32'h34002073;
        rom[36]=32'h00150513;
        rom[37]=32'h00200193;
        rom[38]=32'h10000093;
        rom[39]=32'h0000a103;
        rom[40]=32'h00314663;
        rom[41]=32'h34002073;
        rom[42]=32'h01050513;
        rom[43]=32'h00200193;
        rom[44]=32'h10000093;
        rom[45]=32'h0000a103;
        rom[46]=32'h0021c663;
        rom[47]=32'h34002073;
        rom[48]=32'h00150513;
        rom[49]=32'h00200193;
        rom[50]=32'h10000093;
        rom[51]=32'h0000a103;
        rom[52]=32'h00214663;
        rom[53]=32'h34002073;
        rom[54]=32'h00150513;
        rom[55]=32'h00200193;
        rom[56]=32'h10000093;
        rom[57]=32'h0000a103;
        rom[58]=32'h00315663;
        rom[59]=32'h34002073;
        rom[60]=32'h00150513;
        rom[61]=32'h00200193;
        rom[62]=32'h10000093;
        rom[63]=32'h0000a103;
        rom[64]=32'h0021d663;
        rom[65]=32'h34002073;
        rom[66]=32'h01050513;
        rom[67]=32'h00200193;
        rom[68]=32'h10000093;
        rom[69]=32'h0000a103;
        rom[70]=32'h00215663;
        rom[71]=32'h34002073;
        rom[72]=32'h01050513;
        rom[73]=32'h00200193;
        rom[74]=32'h10000093;
        rom[75]=32'h0000a103;
        rom[76]=32'h00316663;
        rom[77]=32'h34002073;
        rom[78]=32'h01050513;
        rom[79]=32'h00200193;
        rom[80]=32'h10000093;
        rom[81]=32'h0000a103;
        rom[82]=32'h0021e663;
        rom[83]=32'h34002073;
        rom[84]=32'h00150513;
        rom[85]=32'h00200193;
        rom[86]=32'h10000093;
        rom[87]=32'h0000a103;
        rom[88]=32'h00216663;
        rom[89]=32'h34002073;
        rom[90]=32'h00150513;
        rom[91]=32'h00200193;
        rom[92]=32'h10000093;
        rom[93]=32'h0000a103;
        rom[94]=32'h00317663;
        rom[95]=32'h34002073;
        rom[96]=32'h00150513;
        rom[97]=32'h00200193;
        rom[98]=32'h10000093;
        rom[99]=32'h0000a103;
        rom[100]=32'h0021f663;
        rom[101]=32'h34002073;
        rom[102]=32'h01050513;
        rom[103]=32'h00200193;
        rom[104]=32'h10000093;
        rom[105]=32'h0000a103;
        rom[106]=32'h00217663;
        rom[107]=32'h34002073;
        rom[108]=32'h01050513;
        rom[109]=32'h10000093;
        rom[110]=32'h0000a103;
        rom[111]=32'h0040a203;
        rom[112]=32'h00210663;
        rom[113]=32'h00a0a023;
        rom[114]=32'hffffffff;
        rom[115]=32'h40000093;
        rom[116]=32'h00a0a023;
        rom[117]=32'h0000006f;
        repeat(4) @(negedge clk_i);
        rst_n_i=1;
    end
endmodule
