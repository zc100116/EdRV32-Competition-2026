`timescale 1ns/1ps
`include "edrv32_bus.vh"
`include "edrv32_hpm.vh"
// Ordered instruction reference model. Both slots are checked independently.
module tb_dual_alu #(parameter MEMORY_STRESS=0);
    localparam [31:0] RESET_PC=32'h8000_0000;
    reg [8*512-1:0] wavefile;
    initial if($test$plusargs("WAVE"))begin
        if(!$value$plusargs("WAVEFILE=%s",wavefile))wavefile="sim/build/dual-alu.vcd";
        $dumpfile(wavefile);$dumpvars(0,tb_dual_alu);
    end
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0;
    wire imem_req_valid,imem_req_ready,imem_resp_ready;
    wire [31:0] imem_req_addr;
    reg imem_resp_valid=0;
    reg [31:0] imem_resp_rdata=0;
    wire imem_resp_error=0;
    wire dmem_req_valid,dmem_req_ready,dmem_req_we,dmem_resp_valid,dmem_resp_ready,dmem_resp_error;
    wire [31:0] dmem_req_addr,dmem_req_wdata,dmem_resp_rdata;
    wire [1:0] dmem_req_size;
    wire [3:0] dmem_req_wstrb;
    wire retire,second_retire,retire_exception;
    wire [31:0] retire_pc,retire_instr,second_pc,second_instr,retire_cause;
    wire [1:0] retire_count;
    reg [15:0] rom[0:8191];
    reg [31:0] program_pc[0:4095],program_instr[0:4095];
    reg program_c[0:4095];
    reg [31:0] gold[0:31];
    reg [31:0] gold_mem[0:511];
    integer load_pairs=0,store_pairs=0;
    integer count=0,halfwords=0,index=0,cycles=0,pairs=0,alu_count=0,c_count=0;
    integer resident_b1=0,resident_b2=0;
    integer b_lhs_a=0,b_rhs_a=0,b_lhs_b=0,b_rhs_b=0;
    integer steady_first=-1,steady_last=-1,steady_pairs=0;
    integer seed=1,i,j,op,rd,r1,r2;
    reg [31:0] random_state;
    reg imem_stall=0,dmem_stall=0,finished=0;
    function automatic [31:0] random_next;
        input [31:0] v;
        reg [31:0] x;
        begin x=v^(v<<13);x=x^(x>>17);random_next=x^(x<<5);end
    endfunction
    function automatic [31:0] enc_s;
        input [11:0] imm;
        input [4:0] src2,src1;
        input [2:0] f3;
        begin enc_s={imm[11:5],src2,src1,f3,imm[4:0],7'h23};end
    endfunction
    function automatic [31:0] enc_i;
        input [11:0] imm;
        input [4:0] source;
        input [2:0] f3;
        input [4:0] dest;
        input [6:0] opcode;
        begin enc_i={imm,source,f3,dest,opcode};end
    endfunction
    function automatic [31:0] enc_r;
        input [6:0] f7;
        input [4:0] src2,src1;
        input [2:0] f3;
        input [4:0] dest;
        begin enc_r={f7,src2,src1,f3,dest,7'h33};end
    endfunction
    task automatic append32;
        input [31:0] instruction;
        begin
            program_pc[count]=RESET_PC+2*halfwords;program_instr[count]=instruction;
            program_c[count]=0;rom[halfwords]=instruction[15:0];rom[halfwords+1]=instruction[31:16];
            count=count+1;halfwords=halfwords+2;
        end
    endtask
    task automatic append_caddi;
        input [4:0] dest;
        input [5:0] immediate;
        begin
            program_pc[count]=RESET_PC+2*halfwords;
            program_instr[count]=enc_i({{6{immediate[5]}},immediate},dest,3'd0,dest,7'h13);
            program_c[count]=1;rom[halfwords]={3'b000,immediate[5],dest,immediate[4:0],2'b01};
            count=count+1;halfwords=halfwords+1;
        end
    endtask
    task automatic append_cadd;
        input [4:0] dest,source;
        begin
            program_pc[count]=RESET_PC+2*halfwords;
            program_instr[count]=enc_r(0,source,dest,0,dest);
            program_c[count]=1;rom[halfwords]={4'b1001,dest,source,2'b10};
            count=count+1;halfwords=halfwords+1;
        end
    endtask
    assign imem_req_ready=(!imem_resp_valid||imem_resp_ready)&&!imem_stall&&!finished;
    always @(posedge clk) begin
        if (!rst_n) imem_resp_valid<=0;
        else if(imem_req_ready) begin
            imem_resp_valid<=imem_req_valid;
            if(imem_req_valid) imem_resp_rdata<=
                {rom[((imem_req_addr-RESET_PC)>>1)+1],rom[(imem_req_addr-RESET_PC)>>1]};
        end else if(imem_resp_valid&&imem_resp_ready)imem_resp_valid<=0;
    end
    edrv32_core #(.RESET_PC(RESET_PC), .DUAL_ISSUE(1)) u_core (
        .clk_i(clk), .rst_n_i(rst_n),
        .imem_req_valid_o(imem_req_valid), .imem_req_ready_i(imem_req_ready),
        .imem_req_addr_o(imem_req_addr), .imem_resp_valid_i(imem_resp_valid),
        .imem_resp_ready_o(imem_resp_ready), .imem_resp_rdata_i(imem_resp_rdata),
        .imem_resp_error_i(imem_resp_error),
        .dmem_req_valid_o(dmem_req_valid), .dmem_req_ready_i(dmem_req_ready),
        .dmem_req_addr_o(dmem_req_addr), .dmem_req_we_o(dmem_req_we),
        .dmem_req_size_o(dmem_req_size), .dmem_req_wstrb_o(dmem_req_wstrb),
        .dmem_req_wdata_o(dmem_req_wdata), .dmem_req_cacheable_o(),
        .dmem_resp_valid_i(dmem_resp_valid),
        .dmem_resp_ready_o(dmem_resp_ready), .dmem_resp_rdata_i(dmem_resp_rdata),
        .dmem_resp_error_i(dmem_resp_error),
        .dcache_lookup_valid_o(), .dcache_lookup_ready_i(1'b0),
        .dcache_lookup_addr_o(), .dcache_lookup_store_o(),
        .dcache_lookup_resp_valid_i(1'b0), .dcache_lookup_resp_ready_o(),
        .dcache_lookup_resp_data_i(32'd0), .dcache_lookup_resp_error_i(1'b0),
        .dcache_lookup_cancel_o(),
        .cache_perf_events_i(5'd0),
        .irq_soft_i(1'b0), .irq_timer_i(1'b0), .irq_ext_i(1'b0),
        .time_value_i(64'd0),
        .second_retire_o(second_retire), .second_retire_pc_o(second_pc),
        .second_retire_instr_o(second_instr), .retire_count_o(retire_count),
        .retire_o(retire), .retire_pc_o(retire_pc), .retire_instr_o(retire_instr),
        .retire_exception_o(retire_exception), .retire_cause_o(retire_cause),
        .fencei_retire_o()
    );

    edrv32_mem_model #(.MEM_DEPTH_WORDS(2048),.BASE_ADDR(RESET_PC),.DMEM_LAT(7)) u_mem (
        .clk(clk),.rst_n(rst_n),
        .imem_req_valid_i(1'b0),.imem_req_ready_o(),.imem_req_addr_i(32'd0),
        .imem_resp_valid_o(),.imem_resp_ready_i(1'b1),.imem_resp_rdata_o(),.imem_resp_error_o(),
        .dmem_req_valid_i(dmem_req_valid),.dmem_req_ready_o(dmem_req_ready),
        .dmem_req_addr_i(dmem_req_addr),.dmem_req_we_i(dmem_req_we),.dmem_req_size_i(dmem_req_size),
        .dmem_req_wstrb_i(dmem_req_wstrb),.dmem_req_wdata_i(dmem_req_wdata),
        .dmem_resp_valid_o(dmem_resp_valid),.dmem_resp_ready_i(dmem_resp_ready),
        .dmem_resp_rdata_o(dmem_resp_rdata),.dmem_resp_error_o(dmem_resp_error),
        .imem_req_stall_i(1'b0),.dmem_req_stall_i(dmem_stall)
    );
    task automatic check_instruction;
        input [31:0] pc,instruction;
        input slot_b;
        reg [31:0] lhs,rhs,value,address,word_data;
        reg writes;
        integer dest,src1,src2;
        begin
            if(pc!==program_pc[index]||instruction!==program_instr[index])
                $fatal(1,"ordered retire mismatch index=%0d slot=%0d pc=%08x/%08x instr=%08x/%08x",
                    index,slot_b,pc,program_pc[index],instruction,program_instr[index]);
            dest=instruction[11:7];src1=instruction[19:15];src2=instruction[24:20];
            lhs=gold[src1];rhs=gold[src2];value=0;writes=0;
            case(instruction[6:0])
                7'h13,7'h33: begin
                    writes=1;alu_count=alu_count+1;
                    if(instruction[6:0]==7'h13)rhs={{20{instruction[31]}},instruction[31:20]};
                    case(instruction[14:12])
                        0:value=(instruction[6:0]==7'h33&&instruction[30])?lhs-rhs:lhs+rhs;
                        1:value=lhs<<rhs[4:0];
                        2:value=($signed(lhs)<$signed(rhs))?1:0;
                        3:value=(lhs<rhs)?1:0;
                        4:value=lhs^rhs;
                        5:begin
                            if(instruction[30])value=$signed(lhs)>>>rhs[4:0];
                            else value=lhs>>rhs[4:0];
                        end
                        6:value=lhs|rhs;
                        7:value=lhs&rhs;
                    endcase
                end
                7'h37:begin writes=1;alu_count=alu_count+1;value={instruction[31:12],12'd0};end
                7'h17:begin writes=1;alu_count=alu_count+1;value=pc+{instruction[31:12],12'd0};end
                7'h03:begin
                    writes=1;address=lhs+{{20{instruction[31]}},instruction[31:20]};
                    word_data=gold_mem[(address-RESET_PC)>>2]>>(8*address[1:0]);
                    case(instruction[14:12])
                        0:value={{24{word_data[7]}},word_data[7:0]};
                        1:value={{16{word_data[15]}},word_data[15:0]};
                        4:value={24'd0,word_data[7:0]};
                        5:value={16'd0,word_data[15:0]};
                        default:value=word_data;
                    endcase
                end
                7'h23:begin
                    address=lhs+{{20{instruction[31]}},instruction[31:25],instruction[11:7]};
                    case(instruction[14:12])
                        0:gold_mem[(address-RESET_PC)>>2][8*address[1:0]+:8]=rhs[7:0];
                        1:gold_mem[(address-RESET_PC)>>2][8*address[1:0]+:16]=rhs[15:0];
                        default:gold_mem[(address-RESET_PC)>>2]=rhs;
                    endcase
                end
                7'h6f:begin writes=(dest!=0);value=pc+4;end
                default:$fatal(1,"unsupported reference opcode %08x",instruction);
            endcase
            if(slot_b&&instruction[6:0]!=7'h13&&instruction[6:0]!=7'h33&&instruction[6:0]!=7'h37&&instruction[6:0]!=7'h17)
                $fatal(1,"non-ALU in B");
            if(program_c[index])c_count=c_count+1;
            if(writes&&dest!=0)begin
                if(slot_b) begin
                    if(!u_core.commit_second_write_w||u_core.commit_second_rd_w!==dest[4:0]||u_core.commit_second_value_w!==value)
                        $fatal(1,"B result index=%0d x%0d expected=%08x actual=%08x",index,dest,value,u_core.commit_second_value_w);
                end else if(!u_core.commit_gpr_write_w||u_core.commit_gpr_rd_w!==dest[4:0]||u_core.commit_gpr_value_w!==value)
                    $fatal(1,"A result index=%0d x%0d expected=%08x actual=%08x",index,dest,value,u_core.commit_gpr_value_w);
                gold[dest]=value;
            end
            if(index==31)steady_first=cycles;
            if(index>=32&&index<160&&slot_b)steady_pairs=steady_pairs+1;
            if(index==159)steady_last=cycles;
            index=index+1;
        end
    endtask
    initial begin
        if(!$value$plusargs("SEED=%d",seed))seed=1;
        random_state=seed;
        for(i=0;i<8192;i=i+1)rom[i]=16'h0001;
        #1;
        for(i=0;i<32;i=i+1)gold[i]=0;
        for(i=0;i<512;i=i+1)gold_mem[i]=0;
        gold_mem[448]=32'h31415926;
        for(i=1;i<32;i=i+1)append32(enc_i(i,0,0,i,7'h13));
        append32(32'h00000013);
        for(i=0;i<128;i=i+1)append_caddi(8+(i%20),1);
        // Deterministic parent-A/parent-B consumers cover both source selectors.
        append_caddi(20,1);append_caddi(21,1);
        append32(enc_r(0,21,20,0,22));
        append_caddi(24,1);append_caddi(25,1);
        append32(enc_r(0,24,25,0,26));
        // Same-group RAW, WAW, WAR, x0 and immediate bits resembling a source.
        append_caddi(8,1);append_caddi(8,1);
        append32(enc_i(21,0,0,10,7'h13));append32(enc_i(22,0,0,10,7'h13));
        append32(enc_i(1,10,0,11,7'h13));append32(enc_i(33,0,0,10,7'h13));
        append32(enc_i(5,0,0,0,7'h13));append32(enc_i(0,0,0,12,7'h13));
        append32(32'h800003b7); // x7 is the data base; random operations never change it.
        append32(enc_i(12'h700,7,2,3,7'h03));
        u_mem.mem[448]=32'h31415926;
        append32(enc_i(1,3,0,4,7'h13));append_caddi(8,1);append_caddi(9,1);
        if(MEMORY_STRESS!=0)begin
            // Independent B, load-use RAW/WAW rejection, and Store-before-B WAR.
            append32(enc_i(12'h700,7,2,3,7'h03));append_caddi(8,1);
            append32(enc_i(1,3,0,4,7'h13));
            append32(enc_s(12'h704,3,7,2));append32(enc_i(99,0,0,3,7'h13));
            append32(enc_i(12'h704,7,2,4,7'h03));append32(enc_i(1,0,0,4,7'h13));
            append32(enc_i(12'h700,7,2,3,7'h03));append32(enc_i(1,3,0,5,7'h13));
        end
        // C.ADD makes both B operands explicit while preserving two starts
        // per 32-bit fetch block. Cover each previous-parent source selector.
        for(i=0;i<8;i=i+1)begin
            append_caddi(20,1);append_caddi(21,1);
            append_caddi(22,1);append_cadd(20,21);
            append_caddi(20,1);append_caddi(21,1);
            append_caddi(22,1);append_cadd(21,20);
        end
        for(i=0;i<800;i=i+1)begin
            random_state=random_next(random_state);op=random_state[3:0];
            rd=8+(random_state[8:4]%20);r1=8+(random_state[13:9]%20);r2=8+(random_state[18:14]%20);
            if(MEMORY_STRESS!=0 && op<7)begin
                // A separate retirement memory model checks committed store
                // ordering and byte lanes, under random fetch/data backpressure.
                if(op<3)append32(enc_s(12'h700+((random_state[23:19]%16)*4),r2,7,op));
                else append32(enc_i(12'h700+((random_state[23:19]%16)*4),7,
                    op==3?0:op==4?1:op==5?4:5,rd,7'h03));
                append_caddi(8+((rd-8+1)%20),1);
            end else case(op)
                0,1:append_caddi(rd,random_state[24:19]);
                2:append32(enc_r(7'h20,r2,r1,0,rd));
                3:append32(enc_r(7'h20,r2,r1,5,rd));
                4:append32(enc_i({7'd0,random_state[23:19]},r1,5,rd,7'h13));
                5:append32(enc_i({7'h20,random_state[23:19]},r1,5,rd,7'h13));
                6:append32(enc_i({7'd0,random_state[23:19]},r1,1,rd,7'h13));
                7:append32({random_state[31:12],rd[4:0],7'h37});
                8:append32({random_state[31:12],rd[4:0],7'h17});
                9:append32(enc_i(random_state[31:20],r1,4,rd,7'h13));
                default:append32(enc_r(0,r2,r1,random_state[21:19],rd));
            endcase
        end
        append32(32'h0000006f);
        repeat(4)@(negedge clk);rst_n=1;
    end
    always @(negedge clk)if(rst_n)begin
        random_state=random_next(random_state);
        imem_stall=(index>=160)&&(random_state[3:0]==0);
        dmem_stall=(random_state[7:4]==0);
    end
    always @(posedge clk)if(rst_n&&!finished)begin
        cycles=cycles+1;
        if(u_core.decode_valid_w && u_core.decode_accept_w)begin
            if(u_core.decode_resident_second_rs1_w)resident_b1=resident_b1+1;
            if(u_core.decode_resident_second_rs2_w)resident_b2=resident_b2+1;
            if(u_core.u_ex_stage.second_valid_w)begin
                if(u_core.u_ex_stage.second_lhs_source_w==1)b_lhs_a=b_lhs_a+1;
                if(u_core.u_ex_stage.second_rhs_source_w==1)b_rhs_a=b_rhs_a+1;
                if(u_core.u_ex_stage.second_lhs_source_w==2)b_lhs_b=b_lhs_b+1;
                if(u_core.u_ex_stage.second_rhs_source_w==2)b_rhs_b=b_rhs_b+1;
            end
        end
        if(retire_exception)$fatal(1,"unexpected trap %08x pc=%08x",retire_cause,retire_pc);
        if(second_retire&&!retire)$fatal(1,"B retired without A");
        if(retire_count!==(retire?(second_retire?2'd2:2'd1):2'd0))$fatal(1,"retire count mismatch");
        if(second_retire)begin
            if(retire_instr[6:0]==7'h03)load_pairs=load_pairs+1;
            if(retire_instr[6:0]==7'h23)store_pairs=store_pairs+1;
        end
        if(retire)check_instruction(retire_pc,retire_instr,0);
        if(second_retire)begin pairs=pairs+1;check_instruction(second_pc,second_instr,1);end
        if(index==count)begin
            finished=1;
            #1;
            for(j=1;j<32;j=j+1)if(u_core.u_decode_stage.u_regfile.regs_r[j]!==gold[j])
                $fatal(1,"RF final mismatch x%0d",j);
            if(u_core.u_commit_stage.u_csr_file.minstret_r!==count)$fatal(1,"minstret lost B");
            if(steady_last-steady_first>68||steady_pairs<60)
                $fatal(1,"steady independent ALU throughput regressed cycles=%0d pairs=%0d",steady_last-steady_first,steady_pairs);
            repeat(2)@(negedge clk);
            if(u_core.u_commit_stage.u_csr_file.u_hpm_counters.gen_hpm_enabled.counter_low_r[`EDRV32_HPM_RETIRED_ALU-1]!==alu_count)
                $fatal(1,"HPM ALU lost B expected=%0d actual=%0d",alu_count,u_core.u_commit_stage.u_csr_file.u_hpm_counters.gen_hpm_enabled.counter_low_r[`EDRV32_HPM_RETIRED_ALU-1]);
            // Event 30 is compressed retirement; the reset map selects 1..40.
            if(u_core.u_commit_stage.u_csr_file.u_hpm_counters.gen_hpm_enabled.counter_low_r[`EDRV32_HPM_RETIRED_COMPRESSED-1]!==c_count)
                $fatal(1,"HPM compressed lost B");
            if(resident_b1==0 || resident_b2==0)$fatal(1,"Resident B forwarding did not cover both operands");
            if(b_lhs_a==0||b_rhs_a==0||b_lhs_b==0||b_rhs_b==0)
                $fatal(1,"Missing B resident operand coverage lhsA=%0d rhsA=%0d lhsB=%0d rhsB=%0d",
                    b_lhs_a,b_rhs_a,b_lhs_b,b_rhs_b);
            $display("B_RESIDENT lhsA=%0d rhsA=%0d lhsB=%0d rhsB=%0d",b_lhs_a,b_rhs_a,b_lhs_b,b_rhs_b);
            if(MEMORY_STRESS!=0)begin
                if(load_pairs==0||store_pairs==0)$fatal(1,"Missing Load/Store pairing coverage");
                for(j=448;j<464;j=j+1)if(u_mem.mem[j]!==gold_mem[j])
                    $fatal(1,"Committed memory mismatch word=%0d expected=%08x actual=%08x",j,gold_mem[j],u_mem.mem[j]);
                $display("MEM_ALU_PAIRS load=%0d store=%0d",load_pairs,store_pairs);
            end
            $display("RESIDENT_B rs1=%0d rs2=%0d",resident_b1,resident_b2);
            $display("PASS: dual ALU seed=%0d instructions=%0d pairs=%0d cycles=%0d steady128=%0d steady_pairs=%0d",seed,index,pairs,cycles,steady_last-steady_first,steady_pairs);
            $finish;
        end
        if(cycles>20000)$fatal(1,"dual ALU timeout index=%0d/%0d",index,count);
    end
endmodule
