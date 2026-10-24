`timescale 1ns/1ps
`include "edrv32_pair.vh"
// CASEID: delayed Load/Store bus fault, IRQ before Load/Store, misaligned
// Load, ROM Store fault. The trap handler resumes at B for synchronous faults,
// and at A for interrupts. B must modify architectural state exactly once.
module tb_dual_memory_precise #(parameter CACHE_TEST=0);
    localparam [31:0] BASE=32'h80000000;
    localparam [31:0] PAIR_PC=BASE+32'd64;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0,irq_ext=0,irq_sent=0;
    integer case_id=0,cycles=0,traps=0,pair_issued=0,pair_replayed=0,b_retired=0;
    integer requests=0,target_requests=0,bus_wait=0,i;
    reg [31:0] rom[0:127];
    wire imem_req_valid,imem_req_ready,imem_resp_ready;
    wire [31:0] imem_req_addr;
    reg imem_resp_valid=0;
    reg [31:0] imem_data=0,imem_upper=0;
    wire dmem_req_valid,dmem_req_we,dmem_resp_ready;
    wire [31:0] dmem_req_addr,dmem_req_data;
    wire [3:0] dmem_req_strb;
    reg dmem_resp_valid=0,dmem_error=0,bus_pending=0;
    reg [31:0] bus_addr=0;
    reg bus_write=0;
    reg pass_store=0;
    wire lookup_valid,lookup_store,lookup_resp_ready,lookup_cancel;
    wire [31:0] lookup_addr;
    wire [2:0] lookup_token;
    reg lookup_pending=0,lookup_resp_valid=0,lookup_resp_error=0;
    reg [2:0] lookup_resp_token=0;
    reg lookup_resp_store=0;
    reg [31:0] lookup_saved_addr=0;
    integer lookup_wait=0,target_lookups=0;
    wire lookup_ready=!lookup_pending&&!lookup_resp_valid;
    wire retire,second_retire,trap;
    wire [31:0] retire_pc,retire_instr,trap_cause;
    wire [1:0] retire_count;
    wire dmem_ready=!bus_pending&&!dmem_resp_valid;
    wire irq_case=(case_id==2 || case_id==3);
    wire store_case=(case_id==1 || case_id==3 || case_id==5);
    assign imem_req_ready=!imem_resp_valid||imem_resp_ready;
    function automatic [31:0] enc_i;
        input [11:0] imm; input [4:0] rs1; input [2:0] f3;
        input [4:0] rd; input [6:0] opcode;
        begin enc_i={imm,rs1,f3,rd,opcode};end
    endfunction
    function automatic [31:0] enc_s;
        input [11:0] imm;input [4:0] rs2,rs1;
        begin enc_s={imm[11:5],rs2,rs1,3'd2,imm[4:0],7'h23};end
    endfunction
    function automatic [31:0] csr;
        input [11:0] addr;input [4:0] source,dest;input [2:0] f3;
        begin csr={addr,source,f3,dest,7'h73};end
    endfunction
    edrv32_core #(.RESET_PC(BASE),.DUAL_ISSUE(1),.FETCH_WIDE(1),.CACHE_ENABLE(CACHE_TEST)) u_core (
        .clk_i(clk),.rst_n_i(rst_n),
        .imem_req_words_i(2'd2),.imem_resp_upper_i(imem_upper),.imem_preview_upper_i(32'd0),
        .imem_req_valid_o(imem_req_valid),.imem_req_ready_i(imem_req_ready),
        .imem_req_addr_o(imem_req_addr),.imem_resp_valid_i(imem_resp_valid),
        .imem_resp_ready_o(imem_resp_ready),.imem_resp_rdata_i(imem_data),.imem_resp_error_i(1'b0),
        .imem_preview_valid_i(1'b0),.imem_preview_addr_i(32'd0),.imem_preview_data_i(32'd0),
        .dmem_req_valid_o(dmem_req_valid),.dmem_req_ready_i(dmem_ready),
        .dmem_req_addr_o(dmem_req_addr),.dmem_req_we_o(dmem_req_we),
        .dmem_req_size_o(),.dmem_req_wstrb_o(dmem_req_strb),.dmem_req_wdata_o(dmem_req_data),
        .dmem_req_cacheable_o(),.dmem_resp_valid_i(dmem_resp_valid),
        .dmem_resp_ready_o(dmem_resp_ready),.dmem_resp_rdata_i(32'h31415926),
        .dmem_resp_error_i(dmem_error),
        .dcache_lookup_valid_o(lookup_valid),.dcache_lookup_ready_i(lookup_ready),
        .dcache_lookup_addr_o(lookup_addr),.dcache_lookup_token_o(lookup_token),
        .dcache_lookup_store_o(lookup_store),.dcache_lookup_resp_valid_i(lookup_resp_valid),
        .dcache_lookup_resp_ready_o(lookup_resp_ready),.dcache_lookup_resp_data_i(32'h31415926),
        .dcache_lookup_resp_error_i(lookup_resp_error),.dcache_lookup_resp_token_i(lookup_resp_token),
        .dcache_lookup_resp_store_i(lookup_resp_store),.dcache_lookup_cancel_o(lookup_cancel),
        .dcache_lookup_fast_valid_i(1'b0),.dcache_lookup_fast_data_i(32'd0),
        .dcache_lookup_fast_store_i(1'b0),.dcache_lookup_fast_token_i(3'd0),
        .cache_perf_events_i(5'd0),.irq_soft_i(1'b0),.irq_timer_i(1'b0),.irq_ext_i(irq_ext),
        .time_value_i(64'd0),.retire_o(retire),.retire_pc_o(retire_pc),.retire_instr_o(retire_instr),
        .retire_exception_o(trap),.retire_cause_o(trap_cause),.retire_count_o(retire_count),
        .second_retire_o(second_retire),.second_retire_pc_o(),.second_retire_instr_o(),.fencei_retire_o()
    );
    always @(posedge clk) begin
        if(!rst_n)imem_resp_valid<=0;
        else if(imem_req_ready)begin
            imem_resp_valid<=imem_req_valid;
            if(imem_req_valid)begin
                imem_data<=rom[(imem_req_addr-BASE)>>2];
                imem_upper<=rom[((imem_req_addr-BASE)>>2)+1];
            end
        end else if(imem_resp_valid&&imem_resp_ready)imem_resp_valid<=0;
        if(rst_n)begin
            if(lookup_resp_valid&&lookup_resp_ready)lookup_resp_valid<=0;
            if(lookup_valid&&lookup_ready)begin
                lookup_pending<=1;lookup_wait<=12;lookup_saved_addr<=lookup_addr;
                lookup_resp_token<=lookup_token;lookup_resp_store<=lookup_store;
                if(lookup_addr==BASE+32'h600)target_lookups=target_lookups+1;
            end
            if(lookup_pending)begin
                if(lookup_wait!=0)lookup_wait<=lookup_wait-1;
                else begin
                    lookup_pending<=0;lookup_resp_valid<=1;
                    lookup_resp_error<=!irq_case&&(case_id<2)&&(lookup_saved_addr==BASE+32'h600);
                end
            end
            // This lookup model has no architectural writes. A stream kill
            // cancels its speculative response, as the real cache does.
            if(lookup_cancel)begin lookup_pending<=0;lookup_resp_valid<=0;end
            if(dmem_resp_valid&&dmem_resp_ready)dmem_resp_valid<=0;
            if(dmem_req_valid&&dmem_ready)begin
                requests=requests+1;bus_pending<=1;bus_wait<=12;
                bus_addr<=dmem_req_addr;bus_write<=dmem_req_we;
                if(dmem_req_addr==BASE+32'h600)begin
                    target_requests=target_requests+1;
                    if(dmem_req_we && (dmem_req_data!=7 || dmem_req_strb!=4'hf))
                        $fatal(1,"Store source changed by younger B");
                end else if(dmem_req_addr==BASE+32'h700)begin
                    if(!dmem_req_we||dmem_req_data!=2)$fatal(1,"B forwarding result mismatch");
                    pass_store=1;
                end else $fatal(1,"Fault leaked an unexpected request addr=%08x",dmem_req_addr);
            end
            if(bus_pending)begin
                if(bus_wait!=0)bus_wait<=bus_wait-1;
                else begin
                    bus_pending<=0;dmem_resp_valid<=1;
                    dmem_error<=!irq_case&&(case_id<2)&&(bus_addr==BASE+32'h600);
                end
            end
        end
    end
    initial begin
        if(!$value$plusargs("CASEID=%d",case_id))case_id=0;
        #1; // Settle the test configuration before constructing its ROM image.
        for(i=0;i<128;i=i+1)rom[i]=32'h00000013;
        rom[0]=32'h80000437; // x8 data base
        rom[1]=enc_i(12'h100,8,0,1,7'h13);
        rom[2]=csr(12'h305,1,0,1); // direct mtvec
        rom[3]=32'h00001137;
        rom[4]=enc_i(12'h800,2,0,2,7'h13);
        rom[5]=csr(12'h304,2,0,1);
        rom[6]=enc_i(8,0,0,2,7'h13);
        rom[7]=csr(12'h300,2,0,1);
        rom[8]=enc_i(7,0,0,11,7'h13);
        rom[16]=store_case?enc_s(case_id==5?0:12'h600,11,case_id==5?0:8):
            enc_i(case_id==4?12'h601:12'h600,8,2,12,7'h03);
        rom[17]=enc_i(1,10,0,10,7'h13);
        rom[18]=enc_i(1,10,0,13,7'h13);
        rom[19]=enc_s(12'h700,13,8);
        rom[20]=32'h0000006f;
        rom[64]=csr(12'h341,0,14,2);
        rom[65]=enc_i(irq_case?0:4,14,0,14,7'h13);
        rom[66]=csr(12'h341,14,0,1);
        rom[67]=32'h30200073;
        repeat(4)@(negedge clk);rst_n=1;
    end
    always @(negedge clk)if(rst_n && irq_case && !irq_sent &&
        u_core.mem2_hazard_valid_w && u_core.mem2_hazard_pc_w==PAIR_PC &&
        u_core.mem2_second_w[`EDRV32_PAIR_RESULT_W-1])begin
        irq_ext=1;irq_sent=1;
    end
    always @(posedge clk)if(rst_n)begin
        cycles=cycles+1;
        if(u_core.u_decode_stage.pair_accept_w && u_core.align_pc_w==PAIR_PC)
            pair_issued=pair_issued+1;
        if(trap)begin
            traps=traps+1;
            $display("MEM_TRAP case=%0d pc=%08x instr=%08x expected=%08x cause=%08x pair=%b issued=%0d",
                case_id,retire_pc,retire_instr,rom[16],trap_cause,
                u_core.commit_second_w[`EDRV32_PAIR_RESULT_W-1],pair_issued);
            if(retire_pc!=PAIR_PC||retire_count!=0||u_core.commit_second_write_w||
                u_core.commit_gpr_write_w||u_core.u_decode_stage.u_regfile.regs_r[10]!=0)
                $fatal(1,"Memory trap exposed B or lost precise A pc=%08x case=%0d",retire_pc,case_id);
            if(case_id<4 && !u_core.commit_second_w[`EDRV32_PAIR_RESULT_W-1])
                $fatal(1,"Late memory fault/IRQ did not exercise a retained B");
            if(trap_cause!=(irq_case?32'h8000000b:case_id==4?4:store_case?7:5))
                $fatal(1,"Wrong memory pair trap cause=%08x",trap_cause);
            irq_ext=0;
        end
        if(retire && retire_pc==PAIR_PC && second_retire)pair_replayed=pair_replayed+1;
        if(retire && retire_pc==PAIR_PC+4)b_retired=b_retired+1;
        if(second_retire && u_core.second_retire_pc_o==PAIR_PC+4)b_retired=b_retired+1;
        // Cached stores may retire before their committed buffer drains.
        // Wait for the observed store side effect before ending the test.
        if(retire && retire_pc==BASE+80 && pass_store)begin
            if(traps!=1||pair_issued==0||b_retired!=1||!pass_store||
                u_core.u_decode_stage.u_regfile.regs_r[10]!=1 ||
                (irq_case&&(pair_replayed!=1||
                    target_requests!=((CACHE_TEST!=0&&!store_case)?0:1)))||
                (CACHE_TEST!=0&&case_id<4&&target_lookups==0)||
                (case_id>=4&&target_requests!=0))
                $fatal(1,"Precise memory pairing coverage failed case=%0d traps=%0d issued=%0d replay=%0d B=%0d requests=%0d",
                    case_id,traps,pair_issued,pair_replayed,b_retired,target_requests);
            $display("PASS: precise memory/ALU cached=%0d case=%0d cycles=%0d traps=%0d issued=%0d paired_replay=%0d B=%0d",
                CACHE_TEST,case_id,cycles,traps,pair_issued,pair_replayed,b_retired);
            $finish;
        end
        if(cycles>3000)$fatal(1,"Memory precise timeout case=%0d pc=%08x",case_id,retire_pc);
    end
endmodule
