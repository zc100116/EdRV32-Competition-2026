// File: tb.sv; Spec: CPU5.1/CV08; Description: independent empty-IB transfer scoreboard.
// Clock: clk_sys; expectations use only stimulus and public handshakes.
module tb;
    parameter ISSUE_WIDTH = 2;
    localparam RAS_BITS = ISSUE_WIDTH == 2 ? 256 : 128;
    localparam RAS_PTR_BITS = ISSUE_WIDTH == 2 ? 3 : 2;
    localparam RAS_COUNT_BITS = RAS_PTR_BITS+1;
    localparam [3:0] CAPACITY = ISSUE_WIDTH == 2 ? 12 : 8;
    reg clk_i;
    reg rst_n_i;
    reg fetch_push_valid_i;
    wire fetch_push_ready_o;
    reg [2-1:0] fetch_push_count_i;
    reg [32-1:0] fetch_push0_pc_i;
    reg [32-1:0] fetch_push0_instr_i;
    reg fetch_push0_error_i;
    reg [5-1:0] fetch_push0_candidates_i;
    reg fetch_push0_predict_taken_i;
    reg [32-1:0] fetch_push0_predict_target_i;
    reg fetch_push0_predict_token_i;
    reg [3-1:0] fetch_push0_predict_provider_i;
    reg fetch_push0_predict_alternate_i;
    reg [9-1:0] fetch_push0_predict_index0_i;
    reg [9-1:0] fetch_push0_predict_index1_i;
    reg [9-1:0] fetch_push0_predict_index2_i;
    reg [9-1:0] fetch_push0_predict_index3_i;
    reg [10-1:0] fetch_push0_predict_tag0_i;
    reg [10-1:0] fetch_push0_predict_tag1_i;
    reg [10-1:0] fetch_push0_predict_tag2_i;
    reg [10-1:0] fetch_push0_predict_tag3_i;
    reg [12-1:0] fetch_push0_predict_base_index_i;
    reg [12-1:0] fetch_push0_predict_fast_index_i;
    reg [RAS_BITS-1:0] fetch_push0_ras_data_i;
    reg [RAS_PTR_BITS-1:0] fetch_push0_ras_ptr_i;
    reg [RAS_COUNT_BITS-1:0] fetch_push0_ras_count_i;
    reg [32-1:0] fetch_push1_pc_i;
    reg [32-1:0] fetch_push1_instr_i;
    reg fetch_push1_error_i;
    reg [5-1:0] fetch_push1_candidates_i;
    reg fetch_push1_predict_taken_i;
    reg [32-1:0] fetch_push1_predict_target_i;
    reg fetch_push1_predict_token_i;
    reg [3-1:0] fetch_push1_predict_provider_i;
    reg fetch_push1_predict_alternate_i;
    reg [9-1:0] fetch_push1_predict_index0_i;
    reg [9-1:0] fetch_push1_predict_index1_i;
    reg [9-1:0] fetch_push1_predict_index2_i;
    reg [9-1:0] fetch_push1_predict_index3_i;
    reg [10-1:0] fetch_push1_predict_tag0_i;
    reg [10-1:0] fetch_push1_predict_tag1_i;
    reg [10-1:0] fetch_push1_predict_tag2_i;
    reg [10-1:0] fetch_push1_predict_tag3_i;
    reg [12-1:0] fetch_push1_predict_base_index_i;
    reg [12-1:0] fetch_push1_predict_fast_index_i;
    reg [RAS_BITS-1:0] fetch_push1_ras_data_i;
    reg [RAS_PTR_BITS-1:0] fetch_push1_ras_ptr_i;
    reg [RAS_COUNT_BITS-1:0] fetch_push1_ras_count_i;
    reg [2-1:0] ib_remove_count_i;
    wire [4-1:0] ib_credit_o;
    reg frontend_flush_i;
    reg reserve_valid_i;
    reg [2-1:0] reserve_cancel_count_i;
    reg wb0_valid_i;
    reg [5-1:0] wb0_rd_i;
    reg wb1_valid_i;
    reg [5-1:0] wb1_rd_i;
    reg wb0_valid_copy_i;
    reg [4:0] wb0_rd_copy_i;
    reg wb1_valid_copy_i;
    reg [4:0] wb1_rd_copy_i;
    wire ib_head0_valid_o;
    wire ib_head1_valid_o;
    wire [32-1:0] ib_head0_pc_o;
    wire [32-1:0] ib_head0_instr_o;
    wire ib_head0_error_o;
    wire [5-1:0] ib_head0_candidates_o;
    wire ib_head0_predict_taken_o;
    wire [32-1:0] ib_head0_predict_target_o;
    wire ib_head0_predict_token_o;
    wire [3-1:0] ib_head0_predict_provider_o;
    wire ib_head0_predict_alternate_o;
    wire [9-1:0] ib_head0_predict_index0_o;
    wire [9-1:0] ib_head0_predict_index1_o;
    wire [9-1:0] ib_head0_predict_index2_o;
    wire [9-1:0] ib_head0_predict_index3_o;
    wire [10-1:0] ib_head0_predict_tag0_o;
    wire [10-1:0] ib_head0_predict_tag1_o;
    wire [10-1:0] ib_head0_predict_tag2_o;
    wire [10-1:0] ib_head0_predict_tag3_o;
    wire [12-1:0] ib_head0_predict_base_index_o;
    wire [12-1:0] ib_head0_predict_fast_index_o;
    wire [RAS_BITS-1:0] ib_head0_ras_data_o;
    wire [RAS_PTR_BITS-1:0] ib_head0_ras_ptr_o;
    wire [RAS_COUNT_BITS-1:0] ib_head0_ras_count_o;
    wire [32-1:0] ib_head1_pc_o;
    wire [32-1:0] ib_head1_instr_o;
    wire ib_head1_error_o;
    wire [5-1:0] ib_head1_candidates_o;
    wire ib_head1_predict_taken_o;
    wire [32-1:0] ib_head1_predict_target_o;
    wire ib_head1_predict_token_o;
    wire [3-1:0] ib_head1_predict_provider_o;
    wire ib_head1_predict_alternate_o;
    wire [9-1:0] ib_head1_predict_index0_o;
    wire [9-1:0] ib_head1_predict_index1_o;
    wire [9-1:0] ib_head1_predict_index2_o;
    wire [9-1:0] ib_head1_predict_index3_o;
    wire [10-1:0] ib_head1_predict_tag0_o;
    wire [10-1:0] ib_head1_predict_tag1_o;
    wire [10-1:0] ib_head1_predict_tag2_o;
    wire [10-1:0] ib_head1_predict_tag3_o;
    wire [12-1:0] ib_head1_predict_base_index_o;
    wire [12-1:0] ib_head1_predict_fast_index_o;
    wire [RAS_BITS-1:0] ib_head1_ras_data_o;
    wire [RAS_PTR_BITS-1:0] ib_head1_ras_ptr_o;
    wire [RAS_COUNT_BITS-1:0] ib_head1_ras_count_o;
    wire [$clog2((ISSUE_WIDTH == 2 ? 8 : 4)+5)-1:0] ib_count_o;
    edrv32_cpu2_ib #(.ISSUE_WIDTH(ISSUE_WIDTH)) dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .fetch_push_valid_i(fetch_push_valid_i),
        .fetch_push_ready_o(fetch_push_ready_o),
        .fetch_push_count_i(fetch_push_count_i),
        .fetch_push0_pc_i(fetch_push0_pc_i),
        .fetch_push0_instr_i(fetch_push0_instr_i),
        .fetch_push0_error_i(fetch_push0_error_i),
        .fetch_push0_candidates_i(fetch_push0_candidates_i),
        .fetch_push0_predict_taken_i(fetch_push0_predict_taken_i),
        .fetch_push0_predict_target_i(fetch_push0_predict_target_i),
        .fetch_push0_predict_token_i(fetch_push0_predict_token_i),
        .fetch_push0_predict_provider_i(fetch_push0_predict_provider_i),
        .fetch_push0_predict_alternate_i(fetch_push0_predict_alternate_i),
        .fetch_push0_predict_index0_i(fetch_push0_predict_index0_i),
        .fetch_push0_predict_index1_i(fetch_push0_predict_index1_i),
        .fetch_push0_predict_index2_i(fetch_push0_predict_index2_i),
        .fetch_push0_predict_index3_i(fetch_push0_predict_index3_i),
        .fetch_push0_predict_tag0_i(fetch_push0_predict_tag0_i),
        .fetch_push0_predict_tag1_i(fetch_push0_predict_tag1_i),
        .fetch_push0_predict_tag2_i(fetch_push0_predict_tag2_i),
        .fetch_push0_predict_tag3_i(fetch_push0_predict_tag3_i),
        .fetch_push0_predict_base_index_i(fetch_push0_predict_base_index_i),
        .fetch_push0_predict_fast_index_i(fetch_push0_predict_fast_index_i),
        .fetch_push0_ras_data_i(fetch_push0_ras_data_i),
        .fetch_push0_ras_ptr_i(fetch_push0_ras_ptr_i),
        .fetch_push0_ras_count_i(fetch_push0_ras_count_i),
        .fetch_push1_pc_i(fetch_push1_pc_i),
        .fetch_push1_instr_i(fetch_push1_instr_i),
        .fetch_push1_error_i(fetch_push1_error_i),
        .fetch_push1_candidates_i(fetch_push1_candidates_i),
        .fetch_push1_predict_taken_i(fetch_push1_predict_taken_i),
        .fetch_push1_predict_target_i(fetch_push1_predict_target_i),
        .fetch_push1_predict_token_i(fetch_push1_predict_token_i),
        .fetch_push1_predict_provider_i(fetch_push1_predict_provider_i),
        .fetch_push1_predict_alternate_i(fetch_push1_predict_alternate_i),
        .fetch_push1_predict_index0_i(fetch_push1_predict_index0_i),
        .fetch_push1_predict_index1_i(fetch_push1_predict_index1_i),
        .fetch_push1_predict_index2_i(fetch_push1_predict_index2_i),
        .fetch_push1_predict_index3_i(fetch_push1_predict_index3_i),
        .fetch_push1_predict_tag0_i(fetch_push1_predict_tag0_i),
        .fetch_push1_predict_tag1_i(fetch_push1_predict_tag1_i),
        .fetch_push1_predict_tag2_i(fetch_push1_predict_tag2_i),
        .fetch_push1_predict_tag3_i(fetch_push1_predict_tag3_i),
        .fetch_push1_predict_base_index_i(fetch_push1_predict_base_index_i),
        .fetch_push1_predict_fast_index_i(fetch_push1_predict_fast_index_i),
        .fetch_push1_ras_data_i(fetch_push1_ras_data_i),
        .fetch_push1_ras_ptr_i(fetch_push1_ras_ptr_i),
        .fetch_push1_ras_count_i(fetch_push1_ras_count_i),
        .ib_remove_count_i(ib_remove_count_i),
        .ib_credit_o(ib_credit_o),
        .frontend_flush_i(frontend_flush_i),
        .reserve_valid_i(reserve_valid_i),
        .reserve_cancel_count_i(reserve_cancel_count_i),
        .wb0_valid_i(wb0_valid_i),
        .wb0_rd_i(wb0_rd_i),
        .wb1_valid_i(wb1_valid_i),
        .wb1_rd_i(wb1_rd_i),
        .wb0_valid_copy_i(wb0_valid_copy_i),
        .wb0_rd_copy_i(wb0_rd_copy_i),
        .wb1_valid_copy_i(wb1_valid_copy_i),
        .wb1_rd_copy_i(wb1_rd_copy_i),
        .ib_head0_valid_o(ib_head0_valid_o),
        .ib_head1_valid_o(ib_head1_valid_o),
        .ib_head0_pc_o(ib_head0_pc_o),
        .ib_head0_instr_o(ib_head0_instr_o),
        .ib_head0_error_o(ib_head0_error_o),
        .ib_head0_candidates_o(ib_head0_candidates_o),
        .ib_head0_predict_taken_o(ib_head0_predict_taken_o),
        .ib_head0_predict_target_o(ib_head0_predict_target_o),
        .ib_head0_predict_token_o(ib_head0_predict_token_o),
        .ib_head0_predict_provider_o(ib_head0_predict_provider_o),
        .ib_head0_predict_alternate_o(ib_head0_predict_alternate_o),
        .ib_head0_predict_index0_o(ib_head0_predict_index0_o),
        .ib_head0_predict_index1_o(ib_head0_predict_index1_o),
        .ib_head0_predict_index2_o(ib_head0_predict_index2_o),
        .ib_head0_predict_index3_o(ib_head0_predict_index3_o),
        .ib_head0_predict_tag0_o(ib_head0_predict_tag0_o),
        .ib_head0_predict_tag1_o(ib_head0_predict_tag1_o),
        .ib_head0_predict_tag2_o(ib_head0_predict_tag2_o),
        .ib_head0_predict_tag3_o(ib_head0_predict_tag3_o),
        .ib_head0_predict_base_index_o(ib_head0_predict_base_index_o),
        .ib_head0_predict_fast_index_o(ib_head0_predict_fast_index_o),
        .ib_head0_ras_data_o(ib_head0_ras_data_o),
        .ib_head0_ras_ptr_o(ib_head0_ras_ptr_o),
        .ib_head0_ras_count_o(ib_head0_ras_count_o),
        .ib_head1_pc_o(ib_head1_pc_o),
        .ib_head1_instr_o(ib_head1_instr_o),
        .ib_head1_error_o(ib_head1_error_o),
        .ib_head1_candidates_o(ib_head1_candidates_o),
        .ib_head1_predict_taken_o(ib_head1_predict_taken_o),
        .ib_head1_predict_target_o(ib_head1_predict_target_o),
        .ib_head1_predict_token_o(ib_head1_predict_token_o),
        .ib_head1_predict_provider_o(ib_head1_predict_provider_o),
        .ib_head1_predict_alternate_o(ib_head1_predict_alternate_o),
        .ib_head1_predict_index0_o(ib_head1_predict_index0_o),
        .ib_head1_predict_index1_o(ib_head1_predict_index1_o),
        .ib_head1_predict_index2_o(ib_head1_predict_index2_o),
        .ib_head1_predict_index3_o(ib_head1_predict_index3_o),
        .ib_head1_predict_tag0_o(ib_head1_predict_tag0_o),
        .ib_head1_predict_tag1_o(ib_head1_predict_tag1_o),
        .ib_head1_predict_tag2_o(ib_head1_predict_tag2_o),
        .ib_head1_predict_tag3_o(ib_head1_predict_tag3_o),
        .ib_head1_predict_base_index_o(ib_head1_predict_base_index_o),
        .ib_head1_predict_fast_index_o(ib_head1_predict_fast_index_o),
        .ib_head1_ras_data_o(ib_head1_ras_data_o),
        .ib_head1_ras_ptr_o(ib_head1_ras_ptr_o),
        .ib_head1_ras_count_o(ib_head1_ras_count_o),
        .ib_count_o(ib_count_o)
    );
    always #5 clk_i = ~clk_i;
    task tick; begin @(posedge clk_i); #1; @(negedge clk_i); end endtask
    task reserve; begin reserve_valid_i=1;tick();reserve_valid_i=0;end endtask
    task payload;
        begin
            fetch_push0_pc_i=32'h80000060;fetch_push1_pc_i=32'h80000064;
            fetch_push0_instr_i=32'h00100513;fetch_push1_instr_i=32'h00200593;
            fetch_push0_predict_target_i=32'h80000100;
            fetch_push1_predict_target_i=32'h80000200;
            fetch_push0_predict_taken_i=1;fetch_push1_predict_taken_i=0;
            fetch_push0_ras_data_i=RAS_BITS'(32'h12345678);
            fetch_push1_ras_data_i=RAS_BITS'(32'h87654321);
            fetch_push_count_i=2;fetch_push_valid_i=1;
        end
    endtask
    initial begin
        clk_i='0;
        rst_n_i='0;
        fetch_push_valid_i='0;
        fetch_push_count_i='0;
        fetch_push0_pc_i='0;
        fetch_push0_instr_i='0;
        fetch_push0_error_i='0;
        fetch_push0_candidates_i='0;
        fetch_push0_predict_taken_i='0;
        fetch_push0_predict_target_i='0;
        fetch_push0_predict_token_i='0;
        fetch_push0_predict_provider_i='0;
        fetch_push0_predict_alternate_i='0;
        fetch_push0_predict_index0_i='0;
        fetch_push0_predict_index1_i='0;
        fetch_push0_predict_index2_i='0;
        fetch_push0_predict_index3_i='0;
        fetch_push0_predict_tag0_i='0;
        fetch_push0_predict_tag1_i='0;
        fetch_push0_predict_tag2_i='0;
        fetch_push0_predict_tag3_i='0;
        fetch_push0_predict_base_index_i='0;
        fetch_push0_predict_fast_index_i='0;
        fetch_push0_ras_data_i='0;
        fetch_push0_ras_ptr_i='0;
        fetch_push0_ras_count_i='0;
        fetch_push1_pc_i='0;
        fetch_push1_instr_i='0;
        fetch_push1_error_i='0;
        fetch_push1_candidates_i='0;
        fetch_push1_predict_taken_i='0;
        fetch_push1_predict_target_i='0;
        fetch_push1_predict_token_i='0;
        fetch_push1_predict_provider_i='0;
        fetch_push1_predict_alternate_i='0;
        fetch_push1_predict_index0_i='0;
        fetch_push1_predict_index1_i='0;
        fetch_push1_predict_index2_i='0;
        fetch_push1_predict_index3_i='0;
        fetch_push1_predict_tag0_i='0;
        fetch_push1_predict_tag1_i='0;
        fetch_push1_predict_tag2_i='0;
        fetch_push1_predict_tag3_i='0;
        fetch_push1_predict_base_index_i='0;
        fetch_push1_predict_fast_index_i='0;
        fetch_push1_ras_data_i='0;
        fetch_push1_ras_ptr_i='0;
        fetch_push1_ras_count_i='0;
        ib_remove_count_i='0;
        frontend_flush_i='0;
        reserve_valid_i='0;
        reserve_cancel_count_i='0;
        wb0_valid_i='0;
        wb0_rd_i='0;
        wb1_valid_i='0;
        wb1_rd_i='0;
        wb0_valid_copy_i='0;
        wb0_rd_copy_i='0;
        wb1_valid_copy_i='0;
        wb1_rd_copy_i='0;
        tick();rst_n_i=1;tick();
        reserve();payload();ib_remove_count_i=1;#1;
        if(!ib_head0_valid_o || ib_head0_pc_o!==32'h80000060 ||
           ib_head0_instr_o!==32'h00100513 || ib_head0_ras_data_o!==RAS_BITS'(32'h12345678))
            $fatal(1,"FAIL incoming head0");
        if(ISSUE_WIDTH==2 && (!ib_head1_valid_o || ib_head1_pc_o!==32'h80000064))
            $fatal(1,"FAIL incoming head1");
        tick();fetch_push_valid_i=0;ib_remove_count_i=0;#1;
        if(!ib_head0_valid_o || ib_count_o!=1 || ib_head0_pc_o!==32'h80000064 ||
           ib_head0_instr_o!==32'h00200593 || ib_head0_ras_data_o!==RAS_BITS'(32'h87654321))
            $fatal(1,"FAIL unconsumed incoming suffix");
        ib_remove_count_i=1;tick();ib_remove_count_i=0;
        if(ib_head0_valid_o || ib_credit_o!=CAPACITY) $fatal(1,"FAIL suffix drain credit");
        reserve();payload();ib_remove_count_i=2'(ISSUE_WIDTH);tick();
        fetch_push_valid_i=0;ib_remove_count_i=0;#1;
        if(ib_count_o!=4'(2-ISSUE_WIDTH)) $fatal(1,"FAIL consumed group count");
        if(ISSUE_WIDTH==1) begin ib_remove_count_i=1;tick();ib_remove_count_i=0;end
        if(ib_credit_o!=CAPACITY) $fatal(1,"FAIL consumed group credit");
        reserve();payload();tick();fetch_push_valid_i=0;#1;
        if(ib_count_o!=2 || ib_head0_pc_o!==32'h80000060)
            $fatal(1,"FAIL stalled incoming capture");
        frontend_flush_i=1;tick();frontend_flush_i=0;
        if(ib_head0_valid_o || ib_credit_o!=CAPACITY) $fatal(1,"FAIL flush");
        reserve();payload();fetch_push_count_i=1;ib_remove_count_i=1;tick();
        fetch_push_valid_i=0;ib_remove_count_i=0;
        if(ib_count_o!=0 || ib_credit_o!=CAPACITY) $fatal(1,"FAIL one-word group credit");
        frontend_flush_i=1;reserve_valid_i=1;tick();
        frontend_flush_i=0;reserve_valid_i=0;
        if(ib_credit_o!=CAPACITY-2) $fatal(1,"FAIL recovery reservation credit");
        payload();fetch_push_count_i=1;ib_remove_count_i=1;tick();
        fetch_push_valid_i=0;ib_remove_count_i=0;
        if(ib_count_o!=0 || ib_credit_o!=CAPACITY)
            $fatal(1,"FAIL recovery consumed group credit");
        $display("PASS CV08 IB incoming capture width=%0d",ISSUE_WIDTH);$finish;
    end
endmodule
