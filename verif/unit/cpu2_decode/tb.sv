// ISA encoding oracle uses instruction templates, never DUT internals.
module tb #(parameter [31:0] FPU_FORMAT="NONE");
    reg [31:0] instr=0;
    reg [31:0] pc=32'h100;
    reg error=0;
    reg [1:0] fs=3;
    reg [2:0] frm=0;
    wire [2:0] kind;
    wire [4:0] rs1,rs2,rs3,rd;
    wire use1,use2,use3,domain1,domain2,domain3;
    wire [1:0] dest;
    wire [31:0] imm;
    wire load,store,double_beat,late_supported;
    wire [2:0] rm;
    wire exception;
    wire [3:0] cause;
    wire [31:0] tval;
    edrv32_cpu2_decode #(.FPU_FORMAT(FPU_FORMAT)) dut (
        .clk_i(1'b0),
        .rst_n_i(1'b1),
        .instr_i(instr),
        .pc_i(pc),
        .error_i(error),
        .csr_fs_i(fs),
        .csr_frm_i(frm),
        .class_o(kind),
        .rs1_o(rs1),
        .rs2_o(rs2),
        .rs3_o(rs3),
        .rs1_used_o(use1),
        .rs2_used_o(use2),
        .rs3_used_o(use3),
        .rs1_domain_o(domain1),
        .rs2_domain_o(domain2),
        .rs3_domain_o(domain3),
        .rd_o(rd),
        .dest_o(dest),
        .imm_o(imm),
        .load_o(load),
        .store_o(store),
        .double_beat_o(double_beat),
        .late_supported_o(late_supported),
        .rm_o(rm),
        .exception_o(exception),
        .cause_o(cause),
        .tval_o(tval)
    );
    integer count=0;
    task legal(input [31:0] code, input bit expected);
        instr=code; #1; count++;
        if(exception!==!expected || (!expected && (cause!==2 || tval!==code)))
            $fatal(1,"encoding %h legal expected %b got exception %b cause %d at %0t",
                code,expected,exception,cause,$time);
    endtask
    function [31:0] op(input integer f7,input integer f3,input integer opc);
        op=(32'(f7)<<25)|(32'd3<<20)|(32'd2<<15)|(32'(f3)<<12)|(32'd1<<7)|32'(opc);
    endfunction
    initial begin
        // Every funct7/funct3 combination: RV32IM, OP-IMM and the three Zba templates.
        for(integer f7=0;f7<128;f7++) begin
            for(integer f3=0;f3<8;f3++) begin
                legal(op(f7,f3,'h33),f7==0 || f7==1 ||
                    (f7=='h20 && (f3==0 || f3==5)) ||
                    (f7=='h10 && (f3==2 || f3==4 || f3==6)));
                legal(op(f7,f3,'h13),(f3!=1 && f3!=5) || f7==0 ||
                    (f3==5 && f7=='h20));
            end
        end
        for(integer f3=0;f3<8;f3++) begin
            legal(op(0,f3,'h03),f3!=3 && f3<6);
            legal(op(0,f3,'h23),f3<=2);
            legal(op(0,f3,'h63),f3!=2 && f3!=3);
            legal(op(0,f3,'h67),f3==0);
        end
        for(integer shift=1;shift<=3;shift++) begin
            legal(op('h10,shift*2,'h33),1);
            if(kind!==0 || !use1 || !use2 || !late_supported || dest!==1)
                $fatal(1,"Zba dependency metadata");
        end
        legal(32'h123450b7,1); if(imm!==32'h12345000) $fatal(1,"U immediate");
        legal(32'hfff10093,1); if(imm!==32'hffffffff) $fatal(1,"I immediate");
        legal(32'hfe312e23,1); if(imm!==32'hfffffffc) $fatal(1,"S immediate");
        legal(32'hfe310ee3,1); if(imm!==32'hfffffffc) $fatal(1,"B immediate");
        legal(32'hffdff0ef,1); if(imm!==32'hfffffffc) $fatal(1,"J immediate");
        legal(32'h30200073,1); legal(32'h10500073,1);
        legal(32'h10200073,0); legal(32'h00000000,0);
        instr=32'h00000073; #1;
        if(!exception || cause!==11 || tval!==0) $fatal(1,"ecall");
        instr=32'h00100073; #1;
        if(!exception || cause!==3 || tval!==pc) $fatal(1,"ebreak");
        error=1; #1;
        if(!exception || cause!==1 || tval!==pc) $fatal(1,"fetch error priority");
        pc=32'h102; #1;
        if(!exception || cause!==0 || tval!==pc) $fatal(1,"fetch alignment priority");
        error=0; pc=32'h100;
        // FP format/FS and every static/dynamic rounding code for FADD.S and FADD.D.
        for(integer precision=0;precision<4;precision++) begin
            for(integer rounding=0;rounding<8;rounding++) begin
                for(integer dynamic_rm=0;dynamic_rm<8;dynamic_rm++) begin
                    frm=3'(dynamic_rm);
                    legal(op(precision,rounding,'h53), FPU_FORMAT!="NONE" &&
                        (precision==0 || (precision==1 && FPU_FORMAT=="FD")) &&
                        (rounding<5 || (rounding==7 && dynamic_rm<5)));
                end
            end
        end
        frm=0;
        // Independent OP-FP encoding whitelist, including RV32 conversion/move restrictions.
        for(integer group_code=0;group_code<32;group_code++)begin
            for(integer precision=0;precision<4;precision++)begin
                for(integer function_code=0;function_code<8;function_code++)begin
                    for(integer selector=0;selector<4;selector++)begin
                        automatic integer second=selector==3?31:selector;
                        automatic bit enabled=FPU_FORMAT!="NONE" &&
                            (precision==0 || (precision==1 && FPU_FORMAT=="FD"));
                        automatic bit rounded=function_code<5||function_code==7;
                        automatic bit accepted=0;
                        case(group_code)
                            0,1,2,3:accepted=enabled&&rounded;
                            11:accepted=enabled&&rounded&&second==0;
                            4:accepted=enabled&&function_code<3;
                            5:accepted=enabled&&function_code<2;
                            20:accepted=enabled&&function_code<3;
                            24,26:accepted=enabled&&rounded&&second<2;
                            8:accepted=FPU_FORMAT=="FD"&&rounded&&
                                ((precision==0&&second==1)||(precision==1&&second==0));
                            28:accepted=enabled&&second==0&&
                                (function_code==1||(function_code==0&&precision==0));
                            30:accepted=FPU_FORMAT!="NONE"&&precision==0&&second==0&&function_code==0;
                            default:accepted=0;
                        endcase
                        legal((32'(group_code)<<27)|(32'(precision)<<25)|(32'(second)<<20)|
                            (32'd2<<15)|(32'(function_code)<<12)|(32'd1<<7)|32'h53,accepted);
                    end
                end
            end
        end
        for(integer opcode=0;opcode<4;opcode++)begin
            for(integer precision=0;precision<4;precision++)begin
                for(integer rounding=0;rounding<8;rounding++)begin
                    legal((32'd4<<27)|(32'(precision)<<25)|(32'd3<<20)|(32'd2<<15)|
                        (32'(rounding)<<12)|(32'd1<<7)|32'(32'h43+opcode*4),
                        FPU_FORMAT!="NONE"&&(precision==0||(precision==1&&FPU_FORMAT=="FD"))&&
                        (rounding<5||(rounding==7&&frm<5)));
                end
            end
        end
        for(integer width_code=0;width_code<8;width_code++)begin
            legal((32'(width_code)<<12)|32'h87,FPU_FORMAT!="NONE"&&
                (width_code==2||(width_code==3&&FPU_FORMAT=="FD")));
            legal((32'(width_code)<<12)|32'h27,FPU_FORMAT!="NONE"&&
                (width_code==2||(width_code==3&&FPU_FORMAT=="FD")));
        end
        frm=0; fs=0; legal(32'h003100d3,0); legal(32'h00102073,0); fs=3;
        legal(32'h003100d3,FPU_FORMAT!="NONE");
        if(FPU_FORMAT!="NONE" && (dest!==2 || !domain1 || !domain2))
            $fatal(1,"FP arithmetic source domains");
        legal(32'h00310053,FPU_FORMAT!="NONE");
        if(FPU_FORMAT!="NONE" && dest!==2)$fatal(1,"FP f0 must be writable");
        legal(32'h003150d3,0); // Reserved static rounding encoding.
        $display("PASS decode %0d templates FPU_FORMAT=%s",count,FPU_FORMAT);
        $finish;
    end
endmodule
