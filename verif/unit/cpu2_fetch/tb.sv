// Self-checking public-interface test; independent architectural reference.
module tb;
    reg clk_i;
    reg rst_n_i;
    reg f1_valid_i;
    reg [31:0] f1_pc_i;
    reg [1:0] f1_direction_i;
    reg fill_valid_i;
    reg fill_way_i;
    reg [31:0] fill_addr_i;
    reg [31:0] fill_instr_i;
    reg fill_line_valid_i;
    reg btb_write_i;
    reg [31:0] btb_pc_i;
    reg [31:0] btb_target_i;
    reg [2:0] btb_type_i;
    reg [31:1] lvt_i;
    reg [1:0] wb_valid_i;
    reg [9:0] wb_rd_i;
    wire [1:0] wb_valid_copy_i = wb_valid_i;
    wire [9:0] wb_rd_copy_i = wb_rd_i;
    reg ib_accept_i;
    reg [1:0] ib_remove_i;
    wire ib_ready_o;
    wire [3:0] ib_count_o;
    wire [1:0] id_valid_o;
    wire [63:0] id_instr_o;
    wire [9:0] id_candidates_o;
    wire f2_valid_o;
    wire [1:0] f2_hit_o;
    wire [63:0] f2_instr_o;
    wire [1:0] f2_taken_o;
    wire [31:0] f2_target_o;
    wire [5:0] f2_type_o;
    edrv32_cpu2_fetch dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .f1_valid_i(f1_valid_i),
        .f1_pc_i(f1_pc_i),
        .f1_direction_i(f1_direction_i),
        .fill_valid_i(fill_valid_i),
        .fill_way_i(fill_way_i),
        .fill_addr_i(fill_addr_i),
        .fill_instr_i(fill_instr_i),
        .fill_line_valid_i(fill_line_valid_i),
        .btb_write_i(btb_write_i),
        .btb_pc_i(btb_pc_i),
        .btb_target_i(btb_target_i),
        .btb_type_i(btb_type_i),
        .lvt_i(lvt_i),
        .wb_valid_i(wb_valid_i),
        .wb_rd_i(wb_rd_i),
        .wb_valid_copy_i(wb_valid_copy_i),
        .wb_rd_copy_i(wb_rd_copy_i),
        .ib_accept_i(ib_accept_i),
        .ib_remove_i(ib_remove_i),
        .ib_ready_o(ib_ready_o),
        .ib_count_o(ib_count_o),
        .id_valid_o(id_valid_o),
        .id_instr_o(id_instr_o),
        .id_candidates_o(id_candidates_o),
        .f2_valid_o(f2_valid_o),
        .f2_hit_o(f2_hit_o),
        .f2_instr_o(f2_instr_o),
        .f2_taken_o(f2_taken_o),
        .f2_target_o(f2_target_o),
        .f2_type_o(f2_type_o)
    );
    always #5 clk_i = ~clk_i;
    task tick; begin @(posedge clk_i); #1; end endtask
    task init_inputs; begin
        clk_i = '0;
        rst_n_i = '0;
        f1_valid_i = '0;
        f1_pc_i = '0;
        f1_direction_i = '0;
        fill_valid_i = '0;
        fill_way_i = '0;
        fill_addr_i = '0;
        fill_instr_i = '0;
        fill_line_valid_i = '0;
        btb_write_i = '0;
        btb_pc_i = '0;
        btb_target_i = '0;
        btb_type_i = '0;
        lvt_i = '0;
        wb_valid_i = '0;
        wb_rd_i = '0;
        ib_accept_i = '0;
        ib_remove_i = '0;
        tick(); rst_n_i = 1; tick();
    end endtask
    integer n;
    integer k;
    reg [31:0] instructions [0:31];
    reg [31:0] actual;
    reg [4:0] rs1;
    reg [4:0] rs2;
    reg [4:0] candidates;
    task request(input integer pc);
        begin
            f1_pc_i=32'(pc);f1_valid_i=1; tick(); f1_valid_i=0; #1;
            if (f2_hit_o!==3 || f2_instr_o!=={instructions[pc/4+1],instructions[pc/4]})
                $fatal(1,"fetch pc=%h expected %h/%h got %h hit %b",pc,
                    instructions[pc/4],instructions[pc/4+1],f2_instr_o,f2_hit_o);
        end
    endtask
    task check_heads;
        begin
            for(integer slot=0;slot<2;slot=slot+1) begin
                actual=id_instr_o[32*slot+:32];rs1=actual[19:15];rs2=actual[24:20];
                candidates=id_candidates_o[5*slot+:5];
                if ((candidates[4]?candidates[2]:candidates[0]) !==
                    ((rs1==0)?1'b0:lvt_i[rs1])) $fatal(1,"IB owner rs1");
                if ((candidates[4]?candidates[3]:candidates[1]) !==
                    ((rs2==0)?1'b0:lvt_i[rs2])) $fatal(1,"IB owner rs2");
            end
        end
    endtask
    initial begin
        init_inputs();
        // Initialize both way tags through the public fill interface, then fill two lines.
        for(n=0;n<512;n=n+1) begin
            fill_valid_i=1;fill_line_valid_i=0;fill_addr_i=32'(n*32);
            fill_way_i=0;tick();fill_way_i=1;tick();
        end
        for(n=0;n<32;n=n+1) begin
            instructions[n]=(32'((n%31)+1)<<15)|(32'((n*7)%32)<<20)|32'h33;
            fill_valid_i=1;fill_way_i=1'(n/16);fill_addr_i=32'(n*4);
            fill_instr_i=instructions[n];fill_line_valid_i=1;tick();
        end
        fill_valid_i=0;lvt_i=31'h55555555;
        for(n=0;n<31;n=n+1) request(n*4);
        // PC=28 crosses a line; its two words have independent set/tag lookups.
        request(28);ib_accept_i=1;tick();ib_accept_i=0;
        if(ib_count_o!=2 || id_instr_o!=={instructions[8],instructions[7]})
            $fatal(1,"cross-line IB enqueue");
        check_heads();
        for(n=0;n<12;n=n+1) begin
            for(k=0;k<2;k=k+1) begin
                actual=id_instr_o[32*k+:32];rs1=actual[19:15];
                wb_rd_i={rs1,rs1};wb_valid_i=(n%2==0)?1:3;
                tick();lvt_i[rs1]=(n%2!=0);check_heads();
                candidates=id_candidates_o[5*k+:5];
                if(candidates[0]!==candidates[2]) $fatal(1,"both candidates must snoop");
            end
        end
        wb_valid_i=0;ib_remove_i=2;tick();ib_remove_i=0;
        // Two taken BTB words select the oldest, including an odd starting PC.
        btb_write_i=1;btb_type_i=1;btb_pc_i=4;btb_target_i=32'h100;tick();
        btb_pc_i=8;btb_target_i=32'h200;tick();btb_write_i=0;f1_direction_i=3;
        request(4);
        if(f2_taken_o!==1 || f2_target_o!==32'h100) $fatal(1,"oldest taken odd PC");
        ib_accept_i=1;tick();ib_accept_i=0;
        if(ib_count_o!=1) $fatal(1,"younger after taken must not enqueue");
        ib_remove_i=1;tick();ib_remove_i=0;f1_direction_i=0;
        // New enqueue and younger WB on the same edge.
        request(28);actual=instructions[7];rs1=actual[19:15];
        wb_valid_i=3;wb_rd_i={rs1,rs1};ib_accept_i=1;tick();
        lvt_i[rs1]=1;ib_accept_i=0;wb_valid_i=0;check_heads();
        // Fill all twelve physical entries and shift the two fixed heads.
        for(n=0;n<5;n=n+1) begin request(28);ib_accept_i=1;tick();ib_accept_i=0;end
        if(ib_count_o!=12 || ib_ready_o) $fatal(1,"12 physical entries");
        actual=instructions[7];rs1=actual[19:15];
        wb_valid_i=1;wb_rd_i={5'd0,rs1};tick();lvt_i[rs1]=0;wb_valid_i=0;
        for(n=0;n<6;n=n+1) begin check_heads();ib_remove_i=2;tick();end
        ib_remove_i=0;
        if(id_valid_o!=0 || ib_count_o!=0) $fatal(1,"IB drain");
        $display("PASS cpu2_fetch: all word parities, cross-line, ways, oldest BTB, IB snoop");
        $finish;
    end

endmodule
