// Self-checking public-interface test; independent architectural reference.
module tb;
    reg clk_i;
    reg rst_n_i;
    reg id_valid_i;
    reg id_load_i;
    reg id_store_i;
    reg [4:0] id_rs1_i;
    reg [4:0] id_candidates_i;
    reg [31:0] id_imm_i;
    reg [1:0] wb_valid_i;
    reg [9:0] wb_rd_i;
    reg [63:0] wb_data_i;
    reg older_valid_i;
    reg [4:0] older_rd_i;
    reg [1:0] ex_valid_i;
    reg [9:0] ex_rd_i;
    reg [1:0] mem_valid_i;
    reg [9:0] mem_rd_i;
    reg [1:0] wb_mul_pending_i;
    reg [9:0] wb_mul_rd_i;
    reg fill_valid_i;
    reg fill_way_i;
    reg [31:0] fill_addr_i;
    reg [31:0] fill_data_i;
    reg fill_line_valid_i;
    wire id_eligible_o;
    wire [31:0] id_addr_o;
    wire ex_valid_o;
    wire [31:0] ex_addr_o;
    wire operand_valid_o;
    wire operand_hit_o;
    wire [31:0] operand_data_o;
    edrv32_cpu2_id_agu dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .id_valid_i(id_valid_i),
        .id_load_i(id_load_i),
        .id_store_i(id_store_i),
        .id_rs1_i(id_rs1_i),
        .id_candidates_i(id_candidates_i),
        .id_imm_i(id_imm_i),
        .wb_valid_i(wb_valid_i),
        .wb_rd_i(wb_rd_i),
        .wb_data_i(wb_data_i),
        .older_valid_i(older_valid_i),
        .older_rd_i(older_rd_i),
        .ex_valid_i(ex_valid_i),
        .ex_rd_i(ex_rd_i),
        .mem_valid_i(mem_valid_i),
        .mem_rd_i(mem_rd_i),
        .wb_mul_pending_i(wb_mul_pending_i),
        .wb_mul_rd_i(wb_mul_rd_i),
        .fill_valid_i(fill_valid_i),
        .fill_way_i(fill_way_i),
        .fill_addr_i(fill_addr_i),
        .fill_data_i(fill_data_i),
        .fill_line_valid_i(fill_line_valid_i),
        .id_eligible_o(id_eligible_o),
        .id_addr_o(id_addr_o),
        .ex_valid_o(ex_valid_o),
        .ex_addr_o(ex_addr_o),
        .operand_valid_o(operand_valid_o),
        .operand_hit_o(operand_hit_o),
        .operand_data_o(operand_data_o)
    );
    always #5 clk_i = ~clk_i;
    task tick; begin @(posedge clk_i); #1; end endtask
    task init_inputs; begin
        clk_i = '0;
        rst_n_i = '0;
        id_valid_i = '0;
        id_load_i = '0;
        id_store_i = '0;
        id_rs1_i = '0;
        id_candidates_i = '0;
        id_imm_i = '0;
        wb_valid_i = '0;
        wb_rd_i = '0;
        wb_data_i = '0;
        older_valid_i = '0;
        older_rd_i = '0;
        ex_valid_i = '0;
        ex_rd_i = '0;
        mem_valid_i = '0;
        mem_rd_i = '0;
        wb_mul_pending_i = '0;
        wb_mul_rd_i = '0;
        fill_valid_i = '0;
        fill_way_i = '0;
        fill_addr_i = '0;
        fill_data_i = '0;
        fill_line_valid_i = '0;
        tick(); rst_n_i = 1; tick();
    end endtask
    integer n;
    task eligible(input bit expected);
        begin
            #1;if(id_eligible_o!==expected)
                $fatal(1,"AGU eligibility expected %b got %b at %0t",expected,id_eligible_o,$time);
        end
    endtask
    initial begin
        init_inputs();
        // Initialize tags and both way data through public ports.
        for(n=0;n<2;n=n+1) begin
            fill_valid_i=1;fill_way_i=1'(n);fill_addr_i=0;
            fill_line_valid_i=0;tick();
        end
        fill_valid_i=1;fill_way_i=1;fill_addr_i=32'h24;
        fill_line_valid_i=1;fill_data_i=32'hcafebabe;tick();fill_valid_i=0;
        wb_valid_i=1;wb_rd_i={5'd0,5'd5};wb_data_i={32'd0,32'h20};tick();wb_valid_i=0;
        id_valid_i=1;id_load_i=1;id_rs1_i=5;id_imm_i=4;
        eligible(1);if(id_addr_o!==32'h24) $fatal(1,"RF plus imm");
        tick();id_valid_i=0;tick();tick();
        if(!operand_valid_o || !operand_hit_o || operand_data_o!==32'hcafebabe)
            $fatal(1,"load capture expected cafebabe got %h valid %b hit %b",
                operand_data_o,operand_valid_o,operand_hit_o);
        id_valid_i=1;
        older_valid_i=1;older_rd_i=5;eligible(0);older_valid_i=0;
        for(n=0;n<2;n=n+1) begin
            ex_valid_i=2'(1<<n);ex_rd_i={5'd5,5'd5};eligible(0);ex_valid_i=0;
            mem_valid_i=2'(1<<n);mem_rd_i={5'd5,5'd5};eligible(0);mem_valid_i=0;
            wb_mul_pending_i=2'(1<<n);wb_mul_rd_i={5'd5,5'd5};eligible(0);
            wb_mul_pending_i=0;
        end
        id_store_i=1;eligible(0);id_store_i=0;id_load_i=0;eligible(0);id_load_i=1;
        wb_valid_i=3;wb_rd_i={5'd5,5'd5};wb_data_i={32'h100,32'h200};
        eligible(1);if(id_addr_o!==32'h104) $fatal(1,"young WB forwarding");
        tick();wb_valid_i=0;id_candidates_i=5'b00101;
        eligible(1);if(id_addr_o!==32'h104) $fatal(1,"registered owner bank");
        id_rs1_i=0;older_valid_i=1;older_rd_i=0;ex_valid_i=3;ex_rd_i=0;
        mem_valid_i=3;mem_rd_i=0;wb_mul_pending_i=3;wb_mul_rd_i=0;
        wb_valid_i=3;wb_rd_i=0;wb_data_i='1;eligible(1);
        if(id_addr_o!==4) $fatal(1,"x0 must be zero and dependency free");
        $display("PASS cpu2_id_agu: all producer exclusions, x0, WB, local DRM capture");
        $finish;
    end

endmodule
